"""
FastAPI backend for Agentic Chat Assistant
Replaces the Streamlit chat_app.py — wraps the same src/ layer (RAGFlowEnhanced,
CASClient, ModelGatewayClient) behind clean HTTP endpoints consumed by the React UI.

Also embeds the CPU multi-model router (ported from multi-model-cpu-chat-app/app/router.py).
CPU models are deployed in namespace "deploy-models-cpu" on the local cluster and
are accessed via MODEL_URL_CHAT / MODEL_URL_CODE / MODEL_URL_SUMMARIZE env vars.

Unified model registry (v2):
  GET /api/models  returns all models (gateway + CPU) as ModelInfo objects.
  POST /api/chat   is the single chat endpoint for all runtimes — the backend
                   routes internally to either the Model Gateway (RAGFlowEnhanced)
                   or a KServe CPU predictor depending on the selected model.
  The legacy /api/cpu/* endpoints are kept for backward compatibility.
"""

import logging
import os
import sys
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

import httpx
import requests as _requests
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Path setup — identical to chat_app.py so the same src/ imports resolve
# ---------------------------------------------------------------------------
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
load_dotenv(project_root / ".env", override=False)

from src.cas_client import CASClient  # noqa: E402
from src.model_gateway_client import ModelGatewayClient, ModelGatewayConfig  # noqa: E402
from src.rag_flow import RAGFlowEnhanced  # noqa: E402

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(name)s  %(levelname)s  %(message)s",
)
logger = logging.getLogger("backend")

# ---------------------------------------------------------------------------
# Default prompt template — identical to chat_app.py DEFAULT_PROMPT_TEMPLATE
# ---------------------------------------------------------------------------
DEFAULT_PROMPT_TEMPLATE = """You are an enterprise knowledge assistant. Use the following context to answer the user's question accurately and cite your sources.

Context:
{context}

Question: {query}

Instructions:
- Answer based on the provided context
- If the context contains the answer, cite the specific source and line numbers
- If the context doesn't contain enough information, clearly state that
- Be precise and professional

Answer:"""

# ---------------------------------------------------------------------------
# CPU multi-model router — classification signals (ported from router.py)
# ---------------------------------------------------------------------------
_SUMMARIZE_SIGNALS = {
    "summarize", "summarise", "summary", "tldr", "tl;dr",
    "shorten", "condense", "brief", "overview", "abstract",
    "key points", "main points", "in short", "in brief",
}

_CODE_SIGNALS = {
    "code", "function", "implement", "debug", "class ", "def ",
    "import ", "script", "python", "java", "javascript", "typescript",
    "bash", "shell", "sql", "algorithm", "refactor", "compile",
    "error", "exception", "traceback", "snippet", "syntax",
}

_SUMMARIZE_SYSTEM_PROMPT = (
    "You are a concise summarization assistant. "
    "Produce a clear, bullet-pointed summary of the provided text. "
    "Focus only on key facts and main ideas. "
    "Do not add opinions or information not present in the original text."
)

CPU_TASKS = ("chat", "code", "summarize")
CPU_INFERENCE_TIMEOUT = float(os.getenv("INFERENCE_TIMEOUT_S", "300"))

# Capabilities assigned to gateway models — they are general-purpose
GATEWAY_CAPABILITIES = ["chat", "code", "summarize", "rag"]


def _classify_task(prompt: str) -> str:
    """Classify a prompt into chat / code / summarize."""
    low = prompt.lower()
    if any(s in low for s in _SUMMARIZE_SIGNALS):
        return "summarize"
    if any(s in low for s in _CODE_SIGNALS):
        return "code"
    return "chat"


def _cpu_model_cfg(task: str) -> dict:
    """
    Return the URL, model ID, bearer token and capabilities for the given task.
    All are read from env vars injected by the Helm chart:
      MODEL_URL_<TASK>    — KServe predictor Service URL
      MODEL_ID_<TASK>     — vLLM model ID string
      MODEL_TOKEN_<TASK>  — bearer token (from secretKeyRef)
      MODEL_CAPS_<TASK>   — comma-separated capability string (defaults to task name)
    Returns an empty dict if the env vars are not configured.
    """
    t = task.upper()
    url = os.getenv(f"MODEL_URL_{t}", "")
    model_id = os.getenv(f"MODEL_ID_{t}", "")
    token = os.getenv(f"MODEL_TOKEN_{t}", "")
    caps_raw = os.getenv(f"MODEL_CAPS_{t}", task.lower())
    capabilities = [c.strip() for c in caps_raw.split(",") if c.strip()]
    if not (url and model_id):
        return {}
    return {"url": url, "id": model_id, "token": token, "capabilities": capabilities}


