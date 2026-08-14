"""
Unit tests for ToolRegistry and the multi-tool retrieval loop.

Covers:
  - ToolRegistry.register()         — stores callables, warns on overwrite
  - ToolRegistry.call()             — dispatches to registered tool, falls back on unknown name
  - ToolRegistry.call_default()     — convenience wrapper
  - ToolRegistry.tool_names         — returns names in registration order
  - ToolRegistry.is_registered()    — membership check
  - LLMService._run_retrieval_loop  — [CHUNK:tool] dispatch, multi-tool prompt listing,
                                      unknown-tool fallback, bare [CHUNK] backward compat

Naming convention:  test_<thing>_<condition>_<expected>
TC-ID convention:   TC-REG-<NNN>
"""

from unittest.mock import MagicMock, patch

import pytest

from agents.tool_registry import ToolRegistry
from llm_service import LLMService


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def reg() -> ToolRegistry:
    """Return a fresh ToolRegistry with default_tool="cas"."""
    return ToolRegistry(default_tool="cas")


def _success(data=None):
    return {"status": "success", "data": data or []}


def _error(msg="err"):
    return {"status": "error", "error": msg}


# ---------------------------------------------------------------------------
# ToolRegistry.register
# ---------------------------------------------------------------------------

class TestToolRegistryRegister:

    @pytest.mark.unit
    @pytest.mark.registry
    def test_register_adds_tool(self, reg: ToolRegistry) -> None:
        """TC-REG-001: Registering a tool makes it available via is_registered."""
        reg.register("cas", lambda q, **kw: _success())
        assert reg.is_registered("cas")

    @pytest.mark.unit
    @pytest.mark.registry
    def test_register_multiple_tools(self, reg: ToolRegistry) -> None:
        """TC-REG-002: Multiple tools can be registered and are all accessible."""
        reg.register("cas", lambda q, **kw: _success())
        reg.register("watsonx", lambda q, **kw: _success())
        assert reg.is_registered("cas")
        assert reg.is_registered("watsonx")

    @pytest.mark.unit
    @pytest.mark.registry
    def test_tool_names_returns_registration_order(self, reg: ToolRegistry) -> None:
        """TC-REG-003: tool_names must preserve insertion order."""
        reg.register("cas", lambda q, **kw: _success())
        reg.register("watsonx", lambda q, **kw: _success())
        reg.register("sql", lambda q, **kw: _success())
        assert reg.tool_names == ["cas", "watsonx", "sql"]

    @pytest.mark.unit
    @pytest.mark.registry
    def test_is_registered_false_for_unknown(self, reg: ToolRegistry) -> None:
        """TC-REG-004: is_registered returns False for a name that was never registered."""
        assert reg.is_registered("unknown") is False


# ---------------------------------------------------------------------------
# ToolRegistry.call
# ---------------------------------------------------------------------------

class TestToolRegistryCall:

    @pytest.mark.unit
    @pytest.mark.registry
    def test_call_invokes_registered_tool(self, reg: ToolRegistry) -> None:
        """TC-REG-005: call() must invoke the callable registered under the given name."""
        fn = MagicMock(return_value=_success([{"text": "doc"}]))
        reg.register("cas", fn)

        result = reg.call("cas", "what is PCIe?", vector_store_id="vs1")

        fn.assert_called_once_with("what is PCIe?", vector_store_id="vs1")
        assert result["status"] == "success"

    @pytest.mark.unit
    @pytest.mark.registry
    def test_call_falls_back_to_default_for_unknown_name(self, reg: ToolRegistry) -> None:
        """TC-REG-006: Calling an unregistered tool name falls back to the default tool."""
        default_fn = MagicMock(return_value=_success())
        reg.register("cas", default_fn)

        reg.call("nonexistent", "query")

        default_fn.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.registry
    def test_call_returns_error_when_no_default_registered(self) -> None:
        """TC-REG-007: If both the named tool and the default are unregistered, return error dict."""
        reg = ToolRegistry(default_tool="cas")  # no tools registered at all
        result = reg.call("cas", "query")
        assert result["status"] == "error"

    @pytest.mark.unit
    @pytest.mark.registry
    def test_call_catches_exceptions_from_tool(self, reg: ToolRegistry) -> None:
        """TC-REG-008: If the tool callable raises, call() returns an error dict — not an exception."""
        reg.register("cas", lambda q, **kw: (_ for _ in ()).throw(RuntimeError("boom")))
        result = reg.call("cas", "query")
        assert result["status"] == "error"
        assert "boom" in result["error"]

    @pytest.mark.unit
    @pytest.mark.registry
    def test_call_default_dispatches_to_default_tool(self, reg: ToolRegistry) -> None:
        """TC-REG-009: call_default() must invoke the default tool."""
        fn = MagicMock(return_value=_success())
        reg.register("cas", fn)

        reg.call_default("some query", vector_store_id="vs1")

        fn.assert_called_once_with("some query", vector_store_id="vs1")


# ---------------------------------------------------------------------------
# _run_retrieval_loop — tool dispatch via [CHUNK:name] signal
# ---------------------------------------------------------------------------

@pytest.fixture
def llm_env(monkeypatch):
    monkeypatch.setenv("LLM_BASE_URL", "http://localhost:11434")
    monkeypatch.setenv("LLM_MODEL", "llama3")
    monkeypatch.delenv("LLM_API_KEY", raising=False)


