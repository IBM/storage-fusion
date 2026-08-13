"""Unit tests for utils.query.split_query."""

import pytest

from utils.query import split_query


class TestSplitQuery:

    @pytest.mark.unit
    def test_single_question_returned_as_is(self) -> None:
        result = split_query("What is the weather today?")
        assert result == ["What is the weather today?"]

    @pytest.mark.unit
    def test_two_questions_with_question_marks_not_split(self) -> None:
        result = split_query("What is the weather? How cold is it?")
        assert result == ["What is the weather? How cold is it?"]

    @pytest.mark.unit
    def test_no_question_mark_returned_unchanged(self) -> None:
        result = split_query("Tell me about the crisis cleanup process.")
        assert result == ["Tell me about the crisis cleanup process."]

    @pytest.mark.unit
    def test_newline_separated_questions_split(self) -> None:
        result = split_query("What caused the flood?\nWhere did it occur?")
        assert len(result) == 2
        assert result == ["What caused the flood?", "Where did it occur?"]

    @pytest.mark.unit
    def test_preamble_question_not_dropped(self) -> None:
        result = split_query(
            "What is Cyber Vault?\n"
            "In IBM Storage Virtualize, how can you delegate and limit the usage to specific objects?"
        )
        assert len(result) == 2
        assert any("In IBM Storage Virtualize" in q for q in result)

    @pytest.mark.unit
    def test_numbered_list_stripped(self) -> None:
        result = split_query("1. What is Cyber Vault?\n2. How does it work?")
        assert len(result) == 2
        assert not result[0].startswith("1.")
        assert not result[1].startswith("2.")

    @pytest.mark.unit
    def test_four_questions_all_returned(self) -> None:
        text = (
            "What is Cyber Vault designed for?\n"
            "What is the maximum number of PCIe ports in a FlashSystem 9500 with two enclosures?\n"
            "What is my cat's name?\n"
            "In IBM Storage Virtualize, how can you delegate and limit the usage to specific objects?"
        )
        result = split_query(text)
        assert len(result) == 4


