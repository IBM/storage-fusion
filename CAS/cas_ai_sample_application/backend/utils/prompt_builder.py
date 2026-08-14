"""
PromptBuilder — all LLM prompt construction for the RAG pipeline.

Responsibilities:
  1. Load system prompts from disk once at construction time.
       - tool_router_prompt.md  — tiny focused prompt used ONLY to select a tool
       - answer_prompt.md       — full extraction/answer prompt used by the loop
  2. Build the four prompt types the pipeline needs:
       - tool selection prompt  (build_tool_selection_prompt) — pre-loop tool routing
       - synthesis prompt       (build_prompt)                — final answer generation
       - retrieval prompt       (build_retrieval_prompt)      — loop decision + [CHUNK]
       - verification prompt    (build_verification_prompt)   — answer correctness check

Tool routing is now a separate LLM call that runs BEFORE the retrieval loop with a
tiny, example-heavy prompt.  The retrieval/synthesis prompts then use answer_prompt.md
which contains no tool-selection logic — keeping those prompts focused on extraction.

This module has NO knowledge of CAS, LLM I/O, sessions, or query rewriting.
It only knows how to assemble text from chunks, a question, and a history block.
"""

from typing import Any, Dict, List, Optional
import logging
import os

logger = logging.getLogger(__name__)

# Sent back by _build_prompt / _build_retrieval_prompt when retrieval produced
# no usable chunks.  Centralised here so the string is never duplicated across
# the codebase.
NO_DOCS_ANSWER = (
    "No relevant documents were found for this question. "
    "Try rephrasing your query, or check that the correct vector store is selected."
)


