"""
Unit tests for ChunkProcessor

Covers:
  - normalize()               — raw CAS content payload → plain text
  - _structure_infographic_text() — OCR number+label spacing
  - _build()                  — raw CAS result dicts → normalised chunk records
  - _deduplicate()            — same-source/same-content duplicates dropped
  - _apply_dominant_filter()  — weak sources dropped when gap exceeds threshold
  - _reindex()                — 1-based index sequence restored after filtering
  - process()                 — full pipeline end-to-end

Naming convention:  test_<method>_<condition>_<expected_outcome>
TC-ID convention:   TC-CHUNK-<NNN> — matches the project's test catalogue format
                    used in cas_cli_chatbot and the IBM Fusion CAS Assistant codebase.

ChunkProcessor is pure Python with no I/O — no mocks or patches are needed.
Constructor args (max_chunk_chars, dominant_gap_threshold) are passed directly
so tests are not affected by whatever is set in the environment.
"""

import pytest

from chunk_processor import ChunkProcessor


# ---------------------------------------------------------------------------
# Helpers — shared raw result builders used across multiple test classes
# ---------------------------------------------------------------------------

def _make_result(content: str, source: str = "doc.pdf", score: float = 0.9) -> dict:
    """Return a minimal raw CAS result dict for use in _build / process tests."""
    return {
        "content": content,
        "filename": source,
        "score": {"combined_probability_score": score},
    }


# ---------------------------------------------------------------------------
# Realistic query scenarios
#
# Shapes taken directly from a live CAS search response against the
# crisis-domain vector store (query: "weather", max_num_results: 3).
# The real API response uses:
#   - content as a list of typed dicts  e.g. [{"type": "image", "text": "..."}]
#   - score as a dict with combined_probability_score, lexical_score, etc.
#   - filename at the top level (no metadata.source in these results)
#
# Using real field names/shapes here means the tests break if ChunkProcessor
# ever stops handling the actual CAS response format correctly.
#
# Each scenario is a tuple of:
#   (description, raw_results, expected_chunk_count, expected_content_fragments)
# ---------------------------------------------------------------------------

# Scenario 1 — query: "weather"
# Real response: 3 results from 3 different crisis-domain documents.
# Scores: 0.652, 0.581, 0.584 — all within ~0.07 of each other.
# Expected: gap < default threshold (0.09) so all 3 chunks survive filtering.
SCENARIO_WEATHER = (
    "weather",
    [
        {
            "file_id": "10487824",
            "filename": "171_1_1_SC_Helene_Milton_Crisis_Cleanup_Magazine.pdf",
            "score": {
                "score": 0.35325232539440554,
                "logitscore": None,
                "combined_probability_score": 0.6519774178010187,
                "lexical_score": 0.9507025102076319,
            },
            "content": [
                {
                    "type": "image",
                    "text": (
                        "The content of this image captures the appearance of a modern digital "
                        "interface on a weather forecast application. The forecast for Saturday, "
                        "showing a temperature of 27 degrees, indicates sunny weather with no "
                        "precipitation."
                    ),
                }
            ],
        },
        {
            "file_id": "10487821",
            "filename": "177_1_8_Central_Tornadoes_ds.pdf",
            "score": {
                "score": 0.3247907542464803,
                "logitscore": None,
                "combined_probability_score": 0.5805560814424162,
                "lexical_score": 0.8363214086383522,
            },
            "content": [{"type": "text", "text": "PHOTO CREDIT NATIONAL WEATHER SERVICE\n47"}],
        },
        {
            "file_id": "10487808",
            "filename": "172_1_2_KY_Snow_and_Ice_web.pdf",
            "score": {
                "score": 0.2697555003589135,
                "logitscore": None,
                "combined_probability_score": 0.5838453097849605,
                "lexical_score": 0.8979351192110075,
            },
            "content": [
                {
                    "type": "image",
                    "text": (
                        "A forecast of potential snowfall as analyzed by the National Weather "
                        "Service for Jackson, Kentucky, for the period from January 5th to "
                        "January 6th, 2023."
                    ),
                }
            ],
        },
    ],
    3,   # all 3 chunks kept — scores are close, no dominant gap
    ["weather forecast", "NATIONAL WEATHER SERVICE", "National Weather Service"],
)

