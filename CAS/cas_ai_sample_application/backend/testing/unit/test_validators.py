"""
Unit tests for InputValidator

Covers:
  - validate_query  — user question sanitisation and length checks
  - validate_token  — CAS API bearer token format checks
  - validate_endpoint_url — CAS / LLM endpoint URL format checks

Naming convention:  test_<method>_<condition>_<expected_outcome>
TC-ID convention:   TC-VAL-<NNN> — matches the project's test catalogue format
                    used in cas_cli_chatbot and the IBM Fusion CAS Assistant codebase.

InputValidator is pure Python with no I/O — no mocks or patches needed here.
"""

from typing import Any, cast

import pytest

from utils.validators import InputValidator, ValidationError


# ---------------------------------------------------------------------------
# validate_query
# ---------------------------------------------------------------------------

class TestValidateQuery:
    """Test user question sanitisation, type guards, and length limits."""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_query_returns_clean_string_for_valid_input(self) -> None:
        """TC-VAL-001: Valid plain-text query must be returned unchanged (after strip)."""
        result = InputValidator.validate_query("What is IBM Fusion?")

        assert result == "What is IBM Fusion?"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_query_strips_leading_and_trailing_whitespace(self) -> None:
        """TC-VAL-002: Leading/trailing whitespace must be removed from the returned value."""
        result = InputValidator.validate_query("  tell me about CAS  ")

        assert result == "tell me about CAS"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_query_strips_html_script_tags(self) -> None:
        """TC-VAL-003: <script> injection in the query must be stripped before returning."""
        result = InputValidator.validate_query("hello <script>alert(1)</script> world")

        assert "<script>" not in result
        assert "alert" not in result
        assert "hello" in result

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_query_raises_when_none(self) -> None:
        """TC-VAL-004: None input must raise ValidationError — not TypeError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_query(cast(Any, None))

        assert "cannot be None" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_query_raises_when_not_a_string(self) -> None:
        """TC-VAL-005: Non-string input must raise ValidationError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_query(cast(Any, 42))

        assert "must be a string" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_query_raises_when_empty_after_strip(self) -> None:
        """TC-VAL-006: Whitespace-only string must raise ValidationError after sanitisation."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_query("   ")

        assert "cannot be empty" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_query_raises_when_exceeds_max_length(self) -> None:
        """TC-VAL-007: Query longer than MAX_QUERY_LENGTH must raise ValidationError."""
        long_query = "a" * (InputValidator.MAX_QUERY_LENGTH + 1)

        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_query(long_query)

        assert "exceeds maximum length" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_query_accepts_query_at_exact_max_length(self) -> None:
        """TC-VAL-008: Query at exactly MAX_QUERY_LENGTH must pass without error."""
        exact_query = "a" * InputValidator.MAX_QUERY_LENGTH

        result = InputValidator.validate_query(exact_query)

        assert len(result) == InputValidator.MAX_QUERY_LENGTH


# ---------------------------------------------------------------------------
# validate_token
# ---------------------------------------------------------------------------

class TestValidateToken:
    """Test CAS API bearer token format, length, and character guards."""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_token_returns_stripped_token_for_valid_input(self) -> None:
        """TC-VAL-009: A well-formed token must be returned stripped."""
        token = "eyJhbGciOiJSUzI1NiJ9.validtoken"

        result = InputValidator.validate_token(token)

        assert result == token.strip()

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_token_strips_surrounding_whitespace(self) -> None:
        """TC-VAL-010: Surrounding whitespace must be removed from the returned token."""
        result = InputValidator.validate_token("  validtoken12345  ")

        assert result == "validtoken12345"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_token_raises_when_none(self) -> None:
        """TC-VAL-011: None token must raise ValidationError — not AttributeError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_token(cast(Any, None))

        assert "cannot be None" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_token_raises_when_not_a_string(self) -> None:
        """TC-VAL-012: Non-string token must raise ValidationError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_token(cast(Any, 12345))

        assert "must be a string" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_token_raises_when_empty(self) -> None:
        """TC-VAL-013: Empty string must raise ValidationError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_token("")

        assert "cannot be empty" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_token_raises_when_too_short(self) -> None:
        """TC-VAL-014: Token shorter than MIN_TOKEN_LENGTH must raise ValidationError."""
        short_token = "a" * (InputValidator.MIN_TOKEN_LENGTH - 1)

        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_token(short_token)

        assert "must be at least" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_token_raises_when_too_long(self) -> None:
        """TC-VAL-015: Token longer than MAX_TOKEN_LENGTH must raise ValidationError."""
        long_token = "a" * (InputValidator.MAX_TOKEN_LENGTH + 1)

        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_token(long_token)

        assert "exceeds maximum length" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_token_raises_for_each_invalid_character(self) -> None:
        """TC-VAL-016: Each shell-injection character must individually trigger ValidationError."""
        # These chars are explicitly blocked to prevent prompt/shell injection via the token field.
        for bad_char in ("<", ">", '"', "'", ";", "&", "|"):
            token = f"validtoken{bad_char}suffix"

            with pytest.raises(ValidationError) as exc_info:
                InputValidator.validate_token(token)

            assert "invalid characters" in str(exc_info.value), (
                f"Expected 'invalid characters' error for char {bad_char!r}"
            )

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_token_accepts_token_at_exact_min_length(self) -> None:
        """TC-VAL-017: Token at exactly MIN_TOKEN_LENGTH must pass without error."""
        exact_token = "a" * InputValidator.MIN_TOKEN_LENGTH

        result = InputValidator.validate_token(exact_token)

        assert len(result) == InputValidator.MIN_TOKEN_LENGTH