class PromptBuilder:
    """Assembles LLM prompts from retrieved chunks, a question, and history."""

    def __init__(
        self,
        system_prompt_path: Optional[str] = None,
        answer_prompt_path: Optional[str] = None,
        tool_router_prompt_path: Optional[str] = None,
    ) -> None:
        """Load system prompts from disk at construction time.

        Args:
            system_prompt_path:    Path to system_prompt.md (kept for backward
                                   compatibility — used as fallback if
                                   answer_prompt_path is not provided).
            answer_prompt_path:    Path to answer_prompt.md — the extraction
                                   prompt used by synthesis/retrieval/verification.
                                   Defaults to ``answer_prompt.md`` in backend/.
            tool_router_prompt_path: Path to tool_router_prompt.md — the tiny
                                   example-heavy prompt used ONLY for tool selection.
                                   Defaults to ``tool_router_prompt.md`` in backend/.
        """
        backend_dir = os.path.dirname(os.path.dirname(__file__))

        # answer_prompt.md is the primary extraction prompt.
        # Falls back to system_prompt.md so nothing breaks if the file is absent.
        if answer_prompt_path is None:
            answer_prompt_path = os.path.join(backend_dir, "answer_prompt.md")
        self.system_prompt = self._load(answer_prompt_path, fallback_path=os.path.join(backend_dir, "system_prompt.md"))

        # tool_router_prompt.md is loaded separately — used only by build_tool_selection_prompt.
        if tool_router_prompt_path is None:
            tool_router_prompt_path = os.path.join(backend_dir, "tool_router_prompt.md")
        self.tool_router_prompt = self._load(tool_router_prompt_path)

    # ------------------------------------------------------------------
    # Internal loader
    # ------------------------------------------------------------------

    @staticmethod
    def _load(path: str, fallback_path: Optional[str] = None) -> str:
        """Read a file and return its stripped contents.

        Args:
            path:          Primary file path to load.
            fallback_path: If provided and primary is missing, try this path next.
        """
        try:
            with open(path) as f:
                return f.read().strip()
        except FileNotFoundError:
            if fallback_path:
                logger.warning("prompt file not found at %s — trying fallback %s", path, fallback_path)
                try:
                    with open(fallback_path) as f:
                        return f.read().strip()
                except FileNotFoundError:
                    pass
            logger.warning("prompt file not found at %s — using hardcoded fallback", path)
            return "You are a helpful assistant that answers questions based on provided context."

    # ------------------------------------------------------------------
    # Shared helper
    # ------------------------------------------------------------------

    @staticmethod
    def _format_context(chunks: List[Dict[str, Any]]) -> str:
        """Sort chunks by score descending and format them as numbered sources."""
        sorted_chunks = sorted(chunks, key=lambda c: c.get("score") or 0.0, reverse=True)
        return "\n\n".join(f"[Source {c['index']}]\n{c['content']}" for c in sorted_chunks)

    # ------------------------------------------------------------------
    # Prompt builders
    # ------------------------------------------------------------------

    def build_tool_selection_prompt(
        self,
        query: str,
        available_tools: List[str],
    ) -> str:
        """Build the tool-selection prompt for the pre-loop routing call.

        Uses ``tool_router_prompt.md`` — a tiny, example-heavy prompt whose
        only job is to output one tool name.  This prompt is intentionally
        separate from the answer/retrieval prompts so it never competes with
        extraction rules for the model's attention.

        Args:
            query:           The (possibly rewritten) user question.
            available_tools: List of registered tool names from ToolRegistry.

        Returns:
            A prompt string that should produce exactly one tool name as output.
        """
        tool_list = ", ".join(available_tools)
        return (
            f"{self.tool_router_prompt}\n\n"
            f"Tools: {tool_list}\n"
            f"Question: {query}\n"
            "Answer:"
        )

    def build_prompt(
        self,
        query: str,
        chunks: List[Dict[str, Any]],
        history_block: str = "",
    ) -> str:
        """Build the final answer-synthesis prompt.

        Used when the retrieval loop has exhausted its iterations or the model
        chose to answer directly. The LLM receives all retrieved chunks and is
        asked to produce a FULL_ANSWER / [SOURCE: N] response.

        Args:
            query:         The (possibly rewritten) user question.
            chunks:        Processed chunk dicts from ChunkProcessor.
            history_block: Serialised conversation history, or empty string.
        """
        context = self._format_context(chunks)
        history_section = f"{history_block}\n\n" if history_block else ""
        return (
            f"{self.system_prompt}\n\n"
            f"{history_section}"
            f"Context Sources:\n{context}\n\n"
            f"Question: {query}\n"
            "Answer ONLY the question above. Be specific and direct.\n"
            "If the question asks for a total or headline value, do not answer with a category sub-total.\n"
            "If the question asks for a category percentage, return the percentage for that category's "
            "share of the total — not a status metric like \"% closed\" or \"% completed\".\n\n"
            "Response:"
        )

    def build_retrieval_prompt(
        self,
        query: str,
        chunks: List[Dict[str, Any]],
        history_block: str = "",
        iteration: int = 1,
        available_tools: Optional[List[str]] = None,
        tool_descriptions: Optional[Dict[str, str]] = None,
    ) -> str:
        """Build the retrieval-loop decision prompt.

        The model must either answer (FULL_ANSWER / [SOURCE: N]) or signal that
        it needs more context by naming a registered tool and a refined query.

        When ``available_tools`` contains more than one entry the prompt lists
        all tools (with descriptions when provided) so the LLM can choose the
        most appropriate one.  With only one tool the simpler ``[CHUNK] <query>``
        syntax is shown to keep the prompt compact.

        Args:
            query:            The (possibly rewritten) user question.
            chunks:           Processed chunk dicts from ChunkProcessor.
            history_block:    Serialised conversation history, or empty string.
            iteration:        Current loop iteration number (shown in the prompt).
            available_tools:  Registered tool names from ToolRegistry.tool_names.
                              Defaults to ``["cas"]`` when not provided.
            tool_descriptions: Mapping of tool name → description from
                              ToolRegistry.tool_descriptions. Used to help the
                              LLM pick the right tool when multiple are registered.
        """
        # Tool routing is now a separate pre-loop call — build_retrieval_prompt
        # always uses the default tool ("cas") for [CHUNK] signals.  The
        # available_tools / tool_descriptions args are kept for callers that
        # still pass them but are no longer used to build a multi-tool block.
        context = self._format_context(chunks)
        history_section = f"{history_block}\n\n" if history_block else ""
        default_tool = (available_tools or ["cas"])[0]

        chunk_instruction = (
            "If the sources above do NOT contain enough information to answer confidently,\n"
            "respond with exactly:\n"
            f"[CHUNK:{default_tool}] <a specific search query to retrieve the missing information>\n"
        )

        return (
            f"{self.system_prompt}\n\n"
            f"{history_section}"
            f"Context Sources (retrieval attempt {iteration}):\n{context}\n\n"
            f"Question: {query}\n"
            "Answer ONLY the question above.\n\n"
            "CRITICAL MATCHING RULES — violating any of these is a wrong answer:\n"
            "1. Subject match: the answer must come from a source that covers the exact subject "
            "(entity, location, period, or named event) the question is asking about.\n"
            "   - If the question names a specific event or location, use ONLY sources about that "
            "event — not sources about other events that happen to mention a similar metric.\n"
            "   - If multiple different events or locations appear in the retrieved sources, identify "
            "which source is about the questioned subject and use only that source.\n"
            "   - 'there', 'it', 'that', 'those' all refer to the subject identified in the question "
            "or the active history subject — resolve the pronoun before selecting a source.\n"
            "2. Metric match: answer with the exact metric type the question requests.\n"
            "   - If the question asks for a count of one entity type (e.g. 'cases'), return the count "
            "for that entity type ONLY — do NOT substitute a count of a different entity type "
            "(e.g. organizations, volunteers, counties) even if both counts appear in the same source.\n"
            "   - If the question asks for a category percentage, return that category's share of the "
            "total — NOT a status percentage (e.g. '% closed', '% completed', '% resolved').\n"
            "   - If the question asks for a total or headline value, return that single headline "
            "figure — NOT a breakdown list of sub-values (e.g. '$X for A, $Y for B').\n"
            "   - If the question asks for a subject-specific count, return the count for that subject "
            "— NOT a cumulative or multi-subject aggregate total.\n"
            "3. Source match: prefer the source whose content most closely matches the subject implied "
            "by the question and the active topic from history.\n\n"
            "Do not stitch together unrelated facts from different sources or different metrics.\n\n"
            f"{chunk_instruction}\n"
            "If the sources above DO contain enough information, respond in exactly this format:\n"
            "FULL_ANSWER: [your answer in 1-3 sentences]\n"
            "[SOURCE: N]\n"
            "Do NOT write anything after [SOURCE: N] — no notes, no explanations, no caveats.\n\n"
            "Response:"
        )

    def build_verification_prompt(
        self,
        query: str,
        chunks: List[Dict[str, Any]],
        answer_text: str,
    ) -> str:
        """Build the answer-verification prompt.

        The model must confirm, correct, or request a retry ([RETRY] <query>).

        Args:
            query:       The (possibly rewritten) user question.
            chunks:      The same chunks used to generate ``answer_text``.
            answer_text: The candidate answer from the retrieval step.
        """
        context = self._format_context(chunks)
        return (
            f"{self.system_prompt}\n\n"
            f"Context Sources:\n{context}\n\n"
            f"Question: {query}\n"
            f"Candidate answer:\n{answer_text}\n\n"
            "Verify the candidate answer against ALL of the following rejection criteria.\n"
            "Reject if ANY of the following are true:\n"
            "- The answer is for the wrong subject (wrong entity, location, period, or named item)\n"
            "- The answer uses the wrong metric type:\n"
            "    * A status percentage (e.g. \"% closed\", \"% completed\", \"% resolved\") when the "
            "question asks for a category-composition percentage\n"
            "    * A breakdown of components (e.g. \"$X for category A + $Y for category B\") when the "
            "question asks for a single total or headline value\n"
            "    * A cumulative or multi-subject aggregate when the question asks for a subject-specific "
            "count or value\n"
            "    * A count of the wrong entity type\n"
            "- The answer combines numbers from unrelated subjects or sources\n"
            "- The answer has no clear supporting source number\n"
            "- The supporting source does not match the subject implied by the question\n\n"
            "You have three options:\n"
            "1. If the candidate answer passes ALL checks, return it unchanged in exactly this format:\n"
            "FULL_ANSWER: [answer]\n"
            "[SOURCE: N]\n"
            "2. If the candidate answer fails a check but the sources above contain the correct single "
            "headline answer, replace it:\n"
            "FULL_ANSWER: [corrected answer — the single headline figure, not a breakdown]\n"
            "[SOURCE: N]\n"
            "3. If the current sources do not contain the correct answer, respond with exactly:\n"
            "[RETRY] <a better retrieval query that would fetch the headline total directly>\n\n"
            "If the sources clearly show the answer is unavailable, return exactly:\n"
            "FULL_ANSWER: The information needed to answer this question is not available in the "
            "provided context sources.\n"
            "[SOURCE: N/A]\n\n"
            "Response:"
        )