def _cpu_models_available() -> bool:
    """True if at least the CHAT model URL and ID are set."""
    return bool(os.getenv("MODEL_URL_CHAT") and os.getenv("MODEL_ID_CHAT"))


# ---------------------------------------------------------------------------
# Unified model registry
# ---------------------------------------------------------------------------
@dataclass
class ModelDescriptor:
    """
    Internal representation of a model — not sent to the frontend as-is.
    Routing decisions (gateway vs cpu) are made from this object on the backend.

    Selection priority for Auto Detect:
      1. Capability-specific CPU model (exact capability match, runtime='cpu')
      2. General-purpose gateway model that supports the required capability
      3. Any other model that supports the required capability
      4. Default model (CAS+ / first gateway model) as final fallback
    """
    id: str                          # unique display name shown in the UI dropdown
    capabilities: List[str]          # e.g. ["chat","code","summarize","rag"]
    runtime: str                     # "gateway" | "cpu"  — internal only
    endpoint_url: str                # resolved at startup
    token: str = ""                  # bearer token (CPU models); gateway uses shared key
    is_default: bool = False         # True for the CAS+ / configured default model


def _build_model_registry() -> List[ModelDescriptor]:
    """
    Build the unified model registry at startup.
    Order: gateway models first (default at front), then CPU models.

    Gateway models get GATEWAY_CAPABILITIES = ["chat","code","summarize","rag"].
    CPU model capabilities come from MODEL_CAPS_<TASK> env vars.
    """
    registry: List[ModelDescriptor] = []

    # ── Gateway models ────────────────────────────────────────────────────
    gw_endpoint = _env("MODEL_GATEWAY_ENDPOINT")
    gw_api_key = _env("MODEL_GATEWAY_API_KEY")
    default_model_name = _env("MODEL_NAME", "qwen2-5-72b-instruct")

    if gw_endpoint and gw_api_key:
        try:
            url = gw_endpoint.rstrip("/") + "/v1/models"
            headers = {"Authorization": f"Bearer {gw_api_key}"}
            resp = _requests.get(url, headers=headers, timeout=10, verify=_ca_bundle())
            resp.raise_for_status()
            gateway_ids = [m["id"] for m in resp.json().get("data", []) if "id" in m]
            logger.info(f"Loaded {len(gateway_ids)} gateway model(s)")
        except Exception as exc:
            logger.error(f"Failed to load gateway models: {exc}")
            gateway_ids = [default_model_name] if default_model_name else []

        for gid in gateway_ids:
            registry.append(ModelDescriptor(
                id=gid,
                capabilities=GATEWAY_CAPABILITIES,
                runtime="gateway",
                endpoint_url=gw_endpoint,
                token=gw_api_key,
                is_default=(gid == default_model_name),
            ))

        # Ensure the configured default is marked even if not in the live list
        if not any(m.is_default for m in registry) and default_model_name:
            if not any(m.id == default_model_name for m in registry):
                registry.insert(0, ModelDescriptor(
                    id=default_model_name,
                    capabilities=GATEWAY_CAPABILITIES,
                    runtime="gateway",
                    endpoint_url=gw_endpoint,
                    token=gw_api_key,
                    is_default=True,
                ))
            else:
                for m in registry:
                    if m.id == default_model_name:
                        m.is_default = True
                        break

    # ── CPU models ────────────────────────────────────────────────────────
    for task in CPU_TASKS:
        cfg = _cpu_model_cfg(task)
        if not cfg:
            continue
        registry.append(ModelDescriptor(
            id=cfg["id"],
            capabilities=cfg["capabilities"],
            runtime="cpu",
            endpoint_url=cfg["url"],
            token=cfg["token"],
            is_default=False,
        ))
        logger.info(f"Registered CPU model: {cfg['id']} caps={cfg['capabilities']}")

    # If no default was set (e.g. no gateway), mark first entry as default
    if registry and not any(m.is_default for m in registry):
        registry[0].is_default = True

    logger.info(f"Model registry built: {[m.id for m in registry]}")
    return registry