# Scenario 2 — query: "weather" with one low-score outlier injected.
# The three real results above have similar scores.  Here we inject a fourth
# result from an unrelated source with a score far below the dominant (0.20),
# simulating cross-document contamination.
# Expected: dominant filter drops the outlier; 3 chunks from 3 real sources remain.
SCENARIO_WEATHER_WITH_OUTLIER = (
    "weather with unrelated outlier",
    [
        {
            "file_id": "10487824",
            "filename": "171_1_1_SC_Helene_Milton_Crisis_Cleanup_Magazine.pdf",
            "score": {"combined_probability_score": 0.652, "lexical_score": 0.95},
            "content": [{"type": "text", "text": "Sunny weather forecast for Saturday."}],
        },
        {
            "file_id": "10487821",
            "filename": "177_1_8_Central_Tornadoes_ds.pdf",
            "score": {"combined_probability_score": 0.581, "lexical_score": 0.84},
            "content": [{"type": "text", "text": "PHOTO CREDIT NATIONAL WEATHER SERVICE"}],
        },
        {
            "file_id": "10487808",
            "filename": "172_1_2_KY_Snow_and_Ice_web.pdf",
            "score": {"combined_probability_score": 0.584, "lexical_score": 0.90},
            "content": [{"type": "text", "text": "National Weather Service snowfall forecast."}],
        },
        {
            # Injected outlier — low score, unrelated document.
            "file_id": "99999999",
            "filename": "unrelated-equipment-manual.pdf",
            "score": {"combined_probability_score": 0.20, "lexical_score": 0.10},
            "content": [{"type": "text", "text": "Hydraulic pump maintenance schedule page 4."}],
        },
    ],
    3,   # outlier dropped; 3 real weather chunks remain
    ["Sunny weather", "NATIONAL WEATHER SERVICE", "snowfall forecast"],
)

# Scenario 3 — query: "weather" with CAS duplicate.
# CAS sometimes returns the same chunk twice under different file_id values.
# Expected: dedup collapses the duplicate; only 2 unique chunks remain.
SCENARIO_WEATHER_WITH_DUPLICATE = (
    "weather with CAS duplicate",
    [
        {
            "file_id": "10487824",
            "filename": "171_1_1_SC_Helene_Milton_Crisis_Cleanup_Magazine.pdf",
            "score": {"combined_probability_score": 0.652, "lexical_score": 0.95},
            "content": [{"type": "text", "text": "Sunny weather forecast for Saturday at 27 degrees."}],
        },
        {
            # Duplicate — same filename and same text content, different file_id (CAS quirk).
            "file_id": "10487824B",
            "filename": "171_1_1_SC_Helene_Milton_Crisis_Cleanup_Magazine.pdf",
            "score": {"combined_probability_score": 0.652, "lexical_score": 0.95},
            "content": [{"type": "text", "text": "Sunny weather forecast for Saturday at 27 degrees."}],
        },
        {
            "file_id": "10487821",
            "filename": "177_1_8_Central_Tornadoes_ds.pdf",
            "score": {"combined_probability_score": 0.581, "lexical_score": 0.84},
            "content": [{"type": "text", "text": "PHOTO CREDIT NATIONAL WEATHER SERVICE"}],
        },
    ],
    2,   # duplicate collapsed; 2 unique chunks remain
    ["27 degrees", "NATIONAL WEATHER SERVICE"],
)

REALISTIC_SCENARIOS = [
    SCENARIO_WEATHER,
    SCENARIO_WEATHER_WITH_OUTLIER,
    SCENARIO_WEATHER_WITH_DUPLICATE,
]


# ---------------------------------------------------------------------------
# normalize
# ---------------------------------------------------------------------------

