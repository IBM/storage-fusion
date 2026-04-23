"""
Unit tests for AuthService
"""
import pytest
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime, timedelta
import subprocess

from chatbot.services.auth_service import AuthService, AuthenticationError, ConfigurationError


class TestAuthServiceConfiguration:
    """Test authentication service configuration"""

    @pytest.mark.unit
    @pytest.mark.auth
    def test_missing_username_raises_error(self, mock_logger,
                                           mock_cache_service):
        """TC-AUTH-001: Verify authentication fails when oc_username is missing"""
        config = {
            'oc_password': 'test-password',
            'console_url': 'https://console.test.com'
        }

        with pytest.raises(ConfigurationError) as exc_info:
            AuthService(config, mock_logger, mock_cache_service)

        assert 'oc_username' in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.auth
    def test_missing_password_raises_error(self, mock_logger,
                                           mock_cache_service):
        """TC-AUTH-002: Verify authentication fails when oc_password is missing"""
        config = {
            'oc_username': 'test-user',
            'console_url': 'https://console.test.com'
        }

        with pytest.raises(ConfigurationError) as exc_info:
            AuthService(config, mock_logger, mock_cache_service)

        assert 'oc_password' in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.auth
    def test_missing_console_url_raises_error(self, mock_logger,
                                              mock_cache_service):
        """TC-AUTH-003: Verify authentication fails when console_url is missing"""
        config = {'oc_username': 'test-user', 'oc_password': 'test-password'}

        with pytest.raises(ConfigurationError) as exc_info:
            AuthService(config, mock_logger, mock_cache_service)

        assert 'console_url' in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.auth
    def test_multiple_missing_fields_error_message(self, mock_logger,
                                                   mock_cache_service):
        """TC-AUTH-004: Verify ConfigurationError with appropriate message for missing fields"""
        config = {}

        with pytest.raises(ConfigurationError) as exc_info:
            AuthService(config, mock_logger, mock_cache_service)

        error_msg = str(exc_info.value)
        assert 'oc_username' in error_msg
        assert 'oc_password' in error_msg
        assert 'console_url' in error_msg


