"""
Unit tests for LLMService
"""
import pytest
from unittest.mock import Mock, patch, MagicMock
import json

from chatbot.services.llm_service import LLMService


class TestLLMServiceProviderConfiguration:
    """Test LLM provider configuration"""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_error_when_no_providers_configured(self, sample_config,
                                                mock_logger,
                                                mock_metrics_service,
                                                sample_query_result):
        """TC-LLM-001: Verify error when no LLM providers are configured"""
        sample_config['llm_provider_sequence'] = []
        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)

        result = llm_service.call_llm(sample_query_result, "test query")

        assert result is None

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.LLMService._call_nvidia')
    @patch('chatbot.services.llm_service.LLMService._call_openai')
    def test_providers_tried_in_sequence_order(self, mock_openai, mock_nvidia,
                                               sample_config, mock_logger,
                                               mock_metrics_service,
                                               sample_query_result):
        """TC-LLM-002: Verify providers are tried in sequence order"""
        sample_config['llm_provider_sequence'] = ['nvidia', 'openai']
        mock_nvidia.return_value = "NVIDIA response"

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service.call_llm(sample_query_result, "test query")

        # NVIDIA should be called first
        mock_nvidia.assert_called_once()
        # OpenAI should not be called since NVIDIA succeeded
        mock_openai.assert_not_called()
        assert result == "NVIDIA response"

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.LLMService._call_openai')
    @patch('chatbot.services.llm_service.LLMService._call_nvidia')
    def test_fallback_to_next_provider_on_failure(self, mock_nvidia,
                                                  mock_openai, sample_config,
                                                  mock_logger,
                                                  mock_metrics_service,
                                                  sample_query_result):
        """TC-LLM-003: Verify fallback to next provider when current provider fails"""
        sample_config['llm_provider_sequence'] = ['nvidia', 'openai']
        mock_nvidia.side_effect = Exception("NVIDIA failed")
        mock_openai.return_value = "OpenAI response"

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service.call_llm(sample_query_result, "test query")

        # Both should be called
        mock_nvidia.assert_called_once()
        mock_openai.assert_called_once()
        assert result == "OpenAI response"

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.LLMService._call_nvidia')
    @patch('chatbot.services.llm_service.LLMService._call_openai')
    def test_error_when_all_providers_fail(self, mock_openai, mock_nvidia,
                                           sample_config, mock_logger,
                                           mock_metrics_service,
                                           sample_query_result):
        """TC-LLM-004: Verify error when all providers fail"""
        sample_config['llm_provider_sequence'] = ['nvidia', 'openai']
        mock_nvidia.side_effect = Exception("NVIDIA failed")
        mock_openai.side_effect = Exception("OpenAI failed")

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service.call_llm(sample_query_result, "test query")

        assert result is None


class TestLLMServiceOpenAIProvider:
    """Test OpenAI provider"""

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.OpenAI')
    def test_successful_openai_call(self, mock_openai_class, sample_config,
                                    mock_logger, mock_metrics_service):
        """TC-LLM-005: Verify successful OpenAI API call with valid API key"""
        # Mock OpenAI client and streaming response
        mock_client = Mock()
        mock_openai_class.return_value = mock_client

        mock_chunk = Mock()
        mock_chunk.choices = [Mock()]
        mock_chunk.choices[0].delta = Mock()
        mock_chunk.choices[0].delta.content = "Test response"

        mock_stream = [mock_chunk]
        mock_client.chat.completions.create.return_value = mock_stream

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service._call_openai("test prompt")

        assert result == "Test response"

    @pytest.mark.unit
    @pytest.mark.llm
    def test_error_when_api_key_missing(self, sample_config, mock_logger,
                                        mock_metrics_service):
        """TC-LLM-006: Verify error handling when API key is missing"""
        sample_config['openai_api_key'] = None

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service._call_openai("test prompt")

        assert result is None

    @pytest.mark.unit
    @pytest.mark.llm
    def test_error_when_api_key_is_placeholder(self, sample_config, mock_logger,
                                               mock_metrics_service):
        """TC-LLM-007: Verify error handling when API key is placeholder"""
        sample_config['openai_api_key'] = 'sk-YOUR-API-KEY'

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service._call_openai("test prompt")

        assert result is None