class TestNormalize:
    """Test raw CAS content payload → plain text conversion."""

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_returns_plain_string_unchanged(self) -> None:
        """TC-CHUNK-001: A plain string must be returned as-is (stripped)."""
        result = ChunkProcessor.normalize("  Hello, CAS.  ")

        assert result == "Hello, CAS."

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_text_type_item_passed_through(self) -> None:
        """TC-CHUNK-002: List item with type=text must be included in output as-is."""
        content = [{"type": "text", "text": "Some document text."}]

        result = ChunkProcessor.normalize(content)

        assert result == "Some document text."

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_image_type_item_gets_warning_prefix(self) -> None:
        """TC-CHUNK-003: List item with type=image must be prefixed with the AI-estimate warning."""
        content = [{"type": "image", "text": "Chart showing 42% growth."}]

        result = ChunkProcessor.normalize(content)

        assert result.startswith("[AI image estimate")
        assert "Chart showing 42% growth." in result

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_infographic_type_item_structures_text(self) -> None:
        """TC-CHUNK-004: List item with type=infographic must have newlines inserted between number+label pairs."""
        content = [{"type": "infographic", "text": "635 TENNESSEE CASES 17 DAMAGE REQUESTS"}]

        result = ChunkProcessor.normalize(content)

        # The two number+label pairs must now be on separate lines.
        assert "635 TENNESSEE CASES" in result
        assert "17 DAMAGE REQUESTS" in result
        assert "\n" in result

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_multiple_items_joined_by_double_newline(self) -> None:
        """TC-CHUNK-005: Multiple list items must be joined with double newline separators."""
        content = [
            {"type": "text", "text": "First paragraph."},
            {"type": "text", "text": "Second paragraph."},
        ]

        result = ChunkProcessor.normalize(content)

        assert result == "First paragraph.\n\nSecond paragraph."

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_empty_text_items_are_skipped(self) -> None:
        """TC-CHUNK-006: List items with empty text must be silently skipped."""
        content = [
            {"type": "text", "text": ""},
            {"type": "text", "text": "Real content."},
        ]

        result = ChunkProcessor.normalize(content)

        assert result == "Real content."

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_dict_input_extracts_text_key(self) -> None:
        """TC-CHUNK-007: A plain dict must return the value of its 'text' key."""
        result = ChunkProcessor.normalize({"text": "Dict content."})

        assert result == "Dict content."

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_serialised_list_string_is_parsed(self) -> None:
        """TC-CHUNK-008: A pre-serialised list-of-dicts string (CAS quirk) must be parsed and normalised."""
        # CAS sometimes sends the content field as a stringified Python list.
        serialised = "[{'type': 'text', 'text': 'Parsed from string.'}]"

        result = ChunkProcessor.normalize(serialised)

        assert result == "Parsed from string."

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_empty_list_returns_empty_string(self) -> None:
        """TC-CHUNK-009: An empty list must return an empty string — not raise."""
        result = ChunkProcessor.normalize([])

        assert result == ""

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_normalize_non_dict_list_items_converted_to_str(self) -> None:
        """TC-CHUNK-010: Non-dict items in a list (e.g. raw strings) must be str()-converted and included."""
        result = ChunkProcessor.normalize(["hello", "world"])

        assert "hello" in result
        assert "world" in result


# ---------------------------------------------------------------------------
# _structure_infographic_text
# ---------------------------------------------------------------------------

class TestStructureInfographicText:
    """Test OCR number+label pair separation for infographic content."""

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_structure_inserts_newline_before_second_number_label_pair(self) -> None:
        """TC-CHUNK-011: Dense number+label pairs must be split onto separate lines."""
        text = "635 TENNESSEE CASES 17 DAMAGE REQUESTS"

        result = ChunkProcessor._structure_infographic_text(text)

        lines = result.split("\n")
        assert any("635" in line for line in lines)
        assert any("17" in line for line in lines)

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_structure_collapses_excess_blank_lines(self) -> None:
        """TC-CHUNK-012: Three or more consecutive newlines must be collapsed to at most two."""
        text = "100 CASES\n\n\n\n200 REQUESTS"

        result = ChunkProcessor._structure_infographic_text(text)

        assert "\n\n\n" not in result

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_structure_plain_text_unchanged(self) -> None:
        """TC-CHUNK-013: Text with no number+label patterns must be returned stripped and unchanged."""
        text = "  No numbers here.  "

        result = ChunkProcessor._structure_infographic_text(text)

        assert result == "No numbers here."


# ---------------------------------------------------------------------------
# _build
# ---------------------------------------------------------------------------

