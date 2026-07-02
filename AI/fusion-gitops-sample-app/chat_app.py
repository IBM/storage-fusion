#!/usr/bin/env python3
"""
Enhanced Chat Application for Fusion Agentic Assistance Platform
Provides advanced chat interface with real-time progress tracking and source attribution
Implements SOLID design principles with comprehensive error handling
"""
import os
import sys
from pathlib import Path
from typing import Tuple, Optional
import time

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
from src.rag_flow import RAGFlowEnhanced, ProgressUpdate, ProcessingStage
from src.cas_client import CASClient

# Page configuration
st.set_page_config(
    page_title="Agentic Chat Assistant",
    page_icon="🤖",
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
        from datetime import datetime
        
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
            "modified_keys": set(),
            "last_reset_time": None,
            "initialization_time": datetime.now(),
        }


def get_config_value(key: str, default=""):
    """
    Get configuration value with proper fallback hierarchy.
    Precedence: active_values → vault_values → defaults → provided default
    
    Args:
        key: Configuration key to retrieve
        default: Default value if key not found
        
    Returns:
        Configuration value
    """
    if "config" not in st.session_state:
        initialize_session_config()
    
    # Try active values first
    if key in st.session_state.config["active_values"]:
        return st.session_state.config["active_values"][key]
    
    # Fallback to vault values
    if key in st.session_state.config["vault_values"]:
        return st.session_state.config["vault_values"][key]
    
    # Final fallback to defaults
    return CONFIG_DEFAULTS.get(key, default)


def set_config_value(key: str, value):
    """
    Set configuration value in active session.
    Tracks modifications and never touches os.environ.
    
    Args:
        key: Configuration key to set
        value: Value to set
    """
    if "config" not in st.session_state:
        initialize_session_config()
    
    # Update active value
    st.session_state.config["active_values"][key] = value
    
    # Track if different from vault value
    vault_value = st.session_state.config["vault_values"].get(key)
    if value != vault_value:
        st.session_state.config["modified_keys"].add(key)
    else:
        st.session_state.config["modified_keys"].discard(key)


def is_config_modified(key: str = None) -> bool:
    """
    Check if configuration has been modified from vault values.
    
    Args:
        key: Specific key to check, or None to check if any config is modified
        
    Returns:
        True if modified, False otherwise
    """
    if "config" not in st.session_state:
        return False
    
    if key is None:
        return len(st.session_state.config["modified_keys"]) > 0
    
    return key in st.session_state.config["modified_keys"]


def reset_config_to_vault():
    """
    Reset all configuration values to vault-managed values.
    Preserves vault_values reference and updates active_values.
    """
    from datetime import datetime
    
    if "config" not in st.session_state:
        initialize_session_config()
        return
    
    # Copy vault values to active values
    st.session_state.config["active_values"] = st.session_state.config["vault_values"].copy()
    
    # Clear modification tracking
    st.session_state.config["modified_keys"].clear()
    st.session_state.config["last_reset_time"] = datetime.now()
    
    # Invalidate RAG flow to force reinitialization with vault values
    if "rag_flow" in st.session_state:
        st.session_state.rag_flow = None
    
    # Clear vector stores to force refresh
    if "vector_stores" in st.session_state:
        st.session_state.vector_stores = []


def get_modified_config_summary():
    """
    Get list of modified configuration keys with their values.
    
    Returns:
        List of tuples (key, vault_value, active_value)
    """
    if "config" not in st.session_state or not is_config_modified():
        return []
    
    summary = []
    for key in st.session_state.config["modified_keys"]:
        vault_val = st.session_state.config["vault_values"].get(key, "")
        active_val = st.session_state.config["active_values"].get(key, "")
        summary.append((key, vault_val, active_val))
    
    return summary


