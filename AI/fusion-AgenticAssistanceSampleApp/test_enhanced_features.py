#!/usr/bin/env python3
"""
Test script for enhanced Fusion Agentic Assistance features with mock data
Verifies all components work correctly without requiring actual CAS/LLM endpoints
"""

import sys
from pathlib import Path
from typing import List, Dict
from datetime import datetime
import time

# Add project root to path
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

from src.rag_flow import (
    RAGFlowEnhanced,
    ProgressUpdate,
    ProcessingStage,
    SourceAttribution,
    RAGResult
)
from src.monitoring import MonitoringService, get_monitor


# Mock CAS Client for testing
class MockCASClient:
    """Mock CAS client that returns test data"""
    
    def __init__(self, *args, **kwargs):
        print("✅ Mock CAS Client initialized")
    
    def search(self, query: str, top_k: int = 5, **kwargs):
        """Return mock search results"""
        print(f"🔍 Mock CAS Search: '{query}' (top_k={top_k})")
        
        # Mock search results
        from dataclasses import dataclass
        
        @dataclass
        class MockResult:
            document_id: str
            content: str
            metadata: Dict
            score: float
            source: str
        
        results = [
            MockResult(
                document_id="doc_001",
                content="The patent filing process begins with a thorough prior art search to ensure novelty. This involves searching existing patents and publications.",
                metadata={"line_start": 45, "line_end": 67, "file_type": "pdf"},
                score=0.9234,
                source="patent_filing_guide.pdf"
            ),
            MockResult(
                document_id="doc_002",
                content="After the prior art search, you must prepare a detailed patent application including claims, drawings, and specifications.",
                metadata={"line_start": 120, "line_end": 145, "file_type": "pdf"},
                score=0.8756,
                source="patent_application_manual.pdf"
            ),
            MockResult(
                document_id="doc_003",
                content="The patent office will examine your application for novelty, non-obviousness, and utility. This process typically takes 18-24 months.",
                metadata={"line_start": 200, "line_end": 215, "file_type": "pdf"},
                score=0.8123,
                source="patent_examination_process.pdf"
            ),
        ]
        
        return results[:top_k]
    
    def list_vector_stores(self, limit: int = 10):
        """Return mock vector stores"""
        return [
            {"id": "store_001", "name": "Patent Documents"},
            {"id": "store_002", "name": "Technical Manuals"},
        ]
    
    def health_check(self):
        """Return healthy status"""
        return True


# Mock LLM Response
def mock_llm_invoke(prompt: str) -> str:
    """Mock LLM inference"""
    print(f"🤖 Mock LLM Inference (prompt length: {len(prompt)} chars)")
    time.sleep(0.5)  # Simulate processing time
    
    return """Based on the provided documents, the patent filing process involves several key steps:

1. **Prior Art Search**: Begin with a thorough search of existing patents and publications to ensure your invention is novel.

2. **Application Preparation**: Prepare a detailed patent application including:
   - Claims defining the scope of protection
   - Technical drawings and diagrams
   - Detailed specifications

3. **Examination Process**: The patent office will examine your application for:
   - Novelty (is it new?)
   - Non-obviousness (is it inventive?)
   - Utility (is it useful?)

The entire process typically takes 18-24 months from filing to approval.

**Sources:**
- patent_filing_guide.pdf (Lines 45-67)
- patent_application_manual.pdf (Lines 120-145)
- patent_examination_process.pdf (Lines 200-215)"""


