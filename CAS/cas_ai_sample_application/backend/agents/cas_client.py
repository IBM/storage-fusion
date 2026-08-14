"""
CAS Client — Content Aware Storage Client.

Responsibilities:
  1. Normalise a raw user-supplied endpoint string into a clean host URL.
  2. Call the CAS MCP streamable endpoint (JSON-RPC 2.0 over SSE) for all
     vector store operations.
  3. Expose three public methods — list_vector_stores, search_vector_store,
     get_file_content — with stable return shapes so callers never change.

Transport layer
---------------
All three CAS tools go through a single ``_call_mcp_tool()`` helper that
speaks JSON-RPC 2.0 to ``/cas/api/v1/mcp-streamable/``.  The helper is
intentionally generic — passing a different ``mcp_url`` lets you call any
MCP-compatible endpoint without touching the public methods.

The streamable endpoint returns SSE.  ``_parse_mcp_sse_response()`` reads
every ``data:`` line and returns the ``result`` field from the last complete
JSON-RPC message, or an ``{"error": ...}`` dict if only an error arrived.

Credentials are injected after construction via configure() so a single
CASClient can be re-configured per request without passing secrets through
every call chain.
"""

from typing import Any, Dict, Optional
import json
import logging
import os
import requests
import urllib3

from utils.exceptions import CASClientError

logger = logging.getLogger(__name__)

# CAS clusters ship with self-signed certificates. Set CAS_VERIFY_SSL=true
# only if your cluster has a trusted certificate installed.
_CAS_VERIFY_SSL = os.getenv("CAS_VERIFY_SSL", "false").lower() == "true"
if not _CAS_VERIFY_SSL:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Returned by every public method when the client has not been configured yet.
# Kept as a module-level constant so the string is never duplicated.
_NOT_CONFIGURED = "Client not configured. Check CAS_API_KEY and CAS_ENDPOINT in .env"

# Incrementing counter gives every JSON-RPC call a unique id within the
# process lifetime. MCP only requires uniqueness per in-flight request.
_rpc_id: int = 0


def _next_rpc_id() -> int:
    global _rpc_id
    _rpc_id += 1
    return _rpc_id


def _unwrap_mcp_result(result: Any) -> Any:
    """Unwrap the MCP tool-call result envelope into the actual payload.

    The JSON-RPC ``result`` field from the CAS MCP streamable endpoint has
    the shape::

        {
          "content":         [{"type": "text", "text": "<json-string>"}],
          "structuredContent": { ... actual data ... },
          "isError":         false
        }

    ``structuredContent`` is the parsed payload when ``isError`` is false.
    ``content[0].text`` is a JSON string of the same data and is used as a
    fallback when ``structuredContent`` is absent.

    When ``isError`` is true, returns ``{"error": "<message from content>"}``
    so callers can surface it uniformly.

    If ``result`` does not look like a tool-call envelope (e.g. it's already
    a plain list or a plain data dict), it is returned unchanged so existing
    code that handles the older direct-result shape keeps working.
    """
    if not isinstance(result, dict):
        return result

    # Plain data dict — not an envelope (no isError key)
    if "isError" not in result and "content" not in result:
        return result

    if result.get("isError"):
        # Extract the error message from content[0].text
        content = result.get("content", [])
        msg = content[0].get("text", "MCP tool reported an error") if content else "MCP tool reported an error"
        return {"error": msg}

    # Happy path: prefer structuredContent, fall back to parsing content[0].text
    structured = result.get("structuredContent")
    if structured is not None:
        return structured

    content = result.get("content", [])
    if content and isinstance(content[0], dict):
        raw_text = content[0].get("text", "")
        try:
            return json.loads(raw_text)
        except (json.JSONDecodeError, TypeError):
            return raw_text

    return result


