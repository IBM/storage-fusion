"""
LLM service — CAS retrieval + LLM answer synthesis.

Responsibilities:
  1. Configure the LLM backend from environment variables.
  2. Call the OpenAI-compatible /v1/chat/completions API (streaming + blocking).
  3. Run the retrieval loop: search CAS via MCP, decide to answer or refetch.
  4. Rewrite follow-up queries against session history.
  5. Compact session history when it exceeds the token budget.

Prompt assembly is delegated to ``utils.prompt_builder.PromptBuilder`` so
this class only handles I/O — it never constructs prompt strings directly.

Works with any OpenAI-compatible /v1/chat/completions API.
Set LLM_BASE_URL, LLM_MODEL (and optionally LLM_API_KEY) in .env.
"""

from typing import Any, Dict, Iterator, List, Optional, Sequence, Union
import json
import logging
import os
import re

import requests
from requests.exceptions import ConnectionError as RequestsConnectionError, Timeout

from agents.cas_client import CASClient, _unwrap_mcp_result
from agents.tool_registry import ToolRegistry
from chunk_processor import ChunkProcessor
from utils.exceptions import ConfigurationError
from utils.prompt_builder import PromptBuilder
from utils.query import is_bare_metric_fragment, is_self_contained, strip_trailing_pronoun

logger = logging.getLogger(__name__)


def estimate_tokens(text: str) -> int:
    """Rough token estimator: 1 token ≈ 4 characters (floor division)."""
    return len(text) // 4


