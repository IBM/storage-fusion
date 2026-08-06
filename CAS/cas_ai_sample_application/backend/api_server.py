#!/usr/bin/env python3
"""
FastAPI Server for CAS Assistant
Production-ready API with security, validation, and proper error handling
"""

import concurrent.futures
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse, Response, StreamingResponse
from pydantic import BaseModel, Field, field_validator
import uvicorn

from agents.cas_client import CASClient
from llm_service import LLMService
from utils.exceptions import ConfigurationError
from utils.query import split_query
from utils.validators import InputValidator, ValidationError

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=getattr(logging, os.getenv("LOG_LEVEL", "INFO")),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# Initialize FastAPI app
app = FastAPI(
    title="IBM Fusion CAS Assistant API",
    description="Production-ready API for Content Aware Storage LLM queries",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc"
)

# Security: Add trusted host middleware
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")
app.add_middleware(TrustedHostMiddleware, allowed_hosts=ALLOWED_HOSTS)

# CORS Configuration
CORS_ORIGINS = os.getenv("CORS_ORIGINS", "http://localhost:3000,http://localhost:3001").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
    max_age=3600
)

# Security: Add security headers middleware
@app.middleware("http")
async def add_security_headers(request: Request, call_next) -> Response:
    """Add security headers to all responses."""
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Content-Security-Policy"] = "default-src 'self'"
    return response


def _build_cas_client(api_key: str, cas_endpoint: str) -> CASClient:
    """Construct and configure a CASClient from the given credentials."""
    client = CASClient()
    client.configure(api_key=api_key, cas_endpoint=cas_endpoint)
    return client


_CAS_AUTH_ERROR_MESSAGES: Dict[int, str] = {
    422: "Invalid API key. Please check your CAS token and try again.",
    401: "Access denied. Your token may be incorrect.",
    403: "Access denied. Your CRAC (Credential and Role Access Control) may not be set up correctly. Please contact your administrator.",
    404: "Endpoint not found. Please check that your endpoint URL is correct.",
    503: "Could not reach the endpoint. Please check that your endpoint URL is correct.",
    500: "CAS server error. Your namespace may not be properly configured. Please contact your administrator.",
}


def _cas_auth_error_message(result: Dict[str, Any]) -> str:
    """Return a user-facing error message for a failed CAS auth result."""
    http_status = result.get("http_status")
    return _CAS_AUTH_ERROR_MESSAGES.get(http_status, result.get("error", "Authentication failed"))


# ---------------------------------------------------------------------------
# Pydantic Models for Request/Response Validation
# ---------------------------------------------------------------------------
class CASCredentialsBase(BaseModel):
    """Shared CAS credentials and their validators — inherited by any request that talks to CAS."""
    cas_api_key: str = Field(..., min_length=10, max_length=500, description="CAS API token")
    cas_endpoint: str = Field(..., min_length=10, max_length=500, description="CAS endpoint URL")

    @field_validator('cas_api_key', mode='before')
    @classmethod
    def validate_token(cls, v):
        try:
            return InputValidator.validate_token(v)
        except ValidationError as exc:
            raise ValueError(str(exc)) from exc

    @field_validator('cas_endpoint', mode='before')
    @classmethod
    def validate_endpoint(cls, v):
        try:
            return InputValidator.validate_endpoint_url(v)
        except ValidationError as exc:
            raise ValueError(str(exc)) from exc


class AuthValidationResponse(BaseModel):
    """Authentication validation response"""
    valid: bool = Field(..., description="Whether authentication is valid")
    message: str = Field(..., description="Validation message")
    vector_stores: Optional[List[Dict[str, Any]]] = Field(None, description="Available vector stores")


class QueryRequest(CASCredentialsBase):
    """Query request for the RAG pipeline — includes CAS credentials and search parameters."""
    query: str = Field(..., min_length=1, max_length=8000, description="User query")
    max_results: Optional[int] = Field(10, ge=1, le=50, description="Maximum results to retrieve")
    min_score: Optional[float] = Field(0.3, ge=0.0, le=1.0, description="Minimum relevance score")
    vector_store_id: Optional[str] = Field(None, max_length=200, description="Vector store ID to query")

    @field_validator('query', mode='before')
    @classmethod
    def validate_query(cls, v):
        """Sanitize query — strip HTML/script tags."""
        try:
            return InputValidator.validate_query(v)
        except ValidationError as exc:
            raise ValueError(str(exc)) from exc


# Exception Handlers
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Handle HTTP exceptions"""
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.detail,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle general exceptions"""
    logger.error("Unhandled exception: %s", exc, exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": "Internal server error",
            "detail": str(exc) if os.getenv("DEBUG", "false").lower() == "true" else None,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    )


# API Endpoints
@app.get("/", response_model=Dict[str, str])
async def root() -> Dict[str, str]:
    """Root endpoint — minimal liveness check used by documentation links."""
    return {
        "message": "IBM Fusion CAS Assistant API",
        "version": "1.0.0",
        "docs": "/api/docs",
    }