class TestBuild:
    """Test raw CAS result dicts → normalised chunk record construction."""

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_build_returns_chunk_with_expected_keys(self) -> None:
        """TC-CHUNK-014: Every built chunk must contain index, content, score, source, file_id, filename."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        results = [_make_result("Some content.")]

        chunks = cp._build(results)

        assert len(chunks) == 1
        for key in ("index", "content", "score", "source", "file_id", "filename"):
            assert key in chunks[0], f"Missing key: {key}"

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_build_skips_results_with_empty_content(self) -> None:
        """TC-CHUNK-015: Results whose normalised content is empty must be silently dropped."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        results = [{"content": "", "filename": "doc.pdf", "score": {}}]

        chunks = cp._build(results)

        assert chunks == []

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_build_truncates_content_when_max_chunk_chars_set(self) -> None:
        """TC-CHUNK-016: Content longer than max_chunk_chars must be hard-truncated with '...' appended."""
        cp = ChunkProcessor(max_chunk_chars=10, dominant_gap_threshold=0.0)
        results = [_make_result("A" * 50)]

        chunks = cp._build(results)

        assert len(chunks[0]["content"]) == 13  # 10 chars + "..."
        assert chunks[0]["content"].endswith("...")

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_build_does_not_truncate_when_max_chunk_chars_is_zero(self) -> None:
        """TC-CHUNK-017: max_chunk_chars=0 must disable truncation entirely."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        long_content = "B" * 5000
        results = [_make_result(long_content)]

        chunks = cp._build(results)

        assert len(chunks[0]["content"]) == 5000

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_build_uses_filename_as_source_fallback(self) -> None:
        """TC-CHUNK-018: When no metadata source fields exist, filename must be used as source."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        results = [{"content": "text", "filename": "report.pdf", "score": {}}]

        chunks = cp._build(results)

        assert chunks[0]["source"] == "report.pdf"

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_build_uses_chunk_index_as_source_last_resort(self) -> None:
        """TC-CHUNK-019: When no source fields exist at all, source must fall back to 'chunk-<N>'."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        results = [{"content": "text", "score": {}}]

        chunks = cp._build(results)

        assert chunks[0]["source"] == "chunk-1"

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_build_prefers_metadata_source_over_filename(self) -> None:
        """TC-CHUNK-020: metadata['source'] must take priority over the top-level filename field."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        results = [{
            "content": "text",
            "filename": "fallback.pdf",
            "metadata": {"source": "preferred.pdf"},
            "score": {},
        }]

        chunks = cp._build(results)

        assert chunks[0]["source"] == "preferred.pdf"


# ---------------------------------------------------------------------------
# _deduplicate
# ---------------------------------------------------------------------------

