"""
Unit tests for VectorStoreService
"""
import json
from unittest.mock import Mock, patch

import pytest

from chatbot.services.vector_store_service import VectorStoreService


class TestVectorStoreServiceAssignments:

    @pytest.mark.unit
    @patch('chatbot.services.vector_store_service.subprocess.run')
    def test_get_assigned_users_returns_validated_users(
            self, mock_run, sample_config, mock_auth_service, mock_logger,
            mock_cache_service, mock_console):
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({
            'items': [{
                'spec': {
                    'resourceRef': {
                        'name': 'test-vs'
                    },
                    'subjects': {
                        'users': [{
                            'name': 'user1'
                        }, {
                            'name': 'user2'
                        }]
                    }
                },
                'status': {
                    'conditions': [{
                        'type': 'ValidatedUsers',
                        'status': 'True'
                    }]
                }
            }]
        }).encode()
        mock_run.return_value = mock_result

        service = VectorStoreService(sample_config, mock_auth_service,
                                     mock_logger, mock_cache_service,
                                     mock_console)

        users = service.get_assigned_users('test-vs', use_cache=False)

        assert users == ['user1', 'user2']
        assert service.vector_store_assignments['test-vs']['ocp_users'] == [
            'user1', 'user2'
        ]
        mock_cache_service.delete.assert_called_once_with(
            'domain_users_test-vs')
        mock_cache_service.set.assert_called_once_with(
            'domain_users_test-vs', ['user1', 'user2'], ttl_seconds=300)

    @pytest.mark.unit
    @patch('chatbot.services.vector_store_service.subprocess.run')
    def test_get_assigned_groups_returns_validated_groups(
            self, mock_run, sample_config, mock_auth_service, mock_logger,
            mock_cache_service, mock_console):
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = json.dumps({
            'items': [{
                'spec': {
                    'resourceRef': {
                        'name': 'test-vs'
                    },
                    'subjects': {
                        'groups': [{
                            'name': 'group1'
                        }, {
                            'name': 'group2'
                        }]
                    }
                },
                'status': {
                    'conditions': [{
                        'type': 'ValidatedGroups',
                        'status': 'True'
                    }]
                }
            }]
        }).encode()
        mock_run.return_value = mock_result

        service = VectorStoreService(sample_config, mock_auth_service,
                                     mock_logger, mock_cache_service,
                                     mock_console)

        groups = service.get_assigned_groups('test-vs', use_cache=False)

        assert groups == ['group1', 'group2']
        assert service.vector_store_assignments['test-vs']['groups'] == [
            'group1', 'group2'
        ]
        mock_cache_service.delete.assert_called_once_with(
            'domain_groups_test-vs')
        mock_cache_service.set.assert_called_once_with(
            'domain_groups_test-vs', ['group1', 'group2'], ttl_seconds=300)

    def test_get_assigned_users_uses_users_cache_key(
            self, sample_config, mock_auth_service, mock_logger,
            mock_cache_service, mock_console):
        mock_cache_service.get.return_value = ['cached-user']

        service = VectorStoreService(sample_config, mock_auth_service,
                                     mock_logger, mock_cache_service,
                                     mock_console)

        users = service.get_assigned_users('test-vs')

        assert users == ['cached-user']
        mock_cache_service.get.assert_called_once_with('domain_users_test-vs')

    def test_get_assigned_groups_uses_groups_cache_key(
            self, sample_config, mock_auth_service, mock_logger,
            mock_cache_service, mock_console):
        mock_cache_service.get.return_value = ['cached-group']

        service = VectorStoreService(sample_config, mock_auth_service,
                                     mock_logger, mock_cache_service,
                                     mock_console)

        groups = service.get_assigned_groups('test-vs')

        assert groups == ['cached-group']
        mock_cache_service.get.assert_called_once_with('domain_groups_test-vs')