def _select_model_for_task(
    task: str,
    registry: List[ModelDescriptor],
) -> Optional[ModelDescriptor]:
    """
    Auto Detect model selection.

    Priority (documented as per the spec):
      1. CPU model whose capabilities include the required task (exact specialized match)
      2. Gateway model whose capabilities include the required task (general-purpose)
      3. Any other model whose capabilities include the required task
      4. The default model regardless of capability (final fallback — CAS+ is general-purpose)
    """
    cpu_match = next(
        (m for m in registry if m.runtime == "cpu" and task in m.capabilities), None
    )
    if cpu_match:
        return cpu_match

    gateway_match = next(
        (m for m in registry if m.runtime == "gateway" and task in m.capabilities), None
    )
    if gateway_match:
        return gateway_match

    any_match = next((m for m in registry if task in m.capabilities), None)
    if any_match:
        return any_match

    # Final fallback: default model
    return next((m for m in registry if m.is_default), registry[0] if registry else None)


def _get_descriptor(model_id: str, registry: List[ModelDescriptor]) -> Optional[ModelDescriptor]:
    """Look up a model by ID in the registry."""
    return next((m for m in registry if m.id == model_id), None)


# ---------------------------------------------------------------------------
# Application state — built once at startup, reused across all requests
# ---------------------------------------------------------------------------
class _State:
    rag_flow: Optional[RAGFlowEnhanced] = None
    cas_client: Optional[CASClient] = None
    model_gateway_client: Optional[ModelGatewayClient] = None
    vector_stores: List[dict] = []
    models: List[str] = []          # kept for legacy /api/models raw list fallback
    model_registry: List[ModelDescriptor] = []
    ready: bool = False


state = _State()

# ---------------------------------------------------------------------------
# SSL helpers
# ---------------------------------------------------------------------------
# OpenShift mounts the cluster CA here — covers resources signed by the
# cluster's own CA.  Routes using the ingress operator (self-signed) need
# MODEL_GATEWAY_VERIFY_SSL=false to skip verification for those endpoints.
_OPENSHIFT_CA = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"


def _ca_bundle() -> str | bool:
    """
    Returns the SSL verification setting for the Model Gateway:
    - If MODEL_GATEWAY_VERIFY_SSL=false  → skip verification (self-signed Route)
    - If cluster CA exists               → use it
    - Otherwise                          → use system/certifi bundle
    """
    verify_env = os.getenv("MODEL_GATEWAY_VERIFY_SSL", "").lower()
    if verify_env in ("false", "0", "no"):
        return False
    if os.path.exists(_OPENSHIFT_CA):
        return _OPENSHIFT_CA
    return True


def _env(key: str, default: str = "") -> str:
    return os.getenv(key, default).strip()


def _bool_env(key: str, default: bool = False) -> bool:
    val = os.getenv(key, "")
    if not val:
        return default
    return val.lower() in ("true", "1", "yes")


def _int_env(key: str, default: int = 5) -> int:
    val = os.getenv(key, "")
    try:
        return int(val) if val else default
    except ValueError:
        return default


