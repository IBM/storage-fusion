"""
Enhanced Query Service with user-specific bearer token support
"""

import requests
import logging
import subprocess
from typing import Optional, Dict, Any


class QueryService:
    """Enhanced query service with user-specific authentication"""

    def __init__(self, config: Dict, logger: logging.Logger, cache_service=None,
                 auth_service=None, user_auth_manager=None):
        self.config = config
        self.logger = logger
        self.cache_service = cache_service
        self.auth_service = auth_service
        self.user_auth_manager = user_auth_manager

        # Configuration
        self.cas_url = config.get("cas_url")
        self.default_table = config.get("default_table", "gt20")
        self.default_limit = config.get("default_limit", 5)
        self.timeout = config.get("request_timeout", 30)
        self.cache_ttl = config.get('cache', {}).get('query_cache_ttl', 180)  # 3 minutes

        # Initialize token cache
        self.user_tokens = {}

        if not self.cas_url:
            self.logger.warning("CAS URL not configured")

    def query_with_user_token(self, table: Optional[str] = None, limit: Optional[int] = None,
                              username: Optional[str] = None, user_type: str = "ocp",
                              password: Optional[str] = None) -> Dict[str, Any]:
        """
        Get bearer token for a specific user

        Args:
            username: Username to get token for
            user_type: Type of user ("ocp" or "keycloak")

        Returns:
            Bearer token or None if failed
        """
        # Check cache first
        cache_key = f"token_{user_type}_{username}"
        if cache_key in self.user_tokens:
            self.logger.debug(f"Using cached token for {username}")
            return self.user_tokens[cache_key]

        token = None

        if user_type == "ocp":
            token = self._get_ocp_user_token(username)
        elif user_type == "keycloak":
            token = self._get_keycloak_user_token(username)
        else:
            self.logger.error(f"Unknown user type: {user_type}")
            return None

        # Cache token
        if token:
            self.user_tokens[cache_key] = token
            self.logger.info(f"Token obtained for {username} ({user_type})")

        return token

    def _get_ocp_user_token(self, username: str) -> Optional[str]:
        """
        Get token for an OpenShift user by impersonation

        Args:
            username: OCP username

        Returns:
            Bearer token or None
        """
        try:
            # Use oc command to get token for specific user (requires admin privileges)
            # Option 1: Use service account token with impersonation header
            # Option 2: For the current logged-in user, use their token

            # If querying for current user, use existing token
            result = subprocess.run(
                ["oc", "whoami"],
                capture_output=True,
                text=True,
                timeout=10
            )

            current_user = result.stdout.strip()

            if current_user == username:
                # Use current user's token
                token_result = subprocess.run(
                    ["oc", "whoami", "-t"],
                    capture_output=True,
                    text=True,
                    timeout=10
                )

                if token_result.returncode == 0:
                    token = token_result.stdout.strip()
                    self.logger.info(f"Using current user token for {username}")
                    return token
            else:
                # For other users, we need to use service account with impersonation
                # This requires cluster-admin permissions
                self.logger.warning(f"Cannot directly get token for {username}, using admin token with impersonation")

                # Return admin token - the API call will use impersonation header
                if self.auth_service and self.auth_service.token:
                    return self.auth_service.token

            return None

        except subprocess.TimeoutExpired:
            self.logger.error(f"Timeout getting token for {username}")
            return None
        except Exception as e:
            self.logger.error(f"Failed to get OCP token for {username}: {e}")
            return None

    def _get_keycloak_user_token(self, username: str) -> Optional[str]:
        """
        Get token for a Keycloak user

        Args:
            username: Keycloak username

        Returns:
            Bearer token or None
        """
        try:
            # Get user credentials from config
            users_config = self.config.get("users", [])
            user_config = None

            for user in users_config:
                if user.get("name") == username and user.get("type") == "idp":
                    user_config = user
                    break

            if not user_config:
                self.logger.error(f"No configuration found for Keycloak user: {username}")
                return None

            # Get token using client credentials or user credentials
            token_url = user_config.get("token_url") or self.config.get("keycloak_url")
            client_id = user_config.get("client_id")
            client_secret = user_config.get("client_secret")

            # For user-specific queries, we need user's credentials
            # This is a simplified approach - in production, use proper OAuth flow
            user_password = user_config.get("password")

            if client_id and client_secret:
                # Use client credentials flow
                data = {
                    "grant_type": "client_credentials",
                    "client_id": client_id,
                    "client_secret": client_secret
                }
            elif username and user_password:
                # Use resource owner password flow
                data = {
                    "grant_type": "password",
                    "client_id": client_id or self.config.get("client_id"),
                    "username": username,
                    "password": user_password
                }
            else:
                self.logger.error(f"Insufficient credentials for {username}")
                return None

            response = requests.post(
                token_url,
                data=data,
                verify=not self.config.get("allow_self_signed", True),
                timeout=30
            )
            response.raise_for_status()

            token_data = response.json()
            access_token = token_data.get("access_token")

            if access_token:
                self.logger.info(f"Token obtained for Keycloak user: {username}")
                return access_token

            return None

        except requests.HTTPError as e:
            self.logger.error(f"Failed to get Keycloak token: {e.response.status_code} - {e.response.text}")
            return None
        except Exception as e:
            self.logger.error(f"Error getting Keycloak token for {username}: {e}")
            return None

    def query_table(self, table: Optional[str] = None, limit: Optional[int] = None,
                    use_cache: bool = True, username: Optional[str] = None,
                    user_type: str = "ocp") -> Dict[str, Any]:
        """
        Query CAS table with user-specific authentication

        Args:
            table: Table name (default from config)
            limit: Result limit (default from config)
            use_cache: Use cached results if available
            username: Username to query as (uses specific bearer token)
            user_type: Type of user ("ocp" or "keycloak")

        Returns:
            Query results dictionary
        """
        table = table or self.default_table
        limit = limit or self.default_limit

        # Get user-specific token if username provided
        bearer_token = None
        if username:
            bearer_token = self.get_user_token(username, user_type)
            if not bearer_token:
                return {
                    "success": False,
                    "error": f"Failed to obtain token for user: {username}"
                }
        else:
            # Use default admin token
            if self.auth_service and self.auth_service.token:
                bearer_token = self.auth_service.token
            else:
                return {
                    "success": False,
                    "error": "No authentication token available"
                }

        # Build cache key (include username for user-specific caching)
        cache_key = f"query_{table}_{limit}_{username}"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(f"Retrieved query results from cache: {table} (user: {username})")
                return cached

        # Build URL
        url = f"{self.cas_url}/query?table={table}&limit={limit}"

        try:
            self.logger.info(f"Querying CAS API: {url} (user: {username}, type: {user_type})")

            response = requests.get(
                url,
                headers=headers,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout
            )

            # Check for authorization errors
            if response.status_code == 401:
                error_msg = "Invalid or expired user token"
                self.logger.error(f"Authentication failed for user {username}: {error_msg}")

                # Clear cached token for this user
                if self.user_auth_manager:
                    self.user_auth_manager.clear_user_token(username)

                return {
                    "success": False,
                    "error": error_msg,
                    "status_code": 401,
                    "user": username,
                    "details": "User token is invalid or expired. Please re-authenticate."
                }

            if response.status_code == 403:
                error_msg = "User does not have permission to access this resource"
                self.logger.error(f"Authorization failed for user {username}: {error_msg}")
                return {
                    "success": False,
                    "error": error_msg,
                    "status_code": 403,
                    "user": username,
                    "details": f"User '{username}' is not added to this domain or does not have access."
                }

            response.raise_for_status()

            result = response.json()
            result['authenticated_user'] = username
            result['user_type'] = user_type

            # Cache successful result
            if self.cache_service:
                self.cache_service.set(cache_key, result, ttl_seconds=self.cache_ttl)

            self.logger.info(f"Query successful: {table} (user: {username})")
            return result

        except requests.HTTPError as e:
            error_msg = f"CAS API error: {e.response.status_code}"
            self.logger.error(f"{error_msg} - {e.response.text}")
            return {
                "success": False,
                "error": error_msg,
                "details": e.response.text,
                "user": username,
                "status_code": e.response.status_code
            }

        except requests.Timeout:
            error_msg = "Query timed out"
            self.logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg,
                "user": username
            }

        except requests.RequestException as e:
            error_msg = f"Query failed: {str(e)}"
            self.logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg,
                "user": username
            }
        """
        Query CAS table

        Args:
            table: Table name (default from config)
            limit: Result limit (default from config)
            use_cache: Use cached results if available

        Returns:
            Query results dictionary
        """
        table = table or self.default_table
        limit = limit or self.default_limit

        # Build cache key
        cache_key = f"query_{table}_{limit}"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(f"Retrieved query results from cache: {table}")
                return cached

        # Build URL
        url = f"{self.cas_url}/query?table={table}&limit={limit}"

        try:
            self.logger.info(f"Querying CAS API: {url}")

            response = requests.get(
                url,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout
            )
            response.raise_for_status()

            result = response.json()

            # Cache successful result
            if self.cache_service:
                self.cache_service.set(cache_key, result, ttl_seconds=self.cache_ttl)

            self.logger.info(f"Query successful: {table}")
            return result

        except requests.HTTPError as e:
            error_msg = f"CAS API error: {e.response.status_code}"
            self.logger.error(f"{error_msg} - {e.response.text}")
            return {
                "success": False,
                "error": error_msg,
                "details": e.response.text
            }

        except requests.Timeout:
            error_msg = "Query timed out"
            self.logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg
            }

        except requests.RequestException as e:
            error_msg = f"Query failed: {str(e)}"
            self.logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg
            }

    def query_with_filters(self, table: str, filters: Dict[str, Any],
                           limit: Optional[int] = None, username: Optional[str] = None,
                           user_type: str = "ocp") -> Dict[str, Any]:
        """
        Query with additional filters and user-specific token

        Args:
            table: Table name
            filters: Filter parameters
            limit: Result limit
            username: Username to query as
            user_type: Type of user ("ocp" or "keycloak")

        Returns:
            Query results dictionary
        """
        limit = limit or self.default_limit
        url = f"{self.cas_url}/query"

        params = {
            "table": table,
            "limit": limit,
            **filters
        }

        # Get user-specific token
        bearer_token = None
        if username:
            bearer_token = self.get_user_token(username, user_type)
            if not bearer_token:
                return {
                    "success": False,
                    "error": f"Failed to obtain token for user: {username}"
                }
        else:
            if self.auth_service and self.auth_service.token:
                bearer_token = self.auth_service.token

        headers = {
            "Authorization": f"Bearer {bearer_token}",
            "Content-Type": "application/json"
        }

        # Add impersonation if needed
        if username and user_type == "ocp":
            try:
                result = subprocess.run(["oc", "whoami"], capture_output=True, text=True, timeout=5)
                current_user = result.stdout.strip() if result.returncode == 0 else None
                if current_user and current_user != username:
                    headers["Impersonate-User"] = username
            except:
                pass

        try:
            self.logger.info(f"Querying CAS API with filters: {table} (user: {username or 'admin'})")

            response = requests.get(
                url,
                params=params,
                headers=headers,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout
            )
            response.raise_for_status()

            result = response.json()
            self.logger.info(f"Filtered query successful: {table} (user: {username or 'admin'})")
            return result

        except Exception as e:
            error_msg = f"Filtered query failed: {str(e)}"
            self.logger.error(error_msg)
            return {
                "success": False,
                "error": error_msg,
                "user": username
            }

    def clear_user_token_cache(self, username: Optional[str] = None):
        """
        Clear cached tokens for a user or all users

        Args:
            username: Specific username to clear, or None for all
        """
        if username:
            # Clear specific user tokens
            keys_to_remove = [k for k in self.user_tokens.keys() if username in k]
            for key in keys_to_remove:
                del self.user_tokens[key]
            self.logger.info(f"Cleared token cache for user: {username}")
        else:
            # Clear all
            self.user_tokens.clear()
            self.logger.info("Cleared all user token cache")

    def list_tables(self, use_cache: bool = True, username: Optional[str] = None,
                    user_type: str = "ocp") -> list:
        """
        List available tables with user-specific token

        Args:
            use_cache: Use cached results if available
            username: Username to query as
            user_type: Type of user ("ocp" or "keycloak")

        Returns:
            List of table names
        """
        cache_key = f"query_tables_list_{username or 'admin'}"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(f"Retrieved table list from cache (user: {username or 'admin'})")
                return cached

        # Get user-specific token
        bearer_token = None
        if username:
            bearer_token = self.get_user_token(username, user_type)
            if not bearer_token:
                self.logger.error(f"Cannot list tables: failed to get token for {username}")
                return []
        else:
            if self.auth_service and self.auth_service.token:
                bearer_token = self.auth_service.token

        url = f"{self.cas_url}/tables"
        headers = {
            "Authorization": f"Bearer {bearer_token}",
            "Content-Type": "application/json"
        }

        # Add impersonation if needed
        if username and user_type == "ocp":
            try:
                result = subprocess.run(["oc", "whoami"], capture_output=True, text=True, timeout=5)
                current_user = result.stdout.strip() if result.returncode == 0 else None
                if current_user and current_user != username:
                    headers["Impersonate-User"] = username
            except:
                pass

        try:
            self.logger.info(f"Fetching table list from CAS API (user: {username or 'admin'})")

            response = requests.get(
                url,
                headers=headers,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout
            )
            response.raise_for_status()

            tables = response.json().get("tables", [])

            # Cache result
            if self.cache_service:
                self.cache_service.set(cache_key, tables, ttl_seconds=600)  # 10 minutes

            self.logger.info(f"Retrieved {len(tables)} tables (user: {username or 'admin'})")
            return tables

        except Exception as e:
            self.logger.error(f"Failed to list tables: {e}")
            return []

    def get_table_info(self, table: str, username: Optional[str] = None,
                       user_type: str = "ocp") -> Optional[Dict[str, Any]]:
        """
        Get information about a specific table with user-specific token

        Args:
            table: Table name
            username: Username to query as
            user_type: Type of user ("ocp" or "keycloak")

        Returns:
            Table information dictionary or None
        """
        # Get user-specific token
        bearer_token = None
        if username:
            bearer_token = self.get_user_token(username, user_type)
            if not bearer_token:
                self.logger.error(f"Cannot get table info: failed to get token for {username}")
                return None
        else:
            if self.auth_service and self.auth_service.token:
                bearer_token = self.auth_service.token

        url = f"{self.cas_url}/table/{table}/info"
        headers = {
            "Authorization": f"Bearer {bearer_token}",
            "Content-Type": "application/json"
        }

        # Add impersonation if needed
        if username and user_type == "ocp":
            try:
                result = subprocess.run(["oc", "whoami"], capture_output=True, text=True, timeout=5)
                current_user = result.stdout.strip() if result.returncode == 0 else None
                if current_user and current_user != username:
                    headers["Impersonate-User"] = username
            except:
                pass

        try:
            response = requests.get(
                url,
                headers=headers,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout
            )
            response.raise_for_status()

            info = response.json()
            self.logger.info(f"Retrieved info for table: {table} (user: {username or 'admin'})")
            return info

        except Exception as e:
            self.logger.error(f"Failed to get table info: {e}")
            return None

    def clear_cache(self):
        """Clear query cache"""
        if self.cache_service:
            self.cache_service.clear_pattern("query_*")
            self.logger.info("Query cache cleared")

    def get_statistics(self) -> Dict[str, Any]:
        """Get query service statistics"""
        stats = {
            "cas_url": self.cas_url,
            "default_table": self.default_table,
            "default_limit": self.default_limit,
            "cache_enabled": self.cache_service is not None
        }

        if self.cache_service:
            cache_stats = self.cache_service.get_statistics()
            stats["cache_stats"] = cache_stats

        return stats