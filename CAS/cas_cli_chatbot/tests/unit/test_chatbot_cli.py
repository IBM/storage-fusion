"""
Unit tests for ChatbotCLI
"""
import pytest
from unittest.mock import Mock, patch
from prompt_toolkit.validation import ValidationError

from chatbot.cli.chatbot_cli import ChatbotCLI, CommandValidator


@pytest.fixture
def mock_services(mock_auth_service, mock_cache_service, mock_metrics_service):
    """Mock services for CLI testing"""
    return {
        'auth': mock_auth_service,
        'cache': mock_cache_service,
        'metrics': mock_metrics_service,
        'user': Mock(),
        'vector store': Mock(),
        'query': Mock(),
        'llm': Mock()
    }


@pytest.fixture
def mock_error_handler(mock_logger, mock_console):
    """Mock error handler"""
    handler = Mock()
    handler.handle_error = Mock()
    return handler


@pytest.fixture
def mock_session_manager():
    """Mock session manager"""
    manager = Mock()
    manager.get_session_info = Mock(return_value={
        'start_time': '2024-01-01T00:00:00',
        'queries': 5,
        'commands': 10
    })
    manager.get_statistics = Mock(return_value={
        'total_queries': 5,
        'total_commands': 10,
        'session_duration': 3600
    })
    manager.export_session = Mock(return_value=True)
    manager.clear_history = Mock()
    return manager


@pytest.fixture
def chatbot_cli(mock_services, sample_config, mock_logger, mock_console,
                mock_error_handler, mock_session_manager, sample_vector_stores):
    """Create ChatbotCLI instance for testing"""
    with patch('chatbot.cli.chatbot_cli.Console', return_value=mock_console):
        cli = ChatbotCLI(services=mock_services,
                         config=sample_config,
                         logger=mock_logger,
                         console=mock_console,
                         error_handler=mock_error_handler,
                         session_manager=mock_session_manager)
        cli.console = mock_console
        cli._accessible_vector_stores = Mock(return_value=sample_vector_stores)
        return cli


class TestCommandValidator:
    """Test command validation"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_valid_command_passes_validation(self):
        """TC-CLI-001: Verify valid commands are accepted"""
        validator = CommandValidator(['help', 'exit', 'vector stores list'])

        doc = Mock()
        doc.text = 'help'

        validator.validate(doc)

    @pytest.mark.unit
    @pytest.mark.cli
    def test_invalid_command_raises_validation_error(self):
        """TC-CLI-002: Verify invalid commands show error message"""
        validator = CommandValidator(['help', 'exit'])

        doc = Mock()
        doc.text = 'invalid_command'

        with pytest.raises(ValidationError) as exc_info:
            validator.validate(doc)

        assert 'Invalid command' in str(exc_info.value.message)


class TestChatbotCLIInitialization:
    """Test CLI initialization"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_cli_initializes_with_services(self, chatbot_cli, mock_services):
        """Test CLI initializes with all services"""
        assert chatbot_cli.services == mock_services
        assert chatbot_cli.running is True

    @pytest.mark.unit
    @pytest.mark.cli
    def test_cli_initializes_with_config(self, chatbot_cli, sample_config):
        """Test CLI initializes with configuration"""
        assert chatbot_cli.config == sample_config
        assert chatbot_cli.current_user == sample_config['oc_username']

    @pytest.mark.unit
    @pytest.mark.cli
    def test_cli_sets_initial_state(self, chatbot_cli):
        """Test CLI sets initial state correctly"""
        assert chatbot_cli.current_user is not None
        assert chatbot_cli.user_type == 'ocp'
        assert chatbot_cli.current_vector_store is None
        assert chatbot_cli.running is True


