"""
Unit tests for HealthChecker
"""
import pytest
from unittest.mock import Mock, patch
from datetime import datetime

from chatbot.utils.health_check import HealthChecker


class TestHealthCheckerOverall:
    """Test overall health check functionality"""

    @pytest.mark.unit
    @pytest.mark.health
    def test_run_all_checks_executes_all_services(self, mock_logger):
        """TC-HEALTH-001: Verify run_all_checks() executes all service checks"""
        services = {
            'auth': Mock(),
            'cache': Mock(),
            'user': Mock(),
            'vector store': Mock(),
            'query': Mock(),
            'llm': Mock()
        }

        # Setup mocks
        services['auth'].token = 'test-token'
        services['cache'].get_statistics.return_value = {
            'entries': 10,
            'hit_rate_percent': 80.0
        }
        services['user'].list_oc_users.return_value = ['user1', 'user2']
        services['vector store'].config = {'cas_namespace': 'ibm-cas'}
        services['vector store'].list_vector_stores.return_value = [
            'vs1', 'vs2'
        ]
        services['query'].config = {'cas_url': 'https://test.com'}
        services['llm'].config = {'llm_provider_sequence': ['nvidia']}

        health_checker = HealthChecker(services, mock_logger)

        with patch('chatbot.utils.health_check.subprocess.run') as mock_run:
            mock_result = Mock()
            mock_result.returncode = 0
            mock_result.stdout = b'oc v4.12.0'
            mock_run.return_value = mock_result

            results = health_checker.run_all_checks()

        # Should have results for all services
        assert 'auth' in results
        assert 'cache' in results
        assert 'user' in results
        assert 'vector store' in results
        assert 'query' in results
        assert 'llm' in results
        assert 'oc_cli' in results

    @pytest.mark.unit
    @pytest.mark.health
    def test_results_include_timestamp(self, mock_logger):
        """TC-HEALTH-002: Verify results include timestamp for each check"""
        services = {'auth': Mock()}
        services['auth'].token = 'test-token'

        health_checker = HealthChecker(services, mock_logger)
        results = health_checker.run_all_checks()

        for service_name, result in results.items():
            assert 'timestamp' in result
            # Verify timestamp is valid ISO format
            datetime.fromisoformat(result['timestamp'])

    @pytest.mark.unit
    @pytest.mark.health
    def test_exception_handling_for_failed_checks(self, mock_logger):
        """TC-HEALTH-003: Verify exception handling for failed checks"""
        services = {'auth': Mock()}
        services['auth'].token = None  # Will cause check to fail

        health_checker = HealthChecker(services, mock_logger)
        results = health_checker.run_all_checks()

        # Should still return results even if some checks fail
        assert 'auth' in results
        assert results['auth']['healthy'] is False


