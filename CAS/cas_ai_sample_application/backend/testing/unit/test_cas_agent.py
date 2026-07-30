"""
Unit tests for CASClient

Covers:
  - URL construction (_build_cas_url)
  - Configuration state (configure / is_configured)
  - Vector store listing (list_vector_stores)
  - Vector store search (search_vector_store)

Naming convention:  test_<thing_under_test>_<condition>_<expected_outcome>
TC-ID convention:   TC-CAS-<NNN> — matches the project's test catalogue format
                    used in cas_cli_chatbot and the IBM Fusion CAS Assistant codebase.

All external HTTP calls are patched at the module level
(agents.cas_client.requests.*) so no real network traffic is made.
"""

from unittest.mock import MagicMock, patch

import pytest

from agents.cas_client import CASClient
from utils.exceptions import CASClientError


# ---------------------------------------------------------------------------
# _build_cas_url
# ---------------------------------------------------------------------------

class TestBuildCasUrl:
    """Test URL normalisation and construction logic."""

    @pytest.mark.unit
    @pytest.mark.cas
    def test_build_cas_url_uses_existing_api_path(self) -> None:
        """TC-CAS-001: Domain already containing /cas/api/v1 must not be re-wrapped."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="https://example.com/cas/api/v1")

        url = agent._build_cas_url("/vector_stores")

        assert url == "https://example.com/cas/api/v1/vector_stores"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_build_cas_url_normalizes_domain_without_path(self) -> None:
        """TC-CAS-002: Bare domain (no scheme, no path) must be promoted to https with CAS path."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com/")

        url = agent._build_cas_url("/vector_stores")

        assert url == "https://example.com/cas/api/v1/vector_stores"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_build_cas_url_strips_https_prefix(self) -> None:
        """TC-CAS-003: https:// prefix must be stripped before the /cas/api/v1 path is appended."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="https://example.com")

        url = agent._build_cas_url("/vector_stores")

        assert url == "https://example.com/cas/api/v1/vector_stores"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_build_cas_url_strips_http_prefix(self) -> None:
        """TC-CAS-004: http:// prefix must also be stripped — all CAS requests are sent over https."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="http://example.com")

        url = agent._build_cas_url("/vector_stores")

        assert url == "https://example.com/cas/api/v1/vector_stores"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_build_cas_url_raises_when_domain_missing(self) -> None:
        """TC-CAS-005: CASClientError (not a bare ValueError) must be raised when no endpoint is set."""
        agent = CASClient()

        with pytest.raises(CASClientError):
            agent._build_cas_url("/vector_stores")


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
# list_vector_stores
# ---------------------------------------------------------------------------

class TestGetVectorStores:
    """Test vector store list retrieval and response normalisation."""

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
        """TC-CAS-011: HTTP 200 with a data-wrapped list must return status=success and the list."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"data": [{"id": "vs-1"}, {"id": "vs-2"}]}

        with patch("agents.cas_client.requests.get", return_value=mock_response) as mock_get:
            result = agent.list_vector_stores()

        assert result["status"] == "success"
        assert result["vector_stores"] == [{"id": "vs-1"}, {"id": "vs-2"}]
        # Verify exactly one GET was issued — guards against accidental retry loops.
        mock_get.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.cas
    def test_list_vector_stores_returns_error_on_non_200(self) -> None:
        """TC-CAS-012: Non-200 response must return status=error with the HTTP status code."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = MagicMock()
        mock_response.status_code = 403
        mock_response.text = "Forbidden"

        with patch("agents.cas_client.requests.get", return_value=mock_response):
            result = agent.list_vector_stores()

        assert result["status"] == "error"
        assert "403" in result["error"]
        assert result["http_status"] == 403

    @pytest.mark.unit
    @pytest.mark.cas
    def test_list_vector_stores_handles_list_response(self) -> None:
        """TC-CAS-013: Some CAS versions return a plain list — must be handled without KeyError."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = [{"id": "vs-1"}]

        with patch("agents.cas_client.requests.get", return_value=mock_response):
            result = agent.list_vector_stores()

        assert result["status"] == "success"
        assert result["vector_stores"] == [{"id": "vs-1"}]


# ---------------------------------------------------------------------------
# search_vector_store
# ---------------------------------------------------------------------------

class TestSearchVectorStore:
    """Test vector store search, score filtering, and payload construction."""

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
        """TC-CAS-015: HTTP 200 must return status=success with the raw result list."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        raw_results = [{"score": {"combined_probability_score": 0.9}, "text": "doc1"}]
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"data": raw_results}

        with patch("agents.cas_client.requests.post", return_value=mock_response) as mock_post:
            result = agent.search_vector_store(vector_store_id="vs-1", query="hello")

        assert result["status"] == "success"
        assert result["data"] == raw_results
        # Verify exactly one POST was issued.
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
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"data": raw_results}

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.search_vector_store(vector_store_id="vs-1", query="hello", min_score=0.5)

        assert result["status"] == "success"
        assert len(result["data"]) == 1
        assert result["data"][0]["text"] == "high"

    @pytest.mark.unit
    @pytest.mark.cas
    def test_search_vector_store_returns_error_on_non_200(self) -> None:
        """TC-CAS-017: Non-200 response must return status=error with the HTTP status code."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = MagicMock()
        mock_response.status_code = 500
        mock_response.text = "Internal Server Error"

        with patch("agents.cas_client.requests.post", return_value=mock_response):
            result = agent.search_vector_store(vector_store_id="vs-1", query="hello")

        assert result["status"] == "error"
        assert "500" in result["error"]
        assert result["http_status"] == 500

    @pytest.mark.unit
    @pytest.mark.cas
    def test_search_vector_store_includes_optional_payload_fields(self) -> None:
        """TC-CAS-018: Optional (key word args) kwargs must appear in the POST body when explicitly provided."""
        agent = CASClient()
        agent.configure(api_key="token", cas_endpoint="example.com")

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"data": []}

        with patch("agents.cas_client.requests.post", return_value=mock_response) as mock_post:
            agent.search_vector_store(
                vector_store_id="vs-1",
                query="hello",
                max_num_results=5,
                filters={"tag": "finance"},
            )

        _, kwargs = mock_post.call_args
        payload = kwargs["json"]
        assert payload["max_num_results"] == 5
        assert payload["filters"] == {"tag": "finance"}
        assert payload["enable_source"] is True
        assert payload["enable_content_metadata"] is True