# ---------------------------------------------------------------------------
# Startup / shutdown
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Build every heavyweight object once at startup.
    Mirrors the auto-connect block in chat_app.py (lines 689-734).
    """
    cas_endpoint = _env("CAS_ENDPOINT")
    cas_api_key = _env("CAS_API_KEY")
    cas_vector_store_id = _env("CAS_VECTOR_STORE_ID")
    cas_use_mcp = _bool_env("CAS_USE_MCP", default=False)

    gw_endpoint = _env("MODEL_GATEWAY_ENDPOINT")
    gw_api_key = _env("MODEL_GATEWAY_API_KEY")
    model_name = _env("MODEL_NAME", "qwen2-5-72b-instruct")
    top_k = _int_env("DEFAULT_TOP_K", 5)

    # ── Build unified model registry ──────────────────────────────────────
    state.model_registry = _build_model_registry()
    state.models = [m.id for m in state.model_registry if m.runtime == "gateway"]

    if not (cas_endpoint and gw_endpoint and gw_api_key):
        logger.warning(
            "CAS_ENDPOINT / MODEL_GATEWAY_ENDPOINT / MODEL_GATEWAY_API_KEY not all set — "
            "service will start but /api/chat (RAG path) will fail until env vars are provided."
        )
        yield
        return

    # ── CAS client (for vector-store listing) ──────────────────────────────
    try:
        state.cas_client = CASClient(
            endpoint=cas_endpoint,
            api_key=cas_api_key,
            use_mcp=cas_use_mcp,
        )
        raw_stores = state.cas_client.list_vector_stores(limit=50)
        state.vector_stores = raw_stores
        logger.info(f"Loaded {len(raw_stores)} vector store(s) from CAS")
    except Exception as exc:
        logger.error(f"Failed to load vector stores: {exc}")

    # ── Resolve startup defaults ──────────────────────────────────────────
    store_ids = [
        s.get("id", s.get("vector_store_id", "")) for s in state.vector_stores
    ]
    default_store = (
        cas_vector_store_id
        if (cas_vector_store_id and cas_vector_store_id in store_ids)
        else (store_ids[0] if store_ids else None)
    )
    default_model = model_name if model_name else (state.models[0] if state.models else model_name)

    # ── RAGFlowEnhanced — built once, reused for every gateway chat request ─
    try:
        state.rag_flow = RAGFlowEnhanced(
            cas_endpoint=cas_endpoint,
            llm_endpoint=gw_endpoint,
            prompt_template=DEFAULT_PROMPT_TEMPLATE,
            top_k=top_k,
            use_mcp=cas_use_mcp,
            cas_api_key=cas_api_key,
            vector_store_id=default_store,
            enable_detailed_attribution=True,
            max_retries=3,
            timeout=60,
            use_model_gateway=True,
            model_gateway_api_key=gw_api_key,
            model_name=default_model,
        )
        state.ready = True
        logger.info("RAGFlowEnhanced initialised — service ready")
    except Exception as exc:
        logger.error(f"Failed to initialise RAGFlowEnhanced: {exc}")

    yield  # ← application runs here

    # Shutdown (nothing async to clean up)
    logger.info("Backend shutting down")


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Agentic Chat Assistant API",
    version="2.0.0",
    lifespan=lifespan,
)

# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

# ── Unified model info (returned by GET /api/models) ─────────────────────
class ModelInfo(BaseModel):
    id: str
    capabilities: List[str]     # e.g. ["chat","code","summarize","rag"]
    default: bool = False


# ── Unified chat request / response ──────────────────────────────────────
class UnifiedHistoryMessage(BaseModel):
    role: str       # "user" or "assistant"
    content: str


class UnifiedChatRequest(BaseModel):
    query: str
    vector_store_id: str = ""
    model_id: str = ""              # explicit model selection; empty = use default
    auto_detect: bool = False       # True → backend selects model from capabilities
    max_tokens: int = 512
    temperature: float = 0.7
    history: List[UnifiedHistoryMessage] = []


class SourceAttribution(BaseModel):
    source_file: str
    document_id: str
    relevance_score: float
    content_snippet: str
    line_start: Optional[int] = None
    line_end: Optional[int] = None
    metadata: dict = {}


class ResponseMetrics(BaseModel):
    processing_time: float
    sources_count: int
    cas_search_count: int


class UnifiedChatResponse(BaseModel):
    response: str
    model_id: str                       # which model actually answered
    sources: List[SourceAttribution] = []
    metrics: Optional[ResponseMetrics] = None   # set when RAG/CAS was used
    usage: Optional[dict] = None        # set when a CPU model was used


# ── Legacy RAG chat models (unchanged — kept for backward compatibility) ──
class ChatRequest(BaseModel):
    query: str
    vector_store_id: str = ""
    model_name: str = ""


class ChatResponse(BaseModel):
    response: str
    sources: List[SourceAttribution]
    metrics: ResponseMetrics


class VectorStore(BaseModel):
    id: str
    name: str


class ConfigResponse(BaseModel):
    cas_endpoint: str
    model_gateway_endpoint: str
    model_name: str
    cas_vector_store_id: str


# ── Legacy CPU multi-model models (unchanged) ─────────────────────────────
class CpuHistoryMessage(BaseModel):
    role: str        # "user" or "assistant"
    content: str


class CpuChatRequest(BaseModel):
    prompt: str
    task: Optional[str] = None   # "chat" | "code" | "summarize" | null → auto-detect
    max_tokens: int = 512
    temperature: float = 0.7
    system_prompt: Optional[str] = None
    history: List[CpuHistoryMessage] = []


class CpuChatResponse(BaseModel):
    task: str
    model: str
    content: str
    usage: Optional[dict] = None


class CpuTaskInfo(BaseModel):
    id: str
    available: bool


# ---------------------------------------------------------------------------
# API routes
# ---------------------------------------------------------------------------

# ── Liveness / readiness ─────────────────────────────────────────────────
@app.get("/healthz")
def health():
    """Liveness / readiness probe."""
    return {"status": "ok", "ready": state.ready}


@app.get("/api/config", response_model=ConfigResponse)
def get_config():
    """
    Returns non-secret configuration so the React UI can display
    what endpoints are active. Never returns API keys.
    """
    return ConfigResponse(
        cas_endpoint=_env("CAS_ENDPOINT"),
        model_gateway_endpoint=_env("MODEL_GATEWAY_ENDPOINT"),
        model_name=_env("MODEL_NAME", "qwen2-5-72b-instruct"),
        cas_vector_store_id=_env("CAS_VECTOR_STORE_ID"),
    )


@app.get("/api/vector-stores", response_model=List[VectorStore])
def list_vector_stores():
    """Returns the vector stores fetched at startup."""
    result = []
    for s in state.vector_stores:
        vid = s.get("id") or s.get("vector_store_id") or ""
        vname = s.get("name") or vid or "Unknown"
        if vid:
            result.append(VectorStore(id=vid, name=vname))
    return result


# ── Unified model list (v2) ───────────────────────────────────────────────
@app.get("/api/models", response_model=List[ModelInfo])
def list_models():
    """
    Returns ALL available models — gateway and CPU — as ModelInfo objects.
    The 'runtime' source is NOT exposed; the frontend only sees id, capabilities,
    and whether a model is the default.

    Replaces the legacy List[str] response while remaining usable by any code
    that only reads the 'id' field.
    """
    return [
        ModelInfo(id=m.id, capabilities=m.capabilities, default=m.is_default)
        for m in state.model_registry
    ]


# ── Unified chat endpoint (v2) ────────────────────────────────────────────
@app.post("/api/chat", response_model=UnifiedChatResponse)
async def unified_chat(req: UnifiedChatRequest):
    """
    Single chat endpoint for all models and runtimes.

    Routing logic:
    1. Resolve which ModelDescriptor to use:
       - If auto_detect=True  → classify task from prompt, then call
                                 _select_model_for_task() (see priority in docstring)
       - If auto_detect=False → use req.model_id (or default if empty)
    2. If the resolved model runtime == "gateway":
       - Perform CAS search when vector_store_id is provided (RAG)
       - Send prompt (+context) to Model Gateway via RAGFlowEnhanced
    3. If the resolved model runtime == "cpu":
       - CAS search is still performed when vector_store_id is provided,
         context is prepended to the prompt before forwarding to KServe
       - Proxy to KServe /v1/chat/completions via httpx
    """
    if not req.query.strip():
        raise HTTPException(status_code=422, detail="query must not be empty")

    if not state.model_registry:
        raise HTTPException(status_code=503, detail="Model registry is empty — check configuration")

    # ── Step 1: Resolve model ──────────────────────────────────────────────
    if req.auto_detect:
        task = _classify_task(req.query)
        descriptor = _select_model_for_task(task, state.model_registry)
        logger.info("auto_detect: classified task=%s → model=%s", task, descriptor.id if descriptor else "none")
    else:
        mid = req.model_id.strip()
        if mid:
            descriptor = _get_descriptor(mid, state.model_registry)
            if descriptor is None:
                raise HTTPException(status_code=400, detail=f"Unknown model '{mid}'")
        else:
            descriptor = next((m for m in state.model_registry if m.is_default), state.model_registry[0])

    if descriptor is None:
        raise HTTPException(status_code=503, detail="Could not resolve a model for this request")

    # ── Step 2: Route to the correct backend ──────────────────────────────
    if descriptor.runtime == "gateway":
        return await _handle_gateway_chat(req, descriptor)
    else:
        return await _handle_cpu_chat(req, descriptor)


async def _handle_gateway_chat(
    req: UnifiedChatRequest,
    descriptor: ModelDescriptor,
) -> UnifiedChatResponse:
    """
    Handle a chat request routed to a gateway (RAG) model.
    Reuses/rebuilds RAGFlowEnhanced exactly as the legacy /api/chat did.
    """
    if not state.ready or state.rag_flow is None:
        raise HTTPException(
            status_code=503,
            detail="RAG service not ready — check CAS_ENDPOINT / MODEL_GATEWAY_ENDPOINT env vars",
        )

    cas_endpoint = _env("CAS_ENDPOINT")
    cas_api_key = _env("CAS_API_KEY")
    cas_use_mcp = _bool_env("CAS_USE_MCP", False)
    gw_endpoint = _env("MODEL_GATEWAY_ENDPOINT")
    gw_api_key = _env("MODEL_GATEWAY_API_KEY")
    top_k = _int_env("DEFAULT_TOP_K", 5)

    effective_store = req.vector_store_id.strip() or None
    effective_model = descriptor.id

    # Reuse shared rag_flow unless store or model differs from startup defaults
    rag = state.rag_flow
    startup_store = rag.cas_client.vector_store_id if rag.cas_client else None
    startup_model = rag.model_name

    if effective_store != startup_store or effective_model != startup_model:
        try:
            rag = RAGFlowEnhanced(
                cas_endpoint=cas_endpoint,
                llm_endpoint=gw_endpoint,
                prompt_template=DEFAULT_PROMPT_TEMPLATE,
                top_k=top_k,
                use_mcp=cas_use_mcp,
                cas_api_key=cas_api_key,
                vector_store_id=effective_store,
                enable_detailed_attribution=True,
                max_retries=3,
                timeout=60,
                use_model_gateway=True,
                model_gateway_api_key=gw_api_key,
                model_name=effective_model,
            )
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Failed to build RAG flow: {exc}")

    try:
        result = rag.run(req.query)
    except Exception as exc:
        logger.exception("RAG run failed")
        raise HTTPException(status_code=500, detail=str(exc))

    sources = [SourceAttribution(**s.to_dict()) for s in (result.sources or [])]
    metrics = ResponseMetrics(
        processing_time=result.processing_time,
        sources_count=len(result.sources),
        cas_search_count=result.cas_search_count,
    )
    return UnifiedChatResponse(
        response=result.response,
        model_id=descriptor.id,
        sources=sources,
        metrics=metrics,
    )


async def _handle_cpu_chat(
    req: UnifiedChatRequest,
    descriptor: ModelDescriptor,
) -> UnifiedChatResponse:
    """
    Handle a chat request routed to a CPU (KServe) model.

    If a vector_store_id is provided, CAS search is performed and the retrieved
    context is prepended to the user prompt before forwarding to KServe — this
    enables RAG with CPU models just as with gateway models.
    """
    # Optional CAS context injection for CPU models
    effective_prompt = req.query
    sources: List[SourceAttribution] = []
    metrics: Optional[ResponseMetrics] = None

    if req.vector_store_id.strip() and state.cas_client is not None:
        try:
            import time as _time
            _t0 = _time.time()
            results = state.cas_client.search(
                query=req.query,
                vector_store_id=req.vector_store_id.strip(),
                top_k=_int_env("DEFAULT_TOP_K", 5),
            )
            context_parts = []
            for r in results:
                context_parts.append(r.content)
                sources.append(SourceAttribution(
                    source_file=r.source,
                    document_id=r.document_id,
                    relevance_score=r.score,
                    content_snippet=r.content[:400],
                    metadata=r.metadata,
                ))
            if context_parts:
                context_str = "\n\n".join(context_parts)
                effective_prompt = (
                    f"Use the following context to answer the question.\n\n"
                    f"Context:\n{context_str}\n\nQuestion: {req.query}"
                )
            metrics = ResponseMetrics(
                processing_time=_time.time() - _t0,
                sources_count=len(sources),
                cas_search_count=len(sources),
            )
            logger.info("CAS search for CPU model: %d results", len(sources))
        except Exception as exc:
            logger.warning("CAS search failed for CPU model (continuing without context): %s", exc)

    # Determine task for system prompt injection
    task = _classify_task(req.query)

    # Build OpenAI-format messages
    messages = []
    if task == "summarize":
        messages.append({"role": "system", "content": _SUMMARIZE_SYSTEM_PROMPT})
    for h in req.history:
        messages.append({"role": h.role, "content": h.content})
    messages.append({"role": "user", "content": effective_prompt})

    payload = {
        "model": descriptor.id,
        "messages": messages,
        "max_tokens": req.max_tokens,
        "temperature": req.temperature,
    }
    headers = {"Authorization": f"Bearer {descriptor.token}"} if descriptor.token else {}
    url = descriptor.endpoint_url.rstrip("/") + "/v1/chat/completions"

    logger.info("cpu_chat model=%s prompt_len=%d", descriptor.id, len(effective_prompt))

    async with httpx.AsyncClient(timeout=CPU_INFERENCE_TIMEOUT, verify=False) as client:
        try:
            r = await client.post(url, json=payload, headers=headers)
            r.raise_for_status()
        except httpx.HTTPStatusError as exc:
            logger.error("cpu upstream error: %s %s", exc.response.status_code, exc.response.text)
            raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text)
        except httpx.RequestError as exc:
            logger.error("cpu request error: %s", exc)
            raise HTTPException(status_code=502, detail=f"Could not reach CPU model backend: {exc}")

    body = r.json()
    content = body["choices"][0]["message"]["content"]
    usage = body.get("usage")

    return UnifiedChatResponse(
        response=content,
        model_id=descriptor.id,
        sources=sources,
        metrics=metrics,
        usage=usage,
    )


# ---------------------------------------------------------------------------
# Legacy RAG chat endpoint — kept for backward compatibility
# ---------------------------------------------------------------------------
@app.post("/api/rag/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    """
    Legacy RAG chat endpoint (preserved for backward compatibility).
    New code should use POST /api/chat with model_id set to a gateway model.
    """
    if not req.query.strip():
        raise HTTPException(status_code=422, detail="query must not be empty")

    if not state.ready or state.rag_flow is None:
        raise HTTPException(
            status_code=503,
            detail="Service not ready — check CAS_ENDPOINT / MODEL_GATEWAY_ENDPOINT env vars",
        )

    cas_endpoint = _env("CAS_ENDPOINT")
    cas_api_key = _env("CAS_API_KEY")
    cas_use_mcp = _bool_env("CAS_USE_MCP", False)
    gw_endpoint = _env("MODEL_GATEWAY_ENDPOINT")
    gw_api_key = _env("MODEL_GATEWAY_API_KEY")
    top_k = _int_env("DEFAULT_TOP_K", 5)

    effective_store = req.vector_store_id.strip() or None
    effective_model = req.model_name.strip() or _env("MODEL_NAME", "qwen2-5-72b-instruct")

    rag = state.rag_flow
    startup_store = rag.cas_client.vector_store_id if rag.cas_client else None
    startup_model = rag.model_name

    if effective_store != startup_store or effective_model != startup_model:
        try:
            rag = RAGFlowEnhanced(
                cas_endpoint=cas_endpoint,
                llm_endpoint=gw_endpoint,
                prompt_template=DEFAULT_PROMPT_TEMPLATE,
                top_k=top_k,
                use_mcp=cas_use_mcp,
                cas_api_key=cas_api_key,
                vector_store_id=effective_store,
                enable_detailed_attribution=True,
                max_retries=3,
                timeout=60,
                use_model_gateway=True,
                model_gateway_api_key=gw_api_key,
                model_name=effective_model,
            )
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Failed to build RAG flow: {exc}")

    try:
        result = rag.run(req.query)
    except Exception as exc:
        logger.exception("RAG run failed")
        raise HTTPException(status_code=500, detail=str(exc))

    sources = [SourceAttribution(**s.to_dict()) for s in (result.sources or [])]
    metrics = ResponseMetrics(
        processing_time=result.processing_time,
        sources_count=len(result.sources),
        cas_search_count=result.cas_search_count,
    )
    return ChatResponse(response=result.response, sources=sources, metrics=metrics)


# ---------------------------------------------------------------------------
# Legacy CPU multi-model routes — kept for backward compatibility
# ---------------------------------------------------------------------------
@app.get("/api/cpu/models", response_model=dict)
def cpu_list_models():
    """
    Returns the task → model-ID mapping for the three CPU tasks.
    Kept for backward compatibility; new code should use GET /api/models.
    """
    result = {}
    for task in CPU_TASKS:
        cfg = _cpu_model_cfg(task)
        result[task] = {"id": cfg.get("id", ""), "available": bool(cfg)}
    return result


@app.post("/api/cpu/chat", response_model=CpuChatResponse)
async def cpu_chat(req: CpuChatRequest):
    """
    Legacy CPU multi-model chat endpoint (preserved for backward compatibility).
    New code should use POST /api/chat with the desired model_id.
    """
    if not req.prompt.strip():
        raise HTTPException(status_code=422, detail="prompt must not be empty")

    if not _cpu_models_available():
        raise HTTPException(
            status_code=503,
            detail=(
                "CPU models are not configured. "
                "Set MODEL_URL_CHAT / MODEL_ID_CHAT (and optionally CODE / SUMMARIZE) env vars."
            ),
        )

    task = (req.task or _classify_task(req.prompt)).lower()
    if task not in CPU_TASKS:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown task '{task}'. Valid tasks: {list(CPU_TASKS)}",
        )

    cfg = _cpu_model_cfg(task)
    if not cfg:
        logger.warning(f"Task '{task}' model not configured; falling back to 'chat'")
        task = "chat"
        cfg = _cpu_model_cfg("chat")
        if not cfg:
            raise HTTPException(status_code=503, detail="Chat CPU model not configured")

    messages = []
    effective_system = req.system_prompt or (_SUMMARIZE_SYSTEM_PROMPT if task == "summarize" else None)
    if effective_system:
        messages.append({"role": "system", "content": effective_system})
    for h in req.history:
        messages.append({"role": h.role, "content": h.content})
    messages.append({"role": "user", "content": req.prompt})

    payload = {
        "model": cfg["id"],
        "messages": messages,
        "max_tokens": req.max_tokens,
        "temperature": req.temperature,
    }

    headers = {"Authorization": f"Bearer {cfg['token']}"} if cfg["token"] else {}
    url = cfg["url"].rstrip("/") + "/v1/chat/completions"

    logger.info("cpu_chat task=%s model=%s prompt_len=%d", task, cfg["id"], len(req.prompt))

    async with httpx.AsyncClient(timeout=CPU_INFERENCE_TIMEOUT, verify=False) as client:
        try:
            r = await client.post(url, json=payload, headers=headers)
            r.raise_for_status()
        except httpx.HTTPStatusError as exc:
            logger.error("cpu upstream error: %s %s", exc.response.status_code, exc.response.text)
            raise HTTPException(
                status_code=exc.response.status_code,
                detail=exc.response.text,
            )
        except httpx.RequestError as exc:
            logger.error("cpu request error: %s", exc)
            raise HTTPException(status_code=502, detail=f"Could not reach CPU model backend: {exc}")

    body = r.json()
    content = body["choices"][0]["message"]["content"]
    usage = body.get("usage")

    return CpuChatResponse(task=task, model=cfg["id"], content=content, usage=usage)


# ---------------------------------------------------------------------------
# Serve the compiled React SPA
# Must come LAST so API routes take priority
# ---------------------------------------------------------------------------
_static_dir = Path(__file__).parent / "static"

if _static_dir.exists():
    app.mount("/assets", StaticFiles(directory=_static_dir / "assets"), name="assets")

    @app.get("/{full_path:path}", include_in_schema=False)
    def spa_fallback(full_path: str):
        """Catch-all: serve index.html for any non-API path (React router)."""
        index = _static_dir / "index.html"
        if index.exists():
            return FileResponse(index)
        return JSONResponse({"detail": "UI not built yet"}, status_code=404)
