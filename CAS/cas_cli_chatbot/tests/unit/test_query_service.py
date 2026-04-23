"""
Unit tests for QueryService
"""
import pytest
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime

from chatbot.services.query_service import QueryService


class TestQueryServiceTokenValidation:
    """Test bearer token validation"""

    @pytest.mark.unit
    @pytest.mark.query
    def test_query_fails_when_auth_service_not_available(
            self, sample_config, mock_logger):
        """TC-QUERY-001: Verify query fails when auth service is not available"""
        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=None)

        result = query_service.query_vector_store("test query")

        assert result['success'] is False
        assert 'Authentication service not available' in result['error']

    @pytest.mark.unit
    @pytest.mark.query
    def test_query_fails_when_bearer_token_invalid(self, sample_config,
                                                   mock_logger,
                                                   mock_auth_service):
        """TC-QUERY-002: Verify query fails when bearer token is invalid"""
        mock_auth_service.has_valid_token.return_value = False
        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)

        result = query_service.query_vector_store("test query")

        assert result['success'] is False
        assert 'No valid bearer token' in result['error']

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_query_proceeds_when_bearer_token_valid(self, mock_post,
                                                    sample_config, mock_logger,
                                                    mock_auth_service,
                                                    mock_requests_response):
        """TC-QUERY-003: Verify query proceeds when bearer token is valid"""
        mock_auth_service.has_valid_token.return_value = True
        mock_post.return_value = mock_requests_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.query_vector_store("test query")

        mock_post.assert_called_once()
        assert result is not None


class TestQueryServiceVectorStoreQueries:
    """Test vector store queries"""

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_successful_query_to_vector_store(self, mock_post, sample_config,
                                              mock_logger, mock_auth_service,
                                              sample_query_result):
        """TC-QUERY-004: Verify successful query to vector store with valid parameters"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = sample_query_result
        mock_response.raise_for_status = Mock()
        mock_post.return_value = mock_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.query_vector_store("test query",
                                                  vector_store="test-vs",
                                                  limit=5)

        assert result == sample_query_result
        mock_post.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_default_vector_store_used_when_not_specified(
            self, mock_post, sample_config, mock_logger, mock_auth_service):
        """TC-QUERY-005: Verify default vector store is used when not specified"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'success': True}
        mock_response.raise_for_status = Mock()
        mock_post.return_value = mock_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        query_service.query_vector_store("test query")

        # Check that default vector store was used in URL
        call_args = mock_post.call_args
        assert sample_config['default_vector_store'] in call_args[0][0]

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_default_limit_used_when_not_specified(self, mock_post,
                                                   sample_config, mock_logger,
                                                   mock_auth_service):
        """TC-QUERY-006: Verify default limit is used when not specified"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'success': True}
        mock_response.raise_for_status = Mock()
        mock_post.return_value = mock_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        query_service.query_vector_store("test query")

        # Check that default limit was used in payload
        call_args = mock_post.call_args
        payload = call_args[1]['json']
        assert payload['max_num_results'] == sample_config['default_limit']

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_query_results_cached_when_cache_available(
            self, mock_post, sample_config, mock_logger, mock_auth_service,
            mock_cache_service, sample_query_result):
        """TC-QUERY-007: Verify query results are cached when cache service is available"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = sample_query_result
        mock_response.raise_for_status = Mock()
        mock_post.return_value = mock_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     cache_service=mock_cache_service,
                                     auth_service=mock_auth_service)
        query_service.query_vector_store("test query")

        # Verify cache.set was called
        mock_cache_service.set.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_cached_results_returned_on_subsequent_queries(
            self, mock_post, sample_config, mock_logger, mock_auth_service,
            mock_cache_service, sample_query_result):
        """TC-QUERY-008: Verify cached results are returned on subsequent identical queries"""
        mock_cache_service.get.return_value = sample_query_result

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     cache_service=mock_cache_service,
                                     auth_service=mock_auth_service)
        result = query_service.query_vector_store("test query")

        # Should not call API since result is cached
        mock_post.assert_not_called()
        assert result == sample_query_result

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_query_timeout_handling(self, mock_post, sample_config, mock_logger,
                                    mock_auth_service):
        """TC-QUERY-009: Verify query timeout handling (30 seconds default)"""
        mock_post.side_effect = Exception("Timeout")

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.query_vector_store("test query")

        assert result['success'] is False
        assert 'error' in result

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_error_handling_for_invalid_vector_store(self, mock_post,
                                                     sample_config, mock_logger,
                                                     mock_auth_service):
        """TC-QUERY-010: Verify error handling for invalid vector store name"""
        mock_response = Mock()
        mock_response.status_code = 404
        mock_response.raise_for_status.side_effect = Exception("Not found")
        mock_post.return_value = mock_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.query_vector_store("test query",
                                                  vector_store="invalid-vs")

        assert result['success'] is False

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_error_handling_for_network_failures(self, mock_post, sample_config,
                                                 mock_logger,
                                                 mock_auth_service):
        """TC-QUERY-011: Verify error handling for network failures"""
        mock_post.side_effect = Exception("Network error")

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.query_vector_store("test query")

        assert result['success'] is False
        assert 'error' in result


