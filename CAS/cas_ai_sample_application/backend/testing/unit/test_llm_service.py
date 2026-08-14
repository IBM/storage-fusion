"""
Unit tests for LLMService

Covers:
  - Constructor                — raises ConfigurationError when required env vars missing
  - _build_prompt()            — context ordering and required sections
  - _build_chat_payload()      — OpenAI-compatible payload shape
  - _auth_headers()            — Bearer header present/absent based on LLM_API_KEY
  - _call_llm()                — SSE token extraction, connection errors, HTTP errors
  - _ask_llm()                 — collected string wrapper over _call_llm()
  - _parse_structured_answer() — FULL_ANSWER tag, SOURCE tag, plain-text fallback
  - _get_vector_store_id()     — CAS success/error delegation
  - check_model_compatibility() — format probe: pass, fail, unreachable LLM

Naming convention:  test_<method>_<condition>_<expected_outcome>
TC-ID convention:   TC-LLM-<NNN>

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

        prompt = svc.prompt_builder.build_prompt("What is the backup policy?", chunks)

        assert "What is the backup policy?" in prompt

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_prompt_includes_source_labels(self, svc: LLMService) -> None:
        """TC-LLM-010: Each chunk must appear under a [Source N] label in the prompt."""
        chunks = [
            {"index": 1, "content": "First chunk.", "score": 0.9},
            {"index": 2, "content": "Second chunk.", "score": 0.8},
        ]

        prompt = svc.prompt_builder.build_prompt("Any question?", chunks)

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

        prompt = svc.prompt_builder.build_prompt("Any question?", chunks)

        # High score content must appear before low score content in the string.
        assert prompt.index("High score chunk.") < prompt.index("Low score chunk.")

    @pytest.mark.unit
    @pytest.mark.llm
    def test_build_prompt_contains_response_section(self, svc: LLMService) -> None:
        """TC-LLM-012: Prompt must end with a 'Response:' marker so the LLM knows where to write."""
        chunks = [{"index": 1, "content": "context", "score": 0.9}]

        prompt = svc.prompt_builder.build_prompt("question?", chunks)

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

        prompt = svc.prompt_builder.build_prompt("What does the weather forecast say?", chunks)

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
# _call_llm
# ---------------------------------------------------------------------------

class TestCallLLM:
    """Test SSE streaming, token extraction, collect mode, and error fallback."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_yields_tokens_from_sse_response(self, svc: LLMService) -> None:
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
            tokens = list(svc._call_llm("test prompt"))

        assert tokens == ["Hello"]

    @pytest.mark.unit
    @pytest.mark.llm
    def test_ask_llm_returns_joined_string(self, svc: LLMService) -> None:
        """TC-LLM-020b: _ask_llm must return a single joined string from the stream."""
        lines = [
            json.dumps({"choices": [{"delta": {"content": t}}]}).encode()
            for t in ["Hello", " ", "world"]
        ]
        mock_response = MagicMock()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_response.raise_for_status = Mock()
        mock_response.iter_lines.return_value = [b"data: " + l for l in lines] + [b"data: [DONE]"]

        with patch("llm_service.requests.post", return_value=mock_response):
            result = svc._ask_llm("test prompt", max_tokens=80)

        assert result == "Hello world"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_ask_llm_returns_sentinel_on_connection_error(self, svc: LLMService) -> None:
        """TC-LLM-020c: _ask_llm must return the error sentinel string on ConnectionError."""
        from requests.exceptions import ConnectionError as ReqConnError

        with patch("llm_service.requests.post", side_effect=ReqConnError("refused")):
            result = svc._ask_llm("test prompt", max_tokens=80)

        assert isinstance(result, str)
        assert result.startswith("[LLM_UNAVAILABLE")

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_yields_unavailable_on_connection_error(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-021: ConnectionError must yield [LLM_UNAVAILABLE ...] sentinel — not raise to the caller."""
        from requests.exceptions import ConnectionError as ReqConnError

        with patch("llm_service.requests.post", side_effect=ReqConnError("refused")):
            tokens = list(svc._call_llm("test prompt"))

        assert len(tokens) == 1
        assert tokens[0].startswith("[LLM_UNAVAILABLE")

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_yields_unavailable_on_timeout(self, svc: LLMService) -> None:
        """TC-LLM-022: Timeout must yield [LLM_UNAVAILABLE ...] sentinel — not raise to the caller."""
        from requests.exceptions import Timeout

        with patch("llm_service.requests.post", side_effect=Timeout("timed out")):
            tokens = list(svc._call_llm("test prompt"))

        assert len(tokens) == 1
        assert tokens[0].startswith("[LLM_UNAVAILABLE")

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_skips_empty_lines(self, svc: LLMService) -> None:
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
            tokens = list(svc._call_llm("test prompt"))

        assert tokens == ["World"]

    @pytest.mark.unit
    @pytest.mark.llm
    def test_call_llm_skips_malformed_json_lines(self, svc: LLMService) -> None:
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
            tokens = list(svc._call_llm("test prompt"))

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
        token_line = json.dumps(
            {"choices": [{"delta": {"content": "FULL_ANSWER: 4.2\n[SOURCE: 1]"}}]}
        ).encode()
        mock_response = MagicMock()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_response.raise_for_status = Mock()
        mock_response.iter_lines.return_value = [b"data: " + token_line, b"data: [DONE]"]

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
        token_line = json.dumps(
            {"choices": [{"delta": {"content": "The version is 4.2."}}]}
        ).encode()
        mock_response = MagicMock()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_response.raise_for_status = Mock()
        mock_response.iter_lines.return_value = [b"data: " + token_line, b"data: [DONE]"]

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


# ---------------------------------------------------------------------------
# _resolve_query_from_block
# ---------------------------------------------------------------------------

class TestResolveQuery:
    """Test the follow-up query rewriter."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_resolve_query_returns_original_when_no_session(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-041: With no history block, _resolve_query_from_block must return the query unchanged."""
        assert svc._resolve_query_from_block("More about that", "") == "More about that"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_resolve_query_returns_original_when_session_has_no_history(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-042: Empty history block must return query unchanged without calling LLM."""
        from session_store import Session
        empty_session = Session(session_id="test-id")
        history_block = svc._build_history_block(empty_session)
        with patch("llm_service.requests.post") as mock_post:
            result = svc._resolve_query_from_block("More about that", history_block)
        mock_post.assert_not_called()
        assert result == "More about that"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_resolve_query_calls_llm_when_history_exists(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-043: When history block is non-empty, _resolve_query_from_block must call _ask_llm."""
        from session_store import Session, Turn
        session = Session(session_id="test-id")
        session.turns.append(Turn(query="What is Cyber Vault?", answer="Cyber Vault reduces recovery time.", sources=["doc.pdf"]))
        history_block = svc._build_history_block(session)

        with patch.object(svc, "_ask_llm", return_value="What is Cyber Vault designed for?") as mock_ask:
            result = svc._resolve_query_from_block("What about it?", history_block)

        mock_ask.assert_called_once()
        assert result == "What is Cyber Vault designed for?"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_resolve_query_falls_back_on_llm_sentinel(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-044: When _ask_llm returns a sentinel, _resolve_query_from_block must fall back to original."""
        from session_store import Session, Turn
        session = Session(session_id="test-id")
        session.turns.append(Turn(query="What is OBAC?", answer="OBAC controls object access.", sources=["doc.pdf"]))
        history_block = svc._build_history_block(session)

        with patch.object(svc, "_ask_llm", return_value="[LLM_UNAVAILABLE url=http://x model=m]"):
            result = svc._resolve_query_from_block("More about it", history_block)

        assert result == "More about it"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_resolve_query_passes_through_long_rewrite_unchanged(
        self, svc: LLMService
    ) -> None:
        """TC-LLM-045: Any non-sentinel rewrite is returned as-is — no sentence-split check."""
        from session_store import Session, Turn
        session = Session(session_id="test-id")
        session.turns.append(Turn(
            query="How many PCIe ports does a FlashSystem 9500 have?",
            answer="A FlashSystem 9500 has 48 PCIe ports.",
            sources=["doc.pdf"],
        ))
        history_block = svc._build_history_block(session)

        long_q = "What is the maximum number of PCIe ports in a FlashSystem 9500 with two enclosures?"
        with patch.object(svc, "_ask_llm", return_value=long_q):
            result = svc._resolve_query_from_block("How about with 2 enclosures?", history_block)

        assert result == long_q


# ---------------------------------------------------------------------------
# _build_history_block
# ---------------------------------------------------------------------------

class TestBuildHistoryBlock:
    """Test the unified conversation history block formatter."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_returns_empty_string_when_session_is_none(self, svc: LLMService) -> None:
        """TC-LLM-046: None session must return empty string — no history available."""
        assert svc._build_history_block(None) == ""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_returns_empty_string_when_session_is_empty(self, svc: LLMService) -> None:
        """TC-LLM-047: Session with no turns and no summary must return empty string."""
        from session_store import Session
        assert svc._build_history_block(Session(session_id="x")) == ""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_includes_conversation_history_markers(self, svc: LLMService) -> None:
        """TC-LLM-048: Block must open with [CONVERSATION HISTORY] and close with [END HISTORY]."""
        from session_store import Session, Turn
        session = Session(session_id="x")
        session.turns.append(Turn(query="Q1", answer="A1", sources=[]))
        block = svc._build_history_block(session)
        assert block.startswith("[CONVERSATION HISTORY]")
        assert block.endswith("[END HISTORY]")

    @pytest.mark.unit
    @pytest.mark.llm
    def test_doc_turns_appear_as_numbered_turns(self, svc: LLMService) -> None:
        """TC-LLM-049: Document Q&A turns must appear as 'Turn N: Q: ... | A: ...' lines."""
        from session_store import Session, Turn
        session = Session(session_id="x")
        session.turns.append(Turn(query="What is Cyber Vault?", answer="An air-gap solution.", sources=["doc.pdf"]))
        block = svc._build_history_block(session)
        assert "Turn 1: Q: What is Cyber Vault? | A: An air-gap solution." in block

    @pytest.mark.unit
    @pytest.mark.llm
    def test_meta_turns_appear_as_numbered_turns(self, svc: LLMService) -> None:
        """TC-LLM-050: Meta turns ([meta] source) must appear as numbered turns, not be excluded."""
        from session_store import Session, Turn
        session = Session(session_id="x")
        session.turns.append(Turn(query="What is OBAC?", answer="OBAC controls access.", sources=["doc.pdf"]))
        session.turns.append(Turn(query="Summarise that", answer="OBAC is an access control feature.", sources=["[meta]"]))
        block = svc._build_history_block(session)
        assert "Turn 1:" in block
        assert "Turn 2:" in block

    @pytest.mark.unit
    @pytest.mark.llm
    def test_user_context_turns_appear_as_personal_facts_not_turns(self, svc: LLMService) -> None:
        """TC-LLM-051: [user-context] turns must appear under 'Personal facts:' and not as numbered turns."""
        from session_store import Session, Turn
        session = Session(session_id="x")
        session.turns.append(Turn(query="My name is Priya", answer="Got it!", sources=["[user-context]"]))
        block = svc._build_history_block(session)
        assert "Personal facts:" in block
        assert "My name is Priya" in block
        assert "Turn 1:" not in block

    @pytest.mark.unit
    @pytest.mark.llm
    def test_running_summary_included_when_present(self, svc: LLMService) -> None:
        """TC-LLM-052: A non-empty running_summary must appear as 'Summary: ...' in the block."""
        from session_store import Session
        session = Session(session_id="x")
        session.running_summary = "User asked about Cyber Vault and OBAC."
        block = svc._build_history_block(session)
        assert "Summary: User asked about Cyber Vault and OBAC." in block

    @pytest.mark.unit
    @pytest.mark.llm
    def test_max_turns_limits_included_turns(self, svc: LLMService) -> None:
        """TC-LLM-053: max_turns=2 must include only the 2 most recent turns."""
        from session_store import Session, Turn
        session = Session(session_id="x")
        for i in range(5):
            session.turns.append(Turn(query=f"Q{i}", answer=f"A{i}", sources=[]))
        block = svc._build_history_block(session, max_turns=2)
        assert "Q3" in block
        assert "Q4" in block
        assert "Q0" not in block
        assert "Q1" not in block
        assert "Q2" not in block


# ---------------------------------------------------------------------------
# _run_retrieval_loop
# ---------------------------------------------------------------------------

class TestRunRetrievalLoop:
    """Test the agentic retrieval loop."""

    def _make_cas_success(self, contents):
        """Return a mock cas_client.search_vector_store result with the given text chunks."""
        return {
            "status": "success",
            "data": [
                {"file_id": str(i), "filename": f"doc{i}.pdf",
                 "score": {"combined_probability_score": 0.9 - i * 0.1},
                 "content": [{"type": "text", "text": c}]}
                for i, c in enumerate(contents)
            ],
        }

    @pytest.mark.unit
    @pytest.mark.llm
    def test_loop_returns_answer_on_first_iteration(self, svc: LLMService) -> None:
        """TC-LLM-054: When the LLM is satisfied on the first attempt, loop returns after 1 CAS fetch."""
        svc.cas_client.search_vector_store = MagicMock(
            return_value=self._make_cas_success(["PCIe is a high-speed bus."])
        )
        with patch.object(svc, "_ask_llm", return_value="FULL_ANSWER: PCIe is a high-speed bus.\n[SOURCE: 1]"):
            result = svc._run_retrieval_loop(
                query="What is PCIe?",
                vector_store_id="vs1",
                chunk_cap=5,
                min_score=0.1,
            )

        assert svc.cas_client.search_vector_store.call_count == 1
        assert result["iterations"] == 1
        assert result["forced"] is False
        assert "answer_text" in result
        assert result["final_prompt"] is None

    @pytest.mark.unit
    @pytest.mark.llm
    def test_loop_refines_query_on_chunk_signal(self, svc: LLMService) -> None:
        """TC-LLM-055: [CHUNK] response triggers a second CAS fetch with the refined query."""
        call_count = {"n": 0}

        def side_effect(*args, **kwargs):
            call_count["n"] += 1
            return self._make_cas_success([f"chunk from call {call_count['n']}"])

        svc.cas_client.search_vector_store = MagicMock(side_effect=side_effect)

        responses = iter([
            # pre-loop tool router call — returns "cas" (the default)
            "cas",
            "[CHUNK] FlashSystem 9500 PCIe slots per enclosure",
            "FULL_ANSWER: The answer is 48.\n[SOURCE: 1]",
            # verification step — pass through unchanged
            "FULL_ANSWER: The answer is 48.\n[SOURCE: 1]",
        ])
        with patch.object(svc, "_ask_llm", side_effect=lambda p, **kw: next(responses)):
            result = svc._run_retrieval_loop(
                query="How many PCIe ports?",
                vector_store_id="vs1",
                chunk_cap=5,
                min_score=0.1,
            )

        assert svc.cas_client.search_vector_store.call_count == 2
        assert result["iterations"] == 2
        assert result["forced"] is False

    @pytest.mark.unit
    @pytest.mark.llm
    def test_loop_forces_answer_at_max_iter(self, svc: LLMService) -> None:
        """TC-LLM-056: Loop never exceeds retrieval_loop_max_iter+1 CAS fetches regardless of [CHUNK] signals."""
        svc.retrieval_loop_max_iter = 2
        svc.cas_client.search_vector_store = MagicMock(
            return_value=self._make_cas_success(["some content"])
        )
        # Always ask for more — loop must still terminate
        with patch.object(svc, "_ask_llm", return_value="[CHUNK] more info please"):
            result = svc._run_retrieval_loop(
                query="Tell me everything",
                vector_store_id="vs1",
                chunk_cap=5,
                min_score=0.1,
            )

        assert svc.cas_client.search_vector_store.call_count <= svc.retrieval_loop_max_iter + 1
        assert result["forced"] is True
        assert result["final_prompt"] is not None

    @pytest.mark.unit
    @pytest.mark.llm
    def test_loop_stops_on_duplicate_query(self, svc: LLMService) -> None:
        """TC-LLM-057: If [CHUNK] returns the same query twice, the loop breaks to avoid infinite fetching."""
        svc.cas_client.search_vector_store = MagicMock(
            return_value=self._make_cas_success(["content"])
        )
        # Return the same query every time — should break after detecting the duplicate
        with patch.object(svc, "_ask_llm", return_value="[CHUNK] What is PCIe?"):
            result = svc._run_retrieval_loop(
                query="What is PCIe?",
                vector_store_id="vs1",
                chunk_cap=5,
                min_score=0.1,
            )

        # First call uses "What is PCIe?" — second [CHUNK] returns the same query — loop breaks
        assert svc.cas_client.search_vector_store.call_count == 1
        assert result["forced"] is True

    @pytest.mark.unit
    @pytest.mark.llm
    def test_loop_falls_back_on_cas_error(self, svc: LLMService) -> None:
        """TC-LLM-058: CAS error on first fetch returns empty chunks and forced=True."""
        svc.cas_client.search_vector_store = MagicMock(
            return_value={"status": "error", "error": "connection refused"}
        )
        result = svc._run_retrieval_loop(
            query="What is PCIe?",
            vector_store_id="vs1",
            chunk_cap=5,
            min_score=0.1,
        )

        assert result["chunks"] == []
        assert result["forced"] is True

    @pytest.mark.unit
    @pytest.mark.llm
    def test_loop_deduplicates_chunk_content(self, svc: LLMService) -> None:
        """TC-LLM-059: Identical chunk content from two fetches must appear only once in the result."""
        svc.cas_client.search_vector_store = MagicMock(
            return_value=self._make_cas_success(["PCIe is a high-speed bus."])
        )
        responses = iter([
            "[CHUNK] more about PCIe",
            "FULL_ANSWER: PCIe is fast.\n[SOURCE: 1]",
            # verification step — pass through unchanged
            "FULL_ANSWER: PCIe is fast.\n[SOURCE: 1]",
        ])
        with patch.object(svc, "_ask_llm", side_effect=lambda p, **kw: next(responses)):
            result = svc._run_retrieval_loop(
                query="What is PCIe?",
                vector_store_id="vs1",
                chunk_cap=5,
                min_score=0.1,
            )

        contents = [c["content"] for c in result["chunks"]]
        assert len(contents) == len(set(contents)), "Duplicate chunk content found"


# ---------------------------------------------------------------------------
# estimate_tokens (module-level function)
# ---------------------------------------------------------------------------

class TestEstimateTokens:
    """Test the rough token estimator used by the compaction trigger."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_estimate_tokens_returns_zero_for_empty_string(self) -> None:
        """TC-LLM-060: Empty string must return 0 tokens."""
        from llm_service import estimate_tokens
        assert estimate_tokens("") == 0

    @pytest.mark.unit
    @pytest.mark.llm
    def test_estimate_tokens_divides_by_four(self) -> None:
        """TC-LLM-061: 40-char string must estimate to 10 tokens (40 // 4)."""
        from llm_service import estimate_tokens
        assert estimate_tokens("a" * 40) == 10

    @pytest.mark.unit
    @pytest.mark.llm
    def test_estimate_tokens_floors_division(self) -> None:
        """TC-LLM-062: 9-char string must estimate to 2 tokens (9 // 4 = 2, not 2.25)."""
        from llm_service import estimate_tokens
        assert estimate_tokens("123456789") == 2


# ---------------------------------------------------------------------------
# _compact_history
# ---------------------------------------------------------------------------

class TestCompactHistory:
    """Test session history compaction — fold + keep, budget check, LLM failure fallback."""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_compact_noop_when_session_is_none(self, svc: LLMService) -> None:
        """TC-LLM-067: None session must not raise — compaction is a no-op."""
        # Must not raise.
        svc._compact_history(None)

    @pytest.mark.unit
    @pytest.mark.llm
    def test_compact_noop_when_under_budget(self, svc: LLMService) -> None:
        """TC-LLM-068: Session under the token budget must not trigger any LLM call."""
        from session_store import Session, Turn
        svc.session_max_context_tokens = 25000
        svc.session_compact_threshold = 0.80
        session = Session(session_id="x")
        session.turns.append(Turn(query="Q1", answer="A1", sources=[]))

        with patch.object(svc, "_ask_llm") as mock_ask:
            svc._compact_history(session)

        mock_ask.assert_not_called()

    @pytest.mark.unit
    @pytest.mark.llm
    def test_compact_folds_old_turns_into_summary(self, svc: LLMService) -> None:
        """TC-LLM-069: When over budget, _compact_history returns a plan with summary and kept turns."""
        from session_store import Session, Turn
        # Use a tiny budget so even small sessions trigger compaction.
        svc.session_max_context_tokens = 10
        svc.session_compact_threshold = 0.5
        svc.session_keep_turns = 1

        session = Session(session_id="x")
        session.turns.append(Turn(query="Q1", answer="A1" * 20, sources=[]))
        session.turns.append(Turn(query="Q2", answer="A2" * 20, sources=[]))

        with patch.object(svc, "_ask_llm", return_value="Summary of Q1 and Q2."):
            plan = svc._compact_history(session)

        # _compact_history is side-effect-free — it returns a plan dict for the
        # caller to apply via SessionStore.set_summary(), not mutate the session directly.
        assert plan is not None
        assert plan["summary"] == "Summary of Q1 and Q2."
        # Only the most recent turn (Q2) is in the plan to keep.
        assert len(plan["turns_to_keep"]) == 1
        assert plan["turns_to_keep"][0].query == "Q2"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_compact_leaves_history_unchanged_on_llm_failure(self, svc: LLMService) -> None:
        """TC-LLM-070: LLM sentinel from compaction call must leave history unmodified."""
        from session_store import Session, Turn
        svc.session_max_context_tokens = 10
        svc.session_compact_threshold = 0.5
        svc.session_keep_turns = 1

        session = Session(session_id="x")
        session.turns.append(Turn(query="Q1", answer="A1" * 20, sources=[]))
        session.turns.append(Turn(query="Q2", answer="A2" * 20, sources=[]))
        original_turn_count = len(session.turns)

        with patch.object(svc, "_ask_llm", return_value="[LLM_UNAVAILABLE url=x model=m]"):
            svc._compact_history(session)

        # History must be left intact on compaction failure.
        assert len(session.turns) == original_turn_count
        assert session.running_summary == ""
