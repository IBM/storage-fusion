"""
Integration tests for end-to-end workflows
"""
import pytest
from unittest.mock import Mock, patch, MagicMock


class TestEndToEndWorkflows:
    """Test complete end-to-end workflows"""

    @pytest.mark.integration
    @pytest.mark.slow
    @patch('chatbot.services.auth_service.subprocess.run')
    @patch('chatbot.services.query_service.requests.post')
    @patch('chatbot.services.query_service.requests.get')
    def test_authenticate_list_select_query_workflow(self, mock_get, mock_post,
                                                     mock_run, sample_config,
                                                     mock_logger,
                                                     mock_cache_service,
                                                     mock_metrics_service):
        """TC-INT-001: Complete workflow: authenticate → list vector stores → select → query"""
        from chatbot.services.auth_service import AuthService
        from chatbot.services.query_service import QueryService

        # Setup authentication mocks
        login_result = Mock()
        login_result.returncode = 0
        token_result = Mock()
        token_result.returncode = 0
        token_result.stdout = 'test-token-123'
        mock_run.side_effect = [login_result, token_result]

        # Setup vector store list mock
        mock_get_response = Mock()
        mock_get_response.status_code = 200
        mock_get_response.json.return_value = {
            'data': [{
                'name': 'vector-store-1'
            }, {
                'name': 'vector-store-2'
            }]
        }
        mock_get_response.raise_for_status = Mock()
        mock_get.return_value = mock_get_response

        # Setup query mock
        mock_post_response = Mock()
        mock_post_response.status_code = 200
        mock_post_response.json.return_value = {
            'success': True,
            'data': [{
                'text': 'Result 1'
            }, {
                'text': 'Result 2'
            }]
        }
        mock_post_response.raise_for_status = Mock()
        mock_post.return_value = mock_post_response

        # Execute workflow
        # 1. Authenticate
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_result = auth_service.authenticate()
        assert auth_result is True
        assert auth_service.token == 'test-token-123'

        # 2. List vector stores
        query_service = QueryService(sample_config,
                                     mock_logger,
                                     cache_service=mock_cache_service,
                                     auth_service=auth_service)
        vector_stores = query_service.list_vector_stores(use_cache=False)
        assert len(vector_stores) == 2
        assert 'vector-store-1' in vector_stores

        # 3. Query selected vector store
        query_result = query_service.query_vector_store(
            "test query", vector_store="vector-store-1", limit=5)
        assert query_result['success'] is True
        assert len(query_result['data']) == 2

    @pytest.mark.integration
    @pytest.mark.slow
    @patch('chatbot.services.vector_store_service.subprocess.run')
    def test_vector_search_retrieve_file_query_workflow(self, mock_run,
                                                        sample_config,
                                                        mock_logger,
                                                        mock_auth_service):
        """TC-INT-003: Complete workflow: vector search → retrieve file content → query file"""
        from chatbot.services.vector_store_service import VectorStoreService
        from chatbot.services.query_service import QueryService

        # Setup vector store service
        vector_store_service = VectorStoreService(sample_config,
                                                  mock_auth_service,
                                                  mock_logger)

        # Mock vector store listing
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = b'{"items": [{"metadata": {"name": "test-vs"}}]}'
        mock_run.return_value = mock_result

        vector_stores = vector_store_service.list_vector_stores(use_cache=False)
        assert 'test-vs' in vector_stores


