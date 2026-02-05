"""
User Authentication Manager - Handle user-specific authentication and token management
"""

import subprocess
import requests
import logging
from typing import Optional, Dict, Any, Tuple
from datetime import datetime, timedelta
from getpass import getpass

class UserAuthenticationError(Exception):
    """User authentication related errors"""
    pass

class UserAuthenticationManager:
    """
    Manages user-specific authentication for both OCP and Keycloak users
    Handles token acquisition, caching, and refresh
    """
    
    def __init__(self, config: Dict, logger: logging.Logger):
        self.config = config
        self.logger = logger
        
        # User token cache: {username: {token, expiry, user_type}}
        self.user_tokens = {}
        
        # Keycloak configuration
        self.keycloak_url = config.get("keycloak_url")
        self.keycloak_client_id = config.get("client_id")
        self.keycloak_client_secret = config.get("client_secret")
        
        self.logger.info("User Authentication Manager initialized")
    
    def authenticate_ocp_user(self, username: str, password: Optional[str] = None) -> Tuple[bool, Optional[str]]:
        """
        Authenticate an OpenShift user and get their token
        
        Args:
            username: OCP username
            password: OCP password (if None, will prompt)
            
        Returns:
            Tuple (success, token)
        """
        try:
            # Get password if not provided
            if password is None:
                password = getpass(f"Enter password for OCP user '{username}': ")
            
            # Get API URL from console
            console_url = self.config.get("console_url")
            api_url = self._extract_api_url(console_url)
            
            self.logger.info(f"Authenticating OCP user: {username}")
            
            # Attempt OCP login
            result = subprocess.run([
                "oc", "login", api_url,
                "--username", username,
                "--password", password,
                "--insecure-skip-tls-verify"
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                error_msg = result.stderr.decode() if isinstance(result.stderr, bytes) else result.stderr
                self.logger.error(f"OCP login failed for {username}: {error_msg}")
                return False, None
            
            # Get token for this user
            token_result = subprocess.run(
                ['oc', 'whoami', '-t'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if token_result.returncode != 0:
                self.logger.error(f"Failed to retrieve token for {username}")
                return False, None
            
            token = token_result.stdout.strip()
            
            # Verify token is valid by checking whoami
            verify_result = subprocess.run(
                ['oc', 'whoami'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if verify_result.returncode != 0:
                self.logger.error(f"Token verification failed for {username}")
                return False, None
            
            verified_user = verify_result.stdout.strip()
            
            if verified_user != username:
                self.logger.error(f"Token mismatch: expected {username}, got {verified_user}")
                return False, None
            
            # Cache the token (OCP tokens typically valid for 24 hours)
            self.user_tokens[username] = {
                'token': token,
                'expiry': datetime.now() + timedelta(hours=24),
                'user_type': 'ocp',
                'authenticated_at': datetime.now()
            }
            
            self.logger.info(f"Successfully authenticated OCP user: {username}")
            return True, token
            
        except subprocess.TimeoutExpired:
            self.logger.error(f"OCP authentication timeout for {username}")
            return False, None
        except Exception as e:
            self.logger.error(f"OCP authentication error for {username}: {e}")
            return False, None
    
    def authenticate_keycloak_user(self, username: str, password: Optional[str] = None) -> Tuple[bool, Optional[str]]:
        """
        Authenticate a Keycloak user and get their token
        Uses password grant flow (Direct Access Grants must be enabled)
        
        Args:
            username: Keycloak username
            password: Keycloak password (if None, will prompt)
            
        Returns:
            Tuple (success, token)
        """
        try:
            # Get password if not provided
            if password is None:
                password = getpass(f"Enter password for Keycloak user '{username}': ")
            
            if not self.keycloak_url:
                self.logger.error("Keycloak URL not configured")
                return False, None
            
            self.logger.info(f"Authenticating Keycloak user: {username}")
            
            # Use password grant flow
            data = {
                "grant_type": "password",
                "client_id": self.keycloak_client_id,
                "client_secret": self.keycloak_client_secret,
                "username": username,
                "password": password
            }
            
            response = requests.post(
                self.keycloak_url,
                data=data,
                verify=not self.config.get("allow_self_signed", True),
                timeout=30
            )
            
            if response.status_code != 200:
                error_text = response.text
                self.logger.error(f"Keycloak auth failed for {username}: {response.status_code} - {error_text}")
                return False, None
            
            token_data = response.json()
            access_token = token_data.get("access_token")
            expires_in = token_data.get("expires_in", 3600)
            
            if not access_token:
                self.logger.error(f"No access token in Keycloak response for {username}")
                return False, None
            
            # Cache the token
            self.user_tokens[username] = {
                'token': access_token,
                'expiry': datetime.now() + timedelta(seconds=expires_in),
                'user_type': 'keycloak',
                'refresh_token': token_data.get("refresh_token"),
                'authenticated_at': datetime.now()
            }
            
            self.logger.info(f"Successfully authenticated Keycloak user: {username}")
            return True, access_token
            
        except requests.Timeout:
            self.logger.error(f"Keycloak authentication timeout for {username}")
            return False, None
        except Exception as e:
            self.logger.error(f"Keycloak authentication error for {username}: {e}")
            return False, None
    
    def get_user_token(self, username: str, user_type: str = "ocp", 
                      password: Optional[str] = None, force_refresh: bool = False) -> Optional[str]:
        """
        Get or refresh token for a specific user
        
        Args:
            username: Username
            user_type: Type of user ("ocp" or "keycloak")
            password: Password (if None, will prompt)
            force_refresh: Force token refresh even if cached
            
        Returns:
            Bearer token or None if authentication fails
        """
        # Check cache first
        if not force_refresh and username in self.user_tokens:
            cached = self.user_tokens[username]
            if cached['expiry'] > datetime.now():
                self.logger.debug(f"Using cached token for {username}")
                return cached['token']
            else:
                self.logger.info(f"Token expired for {username}, refreshing...")
                del self.user_tokens[username]
        
        # Get new token
        if user_type == "ocp":
            success, token = self.authenticate_ocp_user(username, password)
        elif user_type == "keycloak":
            success, token = self.authenticate_keycloak_user(username, password)
        else:
            self.logger.error(f"Unknown user type: {user_type}")
            return None
        
        return token if success else None
    
    def get_user_auth_headers(self, username: str, user_type: str = "ocp",
                             password: Optional[str] = None) -> Optional[Dict[str, str]]:
        """
        Get authorization headers for a specific user
        
        Args:
            username: Username
            user_type: Type of user ("ocp" or "keycloak")
            password: Password for authentication
            
        Returns:
            Dictionary with Authorization header or None
        """
        token = self.get_user_token(username, user_type, password)
        
        if not token:
            return None
        
        return {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
    
    def is_user_token_valid(self, username: str) -> bool:
        """
        Check if cached token for user is still valid
        
        Args:
            username: Username
            
        Returns:
            True if token exists and is valid
        """
        if username not in self.user_tokens:
            return False
        
        cached = self.user_tokens[username]
        return cached['expiry'] > datetime.now()
    
    def get_user_info(self, username: str) -> Optional[Dict[str, Any]]:
        """
        Get information about cached user authentication
        
        Args:
            username: Username
            
        Returns:
            User info dictionary or None
        """
        if username not in self.user_tokens:
            return None
        
        cached = self.user_tokens[username]
        
        return {
            'username': username,
            'user_type': cached['user_type'],
            'authenticated_at': cached['authenticated_at'].isoformat(),
            'expires_at': cached['expiry'].isoformat(),
            'is_valid': cached['expiry'] > datetime.now(),
            'token_age_seconds': (datetime.now() - cached['authenticated_at']).total_seconds()
        }
    
    def clear_user_token(self, username: str):
        """
        Clear cached token for a user
        
        Args:
            username: Username
        """
        if username in self.user_tokens:
            del self.user_tokens[username]
            self.logger.info(f"Cleared token for user: {username}")
    
    def clear_all_tokens(self):
        """Clear all cached user tokens"""
        self.user_tokens.clear()
        self.logger.info("Cleared all user tokens")
    
    def _extract_api_url(self, console_url: str) -> str:
        """Extract API URL from console URL"""
        from urllib.parse import urlparse
        
        parsed = urlparse(console_url)
        host = parsed.hostname
        
        if host.startswith("console-openshift-console.apps."):
            api_host = host.replace("console-openshift-console.apps.", "api.")
            return f"https://{api_host}:6443"
        
        raise ValueError(f"Unsupported console URL format: {console_url}")
    
    def list_authenticated_users(self) -> list:
        """Get list of currently authenticated users"""
        users = []
        for username, info in self.user_tokens.items():
            if info['expiry'] > datetime.now():
                users.append({
                    'username': username,
                    'type': info['user_type'],
                    'expires_in': (info['expiry'] - datetime.now()).total_seconds()
                })
        return users
