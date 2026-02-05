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
from src.rag_flow_enhanced import RAGFlowEnhanced, ProgressUpdate, ProcessingStage
from src.cas_client import CASClient

# Page configuration
st.set_page_config(
    page_title="Fusion Agentic Assistance Chat Assistant - Enhanced",
    page_icon="🤖",
    layout="wide",
    initial_sidebar_state="expanded",
)

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
        font-size: 0.9em;
    }
    .progress-completed {
        background-color: #d4edda;
        border-left: 3px solid #28a745;
    }
    .progress-in-progress {
        background-color: #fff3cd;
        border-left: 3px solid #ffc107;
    }
    .progress-failed {
        background-color: #f8d7da;
        border-left: 3px solid #dc3545;
    }
    .metric-card {
        background-color: #ffffff;
        padding: 15px;
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        margin: 10px 0;
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
if "config_expanded" not in st.session_state:
    st.session_state.config_expanded = False
if "progress_updates" not in st.session_state:
    st.session_state.progress_updates = []
if "current_sources" not in st.session_state:
    st.session_state.current_sources = []
if "processing_metrics" not in st.session_state:
    st.session_state.processing_metrics = {}

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
    """
    Validate endpoint URL format
    
    Args:
        endpoint: URL to validate
        endpoint_type: Type of endpoint (for error messages)
    
    Returns:
        Tuple of (is_valid, error_message)
    """
    if not endpoint:
        return False, f"{endpoint_type} endpoint is required"
    
    endpoint = endpoint.rstrip("/")
    
    if not endpoint.startswith(("http://", "https://")):
        return False, f"{endpoint_type} endpoint must start with http:// or https://"
    
    return True, ""


def progress_callback(update: ProgressUpdate):
    """
    Callback function for progress updates
    
    Args:
        update: Progress update object
    """
    st.session_state.progress_updates.append(update)


def initialize_rag_flow(
    vector_store_id=None, cas_endpoint=None, cas_api_key=None, llm_endpoint=None
):
    """Initialize enhanced RAG flow with configuration"""
    cas_endpoint = (cas_endpoint or os.getenv("CAS_ENDPOINT", "")).rstrip("/")
    llm_endpoint = (llm_endpoint or os.getenv("LLM_ENDPOINT", "")).rstrip("/")
    cas_api_key = cas_api_key or os.getenv("CAS_API_KEY", "")
    cas_use_mcp = os.getenv("CAS_USE_MCP", "false").lower() == "true"

    if not vector_store_id:
        vector_store_id = os.getenv("CAS_VECTOR_STORE_ID", "").strip()
        if not vector_store_id:
            vector_store_id = None

    # Validate endpoints
    cas_valid, cas_error = validate_endpoint(cas_endpoint, "CAS")
    llm_valid, llm_error = validate_endpoint(llm_endpoint, "LLM")
    
    if not cas_valid:
        st.error(f"❌ {cas_error}")
        return None
    if not llm_valid:
        st.error(f"❌ {llm_error}")
        return None

    if not cas_use_mcp and not vector_store_id:
        st.warning("⚠️ Vector Store ID is recommended for REST API mode.")

    try:
        if cas_api_key:
            os.environ["CAS_API_KEY"] = cas_api_key

        rag_flow = RAGFlowEnhanced(
            cas_endpoint=cas_endpoint,
            llm_endpoint=llm_endpoint,
            prompt_template=DEFAULT_PROMPT_TEMPLATE,
            top_k=int(os.getenv("DEFAULT_TOP_K", "5")),
            use_mcp=cas_use_mcp,
            cas_api_key=cas_api_key,
            vector_store_id=vector_store_id,
            progress_callback=progress_callback,
            enable_detailed_attribution=True,
            max_retries=3,
            timeout=60
        )
        return rag_flow
    except Exception as e:
        st.error(f"❌ Failed to initialize RAG flow: {str(e)}")
        return None


def get_cas_client():
    """Get CAS client from selected agent or default"""
    if st.session_state.selected_agent:
        agent = st.session_state.selected_agent
        use_mcp = os.getenv("CAS_USE_MCP", "false").lower() == "true"
        return CASClient(
            endpoint=agent.get("endpoint", ""),
            api_key=agent.get("api_key", ""),
            use_mcp=use_mcp,
            vector_store_id=st.session_state.selected_vector_store,
        )
    return None


def render_progress_tracker():
    """Render real-time progress tracker in sidebar"""
    if st.session_state.progress_updates:
        st.markdown("### 🔄 Processing Status")
        
        # Show latest updates (last 10)
        recent_updates = st.session_state.progress_updates[-10:]
        
        for update in reversed(recent_updates):
            # Determine CSS class based on stage
            if update.stage == ProcessingStage.COMPLETED:
                css_class = "progress-completed"
                icon = "✅"
            elif update.stage == ProcessingStage.FAILED:
                css_class = "progress-failed"
                icon = "❌"
            else:
                css_class = "progress-in-progress"
                icon = "⏳"
            
            # Format timestamp
            time_str = update.timestamp.strftime("%H:%M:%S")
            
            # Render progress item
            st.markdown(f"""
            <div class="progress-item {css_class}">
                <strong>{icon} {update.stage.value.replace('_', ' ').title()}</strong><br>
                <small>{time_str}</small> - {update.message}
            </div>
            """, unsafe_allow_html=True)
            
            if update.error:
                st.error(f"Error: {update.error}")


def render_source_attribution_panel(sources):
    """
    Render detailed source attribution panel
    
    Args:
        sources: List of SourceAttribution objects
    """
    if not sources:
        st.info("ℹ️ No sources found in CAS for this query. Response is based on LLM's general knowledge.")
        return
    
    st.markdown("### 📚 Source Attribution")
    st.markdown(f"**Information retrieved from {len(sources)} source(s):**")
    
    for i, source in enumerate(sources, 1):
        with st.expander(f"📄 Source {i}: {source.source_file} (Relevance: {source.relevance_score:.4f})", expanded=(i == 1)):
            col1, col2 = st.columns([2, 1])
            
            with col1:
                st.markdown("**File Information:**")
                st.code(source.source_file, language=None)
                
                if source.line_start and source.line_end:
                    st.markdown(f"**📍 Line Numbers:** `{source.line_start}` - `{source.line_end}`")
                
                st.markdown(f"**🎯 Relevance Score:** `{source.relevance_score:.4f}`")
            
            with col2:
                st.markdown("**Document ID:**")
                st.code(source.document_id, language=None)
            
            st.markdown("**Content Snippet:**")
            st.text_area(
                "",
                value=source.content_snippet,
                height=150,
                key=f"source_snippet_{i}",
                disabled=True
            )
            
            if source.metadata:
                st.markdown("**Metadata:**")
                st.json(source.metadata)


def render_processing_metrics():
    """Render processing metrics"""
    if st.session_state.processing_metrics:
        metrics = st.session_state.processing_metrics
        
        col1, col2, col3 = st.columns(3)
        
        with col1:
            st.metric(
                "Processing Time",
                f"{metrics.get('processing_time', 0):.2f}s"
            )
        
        with col2:
            st.metric(
                "Sources Found",
                metrics.get('sources_count', 0)
            )
        
        with col3:
            st.metric(
                "CAS Searches",
                metrics.get('cas_search_count', 0)
            )


# Header with configuration button
col1, col2 = st.columns([3, 1])
with col1:
    st.title("🤖 Fusion Agentic Assistance Chat Assistant - Enhanced")
    st.caption("Enterprise RAG with Real-time Progress Tracking & Source Attribution")
with col2:
    if st.button("⚙️ Configuration", use_container_width=True):
        st.session_state.config_expanded = not st.session_state.config_expanded

# Configuration modal/expander
if st.session_state.config_expanded:
    with st.expander("⚙️ Configuration", expanded=True):
        st.subheader("CAS Configuration")
        cas_endpoint = st.text_input(
            "CAS Endpoint",
            value=os.getenv("CAS_ENDPOINT", ""),
            placeholder="https://cas-endpoint.com",
            help="CAS REST API endpoint URL",
            key="config_cas_endpoint",
        )

        cas_api_key = st.text_input(
            "CAS API Key",
            value=os.getenv("CAS_API_KEY", ""),
            type="password",
            help="CAS API key for authentication",
            key="config_cas_api_key",
        )

        st.subheader("LLM Configuration")
        llm_endpoint = st.text_input(
            "LLM Endpoint",
            value=os.getenv("LLM_ENDPOINT", ""),
            help="OpenShift AI LLM endpoint (vLLM OpenAI-compatible API)",
            key="config_llm_endpoint",
        )

        # Initialize button
        if st.button(
            "🔌 Initialize Components", type="primary", use_container_width=True
        ):
            if not cas_endpoint or not llm_endpoint:
                st.error("Please provide CAS Endpoint and LLM Endpoint")
            else:
                # Update environment
                os.environ["CAS_ENDPOINT"] = cas_endpoint
                os.environ["CAS_API_KEY"] = cas_api_key
                os.environ["LLM_ENDPOINT"] = llm_endpoint

                # Create default agent automatically
                default_agent = {
                    "name": "CAS Agent",
                    "endpoint": cas_endpoint,
                    "api_key": cas_api_key,
                }
                st.session_state.cas_agents = [default_agent]
                st.session_state.selected_agent = default_agent

                # Initialize RAG flow
                st.session_state.rag_flow = initialize_rag_flow(
                    vector_store_id=st.session_state.selected_vector_store,
                    cas_endpoint=cas_endpoint,
                    cas_api_key=cas_api_key,
                    llm_endpoint=llm_endpoint,
                )

                # Close configuration modal
                st.session_state.config_expanded = False

                st.success("✅ Components initialized! Agent created automatically.")
                st.rerun()

# Main layout with three columns
col_left, col_main, col_right = st.columns([1, 2, 1])

# Left sidebar panel
with col_left:
    st.markdown("### 🔍 CAS Search Panel")

    # Agent Status
    st.markdown("#### 1️⃣ Agent Status")
    if st.session_state.selected_agent:
        st.success(f"✅ {st.session_state.selected_agent['name']}")
        if st.button("🗑️ Clear Chat", use_container_width=True):
            st.session_state.messages = []
            st.session_state.progress_updates = []
            st.session_state.current_sources = []
            st.session_state.processing_metrics = {}
            st.rerun()
    else:
        st.warning("⚠️ No agent configured")

    st.divider()

    # Vector Store Selection
    st.markdown("#### 2️⃣ Vector Store")

    if st.session_state.selected_agent:
        load_button = st.button("🔄 Load Stores", use_container_width=True)
        
        if load_button:
            try:
                use_mcp = os.getenv("CAS_USE_MCP", "false").lower() == "true"
                cas_client = CASClient(
                    endpoint=st.session_state.selected_agent["endpoint"],
                    api_key=st.session_state.selected_agent["api_key"],
                    use_mcp=use_mcp,
                )

                with st.spinner("🔄 Loading..."):
                    stores = cas_client.list_vector_stores(limit=50)
                    st.session_state.vector_stores = stores

                    if stores:
                        st.success(f"✅ Loaded {len(stores)}")
                    else:
                        st.warning("⚠️ No stores found")

            except Exception as e:
                st.error(f"❌ Failed: {str(e)}")

        if st.session_state.vector_stores:
            store_options = {
                store.get("id", store.get("vector_store_id", "")): store.get(
                    "name", store.get("id", "Unknown")
                )
                for store in st.session_state.vector_stores
            }
            selected_store_id = st.selectbox(
                "Select Store",
                options=list(store_options.keys()),
                format_func=lambda x: f"{store_options[x]}",
                key="vector_store_selector",
            )
            st.session_state.selected_vector_store = selected_store_id
        else:
            manual_store_id = st.text_input(
                "Vector Store ID",
                value=os.getenv("CAS_VECTOR_STORE_ID", ""),
                key="manual_vector_store_input",
            )
            if manual_store_id:
                st.session_state.selected_vector_store = manual_store_id
    else:
        st.info("💡 Initialize first")

    st.divider()

    # Status
    st.markdown("#### 📊 Status")
    if st.session_state.rag_flow:
        st.success("🟢 Ready")
    else:
        st.warning("🟡 Not initialized")

    if st.session_state.selected_vector_store:
        st.info(f"Store: {st.session_state.selected_vector_store[:20]}...")

# Main chat interface
with col_main:
    st.markdown("### 💬 Chat Interface")
    
    # Display processing metrics if available
    if st.session_state.processing_metrics:
        render_processing_metrics()
    
    # Display chat messages
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])

    # Chat input
    if prompt := st.chat_input("Ask a question about your enterprise documents..."):
        # Add user message
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        # Check if components are initialized
        if not st.session_state.selected_agent:
            with st.chat_message("assistant"):
                st.error("⚠️ Please initialize components first")
        elif not st.session_state.selected_vector_store:
            with st.chat_message("assistant"):
                st.error("⚠️ Please select a vector store")
        elif not st.session_state.rag_flow:
            with st.chat_message("assistant"):
                st.warning("⚠️ RAG flow not initialized")
        else:
            # Execute RAG query
            with st.chat_message("assistant"):
                try:
                    # Clear previous progress
                    st.session_state.progress_updates = []
                    st.session_state.current_sources = []
                    
                    with st.spinner("Processing your request..."):
                        # Execute RAG flow (ALWAYS goes through CAS)
                        result = st.session_state.rag_flow.run(prompt)
                        
                        # Display response
                        st.markdown(result.response)
                        
                        # Store sources and metrics
                        st.session_state.current_sources = result.sources
                        st.session_state.processing_metrics = {
                            'processing_time': result.processing_time,
                            'sources_count': len(result.sources),
                            'cas_search_count': result.cas_search_count
                        }
                    
                    # Add assistant message
                    st.session_state.messages.append({
                        "role": "assistant",
                        "content": result.response,
                        "sources": [s.to_dict() for s in result.sources],
                        "metrics": st.session_state.processing_metrics
                    })
                    
                    st.rerun()

                except Exception as e:
                    error_msg = f"Error: {str(e)}"
                    st.error(error_msg)
                    st.session_state.messages.append(
                        {"role": "assistant", "content": error_msg}
                    )

# Right panel - Progress Tracker and Source Attribution
with col_right:
    st.markdown("### 📊 Real-time Tracking")
    
    # Progress Tracker
    render_progress_tracker()
    
    st.divider()
    
    # Source Attribution Panel
    if st.session_state.current_sources:
        render_source_attribution_panel(st.session_state.current_sources)

# Footer
st.markdown("---")
st.markdown("**Fusion Agentic Assistance Platform Enhanced** - OpenShift AI + CAS with Real-time Tracking & Source Attribution")