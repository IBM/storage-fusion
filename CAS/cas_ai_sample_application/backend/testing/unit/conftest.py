"""
Pytest configuration and shared fixtures for cast-intern backend unit tests.


Fixture inventory
-----------------
llm_env        — sets LLM_BASE_URL + LLM_MODEL env vars so LLMService.__init__
                 does not raise ConfigurationError.  Used by any test that
                 constructs an LLMService.

mock_cas_client — a pre-configured MagicMock CASClient injected into LLMService
                 so tests never make real outbound HTTP calls to CAS.

svc            — a fully-constructed LLMService(cas_client=mock_cas_client) ready
                 for method-level tests that don't care about the CASAgent itself.
"""

from unittest.mock import MagicMock

import pytest

from llm_service import LLMService


# ---------------------------------------------------------------------------
# LLMService environment fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def llm_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Set the minimum required env vars so LLMService.__init__ does not raise.

    LLM_BASE_URL and LLM_MODEL are required — the constructor raises
    ConfigurationError if either is missing.  Optional vars (LLM_API_KEY,
    DEFAULT_VECTOR_STORE) are explicitly cleared so individual tests start
    from a known, clean state and can opt-in via monkeypatch.setenv().

    Used by: test_llm_service.py
    """
    monkeypatch.setenv("LLM_BASE_URL", "http://localhost:11434")
    monkeypatch.setenv("LLM_MODEL", "llama3")
    # Clear optional vars — tests that need them set their own values.
    monkeypatch.delenv("LLM_API_KEY", raising=False)
    monkeypatch.delenv("DEFAULT_VECTOR_STORE", raising=False)


@pytest.fixture
def mock_cas_client() -> MagicMock:
    """Return a MagicMock CASClient with a default success response for get_vector_stores.

    Injected into LLMService so tests never make real outbound HTTP calls.
    Tests that need a specific CAS error response override the return_value
    directly on their local copy.

    Default behaviour:
      mock_cas_client.list_vector_stores() → {"status": "success", "vector_stores": [...]}

    Used by: test_llm_service.py
    """
    agent = MagicMock()
    # Provide a sensible default so tests that don't care about CAS responses
    # don't need to configure the mock themselves.
    agent.list_vector_stores.return_value = {
        "status": "success",
        "vector_stores": [{"id": "crisis-domain"}, {"id": "test-store"}],
    }
    # Return an empty tool list so LLMService falls back to the hardcoded
    # "cas" search tool during construction — no real MCP calls in unit tests.
    agent.discover_tools.return_value = {"status": "success", "tools": []}
    return agent


@pytest.fixture
def svc(llm_env: None, mock_cas_client: MagicMock) -> LLMService:
    """Return a fully-constructed LLMService ready for method-level unit tests.

    Combines llm_env (env vars) and mock_cas_agent (no real HTTP) so individual
    tests don't repeat that boilerplate.  Tests that need to inspect or override
    CAS behaviour should use mock_cas_client directly instead of this fixture.

    Used by: test_llm_service.py
    """
    return LLMService(cas_client=mock_cas_client)
