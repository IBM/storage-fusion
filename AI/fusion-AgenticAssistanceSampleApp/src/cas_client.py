"""
CAS (Content-Aware Storage) Client for RAG Retrieval
Integrates with CAS MCP (Model Context Protocol) and REST API for enterprise document retrieval
"""

import os
import sys
import requests
import uuid
from typing import List, Dict, Optional
from dataclasses import dataclass

# Suppress SSL warnings when verify=False
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


@dataclass
class CASSearchResult:
    """Represents a search result from CAS"""

    document_id: str
    content: str
    metadata: Dict
    score: float
    source: str


class CASClient:
    """
    Client for interacting with CAS via MCP (Model Context Protocol) or REST API

    Supports both:
    - MCP Protocol: POST /cas/api/v1/mcp (JSON-RPC 2.0)
    - REST API: POST /cas/api/v1/vector_stores/{id}/search

    Example:
        cas = CASClient(endpoint="https://console-ibm-spectrum-fusion-ns.apps.cas-oregon-rosa.6kdo.p1.openshiftapps.com/")
        results = cas.search(query='What is OpenShift AI architecture?', top_k=5)
    """

    def __init__(
        self,
        endpoint: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout: int = 30,
        use_mcp: bool = True,
        vector_store_id: Optional[str] = None,
        verify_ssl: Optional[bool] = None,
    ):
        """
        Initialize CAS client

        Args:
            endpoint: CAS API endpoint URL (base URL, e.g., https://domain.com/cas)
            api_key: Bearer token for authentication
            timeout: Request timeout in seconds
            use_mcp: Use MCP protocol (True) or REST API (False)
            vector_store_id: Vector store ID for REST API (optional, will be discovered if not provided)
            verify_ssl: Whether to verify SSL certificates (default: True, set to False for self-signed certs)
        """
        self.endpoint = endpoint or os.getenv(
            "CAS_ENDPOINT",
            "https://console-ibm-spectrum-fusion-ns.apps.cas-oregon-rosa.6kdo.p1.openshiftapps.com",
        )
        # Ensure endpoint doesn't have trailing slash for path construction
        self.endpoint = self.endpoint.rstrip("/")
        self.api_key = api_key or os.getenv("CAS_API_KEY")
        self.timeout = timeout
        self.use_mcp = use_mcp
        self.vector_store_id = vector_store_id or os.getenv("CAS_VECTOR_STORE_ID")

        # SSL verification: default to False if CAS_VERIFY_SSL is not set (for self-signed certs)
        if verify_ssl is None:
            verify_ssl_env = os.getenv("CAS_VERIFY_SSL", "false").lower()
            self.verify_ssl = verify_ssl_env in ("true", "1", "yes")
        else:
            self.verify_ssl = verify_ssl

        self.session = requests.Session()
        # Set verify=False on session for self-signed certificates
        # Individual requests can still override this, but this ensures default behavior
        if not self.verify_ssl:
            # Disable SSL verification at session level
            self.session.verify = False

        if self.api_key:
            self.session.headers.update({"Authorization": f"Bearer {self.api_key}"})

        # MCP endpoint
        self.mcp_endpoint = f"{self.endpoint}/cas/api/v1/mcp"
        # REST endpoints (CAS API format)
        self.rest_base = f"{self.endpoint}/cas/api/v1"

    def _search_via_mcp(
        self, query: str, top_k: int = 5, vector_store_id: Optional[str] = None
    ) -> List[CASSearchResult]:
        """
        Search using MCP protocol (JSON-RPC 2.0)
        Simply pass the query to MCP - it will figure out which tool to use

        Args:
            query: Search query string
            top_k: Number of results to return
            vector_store_id: Vector store ID (optional - MCP will handle if not provided)

        Returns:
            List of CASSearchResult objects
        """
        # Build arguments - include vector_store_id if we have it, otherwise let MCP handle it
        # Try to get vector_store_id from cache or auto-discover once
        store_id = vector_store_id or self.vector_store_id

        # Simple auto-discovery if needed (only once, cache it)
        if not store_id and self.api_key:
            try:
                stores = self.list_vector_stores(limit=1)
                if stores and len(stores) > 0:
                    store_id = stores[0].get("id", stores[0].get("vector_store_id", ""))
                    if store_id:
                        self.vector_store_id = store_id  # Cache it
            except Exception:
                # If discovery fails, proceed without it - MCP might handle it
                pass

        # Build arguments - pass query and let MCP figure out the rest
        arguments = {
            "server_url": f"{self.endpoint}/",  # MCP requires trailing slash
            "auth_token": self.api_key or "",
            "query": query,
            "limit": top_k,
        }

        # Add vector_store_id if we have it
        if store_id:
            arguments["vector_store_id"] = store_id

        # MCP JSON-RPC 2.0 request - MCP will route to appropriate tool
        mcp_request = {
            "jsonrpc": "2.0",
            "id": str(uuid.uuid4()),
            "method": "tools/call",
            "params": {
                "name": "search_vector_stores",  # MCP handles tool selection
                "arguments": arguments,
            },
        }

        try:
            response = self.session.post(
                self.mcp_endpoint,
                json=mcp_request,
                timeout=self.timeout,
                headers={"Content-Type": "application/json"},
                verify=self.verify_ssl,
            )
            response.raise_for_status()

            data = response.json()

            # Handle JSON-RPC response
            if "error" in data:
                raise Exception(f"MCP error: {data['error']}")

            result = data.get("result", {})

            # Parse MCP tool result - MCP returns result in content[0].text format
            items = []
            if isinstance(result, dict) and "content" in result:
                # MCP wraps result in content array
                content = result.get("content", [])
                if content and isinstance(content, list) and len(content) > 0:
                    text_content = content[0].get("text", "")
                    if text_content:
                        # Parse the text content (string representation of dict/list)
                        import ast

                        try:
                            parsed = ast.literal_eval(text_content)
                            if isinstance(parsed, dict):
                                # Extract data array from parsed dict
                                if "data" in parsed:
                                    items = parsed["data"]
                                elif "results" in parsed:
                                    items = parsed["results"]
                            elif isinstance(parsed, list):
                                items = parsed
                        except (ValueError, SyntaxError):
                            # If ast fails, try JSON
                            import json

                            try:
                                parsed = json.loads(text_content)
                                if isinstance(parsed, dict) and "data" in parsed:
                                    items = parsed["data"]
                                elif isinstance(parsed, list):
                                    items = parsed
                            except json.JSONDecodeError:
                                pass

            # Fallback: direct result parsing
            if not items:
                if isinstance(result, dict):
                    items = result.get("results", result.get("data", []))
                elif isinstance(result, list):
                    items = result

            results = []
            for item in items:
                # Extract score - can be dict or float
                score_obj = item.get("score", item.get("relevance_score", 0.0))
                if isinstance(score_obj, dict):
                    score_value = score_obj.get("score", 0.0)
                else:
                    score_value = float(score_obj) if score_obj else 0.0

                # Extract content - can be string, list, or dict
                content_raw = item.get("content", item.get("text", ""))
                if isinstance(content_raw, list):
                    # Content is array of objects with 'text' field
                    content_parts = []
                    for c in content_raw:
                        if isinstance(c, dict):
                            content_parts.append(c.get("text", ""))
                        else:
                            content_parts.append(str(c))
                    content_text = "\n".join(content_parts)
                elif isinstance(content_raw, dict):
                    content_text = content_raw.get("text", str(content_raw))
                else:
                    content_text = str(content_raw) if content_raw else ""

                results.append(
                    CASSearchResult(
                        document_id=item.get(
                            "id", item.get("document_id", item.get("file_id", ""))
                        ),
                        content=content_text,
                        metadata=item.get("metadata", {}),
                        score=score_value,
                        source=item.get(
                            "source", item.get("file_name", item.get("filename", ""))
                        ),
                    )
                )

            return results

        except requests.exceptions.RequestException as e:
            raise Exception(f"CAS MCP search failed: {str(e)}")

    def _search_via_rest(
        self,
        query: str,
        top_k: int = 5,
        vector_store_id: Optional[str] = None,
        ranking_options: Optional[Dict] = None,
        enable_source: bool = True,
        enable_content_metadata: bool = True,
    ) -> List[CASSearchResult]:
        """
        Search using REST API (actual CAS API format)

        Args:
            query: Search query string
            top_k: Number of results to return (max_num_results)
            vector_store_id: Vector store ID (required for REST)
            ranking_options: Ranking options dict (e.g., {"ranker": "auto"})
            enable_source: Enable source information in response
            enable_content_metadata: Enable content metadata (includes line numbers)

        Returns:
            List of CASSearchResult objects
        """
        store_id = vector_store_id or self.vector_store_id
        if not store_id:
            raise ValueError("vector_store_id is required for REST API search")

        # CAS API endpoint format: /cas/api/v1/vector_stores/{id}/search
        search_url = f"{self.endpoint}/cas/api/v1/vector_stores/{store_id}/search"

        payload = {
            "query": query,
            "max_num_results": top_k,
            "ranking_options": ranking_options or {"ranker": "auto"},
            "enable_source": enable_source,
            "enable_content_metadata": enable_content_metadata,
        }

        try:
            # Debug: Log the actual URL being called
            print(f"DEBUG: CAS REST search URL: {search_url}", file=sys.stderr)
            print(f"DEBUG: CAS REST payload: {payload}", file=sys.stderr)

            response = self.session.post(
                search_url,
                json=payload,
                timeout=self.timeout,
                headers={
                    "Content-Type": "application/json",
                    "accept": "application/json",
                },
                verify=self.verify_ssl,
            )
            response.raise_for_status()

            data = response.json()
            results = []

            # Parse CAS API response format
            # Response structure: {"data": [{"file_id": "...", "filename": "...", "content": [{"text": "...", "metadata": {...}}], "score": {...}}]}
            items = data.get("data", [])

            for item in items:
                # Extract text from content array with metadata
                content_text = ""
                content_metadata = {}
                content_array = item.get("content", [])

                if content_array and isinstance(content_array, list):
                    # Content is array of objects with "text" and optional "metadata" fields
                    text_parts = []
                    for c in content_array:
                        if c.get("text"):
                            text_parts.append(c.get("text", ""))
                            # Extract metadata from first content item (line numbers, etc.)
                            if not content_metadata and c.get("metadata"):
                                content_metadata = c.get("metadata", {})
                    content_text = "\n".join(text_parts)

                # Extract score
                score_obj = item.get("score", {})
                score_value = (
                    score_obj.get("score", 0.0)
                    if isinstance(score_obj, dict)
                    else float(score_obj) if score_obj else 0.0
                )

                # Extract filename/source
                filename = item.get("filename", item.get("source", ""))

                # Merge item metadata with content metadata
                merged_metadata = item.get("metadata", {})
                merged_metadata.update(content_metadata)

                results.append(
                    CASSearchResult(
                        document_id=item.get("file_id", item.get("id", "")),
                        content=content_text,
                        metadata=merged_metadata,
                        score=score_value,
                        source=filename,
                    )
                )

            return results

        except requests.exceptions.RequestException as e:
            raise Exception(f"CAS REST search failed: {str(e)}")

    def search(
        self,
        query: str,
        top_k: int = 5,
        filters: Optional[Dict] = None,
        search_type: str = "hybrid",
        vector_store_id: Optional[str] = None,
        ranking_options: Optional[Dict] = None,
        enable_source: bool = True,
        enable_content_metadata: bool = False,
    ) -> List[CASSearchResult]:
        """
        Search CAS for relevant documents

        Uses MCP protocol by default, falls back to REST if MCP is disabled.

        Args:
            query: Search query string
            top_k: Number of results to return (max_num_results for REST)
            filters: Optional metadata filters (not used in MCP, kept for compatibility)
            search_type: Type of search (not used in MCP, kept for compatibility)
            vector_store_id: Vector store ID (auto-discovered for MCP if not provided, required for REST)
            ranking_options: Ranking options for REST API (e.g., {"ranker": "auto"})
            enable_source: Enable source information in REST response
            enable_content_metadata: Enable content metadata in REST response

        Returns:
            List of CASSearchResult objects
        """
        if self.use_mcp:
            return self._search_via_mcp(query, top_k, vector_store_id)
        else:
            return self._search_via_rest(
                query,
                top_k,
                vector_store_id,
                ranking_options=ranking_options,
                enable_source=enable_source,
                enable_content_metadata=enable_content_metadata,
            )

    def list_vector_stores(self, limit: int = 10, order: str = "desc") -> List[Dict]:
        """
        List available vector stores (tables)

        Args:
            limit: Maximum number of vector stores to return
            order: Sort order ("asc" or "desc")

        Returns:
            List of vector store dictionaries with id, name, etc.
        """
        if self.use_mcp:
            # Use MCP protocol
            mcp_request = {
                "jsonrpc": "2.0",
                "id": str(uuid.uuid4()),
                "method": "tools/call",
                "params": {
                    "name": "list_vector_stores",
                    "arguments": {
                        "server_url": f"{self.endpoint}/",  # MCP requires trailing slash
                        "auth_token": self.api_key or "",
                    },
                },
            }

            try:
                response = self.session.post(
                    self.mcp_endpoint,
                    json=mcp_request,
                    timeout=self.timeout,
                    verify=self.verify_ssl,
                )
                response.raise_for_status()

                data = response.json()
                if "error" in data:
                    raise Exception(f"MCP error: {data['error']}")

                result = data.get("result", {})

                # MCP tool call result format - result.content[0].text contains the actual data
                if isinstance(result, dict) and "content" in result:
                    content = result.get("content", [])
                    if content and isinstance(content, list) and len(content) > 0:
                        text_content = content[0].get("text", "")
                        if text_content:
                            # Parse the text content (it's a string representation of dict/list)
                            import ast

                            try:
                                # Try parsing as Python literal (dict/list)
                                parsed = ast.literal_eval(text_content)
                                if isinstance(parsed, dict):
                                    # Extract data array from parsed dict
                                    if "data" in parsed:
                                        return parsed["data"]
                                    elif "vector_stores" in parsed:
                                        return parsed["vector_stores"]
                                elif isinstance(parsed, list):
                                    return parsed
                            except (ValueError, SyntaxError):
                                # If ast fails, try JSON
                                import json

                                try:
                                    parsed = json.loads(text_content)
                                    if isinstance(parsed, dict) and "data" in parsed:
                                        return parsed["data"]
                                    elif isinstance(parsed, list):
                                        return parsed
                                except json.JSONDecodeError:
                                    pass

                # Fallback: Check if result contains vector_stores array directly
                if isinstance(result, dict):
                    if "vector_stores" in result:
                        return result["vector_stores"]
                    elif isinstance(result.get("data"), list):
                        return result["data"]
                elif isinstance(result, list):
                    return result

                return []

            except requests.exceptions.RequestException as e:
                raise Exception(f"CAS MCP list_vector_stores failed: {str(e)}")
        else:
            # Use REST API - actual CAS API format
            # GET /cas/api/v1/vector_stores?limit=10&order=desc
            list_url = f"{self.rest_base}/vector_stores"
            params = {"limit": limit, "order": order}

            try:
                # Debug logging
                print(f"DEBUG: CAS REST list_vector_stores", file=sys.stderr)
                print(f"  URL: {list_url}", file=sys.stderr)
                print(f"  Params: {params}", file=sys.stderr)
                print(f"  Headers: accept=application/json", file=sys.stderr)
                print(f"  API Key: {'***' + self.api_key[-10:] if self.api_key else 'Not set'}", file=sys.stderr)
                print(f"  Verify SSL: {self.verify_ssl}", file=sys.stderr)

                response = self.session.get(
                    list_url,
                    params=params,
                    timeout=self.timeout,
                    headers={"accept": "application/json"},
                    verify=self.verify_ssl,
                )
                
                print(f"DEBUG: Response status: {response.status_code}", file=sys.stderr)
                print(f"DEBUG: Response headers: {dict(response.headers)}", file=sys.stderr)
                
                response.raise_for_status()
                data = response.json()
                
                print(f"DEBUG: Response data: {data}", file=sys.stderr)

                # Parse actual CAS API response format
                # Response: {"data": [{"id": "test-nmh", "name": "test-nmh", ...}], "object": "list"}
                result = data.get("data", [])
                print(f"DEBUG: Returning {len(result)} vector stores", file=sys.stderr)
                return result
                
            except requests.exceptions.RequestException as e:
                print(f"DEBUG: Request failed: {str(e)}", file=sys.stderr)
                if hasattr(e, 'response') and e.response is not None:
                    print(f"DEBUG: Response text: {e.response.text}", file=sys.stderr)
                raise Exception(f"CAS REST list_vector_stores failed: {str(e)}")

    def get_document(self, document_id: str) -> Optional[Dict]:
        """
        Retrieve a specific document by ID

        Args:
            document_id: Document identifier

        Returns:
            Document data or None if not found
        """
        doc_url = f"{self.endpoint.rstrip('/')}/api/v1/documents/{document_id}"

        try:
            response = self.session.get(
                doc_url, timeout=self.timeout, verify=self.verify_ssl
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException:
            return None

    def get_file_content(
        self,
        file_id: str,
        vector_store_id: Optional[str] = None,
        enable_content_metadata: bool = True,
        enable_source: bool = True,
    ) -> Optional[Dict]:
        """
        Retrieve file content from vector store using content API

        API: GET /cas/api/v1/vector_stores/{vector_store_id}/files/{file_id}/content

        Args:
            file_id: File ID to retrieve
            vector_store_id: Vector store ID (uses self.vector_store_id if not provided)
            enable_content_metadata: Enable content metadata in response (default: True)
            enable_source: Enable source information in response (default: True)

        Returns:
            File content data or None if not found
        """
        store_id = vector_store_id or self.vector_store_id
        if not store_id:
            raise ValueError("vector_store_id is required for get_file_content")

        content_url = (
            f"{self.rest_base}/vector_stores/{store_id}/files/{file_id}/content"
        )

        params = {
            "enable_content_metadata": enable_content_metadata,
            "enable_source": enable_source,
        }

        try:
            response = self.session.get(
                content_url,
                params=params,
                timeout=self.timeout,
                headers={"accept": "application/json"},
                verify=self.verify_ssl,
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            raise Exception(f"Failed to retrieve file content: {str(e)}")

    def health_check(self) -> bool:
        """
        Check if CAS service is healthy

        Returns:
            True if service is available
        """
        # Try MCP endpoint first, then health endpoint
        try:
            if self.use_mcp:
                # Try MCP initialize as health check
                mcp_request = {
                    "jsonrpc": "2.0",
                    "id": str(uuid.uuid4()),
                    "method": "initialize",
                    "params": {},
                }
                response = self.session.post(
                    self.mcp_endpoint,
                    json=mcp_request,
                    timeout=5,
                    verify=self.verify_ssl,
                )
                return response.status_code == 200
            else:
                # Try REST health endpoint
                health_url = f"{self.endpoint}/health"
                response = self.session.get(
                    health_url, timeout=5, verify=self.verify_ssl
                )
                return response.status_code == 200
        except requests.exceptions.RequestException:
            return False
