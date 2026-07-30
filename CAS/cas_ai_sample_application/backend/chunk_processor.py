"""
ChunkProcessor — post-retrieval normalization and filtering of CAS search results.

Responsibilities:
  1. normalize raw CAS content payloads (list-of-typed-items) into plain text.
  2. Build normalized chunk records from raw CAS result dicts.
  3. Deduplicate chunks returned twice by CAS for the same source file.
  4. Apply a dominant-source filter to prevent cross-document contamination.
  5. Reindex chunks 1..N after filtering.

Configuration is read from environment variables so callers don't need to
thread tuning values through every call site.
"""

from typing import Any, Dict, List, Optional
import ast
import os
import re


class ChunkProcessor:
    """Normalize, deduplicate, and filter CAS search result chunks."""

    def __init__(
        self,
        max_chunk_chars: Optional[int] = None,
        dominant_gap_threshold: Optional[float] = None,
        normalize_fn=None,
    ):
        """
        Args:
            max_chunk_chars: Hard-truncate content at this many characters
                (0 or None = no limit). Defaults to RAG_MAX_CHUNK_CHARS env var.
            dominant_gap_threshold: Minimum score gap between the top source and
                the next-best source before weaker sources are dropped.
                Defaults to RAG_DOMINANT_GAP env var.
            normalize_fn: Callable(content) -> str used to convert raw CAS
                content payloads to plain text. Defaults to ChunkProcessor.normalize
                if not supplied. Override for testing or alternative CAS formats.
        """
        self.max_chunk_chars = (
            max_chunk_chars
            if max_chunk_chars is not None
            else int(os.getenv("RAG_MAX_CHUNK_CHARS", "0"))
        )
        self.dominant_gap_threshold = (
            dominant_gap_threshold
            if dominant_gap_threshold is not None
            else float(os.getenv("RAG_DOMINANT_GAP", "0.09"))
        )
        self._normalize = normalize_fn or ChunkProcessor.normalize

    # ------------------------------------------------------------------
    # CAS content normalization
    # ------------------------------------------------------------------

    @staticmethod
    def normalize(content: Any) -> str:
        """Convert a raw CAS content payload into plain text.

        CAS returns content as a list of typed items, e.g.:
            [{"type": "image", "text": "..."}, {"type": "text", "text": "..."}]

        Each type is handled differently:
          - text       → passed through as-is
          - image      → prefixed with an AI-estimate warning label
          - infographic → newlines inserted between OCR-jumbled number+label pairs
        """
        if isinstance(content, str):
            stripped = content.strip()
            if stripped.startswith("[{") or stripped.startswith("[{'"):
                try:
                    parsed = ast.literal_eval(stripped)
                    if isinstance(parsed, list):
                        return ChunkProcessor.normalize(parsed)
                except Exception:
                    pass
            return stripped
        if isinstance(content, list):
            parts: List[str] = []
            for item in content:
                if isinstance(item, dict):
                    item_type = item.get("type", "text")
                    text = str(item.get("text", "")).strip()
                    if text:
                        if item_type == "infographic":
                            text = ChunkProcessor._structure_infographic_text(text)
                        if item_type == "image":
                            text = (
                                "[AI image estimate — figures are approximate, "
                                "not exact document text]\n" + text
                            )
                        parts.append(text)
                elif item:
                    parts.append(str(item).strip())
            return "\n\n".join(part for part in parts if part)
        if isinstance(content, dict):
            return str(content.get("text", "")).strip()
        return str(content).strip()

    @staticmethod
    def _structure_infographic_text(text: str) -> str:
        """Insert newlines before number+label pairs in dense infographic OCR text.

        Turns e.g. "635 TENNESSEE CASES 17 DAMAGE REQUESTS"
        into       "635 TENNESSEE CASES\n17 DAMAGE REQUESTS"
        so the LLM can associate each number with its label unambiguously.
        """
        text = re.sub(r'(?<!\n)(\b[\d,\.]+[KkMm%]?\b)\s+([A-Z][A-Z\s&/\-]+)', r'\n\1 \2', text)
        text = re.sub(r'\n{3,}', '\n\n', text)
        return text.strip()

    def process(self, results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Run the full processing pipeline: build → deduplicate → filter → reindex.

        Args:
            results: Raw result dicts from CAS search_vector_store().

        Returns:
            Processed, reindexed list of chunk dicts ready for prompt assembly.
        """
        raw = self._build(results)
        deduped = self._deduplicate(raw)
        filtered = self._apply_dominant_filter(deduped)
        return self._reindex(filtered)

    # ------------------------------------------------------------------
    # Pipeline steps
    # ------------------------------------------------------------------

    def _build(self, results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Convert raw CAS result dicts into normalised chunk records.

        Args:
            results: Raw CAS search result dicts.

        Returns:
            List of normalised chunk dicts with index, content, score, source,
            file_id, and filename fields.
        """
        chunks = []
        for index, result in enumerate(results, start=1):
            content = self._normalize(result.get("content", ""))
            if not content:
                continue
            if self.max_chunk_chars > 0 and len(content) > self.max_chunk_chars:
                content = content[:self.max_chunk_chars] + "..."
            metadata = result.get("metadata", {}) if isinstance(result.get("metadata"), dict) else {}
            score_obj = result.get("score", {}) if isinstance(result.get("score"), dict) else {}
            chunks.append({
                "index": index,
                "content": content,
                "score": score_obj.get("combined_probability_score"),
                "source": (
                    metadata.get("source") or metadata.get("file_name") or
                    metadata.get("title") or result.get("filename") or f"chunk-{index}"
                ),
                "file_id": result.get("file_id"),
                "filename": result.get("filename"),
            })
        return chunks

    def _deduplicate(self, chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Drop exact-duplicate chunks (same source + same content).

        CAS occasionally returns the same chunk twice under different IDs.
        Identical text in *different* files is not a duplicate — the source
        key differs so both copies are preserved.
        """
        seen: Dict[tuple, Dict] = {}
        for chunk in chunks:
            seen.setdefault((chunk["source"], chunk["content"]), chunk)
        return list(seen.values())

    def _apply_dominant_filter(self, chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Drop chunks from sources whose best score falls too far below the top source.

        Strategy:
          1. Find the source with the highest best-score (the dominant source).
          2. Drop every other source whose best score is more than
             dominant_gap_threshold below the dominant source's best score.
          3. If no sources are dropped the filter is a no-op, so genuine
             multi-document queries are unaffected.

        This is purely score-driven. The chunk-count tie-break condition from the
        original implementation has been removed because it prevented the filter
        from firing when two documents returned the same number of chunks at
        similar (but not equal) scores — the most common cross-document
        contamination pattern.

        Set RAG_DOMINANT_GAP=0.0 in .env to disable this filter entirely.
        """
        if len(chunks) <= 1:
            return chunks

        if self.dominant_gap_threshold <= 0.0:
            return chunks

        source_best_score: Dict[str, float] = {}
        for c in chunks:
            src = c["source"]
            source_best_score[src] = max(source_best_score.get(src, 0.0), c["score"] or 0.0)

        if len(source_best_score) <= 1:
            return chunks

        top_score = max(source_best_score.values())
        allowed = {s for s, score in source_best_score.items() if top_score - score < self.dominant_gap_threshold}

        # Only apply the filter if it would actually drop something.
        # If every source passes (scores are very close) leave all chunks
        # in — this is a genuine multi-document query.
        if len(allowed) == len(source_best_score):
            return chunks

        return [c for c in chunks if c["source"] in allowed]

    def _reindex(self, chunks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Renumber chunk index fields 1..N after filtering.

        Args:
            chunks: Filtered chunk list whose indices may have gaps.

        Returns:
            Same chunks with ``index`` fields replaced by a contiguous 1-based sequence.
        """
        return [{**c, "index": i} for i, c in enumerate(chunks, start=1)]
