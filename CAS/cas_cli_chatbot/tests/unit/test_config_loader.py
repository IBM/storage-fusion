"""
Unit tests for ConfigLoader
"""
import pytest
import yaml
from unittest.mock import Mock, patch, mock_open
from pathlib import Path

from chatbot.utils.config_loader import ConfigLoader, ConfigurationError


class TestConfigLoaderInitialization:
    """Test config loader initialization"""

    @pytest.mark.unit
    @pytest.mark.config
    def test_config_loader_initializes(self, tmp_path):
        """TC-CFG-001: Verify config loader initializes with path"""
        config_path = tmp_path / "config.yaml"
        loader = ConfigLoader(config_path)

        assert loader.config_path == config_path


class TestConfigLoaderLoad:
    """Test loading configuration"""

    @pytest.mark.unit
    @pytest.mark.config
    def test_load_valid_config(self, tmp_path):
        """TC-CFG-002: Verify load returns valid config"""
        config_path = tmp_path / "config.yaml"
        config_data = {
            'console_url': 'https://console.example.com',
            'oc_username': 'admin',
            'oc_password': 'password123'
        }

        with open(config_path, 'w') as f:
            yaml.dump(config_data, f)

        loader = ConfigLoader(config_path)
        config = loader.load()

        assert config['console_url'] == 'https://console.example.com'
        assert config['oc_username'] == 'admin'

    @pytest.mark.unit
    @pytest.mark.config
    def test_load_nonexistent_file_raises_error(self, tmp_path):
        """TC-CFG-003: Verify load raises error for nonexistent file"""
        config_path = tmp_path / "nonexistent.yaml"
        loader = ConfigLoader(config_path)

        with pytest.raises(ConfigurationError) as exc_info:
            loader.load()

        assert "not found" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.config
    def test_load_empty_file_raises_error(self, tmp_path):
        """TC-CFG-004: Verify load raises error for empty file"""
        config_path = tmp_path / "config.yaml"
        config_path.write_text("")

        loader = ConfigLoader(config_path)

        with pytest.raises(ConfigurationError) as exc_info:
            loader.load()

        assert "empty" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.config
    def test_load_invalid_yaml_raises_error(self, tmp_path):
        """TC-CFG-005: Verify load raises error for invalid YAML"""
        config_path = tmp_path / "config.yaml"
        config_path.write_text("invalid: yaml: content:")

        loader = ConfigLoader(config_path)

        with pytest.raises(ConfigurationError) as exc_info:
            loader.load()

        assert "YAML" in str(exc_info.value)


class TestConfigLoaderValidation:
    """Test configuration validation"""

    @pytest.mark.unit
    @pytest.mark.config
    def test_validate_passes_for_valid_config(self, tmp_path):
        """TC-CFG-006: Verify validate passes for valid config"""
        config_path = tmp_path / "config.yaml"
        loader = ConfigLoader(config_path)

        config = {
            'console_url': 'https://console.example.com',
            'oc_username': 'admin',
            'oc_password': 'password123'
        }

        result = loader.validate(config)

        assert result is True

    @pytest.mark.unit
    @pytest.mark.config
    def test_validate_fails_for_missing_required_field(self, tmp_path):
        """TC-CFG-007: Verify validate fails for missing required field"""
        config_path = tmp_path / "config.yaml"
        loader = ConfigLoader(config_path)

        config = {
            'console_url': 'https://console.example.com',
            'oc_username': 'admin'
            # Missing oc_password
        }

        with pytest.raises(ConfigurationError) as exc_info:
            loader.validate(config)

        assert "oc_password" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.config
    def test_validate_fails_for_invalid_console_url(self, tmp_path):
        """TC-CFG-008: Verify validate fails for invalid console URL"""
        config_path = tmp_path / "config.yaml"
        loader = ConfigLoader(config_path)

        config = {
            'console_url': 'http://console.example.com',  # Should be https
            'oc_username': 'admin',
            'oc_password': 'password123'
        }

        with pytest.raises(ConfigurationError) as exc_info:
            loader.validate(config)

        assert "https" in str(exc_info.value)

    @pytest.mark.unit
    @pytest.mark.config
    def test_validate_fails_for_invalid_log_level(self, tmp_path):
        """TC-CFG-009: Verify validate fails for invalid log level"""
        config_path = tmp_path / "config.yaml"
        loader = ConfigLoader(config_path)

        config = {
            'console_url': 'https://console.example.com',
            'oc_username': 'admin',
            'oc_password': 'password123',
            'log_level': 'INVALID'
        }

        with pytest.raises(ConfigurationError) as exc_info:
            loader.validate(config)

        assert "log_level" in str(exc_info.value)