class TestServiceIntegration:
    """Test service integration"""

    @pytest.mark.integration
    def test_auth_service_token_used_by_query_service(self, sample_config,
                                                      mock_logger,
                                                      mock_cache_service):
        """TC-INT-005: Verify auth service token is used by query service"""
        from chatbot.services.auth_service import AuthService
        from chatbot.services.query_service import QueryService

        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = 'integration-test-token'
        auth_service.token_expiry = None  # Will make has_valid_token return False

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=auth_service)

        # Query should fail because token is not valid
        result = query_service.query_vector_store("test query")
        assert result['success'] is False

    @pytest.mark.integration
    def test_cache_service_used_across_services(self, sample_config,
                                                mock_logger, mock_cache_service,
                                                mock_auth_service):
        """TC-INT-006: Verify cache service is used across all services"""
        from chatbot.services.query_service import QueryService

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     cache_service=mock_cache_service,
                                     auth_service=mock_auth_service)

        # Cache should be checked for vector stores
        mock_cache_service.get.return_value = ['cached-vs-1', 'cached-vs-2']

        result = query_service.list_vector_stores(use_cache=True)

        # Should return cached result
        assert result == ['cached-vs-1', 'cached-vs-2']
        mock_cache_service.get.assert_called_once()

    @pytest.mark.integration
    def test_metrics_service_tracks_operations(self, sample_config, mock_logger,
                                               mock_metrics_service):
        """TC-INT-007: Verify metrics service tracks operations across services"""
        from chatbot.services.llm_service import LLMService

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)

        # Metrics should be tracked
        with patch('chatbot.services.llm_service.LLMService._call_nvidia'
                  ) as mock_nvidia:
            mock_nvidia.return_value = "test response"
            sample_config['llm_provider_sequence'] = ['nvidia']

            llm_service.call_llm({'data': 'test'}, "test query")

            # Verify metrics were recorded
            assert mock_metrics_service.increment.called
            assert mock_metrics_service.record_timing.called


class TestTokenRefreshIntegration:
    """Test token refresh integration"""

    @pytest.mark.integration
    @pytest.mark.slow
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_token_refresh_during_long_session(self, mock_run, sample_config,
                                               mock_logger, mock_cache_service):
        """TC-INT-009: Verify token refresh when approaching expiry during long session"""
        from chatbot.services.auth_service import AuthService
        from datetime import datetime, timedelta

        # Initial authentication
        login_result = Mock()
        login_result.returncode = 0
        token_result = Mock()
        token_result.returncode = 0
        token_result.stdout = 'initial-token'
        mock_run.side_effect = [login_result, token_result]

        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.authenticate()

        assert auth_service.token == 'initial-token'

        # Simulate token approaching expiry
        auth_service.token_expiry = datetime.now() + timedelta(minutes=3)

        # Setup refresh mocks
        refresh_login = Mock()
        refresh_login.returncode = 0
        refresh_token = Mock()
        refresh_token.returncode = 0
        refresh_token.stdout = 'refreshed-token'
        mock_run.side_effect = [refresh_login, refresh_token]

        # Trigger refresh
        auth_service.authenticate()

        assert auth_service.token == 'refreshed-token'

    @pytest.mark.integration
    @patch('chatbot.services.auth_service.subprocess.run')
    def test_operations_continue_after_token_refresh(self, mock_run,
                                                     sample_config, mock_logger,
                                                     mock_cache_service):
        """TC-INT-010: Verify operations continue after token refresh"""
        from chatbot.services.auth_service import AuthService
        from chatbot.services.query_service import QueryService

        # Setup auth service with token
        auth_service = AuthService(sample_config, mock_logger,
                                   mock_cache_service)
        auth_service.token = 'old-token'

        # Create query service
        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=auth_service)

        # Refresh token
        login_result = Mock()
        login_result.returncode = 0
        token_result = Mock()
        token_result.returncode = 0
        token_result.stdout = 'new-token'
        mock_run.side_effect = [login_result, token_result]

        auth_service.authenticate()

        # Query service should use new token
        assert auth_service.token == 'new-token'

        with patch('chatbot.services.query_service.requests.post') as mock_post:
            mock_response = Mock()
            mock_response.status_code = 200
            mock_response.json.return_value = {'success': True, 'data': []}
            mock_response.raise_for_status = Mock()
            mock_post.return_value = mock_response

            result = query_service.query_vector_store("test query")

            # Should use new token in request
            call_args = mock_post.call_args
            headers = call_args[1]['headers']
            assert headers['Authorization'] == 'Bearer new-token'
