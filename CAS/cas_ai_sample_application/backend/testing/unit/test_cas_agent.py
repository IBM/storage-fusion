"""
Unit tests for CASClient

Covers:
  - URL construction (_build_cas_url, _build_mcp_url)
  - Configuration state (configure / is_configured)
  - SSE response parsing (_parse_mcp_sse_response)
  - Vector store listing (list_vector_stores)
  - Vector store search (search_vector_store)
  - File content retrieval (get_file_content)

Naming convention:  test_<thing_under_test>_<condition>_<expected_outcome>
TC-ID convention:   TC-CAS-<NNN> — matches the project's test catalogue format
                    used in cas_cli_chatbot and the IBM Fusion CAS Assistant codebase.

All external HTTP calls are patched at the module level
(agents.cas_client.requests.post) so no real network traffic is made.
"""

from io import BytesIO
from unittest.mock import MagicMock, patch

import pytest

from agents.cas_client import CASClient
from utils.exceptions import CASClientError


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_sse_response(*result_dicts, status_code=200):
    """Build a mock requests.Response that streams SSE data: lines.

    Each positional argument is a dict that will be serialised as a
    JSON-RPC 2.0 response carrying a ``result`` field.
    """
    import json
    lines = []
    for i, payload in enumerate(result_dicts, start=1):
        msg = {"jsonrpc": "2.0", "id": i, "result": payload}
        lines.append(f"data: {json.dumps(msg)}".encode())
        lines.append(b"")  # blank line separator

    mock_resp = MagicMock()
    mock_resp.status_code = status_code
    mock_resp.raise_for_status = MagicMock()
    mock_resp.iter_lines.return_value = lines
    return mock_resp


def _make_sse_error_response(error_msg, status_code=200):
    """Build a mock response that returns a JSON-RPC error in the SSE stream."""
    import json
    msg = {"jsonrpc": "2.0", "id": 1, "error": {"code": -32603, "message": error_msg}}
    lines = [f"data: {json.dumps(msg)}".encode(), b""]
    mock_resp = MagicMock()
    mock_resp.status_code = status_code
    mock_resp.raise_for_status = MagicMock()
    mock_resp.iter_lines.return_value = lines
    return mock_resp


# ---------------------------------------------------------------------------
# _extract_host  (TC-CAS-001..005 — URL normalisation logic)
# ---------------------------------------------------------------------------

class TestExtractHost:
    """Test host extraction and URL normalisation logic."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_extract_host_strips_path_from_full_cas_url(self) -> None:
        """TC-CAS-001: An endpoint containing /cas/api/v1 must return only the bare host."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="https://example.com/cas/api/v1")

        host = agent._extract_host()

        assert host == "https://example.com"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_extract_host_promotes_bare_domain_to_https(self) -> None:
        """TC-CAS-002: A bare domain (no scheme, no path) must be returned as https://host."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com/")

        host = agent._extract_host()

        assert host == "https://example.com"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_extract_host_strips_https_prefix(self) -> None:
        """TC-CAS-003: https:// prefix in the endpoint must produce https://host (no double scheme)."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="https://example.com")

        host = agent._extract_host()

        assert host == "https://example.com"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_extract_host_normalizes_http_to_https(self) -> None:
        """TC-CAS-004: http:// prefix must be upgraded to https:// — all CAS traffic is TLS."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="http://example.com")

        host = agent._extract_host()

        assert host == "https://example.com"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_extract_host_raises_when_endpoint_not_configured(self) -> None:
        """TC-CAS-005: CASClientError (not a bare ValueError) must be raised when no endpoint is set."""
        agent = CASClient()

        with pytest.raises(CASClientError):
            agent._extract_host()


# ---------------------------------------------------------------------------
# _build_mcp_url
# ---------------------------------------------------------------------------

class TestBuildMcpUrl:
    """Test MCP streamable URL construction."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_build_mcp_url_produces_streamable_path(self) -> None:
        """TC-CAS-019: MCP URL must end with /cas/api/v1/mcp-streamable/."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="https://example.com")

        url = agent._build_mcp_url()

        assert url == "https://example.com/cas/api/v1/mcp-streamable/"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_build_mcp_url_strips_existing_path(self) -> None:
        """TC-CAS-020: An endpoint that already includes /cas/api/v1 must still produce the MCP URL."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="https://example.com/cas/api/v1")

        url = agent._build_mcp_url()

        assert url == "https://example.com/cas/api/v1/mcp-streamable/"


# ---------------------------------------------------------------------------
# configure / is_configured
# ---------------------------------------------------------------------------

