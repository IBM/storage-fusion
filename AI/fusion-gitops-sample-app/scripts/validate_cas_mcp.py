#!/usr/bin/env python3
"""
Validate CAS MCP Connection

This script checks:
1. CAS endpoint is accessible
2. CAS MCP endpoint is available
3. Vector store exists
4. Can perform search queries
"""

import os
import sys
import requests
from typing import Dict, Optional

def check_cas_endpoint(endpoint: str, timeout: int = 10) -> bool:
    """Check if CAS endpoint is accessible"""
    print(f"🌐 Checking CAS endpoint: {endpoint}...")
    
    try:
        # Try root endpoint
        response = requests.get(endpoint, timeout=timeout, verify=False)
        if response.status_code in [200, 401, 403]:  # Any response means it's reachable
            print(f"   ✅ CAS endpoint is accessible")
            return True
        else:
            print(f"   ⚠️  CAS endpoint returned status: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"   ❌ Cannot reach CAS endpoint: {e}")
        return False

def check_cas_mcp(endpoint: str, api_key: str, timeout: int = 10) -> bool:
    """Check if CAS MCP endpoint is available"""
    print(f"🔍 Checking CAS MCP endpoint...")
    
    # MCP endpoint typically at /cas/api/v1/mcp or similar
    mcp_endpoints = [
        f"{endpoint.rstrip('/')}/cas/api/v1/mcp",
        f"{endpoint.rstrip('/')}/api/v1/mcp",
        f"{endpoint.rstrip('/')}/mcp"
    ]
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    for mcp_url in mcp_endpoints:
        try:
            # Try to call MCP endpoint
            response = requests.get(mcp_url, headers=headers, timeout=timeout, verify=False)
            if response.status_code == 200:
                print(f"   ✅ CAS MCP endpoint found: {mcp_url}")
                return True
        except:
            continue
    
    print(f"   ⚠️  CAS MCP endpoint not found at standard locations")
    return False

def check_vector_store(endpoint: str, api_key: str, vector_store_id: str, timeout: int = 10) -> bool:
    """Check if vector store exists and is accessible"""
    print(f"📚 Checking vector store: {vector_store_id}...")
    
    # Try to list vector stores or check specific one
    search_url = f"{endpoint.rstrip('/')}/cas/api/v1/vector_stores/{vector_store_id}/search"
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "query": "test",
        "max_num_results": 1
    }
    
    try:
        response = requests.post(
            search_url,
            json=payload,
            headers=headers,
            timeout=timeout,
            verify=False
        )
        
        if response.status_code == 200:
            print(f"   ✅ Vector store '{vector_store_id}' is accessible")
            data = response.json()
            print(f"   📊 Search test successful")
            return True
        elif response.status_code == 404:
            print(f"   ❌ Vector store '{vector_store_id}' not found")
            return False
        elif response.status_code == 401:
            print(f"   ❌ Authentication failed. Check API key.")
            return False
        else:
            print(f"   ⚠️  Vector store check returned status: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"   ❌ Error checking vector store: {e}")
        return False

def test_cas_search(endpoint: str, api_key: str, vector_store_id: str, query: str = "test", timeout: int = 10) -> Optional[Dict]:
    """Test CAS search functionality"""
    print(f"🔍 Testing CAS search with query: '{query}'...")
    
    search_url = f"{endpoint.rstrip('/')}/cas/api/v1/vector_stores/{vector_store_id}/search"
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "query": query,
        "max_num_results": 3
    }
    
    try:
        response = requests.post(
            search_url,
            json=payload,
            headers=headers,
            timeout=timeout,
            verify=False
        )
        
        if response.status_code == 200:
            data = response.json()
            results = data.get("results", [])
            print(f"   ✅ Search successful - Found {len(results)} results")
            if results:
                print(f"   📄 Sample result: {results[0].get('content', '')[:100]}...")
            return data
        else:
            print(f"   ❌ Search failed with status: {response.status_code}")
            print(f"   Response: {response.text[:200]}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"   ❌ Error during search: {e}")
        return None

def main():
    """Main validation function"""
    print("=" * 60)
    print("🔍 CAS MCP Validation")
    print("=" * 60)
    print()
    
    # Configuration from environment
    cas_endpoint = os.getenv("CAS_ENDPOINT", "")
    cas_api_key = os.getenv("CAS_API_KEY", "")
    cas_vector_store_id = os.getenv("CAS_VECTOR_STORE_ID", "test-nmh")
    
    if not cas_endpoint:
        print("❌ CAS_ENDPOINT environment variable not set")
        print("   Set it with: export CAS_ENDPOINT=https://your-cas-endpoint/")
        sys.exit(1)
    
    if not cas_api_key:
        print("❌ CAS_API_KEY environment variable not set")
        print("   Set it with: export CAS_API_KEY=your-api-key")
        sys.exit(1)
    
    results = {
        "endpoint": False,
        "mcp": False,
        "vector_store": False,
        "search": False
    }
    
    # 1. Check endpoint
    results["endpoint"] = check_cas_endpoint(cas_endpoint)
    print()
    
    if not results["endpoint"]:
        print("❌ CAS endpoint not accessible. Check network connectivity.")
        sys.exit(1)
    
    # 2. Check MCP (optional)
    results["mcp"] = check_cas_mcp(cas_endpoint, cas_api_key)
    print()
    
    # 3. Check vector store
    results["vector_store"] = check_vector_store(cas_endpoint, cas_api_key, cas_vector_store_id)
    print()
    
    if not results["vector_store"]:
        print("❌ Vector store not accessible. Check vector store ID and API key.")
        sys.exit(1)
    
    # 4. Test search
    search_result = test_cas_search(cas_endpoint, cas_api_key, cas_vector_store_id)
    results["search"] = search_result is not None
    print()
    
    # Summary
    print("=" * 60)
    print("📊 Validation Summary")
    print("=" * 60)
    print(f"CAS Endpoint:     {'✅' if results['endpoint'] else '❌'}")
    print(f"CAS MCP:          {'✅' if results['mcp'] else '⚠️  (optional)'}")
    print(f"Vector Store:     {'✅' if results['vector_store'] else '❌'}")
    print(f"Search Test:      {'✅' if results['search'] else '❌'}")
    print()
    
    if results["endpoint"] and results["vector_store"] and results["search"]:
        print("✅ All checks passed! CAS is ready.")
        print()
        print("📝 Configuration:")
        print(f"   CAS_ENDPOINT={cas_endpoint}")
        print(f"   CAS_VECTOR_STORE_ID={cas_vector_store_id}")
        print("   CAS_API_KEY=*** (set in environment)")
        sys.exit(0)
    else:
        print("❌ Some checks failed. Please fix the issues above.")
        sys.exit(1)

if __name__ == "__main__":
    # Disable SSL warnings for self-signed certificates
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    main()