class CASClient:
    """CAS Client — talks to IBM Content Aware Storage via MCP streamable."""

    def __init__(self):
        """Initialize CAS client — credentials must be set via configure()."""
        self._configured = False
        self._api_key: Optional[str] = None
        self._cas_endpoint: Optional[str] = None

    # ------------------------------------------------------------------
    # URL helpers
    # ------------------------------------------------------------------

    def _extract_host(self) -> str:
        """Return the bare ``https://hostname`` extracted from the configured endpoint.

        Strips any scheme, path, and trailing slash so callers always get a
        clean host root they can append an arbitrary path to.

        Raises:
            CASClientError: if the client has not been configured.
        """
        if not self._cas_endpoint:
            raise CASClientError("CAS endpoint not configured — call configure() first")

        url = self._cas_endpoint.strip().rstrip("/")

        # Drop scheme so we can normalise unconditionally to https.
        if url.startswith("https://"):
            url = url[8:]
        elif url.startswith("http://"):
            url = url[7:]

        # Keep only the host portion — drop any path the user may have included.
        host = url.split("/")[0]
        return f"https://{host}"

    def _build_mcp_url(self) -> str:
        """Return the CAS MCP streamable endpoint URL.

        Raises:
            CASClientError: if the client has not been configured.
        """
        return f"{self._extract_host()}/cas/api/v1/mcp-streamable/"

    # ------------------------------------------------------------------
    # MCP transport
    # ------------------------------------------------------------------

    @staticmethod
    def _parse_mcp_sse_response(response: requests.Response) -> Any:
        """Parse an SSE stream from the MCP streamable endpoint.

        Reads every ``data:`` line, parses each as JSON-RPC 2.0, and returns
        the ``result`` from the *last* complete message.  Returns
        ``{"error": ...}`` if only errors arrived; ``None`` if the stream was
        empty or unparseable.

        Args:
            response: A ``requests.Response`` opened with ``stream=True``.
        """
        last_result = None
        last_error = None

        for raw_line in response.iter_lines():
            if not raw_line:
                continue
            line = raw_line.decode("utf-8") if isinstance(raw_line, bytes) else raw_line
            if not line.startswith("data:"):
                continue
            payload = line[len("data:"):].strip()
            if not payload or payload == "[DONE]":
                continue
            try:
                msg = json.loads(payload)
            except json.JSONDecodeError:
                logger.debug("mcp_sse_non_json line=%r", line[:120])
                continue

            if "error" in msg:
                last_error = msg["error"]
            if "result" in msg:
                last_result = msg["result"]

        if last_error is not None and last_result is None:
            return {"error": last_error}
        return last_result

    def _call_mcp_tool(
        self,
        mcp_url: str,
        tool_name: str,
        arguments: Dict[str, Any],
    ) -> Any:
        """Send a JSON-RPC 2.0 ``tools/call`` to an MCP streamable endpoint.

        Generic transport — passing a different ``mcp_url`` reaches any
        MCP-compatible server with no other code changes.

        Args:
            mcp_url:   Full URL of the MCP streamable endpoint.
            tool_name: MCP tool name to invoke.
            arguments: Tool argument dict.

        Returns:
            Parsed result from ``_parse_mcp_sse_response()``.

        Raises:
            CASClientError: on HTTP / connection / timeout failure.
        """
        payload = {
            "jsonrpc": "2.0",
            "id": _next_rpc_id(),
            "method": "tools/call",
            "params": {"name": tool_name, "arguments": arguments},
        }
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        timeout = int(os.getenv("CAS_TIMEOUT", "30"))
        logger.debug("mcp_call tool=%s url=%s", tool_name, mcp_url)
        try:
            response = requests.post(
                mcp_url,
                json=payload,
                headers=headers,
                stream=True,
                timeout=timeout,
                verify=_CAS_VERIFY_SSL,
            )
            response.raise_for_status()
            return self._parse_mcp_sse_response(response)
        except requests.exceptions.HTTPError as exc:
            status = exc.response.status_code if exc.response is not None else "unknown"
            raise CASClientError(f"MCP tool '{tool_name}' failed with HTTP {status}") from exc
        except requests.exceptions.ConnectionError as exc:
            raise CASClientError(f"Could not connect to MCP endpoint {mcp_url}: {exc}") from exc
        except requests.exceptions.Timeout as exc:
            raise CASClientError(f"MCP request to {mcp_url} timed out") from exc

    def _mcp_arguments(self, extra: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Build the base MCP argument dict (auth_token) for any CAS tool.

        The ``server_url`` parameter was removed — CAS clusters reject it with
        a pydantic validation error (unexpected keyword argument). Only
        ``auth_token`` is required as a base argument. Tool-specific extras are
        merged in via ``extra`` so callers pass one dict, not two.
        """
        args: Dict[str, Any] = {
            "auth_token": self._api_key,
        }
        if extra:
            args.update(extra)
        return args

    # User-facing messages for CAS authentication failures keyed by HTTP status.
    # Centralised here so all CAS error paths produce consistent user guidance.
    _AUTH_ERROR_MESSAGES: Dict[int, str] = {
        401: "Access denied. Your token may be incorrect.",
        403: "Access denied. Your CRAC (Credential and Role Access Control) may not be set up correctly. Please contact your administrator.",
        404: "Endpoint not found. Please check that your endpoint URL is correct.",
        422: "Invalid API key. Please check your CAS token and try again.",
        500: "CAS server error. Your namespace may not be properly configured. Please contact your administrator.",
        503: "Could not reach the endpoint. Please check that your endpoint URL is correct.",
    }

    @staticmethod
    def _error_response(exc: CASClientError) -> Dict[str, Any]:
        """Convert a CASClientError into a ``{"status": "error", "error": "..."}`` dict.

        Checks the exception message for a known HTTP status code and substitutes
        a user-facing message from ``_AUTH_ERROR_MESSAGES`` when one is found.
        """
        msg = str(exc)
        for code, user_msg in CASClient._AUTH_ERROR_MESSAGES.items():
            if str(code) in msg:
                return {"status": "error", "error": user_msg}
        return {"status": "error", "error": msg}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def discover_tools(self) -> Dict[str, Any]:
        """Discover available tools from the CAS MCP server via ``tools/list``.

        Calls the standard MCP ``tools/list`` method on the CAS streamable
        endpoint and returns the tool descriptors the server advertises.

        This is the MCP-native way to learn what tools are available without
        hardcoding them.  Each descriptor has at minimum a ``name`` key and
        optionally ``description`` and ``inputSchema``.

        Returns:
            ``{"status": "success", "tools": [...]}`` where each entry is a
            tool descriptor dict, or ``{"status": "error", "error": "..."}``
            on failure.
        """
        if not self.is_configured():
            return {"status": "error", "error": _NOT_CONFIGURED}
        try:
            payload = {
                "jsonrpc": "2.0",
                "id": _next_rpc_id(),
                "method": "tools/list",
                "params": {},
            }
            headers = {
                "Content-Type": "application/json",
                "Accept": "application/json, text/event-stream",
            }
            timeout = int(os.getenv("CAS_TIMEOUT", "30"))
            logger.debug("mcp_tools_list url=%s", self._build_mcp_url())
            response = requests.post(
                self._build_mcp_url(),
                json=payload,
                headers=headers,
                stream=True,
                timeout=timeout,
                verify=_CAS_VERIFY_SSL,
            )
            response.raise_for_status()
            result = self._parse_mcp_sse_response(response)
            if result is None:
                return {"status": "error", "error": "Empty response from tools/list"}
            if isinstance(result, dict) and "error" in result:
                return {"status": "error", "error": str(result["error"])}

            # MCP tools/list result shape: {"tools": [...]} or a bare list
            if isinstance(result, dict):
                tools = result.get("tools", [])
            elif isinstance(result, list):
                tools = result
            else:
                tools = []

            return {"status": "success", "tools": tools}

        except requests.exceptions.HTTPError as exc:
            status_code = exc.response.status_code if exc.response is not None else "unknown"
            logger.warning("mcp_tools_list_http_error status=%s", status_code)
            return {"status": "error", "error": f"tools/list failed with HTTP {status_code}"}
        except requests.exceptions.ConnectionError as exc:
            logger.warning("mcp_tools_list_connection_error error=%r", exc)
            return {"status": "error", "error": f"Could not connect to MCP endpoint: {exc}"}
        except requests.exceptions.Timeout:
            logger.warning("mcp_tools_list_timeout url=%s", self._build_mcp_url())
            return {"status": "error", "error": "tools/list request timed out"}
        except Exception as exc:
            logger.warning("mcp_tools_list_exception error=%r", exc)
            return {"status": "error", "error": str(exc)}

    def list_vector_stores(self) -> Dict[str, Any]:
        """List available vector stores via the CAS MCP ``list_vector_stores`` tool.

        Returns:
            ``{"status": "success", "vector_stores": [...]}`` or
            ``{"status": "error", "error": "..."}`` on failure.
        """
        if not self.is_configured():
            return {"status": "error", "error": _NOT_CONFIGURED}
        try:
            result = self._call_mcp_tool(
                mcp_url=self._build_mcp_url(),
                tool_name="list_vector_stores",
                arguments=self._mcp_arguments(),
            )
            if result is None:
                return {"status": "error", "error": "Empty response from MCP endpoint"}
            if isinstance(result, dict) and "error" in result:
                return {"status": "error", "error": str(result["error"])}

            # Unwrap the MCP tool result envelope.
            # The JSON-RPC result is {"content": [...], "structuredContent": {...}, "isError": bool}.
            # isError=true means the tool itself reported an error inside content[0].text.
            data = _unwrap_mcp_result(result)
            if isinstance(data, dict) and "error" in data:
                return {"status": "error", "error": str(data["error"])}

            # data is now the actual payload — a list, or {"data": [...]} / {"vector_stores": [...]}
            if isinstance(data, list):
                vector_stores = data
            elif isinstance(data, dict):
                vector_stores = data.get("data", data.get("vector_stores", []))
            else:
                vector_stores = []

            return {"status": "success", "vector_stores": vector_stores}

        except CASClientError as exc:
            logger.warning("list_vector_stores_mcp_error error=%r", exc)
            return self._error_response(exc)
        except Exception as exc:
            logger.warning("list_vector_stores_exception error=%r", exc)
            return {"status": "error", "error": str(exc)}

    def search_vector_store(
        self,
        vector_store_id: str,
        query: str,
        max_num_results: int = 10,
        min_score: float = 0.0,
        filters: Optional[Dict] = None,
        ranking_options: Optional[Dict] = None,
    ) -> Dict[str, Any]:
        """Search a vector store via the CAS MCP ``search_vector_stores`` tool.

        Args:
            vector_store_id: ID of the store to search.
            query:           Search query text.
            max_num_results: Upper limit on results returned (default 10).
            min_score:       Client-side minimum score filter (default 0.0).
            filters:         Optional MCP filters passthrough.
            ranking_options: Optional MCP ranking options passthrough.

        Returns:
            ``{"status": "success", "data": [...]}`` or
            ``{"status": "error", "error": "..."}`` on failure.
        """
        if not self.is_configured():
            return {"status": "error", "error": _NOT_CONFIGURED}
        try:
            # Argument names must match the MCP tool schema exactly.
            # The tool uses "max_num_results" (not "limit").
            extra: Dict[str, Any] = {
                "vector_store_id": vector_store_id,
                "query": query,
                "max_num_results": max_num_results,
            }
            if filters is not None:
                extra["filters"] = filters
            if ranking_options is not None:
                extra["ranking_options"] = ranking_options

            result = self._call_mcp_tool(
                mcp_url=self._build_mcp_url(),
                tool_name="search_vector_stores",
                arguments=self._mcp_arguments(extra),
            )
            if result is None:
                return {"status": "error", "error": "Empty response from MCP endpoint"}

            data = _unwrap_mcp_result(result)
            if isinstance(data, dict) and "error" in data:
                logger.warning("cas_search_mcp_tool_error error=%r", data["error"])
                return {"status": "error", "error": str(data["error"])}

            # Normalise to a flat list then apply the client-side score gate.
            raw_results: list = data if isinstance(data, list) else data.get("data", []) if isinstance(data, dict) else []

            if min_score > 0.0:
                raw_results = [
                    r for r in raw_results
                    if r.get("score", {}).get("combined_probability_score", 0) >= min_score
                ]

            return {"status": "success", "data": raw_results}

        except CASClientError as exc:
            logger.warning("cas_search_mcp_error error=%r", exc)
            return self._error_response(exc)
        except Exception as exc:
            logger.warning("cas_search_exception error=%r", exc)
            return {"status": "error", "error": str(exc)}

    def get_file_content(
        self,
        vector_store_id: str,
        file_id: str,
    ) -> Dict[str, Any]:
        """Retrieve a file's full content via the CAS MCP ``get_vector_store_file_content`` tool.

        Use after ``search_vector_store()`` when you need the complete document.
        The ``file_id`` comes from search result objects.

        Returns:
            ``{"status": "success", "content": "..."}`` or
            ``{"status": "error", "error": "..."}`` on failure.
        """
        if not self.is_configured():
            return {"status": "error", "error": _NOT_CONFIGURED}
        try:
            result = self._call_mcp_tool(
                mcp_url=self._build_mcp_url(),
                tool_name="get_vector_store_file_content",
                arguments=self._mcp_arguments({
                    "vector_store_id": vector_store_id,
                    "file_id": file_id,
                }),
            )
            if result is None:
                return {"status": "error", "error": "Empty response from MCP endpoint"}

            data = _unwrap_mcp_result(result)
            if isinstance(data, dict) and "error" in data:
                return {"status": "error", "error": str(data["error"])}

            # data is the actual file content — a string or a dict with a "content" key.
            if isinstance(data, str):
                content = data
            elif isinstance(data, dict):
                content = data.get("content", json.dumps(data))
            else:
                content = str(data)

            return {"status": "success", "content": content}

        except CASClientError as exc:
            logger.warning("get_file_content_mcp_error error=%r", exc)
            return {"status": "error", "error": str(exc)}
        except Exception as exc:
            logger.warning("get_file_content_exception error=%r", exc)
            return {"status": "error", "error": str(exc)}

    # ------------------------------------------------------------------
    # Configuration
    # ------------------------------------------------------------------

    def configure(self, **config: Any) -> None:
        """Inject credentials into the client.

        Args:
            api_key:      Bearer token for CAS authentication.
            cas_endpoint: Base URL of the CAS cluster.
        """
        self._api_key = config.get("api_key") or self._api_key
        self._cas_endpoint = config.get("cas_endpoint") or self._cas_endpoint

        if self._api_key and self._cas_endpoint:
            self._configured = True
        else:
            logger.warning(
                "cas_client incomplete_configuration endpoint=%r api_key_set=%s",
                self._cas_endpoint,
                bool(self._api_key),
            )

    def is_configured(self) -> bool:
        """Return True if both api_key and cas_endpoint have been supplied."""
        return self._configured
