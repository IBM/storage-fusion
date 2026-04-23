"""
Unit tests for ResponseFormatter
"""
import pytest
from datetime import datetime

from chatbot.utils.response_formatter import ResponseFormatter


class TestSuccessResponse:
    """Test success response formatting"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_success_response_structure(self):
        """TC-FMT-001: Verify success response has correct structure"""
        response = ResponseFormatter.success(data={'key': 'value'})

        assert response['success'] is True
        assert response['data'] == {'key': 'value'}
        assert response['error'] is None
        assert 'timestamp' in response

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_success_response_with_message(self):
        """TC-FMT-002: Verify success response includes optional message"""
        response = ResponseFormatter.success(data={'key': 'value'},
                                             message='Operation successful')

        assert response['message'] == 'Operation successful'

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_success_response_without_data(self):
        """TC-FMT-003: Verify success response works without data"""
        response = ResponseFormatter.success()

        assert response['success'] is True
        assert response['data'] is None

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_success_response_timestamp_format(self):
        """TC-FMT-004: Verify timestamp is in ISO format"""
        response = ResponseFormatter.success()

        # Should be able to parse as ISO format
        datetime.fromisoformat(response['timestamp'])


class TestErrorResponse:
    """Test error response formatting"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_error_response_structure(self):
        """TC-FMT-005: Verify error response has correct structure"""
        response = ResponseFormatter.error('Something went wrong')

        assert response['success'] is False
        assert response['data'] is None
        assert response['error'] == 'Something went wrong'
        assert 'timestamp' in response

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_error_response_with_code(self):
        """TC-FMT-006: Verify error response includes error code"""
        response = ResponseFormatter.error('Error message',
                                           error_code='ERR_001')

        assert response['error_code'] == 'ERR_001'

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_error_response_with_details(self):
        """TC-FMT-007: Verify error response includes details"""
        details = {'field': 'username', 'reason': 'invalid'}
        response = ResponseFormatter.error('Error message', details=details)

        assert response['details'] == details


class TestValidationErrorResponse:
    """Test validation error response"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_validation_error_response(self):
        """TC-FMT-008: Verify validation error response structure"""
        response = ResponseFormatter.validation_error('Invalid input')

        assert response['success'] is False
        assert response['error'] == 'Invalid input'
        assert response['error_code'] == 'VALIDATION_ERROR'

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_validation_error_with_field(self):
        """TC-FMT-009: Verify validation error includes field name"""
        response = ResponseFormatter.validation_error('Invalid input',
                                                      field='username')

        assert response['details']['field'] == 'username'


class TestAuthenticationErrorResponse:
    """Test authentication error response"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_authentication_error_default_message(self):
        """TC-FMT-010: Verify authentication error has default message"""
        response = ResponseFormatter.authentication_error()

        assert response['error'] == 'Authentication failed'
        assert response['error_code'] == 'AUTHENTICATION_ERROR'

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_authentication_error_custom_message(self):
        """TC-FMT-011: Verify authentication error accepts custom message"""
        response = ResponseFormatter.authentication_error('Invalid credentials')

        assert response['error'] == 'Invalid credentials'


class TestAuthorizationErrorResponse:
    """Test authorization error response"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_authorization_error_default_message(self):
        """TC-FMT-012: Verify authorization error has default message"""
        response = ResponseFormatter.authorization_error()

        assert response['error'] == 'Insufficient permissions'
        assert response['error_code'] == 'AUTHORIZATION_ERROR'

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_authorization_error_custom_message(self):
        """TC-FMT-013: Verify authorization error accepts custom message"""
        response = ResponseFormatter.authorization_error('Access denied')

        assert response['error'] == 'Access denied'


class TestNotFoundErrorResponse:
    """Test not found error response"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_not_found_error_without_identifier(self):
        """TC-FMT-014: Verify not found error without identifier"""
        response = ResponseFormatter.not_found_error('User')

        assert response['error'] == 'User not found'
        assert response['error_code'] == 'NOT_FOUND'

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_not_found_error_with_identifier(self):
        """TC-FMT-015: Verify not found error with identifier"""
        response = ResponseFormatter.not_found_error('User',
                                                     identifier='user123')

        assert response['error'] == 'User not found: user123'


class TestTimeoutErrorResponse:
    """Test timeout error response"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_timeout_error_structure(self):
        """TC-FMT-016: Verify timeout error structure"""
        response = ResponseFormatter.timeout_error('Database query', 30)

        assert 'Database query' in response['error']
        assert '30 seconds' in response['error']
        assert response['error_code'] == 'TIMEOUT_ERROR'

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_timeout_error_includes_timeout_in_details(self):
        """TC-FMT-017: Verify timeout error includes timeout in details"""
        response = ResponseFormatter.timeout_error('API call', 60)

        assert response['details']['timeout_seconds'] == 60


class TestNetworkErrorResponse:
    """Test network error response"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_network_error_default_message(self):
        """TC-FMT-018: Verify network error has default message"""
        response = ResponseFormatter.network_error()

        assert response['error'] == 'Network error occurred'
        assert response['error_code'] == 'NETWORK_ERROR'

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_network_error_custom_message(self):
        """TC-FMT-019: Verify network error accepts custom message"""
        response = ResponseFormatter.network_error('Connection refused')

        assert response['error'] == 'Connection refused'


class TestInternalErrorResponse:
    """Test internal error response"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_internal_error_default_message(self):
        """TC-FMT-020: Verify internal error has default message"""
        response = ResponseFormatter.internal_error()

        assert response['error'] == 'Internal server error'
        assert response['error_code'] == 'INTERNAL_ERROR'

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_internal_error_custom_message(self):
        """TC-FMT-021: Verify internal error accepts custom message"""
        response = ResponseFormatter.internal_error(
            'Database connection failed')

        assert response['error'] == 'Database connection failed'


class TestResponseConsistency:
    """Test response consistency across methods"""

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_all_responses_have_success_field(self):
        """TC-FMT-022: Verify all responses have success field"""
        success_resp = ResponseFormatter.success()
        error_resp = ResponseFormatter.error('Error')

        assert 'success' in success_resp
        assert 'success' in error_resp

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_all_responses_have_timestamp(self):
        """TC-FMT-023: Verify all responses have timestamp"""
        success_resp = ResponseFormatter.success()
        error_resp = ResponseFormatter.error('Error')

        assert 'timestamp' in success_resp
        assert 'timestamp' in error_resp

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_success_responses_have_no_error(self):
        """TC-FMT-024: Verify success responses have error as None"""
        response = ResponseFormatter.success(data={'test': 'data'})

        assert response['error'] is None

    @pytest.mark.unit
    @pytest.mark.formatter
    def test_error_responses_have_no_data(self):
        """TC-FMT-025: Verify error responses have data as None"""
        response = ResponseFormatter.error('Error message')

        assert response['data'] is None
