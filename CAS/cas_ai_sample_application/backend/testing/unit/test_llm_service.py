"""
Unit tests for LLMService

Covers:
  - Constructor                — raises ConfigurationError when required env vars missing
  - _split_questions()         — single vs multi-question detection
  - _build_prompt()            — context ordering and required sections
  - _build_chat_payload()      — OpenAI-compatible payload shape
  - _auth_headers()            — Bearer header present/absent based on LLM_API_KEY
  - _call_llm_stream()         — SSE token extraction, connection errors, HTTP errors
  - _parse_structured_answer() — FULL_ANSWER tag, SOURCE tag, plain-text fallback
  - _get_vector_store_id()     — CAS success/error delegation
  - check_model_compatibility() — format probe: pass, fail, unreachable LLM

Naming convention:  test_<method>_<condition>_<expected_outcome>
TC-ID convention:   TC-LLM-<NNN> — matches the project's test catalogue format
                    used in cas_cli_chatbot and the IBM Fusion CAS Assistant codebase.

LLMService reads env vars in __init__, so every test that constructs one must
set LLM_BASE_URL and LLM_MODEL via monkeypatch (or the `llm_env` fixture below)
to avoid ConfigurationError.  All outbound HTTP calls are patched at the module
level (llm_service.requests.*) so no real network traffic is made.
"""

import json
from typing import Any
from unittest.mock import MagicMock, Mock, patch

import pytest

from llm_service import LLMService
from utils.exceptions import ConfigurationError


# ---------------------------------------------------------------------------
# Fixtures: llm_env, mock_cas_client, svc — defined in conftest.py
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Constructor / ConfigurationError
# ---------------------------------------------------------------------------

class TestLLMServiceConstructor:
    """Test that missing required env vars raise ConfigurationError at construction time."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_constructor_raises_when_llm_base_url_missing(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """TC-LLM-001: Missing LLM_BASE_URL must raise ConfigurationError — not proceed silently."""
        monkeypatch.setenv("LLM_MODEL", "llama3")
        monkeypatch.delenv("LLM_BASE_URL", raising=False)

        with pytest.raises(ConfigurationError) as exc_info:
            LLMService()

        assert "LLM_BASE_URL" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.llm
    def test_constructor_raises_when_llm_model_missing(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """TC-LLM-002: Missing LLM_MODEL must raise ConfigurationError — not proceed silently."""
        monkeypatch.setenv("LLM_BASE_URL", "http://localhost:11434")
        monkeypatch.delenv("LLM_MODEL", raising=False)

        with pytest.raises(ConfigurationError) as exc_info:
            LLMService()

        assert "LLM_MODEL" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.llm
    def test_constructor_strips_trailing_slash_from_base_url(
        self, llm_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """TC-LLM-003: Trailing slash on LLM_BASE_URL must be removed to avoid double-slash in requests."""
        monkeypatch.setenv("LLM_BASE_URL", "http://localhost:11434/")

        svc = LLMService(cas_client=MagicMock())

        assert not svc.llm_base_url.endswith("/")

    @pytest.mark.unit
    @pytest.mark.llm
    def test_constructor_stores_model_name(self, llm_env: None) -> None:
        """TC-LLM-004: llm_model attribute must reflect the LLM_MODEL env var."""
        svc = LLMService(cas_client=MagicMock())

        assert svc.llm_model == "llama3"


# ---------------------------------------------------------------------------
# _build_prompt
# ---------------------------------------------------------------------------

class TestBuildPrompt:
    """Test prompt construction — context ordering, required sections, question inclusion."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_prompt_includes_question(self, svc: LLMService) -> None:
        """TC-LLM-009: The user question must appear verbatim in the assembled prompt."""
        chunks = [{"index": 1, "content": "Some context.", "score": 0.9}]

        prompt = svc._build_prompt("What is the backup policy?", chunks)

        assert "What is the backup policy?" in prompt

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_prompt_includes_source_labels(self, svc: LLMService) -> None:
        """TC-LLM-010: Each chunk must appear under a [Source N] label in the prompt."""
        chunks = [
            {"index": 1, "content": "First chunk.", "score": 0.9},
            {"index": 2, "content": "Second chunk.", "score": 0.8},
        ]

        prompt = svc._build_prompt("Any question?", chunks)

        assert "[Source 1]" in prompt
        assert "[Source 2]" in prompt

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_prompt_orders_chunks_by_score_descending(self, svc: LLMService) -> None:
        """TC-LLM-011: Highest-score chunk must appear before lower-score chunk in the prompt."""
        chunks = [
            {"index": 1, "content": "Low score chunk.", "score": 0.5},
            {"index": 2, "content": "High score chunk.", "score": 0.9},
        ]

        prompt = svc._build_prompt("Any question?", chunks)

        # High score content must appear before low score content in the string.
        assert prompt.index("High score chunk.") < prompt.index("Low score chunk.")

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_prompt_contains_response_section(self, svc: LLMService) -> None:
        """TC-LLM-012: Prompt must end with a 'Response:' marker so the LLM knows where to write."""
        chunks = [{"index": 1, "content": "context", "score": 0.9}]

        prompt = svc._build_prompt("question?", chunks)

        assert "Response:" in prompt

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_prompt_real_weather_chunks(self, svc: LLMService) -> None:
        """TC-LLM-013: Real crisis-domain chunks must be included in the prompt correctly.

        Uses the same filenames from the live CAS response (query: 'weather') to
        verify the prompt is assembled with realistic content.
        """
        # ---------------------------------------------------------------------------
        # Where this data came from
        # ---------------------------------------------------------------------------
        # This data is NOT synthetic — it came from a real CAS API call against the
        # crisis-domain vector store:
        #
        #
        # Raw response (abbreviated):
        #   {
        #     "file_id": "10487824",
        #     "filename": "171_1_1_SC_Helene_Milton_Crisis_Cleanup_Magazine.pdf",
        #     "score": { "combined_probability_score": 0.6519774178010187 },
        #     "content": [{ "type": "image", "text": "...27 degrees...sunny weather..." }]
        #   },
        #   {
        #     "file_id": "10487821",
        #     "filename": "177_1_8_Central_Tornadoes_ds.pdf",
        #     "score": { "combined_probability_score": 0.5805560814424162 },
        #     "content": [{ "type": "text", "text": "PHOTO CREDIT NATIONAL WEATHER SERVICE" }]
        #   }
        #
        # The content strings below are what ChunkProcessor.normalize() produces
        # from those raw content payloads (list-of-typed-dicts → plain text).
        # The scores 0.652 / 0.581 are the real combined_probability_score values.
        #
        # This could have been any real query result — "weather" was just the query
        # run at the time. Swap these values with results from any other real query
        # and the test serves the same purpose.
        # ---------------------------------------------------------------------------
        chunks = [
            {
                "index": 1,
                "content": "Sunny weather forecast for Saturday at 27 degrees.",
                "score": 0.652,   # real combined_probability_score from the API response
                "source": "171_1_1_SC_Helene_Milton_Crisis_Cleanup_Magazine.pdf",
            },
            {
                "index": 2,
                "content": "PHOTO CREDIT NATIONAL WEATHER SERVICE",
                "score": 0.581,   # real combined_probability_score from the API response
                "source": "177_1_8_Central_Tornadoes_ds.pdf",
            },
        ]

        prompt = svc._build_prompt("What does the weather forecast say?", chunks)

        assert "27 degrees" in prompt
        assert "NATIONAL WEATHER SERVICE" in prompt
        assert "What does the weather forecast say?" in prompt
        # Higher score chunk must appear first.
        assert prompt.index("27 degrees") < prompt.index("NATIONAL WEATHER SERVICE")


