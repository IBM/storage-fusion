"""
Fixed Vector Store Service with proper user assignment for OCP and Keycloak users
"""

import requests
import urllib3
import subprocess
import json
import logging
from typing import List, Dict, Optional, Any
from rich.console import Console
from chatbot.utils.validators import InputValidator, ValidationError


class VectorStoreService:
    """Enhanced vector store management service with proper user assignment"""

    def __init__(self,
                 config: dict,
                 auth_service,
                 logger: logging.Logger,
                 cache_service=None,
                 console: Optional[Console] = None):
        self.config = config
        self.auth_service = auth_service
        self.logger = logger
        self.cache_service = cache_service
        self.console = console or Console()

        # Disable insecure HTTPS warnings
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

        # Setup API base URL
        # console_url = self.auth_service.config.get("console_url")
        # if console_url.endswith("/"):
        #     console_url = console_url[:-1]
        # self.api_base = f"{console_url}/cas/api/v1"

        # In-memory storage for domain assignments (local cache)
        self.vector_store_assignments: Dict[str, Dict[str, List[str]]] = {}

        # Cache TTL
        self.cache_ttl = config.get('cache', {}).get('domain_cache_ttl',
                                                     300)  # 5 minutes

        self.logger.info("Vector Search Service initialized")

    def list_vector_stores(self,
                           namespace: str = "ibm-cas",
                           use_cache: bool = True) -> List[str]:
        """
        Fetch vector stores from OpenShift

        Args:
            namespace: Kubernetes namespace
            use_cache: Use cached results if available

        Returns:
            List of vector store names
        """
        # Validate input
        try:
            namespace = InputValidator.validate_namespace(namespace, "namespace")
        except ValidationError as e:
            self.logger.error(f"Input validation failed: {e}")
            return []
        
        cache_key = f"domains_{namespace}"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(
                    f"Retrieved {len(cached)} vector stores from cache")
                return cached

        try:
            # Fetch vector_stores using oc command
            result = subprocess.run(
                ["oc", "get", "domains", "-n", namespace, "-o", "json"],
                check=True,
                capture_output=True,
                timeout=30)

            data = json.loads(result.stdout.decode())
            vector_stores = [
                item["metadata"]["name"] for item in data.get("items", [])
            ]

            vector_stores.sort()

            self.console.print(
                f"[green]✓ Fetched {len(vector_stores)} vector_stores from {namespace}[/]"
            )

            # Cache results
            if self.cache_service:
                self.cache_service.set(cache_key,
                                       vector_stores,
                                       ttl_seconds=self.cache_ttl)

            return vector_stores

        except subprocess.CalledProcessError as e:
            error_msg = f"Failed to fetch vector_stores: {e.stderr.decode()}"
            self.console.print(f"[red]✗ {error_msg}[/]")
            self.logger.error(error_msg)
            return []
        except subprocess.TimeoutExpired:
            self.logger.error("Vector store fetch timed out")
            return []
        except Exception as e:
            self.logger.error(f"Error fetching vector stores: {e}")
            return []

    def get_vector_store_details(self,
                                 vector_store_name: str,
                                 namespace: str = "ibm-cas") -> Optional[Dict]:
        """
        Get detailed information about a vector store including assigned users

        Args:
            vector_store_name: Name of the vector store
            namespace: Kubernetes namespace

        Returns:
            Vector store details or None if not found
        """
        # Validate inputs
        try:
            vector_store_name = InputValidator.validate_vector_store_name(vector_store_name, "vector_store_name")
            namespace = InputValidator.validate_namespace(namespace, "namespace")
        except ValidationError as e:
            self.logger.error(f"Input validation failed: {e}")
            return None
        
        try:
            result = subprocess.run([
                "oc", "get", "domain", vector_store_name, "-n", namespace, "-o",
                "json"
            ],
                                    capture_output=True,
                                    timeout=10)

            if result.returncode == 0:
                data = json.loads(result.stdout.decode())

                # Get assigned users for this vector store
                users = self.get_assigned_users(vector_store_name, namespace)

                return {
                    'name':
                        vector_store_name,
                    'namespace':
                        namespace,
                    'created':
                        data.get('metadata', {}).get('creationTimestamp'),
                    'uid':
                        data.get('metadata', {}).get('uid'),
                    'spec':
                        data.get('spec', {}),
                    'status':
                        data.get('status', {}),
                    'assigned_users': {
                        'users': users,
                        'total': len(users)
                    }
                }
        except Exception as e:
            self.logger.error(f"Failed to get vector store details: {e}")

        return None

    def get_assigned_users(self,
                           vector_store_name: str,
                           namespace: str = "ibm-cas",
                           use_cache: bool = True) -> List[str]:
        """
        Fetch all assigned users for a vector store from the domain resource

        Args:
            vector_store_name: Name of the vector store
            namespace: Kubernetes namespace
            use_cache: Use cached results if available

        Returns:
            List of validated assigned usernames
        """
        # Validate inputs
        try:
            vector_store_name = InputValidator.validate_vector_store_name(vector_store_name, "vector_store_name")
            namespace = InputValidator.validate_namespace(namespace, "namespace")
        except ValidationError as e:
            self.logger.error(f"Input validation failed: {e}")
            return []
        
        cache_key = f"domain_users_{vector_store_name}"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(
                    f"Retrieved assigned users from cache for {vector_store_name}"
                )
                return cached

        try:
            # Fetch CRAC using oc command
            result = subprocess.run([
                "oc", "get", "casresourceaccesscontrols.cas.isf.ibm.com", "-n", namespace, "-o",
                "json"
            ],
                                    capture_output=True,
                                    timeout=10)

            if result.returncode == 0:
                data = json.loads(result.stdout.decode())

                items = data.get('items', [])

                # Find the CasResourceAccessControl for this specific vector store
                item = None
                for resource in items:
                    resource_ref = resource.get('spec',
                                                {}).get('resourceRef', {})
                    if resource_ref.get('name') == vector_store_name:
                        item = resource
                        break

                if not item:
                    self.logger.warning(
                        f"No CasResourceAccessControl found for vector store '{vector_store_name}'"
                    )
                    return []

                # Extract assigned users from spec.subjects.users
                users = item.get('spec', {}).get('subjects',
                                                 {}).get('users', [])
                usernames = [
                    user.get('name') for user in users if user.get('name')
                ]

                # Check validation status from status.conditions
                validated_users = []
                conditions = item.get('status', {}).get('conditions', [])
                for condition in conditions:
                    if condition.get(
                            'type') == 'ValidatedUsers' and condition.get(
                                'status') == 'True':
                        # Users are validated
                        validated_users = usernames
                        break

                # Update the in-memory cache
                self.vector_store_assignments[vector_store_name] = {
                    'ocp_users': validated_users,
                }

                if validated_users:
                    self.console.print(
                        f"[green]✓ Vector store '{vector_store_name}' has {len(validated_users)} validated user(s)[/]"
                    )
                else:
                    self.console.print(
                        f"[yellow]ℹ No validated users assigned to vector store '{vector_store_name}'[/]"
                    )

                # Cache results
                if self.cache_service:
                    self.cache_service.set(cache_key,
                                           validated_users,
                                           ttl_seconds=self.cache_ttl)

                return validated_users

        except subprocess.CalledProcessError as e:
            self.logger.error(
                f"Failed to fetch domain {vector_store_name}: {e}")
        except Exception as e:
            self.logger.error(f"Error fetching assigned users: {e}")

        self.console.print(
            f"[yellow]ℹ Could not fetch users for vector store '{vector_store_name}'[/]"
        )
        return []

    def sync_vector_stores(self, namespace: str = "ibm-cas") -> int:
        """
        Sync vector stores (force cache refresh)

        Args:
            namespace: Kubernetes namespace

        Returns:
            Number of vector stores found
        """
        if self.cache_service:
            self.cache_service.delete(f"domains_{namespace}")

        vector_stores = self.list_vector_stores(namespace, use_cache=False)
        return len(vector_stores)