class TestDeduplicate:
    """Test exact-duplicate chunk removal (same source + same content)."""

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_deduplicate_removes_exact_duplicate(self) -> None:
        """TC-CHUNK-021: Two chunks with identical source and content must be collapsed to one."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        chunks = [
            {"source": "doc.pdf", "content": "same text", "index": 1, "score": 0.9},
            {"source": "doc.pdf", "content": "same text", "index": 2, "score": 0.9},
        ]

        result = cp._deduplicate(chunks)

        assert len(result) == 1

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_deduplicate_keeps_same_content_from_different_sources(self) -> None:
        """TC-CHUNK-022: Identical content from different source files must both be kept."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        chunks = [
            {"source": "doc-a.pdf", "content": "shared text", "index": 1, "score": 0.9},
            {"source": "doc-b.pdf", "content": "shared text", "index": 2, "score": 0.8},
        ]

        result = cp._deduplicate(chunks)

        assert len(result) == 2

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_deduplicate_keeps_unique_chunks_untouched(self) -> None:
        """TC-CHUNK-023: Chunks with distinct content must all be preserved."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        chunks = [
            {"source": "doc.pdf", "content": "chunk one", "index": 1, "score": 0.9},
            {"source": "doc.pdf", "content": "chunk two", "index": 2, "score": 0.8},
        ]

        result = cp._deduplicate(chunks)

        assert len(result) == 2


# ---------------------------------------------------------------------------
# _apply_dominant_filter
# ---------------------------------------------------------------------------

class TestApplyDominantFilter:
    """Test score-gap based filtering to prevent cross-document contamination."""

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_dominant_filter_drops_weak_source_when_gap_exceeds_threshold(self) -> None:
        """TC-CHUNK-024: Source whose best score is more than threshold below the top must be dropped."""
        # threshold=0.09, top=0.9, weak=0.7 → gap=0.2 > 0.09 → weak source dropped
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.09)
        chunks = [
            {"source": "strong.pdf", "content": "a", "index": 1, "score": 0.9},
            {"source": "weak.pdf",   "content": "b", "index": 2, "score": 0.7},
        ]

        result = cp._apply_dominant_filter(chunks)

        sources = [c["source"] for c in result]
        assert "strong.pdf" in sources
        assert "weak.pdf" not in sources

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_dominant_filter_keeps_close_sources_intact(self) -> None:
        """TC-CHUNK-025: Sources within the threshold gap must all be kept — genuine multi-doc query."""
        # threshold=0.09, top=0.9, close=0.85 → gap=0.05 < 0.09 → both kept
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.09)
        chunks = [
            {"source": "doc-a.pdf", "content": "a", "index": 1, "score": 0.90},
            {"source": "doc-b.pdf", "content": "b", "index": 2, "score": 0.85},
        ]

        result = cp._apply_dominant_filter(chunks)

        assert len(result) == 2

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_dominant_filter_disabled_when_threshold_is_zero(self) -> None:
        """TC-CHUNK-026: threshold=0.0 must disable the filter — all chunks returned regardless of gap."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        chunks = [
            {"source": "strong.pdf", "content": "a", "index": 1, "score": 0.9},
            {"source": "weak.pdf",   "content": "b", "index": 2, "score": 0.1},
        ]

        result = cp._apply_dominant_filter(chunks)

        assert len(result) == 2

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_dominant_filter_single_chunk_returned_unchanged(self) -> None:
        """TC-CHUNK-027: A single chunk must always be returned as-is — no filter applied."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.09)
        chunks = [{"source": "only.pdf", "content": "a", "index": 1, "score": 0.9}]

        result = cp._apply_dominant_filter(chunks)

        assert result == chunks

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_dominant_filter_single_source_multiple_chunks_not_filtered(self) -> None:
        """TC-CHUNK-028: Multiple chunks from the same source must all be kept — only one source exists."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.09)
        chunks = [
            {"source": "doc.pdf", "content": "chunk 1", "index": 1, "score": 0.9},
            {"source": "doc.pdf", "content": "chunk 2", "index": 2, "score": 0.8},
        ]

        result = cp._apply_dominant_filter(chunks)

        assert len(result) == 2


# ---------------------------------------------------------------------------
# _reindex
# ---------------------------------------------------------------------------

