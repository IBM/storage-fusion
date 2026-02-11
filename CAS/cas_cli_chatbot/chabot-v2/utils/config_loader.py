"""
Enhanced Configuration Loader with validation and environment variable support
"""

import os
import yaml
import logging
from pathlib import Path
from typing import Dict, Any, List, Optional


class ConfigurationError(Exception):
    """Configuration related errors"""
    pass


class ConfigLoader:
    """
    Advanced configuration loader with validation and environment variable support
    """

    REQUIRED_FIELDS = [
        'console_url',
        'oc_username',
        'oc_password'
    ]

    OPTIONAL_FIELDS = {
        'cas_url': 'https://default-cas-url.com',
        'default_table': 'gt20',
        'default_limit': 5,
        'log_level': 'INFO',
        'log_file': 'cas_chatbot.log',
        'allow_self_signed': True
    }

    def __init__(self, config_path: Path):
        self.config_path = Path(config_path)
        self.logger = logging.getLogger(__name__)

    def load(self) -> Dict[str, Any]:
        """
        Load configuration from YAML file with environment variable substitution

        Returns:
            Configuration dictionary

        Raises:
            ConfigurationError: If configuration is invalid
        """
        if not self.config_path.exists():
            raise ConfigurationError(f"Configuration file not found: {self.config_path}")

        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)

            if not config:
                raise ConfigurationError("Configuration file is empty")

            # Substitute environment variables
            config = self._substitute_env_vars(config)

            # Apply defaults
            config = self._apply_defaults(config)

            return config

        except yaml.YAMLError as e:
            raise ConfigurationError(f"Invalid YAML syntax: {e}")
        except Exception as e:
            raise ConfigurationError(f"Failed to load configuration: {e}")

    def validate(self, config: Dict[str, Any]) -> bool:
        """
        Validate configuration

        Args:
            config: Configuration dictionary

        Returns:
            True if valid

        Raises:
            ConfigurationError: If validation fails
        """
        errors = []

        # Check required fields
        for field in self.REQUIRED_FIELDS:
            if field not in config or not config[field]:
                errors.append(f"Missing required field: {field}")

        # Validate URLs
        if 'console_url' in config:
            if not config['console_url'].startswith('https://'):
                errors.append("console_url must start with https://")

        # Validate numeric fields
        numeric_fields = ['default_limit']
        for field in numeric_fields:
            if field in config:
                if not isinstance(config[field], int) or config[field] <= 0:
                    errors.append(f"{field} must be a positive integer")

        # Validate log level
        valid_log_levels = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']
        if 'log_level' in config:
            if config['log_level'].upper() not in valid_log_levels:
                errors.append(f"log_level must be one of: {', '.join(valid_log_levels)}")

        # Validate LLM provider sequence
        if 'llm_provider_sequence' in config:
            if not isinstance(config['llm_provider_sequence'], list):
                errors.append("llm_provider_sequence must be a list")
            elif not config['llm_provider_sequence']:
                errors.append("llm_provider_sequence cannot be empty")

        if errors:
            error_msg = "Configuration validation failed:\n" + "\n".join(f"  - {e}" for e in errors)
            raise ConfigurationError(error_msg)

        return True

    def _substitute_env_vars(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """
        Substitute environment variables in configuration
        Format: ${VAR_NAME} or ${VAR_NAME:default_value}
        """

        def substitute(value):
            if isinstance(value, str):
                # Handle ${VAR_NAME:default} format
                if value.startswith('${') and value.endswith('}'):
                    var_expr = value[2:-1]

                    if ':' in var_expr:
                        var_name, default = var_expr.split(':', 1)
                        return os.getenv(var_name.strip(), default)
                    else:
                        var_name = var_expr.strip()
                        env_value = os.getenv(var_name)
                        if env_value is None:
                            self.logger.warning(f"Environment variable {var_name} not set")
                            return value
                        return env_value

            elif isinstance(value, dict):
                return {k: substitute(v) for k, v in value.items()}

            elif isinstance(value, list):
                return [substitute(item) for item in value]

            return value

        return substitute(config)

    def _apply_defaults(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Apply default values for optional fields"""
        for field, default_value in self.OPTIONAL_FIELDS.items():
            if field not in config:
                config[field] = default_value
                self.logger.debug(f"Applied default for {field}: {default_value}")

        return config

    def reload(self) -> Dict[str, Any]:
        """Reload configuration from file"""
        self.logger.info("Reloading configuration...")
        return self.load()

    def save(self, config: Dict[str, Any], backup: bool = True):
        """
        Save configuration to file

        Args:
            config: Configuration to save
            backup: Create backup before saving
        """
        if backup and self.config_path.exists():
            backup_path = self.config_path.with_suffix('.yaml.bak')
            import shutil
            shutil.copy2(self.config_path, backup_path)
            self.logger.info(f"Created backup: {backup_path}")

        with open(self.config_path, 'w') as f:
            yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False)

        self.logger.info(f"Configuration saved to {self.config_path}")

    @staticmethod
    def create_sample_config(output_path: Path):
        """Create a sample configuration file"""
        sample_config = {
            'console_url': 'https://console-openshift-console.apps.example.com',
            'oc_username': 'admin',
            'oc_password': '${OC_PASSWORD:changeme}',
            'cas_url': 'https://cas-api.example.com',
            'default_table': 'gt20',
            'default_limit': 5,
            'llm_provider_sequence': ['nvidia', 'openai', 'ollama'],
            'nvidia_llm_url': 'http://nvidia-llm.example.com',
            'nvidia_model': 'meta/llama3-8b-instruct',
            'openai_api_key': '${OPENAI_API_KEY}',
            'keycloak_url': 'http://keycloak.example.com/realms/master/protocol/openid-connect/token',
            'client_id': 'myapp',
            'client_secret': '${KEYCLOAK_CLIENT_SECRET}',
            'keycloak_users_url': 'http://keycloak.example.com/admin/realms/master/users',
            'logging': {
                'level': 'INFO',
                'file': 'cas_chatbot.log',
                'max_bytes': 10485760,
                'backup_count': 5
            },
            'cache': {
                'default_ttl': 300,
                'max_entries': 1000
            },
            'session': {
                'file': 'session_history.json',
                'auto_save': True
            },
            'metrics': {
                'max_samples': 100
            },
            'allow_self_signed': True
        }

        with open(output_path, 'w') as f:
            yaml.safe_dump(sample_config, f, default_flow_style=False, sort_keys=False)

        print(f"Sample configuration created: {output_path}")