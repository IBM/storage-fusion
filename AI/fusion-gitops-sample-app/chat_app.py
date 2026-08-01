#!/usr/bin/env python3
"""
Enhanced Chat Application for Fusion Agentic Assistance Platform
Provides advanced chat interface with real-time progress tracking and source attribution
Implements SOLID design principles with comprehensive error handling
"""
import os
import sys
from pathlib import Path
from typing import Tuple

# Set Streamlit home to avoid permission issues in containers
try:
    streamlit_home = "/app/.streamlit"
    os.makedirs(streamlit_home, exist_ok=True)
    os.environ["STREAMLIT_HOME"] = streamlit_home
except (PermissionError, OSError):
    try:
        streamlit_home = os.path.expanduser("~/.streamlit")
        os.makedirs(streamlit_home, exist_ok=True)
        os.environ["STREAMLIT_HOME"] = streamlit_home
    except (PermissionError, OSError):
        pass

import streamlit as st
from dotenv import load_dotenv

# Add project root to path
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

# Load environment variables
load_dotenv()

# Import enhanced RAG flow and CAS client
from src.rag_flow import RAGFlowEnhanced
from src.cas_client import CASClient

# Page configuration
st.set_page_config(
    page_title="Agentic Chat Assistant",
    page_icon="❇",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Configuration Management Constants
CONFIG_DEFAULTS = {
    "cas_endpoint": "",
    "cas_api_key": "",
    "cas_vector_store_id": "",
    "cas_use_mcp": False,
    "model_gateway_endpoint": "",
    "model_gateway_api_key": "",
    "model_name": "qwen2-5-72b-instruct",
    "default_top_k": 5,
}

CONFIG_ENV_MAPPING = {
    "cas_endpoint": "CAS_ENDPOINT",
    "cas_api_key": "CAS_API_KEY",
    "cas_vector_store_id": "CAS_VECTOR_STORE_ID",
    "cas_use_mcp": "CAS_USE_MCP",
    "model_gateway_endpoint": "MODEL_GATEWAY_ENDPOINT",
    "model_gateway_api_key": "MODEL_GATEWAY_API_KEY",
    "model_name": "MODEL_NAME",
    "default_top_k": "DEFAULT_TOP_K",
}


# Configuration Management Functions
def initialize_session_config():
    """
    Initialize session configuration from environment variables.
    Called once per session, loads from environment variables into session state.
    This ensures vault-managed values are never modified in os.environ.
    """
    if "config" not in st.session_state:
        # Load vault values from environment (immutable reference)
        vault_values = {}
        for config_key, env_key in CONFIG_ENV_MAPPING.items():
            env_value = os.getenv(env_key, "")

            # Type conversion
            if config_key == "cas_use_mcp":
                vault_values[config_key] = env_value.lower() == "true"
            elif config_key == "default_top_k":
                vault_values[config_key] = int(env_value) if env_value else CONFIG_DEFAULTS[config_key]
            else:
                vault_values[config_key] = env_value if env_value else CONFIG_DEFAULTS[config_key]

        # Initialize session config
        st.session_state.config = {
            "vault_values": vault_values.copy(),  # Immutable reference
            "active_values": vault_values.copy(),  # Mutable working copy
        }


def get_config_value(key: str, default=""):
    """
    Get configuration value with proper fallback hierarchy.
    Precedence: active_values → vault_values → defaults → provided default
    """
    if "config" not in st.session_state:
        initialize_session_config()

    if key in st.session_state.config["active_values"]:
        return st.session_state.config["active_values"][key]

    if key in st.session_state.config["vault_values"]:
        return st.session_state.config["vault_values"][key]

    return CONFIG_DEFAULTS.get(key, default)


def set_config_value(key: str, value):
    """
    Set configuration value in active session.
    """
    if "config" not in st.session_state:
        initialize_session_config()

    st.session_state.config["active_values"][key] = value


# ── Modern Design System ──────────────────────────────────────────────────────
st.markdown("""
<style>
  /* ── Global resets & typography ── */
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');

  html, body, [class*="css"] {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  }

  /* ── App background ── */
  .stApp {
      background: #0D1117;
  }

  /* ── Sidebar ── */
  [data-testid="stSidebar"] {
      background: #111620 !important;
      border-right: 1px solid rgba(255,255,255,0.07) !important;
  }
  [data-testid="stSidebar"] .stMarkdown h3,
  [data-testid="stSidebar"] .stMarkdown h4 {
      font-size: 0.70rem;
      font-weight: 600;
      letter-spacing: 0.10em;
      text-transform: uppercase;
      color: #4F8EF7;
      margin: 0 0 8px 0;
  }

  /* ── Sidebar brand header ── */
  .brand-header {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 6px 0 18px 0;
      border-bottom: 1px solid rgba(255,255,255,0.07);
      margin-bottom: 20px;
  }
  .brand-icon {
      width: 34px;
      height: 34px;
      background: linear-gradient(135deg, #2D6BE4 0%, #4F8EF7 100%);
      border-radius: 9px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 1rem;
      flex-shrink: 0;
  }
  .brand-name {
      font-size: 1.05rem;
      font-weight: 700;
      color: #E2E8F0;
      line-height: 1.2;
  }
  .brand-sub {
      font-size: 0.72rem;
      color: #64748B;
      font-weight: 400;
  }

  /* ── Status text ── */
  .status-pill {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      font-size: 0.75rem;
      font-weight: 400;
  }
  .status-ready {
      color: #34D399;
  }
  .status-idle {
      color: #FBBF24;
  }
  .status-store {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      font-size: 0.73rem;
      color: #64748B;
      margin-left: 2px;
  }

  /* ── Section divider ── */
  .section-divider {
      border: none;
      border-top: 1px solid rgb(34 38 48);
      margin: 14px 0;
  }

  /* ── Input labels ── */
  [data-testid="stSidebar"] label {
      font-size: 0.78rem !important;
      font-weight: 500 !important;
      color: #94A3B8 !important;
      letter-spacing: 0.01em;
  }

  /* ── Text inputs ── */
  [data-testid="stSidebar"] input:not([class*="st-"]),
  [data-testid="stSidebar"] .stSelectbox select {
      background: #1C2333 !important;
      border: 1px solid rgba(255,255,255,0.08) !important;
      color: #E2E8F0 !important;
      font-size: 0.83rem !important;
  }
  [data-testid="stSidebar"] input:not([class*="st-"]):focus {
      border-color: rgba(79, 142, 247, 0.55) !important;
      box-shadow: 0 0 0 3px rgba(79, 142, 247, 0.10) !important;
  }
  /* Remove extra border on selectbox internal search input */
  [data-testid="stSidebar"] [data-testid="stSelectbox"] input {
      border: none !important;
      box-shadow: none !important;
      background: transparent !important;
  }

  /* ── Primary button ── */
  [data-testid="stSidebar"] .stButton > button[kind="primary"] {
      background: linear-gradient(135deg, #2D6BE4 0%, #4F8EF7 100%) !important;
      border: none !important;
      border-radius: 9px !important;
      color: #fff !important;
      font-weight: 600 !important;
      font-size: 0.83rem !important;
      padding: 10px 16px !important;
      transition: opacity 0.18s ease, transform 0.12s ease !important;
  }
  [data-testid="stSidebar"] .stButton > button[kind="primary"]:hover {
      opacity: 0.88 !important;
      transform: translateY(-1px) !important;
  }

  /* ── Secondary / outline buttons ── */
  [data-testid="stSidebar"] .stButton > button:not([kind="primary"]) {
      background: rgba(255,255,255,0.04) !important;
      border: 1px solid rgba(255,255,255,0.09) !important;
      border-radius: 9px !important;
      color: #CBD5E1 !important;
      font-size: 0.82rem !important;
      transition: background 0.15s ease !important;
  }
  [data-testid="stSidebar"] .stButton > button:not([kind="primary"]):not(:disabled):hover {
      background: rgba(79, 142, 247, 0.10) !important;
      border-color: rgba(79, 142, 247, 0.35) !important;
      color: #E2E8F0 !important;
  }
  [data-testid="stSidebar"] .stButton > button:disabled {
      background: rgba(255,255,255,0.02) !important;
      border-color: rgba(255,255,255,0.05) !important;
      color: rgba(255,255,255,0.20) !important;
      cursor: not-allowed !important;
  }

  /* ── Expander ── */
  [data-testid="stSidebar"] [data-testid="stExpander"] {
      background: #161B26 !important;
      border: 1px solid rgba(255,255,255,0.07) !important;
      border-radius: 10px !important;
  }
  [data-testid="stSidebar"] [data-testid="stExpander"] summary {
      font-size: 0.83rem !important;
      font-weight: 600 !important;
      color: #CBD5E1 !important;
      padding: 10px 14px !important;
  }

  /* ── Main area bottom padding ── */
  .main .block-container {
      padding-bottom: 150px;
      padding-top: 2rem;
  }

  /* ── Welcome screen ── */
  .welcome-wrap {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 62vh;
      text-align: center;
      padding: 40px 20px;
      pointer-events: none;
      user-select: none;
  }
  .welcome-orb {
      width: 80px;
      height: 80px;
      border-radius: 24px;
      background: linear-gradient(135deg, #2D6BE4 0%, #4F8EF7 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 2.2rem;
      margin: 0 auto 28px;
      box-shadow: 0 16px 40px rgba(45, 107, 228, 0.28);
  }
  .welcome-title {
      font-size: 2rem;
      font-weight: 700;
      color: #E2E8F0;
      margin: 0 0 12px 0;
      letter-spacing: -0.02em;
  }
  .welcome-sub {
      font-size: 1rem;
      color: #64748B;
      max-width: 460px;
      margin: 0 auto 32px;
      line-height: 1.65;
  }
  .welcome-chips {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: center;
      max-width: 560px;
  }
  .chip {
      background: #161B26;
      border: 1px solid rgba(79, 142, 247, 0.20);
      border-radius: 20px;
      padding: 6px 14px;
      font-size: 0.82rem;
      color: #7EB3FA;
      cursor: default;
  }

  /* ── Source / attribution card ── */
  .source-card {
      background: #161B26;
      border: 1px solid rgba(255,255,255,0.07);
      border-left: 3px solid #4F8EF7;
      border-radius: 10px;
      padding: 14px 16px;
      margin: 10px 0;
  }
  .source-title {
      font-size: 0.85rem;
      font-weight: 600;
      color: #E2E8F0;
      margin-bottom: 4px;
  }
  .source-meta {
      font-size: 0.75rem;
      color: #64748B;
  }

  /* ── Metric cards ── */
  .metric-row {
      display: flex;
      gap: 10px;
      margin: 8px 0 14px 0;
  }
  .metric-card {
      flex: 1;
      background: #161B26;
      border: 1px solid rgba(255,255,255,0.07);
      border-radius: 10px;
      padding: 12px 14px;
      text-align: center;
  }
  .metric-value {
      font-size: 1.35rem;
      font-weight: 700;
      color: #7EB3FA;
      line-height: 1.2;
  }
  .metric-label {
      font-size: 0.70rem;
      color: #64748B;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      margin-top: 2px;
  }

  /* ── Chat input ── */
  [data-testid="stChatInput"] textarea {
      background: #161B26 !important;
      border-radius: 12px !important;
      color: #E2E8F0 !important;
      font-size: 0.92rem !important;
  }
  [data-testid="stChatInput"] textarea:focus {
      border-color: rgba(79, 142, 247, 0.60) !important;
  }

  /* ── Chat messages — hide all avatars ── */
  [data-testid="stChatMessage"] {
      background: transparent !important;
  }
  [data-testid="stChatMessage"] [data-testid="stChatMessageAvatarUser"],
  [data-testid="stChatMessage"] [data-testid="stChatMessageAvatarAssistant"],
  [data-testid="stChatMessage"] .stChatMessageAvatar {
      display: none !important;
  }

  /* ── User bubble (right-aligned) ── */
  .user-bubble-wrap {
      display: flex;
      justify-content: flex-end;
      margin: 6px 0 14px 0;
  }
  .user-bubble {
      background: linear-gradient(135deg, #2D6BE4 0%, #4F8EF7 100%);
      color: #fff;
      border-radius: 18px 18px 4px 18px;
      padding: 10px 16px;
      max-width: 72%;
      font-size: 0.92rem;
      line-height: 1.55;
      word-break: break-word;
  }

  /* ── Assistant response (left-aligned, no bubble) ── */
  .assistant-wrap {
      margin: 4px 0 18px 0;
      max-width: 88%;
  }
  .assistant-wrap p,
  .assistant-wrap li,
  .assistant-wrap td {
      font-size: 0.93rem;
      line-height: 1.65;
      color: #E2E8F0;
  }

  /* ── Scrollbar ── */
  ::-webkit-scrollbar { width: 5px; }
  ::-webkit-scrollbar-track { background: transparent; }
  ::-webkit-scrollbar-thumb { background: rgba(79, 142, 247, 0.25); border-radius: 10px; }

  /* ── Info / warning / error tweaks ── */
  [data-testid="stAlert"] {
      border-radius: 10px !important;
      font-size: 0.83rem !important;
  }

  /* ── Caption ── */
  .stCaption, .st-caption {
      color: #64748B !important;
      font-size: 0.75rem !important;
  }
</style>
""", unsafe_allow_html=True)

# Initialize session state
if "messages" not in st.session_state:
    st.session_state.messages = []
if "rag_flow" not in st.session_state:
    st.session_state.rag_flow = None
if "cas_agents" not in st.session_state:
    st.session_state.cas_agents = []
if "selected_agent" not in st.session_state:
    st.session_state.selected_agent = None
if "vector_stores" not in st.session_state:
    st.session_state.vector_stores = []
if "selected_vector_store" not in st.session_state:
    st.session_state.selected_vector_store = None
if "is_processing" not in st.session_state:
    st.session_state.is_processing = False
if "auto_connected" not in st.session_state:
    st.session_state.auto_connected = False
if "available_models" not in st.session_state:
    st.session_state.available_models = []
if "selected_model" not in st.session_state:
    st.session_state.selected_model = None

# Default prompt template
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


def validate_endpoint(endpoint: str, endpoint_type: str) -> Tuple[bool, str]:
    if not endpoint:
        return False, f"{endpoint_type} endpoint is required"
    endpoint = endpoint.rstrip("/")
    if not endpoint.startswith(("http://", "https://")):
        return False, f"{endpoint_type} endpoint must start with http:// or https://"
    return True, ""


def on_vector_store_change():
    """Sync selected store and rebuild rag_flow so the new store is used immediately."""
    if "vector_store_selector" in st.session_state:
        new_store = st.session_state.vector_store_selector
        st.session_state.selected_vector_store = new_store
        if st.session_state.selected_agent:
            st.session_state.rag_flow = initialize_rag_flow(
                vector_store_id=new_store,
            )


def initialize_rag_flow(
    vector_store_id=None, cas_endpoint=None, cas_api_key=None,
    model_gateway_endpoint=None, model_gateway_api_key=None, model_name=None
):
    cas_endpoint = (cas_endpoint or get_config_value("cas_endpoint", "")).rstrip("/")
    cas_api_key = cas_api_key or get_config_value("cas_api_key", "")
    cas_use_mcp = get_config_value("cas_use_mcp", "false")
    if isinstance(cas_use_mcp, str):
        cas_use_mcp = cas_use_mcp.lower() == "true"

    model_gateway_endpoint = (model_gateway_endpoint or get_config_value("model_gateway_endpoint", "")).rstrip("/")
    model_gateway_api_key = model_gateway_api_key or get_config_value("model_gateway_api_key", "")
    model_name = model_name or get_config_value("model_name", "qwen2-5-72b-instruct")

    if not model_gateway_api_key:
        st.toast("Model Gateway API Key is required.", icon=":material/error:")
        return None

    if not vector_store_id:
        vector_store_id = get_config_value("cas_vector_store_id", "").strip()
        if not vector_store_id:
            vector_store_id = None

    cas_valid, cas_error = validate_endpoint(cas_endpoint, "CAS")
    gateway_valid, gateway_error = validate_endpoint(model_gateway_endpoint, "Model Gateway")

    if not cas_valid:
        st.toast(cas_error, icon=":material/error:")
        return None
    if not gateway_valid:
        st.toast(gateway_error, icon=":material/error:")
        return None

    if not cas_use_mcp and not vector_store_id:
        st.toast("Vector Store ID is recommended for REST API mode.", icon=":material/warning:")

    try:
        rag_flow = RAGFlowEnhanced(
            cas_endpoint=cas_endpoint,
            llm_endpoint=model_gateway_endpoint,
            prompt_template=DEFAULT_PROMPT_TEMPLATE,
            top_k=int(get_config_value("default_top_k", "5")),
            use_mcp=cas_use_mcp,
            cas_api_key=cas_api_key,
            vector_store_id=vector_store_id,
            enable_detailed_attribution=True,
            max_retries=3,
            timeout=60,
            use_model_gateway=True,
            model_gateway_api_key=model_gateway_api_key,
            model_name=model_name
        )
        return rag_flow
    except Exception as e:
        st.toast(f"Failed to initialise RAG flow: {str(e)}", icon=":material/error:")
        return None


def fetch_models(gateway_endpoint, api_key) -> bool:
    """Fetch available models from the Model Gateway /v1/models endpoint.
    Returns True if at least one model was retrieved, False otherwise."""
    try:
        import requests as _requests
        url = gateway_endpoint.rstrip("/") + "/v1/models"
        headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        resp = _requests.get(url, headers=headers, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        model_ids = [m["id"] for m in data.get("data", []) if "id" in m]
        st.session_state.available_models = model_ids
        return bool(model_ids)
    except Exception as e:
        st.session_state.available_models = []
        st.toast(f"Could not load models: {str(e)}", icon=":material/error:")
        return False


def fetch_vector_stores(endpoint, api_key) -> bool:
    """Fetch vector stores into session state.
    Returns True if at least one store was retrieved, False otherwise."""
    try:
        use_mcp = get_config_value("cas_use_mcp", "false")
        if isinstance(use_mcp, str):
            use_mcp = use_mcp.lower() == "true"
        cas_client = CASClient(
            endpoint=endpoint,
            api_key=api_key,
            use_mcp=use_mcp,
        )
        stores = cas_client.list_vector_stores(limit=50)
        st.session_state.vector_stores = stores
        return bool(stores)
    except Exception as e:
        st.session_state.vector_stores = []
        st.toast(f"Could not load vector stores: {str(e)}", icon=":material/error:")
        return False


def render_response_metrics_and_sources(msg_index, metrics, sources):
    if not metrics and not sources:
        return

    # Metric cards via custom HTML (avoids Streamlit's default metric styling)
    if metrics:
        proc_time = f"{metrics.get('processing_time', 0):.2f}s"
        src_count = metrics.get("sources_count", 0)
        cas_passes = metrics.get("cas_search_count", 0)
        st.markdown(
            f'<div class="metric-row">'
            f'<div class="metric-card"><div class="metric-value">{proc_time}</div>'
            f'<div class="metric-label">Processing Time</div></div>'
            f'<div class="metric-card"><div class="metric-value">{src_count}</div>'
            f'<div class="metric-label">Sources Used</div></div>'
            f'<div class="metric-card"><div class="metric-value">{cas_passes}</div>'
            f'<div class="metric-label">CAS Passes</div></div>'
            f"</div>",
            unsafe_allow_html=True,
        )

    # Sources expander
    if sources:
        with st.expander(f"View {len(sources)} cited source{'s' if len(sources) != 1 else ''}", expanded=False):
            for i, source in enumerate(sources, 1):
                s_file = source.get("source_file", "Unknown")
                s_rel = source.get("relevance_score", 0.0)
                s_start = source.get("line_start", None)
                s_end = source.get("line_end", None)
                s_id = source.get("document_id", "Unknown")
                s_snippet = source.get("content_snippet", "")
                s_meta = source.get("metadata", {})

                lines_str = f"Lines {s_start}–{s_end} · " if s_start and s_end else ""
                st.markdown(
                    f'<div class="source-card">'
                    f'<div class="source-title">Source {i} — {s_file}</div>'
                    f'<div class="source-meta">{lines_str}Relevance: {s_rel:.4f} · ID: <code style="font-size:0.72rem">{s_id}</code></div>'
                    f"</div>",
                    unsafe_allow_html=True,
                )

                if s_snippet:
                    st.text_area(
                        "Content snippet",
                        value=s_snippet,
                        height=90,
                        key=f"msg_{msg_index}_source_snippet_{i}",
                        disabled=True,
                        label_visibility="collapsed",
                    )
                if s_meta:
                    st.json(s_meta)
    else:
        st.info("No sources found in CAS for this query. Response is based on general LLM knowledge.")


# ── AUTO-CONNECT on first load using env/vault values ─────────────────────────
if not st.session_state.auto_connected:
    st.session_state.auto_connected = True
    initialize_session_config()
    _cas_ep = get_config_value("cas_endpoint", "")
    _gw_ep = get_config_value("model_gateway_endpoint", "")
    _gw_key = get_config_value("model_gateway_api_key", "")
    if _cas_ep and _gw_ep and _gw_key:
        _cas_key = get_config_value("cas_api_key", "")
        _pref_model = get_config_value("model_name", "")
        _default_agent = {"name": "CAS Agent", "endpoint": _cas_ep, "api_key": _cas_key}
        st.session_state.cas_agents = [_default_agent]
        st.session_state.selected_agent = _default_agent
        _stores_ok = fetch_vector_stores(_cas_ep, _cas_key)
        _models_ok = fetch_models(_gw_ep, _gw_key)
        if _stores_ok and _models_ok:
            # Resolve default vector store: prefer env value if present in list, else first
            _pref_store = get_config_value("cas_vector_store_id", "").strip()
            _store_ids = [
                s.get("id", s.get("vector_store_id", ""))
                for s in st.session_state.vector_stores
            ]
            if _pref_store and _pref_store in _store_ids:
                _store = _pref_store
            elif _store_ids:
                _store = _store_ids[0]
            else:
                _store = None
            st.session_state.selected_vector_store = _store

            # Resolve default model: prefer env value if present in list, else first available
            _models = st.session_state.available_models
            if _pref_model and _pref_model in _models:
                _model = _pref_model
            elif _models:
                _model = _models[0]
            else:
                _model = _pref_model or "qwen2-5-72b-instruct"
            st.session_state.selected_model = _model
            st.session_state.rag_flow = initialize_rag_flow(
                vector_store_id=_store,
                cas_endpoint=_cas_ep,
                cas_api_key=_cas_key,
                model_gateway_endpoint=_gw_ep,
                model_gateway_api_key=_gw_key,
                model_name=_model,
            )


# ── SIDEBAR ───────────────────────────────────────────────────────────────────
with st.sidebar:
    initialize_session_config()

    # Brand header
    is_ready = bool(st.session_state.rag_flow)
    status_class = "status-ready" if is_ready else "status-idle"
    status_dot = "●" if is_ready else "○"
    status_label = "Connected" if is_ready else "Not connected"

    st.markdown(
        f'<div class="brand-header">'
        f'<div class="brand-icon">❇</div>'
        f'<div>'
        f'<div class="brand-name">Agentic Chat Assistant</div>'
        f'<div class="brand-sub"><span class="status-pill {status_class}">{status_dot} {status_label}</span></div>'
        f'</div>'
        f'</div>',
        unsafe_allow_html=True,
    )

    # ── Grouped: Agent · Vector Store · Model ──
    # Vector Store
    st.markdown(
        '<p style="font-size:0.78rem;font-weight:500;color:#94A3B8;letter-spacing:0.01em;margin:0 0 4px;">Vector Store</p>',
        unsafe_allow_html=True,
    )
    if st.session_state.vector_stores:
        store_options = {
            store.get("id", store.get("vector_store_id", "")): store.get("name", store.get("id", "Unknown"))
            for store in st.session_state.vector_stores
        }
        store_keys = list(store_options.keys())

        current_store_id = st.session_state.selected_vector_store
        default_index = store_keys.index(current_store_id) if current_store_id in store_keys else 0
        selected_store_id = st.selectbox(
            "Vector Store",
            options=store_keys,
            index=default_index,
            format_func=lambda x: store_options[x],
            key="vector_store_selector",
            on_change=on_vector_store_change,
            label_visibility="collapsed",
        )
        st.session_state.selected_vector_store = selected_store_id
    else:
        st.markdown(
            '<p style="font-size:0.78rem;color:#4B5563;margin:0 0 4px;">Connect to load available vector stores.</p>',
            unsafe_allow_html=True,
        )

    # Model
    st.markdown(
        '<p style="font-size:0.78rem;font-weight:500;color:#94A3B8;letter-spacing:0.01em;margin:8px 0 4px;">Model</p>',
        unsafe_allow_html=True,
    )
    if st.session_state.available_models:
        _cur_model = st.session_state.selected_model
        _model_keys = st.session_state.available_models
        _model_idx = _model_keys.index(_cur_model) if _cur_model in _model_keys else 0

        def _on_model_change():
            new_model = st.session_state.model_selector
            st.session_state.selected_model = new_model
            set_config_value("model_name", new_model)
            if st.session_state.selected_agent:
                st.session_state.rag_flow = initialize_rag_flow(
                    vector_store_id=st.session_state.selected_vector_store,
                    model_name=new_model,
                )

        _chosen_model = st.selectbox(
            "Model",
            options=_model_keys,
            index=_model_idx,
            key="model_selector",
            on_change=_on_model_change,
            label_visibility="collapsed",
        )
        st.session_state.selected_model = _chosen_model
    else:
        st.markdown(
            '<p style="font-size:0.78rem;color:#4B5563;margin:0 0 4px;">Connect to load available models.</p>',
            unsafe_allow_html=True,
        )

    # Clear chat (bottom of group)
    if st.session_state.selected_agent:
        st.markdown('<div style="margin-top:10px;"></div>', unsafe_allow_html=True)
        has_messages = bool(st.session_state.messages)
        if st.button("New Chat", use_container_width=True, disabled=not has_messages):
            st.session_state.messages = []
            st.session_state.is_processing = False
            st.rerun()


# ── MAIN CHAT AREA ────────────────────────────────────────────────────────────
_greeting_placeholder = st.empty()

if not st.session_state.messages and not st.session_state.is_processing:
    with _greeting_placeholder.container():
        st.markdown(
            """
            <div class="welcome-wrap">
                <div class="welcome-orb">❇</div>
                <h2 class="welcome-title">How can I help you today?</h2>
                <p class="welcome-sub">
                    Ask questions about your enterprise documents. Connect your data stores
                    in the sidebar to unlock RAG-powered responses.
                </p>
                <div class="welcome-chips">
                    <span class="chip">Summarise a document</span>
                    <span class="chip">Find specific information</span>
                    <span class="chip">Extract key points</span>
                </div>
            </div>
            """,
            unsafe_allow_html=True,
        )
else:
    for idx, message in enumerate(st.session_state.messages):
        if message["role"] == "user":
            st.markdown(
                f'<div class="user-bubble-wrap">'
                f'<div class="user-bubble">{message["content"]}</div>'
                f'</div>',
                unsafe_allow_html=True,
            )
        else:
            with st.container():
                st.markdown(
                    f'<div class="assistant-wrap">',
                    unsafe_allow_html=True,
                )
                st.markdown(message["content"])
                st.markdown('</div>', unsafe_allow_html=True)
                render_response_metrics_and_sources(
                    msg_index=idx,
                    metrics=message.get("metrics"),
                    sources=message.get("sources"),
                )


# ── CHAT INPUT ────────────────────────────────────────────────────────────────
if prompt := st.chat_input("Ask a question about your enterprise documents…"):
    st.session_state.is_processing = True
    _greeting_placeholder.empty()

    st.markdown(
        f'<div class="user-bubble-wrap">'
        f'<div class="user-bubble">{prompt}</div>'
        f'</div>',
        unsafe_allow_html=True,
    )
    st.session_state.messages.append({"role": "user", "content": prompt})

    if not st.session_state.selected_agent:
        st.session_state.messages.append({"role": "assistant", "content": "Please initialise components first via the sidebar."})
        st.session_state.is_processing = False
        st.rerun()
    elif not st.session_state.selected_vector_store:
        st.session_state.messages.append({"role": "assistant", "content": "Please select a vector store from the sidebar."})
        st.session_state.is_processing = False
        st.rerun()
    elif not st.session_state.rag_flow:
        st.session_state.messages.append({"role": "assistant", "content": "RAG flow is not initialised yet."})
        st.session_state.is_processing = False
        st.rerun()
    else:
        try:
            with st.spinner("Thinking…"):
                result = st.session_state.rag_flow.run(prompt)

            metrics_payload = {
                "processing_time": result.processing_time,
                "sources_count": len(result.sources),
                "cas_search_count": result.cas_search_count,
            }

            st.session_state.messages.append({
                "role": "assistant",
                "content": result.response,
                "sources": [s.to_dict() for s in result.sources] if result.sources else [],
                "metrics": metrics_payload,
            })
            st.session_state.is_processing = False
            st.rerun()

        except Exception as e:
            st.toast(f"Query failed: {str(e)}", icon=":material/error:")
            st.session_state.messages.append({
                "role": "assistant",
                "content": "Something went wrong processing your request. Please try again.",
            })
            st.session_state.is_processing = False
            st.rerun()