class TestReindex:
    """Test 1-based index sequence restoration after filtering."""

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_reindex_produces_contiguous_1_based_sequence(self) -> None:
        """TC-CHUNK-029: After filtering leaves gaps, reindex must produce 1, 2, 3, …"""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        # Simulate gaps left by the dominant filter (indices 1 and 3, no 2).
        chunks = [
            {"source": "doc.pdf", "content": "a", "index": 1, "score": 0.9},
            {"source": "doc.pdf", "content": "b", "index": 3, "score": 0.8},
        ]

        result = cp._reindex(chunks)

        assert [c["index"] for c in result] == [1, 2]

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_reindex_empty_list_returns_empty_list(self) -> None:
        """TC-CHUNK-030: Reindexing an empty list must return an empty list — not raise."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)

        result = cp._reindex([])

        assert result == []


# ---------------------------------------------------------------------------
# process  (full pipeline)
# ---------------------------------------------------------------------------

class TestProcess:
    """Test the full build → deduplicate → filter → reindex pipeline."""

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_process_empty_results_returns_empty_list(self) -> None:
        """TC-CHUNK-031: Empty input must return an empty list — not raise."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)

        result = cp.process([])

        assert result == []

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_process_single_result_returns_one_indexed_chunk(self) -> None:
        """TC-CHUNK-032: Single valid result must produce exactly one chunk with index=1."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)

        result = cp.process([_make_result("Hello world.")])

        assert len(result) == 1
        assert result[0]["index"] == 1
        assert result[0]["content"] == "Hello world."

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_process_deduplicates_and_reindexes(self) -> None:
        """TC-CHUNK-033: Duplicate chunks must be removed and remaining chunks reindexed from 1."""
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.0)
        results = [
            _make_result("same content", source="doc.pdf", score=0.9),
            _make_result("same content", source="doc.pdf", score=0.9),  # duplicate
            _make_result("other content", source="doc.pdf", score=0.8),
        ]

        result = cp.process(results)

        assert len(result) == 2
        assert [c["index"] for c in result] == [1, 2]

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_process_filters_weak_source_and_reindexes(self) -> None:
        """TC-CHUNK-034: Dominant filter must remove the weak source; remaining chunks reindexed from 1."""
        # threshold=0.09, strong=0.9, weak=0.5 → gap=0.4 > threshold → weak dropped
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.09)
        results = [
            _make_result("strong content", source="strong.pdf", score=0.9),
            _make_result("weak content",   source="weak.pdf",   score=0.5),
        ]

        result = cp.process(results)

        assert len(result) == 1
        assert result[0]["source"] == "strong.pdf"
        assert result[0]["index"] == 1

    # -----------------------------------------------------------------------
    # Realistic scenario tests — driven by real CAS response shapes
    # (crisis-domain vector store, query: "weather").
    # -----------------------------------------------------------------------

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_process_real_weather_query_keeps_all_close_scored_chunks(self) -> None:
        """TC-CHUNK-035: Real CAS response with close scores must keep all chunks — no dominant gap.

        Scores from the live response: 0.652, 0.581, 0.584.
        Max gap = 0.652 - 0.581 = 0.071 < default threshold 0.09 → all 3 survive.
        Content uses real CAS shape: list-of-typed-dicts with type=image and type=text.
        """
        description, raw_results, expected_count, fragments = SCENARIO_WEATHER
        # Use the default threshold (0.09) — same as production.
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.09)

        result = cp.process(raw_results)

        assert len(result) == expected_count, (
            f"Scenario '{description}': expected {expected_count} chunks, got {len(result)}"
        )
        all_content = " ".join(c["content"] for c in result)
        for fragment in fragments:
            assert fragment in all_content, (
                f"Scenario '{description}': expected fragment {fragment!r} not found in output"
            )
        # Indices must be contiguous starting at 1.
        assert [c["index"] for c in result] == list(range(1, expected_count + 1))

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_process_real_weather_query_drops_injected_outlier(self) -> None:
        """TC-CHUNK-036: Real CAS scores with one low-score outlier — outlier must be dropped.

        Three real weather results (0.652, 0.581, 0.584) plus an injected outlier at 0.20.
        Gap = 0.652 - 0.20 = 0.452 > 0.09 → outlier dropped; 3 weather chunks remain.
        """
        description, raw_results, expected_count, fragments = SCENARIO_WEATHER_WITH_OUTLIER
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.09)

        result = cp.process(raw_results)

        assert len(result) == expected_count, (
            f"Scenario '{description}': expected {expected_count} chunks, got {len(result)}"
        )
        filenames = [c["filename"] for c in result]
        assert "unrelated-equipment-manual.pdf" not in filenames, (
            "Outlier document must have been dropped by the dominant filter"
        )
        all_content = " ".join(c["content"] for c in result)
        for fragment in fragments:
            assert fragment in all_content, (
                f"Scenario '{description}': expected fragment {fragment!r} not found in output"
            )

    @pytest.mark.unit
    @pytest.mark.chunk
    def test_process_real_weather_query_deduplicates_cas_duplicate(self) -> None:
        """TC-CHUNK-037: Real CAS duplicate (same filename + content, different file_id) must be collapsed.

        CAS returned the same chunk from 171_1_1_SC_Helene_Milton... twice under different
        file_ids. After dedup, only 2 unique chunks must remain, reindexed 1 and 2.
        """
        description, raw_results, expected_count, fragments = SCENARIO_WEATHER_WITH_DUPLICATE
        cp = ChunkProcessor(max_chunk_chars=0, dominant_gap_threshold=0.09)

        result = cp.process(raw_results)

        assert len(result) == expected_count, (
            f"Scenario '{description}': expected {expected_count} chunks, got {len(result)}"
        )
        assert [c["index"] for c in result] == list(range(1, expected_count + 1))
        all_content = " ".join(c["content"] for c in result)
        for fragment in fragments:
            assert fragment in all_content, (
                f"Scenario '{description}': expected fragment {fragment!r} not found in output"
            )