@pytest.fixture
def svc_with_tools(llm_env):
    """LLMService with the default CAS mock plus a second 'watsonx' mock tool."""
    mock_cas = MagicMock()
    mock_cas.search_vector_store.return_value = {
        "status": "success",
        "data": [{"file_id": "1", "filename": "doc.pdf",
                  "score": {"combined_probability_score": 0.9},
                  "content": [{"type": "text", "text": "CAS result"}]}],
    }
    svc = LLMService(cas_client=mock_cas)

    # Register a second MCP tool so the loop can pick it
    watsonx_mock = MagicMock(return_value={
        "status": "success",
        "data": [{"file_id": "2", "filename": "wx.pdf",
                  "score": {"combined_probability_score": 0.8},
                  "content": [{"type": "text", "text": "Watsonx result"}]}],
    })
    svc.tool_registry.register("watsonx", watsonx_mock)
    svc._watsonx_mock = watsonx_mock
    return svc


class TestRetrievalLoopToolDispatch:

    @pytest.mark.unit
    @pytest.mark.registry
    def test_chunk_signal_with_tool_name_calls_named_tool(
        self, svc_with_tools: LLMService
    ) -> None:
        """TC-REG-010: [CHUNK:watsonx] signal must dispatch to the watsonx tool, not CAS."""
        responses = iter([
            "cas",  # pre-loop tool router (starts with cas; loop then redirects via [CHUNK:watsonx])
            "[CHUNK:watsonx] storage replication topology",
            "FULL_ANSWER: Watsonx result.\n[SOURCE: 1]",
            "FULL_ANSWER: Watsonx result.\n[SOURCE: 1]",  # verification pass
        ])
        with patch.object(svc_with_tools, "_ask_llm", side_effect=lambda p, **kw: next(responses)):
            svc_with_tools._run_retrieval_loop(
                query="How does replication work?",
                vector_store_id="vs1",
            )

        svc_with_tools._watsonx_mock.assert_called_once()
        # CAS was called once (first fetch), watsonx once (second fetch)
        assert svc_with_tools.cas_client.search_vector_store.call_count == 1

    @pytest.mark.unit
    @pytest.mark.registry
    def test_bare_chunk_signal_uses_default_tool(
        self, svc_with_tools: LLMService
    ) -> None:
        """TC-REG-011: Bare [CHUNK] with no tool name must use the default tool (cas)."""
        responses = iter([
            "cas",  # pre-loop tool router
            "[CHUNK] more PCIe details",
            "FULL_ANSWER: 48 ports.\n[SOURCE: 1]",
            "FULL_ANSWER: 48 ports.\n[SOURCE: 1]",  # verification
        ])
        with patch.object(svc_with_tools, "_ask_llm", side_effect=lambda p, **kw: next(responses)):
            svc_with_tools._run_retrieval_loop(
                query="PCIe port count?",
                vector_store_id="vs1",
            )

        # Both fetches went to CAS; watsonx never called
        assert svc_with_tools.cas_client.search_vector_store.call_count == 2
        svc_with_tools._watsonx_mock.assert_not_called()

    @pytest.mark.unit
    @pytest.mark.registry
    def test_unknown_tool_in_chunk_signal_falls_back_to_default(
        self, svc_with_tools: LLMService
    ) -> None:
        """TC-REG-012: [CHUNK:unknown_tool] must fall back to the default tool without raising."""
        responses = iter([
            "cas",  # pre-loop tool router
            "[CHUNK:nonexistent] some query",
            "FULL_ANSWER: Fallback result.\n[SOURCE: 1]",
            "FULL_ANSWER: Fallback result.\n[SOURCE: 1]",
        ])
        with patch.object(svc_with_tools, "_ask_llm", side_effect=lambda p, **kw: next(responses)):
            result = svc_with_tools._run_retrieval_loop(
                query="What is X?",
                vector_store_id="vs1",
            )

        # Should not crash; result should still come back
        assert result["chunks"]

    @pytest.mark.unit
    @pytest.mark.registry
    def test_retrieval_prompt_lists_multiple_tools(
        self, svc_with_tools: LLMService
    ) -> None:
        """TC-REG-013: Retrieval prompt uses the first available tool in its [CHUNK] instruction.

        Tool routing is now a separate pre-loop call so the retrieval prompt no
        longer contains a multi-tool selection block — it always emits a single
        [CHUNK:<tool>] line using the first entry in available_tools.
        """
        chunks = [{"index": 1, "content": "context", "score": 0.9}]
        prompt = svc_with_tools.prompt_builder.build_retrieval_prompt(
            "question?",
            chunks,
            available_tools=svc_with_tools.tool_registry.tool_names,
        )
        # The prompt should reference the first tool (cas) in its [CHUNK] line
        assert "[CHUNK:cas]" in prompt

    @pytest.mark.unit
    @pytest.mark.registry
    def test_retrieval_prompt_single_tool_uses_simple_form(
        self, svc_with_tools: LLMService
    ) -> None:
        """TC-REG-014: With only one tool the prompt uses [CHUNK:cas] not the multi-tool form."""
        chunks = [{"index": 1, "content": "context", "score": 0.9}]
        prompt = svc_with_tools.prompt_builder.build_retrieval_prompt(
            "question?",
            chunks,
            available_tools=["cas"],
        )
        assert "[CHUNK:cas]" in prompt
        # Multi-tool selection line should not appear
        assert "[CHUNK:<tool_name>]" not in prompt