# ---------------------------------------------------------------------------
# _build_chat_payload
# ---------------------------------------------------------------------------

class TestBuildChatPayload:
    """Test OpenAI-compatible /v1/chat/completions payload construction."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_chat_payload_contains_model(self, svc: LLMService) -> None:
        """TC-LLM-014: Payload must include the configured model name."""
        payload = svc._build_chat_payload("test prompt", stream=False)

        assert payload["model"] == "llama3"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_chat_payload_stream_flag_respected(self, svc: LLMService) -> None:
        """TC-LLM-015: stream=True and stream=False must both be reflected in the payload."""
        assert svc._build_chat_payload("p", stream=True)["stream"] is True
        assert svc._build_chat_payload("p", stream=False)["stream"] is False

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_chat_payload_prompt_in_messages(self, svc: LLMService) -> None:
        """TC-LLM-016: The prompt string must appear as the content of the user message."""
        payload = svc._build_chat_payload("my prompt", stream=False)

        assert payload["messages"][0]["role"] == "user"
        assert payload["messages"][0]["content"] == "my prompt"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_chat_payload_includes_max_tokens(self, svc: LLMService) -> None:
        """TC-LLM-017: max_tokens must be present in the payload so the LLM doesn't run indefinitely."""
        payload = svc._build_chat_payload("p", stream=False)

        assert "max_tokens" in payload
        assert isinstance(payload["max_tokens"], int)


# ---------------------------------------------------------------------------
# _auth_headers
# ---------------------------------------------------------------------------