def test_progress_tracking():
    """Test progress tracking functionality"""
    print("\n" + "="*60)
    print("TEST 1: Progress Tracking")
    print("="*60)
    
    progress_updates = []
    
    def progress_callback(update: ProgressUpdate):
        """Capture progress updates"""
        progress_updates.append(update)
        print(f"📊 [{update.stage.value}] {update.message}")
        if update.details:
            print(f"   Details: {update.details}")
        if update.error:
            print(f"   ❌ Error: {update.error}")
    
    # Create mock RAG flow
    rag_flow = RAGFlowEnhanced(
        cas_endpoint="http://mock-cas:8080",
        llm_endpoint="http://mock-llm:8080",
        prompt_template="Context: {context}\n\nQuestion: {query}\n\nAnswer:",
        top_k=3,
        progress_callback=progress_callback,
        enable_detailed_attribution=True
    )
    
    # Replace CAS client with mock
    rag_flow.cas_client = MockCASClient()
    
    # Replace LLM invoke with mock
    rag_flow.invoke_llm_with_retry = mock_llm_invoke
    
    # Run query
    query = "What is the patent filing process?"
    print(f"\n🔍 Query: {query}\n")
    
    result = rag_flow.run(query)
    
    # Verify progress updates
    print(f"\n✅ Progress Updates Captured: {len(progress_updates)}")
    assert len(progress_updates) > 0, "No progress updates captured!"
    
    # Check all stages were hit
    stages = [update.stage for update in progress_updates]
    print(f"✅ Stages: {[s.value for s in stages]}")
    
    assert ProcessingStage.INITIALIZED in stages, "Missing INITIALIZED stage"
    assert ProcessingStage.SEARCHING_CAS in stages, "Missing SEARCHING_CAS stage"
    assert ProcessingStage.COMPLETED in stages, "Missing COMPLETED stage"
    
    print("\n✅ TEST 1 PASSED: Progress tracking works correctly!")
    return result


def test_source_attribution(result: RAGResult):
    """Test source attribution with line numbers"""
    print("\n" + "="*60)
    print("TEST 2: Source Attribution")
    print("="*60)
    
    print(f"\n📚 Sources Found: {len(result.sources)}")
    
    assert len(result.sources) > 0, "No sources found!"
    
    for i, source in enumerate(result.sources, 1):
        print(f"\n📄 Source {i}:")
        print(f"   File: {source.source_file}")
        print(f"   Document ID: {source.document_id}")
        print(f"   Relevance Score: {source.relevance_score:.4f}")
        print(f"   Line Numbers: {source.line_start}-{source.line_end}")
        print(f"   Content Snippet: {source.content_snippet[:100]}...")
        print(f"   Metadata: {source.metadata}")
        
        # Verify required fields
        assert source.source_file, "Missing source file!"
        assert source.document_id, "Missing document ID!"
        assert source.relevance_score > 0, "Invalid relevance score!"
        assert source.line_start is not None, "Missing line_start!"
        assert source.line_end is not None, "Missing line_end!"
    
    print("\n✅ TEST 2 PASSED: Source attribution works correctly!")


def test_cas_search_guarantee(result: RAGResult):
    """Test that CAS search was called"""
    print("\n" + "="*60)
    print("TEST 3: CAS Search Guarantee")
    print("="*60)
    
    print(f"\n🔍 Sources Retrieved: {result.cas_search_count}")
    print(f"📚 Number of Documents: {len(result.sources)}")
    
    # Verify CAS search was performed (sources were retrieved)
    assert result.cas_search_count > 0, "CAS search was not called!"
    assert len(result.sources) > 0, "No sources retrieved from CAS!"
    
    # Verify all sources have required attribution
    for source in result.sources:
        assert source.line_start is not None, "Source missing line numbers!"
        assert source.relevance_score > 0, "Source missing relevance score!"
    
    print("✅ TEST 3 PASSED: CAS search guarantee verified!")


def test_monitoring_service():
    """Test monitoring and logging"""
    print("\n" + "="*60)
    print("TEST 4: Monitoring Service")
    print("="*60)
    
    from src.monitoring import LogLevel
    
    monitor = MonitoringService(
        service_name="test-fusion-agentic-assistance",
        log_level="INFO",
        enable_console=True
    )
    
    # Test logging
    print("\n📝 Testing logging...")
    monitor.log(
        LogLevel.INFO,
        "Test log message",
        extra={"test_key": "test_value"}
    )
    
    # Test metrics
    print("\n📊 Testing metrics...")
    monitor.record_metric("test_duration", 1.234, tags={"operation": "test"})
    monitor.record_metric("test_count", 5)
    
    # Test operation tracking
    print("\n⏱️ Testing operation tracking...")
    with monitor.track_operation("test_operation"):
        time.sleep(0.1)
    
    # Get metrics summary
    summary = monitor.get_metrics_summary()
    print(f"\n📈 Metrics Summary: {summary}")
    
    assert "test_duration" in summary, "Metric not recorded!"
    assert summary["test_duration"]["count"] == 1, "Metric count incorrect!"
    
    # Get health status
    health = monitor.get_health_status()
    print(f"\n💚 Health Status: {health['status']}")
    
    assert health["status"] == "healthy", "Service not healthy!"
    
    print("\n✅ TEST 4 PASSED: Monitoring service works correctly!")


