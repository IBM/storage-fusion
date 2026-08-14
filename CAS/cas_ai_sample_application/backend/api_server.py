#!/usr/bin/env python3
"""
FastAPI Server for CAS Assistant
Production-ready API with security, validation, and proper error handling
"""

import asyncio
import json
import logging
import os
import re
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Sequence

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse, Response, StreamingResponse
from pydantic import BaseModel, Field, field_validator
import uvicorn

from agents.cas_client import CASClient
from llm_service import LLMService
from session_store import SessionStore, Turn
from utils.exceptions import ConfigurationError
from utils.prompt_builder import NO_DOCS_ANSWER
from utils.query import _NAMED_ENTITY, split_query
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
# SESSION_ENABLED=false disables all in-memory session/history logic.
# Every request is treated as a fresh conversation — no context is carried
# between turns, no sessions are created or stored, and the background sweep
# task never starts.  Safe for stateless / multi-replica deployments and
# useful during development when you don't want history rewriting queries.
#
# To RE-ENABLE sessions, either remove this line or set SESSION_ENABLED=true.
# Use a mutable container so the toggle endpoint can flip it at runtime
# without needing a module-level `global` statement in every function.
_session_state: Dict[str, bool] = {
    "enabled": os.getenv("SESSION_ENABLED", "true").lower() not in ("false", "0", "no")
}


def SESSION_ENABLED() -> bool:  # type: ignore[override]
    """Return whether session handling is currently active."""
    return _session_state["enabled"]

SESSION_TTL_SECONDS = int(os.getenv("SESSION_TTL_SECONDS", "3600"))
SESSION_SWEEP_INTERVAL_SECONDS = int(os.getenv("SESSION_SWEEP_INTERVAL_SECONDS", "300"))
session_store = SessionStore(ttl_seconds=SESSION_TTL_SECONDS)


def _apply_compaction(llm: LLMService, session_id: str, session) -> None:
    """Run compaction for *session* if it's over budget and persist the result.

    LLMService only computes the compaction plan (summary + turns to keep);
    applying it goes through SessionStore.set_summary() so the mutation is
    protected by the store's lock, same as every other session write.
    """
    if session is None:
        return
    plan = llm._compact_history(session)
    if plan is not None:
        session_store.set_summary(session_id, plan["summary"], plan["turns_to_keep"])
        logger.debug(
            "session_compacted id=%s kept_turns=%d",
            session_id, len(plan["turns_to_keep"]),
        )


