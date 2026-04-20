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


class VectorStoreService:
    """Enhanced vector store management service with proper user assignment"""

    def __init__(self,
                 config: dict,
                 auth_service,
                 logger: logging.Logger,
                 cache_service=None,
                 console: Console = None):
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

        # In-memory storage for vector store assignments (local cache)
        # Format: {vector_store_name: {ocp_users: [...], keycloak_users: [...]}}
        self.vector_store_assignments = {}

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
                ocp_users, keycloak_users = self.get_assigned_users_detailed(
                    vector_store_name)

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
                        'ocp': ocp_users,
                        'keycloak': keycloak_users,
                        'total': len(ocp_users) + len(keycloak_users)
                    }
                }
        except Exception as e:
            self.logger.error(f"Failed to get vector store details: {e}")

        return None

    def get_assigned_users(self,
                           vector_store_name: str,
                           use_cache: bool = True) -> List[str]:
        """
        Fetch all assigned users for a vector store (OCP + Keycloak)

        Args:
            vector_store_name: Name of the vector store
            use_cache: Use cached results if available

        Returns:
            List of assigned usernames
        """
        cache_key = f"domain_users_{vector_store_name}"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(
                    f"Retrieved assigned users from cache for {vector_store_name}"
                )
                return cached

        # Get from local assignment tracking first
        users = []
        if vector_store_name in self.vector_store_assignments:
            users.extend(
                self.vector_store_assignments[vector_store_name]['ocp_users'])
            users.extend(self.vector_store_assignments[vector_store_name]
                         ['keycloak_users'])

        # Try to fetch from CAS API as well
        try:
            #TODO: "Could not reach CAS API" error probably due to wrong URL
            url = f"{self.api_base}/resource-access-controls"
            headers = {"Authorization": f"Bearer {self.auth_service.token}"}

            resp = requests.get(url, headers=headers, verify=False, timeout=30)

            if resp.status_code == 200:
                data = resp.json()

                # Filter entries by vector_store_name
                vector_store_entries = [
                    entry for entry in data.get("items", [])
                    if entry.get("type") == "Domain" and
                    entry.get("name") == vector_store_name
                ]

                api_users = []
                for entry in vector_store_entries:
                    api_users += [u["name"] for u in entry.get("users", [])]

                # Merge with local users
                all_users = sorted(set(users + api_users))

                if all_users:
                    self.console.print(
                        f"[green]✓ Vector store '{vector_store_name}' has {len(all_users)} assigned user(s)[/]"
                    )
                else:
                    self.console.print(
                        f"[yellow]ℹ No users assigned to vector store '{vector_store_name}'[/]"
                    )

                # Cache results
                if self.cache_service:
                    self.cache_service.set(cache_key,
                                           all_users,
                                           ttl_seconds=self.cache_ttl)

                return all_users

        except Exception as e:
            self.logger.warning(f"Could not fetch from CAS API: {e}")

        # If no API results, use local tracking
        if users:
            users = sorted(set(users))
            self.console.print(
                f"[cyan]Vector store '{vector_store_name}' assigned users: {', '.join(users)}[/]"
            )

            # Cache results
            if self.cache_service:
                self.cache_service.set(cache_key,
                                       users,
                                       ttl_seconds=self.cache_ttl)

            return users
        else:
            self.console.print(
                f"[yellow]ℹ No users currently assigned to vector store '{vector_store_name}'[/]"
            )
            return []

    def get_assigned_users_detailed(self, vector_store_name: str) -> tuple:
        """
        Get assigned users separated by type (OCP and Keycloak)

        Args:
            vector_store_name: Name of the vector store

        Returns:
            Tuple of (ocp_users, keycloak_users)
        """
        ocp_users = []
        keycloak_users = []

        if vector_store_name in self.vector_store_assignments:
            ocp_users = self.vector_store_assignments[vector_store_name].get(
                'ocp_users', [])
            keycloak_users = self.vector_store_assignments[
                vector_store_name].get('keycloak_users', [])

        return ocp_users, keycloak_users

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

    def display_vector_store_assignments(self, vector_store_name: str):
        """
        Display formatted vector store assignments

        Args:
            vector_store_name: Name of the vector store
        """
        ocp_users, keycloak_users = self.get_assigned_users_detailed(
            vector_store_name)

        table_data = {
            'Vector store':
                vector_store_name,
            'OCP Users':
                ', '.join(ocp_users) if ocp_users else 'None',
            'Keycloak Users':
                ', '.join(keycloak_users) if keycloak_users else 'None',
            'Total Users':
                len(ocp_users) + len(keycloak_users)
        }

        info_str = "\n".join([f"{k}: {v}" for k, v in table_data.items()])
        self.console.print(f"\n[cyan]{info_str}[/]\n")

        return table_data