class TestVectorStoreCommands:
    """Test vector store related commands"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_vector_stores_list_displays_stores(self, chatbot_cli,
                                                sample_vector_stores):
        """TC-CLI-005: Verify vector_stores list displays all vector stores"""
        chatbot_cli.services[
            'vector store'].list_vector_stores.return_value = sample_vector_stores

        chatbot_cli.cmd_vector_stores_list()

        chatbot_cli.services[
            'vector store'].list_vector_stores.assert_called_once()
        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_vector_stores_select_allows_selection(self, chatbot_cli,
                                                   sample_vector_stores):
        """TC-CLI-006: Verify vector_stores select allows interactive selection"""
        chatbot_cli.services[
            'vector store'].list_vector_stores.return_value = sample_vector_stores
        chatbot_cli.session.prompt = Mock(return_value='vector-store-1')

        chatbot_cli.cmd_vector_stores_select()

        assert chatbot_cli.current_vector_store == 'vector-store-1'
        chatbot_cli.session.prompt.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_vector_stores_info_displays_details(self, chatbot_cli):
        """TC-CLI-007: Verify vector_stores info displays detailed information"""
        chatbot_cli.current_vector_store = 'test-vs'
        chatbot_cli.services[
            'vector store'].get_vector_store_details.return_value = {
                'name': 'test-vs',
                'created': '2024-01-01',
                'assigned_users': {
                    'ocp': ['user1'],
                    'keycloak': [],
                    'total': 1
                }
            }

        chatbot_cli.cmd_vector_stores_info()

        chatbot_cli.services[
            'vector store'].get_vector_store_details.assert_called_once_with(
                'test-vs', 'ibm-cas')
        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_vector_store_selection_updates_prompt(self, chatbot_cli):
        """TC-CLI-008: Verify vector store selection updates prompt"""
        chatbot_cli.current_vector_store = 'production-vs'

        prompt = chatbot_cli._build_prompt()

        assert 'production-vs' in prompt


class TestQueryCommands:
    """Test query related commands"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_query_ask_prompts_for_input(self, chatbot_cli):
        """TC-CLI-010: Verify query ask prompts for user input"""
        chatbot_cli.session.prompt = Mock(return_value='What is the answer?')
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli.services['query'].query_vector_store.return_value = {
            'success': True,
            'data': [{
                'text': 'Answer'
            }]
        }
        chatbot_cli.services['llm'].call_llm.return_value = 'LLM response'
        chatbot_cli._has_valid_llm_config = Mock(return_value=True)

        chatbot_cli.cmd_query_ask()

        chatbot_cli.session.prompt.assert_called()
        chatbot_cli.services['query'].query_vector_store.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_query_history_shows_previous_queries(self, chatbot_cli):
        """TC-CLI-013: Verify query history shows previous queries"""
        queries_list = [{
            'query': 'test query 1',
            'timestamp': '2024-01-01',
            'user': 'test-user',
            'vector store': 'test-vs'
        }, {
            'query': 'test query 2',
            'timestamp': '2024-01-02',
            'user': 'test-user',
            'vector store': 'test-vs'
        }]
        chatbot_cli.session_manager.get_history.return_value = {
            'queries': queries_list
        }

        chatbot_cli.cmd_query_history()

        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_query_requires_vector_store_selection(self, chatbot_cli):
        """TC-CLI-014: Verify query requires valid vector store selection"""
        chatbot_cli.current_vector_store = None

        chatbot_cli.cmd_query_ask()

        assert any('vector store' in str(call).lower()
                   for call in chatbot_cli.console.print.call_args_list)