# ---------------------------------------------------------------------------
# validate_endpoint_url
# ---------------------------------------------------------------------------

class TestValidateEndpointUrl:
    """Test CAS / LLM endpoint URL scheme, format, and length guards."""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_endpoint_url_returns_url_for_valid_https(self) -> None:
        """TC-VAL-018: Valid https:// URL must be returned stripped."""
        result = InputValidator.validate_endpoint_url("https://cas.example.com/cas/api/v1")

        assert result == "https://cas.example.com/cas/api/v1"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_endpoint_url_returns_url_for_valid_http(self) -> None:
        """TC-VAL-019: Valid http:// URL (e.g. local Ollama) must be accepted."""
        result = InputValidator.validate_endpoint_url("http://localhost:11434")

        assert result == "http://localhost:11434"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_endpoint_url_accepts_ip_address_url(self) -> None:
        """TC-VAL-020: IP-address-based URLs must be accepted — common in cluster deployments."""
        result = InputValidator.validate_endpoint_url("https://192.168.1.100:8443")

        assert result == "https://192.168.1.100:8443"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_endpoint_url_raises_when_none(self) -> None:
        """TC-VAL-021: None URL must raise ValidationError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_endpoint_url(cast(Any, None))

        assert "cannot be None" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_endpoint_url_raises_when_not_a_string(self) -> None:
        """TC-VAL-022: Non-string URL must raise ValidationError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_endpoint_url(cast(Any, 8080))

        assert "must be a string" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_endpoint_url_raises_when_empty(self) -> None:
        """TC-VAL-023: Empty string must raise ValidationError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_endpoint_url("")

        assert "cannot be empty" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_endpoint_url_raises_when_missing_scheme(self) -> None:
        """TC-VAL-024: URL without http:// or https:// scheme must raise ValidationError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_endpoint_url("example.com/cas/api/v1")

        assert "not a valid" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_endpoint_url_raises_when_exceeds_max_length(self) -> None:
        """TC-VAL-025: URL longer than MAX_URL_LENGTH must raise ValidationError."""
        long_url = "https://example.com/" + "a" * InputValidator.MAX_URL_LENGTH

        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_endpoint_url(long_url)

        assert "exceeds maximum length" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_endpoint_url_strips_surrounding_whitespace(self) -> None:
        """TC-VAL-026: Surrounding whitespace must be removed before validation and return."""
        result = InputValidator.validate_endpoint_url("  https://example.com  ")

        assert result == "https://example.com"


# ---------------------------------------------------------------------------
# validate_session_id
# ---------------------------------------------------------------------------

class TestValidateSessionId:
    """Test UUID session-id format validation."""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_session_id_accepts_valid_uuid(self) -> None:
        """TC-VAL-027: A well-formed lower-case UUID string must be returned stripped."""
        valid_uuid = "550e8400-e29b-41d4-a716-446655440000"
        result = InputValidator.validate_session_id(valid_uuid)
        assert result == valid_uuid

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_session_id_accepts_uuid_with_surrounding_whitespace(self) -> None:
        """TC-VAL-028: Leading/trailing whitespace must be stripped before validation."""
        valid_uuid = "  550e8400-e29b-41d4-a716-446655440000  "
        result = InputValidator.validate_session_id(valid_uuid)
        assert result == valid_uuid.strip()

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_session_id_raises_when_not_a_string(self) -> None:
        """TC-VAL-029: Non-string input must raise ValidationError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_session_id(cast(Any, 12345))
        assert "must be a string" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_validate_session_id_raises_when_malformed(self) -> None:
        """TC-VAL-030: A string that is not a valid UUID format must raise ValidationError."""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_session_id("not-a-uuid")
        assert "not a valid session id" in str(exc_info.value)
