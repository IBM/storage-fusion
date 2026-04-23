"""
Pytest configuration and shared fixtures
"""
import pytest
import logging
from unittest.mock import Mock, MagicMock
from datetime import datetime, timedelta


@pytest.fixture
def mock_logger():
    """Mock logger for testing"""
    logger = Mock(spec=logging.Logger)
    logger.info = Mock()
    logger.error = Mock()
    logger.warning = Mock()
    logger.debug = Mock()
    logger.exception = Mock()
    return logger


@pytest.fixture
def mock_console():
    """Mock Rich console for testing"""
    console = Mock()
    console.print = Mock()
    return console


@pytest.fixture
def sample_config():
    """Sample configuration for testing"""
    return {
        'console_url':
            'https://console-openshift-console.apps.test-cluster.com',
        'oc_username':
            'test-user',
        'oc_password':
            'test-password',
        'cas_url':
            'https://console-ibm-spectrum-fusion-ns.apps.test-cluster.com/cas/api/v1',
        'cas_namespace':
            'ibm-cas',
        'default_vector_store':
            'test-vector-store',
        'default_limit':
            5,
        'allow_self_signed':
            True,
        'token_refresh_threshold':
            300,
        'request_timeout':
            30,
        'llm_timeout':
            60,
        'llm_max_retries':
            2,
        'llm_provider_sequence': ['nvidia', 'openai', 'ollama'],
        'nvidia_llm_url':
            'http://test-nvidia-endpoint',
        'nvidia_model':
            'meta/llama-3.2-1b-instruct',
        'openai_api_key':
            'sk-test-key',
        'openai_model':
            'gpt-3.5-turbo',
        'ollama_host':
            'http://localhost:11434',
        'ollama_model':
            'llama3',
        'enable_source':
            False,
        'enable_content_metadata':
            False,
        'cache': {
            'default_ttl': 300,
            'max_entries': 1000,
            'user_cache_ttl': 600,
            'domain_cache_ttl': 300,
            'query_cache_ttl': 180
        },
        'logging': {
            'level': 'INFO',
            'file': 'logs/cas_chatbot.log',
            'max_bytes': 10485760,
            'backup_count': 5
        }
    }


@pytest.fixture
def mock_cache_service():
    """Mock cache service for testing"""
    cache = Mock()
    cache.get = Mock(return_value=None)
    cache.set = Mock()
    cache.delete = Mock()
    cache.clear_pattern = Mock()
    cache.get_statistics = Mock(return_value={
        'entries': 10,
        'hits': 50,
        'misses': 10,
        'hit_rate_percent': 83.33
    })
    return cache


@pytest.fixture
def mock_metrics_service():
    """Mock metrics service for testing"""
    metrics = Mock()
    metrics.increment = Mock()
    metrics.record_timing = Mock()
    metrics.record_error = Mock()
    metrics.get_statistics = Mock(return_value={
        'total_requests': 100,
        'total_errors': 5,
        'uptime_seconds': 3600
    })
    return metrics


@pytest.fixture
def mock_auth_service(sample_config, mock_logger, mock_cache_service):
    """Mock authentication service for testing"""
    auth = Mock()
    auth.config = sample_config
    auth.logger = mock_logger
    auth.cache_service = mock_cache_service
    auth.username = sample_config['oc_username']
    auth.password = sample_config['oc_password']
    auth.console_url = sample_config['console_url']
    auth.token = 'test-bearer-token-12345'
    auth.token_expiry = datetime.now() + timedelta(hours=24)
    auth.token_fetch_attempted = True
    auth.authenticate = Mock(return_value=True)
    auth.has_valid_token = Mock(return_value=True)
    auth.get_token_info = Mock(
        return_value={
            'oc_authenticated': True,
            'token_valid': True,
            'token_fetch_attempted': True,
            'oc_token_expires_in': 86400
        })
    auth.refresh_tokens = Mock()
    auth.logout = Mock()
    return auth


@pytest.fixture
def mock_subprocess_run():
    """Mock subprocess.run for testing"""
    mock_result = Mock()
    mock_result.returncode = 0
    mock_result.stdout = b'test-output'
    mock_result.stderr = b''
    return mock_result


@pytest.fixture
def mock_requests_response():
    """Mock requests response for testing"""
    response = Mock()
    response.status_code = 200
    response.ok = True
    response.json = Mock(return_value={'success': True, 'data': []})
    response.text = 'Success'
    response.raise_for_status = Mock()
    return response


@pytest.fixture
def sample_vector_stores():
    """Sample vector stores data for testing"""
    return ['vector-store-1', 'vector-store-2', 'test-vector-store']


@pytest.fixture
def sample_query_result():
    """Sample query result for testing"""
    return {
        'success': True,
        'data': [{
            'text': 'Sample text chunk 1',
            'metadata': {
                'filename': 'test-file-1.pdf',
                'file_id': 'file-123',
                'score': 0.95
            }
        }, {
            'text': 'Sample text chunk 2',
            'metadata': {
                'filename': 'test-file-2.pdf',
                'file_id': 'file-456',
                'score': 0.87
            }
        }],
        'timestamp': datetime.now().isoformat()
    }


@pytest.fixture
def sample_llm_response():
    """Sample LLM response for testing"""
    return "This is a test LLM response based on the provided context."


@pytest.fixture
def sample_health_check_results():
    """Sample health check results for testing"""
    return {
        'auth': {
            'healthy': True,
            'message': 'Authenticated',
            'timestamp': datetime.now().isoformat()
        },
        'cache': {
            'healthy': True,
            'message': '10 entries, 83.33% hit rate',
            'timestamp': datetime.now().isoformat()
        },
        'user': {
            'healthy': True,
            'message': 'Connected, 5 OCP users',
            'timestamp': datetime.now().isoformat()
        },
        'vector store': {
            'healthy': True,
            'message': '3 vector stores available',
            'timestamp': datetime.now().isoformat()
        },
        'query': {
            'healthy': True,
            'message': 'Configured',
            'timestamp': datetime.now().isoformat()
        },
        'llm': {
            'healthy': True,
            'message': 'Providers: nvidia, openai, ollama',
            'timestamp': datetime.now().isoformat()
        },
        'oc_cli': {
            'healthy': True,
            'message': 'Installed: oc v4.12.0',
            'timestamp': datetime.now().isoformat()
        }
    }