class TestCASAPICommands:
    """Test CAS API commands"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_casapi_vector_search_retrieves_chunks(self, chatbot_cli):
        """TC-CLI-015: Verify casapi vector_search retrieves text chunks"""
        chatbot_cli.session.prompt = Mock(side_effect=['test query', '5'])
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli.services['query'].query_vector_store.return_value = {
            'success':
                True,
            'data': [{
                'text': 'chunk 1',
                'metadata': {
                    'filename': 'file1.pdf',
                    'file_id': '123'
                }
            }, {
                'text': 'chunk 2',
                'metadata': {
                    'filename': 'file2.pdf',
                    'file_id': '456'
                }
            }]
        }

        chatbot_cli.cmd_vector_search()

        chatbot_cli.services['query'].query_vector_store.assert_called_once()
        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_casapi_vector_search_filter_applies_filters(self, chatbot_cli):
        """TC-CLI-016: Verify casapi vector_search filter applies filters correctly"""
        chatbot_cli._get_input = Mock(side_effect=['test query', '5'])
        chatbot_cli.session.prompt = Mock(
            side_effect=['filename', 'eq', 'test.pdf'])
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli.services['query'].query_with_filters.return_value = {
            'success': True,
            'data': []
        }

        chatbot_cli.cmd_vector_search_filter()

        chatbot_cli.services['query'].query_with_filters.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_casapi_show_file_content_displays_content(self, chatbot_cli):
        """TC-CLI-017: Verify casapi show_file_content displays file content"""
        chatbot_cli.session.prompt = Mock(side_effect=['vs-123', 'file-456'])
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.current_user = 'test-user'
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli.services['query'].get_file_content.return_value = {
            'success': True,
            'data': {
                'text': 'File content here'
            }
        }

        chatbot_cli.cmd_casapi_show_file_content()

        chatbot_cli.services['query'].get_file_content.assert_called_once()
        call_kwargs = chatbot_cli.services[
            'query'].get_file_content.call_args.kwargs
        assert call_kwargs['vector_store_id'] == 'vs-123'
        assert call_kwargs['file_id'] == 'file-456'

    @pytest.mark.unit
    @pytest.mark.cli
    def test_casapi_query_file_queries_specific_file(self, chatbot_cli):
        """TC-CLI-018: Verify casapi query file queries specific file"""
        chatbot_cli.session.prompt = Mock(
            side_effect=['vs-123', 'file-456', 'What is this about?'])
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli.services['query'].get_file_content.return_value = {
            'success': True,
            'data': {
                'text': 'File content'
            }
        }
        chatbot_cli.services['llm'].call_llm.return_value = 'LLM response'
        chatbot_cli._has_valid_llm_config = Mock(return_value=True)

        chatbot_cli.cmd_casapi_query_file()

        chatbot_cli.services['query'].get_file_content.assert_called_once()
        chatbot_cli.services['llm'].call_llm.assert_called_once()


class TestSessionCommands:
    """Test session management commands"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_session_view_displays_current_status(self, chatbot_cli):
        """TC-CLI-020: Verify session view displays current session status"""
        chatbot_cli.session_manager.get_history.return_value = {
            'queries': [],
            'commands': []
        }

        chatbot_cli.display_status()

        chatbot_cli.session_manager.get_history.assert_called()
        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_session_history_shows_history(self, chatbot_cli):
        """TC-CLI-021: Verify session history shows session history"""
        history_data = {
            'queries': [{
                'query': 'test query 1',
                'timestamp': '2024-01-01'
            }, {
                'query': 'test query 2',
                'timestamp': '2024-01-02'
            }]
        }
        chatbot_cli.session_manager.get_history.return_value = history_data

        chatbot_cli.cmd_query_history()

        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_session_stats_displays_statistics(self, chatbot_cli):
        """TC-CLI-022: Verify session stats displays statistics"""
        chatbot_cli.session_manager.get_history.return_value = {
            'queries': [],
            'file_lookups': []
        }

        chatbot_cli.cmd_session_info()

        chatbot_cli.session_manager.get_statistics.assert_called_once()
        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_session_export_saves_to_file(self, chatbot_cli):
        """TC-CLI-023: Verify session export saves session to file"""
        chatbot_cli.session.prompt = Mock(return_value='session_export.json')
        chatbot_cli.session_manager.export = Mock()

        chatbot_cli.cmd_session_export()

        chatbot_cli.session_manager.export.assert_called_once_with(
            'session_export.json')

    @pytest.mark.unit
    @pytest.mark.cli
    def test_session_clear_clears_history(self, chatbot_cli):
        """TC-CLI-024: Verify session clear clears session history"""
        with patch('chatbot.cli.command_handlers.confirm', return_value=True):
            chatbot_cli.session_manager.clear = Mock()

            chatbot_cli.cmd_session_clear()

            chatbot_cli.session_manager.clear.assert_called_once()