async def _sweep_expired_sessions_loop() -> None:
    """Background loop: periodically evict sessions past their TTL.

    Runs for the lifetime of the process. sweep_expired() itself is cheap
    (one dict scan under the lock) so a 5-minute default interval is plenty
    fine-grained relative to the 1-hour default TTL.
    """
    while True:
        await asyncio.sleep(SESSION_SWEEP_INTERVAL_SECONDS)
        try:
            session_store.sweep_expired()
        except Exception as exc:
            logger.warning("session_sweep_error error=%r", exc)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/shutdown hooks, replacing the deprecated @app.on_event API.

    Startup: launch the background TTL sweep for expired sessions (only when
    SESSION_ENABLED=true).
    Shutdown: cancel it cleanly so process exit isn't left waiting on it.
    """
    if SESSION_ENABLED():
        sweep_task = asyncio.create_task(_sweep_expired_sessions_loop())
    else:
        logger.info("session_disabled — history, compaction, and TTL sweep are all off")
        sweep_task = None
    try:
        yield
    finally:
        if sweep_task is not None:
            sweep_task.cancel()
            try:
                await sweep_task
            except asyncio.CancelledError:
                pass


app = FastAPI(
    title="IBM Fusion CAS Assistant API",
    description="Production-ready API for Content Aware Storage LLM queries",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    lifespan=lifespan,
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
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
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


def _is_meta_history_question(query: str) -> bool:
    """Return True when the user is asking about the conversation itself."""
    lowered = query.lower()
    patterns = (
        r"\bour history\b",
        r"\bwhat is our history\b",
        r"\bwhat are all the questions\b",
        r"\bwhat have i asked\b",
        r"\bwhat did i ask\b",
        r"\bsummar(?:ize|ise) (?:our|this) conversation\b",
        r"\bconversation history\b",
        r"\bwhat questions have i\b",
        r"\bshow (?:me )?(?:our|the) conversation\b",
        r"\bwhat did we discuss\b",
        r"\bwhat have we (?:talked|discussed|covered)\b",
        r"\brecap (?:our|this|the) (?:chat|conversation|session)\b",
    )
    return any(re.search(pattern, lowered) for pattern in patterns)



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
    session_id: Optional[str] = Field(None, description="Existing session id, if continuing a conversation")

    @field_validator('query', mode='before')
    @classmethod
    def validate_query(cls, v):
        """Sanitize query — strip HTML/script tags."""
        try:
            return InputValidator.validate_query(v)
        except ValidationError as exc:
            raise ValueError(str(exc)) from exc

    @field_validator('session_id', mode='before')
    @classmethod
    def validate_session_id_field(cls, v):
        if v is None:
            return v
        try:
            return InputValidator.validate_session_id(v)
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
                message=result.get("error", "Authentication failed"),
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


@app.get("/api/session/status")
async def get_session_status():
    """Return whether session/history handling is currently enabled."""
    return {"enabled": SESSION_ENABLED()}


@app.post("/api/session/toggle")
async def toggle_session():
    """Flip session handling on or off at runtime — no restart required.

    Returns the new state after the toggle.
    """
    _session_state["enabled"] = not _session_state["enabled"]
    new_state = _session_state["enabled"]
    logger.info("session_toggled enabled=%s", new_state)
    return {"enabled": new_state}


@app.delete("/api/session/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(session_id: str):
    """Delete a session immediately — called by the frontend on 'New Chat'.

    No-op when SESSION_ENABLED=false (nothing was ever stored).
    """
    if not SESSION_ENABLED():
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    try:
        InputValidator.validate_session_id(session_id)
    except ValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    session_store.delete(session_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


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

    # --- Session setup (skipped entirely when SESSION_ENABLED=false) ----------
    session = None
    active_session_id: Optional[str] = None
    if SESSION_ENABLED():
        if request.session_id:
            session = session_store.get(request.session_id)
            active_session_id = request.session_id
        if session is None:
            active_session_id = session_store.create()
            session = session_store.get(active_session_id)
    # --------------------------------------------------------------------------

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

        yield "[THINKING]"

        for idx, q in enumerate(queries, 1):
            yield f"**{q}**\n\n"

            current_history_block = temp_llm._build_history_block(session)

            if _is_meta_history_question(q):
                if current_history_block:
                    meta_prompt = (
                        f"{current_history_block}\n\n"
                        f'The user now asks: "{q}"\n\n'
                        "Answer using only the conversation history above. "
                        "If the user asks for all prior questions, list the user questions in order. "
                        "Do not use document sources."
                    )
                    clean_answer = temp_llm._ask_llm(meta_prompt)
                    if clean_answer.startswith("[LLM_"):
                        yield clean_answer
                        return
                    if not clean_answer:
                        clean_answer = "I couldn't retrieve the conversation history right now."
                else:
                    clean_answer = "There is no conversation history yet."

                yield clean_answer
                if SESSION_ENABLED():
                    session_store.add_turn(
                        active_session_id,
                        Turn(query=q, answer=clean_answer, sources=["[meta]"]),
                    )
                    _apply_compaction(temp_llm, active_session_id, session)
                if total > 1 and idx < total:
                    yield "\n\n---\n\n"
                continue

            # Pass the frozen history block to _resolve_query rather than the
            # live session so that add_turn calls from earlier iterations in
            # this same generate() loop do not shift the rewrite context.
            resolved_query = temp_llm._resolve_query_from_block(q, current_history_block)
            logger.debug(
                "turn_start idx=%d original=%r resolved=%r",
                idx, q, resolved_query,
            )

            # Persist the subject from the ORIGINAL question (q), not the
            # filler-stripped resolved_query. After stripping "What about"
            # from "What about Tennessee — how many cases?", the result starts
            # with "Tennessee" — making it the FIRST word, which _NAMED_ENTITY
            # (non-first-word pattern) would miss. Using q preserves "What
            # about Tennessee…" where "Tennessee" is still a non-first word.
            # Bare fragments ("Organizations?") and pronoun follow-ups have no
            # capitalised non-first word in q either, so they still pass through.
            if SESSION_ENABLED() and _NAMED_ENTITY.search(q):
                resolved_subject = temp_llm._extract_subject_from_text(q)
                if resolved_subject:
                    session_store.set_active_subject(active_session_id, resolved_subject)

            loop_result = temp_llm._run_retrieval_loop(
                query=resolved_query,
                vector_store_id=vector_store_id,
                max_results=max_r,
                min_score=min_score,
                history_block=current_history_block,
            )

            chunks = loop_result["chunks"]
            if not chunks:
                yield NO_DOCS_ANSWER
                if total > 1 and idx < total:
                    yield "\n\n---\n\n"
                continue

            if loop_result.get("final_prompt") is None and "answer_text" in loop_result:
                # answer_text may contain internal verification reasoning before
                # FULL_ANSWER: — parse it first, then yield only the clean answer.
                full_response = loop_result["answer_text"]
                if full_response.startswith("[LLM_"):
                    yield full_response
                    return
                structured = temp_llm._parse_structured_answer(full_response)
                yield structured.get("answer", full_response)
            else:
                full_response = ""
                for token in temp_llm._call_llm(loop_result["final_prompt"]):
                    full_response += token
                    yield token
                    if full_response.startswith("[LLM_"):
                        return
                structured = temp_llm._parse_structured_answer(full_response)
            src_num = structured.get("source_number")
            source_name = next(
                (c["source"] for c in chunks if c["index"] == src_num),
                None,
            )
            if source_name is None and len(chunks) == 1:
                source_name = chunks[0]["source"]
            clean_answer = structured.get("answer", full_response)
            logger.debug(
                "turn_end idx=%d chunks=%d cited_src_num=%r cited_source=%r answer_prefix=%r",
                idx,
                len(chunks),
                src_num,
                source_name,
                clean_answer[:80] if clean_answer else "",
            )
            if source_name:
                yield f"\n[SOURCE]{json.dumps({'source_name': source_name})}"

            if total > 1 and idx < total:
                yield "\n\n---\n\n"

            if SESSION_ENABLED():
                # Strip any leaked FULL_ANSWER: prefix so the history block
                # stays clean regardless of model format compliance.
                stored_answer = re.sub(
                    r'^FULL_ANSWER:\s*', '', clean_answer, flags=re.IGNORECASE
                ).strip()
                session_store.add_turn(
                    active_session_id,
                    Turn(
                        query=q,
                        answer=stored_answer,
                        sources=[source_name] if source_name else [],
                    ),
                )
                _apply_compaction(temp_llm, active_session_id, session)

        yield f"\n[DONE]{json.dumps({'model': temp_llm.llm_model, 'multi_query': total > 1, 'session_id': active_session_id})}"

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