class TestConfigLoaderEnvironmentVariables:
    """Test environment variable substitution"""

    @pytest.mark.unit
    @pytest.mark.config
    @patch.dict('os.environ', {'TEST_PASSWORD': 'env_password'})
    def test_substitute_env_vars(self, tmp_path):
        """TC-CFG-010: Verify environment variable substitution"""
        config_path = tmp_path / "config.yaml"
        config_data = {
            'console_url': 'https://console.example.com',
            'oc_username': 'admin',
            'oc_password': '${TEST_PASSWORD}'
        }

        with open(config_path, 'w') as f:
            yaml.dump(config_data, f)

        loader = ConfigLoader(config_path)
        config = loader.load()

        assert config['oc_password'] == 'env_password'

    @pytest.mark.unit
    @pytest.mark.config
    @patch.dict('os.environ', {}, clear=True)
    def test_substitute_env_vars_with_default(self, tmp_path):
        """TC-CFG-011: Verify environment variable with default value"""
        config_path = tmp_path / "config.yaml"
        config_data = {
            'console_url': 'https://console.example.com',
            'oc_username': 'admin',
            'oc_password': '${MISSING_VAR:default_password}'
        }

        with open(config_path, 'w') as f:
            yaml.dump(config_data, f)

        loader = ConfigLoader(config_path)
        config = loader.load()

        assert config['oc_password'] == 'default_password'


class TestConfigLoaderDefaults:
    """Test default value application"""

    @pytest.mark.unit
    @pytest.mark.config
    def test_apply_defaults_for_missing_fields(self, tmp_path):
        """TC-CFG-012: Verify defaults are applied for missing optional fields"""
        config_path = tmp_path / "config.yaml"
        config_data = {
            'console_url': 'https://console.example.com',
            'oc_username': 'admin',
            'oc_password': 'password123'
        }

        with open(config_path, 'w') as f:
            yaml.dump(config_data, f)

        loader = ConfigLoader(config_path)
        config = loader.load()

        assert 'default_limit' in config
        assert config['default_limit'] == 5


class TestConfigLoaderSave:
    """Test saving configuration"""

    @pytest.mark.unit
    @pytest.mark.config
    def test_save_config_to_file(self, tmp_path):
        """TC-CFG-013: Verify save writes config to file"""
        config_path = tmp_path / "config.yaml"
        loader = ConfigLoader(config_path)

        config = {
            'console_url': 'https://console.example.com',
            'oc_username': 'admin',
            'oc_password': 'password123'
        }

        loader.save(config, backup=False)

        assert config_path.exists()
        with open(config_path) as f:
            saved_config = yaml.safe_load(f)
            assert saved_config['console_url'] == 'https://console.example.com'

    @pytest.mark.unit
    @pytest.mark.config
    def test_save_creates_backup(self, tmp_path):
        """TC-CFG-014: Verify save creates backup when requested"""
        config_path = tmp_path / "config.yaml"
        backup_path = tmp_path / "config.yaml.bak"

        # Create initial config
        config_data = {'key': 'old_value'}
        with open(config_path, 'w') as f:
            yaml.dump(config_data, f)

        loader = ConfigLoader(config_path)
        new_config = {'key': 'new_value'}

        loader.save(new_config, backup=True)

        assert backup_path.exists()


class TestConfigLoaderReload:
    """Test reloading configuration"""

    @pytest.mark.unit
    @pytest.mark.config
    def test_reload_returns_fresh_config(self, tmp_path):
        """TC-CFG-015: Verify reload returns fresh configuration"""
        config_path = tmp_path / "config.yaml"
        config_data = {
            'console_url': 'https://console.example.com',
            'oc_username': 'admin',
            'oc_password': 'password123'
        }

        with open(config_path, 'w') as f:
            yaml.dump(config_data, f)

        loader = ConfigLoader(config_path)
        config1 = loader.load()

        # Modify file
        config_data['oc_username'] = 'newadmin'
        with open(config_path, 'w') as f:
            yaml.dump(config_data, f)

        config2 = loader.reload()

        assert config2['oc_username'] == 'newadmin'


class TestConfigLoaderSampleConfig:
    """Test sample config creation"""

    @pytest.mark.unit
    @pytest.mark.config
    def test_create_sample_config(self, tmp_path):
        """TC-CFG-016: Verify create_sample_config creates valid sample"""
        output_path = tmp_path / "sample_config.yaml"

        ConfigLoader.create_sample_config(output_path)

        assert output_path.exists()
        with open(output_path) as f:
            sample = yaml.safe_load(f)
            assert 'console_url' in sample
            assert 'oc_username' in sample
            assert 'llm_provider_sequence' in sample