class TestConfigure:
    """Test credential injection and configuration-state tracking."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_configure_marks_agent_configured_when_values_present(self) -> None:
        """TC-CAS-006: Agent must report configured=True when both token and domain are set."""
        agent = CASClient()

        agent.configure(api_key="token", cas_endpoint="example.com")

        assert agent.is_configured() is True

    @pytest.mark.unit
    @pytest.mark.cas
    def test_configure_not_configured_when_token_missing(self) -> None:
        """TC-CAS-007: Missing api_key must leave the agent in an unconfigured state."""
        agent = CASClient()

        agent.configure(cas_endpoint="example.com")

        assert agent.is_configured() is False

    @pytest.mark.unit
    @pytest.mark.cas
    def test_configure_not_configured_when_domain_missing(self) -> None:
        """TC-CAS-008: Missing cas_endpoint must leave the agent in an unconfigured state."""
        agent = CASClient()

        agent.configure(api_key="token")

        assert agent.is_configured() is False

    @pytest.mark.unit
    @pytest.mark.cas
    def test_configure_can_be_called_incrementally(self) -> None:
        """TC-CAS-009: Two configure() calls each with one field must result in a configured agent."""
        agent = CASClient()

        agent.configure(api_key="token")
        agent.configure(cas_endpoint="example.com")

        assert agent.is_configured() is True


# ---------------------------------------------------------------------------
# _parse_mcp_sse_response
# ---------------------------------------------------------------------------

class TestParseMcpSseResponse:
    """Test SSE stream parsing."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_parse_sse_returns_last_result(self) -> None:
        """TC-CAS-021: The last result in the SSE stream must be returned."""
        import json
        lines = [
            b"data: " + json.dumps({"jsonrpc": "2.0", "id": 1, "result": {"first": True}}).encode(),
            b"",
            b"data: " + json.dumps({"jsonrpc": "2.0", "id": 2, "result": [{"id": "vs-1"}]}).encode(),
            b"",
        ]
        mock_resp = MagicMock()
        mock_resp.iter_lines.return_value = lines

        result = CASClient._parse_mcp_sse_response(mock_resp)

        assert result == [{"id": "vs-1"}]

    @pytest.mark.unit
    @pytest.mark.cas
    def test_parse_sse_returns_error_dict_when_no_result(self) -> None:
        """TC-CAS-022: An SSE stream with only an error message must return an error dict."""
        import json
        lines = [
            b"data: " + json.dumps({"jsonrpc": "2.0", "id": 1, "error": {"code": -32602, "message": "bad params"}}).encode(),
            b"",
        ]
        mock_resp = MagicMock()
        mock_resp.iter_lines.return_value = lines

        result = CASClient._parse_mcp_sse_response(mock_resp)

        assert isinstance(result, dict)
        assert "error" in result

    @pytest.mark.unit
    @pytest.mark.cas
    def test_parse_sse_skips_non_data_lines(self) -> None:
        """TC-CAS-023: Lines not starting with 'data:' must be ignored."""
        import json
        lines = [
            b"event: message",
            b"data: " + json.dumps({"jsonrpc": "2.0", "id": 1, "result": "ok"}).encode(),
            b"",
        ]
        mock_resp = MagicMock()
        mock_resp.iter_lines.return_value = lines

        result = CASClient._parse_mcp_sse_response(mock_resp)

        assert result == "ok"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_parse_sse_returns_none_on_empty_stream(self) -> None:
        """TC-CAS-024: An empty SSE stream must return None."""
        mock_resp = MagicMock()
        mock_resp.iter_lines.return_value = []

        result = CASClient._parse_mcp_sse_response(mock_resp)

        assert result is None


# ---------------------------------------------------------------------------
# list_vector_stores
# ---------------------------------------------------------------------------