class TestAuthServiceAPIURL:
    """Test API URL extraction"""

    @pytest.mark.unit
    @pytest.mark.auth
    def test_correct_api_url_extraction(self, sample_config, mock_logger,
                                        mock_cache_service):
        """TC-AUTH-005: Verify correct API URL extraction from standard OpenShift console URL"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)

        api_url = auth_service.get_api_url_from_console()

        assert api_url == 'https://api.test-cluster.com:6443'

    @pytest.mark.unit
    @pytest.mark.auth
    def test_invalid_console_url_no_hostname(self, sample_config, mock_logger,
                                             mock_cache_service):
        """TC-AUTH-006: Verify error handling for invalid console URL (no hostname)"""
        sample_config['console_url'] = 'not-a-valid-url'
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)

        with pytest.raises(ConfigurationError) as exc_info:
            auth_service.get_api_url_from_console()

        assert 'Invalid console URL' in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.auth
    def test_unsupported_console_url_format(self, sample_config, mock_logger,
                                            mock_cache_service):
        """TC-AUTH-007: Verify error handling for unsupported console URL format"""
        sample_config['console_url'] = 'https://different-format.com'
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)

        with pytest.raises(ConfigurationError) as exc_info:
            auth_service.get_api_url_from_console()

        assert 'Unsupported' in str(exc_info.value)


class TestAuthServiceAuthentication:
    """Test authentication flow"""

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_successful_authentication(self, mock_run, sample_config,
                                       mock_logger, mock_cache_service):
        """TC-AUTH-008: Verify successful authentication with valid credentials"""
        # Mock successful oc login
        login_result = Mock()
        login_result.returncode = 0
        login_result.stdout = 'Login successful'
        login_result.stderr = ''

        # Mock successful token retrieval
        token_result = Mock()
        token_result.returncode = 0
        token_result.stdout = 'test-bearer-token-12345'
        token_result.stderr = ''

        mock_run.side_effect = [login_result, token_result]

        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        result = auth_service.authenticate()

        assert result is True
        assert auth_service.token == 'test-bearer-token-12345'

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_bearer_token_retrieved_after_login(self, mock_run, sample_config,
                                                mock_logger,
                                                mock_cache_service):
        """TC-AUTH-009: Verify bearer token is retrieved after successful login"""
        login_result = Mock()
        login_result.returncode = 0

        token_result = Mock()
        token_result.returncode = 0
        token_result.stdout = 'test-token-abc123'

        mock_run.side_effect = [login_result, token_result]

        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.authenticate()

        assert auth_service.token == 'test-token-abc123'
        assert auth_service.token_expiry is not None

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_authentication_fails_with_invalid_credentials(
            self, mock_run, sample_config, mock_logger, mock_cache_service):
        """TC-AUTH-010: Verify authentication fails with invalid credentials"""
        login_result = Mock()
        login_result.returncode = 1
        login_result.stderr = 'Login failed: invalid credentials'

        mock_run.return_value = login_result

        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)

        with pytest.raises(AuthenticationError) as exc_info:
            auth_service.authenticate()

        assert 'Login failed' in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_authentication_timeout_handling(self, mock_run, sample_config,
                                             mock_logger, mock_cache_service):
        """TC-AUTH-011: Verify authentication timeout handling (30 seconds)"""
        mock_run.side_effect = subprocess.TimeoutExpired('oc', 30)

        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)

        with pytest.raises(AuthenticationError) as exc_info:
            auth_service.authenticate()

        assert 'timed out' in str(exc_info.value).lower()

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_token_expiry_set_after_authentication(self, mock_run,
                                                   sample_config, mock_logger,
                                                   mock_cache_service):
        """TC-AUTH-012: Verify token expiry is set to 24 hours after successful authentication"""
        login_result = Mock()
        login_result.returncode = 0

        token_result = Mock()
        token_result.returncode = 0
        token_result.stdout = 'test-token'

        mock_run.side_effect = [login_result, token_result]

        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        before_auth = datetime.now()
        auth_service.authenticate()
        after_auth = datetime.now()

        # Token should expire approximately 24 hours from now
        expected_expiry = before_auth + timedelta(hours=24)
        assert auth_service.token_expiry >= expected_expiry
        assert auth_service.token_expiry <= after_auth + timedelta(hours=24,
                                                                   minutes=1)

    @pytest.mark.unit
    @pytest.mark.auth
    def test_cached_token_used_when_valid(self, sample_config, mock_logger,
                                          mock_cache_service):
        """TC-AUTH-013: Verify cached token is used when valid"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = 'cached-token'
        auth_service.token_expiry = datetime.now() + timedelta(hours=1)

        with patch('chatbot.services.auth_service.subprocess.run') as mock_run:
            result = auth_service.authenticate()

            # Should not call subprocess since token is valid
            mock_run.assert_not_called()
            assert result is True

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_token_refresh_when_expiry_threshold_reached(
            self, mock_run, sample_config, mock_logger, mock_cache_service):
        """TC-AUTH-014: Verify token refresh when expiry threshold is reached (5 minutes)"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        # Set token to expire in 4 minutes (below 5 minute threshold)
        auth_service.token = 'old-token'
        auth_service.token_expiry = datetime.now() + timedelta(minutes=4)

        login_result = Mock()
        login_result.returncode = 0

        token_result = Mock()
        token_result.returncode = 0
        token_result.stdout = 'new-token'

        mock_run.side_effect = [login_result, token_result]

        auth_service.authenticate()

        # Should have refreshed the token
        assert auth_service.token == 'new-token'


class TestAuthServiceTokenManagement:
    """Test token management"""

    @pytest.mark.unit
    @pytest.mark.auth
    def test_has_valid_token_returns_true_when_valid(self, sample_config,
                                                     mock_logger,
                                                     mock_cache_service):
        """TC-AUTH-015: Verify has_valid_token() returns True when token is valid"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = 'valid-token'
        auth_service.token_expiry = datetime.now() + timedelta(hours=1)

        assert auth_service.has_valid_token() is True

    @pytest.mark.unit
    @pytest.mark.auth
    def test_has_valid_token_returns_false_when_expired(self, sample_config,
                                                        mock_logger,
                                                        mock_cache_service):
        """TC-AUTH-016: Verify has_valid_token() returns False when token is expired"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = 'expired-token'
        auth_service.token_expiry = datetime.now() - timedelta(hours=1)

        assert auth_service.has_valid_token() is False

    @pytest.mark.unit
    @pytest.mark.auth
    def test_has_valid_token_returns_false_when_no_token(
            self, sample_config, mock_logger, mock_cache_service):
        """TC-AUTH-017: Verify has_valid_token() returns False when no token exists"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = None

        assert auth_service.has_valid_token() is False

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_token_cached_in_cache_service(self, mock_run, sample_config,
                                           mock_logger, mock_cache_service):
        """TC-AUTH-018: Verify token is cached in cache service when available"""
        login_result = Mock()
        login_result.returncode = 0

        token_result = Mock()
        token_result.returncode = 0
        token_result.stdout = 'test-token'

        mock_run.side_effect = [login_result, token_result]

        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.authenticate()

        # Verify cache service was called to store token
        mock_cache_service.set.assert_called_once()
        call_args = mock_cache_service.set.call_args
        assert call_args[0][0] == 'auth_token'
        assert call_args[0][1] == 'test-token'

    @pytest.mark.unit
    @pytest.mark.auth
    def test_get_token_info_returns_correct_status(self, sample_config,
                                                   mock_logger,
                                                   mock_cache_service):
        """TC-AUTH-019: Verify get_token_info() returns correct token status information"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = 'test-token'
        auth_service.token_expiry = datetime.now() + timedelta(hours=2)
        auth_service.token_fetch_attempted = True

        info = auth_service.get_token_info()

        assert info['oc_authenticated'] is True
        assert info['token_valid'] is True
        assert info['token_fetch_attempted'] is True
        assert 'oc_token_expires_in' in info
        assert info['oc_token_expires_in'] > 0


class TestAuthServiceLogout:
    """Test logout functionality"""

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_logout_clears_bearer_token(self, mock_run, sample_config,
                                        mock_logger, mock_cache_service):
        """TC-AUTH-020: Verify logout clears bearer token"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = 'test-token'

        auth_service.logout()

        assert auth_service.token is None

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_logout_clears_token_expiry(self, mock_run, sample_config,
                                        mock_logger, mock_cache_service):
        """TC-AUTH-021: Verify logout clears token expiry"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = 'test-token'
        auth_service.token_expiry = datetime.now() + timedelta(hours=1)

        auth_service.logout()

        assert auth_service.token_expiry is None

    @pytest.mark.unit
    @pytest.mark.auth
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_logout_clears_cached_token(self, mock_run, sample_config,
                                        mock_logger, mock_cache_service):
        """TC-AUTH-022: Verify logout clears cached token from cache service"""
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = 'test-token'

        auth_service.logout()

        mock_cache_service.delete.assert_called_once_with('auth_token')