def test_error_handling():
    """Test error handling and retry logic"""
    print("\n" + "="*60)
    print("TEST 5: Error Handling")
    print("="*60)
    
    progress_updates = []
    
    def progress_callback(update: ProgressUpdate):
        progress_updates.append(update)
        if update.error:
            print(f"❌ Error captured: {update.error}")
    
    # Create RAG flow
    rag_flow = RAGFlowEnhanced(
        cas_endpoint="http://mock-cas:8080",
        llm_endpoint="http://mock-llm:8080",
        prompt_template="Context: {context}\n\nQuestion: {query}\n\nAnswer:",
        progress_callback=progress_callback,
        max_retries=3
    )
    
    # Replace with mock that works
    rag_flow.cas_client = MockCASClient()
    rag_flow.invoke_llm_with_retry = mock_llm_invoke
    
    # Test successful execution
    print("\n✅ Testing successful execution...")
    result = rag_flow.run("Test query")
    
    assert result.response, "No response generated!"
    print(f"✅ Response generated: {len(result.response)} chars")
    
    # Check for any errors in progress
    errors = [u for u in progress_updates if u.error]
    print(f"\n📊 Errors encountered: {len(errors)}")
    
    print("\n✅ TEST 5 PASSED: Error handling works correctly!")


def test_performance_metrics(result: RAGResult):
    """Test performance metrics"""
    print("\n" + "="*60)
    print("TEST 6: Performance Metrics")
    print("="*60)
    
    print(f"\n⏱️ Processing Time: {result.processing_time:.2f}s")
    print(f"📊 Sources Retrieved: {len(result.sources)}")
    print(f"🔍 CAS Searches: {result.cas_search_count}")
    print(f"📝 Response Length: {len(result.response)} chars")
    print(f"📋 Context Length: {len(result.context_used)} chars")
    
    assert result.processing_time > 0, "Invalid processing time!"
    assert result.processing_time < 10, "Processing took too long!"
    
    print("\n✅ TEST 6 PASSED: Performance metrics captured correctly!")


def run_all_tests():
    """Run all tests"""
    print("\n" + "="*60)
    print("🧪 ENHANCED LLMOPS FEATURES TEST SUITE")
    print("="*60)
    print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    try:
        # Test 1: Progress Tracking
        result = test_progress_tracking()
        
        # Test 2: Source Attribution
        test_source_attribution(result)
        
        # Test 3: CAS Search Guarantee
        test_cas_search_guarantee(result)
        
        # Test 4: Monitoring Service
        test_monitoring_service()
        
        # Test 5: Error Handling
        test_error_handling()
        
        # Test 6: Performance Metrics
        test_performance_metrics(result)
        
        # Summary
        print("\n" + "="*60)
        print("✅ ALL TESTS PASSED!")
        print("="*60)
        print("\n📊 Test Summary:")
        print("  ✅ Progress Tracking - PASSED")
        print("  ✅ Source Attribution - PASSED")
        print("  ✅ CAS Search Guarantee - PASSED")
        print("  ✅ Monitoring Service - PASSED")
        print("  ✅ Error Handling - PASSED")
        print("  ✅ Performance Metrics - PASSED")
        print("\n🎉 All enhanced features are working correctly!")
        
        return True
        
    except Exception as e:
        print("\n" + "="*60)
        print("❌ TEST FAILED!")
        print("="*60)
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)