class LLMService:
    """Retrieve chunks from CAS and synthesize an answer with an LLM."""

    def __init__(
        self,
        cas_client: Optional[CASClient] = None,
    ) -> None:
        self.cas_client = cas_client or CASClient()

        llm_base_url = os.getenv("LLM_BASE_URL")
        llm_model = os.getenv("LLM_MODEL")
        if not llm_base_url:
            raise ConfigurationError("LLM_BASE_URL is not set in .env.")
        if not llm_model:
            raise ConfigurationError(
                "LLM_MODEL is not set in your .env (e.g. llama3, meta/llama-3.1-8b-instruct, gpt-4o)."
            )

        self.llm_base_url = llm_base_url.rstrip("/")
        self.llm_model = llm_model
        self.llm_api_key = os.getenv("LLM_API_KEY", "")
        self.vector_store_id = os.getenv("CAS_VECTOR_STORE_ID")
        self.default_max_results = int(os.getenv("RAG_MAX_RESULTS", "10"))
        self.default_min_score = float(os.getenv("RAG_MIN_SCORE", "0.1"))
        self.request_timeout = int(os.getenv("LLM_TIMEOUT", "60"))
        self.llm_max_tokens = int(os.getenv("LLM_MAX_TOKENS", "300"))
        self.chunk_processor = ChunkProcessor()
        self.retrieval_loop_max_iter = int(os.getenv("RETRIEVAL_LOOP_MAX_ITER", "2"))
        self.fact_check_enabled = os.getenv("FACT_CHECK_ENABLED", "true").lower() not in ("false", "0", "no")
        self.tool_router_enabled = os.getenv("TOOL_ROUTER_ENABLED", "true").lower() not in ("false", "0", "no")
        # PromptBuilder loads system_prompt.md once and owns all prompt assembly.
        # LLMService never constructs prompt strings directly.
        self.prompt_builder = PromptBuilder()
        # Expose system_prompt as a pass-through for the model compatibility probe.
        self.system_prompt = self.prompt_builder.system_prompt

        # ToolRegistry — maps tool names to retrieval callables.
        # The LLM requests a tool by name in its [CHUNK:<name>] signal.
        #
        # Tool registration is now discovery-driven: on startup we call
        # tools/list on the CAS MCP endpoint and register every tool the
        # server advertises.  If discovery fails (CAS unreachable at init
        # time, or the endpoint doesn't support tools/list), we fall back
        # to the single hardcoded "cas" search tool so nothing breaks.
        self.tool_registry = ToolRegistry(default_tool="cas")
        self._register_discovered_tools()

        # Session compaction settings
        self.session_max_context_tokens = int(os.getenv("SESSION_MAX_CONTEXT_TOKENS", "25000"))
        self.session_compact_threshold = float(os.getenv("SESSION_COMPACT_THRESHOLD", "0.80"))
        self.session_keep_turns = int(os.getenv("SESSION_KEEP_TURNS", "4"))
        # History-block display cap. Defaults to session_keep_turns so the
        # "how many turns survive compaction" and "how many turns are shown
        # per prompt" knobs stay in sync unless explicitly overridden.
        self.session_history_turns = int(
            os.getenv("SESSION_HISTORY_TURNS", str(self.session_keep_turns))
        )
        # Token budget for the compaction summary call itself — deliberately
        # small and independent of LLM_MAX_TOKENS, since a "summary" that's
        # allowed to run to LLM_MAX_TOKENS defeats the point of compacting.
        self.session_compact_summary_tokens = int(
            os.getenv("SESSION_COMPACT_SUMMARY_TOKENS", "300")
        )

    # ------------------------------------------------------------------
    # Tool registration
    # ------------------------------------------------------------------

    def _make_cas_search_fn(self) -> Any:
        """Return the standard CAS vector-search callable for the ToolRegistry.

        Isolated here so both the discovery path and the fallback path
        share exactly the same closure without duplication.
        """
        max_results = self.default_max_results
        min_score = self.default_min_score
        cas = self.cas_client

        def _cas_search(query: str, vector_store_id: str = "", **_kwargs: Any) -> Dict[str, Any]:
            return cas.search_vector_store(
                vector_store_id=vector_store_id,
                query=query,
                max_num_results=max_results * 2,
                min_score=min_score,
            )

        return _cas_search

    def _make_generic_mcp_fn(self, tool_name: str) -> Any:
        """Return a callable that forwards any MCP tool call by name.

        Used for tools discovered via tools/list that aren't the primary
        search tool.  The callable passes ``auth_token`` automatically and
        forwards ``vector_store_id`` when provided.

        Args:
            tool_name: The exact MCP tool name to invoke (e.g.
                       ``"get_vector_store_file_content"``).
        """
        cas = self.cas_client

        def _generic_mcp(query: str, vector_store_id: str = "", **_kwargs: Any) -> Dict[str, Any]:
            arguments: Dict[str, Any] = {"auth_token": cas._api_key, "query": query}
            if vector_store_id:
                arguments["vector_store_id"] = vector_store_id
            try:
                result = cas._call_mcp_tool(
                    mcp_url=cas._build_mcp_url(),
                    tool_name=tool_name,
                    arguments=arguments,
                )
                if result is None:
                    return {"status": "error", "error": "Empty response from MCP tool"}
                data = _unwrap_mcp_result(result)
                if isinstance(data, dict) and "error" in data:
                    return {"status": "error", "error": str(data["error"])}
                items = data if isinstance(data, list) else (data.get("data", []) if isinstance(data, dict) else [])
                return {"status": "success", "data": items}
            except Exception as exc:
                logger.warning("generic_mcp_tool_error tool=%r error=%r", tool_name, exc)
                return {"status": "error", "error": str(exc)}

        return _generic_mcp

    def _register_discovered_tools(self) -> None:
        """Populate the ToolRegistry from the CAS MCP server's own tools/list.

        Calls ``tools/list`` on the CAS MCP endpoint so the LLM can choose
        from whatever tools the server actually advertises — no hardcoding.

        Discovery rules:
        - The tool named ``search_vector_stores`` (or any tool whose name
          contains ``search``) is always registered under the alias ``"cas"``
          and set as the default, using the optimised CAS search wrapper.
        - Every other advertised tool is registered under its MCP name so the
          LLM can request it with ``[CHUNK:<mcp_tool_name>]``.
        - If discovery fails or returns an empty list, falls back to the
          single hardcoded ``"cas"`` search tool so nothing breaks.
        """
        if not self.cas_client.is_configured():
            logger.debug("tool_discovery skipped — CAS client not configured yet, using fallback")
            self._register_fallback_cas_tool()
            return

        result = self.cas_client.discover_tools()
        if result.get("status") != "success":
            logger.warning(
                "tool_discovery failed error=%r — falling back to hardcoded cas tool",
                result.get("error"),
            )
            self._register_fallback_cas_tool()
            return

        tools = result.get("tools", [])
        if not tools:
            logger.warning("tool_discovery returned no tools — falling back to hardcoded cas tool")
            self._register_fallback_cas_tool()
            return

        # Tools the LLM should never see — internal/admin tools that are not
        # useful as retrieval tools and would only confuse the LLM's choice.
        _INTERNAL_TOOLS = {"list_vector_stores"}

        registered = 0
        for descriptor in tools:
            if not isinstance(descriptor, dict):
                continue
            name = descriptor.get("name", "").strip()
            description = descriptor.get("description", "").strip()
            if not name:
                continue

            # Skip internal tools — register them silently so the transport
            # layer can still call them (e.g. CASClient.list_vector_stores),
            # but don't expose them to the LLM via the ToolRegistry.
            if name in _INTERNAL_TOOLS:
                logger.debug("tool_discovery skipping internal tool name=%r", name)
                continue

            # The primary search tool is always exposed as "cas" so the rest
            # of the pipeline (default_tool, fallback logic) stays unchanged.
            is_search = "search" in name.lower()
            registry_name = "cas" if is_search else name

            if is_search:
                fn = self._make_cas_search_fn()
                desc = description or "IBM Content Aware Storage vector search — documents, technical specs, IBM Fusion content"
            else:
                fn = self._make_generic_mcp_fn(name)
                desc = description or f"CAS MCP tool: {name}"

            self.tool_registry.register(registry_name, fn, description=desc)
            registered += 1
            logger.debug("tool_discovery registered name=%r (mcp=%r) desc=%r", registry_name, name, desc[:80])

        if registered == 0:
            logger.warning("tool_discovery registered 0 tools — falling back to hardcoded cas tool")
            self._register_fallback_cas_tool()
            return

        # Ensure "cas" is always present even if the server didn't advertise
        # a tool with "search" in the name.
        if not self.tool_registry.is_registered("cas"):
            logger.warning("tool_discovery: no search tool found — registering hardcoded cas fallback")
            self._register_fallback_cas_tool()

        logger.info(
            "tool_discovery complete registered=%d tools=%r",
            registered,
            self.tool_registry.tool_names,
        )

    def _register_fallback_cas_tool(self) -> None:
        """Register the hardcoded CAS search tool.

        Called when ``tools/list`` is unavailable or returns nothing.
        Keeps the registry in a valid state so the retrieval loop always
        has at least one tool to dispatch to.
        """
        self.tool_registry.register(
            "cas",
            self._make_cas_search_fn(),
            description="IBM Content Aware Storage vector search — documents, technical specs, IBM Fusion content",
        )
        logger.debug("tool_discovery fallback registered hardcoded cas tool")

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def check_model_compatibility(self) -> Dict[str, Any]:
        """Send a minimal probe to the LLM to check structured-output format compliance.

        Sends a tiny synthetic context + question and checks whether the model
        produces a response containing both FULL_ANSWER: and [SOURCE: N].
        Models that fail this check are too small or too poorly instruction-tuned
        to reliably follow the pipeline's output format.

        Returns:
            Dict with keys:
              - "compatible" (bool): True if the model passed or is unreachable
                (unreachable is handled by the existing LLM error sentinels).
              - "model" (str): the configured model name.
              - "reason" (str): human-readable explanation.
        """
        probe_prompt = (
            "You are a retrieval-augmented assistant.\n\n"
            "Context Sources:\n"
            "[Source 1]\nThe test system version is 4.2.\n\n"
            "Question: What is the test system version?\n"
            "Answer ONLY the question above. Be specific and direct.\n\n"
            "Response in exactly this format:\n"
            "FULL_ANSWER: [your answer]\n"
            "[SOURCE: 1]\n\n"
            "Response:"
        )
        text = self._ask_llm(probe_prompt)
        if text.startswith("[LLM_"):
            logger.debug("llm_compat_check_skipped sentinel=%r", text[:60])
            return {"compatible": True, "model": self.llm_model, "reason": "Probe skipped (LLM unreachable)."}
        has_full_answer = bool(re.search(r'FULL_ANSWER\s*:', text, re.IGNORECASE))
        has_source = bool(re.search(r'\[SOURCE\s*:\s*(\d+|N/A)\]', text, re.IGNORECASE))
        if has_full_answer and has_source:
            return {"compatible": True, "model": self.llm_model, "reason": "Model passed format compliance check."}
        logger.warning("llm_compat_check_failed model=%s response=%r", self.llm_model, text[:200])
        return {
            "compatible": False,
            "model": self.llm_model,
            "reason": "Model did not produce the required FULL_ANSWER / [SOURCE: N] format.",
        }

    def _extract_chunks(self, results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Normalise, deduplicate, and filter CAS results via ChunkProcessor.

        Args:
            results: Raw CAS search result dicts from search_vector_store().

        Returns:
            Processed list of chunk dicts with index, content, score, source fields.
        """
        return self.chunk_processor.process(results)

    def _is_history_anchor_turn(self, turn) -> bool:
        """Return True when a turn is safe to use as the active retrieval anchor."""
        if not turn.sources or any(source in ("[meta]", "[user-context]") for source in turn.sources):
            return False

        answer = (turn.answer or "").strip().lower()
        if not answer:
            return False
        if "not available in the provided context sources" in answer:
            return False
        if "no relevant documents were found" in answer:
            return False
        if answer.startswith("[llm_"):
            return False
        return True

    def _build_history_block(self, session, max_turns: Optional[int] = None) -> str:
        """Build a compact history block from recent session turns.

        Includes:
        - running_summary (if present) as a compacted backdrop
        - [user-context] turns as "Personal facts:" rather than numbered turns
        - All other turns as numbered Turn N: Q/A lines
        - Active topic, active answer, and active source for anchor resolution

        Off-topic turns (no sources, or unavailable-answer turns) are excluded
        from the numbered display so they cannot pollute the rewrite context.
        """
        if session is None or (not session.turns and not session.running_summary):
            return ""

        max_turns = max_turns if max_turns is not None else self.session_history_turns

        # Separate user-context turns from regular turns
        regular_turns = [t for t in session.turns if not (
            t.sources and any(s == "[user-context]" for s in t.sources)
        )]
        personal_turns = [t for t in session.turns if (
            t.sources and any(s == "[user-context]" for s in t.sources)
        )]

        if not regular_turns and not session.running_summary and not personal_turns:
            return ""

        # All regular turns are displayed (meta, no-source, failed turns included).
        # Only the "anchor" turn — used for Active topic/answer/source — is
        # restricted to turns that passed document retrieval, so that the rewrite
        # context isn't poisoned by failed or off-topic turns.
        recent = regular_turns[-max_turns:]
        active_turn = next(
            (turn for turn in reversed(regular_turns) if self._is_history_anchor_turn(turn)),
            None,
        )

        lines = ["[CONVERSATION HISTORY]"]

        # Include running summary if one exists (from prior compaction)
        if session.running_summary:
            lines.append(f"Summary: {session.running_summary}")

        # Explicit subject — set from the QUESTION text at resolution time
        # (see LLMService._extract_subject_from_text, called from
        # api_server.generate() right after a query is resolved), not
        # derived from answer text. More reliable than "Active answer" for
        # subject anchoring: it survives a "not available" turn, and
        # doesn't depend on the answer happening to restate the entity name.
        if getattr(session, "active_subject", ""):
            lines.append(f"Explicit subject: {session.active_subject}")

        # Include personal facts from [user-context] turns
        if personal_turns:
            lines.append("Personal facts:")
            for t in personal_turns:
                lines.append(f"  {t.query}")

        # Include numbered turns
        for i, turn in enumerate(recent, start=1):
            lines.append(f"Turn {i}: Q: {turn.query} | A: {turn.answer}")

        # Active turn anchor — provides stable subject/metric context for rewrites.
        # Active topic: the original user query (may be a short fragment; used only
        #               as a fallback label — do NOT derive subject from it alone).
        # Active answer: the last factual answer; used as a secondary subject anchor
        #                when no Explicit subject: line exists.
        # Active source: the document that grounded the last answer.
        if active_turn is not None:
            lines.append(f"Active topic: {active_turn.query}")
            lines.append(f"Active answer: {active_turn.answer}")
            active_sources = [s for s in (active_turn.sources or []) if s not in ("[meta]", "[user-context]")]
            if active_sources:
                lines.append(f"Active source: {active_sources[0]}")

        lines.append("[END HISTORY]")
        result = "\n".join(lines)
        logger.debug(
            "history_block turns=%d active_topic=%r active_source=%r",
            len(recent),
            active_turn.query if active_turn else None,
            (
                [s for s in (active_turn.sources or []) if s not in ("[meta]", "[user-context]")][:1] or [None]
            )[0] if active_turn else None,
        )
        return result

    def needs_compaction(self, session) -> bool:
        """Cheap check: does this session's history exceed the compaction budget?

        Delegates to the same token-budget logic that now lives on SessionStore
        so the two implementations stay in sync.  Kept here for backward
        compatibility with existing test callers.
        """
        if session is None or not session.turns:
            return False
        full_text = " ".join(f"{t.query} {t.answer}" for t in session.turns)
        budget = int(self.session_max_context_tokens * self.session_compact_threshold)
        return estimate_tokens(full_text) > budget

    def _compact_history(self, session) -> Optional[Dict[str, Any]]:
        """Compute a compaction plan when the session context budget is exceeded.

        Checks whether the serialised history exceeds
        session_max_context_tokens * session_compact_threshold tokens.
        If so, summarises all but the last session_keep_turns turns with the LLM
        and returns a plan the caller applies via SessionStore.set_summary().

        This method is intentionally side-effect-free with respect to the
        session object — SessionStore owns the lock that guards concurrent
        mutation, so LLMService only computes; it never assigns directly to
        session.turns / session.running_summary.

        Returns:
            None if compaction isn't needed or the summarisation call failed
            (session is left unchanged in either case).
            Otherwise a dict: {"summary": str, "turns_to_keep": List[Turn]}.
        """
        if not self.needs_compaction(session):
            return None

        keep = self.session_keep_turns
        turns_to_fold = session.turns[:-keep] if keep > 0 else session.turns
        turns_to_keep = session.turns[-keep:] if keep > 0 else []

        if not turns_to_fold:
            return None

        fold_text = "\n".join(
            f"Q: {t.query}\nA: {t.answer}" for t in turns_to_fold
        )
        summary_prefix = f"Prior summary: {session.running_summary}\n\n" if session.running_summary else ""
        compact_prompt = (
            f"{summary_prefix}"
            "Summarise the following conversation turns into one concise paragraph "
            "that captures the key topics, events, states, and facts discussed. "
            "Preserve specific event names, state names, and numeric values.\n\n"
            f"{fold_text}\n\nSummary:"
        )
        summary = self._ask_llm(compact_prompt, max_tokens=self.session_compact_summary_tokens)
        if summary.startswith("[LLM_") or not summary:
            logger.debug("compact_history_skipped llm_failure session=%s", session.session_id)
            return None

        logger.debug(
            "compact_history_computed session=%s folded_turns=%d kept_turns=%d",
            session.session_id, len(turns_to_fold), len(turns_to_keep),
        )
        return {"summary": summary, "turns_to_keep": turns_to_keep}

    _EXPLICIT_SUBJECT_RE = re.compile(r'^Explicit subject:\s*(.+)$', re.MULTILINE)

    def _parse_explicit_subject(self, history_block: str) -> Optional[str]:
        """Read the "Explicit subject:" line already embedded in history_block.

        Cheap, deterministic — no LLM call. Preferred over
        _extract_active_subject, which has to guess the subject from prior
        answer text and can drift when that text doesn't happen to restate
        the entity name.
        """
        if not history_block:
            return None
        m = self._EXPLICIT_SUBJECT_RE.search(history_block)
        return m.group(1).strip() if m else None

    # Filler openers that are transparent to the user but hurt CAS semantic
    # retrieval — stripped from self-contained queries before they go to CAS.
    # Deliberately does NOT include wh-words ("How many", "What is", etc.)
    # because those are load-bearing parts of the retrieval query.
    # e.g. "Now Florida — how many cases?" → "Florida — how many cases?"
    #      "What about Tennessee — how many?" → "Tennessee — how many?"
    _FILLER_RE = re.compile(
        r'^(now|what about|how about|and the|and)\b\s*',
        re.IGNORECASE,
    )

    # Full opener list — used by _extract_subject_from_text to skip past
    # question preamble before scanning for the named entity.
    _OPENER_RE = re.compile(
        r'^(how many|how much|what is|what was|what are|what were|what percentage|'
        r'when did|where is|which|who|tell me|give me|list|describe|explain|'
        r'now|what about|how about|and the|and)\b\s*',
        re.IGNORECASE,
    )

    def _extract_subject_from_text(self, text: str) -> Optional[str]:
        """Extract the named subject from a question — regex first, LLM fallback.

        Tries a fast regex scan for a capitalised named entity (proper noun)
        before falling back to an LLM call.  The LLM call is only made when
        the regex finds nothing — i.e. the question contains no obvious named
        subject and we genuinely need the model to infer one.

        This avoids an extra LLM round-trip on every self-contained question
        (e.g. "How many cases for Winter Storm Blair?" → regex finds "Winter
        Storm Blair" immediately, no LLM needed).

        Importantly, the scan starts from the FIRST capitalised word in the
        (opener-stripped) sentence — not from the second word.  This means
        "Maryland Severe Weather — hotline calls?" correctly extracts
        "Maryland Severe Weather" rather than the erroneous "Severe Weather".
        """
        if not text:
            return None

        # Fast path: strip leading wh-word / filler openers, then extract the
        # first run of consecutive capitalised tokens.
        stripped = text.strip()
        # Remove leading question opener ("How many", "What about", "Now", …)
        scan = self._OPENER_RE.sub("", stripped).strip()
        # Find the first capitalised word anywhere in the remaining text
        first_cap = re.search(r'[A-Z][a-zA-Z]+', scan)
        if first_cap:
            start = first_cap.start()
            tokens = []
            for word in scan[start:].split():
                if not word:
                    break
                clean = word.rstrip("?.,!:—–-")
                # Strip possessives so "Georgia's" → "Georgia"
                clean = re.sub(r"'s$", "", clean)
                if clean and (clean[0].isupper() or (tokens and clean.lower() in ("of", "&"))):
                    tokens.append(clean)
                else:
                    break
            if tokens:
                return " ".join(tokens)

        # Slow path: ask the LLM only when the regex found nothing.
        # This handles abbreviations, shorthand, and non-capitalised subjects.
        prompt = (
            f'Question: "{text}"\n\n'
            "Identify the specific subject this question is about — the exact "
            "named entity, event, or location. Output ONLY that subject as a "
            "short noun phrase. Nothing else. If the question does not name a "
            "specific subject, output NONE."
        )
        raw = self._ask_llm(prompt, max_tokens=20)
        if raw.startswith("[LLM_") or not raw:
            return None
        subject = raw.strip().strip(" .\"'")
        if not subject or subject.upper() == "NONE":
            return None
        return subject

    def _extract_active_subject(self, history_block: str) -> Optional[str]:
        """Ask the LLM for the active subject — reads Turn Q: lines, not Active answer:.

        Fallback used only when no "Explicit subject:" line is available yet.
        Reads the Turn Q: lines in reverse so the subject is anchored to the
        last question the user explicitly named a subject in — not to the
        answer text, which can drift when a prior answer discussed the wrong
        entity.
        """
        if not history_block:
            return None
        prompt = (
            f"{history_block}\n\n"
            "Read the Turn Q: lines above from most recent to oldest. "
            "Find the last Turn Q: line where the user explicitly named a subject "
            "(a proper noun, named event, or location). "
            "Output ONLY that subject as a short noun phrase. "
            "Nothing else. No punctuation, no explanation, no extra words. "
            "If no Turn Q: line explicitly names a subject, output NONE."
        )
        raw = self._ask_llm(prompt, max_tokens=20)
        if raw.startswith("[LLM_") or not raw:
            return None
        subject = raw.strip().strip(" .\"'")
        if not subject or subject.upper() == "NONE":
            return None
        return subject

    def _resolve_query_from_block(self, query: str, history_block: str) -> str:
        """Rewrite a follow-up using an already-built history block string.

        Preferred over _resolve_query when the caller holds a frozen snapshot of
        history (e.g. captured at the top of a generate loop) and must not be
        affected by subsequent session mutations within the same request.

        Self-contained questions (those that already carry their own subject and
        metric) bypass the LLM rewriter entirely so the rewriter cannot corrupt
        metric types, substitute units, or change the question.

        Bare metric fragments ("Organizations?", "Volunteer value?") bypass
        the LLM rewriter too — the metric wording is concatenated onto a
        separately-extracted subject via template, so the LLM never gets a
        chance to re-author (and potentially corrupt) the metric.

        Anything else (a full clause with a dangling pronoun, e.g.
        "What was the volunteer value there?") goes through the LLM rewrite,
        since there the metric is already spelled out in the user's own
        words and the model's only job is pronoun substitution.
        """
        if not history_block:
            return query

        # If the question is already fully specified, skip rewriting.
        # This prevents metric substitution on questions like
        # "How many hotline calls for the Central Tornadoes event?"
        if is_self_contained(query):
            # Strip only filler openers ("Now", "What about", etc.) — NOT
            # wh-words, which are load-bearing parts of the retrieval query.
            # e.g. "Now Florida — how many cases?" → "Florida — how many cases?"
            # but "How many hotline calls for X?" stays unchanged.
            clean = self._FILLER_RE.sub("", query).strip()
            result = clean if len(clean) >= 8 else query
            logger.info("resolve_query bypassed (self-contained) original=%r result=%r", query, result)
            return result

        # Bare metric fragments ("Organizations?", "Muck-out percentage?"):
        # extract only the subject and concatenate — never hand the metric
        # wording itself to the LLM to re-author. Falls through to the full
        # rewrite below only if subject extraction fails.
        if is_bare_metric_fragment(query):
            subject = self._parse_explicit_subject(history_block) or self._extract_active_subject(history_block)
            if subject:
                # Strip trailing location pronoun ("there", "it") before
                # templating — "Organizations there?" → "Organizations for X"
                metric = strip_trailing_pronoun(query).rstrip("?").strip()
                resolved = f"{metric} for {subject}"
                logger.info(
                    "resolve_query template original=%r subject=%r resolved=%r",
                    query, subject, resolved,
                )
                return resolved
            logger.info(
                "resolve_query template_fallback original=%r (subject extraction failed, using full rewrite)",
                query,
            )

        rewrite_prompt = (
            f"{history_block}\n\n"
            f'New question: "{query}"\n\n'
            "Your task: rewrite the new question as ONE standalone search query by substituting "
            "any pronouns or references (it, there, that, those, they) with the explicit subject.\n\n"
            "Step 1 — identify the SUBJECT.\n"
            "  If 'Explicit subject:' is present above, use that subject verbatim — it is the "
            "confirmed subject of the most recently resolved question and is the most reliable anchor.\n"
            "  'there', 'it', 'that', 'those', 'they' ALL refer to the Explicit subject — replace them.\n"
            "  Example: Explicit subject = 'Hurricanes Helene & Milton', question = "
            "'How many Georgia cases were created after that?' "
            "→ output: 'How many Georgia cases were created after Hurricanes Helene & Milton?'\n"
            "  Otherwise, scan the Turn lines from most recent to oldest for the last "
            "explicitly named subject (proper noun, named event, or location).\n"
            "  Only switch the subject if the NEW question itself explicitly names a different one.\n\n"
            "Step 2 — identify the METRIC.\n"
            "  Copy the metric WORD FOR WORD from the new question. Do NOT paraphrase or substitute.\n"
            "  e.g. 'volunteer value' stays 'volunteer value'; 'what percentage' stays 'what percentage'.\n"
            "  Do NOT copy the metric from any prior turn or from 'Active answer:'.\n\n"
            "Step 3 — combine subject + metric into one plain English query, preserving "
            "the question structure (if the question asks 'how many', keep 'how many'; "
            "if it asks 'what percentage', keep 'what percentage').\n\n"
            "IMPORTANT: If the new question contains a named subject that differs from the history "
            "subject (e.g. 'Rochester', a city unrelated to any disaster), do NOT replace it. "
            "Output the question as-is with only pronouns substituted.\n\n"
            "Output format: one plain English search query on a single line. "
            "No markdown, no bullets, no numbered steps, no explanation — just the query."
        )
        raw = self._ask_llm(rewrite_prompt, max_tokens=60)
        if raw.startswith("[LLM_") or not raw:
            return query

        # Sanitise: take only the first non-empty, non-markdown line.
        rewritten = self._sanitise_rewrite(raw, query)

        # Safety check A: if the rewriter dropped a capitalised proper noun that
        # was in the original query, the model substituted the wrong subject — fall back.
        # Exclude common sentence-starter words that are capitalised only by position.
        _SENTENCE_STARTERS = {
            "How", "What", "Where", "When", "Which", "Who", "Why",
            "The", "A", "An", "Is", "Are", "Was", "Were", "Do", "Does",
            "Did", "Can", "Could", "Would", "Will", "Has", "Have", "Had",
        }
        original_caps = set(re.findall(r'\b[A-Z][a-z]+\b', query)) - _SENTENCE_STARTERS
        rewritten_caps = set(re.findall(r'\b[A-Z][a-z]+\b', rewritten)) - _SENTENCE_STARTERS
        if original_caps and not original_caps.issubset(rewritten_caps | {w.lower() for w in rewritten_caps}):
            logger.info("resolve_query rewrite_dropped_noun original=%r rewritten=%r — using original", query, rewritten)
            rewritten = query

        # Safety check B: if the rewriter dropped the metric words from the
        # original query (e.g. rewrote "volunteer value there?" into a copy of
        # the prior question), detect the loss and fall back to the original.
        # We check that at least one significant content word (≥5 chars, not a
        # stop word) from the original still appears in the rewritten query.
        _STOP_WORDS = {
            "about", "after", "before", "being", "could", "during",
            "have", "many", "much", "right", "should", "since",
            "there", "these", "those", "their", "would", "which",
            "where", "while", "other", "under", "until", "using",
        }
        original_content = {
            w.lower() for w in re.findall(r'\b[a-z]{5,}\b', query.lower())
            if w.lower() not in _STOP_WORDS
        }
        if original_content:
            rewritten_lower = rewritten.lower()
            if not any(w in rewritten_lower for w in original_content):
                logger.info(
                    "resolve_query rewrite_dropped_metric original=%r rewritten=%r — using original",
                    query, rewritten,
                )
                rewritten = query

        logger.info("resolve_query original=%r rewritten=%r", query, rewritten)
        return rewritten

    @staticmethod
    def _sanitise_rewrite(raw: str, fallback: str) -> str:
        """Extract the first usable line from a rewriter response.

        Strips markdown formatting, bullets, labels, and blank lines.
        Falls back to `fallback` if nothing clean can be extracted.
        """
        for line in raw.splitlines():
            # Strip markdown bold/italic, bullets, numbered-list markers, and labels
            line = re.sub(r'^[\s\*\#\-\d\.\)]+', '', line)
            line = re.sub(r'\*+', '', line)
            # Drop lines that look like history fragments (contain " | A: " or " | Q: ")
            if ' | A: ' in line or ' | Q: ' in line:
                continue
            # Drop lines that start with "Rewrite:" or similar meta-labels
            if re.match(r'^(rewrite|standalone|query|result|answer)[:\s]', line, re.IGNORECASE):
                line = re.sub(r'^(rewrite|standalone|query|result|answer)[:\s]*', '', line, flags=re.IGNORECASE)
            line = line.strip()
            if len(line) >= 8:  # ignore fragments shorter than 8 chars
                return line
        return fallback

    # [CHUNK:<tool_name>] signal emitted by the LLM when it needs more context.
    # The tool name is optional — bare [CHUNK] falls back to the default tool
    # for backward compatibility with prompts that don't include the tool syntax.
    _CHUNK_SIGNAL = re.compile(r'\[CHUNK(?::([^\]]+))?\]\s*(.+)', re.IGNORECASE)
    _RETRY_SIGNAL = re.compile(r'\[RETRY\]\s*(.+)', re.IGNORECASE)
    # A well-formed answer already has FULL_ANSWER: and [SOURCE:] — no need to
    # run a second verification pass for those.
    _WELL_FORMED_ANSWER = re.compile(
        r'FULL_ANSWER\s*:.+\[SOURCE\s*:\s*(\d+|N/A)\]',
        re.IGNORECASE | re.DOTALL,
    )

    def _run_retrieval_loop(
        self,
        query: str,
        vector_store_id: str,
        max_results: int = None,
        min_score: float = None,
        history_block: str = "",
        # Legacy positional alias kept for callers that pass max_results as chunk_cap
        chunk_cap: int = None,
    ) -> Dict[str, Any]:
        """Run the retrieval loop: fetch → decide → refetch until answered or max iterations.

        Before the loop starts, a dedicated tool-routing LLM call selects the
        best starting tool using ``tool_router_prompt.md`` — a tiny, example-heavy
        prompt whose only job is to output one tool name.  This keeps tool-selection
        logic completely separate from answer-extraction logic and avoids the
        attention-dilution problem that occurs when both compete inside one prompt.

        The loop then drives with three signals:
          - ``FULL_ANSWER: ... [SOURCE: N]``   — loop exits, answer returned.
          - ``[CHUNK:<tool>] <query>``          — fetch more context from the named
                                                  tool and loop again.
          - ``[RETRY] <query>``                 — verification step rejected the answer;
                                                  refetch with the refined query.
        """
        # Support both max_results and the legacy chunk_cap name used by tests
        if max_results is None and chunk_cap is not None:
            max_results = chunk_cap
        if max_results is None:
            max_results = self.default_max_results
        if min_score is None:
            min_score = self.default_min_score

        all_chunks: List[Dict[str, Any]] = []
        fetched_queries: List[str] = []
        current_query = query

        # ── Pre-loop tool routing ────────────────────────────────────────────
        # Skipped when TOOL_ROUTER_ENABLED=false or only one tool is registered.
        tool_names = self.tool_registry.tool_names
        if self.tool_router_enabled and len(tool_names) > 1:
            routing_prompt = self.prompt_builder.build_tool_selection_prompt(
                query=query,
                available_tools=tool_names,
            )
            raw_tool = self._ask_llm(routing_prompt, max_tokens=10)
            # Sanitise: take the first non-empty word, strip punctuation.
            chosen = raw_tool.strip().split()[0].strip(".,!?\"'").lower() if raw_tool.strip() else ""
            if chosen and self.tool_registry.is_registered(chosen):
                current_tool = chosen
                logger.info("tool_router selected tool=%r for query=%r", current_tool, query)
            else:
                current_tool = self.tool_registry.default_tool
                logger.info(
                    "tool_router output=%r not recognised — defaulting to tool=%r",
                    raw_tool[:40], current_tool,
                )
        else:
            current_tool = self.tool_registry.default_tool
        # ────────────────────────────────────────────────────────────────────

        logger.info(
            "retrieval_loop start query=%r tool=%r all_tools=%r",
            query, current_tool, tool_names,
        )

        for iteration in range(1, self.retrieval_loop_max_iter + 2):
            loop_key = (current_tool, current_query)
            if loop_key in fetched_queries:
                logger.debug("retrieval_loop duplicate tool=%r query=%r — stopping", current_tool, current_query)
                break
            fetched_queries.append(loop_key)

            # Dispatch to whichever tool the LLM requested (default: "cas").
            logger.info(
                "retrieval_loop dispatch iter=%d tool=%r query=%r",
                iteration, current_tool, current_query,
            )
            result = self.tool_registry.call(
                current_tool,
                current_query,
                vector_store_id=vector_store_id,
            )
            if result.get("status") != "success":
                logger.warning(
                    "retrieval_loop tool_error tool=%r iter=%d query=%r error=%r — stopping loop",
                    current_tool, iteration, current_query, result.get("error"),
                )
                break

            new_chunks = self._extract_chunks(result.get("data", []))
            logger.info(
                "retrieval_loop fetched iter=%d tool=%r raw=%d kept=%d cumulative=%d",
                iteration, current_tool,
                len(result.get("data", [])), len(new_chunks),
                len(all_chunks) + sum(
                    1 for c in new_chunks
                    if c["content"] not in {ch["content"] for ch in all_chunks}
                ),
            )
            existing_content = {chunk["content"] for chunk in all_chunks}
            for chunk in new_chunks:
                if chunk["content"] not in existing_content:
                    all_chunks.append(chunk)
                    existing_content.add(chunk["content"])

            all_chunks = [{**chunk, "index": i} for i, chunk in enumerate(
                sorted(all_chunks, key=lambda c: c.get("score") or 0.0, reverse=True),
                start=1,
            )]

            if iteration > self.retrieval_loop_max_iter:
                logger.info(
                    "retrieval_loop max_iter=%d reached — forcing answer with %d chunks",
                    self.retrieval_loop_max_iter, len(all_chunks),
                )
                return {
                    "chunks": all_chunks,
                    "final_prompt": self.prompt_builder.build_prompt(query, all_chunks),
                    "iterations": iteration,
                    "forced": True,
                }

            decision = self._ask_llm(
                self.prompt_builder.build_retrieval_prompt(
                    query, all_chunks,
                    history_block=history_block,
                    iteration=iteration,
                    available_tools=self.tool_registry.tool_names,
                    tool_descriptions=self.tool_registry.tool_descriptions,
                )
            )
            logger.info(
                "retrieval_loop llm_decision iter=%d current_tool=%r decision=%r",
                iteration, current_tool, decision[:120],
            )

            if decision.startswith("[LLM_") or not decision:
                logger.warning("retrieval_loop llm_unavailable iter=%d sentinel=%r", iteration, decision[:60])
                break

            # Parse [CHUNK:<tool>] <query> — or bare [CHUNK] <query> for compat.
            chunk_match = self._CHUNK_SIGNAL.match(decision)
            if chunk_match:
                tool_name = (chunk_match.group(1) or "").strip() or self.tool_registry.default_tool
                refined = chunk_match.group(2).strip()
                if refined:
                    current_tool = tool_name
                    current_query = refined
                    logger.info(
                        "retrieval_loop llm_requested_tool tool=%r query=%r",
                        current_tool, current_query,
                    )
                    continue
                break

            # Skip verification entirely when:
            # (a) FACT_CHECK_ENABLED=false (disabled globally), OR
            # (b) the decision is already well-formed AND looks like a single-value
            #     answer (not a breakdown list), OR
            # (c) the question is a multi-subject compare (verifier can't correct those).
            # Only run the verifier where it can actually add value.
            is_compare = (
                " and " in query.lower()
                or "compare" in query.lower()
                or "comparison" in query.lower()
            )
            # Detect breakdown answers: multiple dollar amounts joined with commas/+,
            # or patterns like "$X in Y services, $Z in W services".
            # These must go through the verifier even when the format is well-formed.
            is_breakdown = bool(re.search(
                r'\$[\d,.]+[kKmMbB]?\s+in\b|\$[\d,.]+[kKmMbB]?\s*[\+,]\s*\$',
                decision,
                re.IGNORECASE,
            ))
            if not self.fact_check_enabled or is_compare or (
                self._WELL_FORMED_ANSWER.search(decision) and not is_breakdown
            ):
                verified_answer = decision
            else:
                verified_answer = self._ask_llm(
                    self.prompt_builder.build_verification_prompt(query, all_chunks, decision)
                )
                if verified_answer.startswith("[LLM_") or not verified_answer:
                    verified_answer = decision

                retry_match = self._RETRY_SIGNAL.match(verified_answer)
                if retry_match and iteration <= self.retrieval_loop_max_iter:
                    refined = retry_match.group(1).strip()
                    if refined and (current_tool, refined) not in fetched_queries:
                        current_query = refined
                        # [RETRY] always re-uses the same tool that produced the bad answer.
                        continue
                    verified_answer = decision

            return {
                "chunks": all_chunks,
                "final_prompt": None,
                "answer_text": verified_answer,
                "iterations": iteration,
                "forced": False,
            }

        return {
            "chunks": all_chunks,
            "final_prompt": self.prompt_builder.build_prompt(query, all_chunks),
            "iterations": len(fetched_queries),
            "forced": True,
        }

    def _build_chat_payload(self, prompt: str, stream: bool, max_tokens: Optional[int] = None) -> Dict[str, Any]:
        """Build an OpenAI-compatible /v1/chat/completions request payload."""
        return {
            "model": self.llm_model,
            "messages": [{"role": "user", "content": prompt}],
            "stream": stream,
            "max_tokens": max_tokens if max_tokens is not None else self.llm_max_tokens,
        }

    def _auth_headers(self) -> Dict[str, str]:
        """Return an Authorization header dict if LLM_API_KEY is configured."""
        if self.llm_api_key:
            return {"Authorization": f"Bearer {self.llm_api_key}"}
        return {}

    def _call_llm(self, prompt: str, max_tokens: Optional[int] = None) -> Iterator[str]:
        """Call the OpenAI-compatible /v1/chat/completions API with streaming."""
        payload = self._build_chat_payload(prompt, stream=True, max_tokens=max_tokens)
        try:
            with requests.post(
                f"{self.llm_base_url}/v1/chat/completions",
                json=payload,
                headers=self._auth_headers(),
                stream=True,
                timeout=self.request_timeout,
            ) as response:
                response.raise_for_status()
                for line in response.iter_lines():
                    if not line:
                        continue
                    text = line.decode("utf-8")
                    if text.startswith("data: "):
                        text = text[len("data: "):]
                    if text.strip() == "[DONE]":
                        break
                    try:
                        chunk = json.loads(text)
                        token = (
                            chunk.get("choices", [{}])[0]
                            .get("delta", {})
                            .get("content", "")
                        )
                        if token:
                            yield token
                    except json.JSONDecodeError:
                        continue
        except (RequestsConnectionError, Timeout):
            logger.warning("llm_unreachable url=%s", self.llm_base_url)
            yield f"[LLM_UNAVAILABLE url={self.llm_base_url} model={self.llm_model}]"
        except requests.exceptions.HTTPError as exc:
            status_code = exc.response.status_code if exc.response is not None else "unknown"
            logger.warning("llm_http_error status=%s url=%s model=%s", status_code, self.llm_base_url, self.llm_model)
            if status_code == 404:
                yield f"[LLM_NOT_FOUND url={self.llm_base_url} model={self.llm_model}]"
            else:
                yield f"[LLM_HTTP_ERROR status={status_code} url={self.llm_base_url} model={self.llm_model}]"
        except Exception as exc:
            logger.warning("llm_stream_error error=%r", exc)
            yield f"[LLM_UNAVAILABLE url={self.llm_base_url} model={self.llm_model}]"

    def _ask_llm(self, prompt: str, max_tokens: Optional[int] = None) -> str:
        """Call the LLM and return the complete response as a single string."""
        return "".join(self._call_llm(prompt, max_tokens=max_tokens)).strip()

    def _parse_structured_answer(self, llm_answer: str) -> Dict[str, Any]:
        """Parse the model response, extracting the answer text and source number."""
        answer_text = re.sub(r'^\s*\[CHUNK\].*$', '', llm_answer, flags=re.IGNORECASE | re.MULTILINE).strip()

        full_match = re.search(
            r'FULL_ANSWER:\s*(.+?)(?:\n\n|\n\[SOURCE|\n\(SOURCE|\nSOURCE|\nSource|$)',
            answer_text, re.IGNORECASE | re.DOTALL
        )
        full_answer = full_match.group(1).strip() if full_match else None

        source_match = re.search(r'[\[\(]?\bSOURCE[:\s]+(\d+)[\]\)]?', answer_text, re.IGNORECASE)
        source_number = None
        if source_match:
            try:
                source_number = int(source_match.group(1))
            except ValueError:
                pass

        return {
            "answer": full_answer if full_answer else answer_text,
            "source_number": source_number,
        }

    def _get_vector_store_id(self) -> Union[str, Dict[str, Any]]:
        """Fetch vector stores from CAS and return the first available ID."""
        result = self.cas_client.list_vector_stores()
        if result.get("status") != "success":
            return {"status": "error", "error": "Unable to retrieve vector stores from CAS"}
        vector_stores = result.get("vector_stores", [])
        if not isinstance(vector_stores, list) or not vector_stores:
            return {"status": "error", "error": "CAS returned no vector stores"}
        available_ids = [s.get("id") for s in vector_stores if isinstance(s, dict) and s.get("id")]
        if not available_ids:
            return {"status": "error", "error": "No usable vector store IDs found"}
        return available_ids[0]