"""
Fixed Vector Store Service with proper user assignment for OCP and Keycloak users
"""

import json
import logging
import subprocess
from typing import Any, Protocol, cast

import urllib3
from rich.console import Console

from chatbot.utils.validators import InputValidator, ValidationError


class CacheServiceProtocol(Protocol):
    def get(self, key: str) -> Any: ...
    def set(self, key: str, value: Any, ttl_seconds: int) -> None: ...
    def delete(self, key: str) -> bool: ...


class VectorStoreService:
    """Enhanced vector store management service with proper user assignment"""

    def __init__(
        self,
        config: dict[str, Any],
        auth_service: Any,
        logger: logging.Logger,
        cache_service: CacheServiceProtocol | None = None,
        console: Console | None = None,
    ) -> None:
        self.config: dict[str, Any] = config
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
        self.vector_store_assignments: dict[str, dict[str, list[str]]] = {}

        # Cache TTL
        self.cache_ttl = config.get("cache", {}).get(
            "domain_cache_ttl", 300
        )  # 5 minutes

        self.logger.info("Vector Search Service initialized")

    def list_vector_stores(
        self, namespace: str = "ibm-cas", use_cache: bool = True
    ) -> list[str]:
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
                cached_vector_stores = cast(list[str], cached)
                self.logger.debug(
                    f"Retrieved {len(cached_vector_stores)} vector stores from cache"
                )
                return cached_vector_stores

        try:
            # Fetch vector_stores using oc command
            result = subprocess.run(
                ["oc", "get", "domains", "-n", namespace, "-o", "json"],
                check=True,
                capture_output=True,
                timeout=30,
            )

            data = json.loads(result.stdout.decode())
            vector_stores = [item["metadata"]["name"] for item in data.get("items", [])]

            vector_stores.sort()

            # Cache results
            if self.cache_service:
                self.cache_service.set(
                    cache_key, vector_stores, ttl_seconds=self.cache_ttl
                )

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

    def get_vector_store_details(
        self, vector_store_name: str, namespace: str = "ibm-cas"
    ) -> dict[str, Any] | None:
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
            vector_store_name = InputValidator.validate_vector_store_name(
                vector_store_name, "vector_store_name"
            )
            namespace = InputValidator.validate_namespace(namespace, "namespace")
        except ValidationError as e:
            self.logger.error(f"Input validation failed: {e}")
            return None

        try:
            result = subprocess.run(
                [
                    "oc",
                    "get",
                    "domain",
                    vector_store_name,
                    "-n",
                    namespace,
                    "-o",
                    "json",
                ],
                capture_output=True,
                timeout=10,
            )

            if result.returncode == 0:
                data = json.loads(result.stdout.decode())

                # Get assigned users and groups for this vector store
                users = self.get_assigned_users(
                    vector_store_name, namespace, use_cache=False
                )
                groups = self.get_assigned_groups(
                    vector_store_name, namespace, use_cache=False
                )

                return {
                    "name": vector_store_name,
                    "namespace": namespace,
                    "created": data.get("metadata", {}).get("creationTimestamp"),
                    "uid": data.get("metadata", {}).get("uid"),
                    "spec": data.get("spec", {}),
                    "status": data.get("status", {}),
                    "assigned": {
                        "users": users,
                        "total_users": len(users),
                        "groups": groups,
                        "total_groups": len(groups),
                    },
                }
        except Exception as e:
            self.logger.error(f"Failed to get vector store details: {e}")

        return None

    def _get_crac_for_vector_store(
        self, vector_store_name: str, namespace: str
    ) -> dict[str, Any] | None:
        """Fetch the CasResourceAccessControl resource for a vector store."""
        result = subprocess.run(
            [
                "oc",
                "get",
                "casresourceaccesscontrols.cas.isf.ibm.com",
                "-n",
                namespace,
                "-o",
                "json",
            ],
            capture_output=True,
            timeout=10,
        )

        if result.returncode != 0:
            return None

        data = json.loads(result.stdout.decode())
        items = data.get("items", [])

        for resource in items:
            resource_ref = resource.get("spec", {}).get("resourceRef", {})
            if resource_ref.get("name") == vector_store_name:
                return cast(dict[str, Any], resource)

        return None

    def _get_validated_subjects(
        self,
        vector_store_name: str,
        namespace: str,
        subject_type: str,
        validation_type: str,
        assignment_key: str,
        cache_key_prefix: str,
        success_label: str,
    ) -> list[str]:
        """Fetch validated assigned subjects for a vector store."""
        try:
            vector_store_name = InputValidator.validate_vector_store_name(
                vector_store_name, "vector_store_name"
            )
            namespace = InputValidator.validate_namespace(namespace, "namespace")
        except ValidationError as e:
            self.logger.error(f"Input validation failed: {e}")
            return []

        cache_key = f"{cache_key_prefix}_{vector_store_name}"

        if self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(
                    f"Retrieved assigned {subject_type} from cache for {vector_store_name}"
                )
                return cast(list[str], cached)

        try:
            item = self._get_crac_for_vector_store(vector_store_name, namespace)

            if not item:
                self.logger.warning(
                    f"No CasResourceAccessControl found for vector store '{vector_store_name}'"
                )
                return []

            subjects = item.get("spec", {}).get("subjects", {}).get(subject_type, [])
            subject_names = [
                subject.get("name") for subject in subjects if subject.get("name")
            ]

            validated_subjects = []
            conditions = item.get("status", {}).get("conditions", [])
            for condition in conditions:
                if (
                    condition.get("type") == validation_type
                    and condition.get("status") == "True"
                ):
                    validated_subjects = subject_names
                    break

            assignments = self.vector_store_assignments.setdefault(
                vector_store_name, {}
            )
            assignments[assignment_key] = validated_subjects

            if validated_subjects:
                self.console.print(
                    f"[green]✓ Vector store '{vector_store_name}' has {len(validated_subjects)} validated {success_label}(s)[/]"
                )
            else:
                self.console.print(
                    f"[yellow]ℹ No validated {success_label}s assigned to vector store '{vector_store_name}'[/]"
                )

            if self.cache_service:
                self.cache_service.set(
                    cache_key, validated_subjects, ttl_seconds=self.cache_ttl
                )

            return validated_subjects

        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to fetch domain {vector_store_name}: {e}")
        except Exception as e:
            self.logger.error(f"Error fetching assigned {subject_type}: {e}")

        self.console.print(
            f"[yellow]ℹ Could not fetch {subject_type} for vector store '{vector_store_name}'[/]"
        )
        return []

    def get_assigned_users(
        self, vector_store_name: str, namespace: str = "ibm-cas", use_cache: bool = True
    ) -> list[str]:
        """
        Fetch all assigned users for a vector store from the domain resource

        Args:
            vector_store_name: Name of the vector store
            namespace: Kubernetes namespace
            use_cache: Use cached results if available

        Returns:
            List of validated assigned usernames
        """
        if not use_cache and self.cache_service:
            self.cache_service.delete(f"domain_users_{vector_store_name}")

        return self._get_validated_subjects(
            vector_store_name=vector_store_name,
            namespace=namespace,
            subject_type="users",
            validation_type="ValidatedUsers",
            assignment_key="ocp_users",
            cache_key_prefix="domain_users",
            success_label="user",
        )

    def get_assigned_groups(
        self, vector_store_name: str, namespace: str = "ibm-cas", use_cache: bool = True
    ) -> list[str]:
        """
        Fetch all assigned groups for a vector store from the domain resource

        Args:
            vector_store_name: Name of the vector store
            namespace: Kubernetes namespace
            use_cache: Use cached results if available

        Returns:
            List of validated assigned group names
        """
        if not use_cache and self.cache_service:
            self.cache_service.delete(f"domain_groups_{vector_store_name}")

        return self._get_validated_subjects(
            vector_store_name=vector_store_name,
            namespace=namespace,
            subject_type="groups",
            validation_type="ValidatedGroups",
            assignment_key="groups",
            cache_key_prefix="domain_groups",
            success_label="group",
        )

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