class TestSystemCommands:
    """Test system commands"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_config_show_displays_sanitized_config(self, chatbot_cli):
        """TC-CLI-025: Verify config show displays sanitized configuration"""
        chatbot_cli.cmd_config_show()

        chatbot_cli.console.print.assert_called()
        printed_text = str(chatbot_cli.console.print.call_args_list)
        assert 'password' not in printed_text.lower() or '***' in printed_text

    @pytest.mark.unit
    @pytest.mark.cli
    def test_sensitive_fields_masked_in_config(self, chatbot_cli):
        """TC-CLI-026: Verify sensitive fields are masked in config display"""
        sanitized = chatbot_cli._sanitize_config(chatbot_cli.config)

        if 'oc_password' in sanitized:
            assert sanitized['oc_password'] == '***REDACTED***'
        if 'openai_api_key' in sanitized:
            assert sanitized['openai_api_key'] == '***REDACTED***'

    @pytest.mark.unit
    @pytest.mark.cli
    def test_metrics_displays_application_metrics(self, chatbot_cli):
        """TC-CLI-027: Verify metrics displays application metrics"""
        real_metrics = {
            'total_requests': 100,
            'total_errors': 5,
            'uptime': 3600
        }
        mock_get_metrics = Mock(return_value=real_metrics)
        chatbot_cli.services['metrics'].get_all_metrics = mock_get_metrics

        chatbot_cli.cmd_metrics()

        mock_get_metrics.assert_called_once()
        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_health_runs_health_checks(self, chatbot_cli,
                                       sample_health_check_results):
        """TC-CLI-028: Verify health runs health checks"""
        with patch('chatbot.utils.health_check.HealthChecker'
                  ) as mock_health_checker:
            mock_checker_instance = Mock()
            mock_checker_instance.run_all_checks.return_value = sample_health_check_results
            mock_health_checker.return_value = mock_checker_instance

            chatbot_cli.cmd_health()

            mock_checker_instance.run_all_checks.assert_called_once()
            chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_clear_clears_terminal_screen(self, chatbot_cli):
        """TC-CLI-029: Verify clear clears terminal screen"""
        chatbot_cli.cmd_clear()

        chatbot_cli.console.clear.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_help_shows_available_commands(self, chatbot_cli):
        """TC-CLI-004: Verify help command displays all available commands"""
        chatbot_cli.display_help()

        chatbot_cli.console.print.assert_called()
        assert chatbot_cli.console.print.call_count > 0


class TestPromptBuilding:
    """Test prompt building"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_prompt_includes_current_user(self, chatbot_cli):
        """TC-CLI-031: Verify prompt includes current user when selected"""
        chatbot_cli.current_user = 'test-user'

        prompt = chatbot_cli._build_prompt()

        assert 'test-user' in prompt

    @pytest.mark.unit
    @pytest.mark.cli
    def test_prompt_includes_vector_store(self, chatbot_cli):
        """TC-CLI-032: Verify prompt includes vector store when selected"""
        chatbot_cli.current_user = 'test-user'
        chatbot_cli.current_vector_store = 'production-vs'

        prompt = chatbot_cli._build_prompt()

        assert 'production-vs' in prompt

    @pytest.mark.unit
    @pytest.mark.cli
    def test_prompt_format_is_correct(self, chatbot_cli):
        """TC-CLI-033: Verify prompt format is correct"""
        chatbot_cli.current_user = 'admin'
        chatbot_cli.current_vector_store = 'test-vs'

        prompt = chatbot_cli._build_prompt()

        assert 'admin' in prompt
        assert 'test-vs' in prompt
        assert '>' in prompt