@app.get("/health", response_model=Dict[str, Any])
async def health() -> Dict[str, Any]:
    """Health check endpoint for Kubernetes liveness and readiness probes."""
    return {
        "status": "ok",
        "version": "1.0.0",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/api/auth/validate", response_model=AuthValidationResponse)
async def validate_authentication(auth_request: CASCredentialsBase):
    """
    Validate CAS authentication credentials
    
    This endpoint tests if the provided CAS token and endpoint are valid
    by attempting to retrieve vector stores from the CAS API.
    """
    try:
        temp_agent = _build_cas_client(auth_request.cas_api_key, auth_request.cas_endpoint)

        result = temp_agent.list_vector_stores()

        if result.get("status") == "success":
            vector_stores = result.get("vector_stores", [])
            return AuthValidationResponse(
                valid=True,
                message="Authentication successful",
                vector_stores=vector_stores
            )
        else:
            return AuthValidationResponse(
                valid=False,
                message=_cas_auth_error_message(result),
                vector_stores=None
            )
    
    except ConfigurationError as e:
        logger.error("auth_validate configuration_error=%r", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Server configuration error: {str(e)}",
        )
    except Exception as e:
        logger.debug("auth_validate error=%r", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Validation error: {str(e)}",
        )


@app.get("/api/llm/check")
async def check_llm_compatibility():
    """Check whether the configured LLM model passes the structured-output format probe.

    Returns compatible=True if the model reliably emits FULL_ANSWER: / [SOURCE: N].
    Returns compatible=False with a reason if it does not — callers should surface
    this as a non-blocking warning to the user.
    """
    try:
        llm = LLMService()
    except ConfigurationError as exc:
        return {"compatible": False, "model": "", "reason": str(exc)}
    return llm.check_model_compatibility()


@app.post("/api/query/stream")
async def query_llm_stream(request: QueryRequest):
    """Streaming LLM query — streams tokens as the LLM generates them."""
    logger.debug("stream_query cas_endpoint=%s query_len=%d", request.cas_endpoint, len(request.query))

    temp_agent = _build_cas_client(request.cas_api_key, request.cas_endpoint)
    if not temp_agent.is_configured():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid CAS configuration")

    try:
        temp_llm = LLMService(temp_agent)
    except ConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"LLM backend is not configured: {exc}",
        )
    if request.vector_store_id:
        temp_llm.vector_store_id = request.vector_store_id

    def generate():
        queries = split_query(request.query)
        total = len(queries)
        max_r = request.max_results or temp_llm.default_max_results
        min_score = request.min_score if request.min_score is not None else temp_llm.default_min_score

        vector_store_id = temp_llm.vector_store_id or temp_llm._get_vector_store_id()
        if isinstance(vector_store_id, dict):
            logger.warning("stream_query could not resolve vector store: %s", vector_store_id.get("error"))
            yield "[ERROR: Could not resolve vector store]\n"
            return

        def _fetch_cas(args):
            idx, q = args
            return (idx, q, temp_llm.cas_client.search_vector_store(
                vector_store_id=vector_store_id,
                query=q,
                max_num_results=max_r * 2,
                min_score=min_score,
            ))

        with concurrent.futures.ThreadPoolExecutor(max_workers=total) as executor:
            futures = [executor.submit(_fetch_cas, (idx, q)) for idx, q in enumerate(queries, 1)]
            cas_results = sorted([f.result() for f in concurrent.futures.as_completed(futures)], key=lambda x: x[0])

        yield "[THINKING]"

        for idx, q, retrieval_result in cas_results:
            yield f"**Question {idx}: {q}**\n\n"

            if retrieval_result.get("status") != "success":
                logger.warning("stream_query retrieval_failed q=%d error=%r", idx, retrieval_result.get("error"))
                yield "I could not connect to CAS to retrieve documents. Check that your CAS endpoint is reachable and your token has not expired.\n"
                if total > 1 and idx < total:
                    yield "\n\n---\n\n"
                continue

            raw_data = retrieval_result.get("data", [])
            chunks = temp_llm._extract_chunks(raw_data)

            if not chunks:
                if raw_data:
                    logger.warning("stream_query chunks_filtered q=%d raw=%d min_score=%.2f", idx, len(raw_data), min_score)
                    yield (
                        f"Found {len(raw_data)} result(s) but none met the confidence threshold. "
                        f"Try lowering `RAG_MIN_SCORE` (currently `{min_score}`) or rephrasing the question."
                    )
                else:
                    logger.warning("stream_query no_chunks q=%d", idx)
                    yield "No relevant documents were found for this question. Try rephrasing your query, or check that the correct vector store is selected."
                if total > 1 and idx < total:
                    yield "\n\n---\n\n"
                continue

            prompt = temp_llm._build_prompt(q, chunks)
            full_response = ""
            for token in temp_llm._call_llm_stream(prompt):
                full_response += token
                yield token

            structured = temp_llm._parse_structured_answer(full_response)
            src_num = structured.get("source_number")
            source_name = next(
                (c["source"] for c in chunks if c["index"] == src_num),
                None,
            )
            if source_name:
                yield f"\n[SOURCE]{json.dumps({'source_name': source_name})}"

            if total > 1 and idx < total:
                yield "\n\n---\n\n"

        yield f"\n[DONE]{json.dumps({'model': temp_llm.llm_model, 'multi_query': total > 1})}"

    return StreamingResponse(generate(), media_type="text/plain")


# Run server
if __name__ == "__main__":
    port = int(os.getenv("API_PORT", 8000))
    host = os.getenv("API_HOST", "0.0.0.0")
    debug = os.getenv("DEBUG", "false").lower() == "true"
    uvicorn.run(
        "api_server:app",
        host=host,
        port=port,
        reload=debug,
        reload_includes=["*.env"] if debug else None,
        log_level=os.getenv("LOG_LEVEL", "info").lower()
    )