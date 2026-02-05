"""
Enhanced Authentication Service with token caching and retry logic
"""

import subprocess
import requests
import logging
from urllib.parse import urlparse
from typing import Optional
from datetime import datetime, timedelta


class AuthenticationError(Exception):
    """Authentication related errors"""
    pass


class ConfigurationError(Exception):
    """Configuration related errors"""
    pass


class AuthService:
    """Enhanced authentication service with caching and retry logic"""

    def __init__(self, config: dict, logger: logging.Logger, cache_service=None):
        self.config = config
        self.logger = logger
        self.cache_service = cache_service

        # OpenShift credentials
        self.username = config.get("oc_username")
        self.password = config.get("oc_password")
        self.console_url = config.get("console_url")
        self.token = None
        self.token_expiry = None

        # Keycloak credentials
        self.client_id = config.get("client_id")
        self.client_secret = config.get("client_secret")
        self.keycloak_url = config.get("keycloak_url")
        self.keycloak_token = None
        self.keycloak_token_expiry = None

        # Configuration
        self.allow_self_signed = config.get("allow_self_signed", True)
        self.token_refresh_threshold = config.get("token_refresh_threshold", 300)  # 5 minutes

        # Validate required fields
        self._validate_config()

    def _validate_config(self):
        """Validate authentication configuration"""
        required = ["oc_username", "oc_password", "console_url"]
        missing = [field for field in required if not self.config.get(field)]

        if missing:
            raise ConfigurationError(f"Missing required auth config: {', '.join(missing)}")

    def get_api_url_from_console(self) -> str:
        """Extract API URL from OpenShift console URL"""
        try:
            parsed = urlparse(self.console_url)
            host = parsed.hostname

            if not host:
                raise ValueError("Invalid console URL - no hostname found")

            if host.startswith("console-openshift-console.apps."):
                api_host = host.replace("console-openshift-console.apps.", "api.")
                return f"https://{api_host}:6443"

            raise ValueError("Unsupported OpenShift Console URL format")

        except Exception as e:
            raise ConfigurationError(f"Failed to parse console URL: {e}")

    def authenticate(self) -> bool:
        """
        Authenticate with OpenShift cluster

        Returns:
            True if authentication successful

        Raises:
            AuthenticationError: If authentication fails
        """
        # Check if we have a valid cached token
        if self.token and self._is_token_valid():
            self.logger.info("Using cached authentication token")
            return True

        try:
            api_url = self.get_api_url_from_console()

            self.logger.info(f"Authenticating with OpenShift: {api_url}")

            result = subprocess.run([
                "oc", "login", api_url,
                "--username", self.username,
                "--password", self.password,
                "--insecure-skip-tls-verify"
            ], capture_output=True, text=True, timeout=30)

            if result.returncode != 0:
                raise AuthenticationError(f"Login failed: {result.stderr}")

            # Get token
            token_result = subprocess.run(
                ['oc', 'whoami', '-t'],
                capture_output=True,
                text=True,
                timeout=10
            )

            if token_result.returncode != 0:
                raise AuthenticationError("Failed to retrieve authentication token")

            self.token = token_result.stdout.strip()

            # Set token expiry (default 24 hours for OCP tokens)
            self.token_expiry = datetime.now() + timedelta(hours=24)

            # Cache token if cache service available
            if self.cache_service:
                self.cache_service.set('auth_token', self.token, ttl_seconds=86400)

            self.logger.info("Successfully authenticated with OpenShift")
            return True

        except subprocess.TimeoutExpired:
            raise AuthenticationError("Authentication timed out")
        except Exception as e:
            self.logger.error(f"Authentication failed: {e}")
            raise AuthenticationError(f"Authentication failed: {e}")

    def _is_token_valid(self) -> bool:
        """Check if current token is still valid"""
        if not self.token or not self.token_expiry:
            return False

        # Check if token will expire soon
        time_until_expiry = (self.token_expiry - datetime.now()).total_seconds()

        if time_until_expiry < self.token_refresh_threshold:
            self.logger.info("Token expiring soon, needs refresh")
            return False

        return True

    def get_keycloak_token(self, force_refresh: bool = False) -> str:
        """
        Authenticate with Keycloak using client credentials

        Args:
            force_refresh: Force token refresh even if cached

        Returns:
            Access token

        Raises:
            AuthenticationError: If authentication fails
        """
        # Check cache first
        if not force_refresh and self.keycloak_token and self._is_keycloak_token_valid():
            self.logger.debug("Using cached Keycloak token")
            return self.keycloak_token

        try:
            data = {
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret
            }

            self.logger.info("Authenticating with Keycloak")

            response = requests.post(
                self.keycloak_url,
                data=data,
                verify=not self.allow_self_signed,
                timeout=30
            )
            response.raise_for_status()

            token_data = response.json()
            self.keycloak_token = token_data.get("access_token")

            if not self.keycloak_token:
                raise AuthenticationError("No access token in Keycloak response")

            # Set expiry (usually included in token response)
            expires_in = token_data.get("expires_in", 3600)  # Default 1 hour
            self.keycloak_token_expiry = datetime.now() + timedelta(seconds=expires_in)

            # Cache token
            if self.cache_service:
                self.cache_service.set('keycloak_token', self.keycloak_token, ttl_seconds=expires_in)

            self.logger.info(f"Keycloak authentication successful (expires in {expires_in}s)")
            return self.keycloak_token

        except requests.HTTPError as e:
            error_msg = f"Keycloak auth failed: {e.response.status_code}"
            if e.response.text:
                error_msg += f" - {e.response.text}"
            self.logger.error(error_msg)
            raise AuthenticationError(error_msg)
        except requests.Timeout:
            raise AuthenticationError("Keycloak authentication timed out")
        except Exception as e:
            self.logger.error(f"Keycloak auth failed: {e}")
            raise AuthenticationError(f"Keycloak auth failed: {e}")

    def _is_keycloak_token_valid(self) -> bool:
        """Check if Keycloak token is still valid"""
        if not self.keycloak_token or not self.keycloak_token_expiry:
            return False

        time_until_expiry = (self.keycloak_token_expiry - datetime.now()).total_seconds()

        if time_until_expiry < self.token_refresh_threshold:
            return False

        return True

    def refresh_tokens(self):
        """Refresh all authentication tokens"""
        self.logger.info("Refreshing authentication tokens")

        try:
            self.authenticate()
            if self.keycloak_url:
                self.get_keycloak_token(force_refresh=True)
            self.logger.info("Tokens refreshed successfully")
        except Exception as e:
            self.logger.error(f"Token refresh failed: {e}")
            raise

    def get_token_info(self) -> dict:
        """Get information about current tokens"""
        info = {
            'oc_authenticated': bool(self.token),
            'keycloak_authenticated': bool(self.keycloak_token)
        }

        if self.token_expiry:
            time_left = (self.token_expiry - datetime.now()).total_seconds()
            info['oc_token_expires_in'] = max(0, int(time_left))

        if self.keycloak_token_expiry:
            time_left = (self.keycloak_token_expiry - datetime.now()).total_seconds()
            info['keycloak_token_expires_in'] = max(0, int(time_left))

        return info

    def logout(self):
        """Logout and clear tokens"""
        try:
            subprocess.run(['oc', 'logout'], capture_output=True, timeout=10)
            self.logger.info("Logged out from OpenShift")
        except Exception as e:
            self.logger.warning(f"Logout failed: {e}")

        # Clear tokens
        self.token = None
        self.token_expiry = None
        self.keycloak_token = None
        self.keycloak_token_expiry = None

        # Clear cache
        if self.cache_service:
            self.cache_service.delete('auth_token')
            self.cache_service.delete('keycloak_token')