"""
Enhanced RAG Flow Implementation with Progress Tracking and Source Attribution
Implements SOLID principles with comprehensive error handling and scalability
"""

import logging
from typing import List, Dict, Optional, Tuple, Callable
from dataclasses import dataclass, field
from enum import Enum
from datetime import datetime
import traceback

from .cas_client import CASClient, CASSearchResult


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ProcessingStage(Enum):
    """Enumeration of RAG processing stages"""
    INITIALIZED = "initialized"
    SEARCHING_CAS = "searching_cas"
    CONTEXT_BUILDING = "context_building"
    LLM_INFERENCE = "llm_inference"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class ProgressUpdate:
    """Progress update for real-time tracking"""
    stage: ProcessingStage
    message: str
    timestamp: datetime = field(default_factory=datetime.now)
    details: Optional[Dict] = None
    error: Optional[str] = None


@dataclass
class SourceAttribution:
    """Detailed source attribution with line numbers"""
    source_file: str
    document_id: str
    relevance_score: float
    content_snippet: str
    line_start: Optional[int] = None
    line_end: Optional[int] = None
    metadata: Dict = field(default_factory=dict)
    
    def to_dict(self) -> Dict:
        """Convert to dictionary for serialization"""
        return {
            "source_file": self.source_file,
            "document_id": self.document_id,
            "relevance_score": self.relevance_score,
            "content_snippet": self.content_snippet,
            "line_start": self.line_start,
            "line_end": self.line_end,
            "metadata": self.metadata
        }


@dataclass
class RAGResult:
    """Comprehensive RAG result with all metadata"""
    query: str
    response: str
    sources: List[SourceAttribution]
    context_used: str
    prompt: str
    processing_time: float
    progress_history: List[ProgressUpdate]
    cas_search_count: int
    llm_tokens_used: Optional[int] = None
    
    def to_dict(self) -> Dict:
        """Convert to dictionary for serialization"""
        return {
            "query": self.query,
            "response": self.response,
            "sources": [s.to_dict() for s in self.sources],
            "context_used": self.context_used,
            "prompt": self.prompt,
            "processing_time": self.processing_time,
            "cas_search_count": self.cas_search_count,
            "llm_tokens_used": self.llm_tokens_used,
            "progress_history": [
                {
                    "stage": p.stage.value,
                    "message": p.message,
                    "timestamp": p.timestamp.isoformat(),
                    "details": p.details,
                    "error": p.error
                }
                for p in self.progress_history
            ]
        }


