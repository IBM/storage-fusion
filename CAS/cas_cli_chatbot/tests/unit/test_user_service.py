"""
Unit tests for UserService
"""
import pytest
import json
import subprocess
from unittest.mock import Mock, patch, MagicMock

from chatbot.services.user_service import UserService
from chatbot.utils.validators import ValidationError


class TestUserServiceInitialization:
    """Test user service initialization"""

    @pytest.mark.unit
    @pytest.mark.user
    def test_user_service_initializes_with_config(self, sample_config,
                                                  mock_auth_service,
                                                  mock_logger,
                                                  mock_cache_service):
        """TC-USER-001: Verify user service initializes with config"""
        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)

        assert user_service.config == sample_config
        assert user_service.auth_service == mock_auth_service
        assert user_service.logger == mock_logger
        assert user_service.cache_service == mock_cache_service


class TestUserServiceListOCPUsers:
    """Test listing OCP users"""

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_list_oc_users_returns_users(self, mock_run, sample_config,
                                         mock_auth_service, mock_logger,
                                         mock_cache_service):
        """TC-USER-002: Verify list_oc_users returns list of users"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({
            'items': [{
                'metadata': {
                    'name': 'user1'
                }
            }, {
                'metadata': {
                    'name': 'user2'
                }
            }, {
                'metadata': {
                    'name': 'user3'
                }
            }]
        }).encode()
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        users = user_service.list_oc_users(use_cache=False)

        assert len(users) == 3
        assert 'user1' in users
        assert 'user2' in users
        assert 'user3' in users

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_list_oc_users_returns_sorted_list(self, mock_run, sample_config,
                                               mock_auth_service, mock_logger,
                                               mock_cache_service):
        """TC-USER-003: Verify list_oc_users returns sorted list"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({
            'items': [{
                'metadata': {
                    'name': 'charlie'
                }
            }, {
                'metadata': {
                    'name': 'alice'
                }
            }, {
                'metadata': {
                    'name': 'bob'
                }
            }]
        }).encode()
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        users = user_service.list_oc_users(use_cache=False)

        assert users == ['alice', 'bob', 'charlie']

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_list_oc_users_caches_results(self, mock_run, sample_config,
                                          mock_auth_service, mock_logger,
                                          mock_cache_service):
        """TC-USER-004: Verify list_oc_users caches results"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({
            'items': [{
                'metadata': {
                    'name': 'user1'
                }
            }]
        }).encode()
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        user_service.list_oc_users(use_cache=False)

        mock_cache_service.set.assert_called_once()

    @pytest.mark.unit
    @pytest.mark.user
    def test_list_oc_users_uses_cached_results(self, sample_config,
                                               mock_auth_service, mock_logger,
                                               mock_cache_service):
        """TC-USER-005: Verify list_oc_users uses cached results when available"""
        mock_cache_service.get.return_value = ['cached_user1', 'cached_user2']

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        users = user_service.list_oc_users(use_cache=True)

        assert users == ['cached_user1', 'cached_user2']
        mock_cache_service.get.assert_called_once_with('users_ocp')

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_list_oc_users_handles_subprocess_error(self, mock_run,
                                                    sample_config,
                                                    mock_auth_service,
                                                    mock_logger,
                                                    mock_cache_service):
        """TC-USER-006: Verify list_oc_users handles subprocess errors"""
        mock_run.side_effect = subprocess.CalledProcessError(1,
                                                             'oc',
                                                             stderr=b'Error')

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        users = user_service.list_oc_users(use_cache=False)

        assert users == []

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_list_oc_users_handles_timeout(self, mock_run, sample_config,
                                           mock_auth_service, mock_logger,
                                           mock_cache_service):
        """TC-USER-007: Verify list_oc_users handles timeout"""
        mock_run.side_effect = subprocess.TimeoutExpired('oc', 30)

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        users = user_service.list_oc_users(use_cache=False)

        assert users == []

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_list_oc_users_handles_json_decode_error(self, mock_run,
                                                     sample_config,
                                                     mock_auth_service,
                                                     mock_logger,
                                                     mock_cache_service):
        """TC-USER-008: Verify list_oc_users handles JSON decode errors"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = b'invalid json'
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        users = user_service.list_oc_users(use_cache=False)

        assert users == []