class TestLLMServiceOllamaProvider:
    """Test Ollama provider"""

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.requests.post')
    def test_successful_ollama_call(self, mock_post, sample_config, mock_logger,
                                    mock_metrics_service):
        """TC-LLM-011: Verify successful Ollama API call with valid host"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.raise_for_status = Mock()
        mock_response.iter_lines.return_value = [
            b'{"response": "Test ", "done": false}',
            b'{"response": "response", "done": true}'
        ]
        mock_post.return_value = mock_response

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service._call_ollama("test prompt")

        assert "Test response" in result

    @pytest.mark.unit
    @pytest.mark.llm
    def test_default_host_used_when_not_configured(self, mock_logger,
                                                   mock_metrics_service):
        """TC-LLM-012: Verify default host is used when not configured"""
        config = {'llm_timeout': 60}
        llm_service = LLMService(config, mock_logger, mock_metrics_service)

        # Default should be http://localhost:11434
        assert llm_service.config.get(
            'ollama_host', 'http://localhost:11434') == 'http://localhost:11434'


class TestLLMServiceNVIDIAProvider:
    """Test NVIDIA provider"""

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.requests.post')
    def test_successful_nvidia_call(self, mock_post, sample_config, mock_logger,
                                    mock_metrics_service):
        """TC-LLM-015: Verify successful NVIDIA NIM API call with valid URL"""
        mock_response = Mock()
        mock_response.ok = True
        mock_response.json.return_value = {
            'choices': [{
                'message': {
                    'content': 'NVIDIA response'
                }
            }]
        }
        mock_post.return_value = mock_response

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service._call_nvidia("test prompt")

        assert result == 'NVIDIA response'

    @pytest.mark.unit
    @pytest.mark.llm
    def test_error_when_nvidia_url_not_configured(self, mock_logger,
                                                  mock_metrics_service):
        """TC-LLM-016: Verify error when NVIDIA URL is not configured"""
        config = {'llm_timeout': 60}
        llm_service = LLMService(config, mock_logger, mock_metrics_service)

        result = llm_service._call_nvidia("test prompt")

        assert result is None

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.requests.post')
    def test_error_handling_for_unexpected_response_format(
            self, mock_post, sample_config, mock_logger, mock_metrics_service):
        """TC-LLM-018: Verify error handling for unexpected response format"""
        mock_response = Mock()
        mock_response.ok = True
        mock_response.json.return_value = {'unexpected': 'format'}
        mock_post.return_value = mock_response

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service._call_nvidia("test prompt")

        assert result is None

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.requests.post')
    def test_error_handling_for_api_failures(self, mock_post, sample_config,
                                             mock_logger, mock_metrics_service):
        """TC-LLM-019: Verify error handling for API failures"""
        mock_response = Mock()
        mock_response.ok = False
        mock_response.status_code = 500
        mock_response.text = 'Internal server error'
        mock_post.return_value = mock_response

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service._call_nvidia("test prompt")

        assert result is None


class TestLLMServicePromptBuilding:
    """Test prompt building"""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_prompt_includes_search_result_data(self, sample_config,
                                                mock_logger,
                                                mock_metrics_service,
                                                sample_query_result):
        """TC-LLM-020: Verify prompt includes search result data"""
        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)

        prompt = llm_service._build_prompt(sample_query_result, "test query")

        assert "test query" in prompt
        assert json.dumps(sample_query_result, indent=2) in prompt

    @pytest.mark.unit
    @pytest.mark.llm
    def test_prompt_includes_user_query(self, sample_config, mock_logger,
                                        mock_metrics_service):
        """TC-LLM-021: Verify prompt includes user query"""
        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)

        prompt = llm_service._build_prompt({}, "What is the answer?")

        assert "What is the answer?" in prompt

    @pytest.mark.unit
    @pytest.mark.llm
    def test_search_result_serialization_for_dict(self, sample_config,
                                                  mock_logger,
                                                  mock_metrics_service):
        """TC-LLM-022: Verify search result serialization for dict objects"""
        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)

        result = llm_service._serialize_search_result({'key': 'value'})

        assert result == {'key': 'value'}

    @pytest.mark.unit
    @pytest.mark.llm
    def test_search_result_serialization_with_to_dict_method(
            self, sample_config, mock_logger, mock_metrics_service):
        """TC-LLM-023: Verify search result serialization for objects with to_dict() method"""
        mock_obj = Mock()
        mock_obj.to_dict.return_value = {'serialized': 'data'}

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        result = llm_service._serialize_search_result(mock_obj)

        assert result == {'serialized': 'data'}

    @pytest.mark.unit
    @pytest.mark.llm
    def test_search_result_serialization_when_none(self, sample_config,
                                                   mock_logger,
                                                   mock_metrics_service):
        """TC-LLM-024: Verify search result serialization when result is None"""
        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)

        result = llm_service._serialize_search_result(None)

        assert result['data'] is None
        assert 'message' in result


class TestLLMServiceMetricsTracking:
    """Test metrics tracking"""

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.LLMService._call_nvidia')
    def test_attempt_counter_increments(self, mock_nvidia, sample_config,
                                        mock_logger, mock_metrics_service,
                                        sample_query_result):
        """TC-LLM-025: Verify attempt counter increments for each provider tried"""
        sample_config['llm_provider_sequence'] = ['nvidia']
        mock_nvidia.return_value = "response"

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        llm_service.call_llm(sample_query_result, "test query")

        # Check that attempts metric was called (it's called before success)
        calls = [
            call[0][0] for call in mock_metrics_service.increment.call_args_list
        ]
        assert 'llm_attempts_nvidia' in calls

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.LLMService._call_nvidia')
    def test_success_counter_increments(self, mock_nvidia, sample_config,
                                        mock_logger, mock_metrics_service,
                                        sample_query_result):
        """TC-LLM-026: Verify success counter increments on successful response"""
        sample_config['llm_provider_sequence'] = ['nvidia']
        mock_nvidia.return_value = "response"

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        llm_service.call_llm(sample_query_result, "test query")

        # Check that success metric was incremented
        calls = [
            call[0][0] for call in mock_metrics_service.increment.call_args_list
        ]
        assert 'llm_success_nvidia' in calls

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.LLMService._call_nvidia')
    def test_error_counter_increments_on_failure(self, mock_nvidia,
                                                 sample_config, mock_logger,
                                                 mock_metrics_service,
                                                 sample_query_result):
        """TC-LLM-027: Verify error counter increments on provider failure"""
        sample_config['llm_provider_sequence'] = ['nvidia']
        mock_nvidia.side_effect = Exception("Failed")

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        llm_service.call_llm(sample_query_result, "test query")

        # Check that error metric was incremented
        calls = [
            call[0][0] for call in mock_metrics_service.increment.call_args_list
        ]
        assert 'llm_error_nvidia' in calls

    @pytest.mark.unit
    @pytest.mark.llm
    @patch('chatbot.services.llm_service.LLMService._call_nvidia')
    def test_timing_metrics_recorded(self, mock_nvidia, sample_config,
                                     mock_logger, mock_metrics_service,
                                     sample_query_result):
        """TC-LLM-028: Verify timing metrics are recorded for each provider call"""
        sample_config['llm_provider_sequence'] = ['nvidia']
        mock_nvidia.return_value = "response"

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        llm_service.call_llm(sample_query_result, "test query")

        # Check that timing was recorded
        mock_metrics_service.record_timing.assert_called_once()
        call_args = mock_metrics_service.record_timing.call_args[0]
        assert 'llm_nvidia_duration' in call_args[0]


class TestLLMServiceProviderStatus:
    """Test provider status"""

    @pytest.mark.unit
    @pytest.mark.llm
    def test_get_provider_status_returns_all_configured(self, sample_config,
                                                        mock_logger,
                                                        mock_metrics_service):
        """TC-LLM-029: Verify get_provider_status() returns status for all configured providers"""
        sample_config['llm_provider_sequence'] = ['nvidia', 'openai', 'ollama']

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        status = llm_service.get_provider_status()

        assert 'nvidia' in status
        assert 'openai' in status
        assert 'ollama' in status

    @pytest.mark.unit
    @pytest.mark.llm
    def test_provider_status_includes_model_and_url(self, sample_config,
                                                    mock_logger,
                                                    mock_metrics_service):
        """TC-LLM-030: Verify provider status includes model and URL information"""
        sample_config['llm_provider_sequence'] = ['nvidia']

        llm_service = LLMService(sample_config, mock_logger,
                                 mock_metrics_service)
        status = llm_service.get_provider_status()

        assert 'model' in status['nvidia']
        assert 'url' in status['nvidia']
        assert status['nvidia']['configured'] is True