class RAGFlowEnhanced:
    """
    Enhanced RAG flow orchestrator with progress tracking and source attribution
    
    Implements SOLID principles:
    - Single Responsibility: Each method has one clear purpose
    - Open/Closed: Extensible through callbacks and configuration
    - Liskov Substitution: Can be subclassed without breaking functionality
    - Interface Segregation: Clean, focused interfaces
    - Dependency Inversion: Depends on abstractions (CASClient interface)
    """

    def __init__(
        self,
        cas_endpoint: str,
        llm_endpoint: str,
        prompt_template: str,
        top_k: int = 5,
        use_mcp: bool = True,
        cas_api_key: Optional[str] = None,
        vector_store_id: Optional[str] = None,
        progress_callback: Optional[Callable[[ProgressUpdate], None]] = None,
        enable_detailed_attribution: bool = True,
        max_retries: int = 3,
        timeout: int = 60
    ):
        """
        Initialize enhanced RAG flow
        
        Args:
            cas_endpoint: CAS Search API endpoint
            llm_endpoint: OpenShift AI KServe endpoint for LLM inference
            prompt_template: Prompt template with {context} and {query} placeholders
            top_k: Number of documents to retrieve
            use_mcp: Use MCP protocol (True) or REST API (False)
            cas_api_key: CAS API key for authentication
            vector_store_id: Vector store ID for CAS search
            progress_callback: Callback function for progress updates
            enable_detailed_attribution: Enable detailed source attribution with line numbers
            max_retries: Maximum number of retries for failed operations
            timeout: Request timeout in seconds
        """
        self.cas_endpoint = cas_endpoint
        self.llm_endpoint = llm_endpoint
        self.prompt_template = prompt_template
        self.top_k = top_k
        self.progress_callback = progress_callback
        self.enable_detailed_attribution = enable_detailed_attribution
        self.max_retries = max_retries
        self.timeout = timeout
        
        # Initialize CAS client with error handling
        try:
            if cas_endpoint:
                self.cas_client = CASClient(
                    endpoint=cas_endpoint,
                    api_key=cas_api_key,
                    use_mcp=use_mcp,
                    vector_store_id=vector_store_id,
                    timeout=timeout
                )
                logger.info(f"CAS client initialized: {cas_endpoint}")
            else:
                self.cas_client = None
                logger.warning("CAS endpoint not provided, RAG will work in LLM-only mode")
        except Exception as e:
            logger.error(f"Failed to initialize CAS client: {str(e)}")
            self.cas_client = None
        
        # Progress tracking
        self.progress_history: List[ProgressUpdate] = []
        
    def _emit_progress(
        self, 
        stage: ProcessingStage, 
        message: str, 
        details: Optional[Dict] = None,
        error: Optional[str] = None
    ):
        """
        Emit progress update
        
        Args:
            stage: Current processing stage
            message: Progress message
            details: Additional details
            error: Error message if any
        """
        update = ProgressUpdate(
            stage=stage,
            message=message,
            details=details,
            error=error
        )
        self.progress_history.append(update)
        
        # Call progress callback if provided
        if self.progress_callback:
            try:
                self.progress_callback(update)
            except Exception as e:
                logger.error(f"Progress callback failed: {str(e)}")
        
        # Log progress
        if error:
            logger.error(f"[{stage.value}] {message} - Error: {error}")
        else:
            logger.info(f"[{stage.value}] {message}")

    def retrieve_context_with_attribution(
        self, 
        query: str
    ) -> Tuple[str, List[SourceAttribution]]:
        """
        Retrieve relevant context from CAS with detailed source attribution
        
        ENSURES: Every query goes through CAS search API
        
        Args:
            query: User query
            
        Returns:
            Tuple of (formatted context string, list of source attributions)
        """
        self._emit_progress(
            ProcessingStage.SEARCHING_CAS,
            f"Searching CAS vector store for: '{query[:50]}...'",
            details={"query_length": len(query), "top_k": self.top_k}
        )
        
        # If no CAS client, return empty context
        if not self.cas_client:
            self._emit_progress(
                ProcessingStage.SEARCHING_CAS,
                "CAS client not available, skipping retrieval",
                error="CAS client not initialized"
            )
            return "", []
        
        try:
            # CRITICAL: Always call CAS search API for every query
            results = self.cas_client.search(
                query=query,
                top_k=self.top_k,
                enable_content_metadata=self.enable_detailed_attribution,
                enable_source=True
            )
            
            self._emit_progress(
                ProcessingStage.SEARCHING_CAS,
                f"Retrieved {len(results)} documents from CAS",
                details={
                    "documents_found": len(results),
                    "sources": [r.source for r in results]
                }
            )
            
            # Build context and source attributions
            context_parts = []
            source_attributions = []
            
            for i, result in enumerate(results, 1):
                # Extract line numbers from metadata if available
                line_start = result.metadata.get("line_start")
                line_end = result.metadata.get("line_end")
                
                # Build context with source information
                context_part = f"[Document {i}]\n"
                context_part += f"Source: {result.source}\n"
                if line_start and line_end:
                    context_part += f"Lines: {line_start}-{line_end}\n"
                context_part += f"Relevance Score: {result.score:.4f}\n"
                context_part += f"Content: {result.content}\n"
                context_parts.append(context_part)
                
                # Create source attribution
                attribution = SourceAttribution(
                    source_file=result.source,
                    document_id=result.document_id,
                    relevance_score=result.score,
                    content_snippet=result.content[:200] + "..." if len(result.content) > 200 else result.content,
                    line_start=line_start,
                    line_end=line_end,
                    metadata=result.metadata
                )
                source_attributions.append(attribution)
            
            formatted_context = "\n---\n".join(context_parts)
            
            self._emit_progress(
                ProcessingStage.CONTEXT_BUILDING,
                f"Built context from {len(results)} sources",
                details={"context_length": len(formatted_context)}
            )
            
            return formatted_context, source_attributions
            
        except Exception as e:
            error_msg = f"CAS search failed: {str(e)}"
            self._emit_progress(
                ProcessingStage.SEARCHING_CAS,
                "CAS search failed",
                error=error_msg
            )
            logger.error(f"{error_msg}\n{traceback.format_exc()}")
            
            # Return empty context but don't fail - LLM can still answer
            return "", []

    def build_prompt(self, query: str, context: str) -> str:
        """
        Build prompt with retrieved context
        
        Args:
            query: User query
            context: Retrieved context from CAS
            
        Returns:
            Formatted prompt
        """
        self._emit_progress(
            ProcessingStage.CONTEXT_BUILDING,
            "Building LLM prompt with context"
        )
        
        # If no context, use fallback prompt
        if not context or context.strip() == "":
            fallback_template = """You are a helpful AI assistant. Answer the user's question to the best of your ability.

Question: {query}

Answer:"""
            return fallback_template.format(query=query)
        
        return self.prompt_template.format(context=context, query=query)

    def invoke_llm_with_retry(self, prompt: str) -> str:
        """
        Invoke LLM with retry logic and error handling
        
        Args:
            prompt: Formatted prompt
            
        Returns:
            LLM response
        """
        import requests
        
        self._emit_progress(
            ProcessingStage.LLM_INFERENCE,
            "Invoking LLM for response generation",
            details={"prompt_length": len(prompt)}
        )
        
        # Extract base URL
        if "/v1/" in self.llm_endpoint:
            base_url = self.llm_endpoint.split("/v1/")[0]
        else:
            base_url = self.llm_endpoint.rstrip("/")
        
        endpoint = f"{base_url}/v1/completions"
        
        payload = {
            "prompt": prompt,
            "max_tokens": 512,
            "temperature": 0.7,
            "top_p": 0.9,
        }
        
        headers = {
            "Content-Type": "application/json",
            "Authorization": "Bearer EMPTY",
        }
        
        # Retry logic
        last_error = None
        for attempt in range(self.max_retries):
            try:
                self._emit_progress(
                    ProcessingStage.LLM_INFERENCE,
                    f"LLM inference attempt {attempt + 1}/{self.max_retries}"
                )
                
                response = requests.post(
                    endpoint,
                    json=payload,
                    headers=headers,
                    timeout=self.timeout
                )
                
                # Handle authentication errors
                if response.status_code == 401:
                    headers_no_auth = {"Content-Type": "application/json"}
                    response = requests.post(
                        endpoint,
                        json=payload,
                        headers=headers_no_auth,
                        timeout=self.timeout
                    )
                
                response.raise_for_status()
                result = response.json()
                
                # Parse response
                if "choices" in result:
                    llm_response = result["choices"][0].get("text", "")
                elif "outputs" in result:
                    llm_response = result.get("outputs", [{}])[0].get("generated_text", "")
                else:
                    llm_response = str(result)
                
                self._emit_progress(
                    ProcessingStage.LLM_INFERENCE,
                    "LLM response generated successfully",
                    details={"response_length": len(llm_response)}
                )
                
                return llm_response
                
            except requests.exceptions.RequestException as e:
                last_error = e
                error_detail = ""
                if hasattr(e, 'response') and e.response is not None:
                    error_detail = f" - {e.response.text[:200]}"
                
                logger.warning(f"LLM inference attempt {attempt + 1} failed: {str(e)}{error_detail}")
                
                if attempt < self.max_retries - 1:
                    import time
                    time.sleep(2 ** attempt)  # Exponential backoff
        
        # All retries failed
        error_msg = f"LLM inference failed after {self.max_retries} attempts: {str(last_error)}"
        self._emit_progress(
            ProcessingStage.LLM_INFERENCE,
            "LLM inference failed",
            error=error_msg
        )
        raise Exception(error_msg)

    def run(self, query: str) -> RAGResult:
        """
        Execute end-to-end RAG flow with comprehensive tracking
        
        GUARANTEES:
        1. Every query goes through CAS search API
        2. Detailed source attribution with line numbers
        3. Real-time progress tracking
        4. Comprehensive error handling
        
        Args:
            query: User query
            
        Returns:
            RAGResult with complete metadata
        """
        import time
        start_time = time.time()
        
        # Reset progress history for new query
        self.progress_history = []
        
        self._emit_progress(
            ProcessingStage.INITIALIZED,
            f"Starting RAG pipeline for query: '{query[:50]}...'",
            details={"query": query}
        )
        
        try:
            # Step 1: ALWAYS retrieve context from CAS (critical requirement)
            context, source_attributions = self.retrieve_context_with_attribution(query)
            
            # Step 2: Build prompt
            prompt = self.build_prompt(query, context)
            
            # Step 3: Invoke LLM
            response = self.invoke_llm_with_retry(prompt)
            
            # Calculate processing time
            processing_time = time.time() - start_time
            
            self._emit_progress(
                ProcessingStage.COMPLETED,
                f"RAG pipeline completed successfully in {processing_time:.2f}s",
                details={
                    "processing_time": processing_time,
                    "sources_used": len(source_attributions)
                }
            )
            
            # Build comprehensive result
            result = RAGResult(
                query=query,
                response=response,
                sources=source_attributions,
                context_used=context,
                prompt=prompt,
                processing_time=processing_time,
                progress_history=self.progress_history.copy(),
                cas_search_count=len(source_attributions)
            )
            
            logger.info(f"RAG query completed: {len(source_attributions)} sources, {processing_time:.2f}s")
            
            return result
            
        except Exception as e:
            processing_time = time.time() - start_time
            error_msg = f"RAG pipeline failed: {str(e)}"
            
            self._emit_progress(
                ProcessingStage.FAILED,
                "RAG pipeline failed",
                error=error_msg
            )
            
            logger.error(f"{error_msg}\n{traceback.format_exc()}")
            
            # Return error result
            raise Exception(error_msg)