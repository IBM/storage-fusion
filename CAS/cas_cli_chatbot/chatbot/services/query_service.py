"""
Enhanced Query Service with user-specific bearer token support
"""

import requests
import logging
import subprocess
import hashlib
import json
from typing import Optional, Dict, Any
from chatbot.utils.validators import InputValidator, ValidationError, TokenValidator
from chatbot.utils.response_formatter import ResponseFormatter


class QueryService:
    """Enhanced query service with user-specific authentication"""

    def __init__(self,
                 config: Dict,
                 logger: logging.Logger,
                 cache_service=None,
                 auth_service=None):
        self.config = config
        self.logger = logger
        self.cache_service = cache_service
        self.auth_service = auth_service

        # Configuration
        self.cas_url = config.get("cas_url")
        self.default_vector_store = config.get("default_vector_store", "gt20")
        self.default_limit = config.get("default_limit", 5)
        self.timeout = config.get("request_timeout", 30)
        self.cache_ttl = config.get('cache', {}).get('query_cache_ttl',
                                                     180)  # 3 minutes

        if not self.cas_url:
            self.logger.warning("CAS URL not configured")

    def _check_bearer_token(self) -> Dict[str, Any]:
        """
        Check if bearer token is available and valid
        
        Returns:
            Dict with 'valid' boolean and optional 'error' message
        """
        return TokenValidator.validate_bearer_token(self.auth_service)

    def query_vector_store(self,
                           user_query: str,
                           vector_store: Optional[str] = None,
                           limit: Optional[int] = None,
                           use_cache: bool = True) -> Dict[str, Any]:
        """
        Query CAS vector store with admin authentication

        Args:
            user_query: Query entered by user
            vector_store: vector store name (default from config)
            limit: Result limit (default from config)
            use_cache: Use cached results if available

        Returns:
            Query results dictionary
        """
        # Validate inputs
        try:
            user_query = InputValidator.validate_query(user_query, "user_query")
            if vector_store:
                vector_store = InputValidator.validate_vector_store_name(
                    vector_store, "vector_store")
            if limit is not None:
                limit = InputValidator.validate_limit(limit, "limit")
        except ValidationError as e:
            self.logger.error(f"Input validation failed: {e}")
            return ResponseFormatter.validation_error(str(e))

        # Check if bearer token is valid before proceeding
        token_check = self._check_bearer_token()
        if not token_check['valid']:
            self.logger.error(
                f"Token validation failed: {token_check['error']}")
            return ResponseFormatter.authentication_error(token_check['error'])

        vector_store = vector_store or self.default_vector_store
        limit = limit or self.default_limit

        # Get bearer token from auth service
        bearer_token = self.auth_service.token if self.auth_service else None
        if not bearer_token:
            return ResponseFormatter.authentication_error(
                "Failed to obtain bearer token from auth service")

        # Build cache key with query hash to avoid collisions
        query_hash = hashlib.md5(user_query.encode()).hexdigest()[:8]
        cache_key = f"query_{vector_store}_{limit}_{query_hash}"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(
                    f"Retrieved query results from cache: {vector_store}")
                return cached

        url = f"{self.cas_url}/vector_stores/{vector_store}/search"

        headers = {
            "Authorization": f"Bearer {bearer_token}",
            "Content-Type": "application/json"
        }

        try:
            self.logger.info(f"Querying CAS API: {url}")

            payload = {
                "query":
                    user_query,
                "max_num_results":
                    limit,
                "enable_source":
                    self.config.get("enable_source", False),
                "enable_content_metadata":
                    self.config.get("enable_content_metadata", False)
            }

            response = requests.post(
                url,
                headers=headers,
                json=payload,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout)
            response.raise_for_status()

            result = response.json()

            # Cache successful result
            if self.cache_service:
                self.cache_service.set(cache_key,
                                       result,
                                       ttl_seconds=self.cache_ttl)

            self.logger.info(f"Query successful: {vector_store}")
            return result

        except requests.exceptions.Timeout:
            self.logger.error(f"Query timed out: {vector_store}")
            return ResponseFormatter.timeout_error("Vector store query",
                                                   self.timeout)
        except requests.exceptions.RequestException as e:
            self.logger.error(f"Network error during query: {e}")
            return ResponseFormatter.network_error(str(e))
        except Exception as e:
            self.logger.error(f"Query failed: {e}")
            return ResponseFormatter.internal_error(str(e))

    def query_with_filters(self,
                           user_query: str,
                           filters: Dict[str, Any],
                           vector_store: Optional[str] = None,
                           limit: Optional[int] = None,
                           use_cache: bool = True) -> Dict[str, Any]:
        """
        Query with additional filters using admin token

        Args:
            user_query: Query entered by user
            vector_store: Vector store name
            filters: Filter parameters
            limit: Result limit
            use_cache: Use cached results if available

        Returns:
            Query results dictionary
        """
        # Validate inputs
        try:
            user_query = InputValidator.validate_query(user_query, "user_query")
            filters = InputValidator.validate_filters(filters, "filters")
            if vector_store:
                vector_store = InputValidator.validate_vector_store_name(
                    vector_store, "vector_store")
            if limit is not None:
                limit = InputValidator.validate_limit(limit, "limit")
        except ValidationError as e:
            self.logger.error(f"Input validation failed: {e}")
            return ResponseFormatter.validation_error(str(e))

        # Check if bearer token is valid before proceeding
        token_check = self._check_bearer_token()
        if not token_check['valid']:
            self.logger.error(
                f"Token validation failed: {token_check['error']}")
            return ResponseFormatter.authentication_error(token_check['error'])

        vector_store = vector_store or self.default_vector_store
        limit = limit or self.default_limit

        # Build cache key with query and filter hash
        query_hash = hashlib.md5(user_query.encode()).hexdigest()[:8]
        filter_hash = hashlib.md5(json.dumps(
            filters, sort_keys=True).encode()).hexdigest()[:8]
        cache_key = (
            f"query_filter_{vector_store}_{limit}_{query_hash}_{filter_hash}")

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(
                    f"Retrieved filtered query results from cache: {vector_store}"
                )
                return cached

        url = f"{self.cas_url}/vector_stores/{vector_store}/search"

        # Get bearer token from auth service
        bearer_token = self.auth_service.token if self.auth_service else None
        if not bearer_token:
            return ResponseFormatter.authentication_error(
                "Failed to obtain bearer token from auth service")

        headers = {
            "Authorization": f"Bearer {bearer_token}",
            "Content-Type": "application/json"
        }

        try:
            self.logger.info(f"Querying CAS API with filters: {vector_store}")

            payload = {
                "query":
                    user_query,
                "filters":
                    filters,
                "max_num_results":
                    limit,
                "enable_source":
                    self.config.get("enable_source", False),
                "enable_content_metadata":
                    self.config.get("enable_content_metadata", False)
            }

            response = requests.post(
                url,
                headers=headers,
                json=payload,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout)
            response.raise_for_status()

            result = response.json()

            # Cache successful result
            if self.cache_service:
                self.cache_service.set(cache_key,
                                       result,
                                       ttl_seconds=self.cache_ttl)

            self.logger.info(f"Filtered query successful: {vector_store}")
            return result

        except requests.exceptions.Timeout:
            self.logger.error(f"Filtered query timed out: {vector_store}")
            return ResponseFormatter.timeout_error(
                "Filtered vector store query", self.timeout)
        except requests.exceptions.RequestException as e:
            self.logger.error(f"Network error during filtered query: {e}")
            return ResponseFormatter.network_error(str(e))
        except Exception as e:
            self.logger.error(f"Filtered query failed: {e}")
            return ResponseFormatter.internal_error(str(e))

    def list_vector_stores(self, use_cache: bool = True) -> list:
        """
        List available vector stores using admin token

        Args:
            use_cache: Use cached results if available

        Returns:
            List of vector store names
        """
        # Check if bearer token is valid before proceeding
        token_check = self._check_bearer_token()
        if not token_check['valid']:
            self.logger.error(
                f"Token validation failed: {token_check['error']}")
            return []

        cache_key = "query_tables_list"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug("Retrieved vector store list from cache")
                return cached

        # Get bearer token from auth service
        bearer_token = self.auth_service.token if self.auth_service else None
        if not bearer_token:
            self.logger.error(
                "Cannot list vector stores: no bearer token available")
            return []

        limit = self.config.get('default_limit', 10)
        url = f"{self.cas_url}/vector_stores?limit={limit}&order=desc"
        headers = {
            "Authorization": f"Bearer {bearer_token}",
            "Content-Type": "application/json"
        }

        try:
            response = requests.get(
                url,
                headers=headers,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout)
            response.raise_for_status()

            # Get list of vector stores
            vector_stores = [
                vs["name"]
                for vs in response.json().get("data", [])
                if isinstance(vs, dict) and vs.get("name")
            ]

            # Cache result
            if self.cache_service:
                self.cache_service.set(cache_key,
                                       vector_stores,
                                       ttl_seconds=600)  # 10 minutes

            return vector_stores

        except Exception as e:
            self.logger.error(f"Failed to list vector stores: {e}")
            return []

    def get_vector_store_info(self,
                              vector_store: str) -> Optional[Dict[str, Any]]:
        """
        Get information about a specific vector store using user token

        Args:
            vector_store: Vector store name

        Returns:
            Vector store information dictionary or None
        """
        # Validate inputs
        try:
            vector_store = InputValidator.validate_vector_store_name(
                vector_store, "vector_store")
        except ValidationError as e:
            self.logger.error(f"Input validation failed: {e}")
            return None

        # Check if bearer token is valid before proceeding
        token_check = self._check_bearer_token()
        if not token_check['valid']:
            self.logger.error(
                f"Token validation failed: {token_check['error']}")
            return None

        # Get bearer token from auth service
        bearer_token = self.auth_service.token if self.auth_service else None
        if not bearer_token:
            self.logger.error(
                "Cannot get vector store info: no bearer token available")
            return None

        url = f"{self.cas_url}/vector_stores?limit={self.config.get('default_limit', 10)}&order={self.config.get('default_order', 'desc')}"
        headers = {
            "Authorization": f"Bearer {bearer_token}",
            "Content-Type": "application/json"
        }

        try:
            response = requests.get(
                url,
                headers=headers,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout)
            response.raise_for_status()

            data_list = response.json().get("data")

            # Get the info for the specified vector store
            vector_store_info = next((
                item for item in data_list if item.get("name") == vector_store),
                                     None)

            self.logger.info(f"Retrieved info for vector store: {vector_store}")
            return vector_store_info

        except Exception as e:
            self.logger.error(f"Failed to get vector store info: {e}")
            return None

    def get_file_content(self, vector_store_id: str,
                         file_id: str) -> Dict[str, Any]:
        """Returns all the content (text chunks) for a specific vector store and file by their IDs"""

        # Validate inputs
        try:
            vector_store_id = InputValidator.validate_vector_store_name(
                vector_store_id, "vector_store_id")
            file_id = InputValidator.validate_file_id(file_id, "file_id")
        except ValidationError as e:
            self.logger.error(f"Input validation failed: {e}")
            return ResponseFormatter.validation_error(str(e))

        # Check if bearer token is valid before proceeding
        token_check = self._check_bearer_token()
        if not token_check['valid']:
            self.logger.error(
                f"Token validation failed: {token_check['error']}")
            return ResponseFormatter.authentication_error(token_check['error'])

        url = f"{self.cas_url}/vector_stores/{vector_store_id}/files/{file_id}/content"

        # Get bearer token from auth service
        bearer_token = self.auth_service.token if self.auth_service else None
        if not bearer_token:
            return {
                "success": False,
                "error": "Failed to obtain bearer token from auth service"
            }

        headers = {
            "Authorization": f"Bearer {bearer_token}",
            "Content-Type": "application/json"
        }

        try:
            self.logger.info(
                f"Retrieving file content from file'{file_id}' in vector store '{vector_store_id}'"
            )

            params = {
                "enable_source":
                    self.config.get("enable_source", False),
                "enable_content_metadata":
                    self.config.get("enable_content_metadata", False)
            }

            response = requests.get(
                url,
                params=params,
                headers=headers,
                verify=not self.config.get("allow_self_signed", True),
                timeout=self.timeout)

            response.raise_for_status()

            result = response.json()
            self.logger.info(
                f"File content retrieval successful for file '{file_id}' in '{vector_store_id}'"
            )
            return result

        except requests.exceptions.Timeout:
            self.logger.error(
                f"File content retrieval timed out for file '{file_id}'")
            return ResponseFormatter.timeout_error("File content retrieval",
                                                   self.timeout)
        except requests.exceptions.RequestException as e:
            self.logger.error(
                f"Network error during file content retrieval: {e}")
            return ResponseFormatter.network_error(str(e))
        except Exception as e:
            error_msg = f"File content retrieval failed: {str(e)}"
            self.logger.error(error_msg)
            return ResponseFormatter.internal_error(error_msg)

    def clear_cache(self):
        """Clear query cache"""
        if self.cache_service:
            self.cache_service.clear_pattern("query_*")
            self.logger.info("Query cache cleared")

    def get_statistics(self) -> Dict[str, Any]:
        """Get query service statistics"""
        stats = {
            "cas_url": self.cas_url,
            "default_vector_store": self.default_vector_store,
            "default_limit": self.default_limit,
            "cache_enabled": self.cache_service is not None
        }

        if self.cache_service:
            cache_stats = self.cache_service.get_statistics()
            stats["cache_stats"] = cache_stats

        return stats