# Custom CSS for better UI
st.markdown("""
<style>
    .source-card {
        background-color: #f0f2f6;
        border-left: 4px solid #4CAF50;
        padding: 15px;
        margin: 10px 0;
        border-radius: 5px;
    }
    .progress-item {
        padding: 8px;
        margin: 5px 0;
        border-radius: 4px;
        font-size: 0.85em;
        line-height: 1.3;
    }
    .progress-completed {
        background-color: #d4edda;
        border-left: 3px solid #28a745;
        color: #155724;
    }
    .progress-in-progress {
        background-color: #fff3cd;
        border-left: 3px solid #ffc107;
        color: #856404;
    }
    .progress-failed {
        background-color: #f8d7da;
        border-left: 3px solid #dc3545;
        color: #721c24;
    }
    .metric-card {
        background-color: #f8f9fa;
        padding: 10px;
        border-radius: 6px;
        border: 1px solid #e9ecef;
        margin: 5px 0;
    }
    /* Fixed bottom container space padding for clean scrolling */
    .main .block-container {
        padding-bottom: 140px;
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
if "progress_updates" not in st.session_state:
    st.session_state.progress_updates = []
if "is_processing" not in st.session_state:
    st.session_state.is_processing = False

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


def progress_callback(update: ProgressUpdate):
    st.session_state.progress_updates.append(update)
    # Check if we have an active placeholder reference to write real-time status UI updates
    if "progress_placeholder" in st.session_state and st.session_state.progress_placeholder:
        with st.session_state.progress_placeholder.container():
            render_progress_tracker(from_callback=True)


def on_vector_store_change():
    """Callback function to instantly update and sync selected store status text"""
    if "vector_store_selector" in st.session_state:
        st.session_state.selected_vector_store = st.session_state.vector_store_selector


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
        st.error("❌ Model Gateway API Key is required")
        return None

    if not vector_store_id:
        vector_store_id = get_config_value("cas_vector_store_id", "").strip()
        if not vector_store_id:
            vector_store_id = None

    cas_valid, cas_error = validate_endpoint(cas_endpoint, "CAS")
    gateway_valid, gateway_error = validate_endpoint(model_gateway_endpoint, "Model Gateway")
    
    if not cas_valid:
        st.error(f"❌ {cas_error}")
        return None
    if not gateway_valid:
        st.error(f"❌ {gateway_error}")
        return None

    if not cas_use_mcp and not vector_store_id:
        st.warning("⚠️ Vector Store ID is recommended for REST API mode.")

    try:
        rag_flow = RAGFlowEnhanced(
            cas_endpoint=cas_endpoint,
            llm_endpoint=model_gateway_endpoint,
            prompt_template=DEFAULT_PROMPT_TEMPLATE,
            top_k=int(get_config_value("default_top_k", "5")),
            use_mcp=cas_use_mcp,
            cas_api_key=cas_api_key,
            vector_store_id=vector_store_id,
            progress_callback=progress_callback,
            enable_detailed_attribution=True,
            max_retries=3,
            timeout=60,
            use_model_gateway=True,
            model_gateway_api_key=model_gateway_api_key,
            model_name=model_name
        )
        return rag_flow
    except Exception as e:
        st.error(f"❌ Failed to initialize RAG flow: {str(e)}")
        return None


def fetch_vector_stores(endpoint, api_key):
    """Helper method to fetch vector stores into session state"""
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
    except Exception as e:
        st.sidebar.error(f"❌ Auto-load stores failed: {str(e)}")


def render_progress_tracker(from_callback=False):
    if st.session_state.progress_updates:
        # Avoid rewriting header nesting inside the container refresh loop
        if not from_callback:
            st.markdown("### 🔄 Processing Status")
        
        # Showing slightly fewer items in the sidebar to prevent extreme scrolling
        recent_updates = st.session_state.progress_updates
        
        for update in reversed(recent_updates):
            if update.stage == ProcessingStage.COMPLETED:
                css_class = "progress-completed"
                icon = "✅"
            elif update.stage == ProcessingStage.FAILED:
                css_class = "progress-failed"
                icon = "❌"
            else:
                css_class = "progress-in-progress"
                icon = "⏳"
            
            time_str = update.timestamp.strftime("%H:%M:%S")
            st.markdown(f"""
            <div class="progress-item {css_class}">
                <strong>{icon} {update.stage.value.replace('_', ' ').title()}</strong><br>
                <small style="color: gray;">{time_str}</small> - {update.message}
            </div>
            """, unsafe_allow_html=True)
            
            if update.error:
                st.error(f"Error: {update.error}")
    else:
        # Placeholder view when list is blank
        st.caption("No processing pipelines currently running.")


def render_response_metrics_and_sources(msg_index, metrics, sources):
    if not metrics and not sources:
        return

    # Dynamic metrics per response frame
    if metrics:
        m_col1, m_col2, m_col3 = st.columns(3)
        with m_col1:
            st.metric("Processing Time", f"{metrics.get('processing_time', 0):.2f}s")
        with m_col2:
            st.metric("Sources Used", metrics.get('sources_count', 0))
        with m_col3:
            st.metric("CAS Passes", metrics.get('cas_search_count', 0))
            
    # Sources configuration container per response frame
    if sources:
        with st.expander("📚 View Cited Sources for this Response", expanded=False):
            for i, source in enumerate(sources, 1):
                # Normalized safely to dictionary layout syntax for clean history lookups
                s_file = source.get('source_file', 'Unknown')
                s_rel = source.get('relevance_score', 0.0)
                s_start = source.get('line_start', None)
                s_end = source.get('line_end', None)
                s_id = source.get('document_id', 'Unknown')
                s_snippet = source.get('content_snippet', '')
                s_meta = source.get('metadata', {})

                st.markdown(f"**📄 Source {i}: {s_file}** (Relevance: `{s_rel:.4f}`)")
                
                c1, c2 = st.columns([2, 1])
                with c1:
                    if s_start and s_end:
                        st.markdown(f"**📍 Line Numbers:** `{s_start}` - `{s_end}`")
                with c2:
                    st.markdown(f"**Document ID:** `{s_id}`")
                
                st.text_area(
                    "Content Snippet",
                    value=s_snippet,
                    height=100,
                    key=f"msg_{msg_index}_source_snippet_{i}",
                    disabled=True
                )
                if s_meta:
                    st.json(s_meta)
                st.divider()
    else:
        st.info("ℹ️ No sources found in CAS for this query. Response is based on LLM's general knowledge.")


# --- SIDEBAR PANEL (COMPACT & ORDERED TOP LAYOUT) ---
with st.sidebar:
    # Initialize session configuration
    initialize_session_config()
    
    st.title("🤖 Agentic Chat Assistant")
    
    # 1. Single-line Status Block
    status_text = "🟢 Ready" if st.session_state.rag_flow else "🟡 Not initialized"
    store_text = f"Store: {st.session_state.selected_vector_store}" if st.session_state.selected_vector_store else ""
    st.markdown(f"**Status:** {status_text}")
    st.markdown(store_text)
    st.divider()
    
    # 2. Compact CAS Search Panel
    st.markdown("### 🔍 CAS Search Panel")
    if st.session_state.selected_agent:
        st.caption(f"Active Agent: **{st.session_state.selected_agent['name']}**")
        if st.button("🗑️ Clear Chat History", use_container_width=True):
            st.session_state.messages = []
            st.session_state.progress_updates = []
            st.session_state.is_processing = False
            # Cleanly purge the placeholder element
            if "progress_placeholder" in st.session_state and st.session_state.progress_placeholder:
                st.session_state.progress_placeholder.empty()
            st.rerun()
    else:
        st.caption("⚠️ No agent configured. Connect endpoints below.")

    st.divider()

    # 3. Vector Store Section
    st.markdown("### 🗄️ Vector Store")
    if st.session_state.selected_agent:
        if st.session_state.vector_stores:
            store_options = {
                store.get("id", store.get("vector_store_id", "")): store.get("name", store.get("id", "Unknown"))
                for store in st.session_state.vector_stores
            }
            
            current_store_id = st.session_state.selected_vector_store
            store_keys = list(store_options.keys())
            default_index = store_keys.index(current_store_id) if current_store_id in store_keys else 0
            
            selected_store_id = st.selectbox(
                "Select Store",
                options=store_keys,
                index=default_index,
                format_func=lambda x: f"{store_options[x]}",
                key="vector_store_selector",
                on_change=on_vector_store_change,
                label_visibility="collapsed"
            )
            st.session_state.selected_vector_store = selected_store_id
        else:
            manual_store_id = st.text_input(
                "Vector Store ID",
                value=get_config_value("cas_vector_store_id", ""),
                key="manual_vector_store_input",
            )
            if manual_store_id:
                st.session_state.selected_vector_store = manual_store_id
                
        if st.button("🔄 Refresh Stores", use_container_width=True):
            fetch_vector_stores(st.session_state.selected_agent["endpoint"], st.session_state.selected_agent["api_key"])
            st.rerun()
    else:
        st.info("💡 Complete configuration below to load stores.")

    st.divider()
    
    # 4. Connection Setup Configurations
    with st.expander("🔌 Gateway & API Connections", expanded=not bool(st.session_state.rag_flow)):
        cas_endpoint = st.text_input(
            "CAS Endpoint",
            value=get_config_value("cas_endpoint", ""),
            placeholder="https://cas-endpoint.com",
            key="config_cas_endpoint",
        )
        cas_api_key = st.text_input(
            "CAS API Key",
            value=get_config_value("cas_api_key", ""),
            type="password",
            key="config_cas_api_key",
        )
        model_gateway_endpoint = st.text_input(
            "Model Gateway Endpoint",
            value=get_config_value("model_gateway_endpoint", ""),
            key="config_model_gateway_endpoint",
        )
        model_gateway_api_key = st.text_input(
            "Model Gateway API Key",
            value=get_config_value("model_gateway_api_key", ""),
            type="password",
            key="config_model_gateway_api_key",
        )
        model_name = st.text_input(
            "Model Name",
            value=get_config_value("model_name", "qwen2-5-72b-instruct"),
            key="config_model_name",
        )

        if st.button("🔌 Initialize Components", type="primary", use_container_width=True):
            if not cas_endpoint or not model_gateway_endpoint:
                st.error("Please provide CAS Endpoint and Model Gateway Endpoint")
            elif not model_gateway_api_key:
                st.error("Please provide Model Gateway API Key")
            else:
                # Update session config instead of os.environ
                set_config_value("cas_endpoint", cas_endpoint)
                set_config_value("cas_api_key", cas_api_key)
                set_config_value("model_gateway_endpoint", model_gateway_endpoint)
                set_config_value("model_gateway_api_key", model_gateway_api_key)
                set_config_value("model_name", model_name)

                default_agent = {
                    "name": "CAS Agent",
                    "endpoint": cas_endpoint,
                    "api_key": cas_api_key,
                }
                st.session_state.cas_agents = [default_agent]
                st.session_state.selected_agent = default_agent

                # Automatically trigger loading vector stores right when initializing
                fetch_vector_stores(cas_endpoint, cas_api_key)

                st.session_state.rag_flow = initialize_rag_flow(
                    vector_store_id=st.session_state.selected_vector_store,
                    cas_endpoint=cas_endpoint,
                    cas_api_key=cas_api_key,
                    model_gateway_endpoint=model_gateway_endpoint,
                    model_gateway_api_key=model_gateway_api_key,
                    model_name=model_name
                )
                st.rerun()

    # 5. DOCKED TELEMETRY TRACKER IN SIDEBAR (Using an explicit empty container)
    st.divider()
    st.markdown("### 🔄 Processing Status")
    st.session_state.progress_placeholder = st.empty()
    with st.session_state.progress_placeholder.container():
        render_progress_tracker(from_callback=True)


# --- MAIN SCREEN VIEWPORT FRAME (Full Width Chat View) ---
# If history is blank AND a message isn't processing, show greeting layout
if not st.session_state.messages and not st.session_state.is_processing:
    st.markdown("""
    <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 60vh; text-align: center; color: #6c757d;">
        <div style="font-size: 4rem; margin-bottom: 10px;">🤖</div>
        <h2 style="font-weight: 600; margin-bottom: 5px; color: inherit;">How can I help you today?</h2>
        <p style="font-size: 1.1rem; max-width: 450px; margin: 0 auto;">
            Ask a question about your enterprise documents or connect your data stores in the sidebar to begin.
        </p>
    </div>
    """, unsafe_allow_html=True)
else:
    for idx, message in enumerate(st.session_state.messages):
        with st.chat_message(message["role"]):
            st.markdown(message["content"])
            if message["role"] == "assistant":
                render_response_metrics_and_sources(
                    msg_index=idx, 
                    metrics=message.get("metrics"), 
                    sources=message.get("sources")
                )


# --- ANCHORED STICKY ROOT LEVEL CHAT INPUT CONTAINER ---
if prompt := st.chat_input("Ask a question about your enterprise documents..."):
    # Toggle processing flag to immediately drop greeting screen elements
    st.session_state.is_processing = True
    
    # 1. Immediately render user prompt 
    st.chat_message("user").markdown(prompt)
    st.session_state.messages.append({"role": "user", "content": prompt})
    
    if not st.session_state.selected_agent:
        st.session_state.messages.append({"role": "assistant", "content": "⚠️ Please initialize components first"})
        st.session_state.is_processing = False
        st.rerun()
    elif not st.session_state.selected_vector_store:
        st.session_state.messages.append({"role": "assistant", "content": "⚠️ Please select a vector store"})
        st.session_state.is_processing = False
        st.rerun()
    elif not st.session_state.rag_flow:
        st.session_state.messages.append({"role": "assistant", "content": "⚠️ RAG flow not initialized"})
        st.session_state.is_processing = False
        st.rerun()
    else:
        try:
            st.session_state.progress_updates = []
            
            # 2. Render assistant context container framework containing processing indicators
            with st.chat_message("assistant"):
                with st.spinner("Processing your request..."):
                    result = st.session_state.rag_flow.run(prompt)
                        
            metrics_payload = {
                'processing_time': result.processing_time,
                'sources_count': len(result.sources),
                'cas_search_count': result.cas_search_count
            }
            
            # Explicitly serialize SourceAttribution objects using list comprehensions (.to_dict())
            # to maintain clean session states and avoid runtime serialization errors.
            st.session_state.messages.append({
                "role": "assistant",
                "content": result.response,
                "sources": [s.to_dict() for s in result.sources] if result.sources else [],
                "metrics": metrics_payload
            })
            st.session_state.is_processing = False
            st.rerun()

        except Exception as e:
            st.session_state.messages.append({
                "role": "assistant", 
                "content": f"Error: {str(e)}"
            })
            st.session_state.is_processing = False
            st.rerun()