class TestHealthCheckerIndividualServices:
    """Test individual service health checks"""

    @pytest.mark.unit
    @pytest.mark.health
    def test_auth_service_healthy_when_token_exists(self, mock_logger):
        """TC-HEALTH-004: Verify auth service check returns healthy when token exists"""
        services = {'auth': Mock()}
        services['auth'].token = 'test-token'

        health_checker = HealthChecker(services, mock_logger)
        result = health_checker.check_auth_service()

        assert result['healthy'] is True
        assert 'Authenticated' in result['message']

    @pytest.mark.unit
    @pytest.mark.health
    def test_auth_service_unhealthy_when_no_token(self, mock_logger):
        """TC-HEALTH-005: Verify auth service check returns unhealthy when no token"""
        services = {'auth': Mock()}
        services['auth'].token = None

        health_checker = HealthChecker(services, mock_logger)
        result = health_checker.check_auth_service()

        assert result['healthy'] is False
        assert 'No authentication token' in result['message']

    @pytest.mark.unit
    @pytest.mark.health
    def test_cache_service_includes_hit_rate_statistics(self, mock_logger):
        """TC-HEALTH-006: Verify cache service check includes hit rate statistics"""
        services = {'cache': Mock()}
        services['cache'].get_statistics.return_value = {
            'entries': 25,
            'hit_rate_percent': 85.5
        }

        health_checker = HealthChecker(services, mock_logger)
        result = health_checker.check_cache_service()

        assert result['healthy'] is True
        assert '25 entries' in result['message']
        assert '85.5%' in result['message']

    @pytest.mark.unit
    @pytest.mark.health
    def test_user_service_attempts_to_fetch_users(self, mock_logger):
        """TC-HEALTH-007: Verify user service check attempts to fetch users"""
        services = {'user': Mock()}
        services['user'].list_oc_users.return_value = [
            'user1', 'user2', 'user3'
        ]

        health_checker = HealthChecker(services, mock_logger)
        result = health_checker.check_user_service()

        assert result['healthy'] is True
        assert '3 OCP users' in result['message']
        services['user'].list_oc_users.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.health
    def test_vector_store_service_counts_available_stores(self, mock_logger):
        """TC-HEALTH-008: Verify vector store service check counts available vector stores"""
        services = {'vector store': Mock()}
        services['vector store'].config = {'cas_namespace': 'ibm-cas'}
        services['vector store'].list_vector_stores.return_value = [
            'vs1', 'vs2', 'vs3', 'vs4'
        ]

        health_checker = HealthChecker(services, mock_logger)
        result = health_checker.check_vector_store_service()

        assert result['healthy'] is True
        assert '4 vector stores' in result['message']

    @pytest.mark.unit
    @pytest.mark.health
    def test_query_service_validates_cas_url_configuration(self, mock_logger):
        """TC-HEALTH-009: Verify query service check validates CAS URL configuration"""
        services = {'query': Mock()}
        services['query'].config = {'cas_url': 'https://cas-api.test.com'}

        health_checker = HealthChecker(services, mock_logger)
        result = health_checker.check_query_service()

        assert result['healthy'] is True
        assert 'Configured' in result['message']

    @pytest.mark.unit
    @pytest.mark.health
    def test_llm_service_lists_configured_providers(self, mock_logger):
        """TC-HEALTH-010: Verify LLM service check lists configured providers"""
        services = {'llm': Mock()}
        services['llm'].config = {
            'llm_provider_sequence': ['nvidia', 'openai', 'ollama']
        }

        health_checker = HealthChecker(services, mock_logger)
        result = health_checker.check_llm_service()

        assert result['healthy'] is True
        assert 'nvidia' in result['message']
        assert 'openai' in result['message']
        assert 'ollama' in result['message']

    @pytest.mark.unit
    @pytest.mark.health
    @patch('chatbot.utils.health_check.subprocess.run')
    def test_oc_cli_validates_installation_and_version(self, mock_run,
                                                       mock_logger):
        """TC-HEALTH-011: Verify OC CLI check validates installation and version"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = b'Client Version: 4.12.0\nKubernetes Version: v1.25.0'
        mock_run.return_value = mock_result

        health_checker = HealthChecker({}, mock_logger)
        result = health_checker.check_oc_cli()

        assert result['healthy'] is True
        assert 'Installed' in result['message']


class TestHealthCheckerOCCLI:
    """Test OC CLI health checks"""

    @pytest.mark.unit
    @pytest.mark.health
    @pytest.mark.requires_oc
    @patch('chatbot.utils.health_check.subprocess.run')
    def test_healthy_status_when_oc_installed(self, mock_run, mock_logger):
        """TC-HEALTH-012: Verify healthy status when oc CLI is installed"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = b'oc v4.12.0'
        mock_run.return_value = mock_result

        health_checker = HealthChecker({}, mock_logger)
        result = health_checker.check_oc_cli()

        assert result['healthy'] is True

    @pytest.mark.unit
    @pytest.mark.health
    @pytest.mark.requires_oc
    @patch('chatbot.utils.health_check.subprocess.run')
    def test_unhealthy_status_when_oc_not_installed(self, mock_run,
                                                    mock_logger):
        """TC-HEALTH-013: Verify unhealthy status when oc CLI is not installed"""
        mock_run.side_effect = FileNotFoundError()

        health_checker = HealthChecker({}, mock_logger)
        result = health_checker.check_oc_cli()

        assert result['healthy'] is False
        assert 'not installed' in result['message']

    @pytest.mark.unit
    @pytest.mark.health
    @pytest.mark.requires_oc
    @patch('chatbot.utils.health_check.subprocess.run')
    def test_timeout_handling(self, mock_run, mock_logger):
        """TC-HEALTH-014: Verify timeout handling (5 seconds)"""
        import subprocess
        mock_run.side_effect = subprocess.TimeoutExpired('oc', 5)

        health_checker = HealthChecker({}, mock_logger)
        result = health_checker.check_oc_cli()

        assert result['healthy'] is False
        assert 'timeout' in result['message'].lower()

    @pytest.mark.unit
    @pytest.mark.health
    @pytest.mark.requires_oc
    @patch('chatbot.utils.health_check.subprocess.run')
    def test_version_information_included_in_healthy_response(
            self, mock_run, mock_logger):
        """TC-HEALTH-015: Verify version information is included in healthy response"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = b'Client Version: 4.12.0'
        mock_run.return_value = mock_result

        health_checker = HealthChecker({}, mock_logger)
        result = health_checker.check_oc_cli()

        assert result['healthy'] is True
        assert 'Client Version: 4.12.0' in result['message']
