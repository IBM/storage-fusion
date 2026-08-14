"""
ToolRegistry — a registry of named retrieval tools the LLM can request.

Purpose
-------
The retrieval loop in LLMService needs to ask an external source for more
context when its current chunks are insufficient.  Previously the loop was
hardwired to call ``cas_client.search_vector_store()`` directly.  That meant
adding a second data source (a different MCP server, a SQL index, a web
search tool, etc.) required editing the loop itself — mixing "which tools
exist" with "how the loop works".

This module separates the two concerns:
  - ToolRegistry owns "which tools exist and how to call them".
  - The retrieval loop only sees "give me results for this query from this
    tool name".

Registering a new MCP
---------------------
Each tool is a plain callable:

    def my_tool(query: str, **kwargs) -> Dict[str, Any]:
        ...
        return {"status": "success", "data": [...]}   # same shape as CASClient

Register it once, then the LLM can request it by name in any [CHUNK] signal:

    registry = ToolRegistry(default_tool="cas")
    registry.register("cas", cas_search_fn)
    registry.register("watsonx", watsonx_search_fn)   # add more here

The retrieval prompt lists all registered tool names so the LLM knows what
it can request.  No other code changes are required.

Return shape contract
---------------------
Every registered callable must return a dict with at least:
  {"status": "success", "data": [...]}   on success
  {"status": "error",   "error": "..."}  on failure

The ``data`` list contains chunk-like dicts that ChunkProcessor can process.
This is the same shape ``CASClient.search_vector_store()`` already returns.
"""

from typing import Any, Callable, Dict, List, Optional
import logging

logger = logging.getLogger(__name__)

# Type alias for a retrieval tool callable.
# It must accept ``query`` as a keyword arg and return a result dict.
RetrievalTool = Callable[..., Dict[str, Any]]


class ToolRegistry:
    """Registry of named retrieval tools the LLM can invoke via [CHUNK] signals.

    Usage::

        registry = ToolRegistry(default_tool="cas")
        registry.register("cas", cas_fn)
        registry.register("watsonx", watsonx_fn)

        result = registry.call("cas", "machine learning clusters")
        # or use the default:
        result = registry.call_default("what are the error codes?")

    Each tool callable must accept ``(query: str, **kwargs)`` and return
    ``{"status": "success", "data": [...]}`` or ``{"status": "error", ...}``.
    """

    def __init__(self, default_tool: str = "cas") -> None:
        self._tools: Dict[str, RetrievalTool] = {}
        self._descriptions: Dict[str, str] = {}
        self._default_tool = default_tool

    # ------------------------------------------------------------------
    # Registration
    # ------------------------------------------------------------------

    def register(self, name: str, fn: RetrievalTool, description: str = "") -> None:
        """Register a retrieval tool under ``name``.

        Args:
            name:        Short identifier the LLM uses in [CHUNK:name] signals.
                         Use lowercase and no spaces (e.g. ``"cas"``, ``"watsonx"``).
            fn:          Callable that takes ``(query: str, **kwargs)`` and returns a
                         result dict in the standard shape.
            description: One-line human/LLM-readable description of what this tool
                         covers.  Included in the retrieval prompt so the LLM can
                         pick the right tool when multiple are registered.
        """
        if name in self._tools:
            logger.warning("tool_registry overwriting existing tool name=%r", name)
        self._tools[name] = fn
        self._descriptions[name] = description
        logger.debug("tool_registry registered name=%r", name)

    # ------------------------------------------------------------------
    # Dispatch
    # ------------------------------------------------------------------

    def call(self, name: str, query: str, **kwargs: Any) -> Dict[str, Any]:
        """Call the tool registered under ``name`` with the given query.

        Falls back to the default tool if ``name`` is not registered, so an
        LLM that hallucinates an unknown tool name doesn't hard-fail the loop.

        Args:
            name:  Tool name from the [CHUNK:name] signal.
            query: The refined search query the LLM produced.
            **kwargs: Passed through to the tool callable (e.g. vector_store_id).

        Returns:
            The tool's result dict (``{"status": ..., "data": [...]}``).
        """
        if name not in self._tools:
            logger.warning(
                "tool_registry unknown tool name=%r — falling back to default=%r",
                name, self._default_tool,
            )
            name = self._default_tool
        if name not in self._tools:
            return {"status": "error", "error": f"No tool registered for '{name}'"}
        try:
            return self._tools[name](query, **kwargs)
        except Exception as exc:
            logger.warning("tool_registry call_error name=%r error=%r", name, exc)
            return {"status": "error", "error": str(exc)}

    def call_default(self, query: str, **kwargs: Any) -> Dict[str, Any]:
        """Call the default tool — convenience wrapper for ``call(default, query)``."""
        return self.call(self._default_tool, query, **kwargs)

    # ------------------------------------------------------------------
    # Introspection
    # ------------------------------------------------------------------

    @property
    def tool_names(self) -> List[str]:
        """Return the list of registered tool names in registration order."""
        return list(self._tools.keys())

    @property
    def tool_descriptions(self) -> Dict[str, str]:
        """Return a mapping of tool name → description for all registered tools."""
        return dict(self._descriptions)

    @property
    def default_tool(self) -> str:
        """Return the name of the default tool."""
        return self._default_tool

    def is_registered(self, name: str) -> bool:
        """Return True if ``name`` has been registered."""
        return name in self._tools