class TestQueryServiceFilteredQueries:
    """Test filtered queries"""

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_query_with_filters_executes_successfully(self, mock_post,
                                                      sample_config,
                                                      mock_logger,
                                                      mock_auth_service):
        """TC-QUERY-012: Verify query with filters executes successfully"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'success': True, 'data': []}
        mock_response.raise_for_status = Mock()
        mock_post.return_value = mock_response

        filters = {'key': 'filename', 'operator': 'eq', 'value': 'test.pdf'}
        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.query_with_filters("test query",
                                                  filters,
                                                  vector_store="test-vs")

        assert result['success'] is True
        mock_post.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.post')
    def test_filters_properly_formatted_in_request(self, mock_post,
                                                   sample_config, mock_logger,
                                                   mock_auth_service):
        """TC-QUERY-013: Verify filters are properly formatted in request payload"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'success': True}
        mock_response.raise_for_status = Mock()
        mock_post.return_value = mock_response

        filters = {'key': 'filename', 'operator': 'eq', 'value': 'test.pdf'}
        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        query_service.query_with_filters("test query",
                                         filters,
                                         vector_store="test-vs")

        # Check payload includes filters
        call_args = mock_post.call_args
        payload = call_args[1]['json']
        assert 'filters' in payload
        assert payload['filters'] == filters


class TestQueryServiceVectorStoreManagement:
    """Test vector store management"""

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.get')
    def test_list_vector_stores_returns_all_available(self, mock_get,
                                                      sample_config,
                                                      mock_logger,
                                                      mock_auth_service,
                                                      sample_vector_stores):
        """TC-QUERY-016: Verify list_vector_stores() returns all available vector stores"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'data': [{
                'name': vs
            } for vs in sample_vector_stores]
        }
        mock_response.raise_for_status = Mock()
        mock_get.return_value = mock_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.list_vector_stores(use_cache=False)

        assert len(result) == len(sample_vector_stores)
        assert all(vs in result for vs in sample_vector_stores)

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.get')
    def test_vector_store_list_cached(self, mock_get, sample_config,
                                      mock_logger, mock_auth_service,
                                      mock_cache_service):
        """TC-QUERY-017: Verify vector store list is cached for 10 minutes"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'data': [{'name': 'test-vs'}]}
        mock_response.raise_for_status = Mock()
        mock_get.return_value = mock_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     cache_service=mock_cache_service,
                                     auth_service=mock_auth_service)
        query_service.list_vector_stores(use_cache=False)

        # Verify cache.set was called with 600 seconds TTL
        call_args = mock_cache_service.set.call_args
        assert call_args[1]['ttl_seconds'] == 600

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.get')
    def test_empty_list_when_no_vector_stores(self, mock_get, sample_config,
                                              mock_logger, mock_auth_service):
        """TC-QUERY-018: Verify empty list returned when no vector stores exist"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'data': []}
        mock_response.raise_for_status = Mock()
        mock_get.return_value = mock_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.list_vector_stores(use_cache=False)

        assert result == []


class TestQueryServiceFileContent:
    """Test file content retrieval"""

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.get')
    def test_get_file_content_retrieves_for_valid_file(self, mock_get,
                                                       sample_config,
                                                       mock_logger,
                                                       mock_auth_service):
        """TC-QUERY-021: Verify get_file_content() retrieves content for valid file ID"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'success': True,
            'data': {
                'text': 'File content here'
            }
        }
        mock_response.raise_for_status = Mock()
        mock_get.return_value = mock_response

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.get_file_content("vs-123", "file-456")

        assert result['success'] is True
        assert 'data' in result

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.get')
    def test_error_handling_for_invalid_vector_store_id(self, mock_get,
                                                        sample_config,
                                                        mock_logger,
                                                        mock_auth_service):
        """TC-QUERY-022: Verify error handling for invalid vector store ID"""
        mock_get.side_effect = Exception("Vector store not found")

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.get_file_content("invalid-vs", "file-123")

        assert result['success'] is False
        assert 'error' in result

    @pytest.mark.unit
    @pytest.mark.query
    @patch('chatbot.services.query_service.requests.get')
    def test_error_handling_for_invalid_file_id(self, mock_get, sample_config,
                                                mock_logger, mock_auth_service):
        """TC-QUERY-023: Verify error handling for invalid file ID"""
        mock_get.side_effect = Exception("File not found")

        query_service = QueryService(sample_config,
                                     mock_logger,
                                     auth_service=mock_auth_service)
        result = query_service.get_file_content("vs-123", "invalid-file")

        assert result['success'] is False
        assert 'error' in result


class TestQueryServiceCacheManagement:
    """Test cache management"""

    @pytest.mark.unit
    @pytest.mark.query
    def test_clear_cache_removes_query_entries(self, sample_config, mock_logger,
                                               mock_auth_service,
                                               mock_cache_service):
        """TC-QUERY-025: Verify clear_cache() removes all query-related cache entries"""
        query_service = QueryService(sample_config,
                                     mock_logger,
                                     cache_service=mock_cache_service,
                                     auth_service=mock_auth_service)
        query_service.clear_cache()

        mock_cache_service.clear_pattern.assert_called_once_with("query_*")

    @pytest.mark.unit
    @pytest.mark.query
    def test_statistics_include_cache_info(self, sample_config, mock_logger,
                                           mock_auth_service,
                                           mock_cache_service):
        """TC-QUERY-026: Verify statistics include cache information when cache service is available"""
        query_service = QueryService(sample_config,
                                     mock_logger,
                                     cache_service=mock_cache_service,
                                     auth_service=mock_auth_service)
        stats = query_service.get_statistics()

        assert 'cache_enabled' in stats
        assert stats['cache_enabled'] is True
        assert 'cache_stats' in stats