class TestUserServiceGetUserDetails:
    """Test getting user details"""

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_get_user_details_returns_ocp_user(self, mock_run, sample_config,
                                               mock_auth_service, mock_logger,
                                               mock_cache_service):
        """TC-USER-009: Verify get_user_details returns OCP user details"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({
            'metadata': {
                'name': 'testuser',
                'uid': 'uid-123',
                'creationTimestamp': '2024-01-01T00:00:00Z'
            },
            'identities': ['identity1']
        }).encode()
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        details = user_service.get_user_details('testuser')

        assert details is not None
        assert details['source'] == 'ocp'
        assert details['username'] == 'testuser'
        assert details['uid'] == 'uid-123'

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_get_user_details_returns_none_for_nonexistent_user(
            self, mock_run, sample_config, mock_auth_service, mock_logger,
            mock_cache_service):
        """TC-USER-010: Verify get_user_details returns None for nonexistent user"""
        mock_result = Mock()
        mock_result.returncode = 1
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        details = user_service.get_user_details('nonexistent')

        assert details is None

    @pytest.mark.unit
    @pytest.mark.user
    def test_get_user_details_validates_username(self, sample_config,
                                                 mock_auth_service, mock_logger,
                                                 mock_cache_service):
        """TC-USER-011: Verify get_user_details validates username"""
        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)

        details = user_service.get_user_details('')

        assert details is None


class TestUserServiceSearchUsers:
    """Test searching users"""

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_search_users_returns_matching_users(self, mock_run, sample_config,
                                                 mock_auth_service, mock_logger,
                                                 mock_cache_service):
        """TC-USER-012: Verify search_users returns matching users"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({
            'items': [{
                'metadata': {
                    'name': 'admin'
                }
            }, {
                'metadata': {
                    'name': 'admin-user'
                }
            }, {
                'metadata': {
                    'name': 'testuser'
                }
            }]
        }).encode()
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        matches = user_service.search_users('admin', use_cache=False)

        assert len(matches) == 2
        assert 'admin' in matches
        assert 'admin-user' in matches

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_search_users_is_case_insensitive(self, mock_run, sample_config,
                                              mock_auth_service, mock_logger,
                                              mock_cache_service):
        """TC-USER-013: Verify search_users is case insensitive"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({
            'items': [{
                'metadata': {
                    'name': 'Admin'
                }
            }, {
                'metadata': {
                    'name': 'ADMIN-USER'
                }
            }]
        }).encode()
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        matches = user_service.search_users('admin', use_cache=False)

        assert len(matches) == 2

    @pytest.mark.unit
    @pytest.mark.user
    def test_search_users_validates_query(self, sample_config,
                                          mock_auth_service, mock_logger,
                                          mock_cache_service):
        """TC-USER-014: Verify search_users validates query"""
        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)

        matches = user_service.search_users('')

        assert matches == []


class TestUserServiceSyncUsers:
    """Test syncing users"""

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_sync_users_clears_cache(self, mock_run, sample_config,
                                     mock_auth_service, mock_logger,
                                     mock_cache_service):
        """TC-USER-015: Verify sync_users clears cache"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({'items': []}).encode()
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        user_service.sync_users()

        mock_cache_service.delete.assert_called_once_with('users_ocp')

    @pytest.mark.unit
    @pytest.mark.user
    @patch('chatbot.services.user_service.subprocess.run')
    def test_sync_users_returns_statistics(self, mock_run, sample_config,
                                           mock_auth_service, mock_logger,
                                           mock_cache_service):
        """TC-USER-016: Verify sync_users returns statistics"""
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({
            'items': [{
                'metadata': {
                    'name': 'user1'
                }
            }, {
                'metadata': {
                    'name': 'user2'
                }
            }]
        }).encode()
        mock_run.return_value = mock_result

        user_service = UserService(sample_config, mock_auth_service,
                                   mock_logger, mock_cache_service)
        stats = user_service.sync_users()

        assert stats['ocp_count'] == 2
        assert stats['total_unique'] == 2