class TestGetVectorStores:
    """Test vector store list retrieval via MCP."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_list_vector_stores_returns_error_when_not_configured(self) -> None:
        """TC-CAS-010: Unconfigured client must return an error dict without making any HTTP call."""
        agent = CASClient()

        result = agent.list_vector_stores()

        assert result == {
            "status": "error",
            "error": "Client not configured. Check CAS_API_KEY and CAS_ENDPOINT in .env",
        }

    @pytest.mark.unit
    @pytest.mark.cas
    def test_list_vector_stores_returns_success_on_200(self) -> None:
        """TC-CAS-011: SSE stream with a data list must return status=success and the list."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = _make_sse_response([{"id": "vs-1"}, {"id": "vs-2"}])

        with patch("agents.cas_client.requests.post", return_value=mock_response) as mock_post:
            result = agent.list_vector_stores()

        assert result["status"] == "success"
        assert result["vector_stores"] == [{"id": "vs-1"}, {"id": "vs-2"}]
        mock_post.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.cas
    def test_list_vector_stores_returns_error_on_http_error(self) -> None:
        """TC-CAS-012: HTTP 403 must return status=error with the user-facing CRAC message."""
        import requests as req
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = MagicMock()
        mock_response.status_code = 403
        http_err = req.exceptions.HTTPError(response=mock_response)
        mock_response.raise_for_status.side_effect = http_err

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.list_vector_stores()

        assert result["status"] == "error"
        assert "CRAC" in result["error"]

    @pytest.mark.unit
    @pytest.mark.cas
    def test_list_vector_stores_handles_data_wrapped_response(self) -> None:
        """TC-CAS-013: MCP result wrapped in {data: [...]} must be unwrapped correctly."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = _make_sse_response({"data": [{"id": "vs-1"}]})

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.list_vector_stores()

        assert result["status"] == "success"
        assert result["vector_stores"] == [{"id": "vs-1"}]


# ---------------------------------------------------------------------------
# search_vector_store
# ---------------------------------------------------------------------------

class TestSearchVectorStore:
    """Test vector store search via MCP."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_search_vector_store_returns_error_when_not_configured(self) -> None:
        """TC-CAS-014: Unconfigured agent must return an error dict without making any HTTP call."""
        agent = CASClient()

        result = agent.search_vector_store(vector_store_id="vs-1", query="hello")

        assert result == {
            "status": "error",
            "error": "Client not configured. Check CAS_API_KEY and CAS_ENDPOINT in .env",
        }

    @pytest.mark.unit
    @pytest.mark.cas
    def test_search_vector_store_returns_success_on_200(self) -> None:
        """TC-CAS-015: SSE stream with result list must return status=success with the data."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        raw_results = [{"score": {"combined_probability_score": 0.9}, "text": "doc1"}]
        mock_response = _make_sse_response(raw_results)

        with patch("agents.cas_client.requests.post", return_value=mock_response) as mock_post:
            result = agent.search_vector_store(vector_store_id="vs-1", query="hello")

        assert result["status"] == "success"
        assert result["data"] == raw_results
        mock_post.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.cas
    def test_search_vector_store_filters_by_min_score(self) -> None:
        """TC-CAS-016: Results below min_score threshold must be removed client-side before returning."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        raw_results = [
            {"score": {"combined_probability_score": 0.9}, "text": "high"},
            {"score": {"combined_probability_score": 0.3}, "text": "low"},
        ]
        mock_response = _make_sse_response(raw_results)

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.search_vector_store(vector_store_id="vs-1", query="hello", min_score=0.5)

        assert result["status"] == "success"
        assert len(result["data"]) == 1
        assert result["data"][0]["text"] == "high"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_search_vector_store_returns_error_on_http_error(self) -> None:
        """TC-CAS-017: HTTP 500 must return status=error with the user-facing server error message."""
        import requests as req
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = MagicMock()
        mock_response.status_code = 500
        http_err = req.exceptions.HTTPError(response=mock_response)
        mock_response.raise_for_status.side_effect = http_err

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.search_vector_store(vector_store_id="vs-1", query="hello")

        assert result["status"] == "error"
        assert "namespace" in result["error"]

    @pytest.mark.unit
    @pytest.mark.cas
    def test_search_vector_store_sends_correct_mcp_arguments(self) -> None:
        """TC-CAS-018: MCP arguments must include vector_store_id, query, max_num_results, filters."""
        import json as json_mod
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = _make_sse_response([])

        with patch("agents.cas_client.requests.post", return_value=mock_response) as mock_post:
            agent.search_vector_store(
                vector_store_id="vs-1",
                query="hello",
                max_num_results=5,
                filters={"tag": "finance"},
            )

        _, kwargs = mock_post.call_args
        body = kwargs["json"]
        assert body["method"] == "tools/call"
        args = body["params"]["arguments"]
        assert args["vector_store_id"] == "vs-1"
        assert args["query"] == "hello"
        assert args["max_num_results"] == 5
        assert args["filters"] == {"tag": "finance"}
        assert args["auth_token"] == "token"


# ---------------------------------------------------------------------------
# get_file_content
# ---------------------------------------------------------------------------

class TestGetFileContent:
    """Test file content retrieval via MCP get_vector_store_file_content tool."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_get_file_content_returns_error_when_not_configured(self) -> None:
        """TC-CAS-025: Unconfigured client must return error without making any HTTP call."""
        agent = CASClient()

        result = agent.get_file_content(vector_store_id="vs-1", file_id="123")

        assert result["status"] == "error"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_get_file_content_returns_string_content(self) -> None:
        """TC-CAS-026: String result from MCP must be returned as content."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = _make_sse_response("full document text here")

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.get_file_content(vector_store_id="vs-1", file_id="123")

        assert result["status"] == "success"
        assert result["content"] == "full document text here"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_get_file_content_extracts_content_from_dict(self) -> None:
        """TC-CAS-027: Dict result with a 'content' key must be unwrapped."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = _make_sse_response({"content": "file body", "metadata": {}})

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.get_file_content(vector_store_id="vs-1", file_id="123")

        assert result["status"] == "success"
        assert result["content"] == "file body"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_get_file_content_sends_correct_tool_name(self) -> None:
        """TC-CAS-028: MCP payload must use tool name 'get_vector_store_file_content'."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = _make_sse_response("content")

        with patch("agents.cas_client.requests.post", return_value=mock_response) as mock_post:
            agent.get_file_content(vector_store_id="vs-1", file_id="456")

        _, kwargs = mock_post.call_args
        body = kwargs["json"]
        assert body["params"]["name"] == "get_vector_store_file_content"
        assert body["params"]["arguments"]["file_id"] == "456"
        assert body["params"]["arguments"]["vector_store_id"] == "vs-1"