class TestAuthHeaders:
    """Test Authorization header presence/absence based on LLM_API_KEY."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_auth_headers_empty_when_no_api_key(self, svc: LLMService) -> None:
        """TC-LLM-018: No LLM_API_KEY set must return an empty dict — Ollama-style no-auth."""
        # llm_env fixture deletes LLM_API_KEY; svc.llm_api_key will be "".
        assert svc._auth_headers() == {}

    @pytest.mark.unit
    @pytest.mark.llm
    def test_auth_headers_returns_bearer_when_api_key_set(
        self, llm_env: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """TC-LLM-019: LLM_API_KEY set must produce an Authorization: Bearer <key> header."""
        monkeypatch.setenv("LLM_API_KEY", "test-secret-key")
        svc = LLMService(cas_client=MagicMock())

        headers = svc._auth_headers()

        assert headers == {"Authorization": "Bearer test-secret-key"}


# ---------------------------------------------------------------------------
# _call_llm_stream
# ---------------------------------------------------------------------------

class TestCallLLMStream:
    """Test SSE streaming, token extraction, and error fallback."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_stream_yields_tokens_from_sse_response(self, svc: LLMService) -> None:
        """TC-LLM-020: Valid SSE lines must be decoded and content tokens yielded."""
        token_line = json.dumps({
            "choices": [{"delta": {"content": "Hello"}}]
        }).encode()

        mock_response = MagicMock()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_response.raise_for_status = Mock()
        mock_response.iter_lines.return_value = [
            b"data: " + token_line,
            b"data: [DONE]",
        ]

        with patch("llm_service.requests.post", return_value=mock_response):
            tokens = list(svc._call_llm_stream("test prompt"))

        assert tokens == ["Hello"]

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_stream_yields_unavailable_on_connection_error(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-021: ConnectionError must yield [LLM_UNAVAILABLE ...] sentinel — not raise to the caller."""
        from requests.exceptions import ConnectionError as ReqConnError

        with patch("llm_service.requests.post", side_effect=ReqConnError("refused")):
            tokens = list(svc._call_llm_stream("test prompt"))

        assert len(tokens) == 1
        assert tokens[0].startswith("[LLM_UNAVAILABLE")

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_stream_yields_unavailable_on_timeout(self, svc: LLMService) -> None:
        """TC-LLM-022: Timeout must yield [LLM_UNAVAILABLE ...] sentinel — not raise to the caller."""
        from requests.exceptions import Timeout

        with patch("llm_service.requests.post", side_effect=Timeout("timed out")):
            tokens = list(svc._call_llm_stream("test prompt"))

        assert len(tokens) == 1
        assert tokens[0].startswith("[LLM_UNAVAILABLE")

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_stream_skips_empty_lines(self, svc: LLMService) -> None:
        """TC-LLM-023: Empty SSE lines (keepalive pings) must be silently skipped."""
        token_line = json.dumps({
            "choices": [{"delta": {"content": "World"}}]
        }).encode()

        mock_response = MagicMock()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_response.raise_for_status = Mock()
        mock_response.iter_lines.return_value = [
            b"",           # empty keepalive
            b"data: " + token_line,
            b"data: [DONE]",
        ]

        with patch("llm_service.requests.post", return_value=mock_response):
            tokens = list(svc._call_llm_stream("test prompt"))

        assert tokens == ["World"]

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_stream_skips_malformed_json_lines(self, svc: LLMService) -> None:
        """TC-LLM-024: Malformed JSON SSE lines must be skipped — not crash the generator."""
        mock_response = MagicMock()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_response.raise_for_status = Mock()
        mock_response.iter_lines.return_value = [
            b"data: {not valid json}",
            b"data: [DONE]",
        ]

        with patch("llm_service.requests.post", return_value=mock_response):
            tokens = list(svc._call_llm_stream("test prompt"))

        # No tokens yielded (malformed skipped), no exception raised.
        assert tokens == []


# ---------------------------------------------------------------------------
# _parse_structured_answer
# ---------------------------------------------------------------------------

class TestParseStructuredAnswer:
    """Test LLM response parsing — FULL_ANSWER tag, SOURCE tag, plain-text fallback."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_parse_plain_text_returned_as_answer(self, svc: LLMService) -> None:
        """TC-LLM-025: Plain text without any tags must be returned as-is in the answer field."""
        result = svc._parse_structured_answer("The weather is sunny.")

        assert result["answer"] == "The weather is sunny."
        assert result["source_number"] is None

    @pytest.mark.unit
    @pytest.mark.llm
    def test_parse_extracts_full_answer_tag(self, svc: LLMService) -> None:
        """TC-LLM-026: FULL_ANSWER: tag content must be extracted as the answer."""
        raw = "FULL_ANSWER: Snapshots are retained for 30 days.\nSOURCE: 1"

        result = svc._parse_structured_answer(raw)

        assert "30 days" in result["answer"]

    @pytest.mark.unit
    @pytest.mark.llm
    def test_parse_extracts_source_number(self, svc: LLMService) -> None:
        """TC-LLM-027: SOURCE: N tag must be parsed into an integer source_number."""
        raw = "FULL_ANSWER: Some answer.\nSOURCE: 2"

        result = svc._parse_structured_answer(raw)

        assert result["source_number"] == 2

    @pytest.mark.unit
    @pytest.mark.llm
    def test_parse_source_number_none_when_no_tag(self, svc: LLMService) -> None:
        """TC-LLM-028: When no SOURCE tag is present source_number must be None."""
        result = svc._parse_structured_answer("Just a plain answer with no source.")

        assert result["source_number"] is None

    @pytest.mark.unit
    @pytest.mark.llm
    def test_parse_strips_whitespace_from_answer(self, svc: LLMService) -> None:
        """TC-LLM-029: Leading/trailing whitespace around the answer must be stripped."""
        result = svc._parse_structured_answer("   Some answer.   ")

        assert result["answer"] == "Some answer."


# ---------------------------------------------------------------------------
# _get_vector_store_id
# ---------------------------------------------------------------------------

class TestGetVectorStoreId:
    """Test CAS vector store ID resolution and error delegation."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_get_vector_store_id_returns_first_id_on_success(
        self, llm_env: None
    ) -> None:
        """TC-LLM-030: When CAS returns stores, the first available ID must be returned as a string."""
        mock_agent = MagicMock()
        mock_agent.list_vector_stores.return_value = {
            "status": "success",
            "vector_stores": [{"id": "crisis-domain"}, {"id": "other-store"}],
        }
        svc = LLMService(cas_client=mock_agent)

        result = svc._get_vector_store_id()

        assert result == "crisis-domain"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_get_vector_store_id_returns_error_dict_when_cas_fails(
        self, llm_env: None
    ) -> None:
        """TC-LLM-031: CAS error response must be surfaced as a status=error dict."""
        mock_agent = MagicMock()
        mock_agent.list_vector_stores.return_value = {
            "status": "error",
            "error": "403 Forbidden",
        }
        svc = LLMService(cas_client=mock_agent)

        result = svc._get_vector_store_id()

        assert isinstance(result, dict)
        assert result["status"] == "error"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_get_vector_store_id_returns_error_dict_when_list_empty(
        self, llm_env: None
    ) -> None:
        """TC-LLM-032: Empty vector store list from CAS must return a status=error dict."""
        mock_agent = MagicMock()
        mock_agent.list_vector_stores.return_value = {
            "status": "success",
            "vector_stores": [],
        }
        svc = LLMService(cas_client=mock_agent)

        result = svc._get_vector_store_id()

        assert isinstance(result, dict)
        assert result["status"] == "error"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_get_vector_store_id_returns_error_when_stores_have_no_id_field(
        self, llm_env: None
    ) -> None:
        """TC-LLM-033: Stores missing the 'id' key must result in a status=error dict."""
        mock_agent = MagicMock()
        mock_agent.list_vector_stores.return_value = {
            "status": "success",
            "vector_stores": [{"name": "crisis-domain"}],  # 'id' key missing
        }
        svc = LLMService(cas_client=mock_agent)

        result = svc._get_vector_store_id()

        assert isinstance(result, dict)
        assert result["status"] == "error"


# ---------------------------------------------------------------------------
# check_model_compatibility
# ---------------------------------------------------------------------------

class TestCheckModelCompatibility:
    """Test the LLM format-compliance probe."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_compatible_when_response_contains_full_answer_and_source(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-034: Model passes when response contains FULL_ANSWER: and [SOURCE: N]."""
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "choices": [{"message": {"content": "FULL_ANSWER: 4.2\n[SOURCE: 1]"}}]
        }
        with patch("llm_service.requests.post", return_value=mock_response):
            result = svc.check_model_compatibility()

        assert result["compatible"] is True
        assert result["model"] == svc.llm_model

    @pytest.mark.unit
    @pytest.mark.llm
    def test_incompatible_when_response_missing_required_format(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-035: Model fails when response does not contain FULL_ANSWER: or [SOURCE: N]."""
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "choices": [{"message": {"content": "The version is 4.2."}}]
        }
        with patch("llm_service.requests.post", return_value=mock_response):
            result = svc.check_model_compatibility()

        assert result["compatible"] is False
        assert result["model"] == svc.llm_model

    @pytest.mark.unit
    @pytest.mark.llm
    def test_compatible_returns_true_when_llm_unreachable(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-036: Unreachable LLM must not be flagged as incompatible — returns compatible=True."""
        with patch("llm_service.requests.post", side_effect=ConnectionError("refused")):
            result = svc.check_model_compatibility()

        assert result["compatible"] is True
