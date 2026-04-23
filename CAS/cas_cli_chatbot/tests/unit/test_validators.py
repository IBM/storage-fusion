"""
Unit tests for InputValidator
"""
import pytest

from chatbot.utils.validators import InputValidator, ValidationError


class TestValidateQuery:
    """Test query validation"""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_valid_query_passes(self):
        """TC-VAL-001: Verify valid query passes validation"""
        result = InputValidator.validate_query("What is the answer?")
        
        assert result == "What is the answer?"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_query_strips_whitespace(self):
        """TC-VAL-002: Verify query strips leading/trailing whitespace"""
        result = InputValidator.validate_query("  test query  ")
        
        assert result == "test query"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_empty_query_raises_error(self):
        """TC-VAL-003: Verify empty query raises ValidationError"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_query("")
        
        assert "cannot be empty" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_none_query_raises_error(self):
        """TC-VAL-004: Verify None query raises ValidationError"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_query(None)
        
        assert "cannot be None" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_non_string_query_raises_error(self):
        """TC-VAL-005: Verify non-string query raises ValidationError"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_query(123)
        
        assert "must be a string" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_query_exceeding_max_length_raises_error(self):
        """TC-VAL-006: Verify query exceeding max length raises ValidationError"""
        long_query = "a" * (InputValidator.MAX_QUERY_LENGTH + 1)
        
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_query(long_query)
        
        assert "exceeds maximum length" in str(exc_info.value)


class TestValidateVectorStoreName:
    """Test vector store name validation"""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_valid_vector_store_name_passes(self):
        """TC-VAL-007: Verify valid vector store name passes"""
        result = InputValidator.validate_vector_store_name("my-vector-store_123")
        
        assert result == "my-vector-store_123"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_vector_store_name_with_invalid_chars_raises_error(self):
        """TC-VAL-008: Verify vector store name with invalid chars raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_vector_store_name("invalid@name")
        
        assert "invalid characters" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_empty_vector_store_name_raises_error(self):
        """TC-VAL-009: Verify empty vector store name raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_vector_store_name("")
        
        assert "cannot be empty" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_vector_store_name_exceeding_max_length_raises_error(self):
        """TC-VAL-010: Verify vector store name exceeding max length raises error"""
        long_name = "a" * (InputValidator.MAX_VECTOR_STORE_NAME_LENGTH + 1)
        
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_vector_store_name(long_name)
        
        assert "exceeds maximum length" in str(exc_info.value)


class TestValidateFileId:
    """Test file ID validation"""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_valid_file_id_passes(self):
        """TC-VAL-011: Verify valid file ID passes"""
        result = InputValidator.validate_file_id("file-123_abc")
        
        assert result == "file-123_abc"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_file_id_with_invalid_chars_raises_error(self):
        """TC-VAL-012: Verify file ID with invalid chars raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_file_id("file@123")
        
        assert "invalid characters" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_empty_file_id_raises_error(self):
        """TC-VAL-013: Verify empty file ID raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_file_id("")
        
        assert "cannot be empty" in str(exc_info.value)


class TestValidateUsername:
    """Test username validation"""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_valid_username_passes(self):
        """TC-VAL-014: Verify valid username passes"""
        result = InputValidator.validate_username("user.name@example-123")
        
        assert result == "user.name@example-123"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_username_with_invalid_chars_raises_error(self):
        """TC-VAL-015: Verify username with invalid chars raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_username("user#name")
        
        assert "invalid characters" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_empty_username_raises_error(self):
        """TC-VAL-016: Verify empty username raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_username("")
        
        assert "cannot be empty" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_username_exceeding_max_length_raises_error(self):
        """TC-VAL-017: Verify username exceeding max length raises error"""
        long_username = "a" * (InputValidator.MAX_USERNAME_LENGTH + 1)
        
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_username(long_username)
        
        assert "exceeds maximum length" in str(exc_info.value)


class TestValidateLimit:
    """Test limit validation"""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_valid_limit_passes(self):
        """TC-VAL-018: Verify valid limit passes"""
        result = InputValidator.validate_limit(10)
        
        assert result == 10

    @pytest.mark.unit
    @pytest.mark.validators
    def test_none_limit_returns_default(self):
        """TC-VAL-019: Verify None limit returns default"""
        result = InputValidator.validate_limit(None)
        
        assert result == InputValidator.MAX_LIMIT

    @pytest.mark.unit
    @pytest.mark.validators
    def test_limit_below_min_raises_error(self):
        """TC-VAL-020: Verify limit below minimum raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_limit(0)
        
        assert "must be at least" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_limit_above_max_raises_error(self):
        """TC-VAL-021: Verify limit above maximum raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_limit(InputValidator.MAX_LIMIT + 1)
        
        assert "cannot exceed" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_non_integer_limit_raises_error(self):
        """TC-VAL-022: Verify non-integer limit raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_limit("10")
        
        assert "must be an integer" in str(exc_info.value)


class TestValidateFilters:
    """Test filter validation"""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_valid_filters_pass(self):
        """TC-VAL-023: Verify valid filters pass"""
        filters = {'key': 'filename', 'type': 'eq', 'value': 'test.pdf'}
        
        result = InputValidator.validate_filters(filters)
        
        assert result == filters

    @pytest.mark.unit
    @pytest.mark.validators
    def test_filters_missing_required_key_raises_error(self):
        """TC-VAL-024: Verify filters missing required key raises error"""
        filters = {'type': 'eq', 'value': 'test.pdf'}
        
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_filters(filters)
        
        assert "missing required key" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_filters_with_invalid_operator_raises_error(self):
        """TC-VAL-025: Verify filters with invalid type raises error"""
        filters = {'key': 'filename', 'type': 'invalid', 'value': 'test.pdf'}
        
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_filters(filters)
        
        assert "invalid type" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_none_filters_raises_error(self):
        """TC-VAL-026: Verify None filters raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_filters(None)
        
        assert "cannot be None" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_non_dict_filters_raises_error(self):
        """TC-VAL-027: Verify non-dict filters raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_filters("not a dict")
        
        assert "must be a dictionary" in str(exc_info.value)


class TestValidateNamespace:
    """Test namespace validation"""

    @pytest.mark.unit
    @pytest.mark.validators
    def test_valid_namespace_passes(self):
        """TC-VAL-028: Verify valid namespace passes"""
        result = InputValidator.validate_namespace("ibm-cas")
        
        assert result == "ibm-cas"

    @pytest.mark.unit
    @pytest.mark.validators
    def test_namespace_with_uppercase_raises_error(self):
        """TC-VAL-029: Verify namespace with uppercase raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_namespace("IBM-CAS")
        
        assert "Kubernetes naming rules" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_namespace_with_invalid_chars_raises_error(self):
        """TC-VAL-030: Verify namespace with invalid chars raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_namespace("ibm_cas")
        
        assert "Kubernetes naming rules" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_empty_namespace_raises_error(self):
        """TC-VAL-031: Verify empty namespace raises error"""
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_namespace("")
        
        assert "cannot be empty" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.validators
    def test_namespace_exceeding_max_length_raises_error(self):
        """TC-VAL-032: Verify namespace exceeding 63 chars raises error"""
        long_namespace = "a" * 64
        
        with pytest.raises(ValidationError) as exc_info:
            InputValidator.validate_namespace(long_namespace)
        
        assert "cannot exceed 63 characters" in str(exc_info.value)