# ---------------------------------------------------------------------------
# _unwrap_mcp_result  (envelope unwrapping)
# ---------------------------------------------------------------------------

class TestUnwrapMcpResult:
    """Test the MCP tool-call result envelope unwrapper."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_unwrap_returns_structured_content(self) -> None:
        """TC-CAS-029: structuredContent must be preferred and returned as the payload."""
        from agents.cas_client import _unwrap_mcp_result
        envelope = {
            "content": [{"type": "text", "text": '{"data":[]}'}],
            "structuredContent": {"data": [{"id": "vs-1"}], "object": "list"},
            "isError": False,
        }
        result = _unwrap_mcp_result(envelope)
        assert result == {"data": [{"id": "vs-1"}], "object": "list"}

    @pytest.mark.unit
    @pytest.mark.cas
    def test_unwrap_falls_back_to_content_text_json(self) -> None:
        """TC-CAS-030: When structuredContent is absent, content[0].text JSON must be parsed."""
        from agents.cas_client import _unwrap_mcp_result
        envelope = {
            "content": [{"type": "text", "text": '{"data":[{"id":"vs-1"}]}'}],
            "isError": False,
        }
        result = _unwrap_mcp_result(envelope)
        assert result == {"data": [{"id": "vs-1"}]}

    @pytest.mark.unit
    @pytest.mark.cas
    def test_unwrap_returns_error_dict_when_is_error_true(self) -> None:
        """TC-CAS-031: isError=true must return an error dict with the content text."""
        from agents.cas_client import _unwrap_mcp_result
        envelope = {
            "content": [{"type": "text", "text": "1 validation error for call[list_vector_stores]\nserver_url\n  Unexpected keyword argument"}],
            "isError": True,
        }
        result = _unwrap_mcp_result(envelope)
        assert isinstance(result, dict)
        assert "error" in result
        assert "validation error" in result["error"]

    @pytest.mark.unit
    @pytest.mark.cas
    def test_unwrap_passes_through_plain_list(self) -> None:
        """TC-CAS-032: A plain list (no envelope) must pass through unchanged."""
        from agents.cas_client import _unwrap_mcp_result
        data = [{"id": "vs-1"}, {"id": "vs-2"}]
        assert _unwrap_mcp_result(data) is data

    @pytest.mark.unit
    @pytest.mark.cas
    def test_unwrap_passes_through_plain_dict(self) -> None:
        """TC-CAS-033: A plain dict without isError/content keys passes through unchanged."""
        from agents.cas_client import _unwrap_mcp_result
        data = {"data": [{"id": "vs-1"}]}
        assert _unwrap_mcp_result(data) is data


class TestListVectorStoresEnvelope:
    """Test list_vector_stores with the real MCP envelope shape."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_list_vector_stores_unwraps_structured_content(self) -> None:
        """TC-CAS-034: list_vector_stores must unwrap structuredContent envelope correctly."""
        import json as json_mod
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        stores = [{"id": "lisatest", "name": "lisatest"}, {"id": "cas-testbucket-1", "name": "cas-testbucket-1"}]
        envelope = {
            "content": [{"type": "text", "text": json_mod.dumps({"data": stores, "object": "list"})}],
            "structuredContent": {"data": stores, "object": "list"},
            "isError": False,
        }
        mock_response = _make_sse_response(envelope)

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.list_vector_stores()

        assert result["status"] == "success"
        assert len(result["vector_stores"]) == 2
        assert result["vector_stores"][0]["id"] == "lisatest"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_list_vector_stores_returns_error_on_is_error_envelope(self) -> None:
        """TC-CAS-035: isError=true envelope must surface as status=error."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        envelope = {
            "content": [{"type": "text", "text": "1 validation error for call[list_vector_stores]\nserver_url\n  Unexpected keyword argument"}],
            "isError": True,
        }
        mock_response = _make_sse_response(envelope)

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.list_vector_stores()

        assert result["status"] == "error"
        assert "error" in result
