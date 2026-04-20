"""
Enhanced Authentication Service with token caching and retry logic
"""

import subprocess
import requests
import logging
from urllib.parse import urlparse
from typing import Optional
from datetime import datetime, timedelta
import re

class AuthenticationError(Exception):
    """Authentication related errors"""
    pass


class ConfigurationError(Exception):
    """Configuration related errors"""
    pass


class AuthService:
    """Enhanced authentication service with caching and retry logic"""

    def __init__(self,
                 config: dict,
                 logger: logging.Logger,
                 cache_service=None):
        self.config = config
        self.logger = logger
        self.cache_service = cache_service

        # OpenShift credentials
        self.username = config.get("oc_username")
        self.password = config.get("oc_password")
        self.console_url = config.get("console_url")
        self.token = None  # Bearer token fetched once at login
        self.token_expiry = None
        self.token_fetch_attempted = False  # Track if we've tried to fetch token

        # Configuration
        self.allow_self_signed = config.get("allow_self_signed", True)
        self.token_refresh_threshold = config.get("token_refresh_threshold",
                                                  300)  # 5 minutes

        # Validate required fields
        self._validate_config()

    def _validate_config(self):
        """Validate authentication configuration"""
        required = ["oc_username", "oc_password", "console_url"]
        missing = [field for field in required if not self.config.get(field)]

        if missing:
            raise ConfigurationError(
                f"Missing required auth config: {', '.join(missing)}")

    def get_api_url_from_console(self) -> str:
        """Extract API URL from OpenShift console URL"""
        try:
            parsed = urlparse(self.console_url)
            host = parsed.hostname

            if not host:
                raise ValueError("Invalid console URL - no hostname found")

            if host.startswith("console-openshift-console.apps."):
                api_host = host.replace("console-openshift-console.apps.",
                                        "api.")
                return f"https://{api_host}:6443"

            raise ValueError("Unsupported OpenShift Console URL format")

        except Exception as e:
            raise ConfigurationError(f"Failed to parse console URL: {e}")

    def authenticate(self) -> bool:
        """
        Authenticate with OpenShift cluster and fetch bearer token once

        Returns:
            True if authentication successful and token obtained

        Raises:
            AuthenticationError: If authentication fails
        """
        # Check if we have a valid cached token
        if self.token and self._is_token_valid():
            self.logger.info("Using cached authentication token")
            return True

        # Mark that we're attempting to fetch token
        self.token_fetch_attempted = True

        try:
            api_url = self.get_api_url_from_console()

            self.logger.info(f"Authenticating with OpenShift: {api_url}")

            result = subprocess.run([
                "oc", "login", api_url, "--username", self.username,
                "--password", self.password, "--insecure-skip-tls-verify"
            ],
                                    capture_output=True,
                                    text=True,
                                    timeout=30)

            if result.returncode != 0:
                self.logger.error(f"OC login failed: {result.stderr}")
                raise AuthenticationError(f"Login failed: {result.stderr}")

            # Fetch bearer token immediately after successful login
            self.logger.info("Fetching bearer token...")
            token_result = subprocess.run(['oc', 'whoami', '-t'],
                                          capture_output=True,
                                          text=True,
                                          timeout=10)

            if token_result.returncode != 0:
                self.logger.error("Failed to retrieve bearer token")
                raise AuthenticationError(
                    "Failed to retrieve authentication token")

            self.token = token_result.stdout.strip()

            if not self.token:
                self.logger.error("Bearer token is empty")
                raise AuthenticationError("Bearer token is empty")

            # Set token expiry (default 24 hours for OCP tokens)
            self.token_expiry = datetime.now() + timedelta(hours=24)

            # Cache token if cache service available
            if self.cache_service:
                self.cache_service.set('auth_token',
                                       self.token,
                                       ttl_seconds=86400)

            self.logger.info("Successfully authenticated and obtained bearer token")
            return True

        except subprocess.TimeoutExpired:
            self.logger.error("Authentication timed out")
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

    def refresh_tokens(self):
        """Refresh all authentication tokens"""
        self.logger.info("Refreshing authentication tokens")

        try:
            self.authenticate()
            self.logger.info("Tokens refreshed successfully")
        except Exception as e:
            self.logger.error(f"Token refresh failed: {e}")
            raise

    def has_valid_token(self) -> bool:
        """
        Check if a valid bearer token exists
        
        Returns:
            True if token exists and is valid, False otherwise
        """
        return bool(self.token and self._is_token_valid())

    def get_token_info(self) -> dict:
        """Get information about current tokens"""
        info = {
            'oc_authenticated': bool(self.token),
            'token_valid': self.has_valid_token(),
            'token_fetch_attempted': self.token_fetch_attempted
        }

        if self.token_expiry:
            time_left = (self.token_expiry - datetime.now()).total_seconds()
            info['oc_token_expires_in'] = max(0, int(time_left))

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

        # Clear cache
        if self.cache_service:
            self.cache_service.delete('auth_token')