class TestTokenValidation:
    """Test token validation"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_commands_check_token_validity(self, chatbot_cli):
        """TC-CLI-034: Verify commands requiring token check token validity"""
        chatbot_cli.services['auth'].has_valid_token.return_value = False

        result = chatbot_cli._check_token()

        assert result is False
        chatbot_cli.services['auth'].has_valid_token.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_error_message_when_token_invalid(self, chatbot_cli):
        """TC-CLI-035: Verify error message when token is invalid"""
        chatbot_cli.services['auth'].has_valid_token.return_value = False

        result = chatbot_cli._check_token()

        assert result is False
        chatbot_cli.console.print.assert_called()
        assert chatbot_cli.console.print.call_count > 0

    @pytest.mark.unit
    @pytest.mark.cli
    def test_user_prompted_to_authenticate_when_token_missing(
            self, chatbot_cli):
        """TC-CLI-036: Verify user is prompted to authenticate when token missing"""
        chatbot_cli.services['auth'].token = None
        chatbot_cli.services['auth'].has_valid_token.return_value = False

        result = chatbot_cli._check_token()

        assert result is False
        chatbot_cli.console.print.assert_called()


class TestCommandExecution:
    """Test command execution"""

    @pytest.mark.unit
    @pytest.mark.cli
    def test_execute_command_routes_to_correct_handler(self, chatbot_cli):
        """Test command execution routes to correct handler"""
        with patch.object(chatbot_cli,
                          'cmd_vector_stores_list') as mock_handler:
            chatbot_cli.execute_command('vector stores list')
            mock_handler.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_execute_command_handles_unknown_commands(self, chatbot_cli):
        """Test execution handles unknown commands gracefully"""
        chatbot_cli.execute_command('unknown_command')

        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_exit_command_stops_cli_loop(self, chatbot_cli):
        """Test exit command stops CLI loop"""
        chatbot_cli.execute_command('exit')

        assert chatbot_cli.running is False

    @pytest.mark.unit
    @pytest.mark.cli
    def test_quit_command_stops_cli_loop(self, chatbot_cli):
        """Test quit command stops CLI loop"""
        chatbot_cli.execute_command('quit')

    @pytest.mark.unit
    @pytest.mark.cli
    def test_help_with_specific_command(self, chatbot_cli):
        """TC-CLI-041: Verify help shows specific command details"""
        chatbot_cli.display_help('help')
        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_empty_query_rejected(self, chatbot_cli):
        """TC-CLI-042: Verify empty query is rejected"""
        chatbot_cli._get_query_input = Mock(return_value=None)
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli._has_valid_llm_config = Mock(return_value=True)

        chatbot_cli.cmd_query_ask()

        chatbot_cli._get_query_input.assert_called_once()
        chatbot_cli.services['query'].query_vector_store.assert_not_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_query_without_vector_store_fails(self, chatbot_cli):
        """TC-CLI-043: Verify query fails without vector store selection"""
        chatbot_cli.current_vector_store = None
        chatbot_cli.current_user = 'test-user'

        chatbot_cli.cmd_query_ask()

        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_query_with_invalid_token_fails(self, chatbot_cli):
        """TC-CLI-044: Verify query fails with invalid token"""
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services['auth'].has_valid_token.return_value = False

        chatbot_cli.cmd_query_ask()

        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_vector_store_list_when_empty(self, chatbot_cli):
        """TC-CLI-045: Verify vector store list handles empty list"""
        chatbot_cli.services[
            'vector store'].list_vector_stores.return_value = []
        chatbot_cli._accessible_vector_stores = lambda: []

        chatbot_cli.cmd_vector_stores_list()

        chatbot_cli.console.print.assert_called()
        printed_text = str(chatbot_cli.console.print.call_args_list)
        assert 'no' in printed_text.lower() or 'yellow' in printed_text.lower()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_query_with_failed_retrieval(self, chatbot_cli):
        """TC-CLI-046: Verify query handles failed retrieval"""
        chatbot_cli.session.prompt = Mock(return_value='test query')
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli._has_valid_llm_config = Mock(return_value=True)

        chatbot_cli.services['query'].query_vector_store.return_value = {
            'success': False,
            'error': 'Connection failed'
        }

        chatbot_cli.cmd_query_ask()

        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_session_export_with_error(self, chatbot_cli):
        """TC-CLI-047: Verify session export handles errors"""
        chatbot_cli.session.prompt = Mock(return_value='test.json')
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli.session_manager.export = Mock(
            side_effect=Exception('Write failed'))

        chatbot_cli.cmd_session_export()

        assert any('failed' in str(call).lower()
                   for call in chatbot_cli.console.print.call_args_list)

    @pytest.mark.unit
    @pytest.mark.cli
    def test_user_not_in_vector_store(self, chatbot_cli):
        """TC-CLI-048: Verify error when user not in vector store"""
        chatbot_cli.current_vector_store = 'unauthorized-vs'
        chatbot_cli.current_user = 'test-user'
        chatbot_cli._accessible_vector_stores = Mock(
            return_value=['vector-store-1', 'vector-store-2'])

        result = chatbot_cli._user_in_vector_store('unauthorized-vs')

        assert result is False

    @pytest.mark.unit
    @pytest.mark.cli
    def test_vector_store_info_displays_details(self, chatbot_cli):
        """TC-CLI-049: Verify vector store info displays details"""
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services[
            'vector store'].get_vector_store_details.return_value = {
                'name': 'vector-store-1',
                'namespace': 'test-namespace',
                'created': '2024-01-01',
                'assigned_users': {
                    'ocp': ['user1', 'user2'],
                    'total': 2
                }
            }

        chatbot_cli.cmd_vector_stores_info()

        chatbot_cli.services[
            'vector store'].get_vector_store_details.assert_called_once_with(
                'vector-store-1', 'ibm-cas')
        chatbot_cli.console.print.assert_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_query_history_when_empty(self, chatbot_cli):
        """TC-CLI-050: Verify query history handles empty history"""
        chatbot_cli.session_manager.get_history.return_value = {'queries': []}

        chatbot_cli.cmd_query_history()

        chatbot_cli.console.print.assert_called()
        printed_text = str(chatbot_cli.console.print.call_args_list)
        assert 'no queries' in printed_text.lower(
        ) or 'yellow' in printed_text.lower()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_query_ask_requires_llm_configuration(self, chatbot_cli):
        """Verify llm query ask instructs user to configure LLM when missing."""
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli._has_valid_llm_config = Mock(return_value=False)
        chatbot_cli._ensure_llm_configured = Mock(return_value=False)

        chatbot_cli.cmd_query_ask()

        chatbot_cli._ensure_llm_configured.assert_called_once()
        chatbot_cli.services['query'].query_vector_store.assert_not_called()

    @pytest.mark.unit
    @pytest.mark.cli
    def test_query_file_requires_llm_configuration(self, chatbot_cli):
        """Verify llm query file instructs user to configure LLM when missing."""
        chatbot_cli.current_vector_store = 'vector-store-1'
        chatbot_cli.services['auth'].has_valid_token.return_value = True
        chatbot_cli._has_valid_llm_config = Mock(return_value=False)

        chatbot_cli.cmd_casapi_query_file()

        chatbot_cli.services['query'].get_file_content.assert_not_called()
        chatbot_cli.services['llm'].call_llm.assert_not_called()
        assert any('llm setup' in str(call).lower()
                   for call in chatbot_cli.console.print.call_args_list)

    @pytest.mark.unit
    @pytest.mark.cli
    def test_llm_setup_command_invokes_prompt(self, chatbot_cli):
        """Verify llm setup command runs the interactive setup flow."""
        chatbot_cli._prompt_llm_setup = Mock()

        chatbot_cli.execute_command('llm setup')

        chatbot_cli._prompt_llm_setup.assert_called_once()
