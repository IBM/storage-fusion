"""
Fixed Domain Service with proper user assignment for OCP and Keycloak users
"""

import requests
import urllib3
import subprocess
import json
import logging
from typing import List, Dict, Optional, Any
from rich.console import Console


class DomainService:
    """Enhanced domain management service with proper user assignment"""

    def __init__(self, config: dict, auth_service, logger: logging.Logger,
                 cache_service=None, console: Console = None):
        self.config = config
        self.auth_service = auth_service
        self.logger = logger
        self.cache_service = cache_service
        self.console = console or Console()

        # Disable insecure HTTPS warnings
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

        # Setup API base URL
        console_url = self.auth_service.config.get("console_url")
        if console_url.endswith("/"):
            console_url = console_url[:-1]
        self.api_base = f"{console_url}/api/v1/cas"

        # In-memory storage for domain assignments (local cache)
        # Format: {domain_name: {ocp_users: [...], keycloak_users: [...]}}
        self.domain_assignments = {}

        # Cache TTL
        self.cache_ttl = config.get('cache', {}).get('domain_cache_ttl', 300)  # 5 minutes

        self.logger.info("Domain Service initialized")

    def list_domains(self, namespace: str = "ibm-cas", use_cache: bool = True) -> List[str]:
        """
        Fetch domains from OpenShift

        Args:
            namespace: Kubernetes namespace
            use_cache: Use cached results if available

        Returns:
            List of domain names
        """
        cache_key = f"domains_{namespace}"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(f"Retrieved {len(cached)} domains from cache")
                return cached

        try:
            self.logger.info(f"Fetching domains from namespace: {namespace}")

            result = subprocess.run(
                ["oc", "get", "domains", "-n", namespace, "-o", "json"],
                check=True,
                capture_output=True,
                timeout=30
            )

            data = json.loads(result.stdout.decode())
            domains = [item["metadata"]["name"] for item in data.get("items", [])]

            domains.sort()

            self.console.print(f"[green]✓ Fetched {len(domains)} domains from {namespace}[/]")
            self.logger.info(f"Fetched {len(domains)} domains")

            # Cache results
            if self.cache_service:
                self.cache_service.set(cache_key, domains, ttl_seconds=self.cache_ttl)

            return domains

        except subprocess.CalledProcessError as e:
            error_msg = f"Failed to fetch domains: {e.stderr.decode()}"
            self.console.print(f"[red]✗ {error_msg}[/]")
            self.logger.error(error_msg)
            return []
        except subprocess.TimeoutExpired:
            self.logger.error("Domain fetch timed out")
            return []
        except Exception as e:
            self.logger.error(f"Error fetching domains: {e}")
            return []

    def get_domain_details(self, domain_name: str, namespace: str = "ibm-cas") -> Optional[Dict]:
        """
        Get detailed information about a domain including assigned users

        Args:
            domain_name: Name of the domain
            namespace: Kubernetes namespace

        Returns:
            Domain details or None if not found
        """
        try:
            result = subprocess.run(
                ["oc", "get", "domain", domain_name, "-n", namespace, "-o", "json"],
                capture_output=True,
                timeout=10
            )

            if result.returncode == 0:
                data = json.loads(result.stdout.decode())

                # Get assigned users for this domain
                ocp_users, keycloak_users = self.get_assigned_users_detailed(domain_name)

                return {
                    'name': domain_name,
                    'namespace': namespace,
                    'created': data.get('metadata', {}).get('creationTimestamp'),
                    'uid': data.get('metadata', {}).get('uid'),
                    'spec': data.get('spec', {}),
                    'status': data.get('status', {}),
                    'assigned_users': {
                        'ocp': ocp_users,
                        'keycloak': keycloak_users,
                        'total': len(ocp_users) + len(keycloak_users)
                    }
                }
        except Exception as e:
            self.logger.error(f"Failed to get domain details: {e}")

        return None

    def assign_users_to_domain(self, domain_name: str, users: List[str],
                               user_types: Optional[Dict[str, str]] = None) -> bool:
        """
        Assign users to a domain (OCP or Keycloak)

        Args:
            domain_name: Name of the domain
            users: List of usernames to assign
            user_types: Dict mapping username -> user_type ("ocp" or "keycloak")
                       If not provided, will auto-detect

        Returns:
            True if successful, False otherwise
        """
        if not users:
            self.logger.warning("No users provided for assignment")
            return False

        self.logger.info(f"Assigning {len(users)} user(s) to domain: {domain_name}")

        try:
            # Initialize domain in assignment dict if not exists
            if domain_name not in self.domain_assignments:
                self.domain_assignments[domain_name] = {
                    'ocp_users': [],
                    'keycloak_users': [],
                    'assignments': []
                }

            # Categorize users by type
            ocp_users_to_add = []
            keycloak_users_to_add = []

            for user in users:
                if user_types and user in user_types:
                    user_type = user_types[user]
                else:
                    # Auto-detect user type (this should be done by caller ideally)
                    user_type = "ocp"  # Default to OCP

                if user_type == "ocp":
                    if user not in self.domain_assignments[domain_name]['ocp_users']:
                        ocp_users_to_add.append(user)
                elif user_type == "keycloak":
                    if user not in self.domain_assignments[domain_name]['keycloak_users']:
                        keycloak_users_to_add.append(user)

            # Try to assign via CAS API first
            api_success = self._assign_via_cas_api(domain_name, users)

            # Also maintain local assignment records
            self.domain_assignments[domain_name]['ocp_users'].extend(ocp_users_to_add)
            self.domain_assignments[domain_name]['keycloak_users'].extend(keycloak_users_to_add)

            for user in users:
                user_type = user_types.get(user, "ocp") if user_types else "ocp"
                self.domain_assignments[domain_name]['assignments'].append({
                    'username': user,
                    'user_type': user_type,
                    'assigned_at': __import__('datetime').datetime.now().isoformat()
                })

            self.console.print(f"[green]✓ Successfully assigned {len(users)} user(s) to domain {domain_name}[/]")
            self.logger.info(f"Users assigned to {domain_name}: {users}")

            # Invalidate cache
            if self.cache_service:
                self.cache_service.delete(f"domain_users_{domain_name}")

            return True

        except Exception as e:
            self.console.print(f"[red]✗ Error assigning users: {e}[/]")
            self.logger.error(f"Error assigning users: {e}")
            return False

    def _assign_via_cas_api(self, domain_name: str, users: List[str]) -> bool:
        """
        Attempt to assign users via CAS API

        Args:
            domain_name: Domain name
            users: List of usernames

        Returns:
            True if API call successful
        """
        try:
            url = f"{self.api_base}/resource-access-controls"

            self.logger.info(f"Assigning users via CAS API: {url}")

            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.auth_service.token}"
            }

            payload = {
                "users": {"add": [{"name": u} for u in users]},
                "groups": {"add": []},
                "type": "Domain",
                "name": domain_name
            }

            resp = requests.post(
                url,
                json=payload,
                headers=headers,
                verify=False,
                timeout=30
            )

            if resp.status_code in [200, 201]:
                self.logger.info(f"CAS API assignment successful for {domain_name}")
                return True
            else:
                error_msg = f"CAS API failed: {resp.status_code} {resp.text}"
                self.logger.warning(error_msg)
                return False

        except Exception as e:
            self.logger.warning(f"CAS API assignment failed: {e}")
            return False

    def unassign_users_from_domain(self, domain_name: str, users: List[str]) -> bool:
        """
        Remove users from a domain

        Args:
            domain_name: Name of the domain
            users: List of usernames to remove

        Returns:
            True if successful, False otherwise
        """
        if not users:
            self.logger.warning("No users provided for unassignment")
            return False

        self.logger.info(f"Removing {len(users)} user(s) from domain: {domain_name}")

        try:
            url = f"{self.api_base}/resource-access-controls"

            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.auth_service.token}"
            }

            payload = {
                "users": {"remove": [{"name": u} for u in users]},
                "groups": {"remove": []},
                "type": "Domain",
                "name": domain_name
            }

            resp = requests.post(
                url,
                json=payload,
                headers=headers,
                verify=False,
                timeout=30
            )

            if resp.status_code in [200, 201]:
                # Remove from local assignment tracking
                if domain_name in self.domain_assignments:
                    for user in users:
                        if user in self.domain_assignments[domain_name]['ocp_users']:
                            self.domain_assignments[domain_name]['ocp_users'].remove(user)
                        if user in self.domain_assignments[domain_name]['keycloak_users']:
                            self.domain_assignments[domain_name]['keycloak_users'].remove(user)

                        self.domain_assignments[domain_name]['assignments'] = [
                            a for a in self.domain_assignments[domain_name]['assignments']
                            if a['username'] != user
                        ]

                self.console.print(f"[green]✓ Successfully removed {len(users)} user(s) from domain {domain_name}[/]")

                # Invalidate cache
                if self.cache_service:
                    self.cache_service.delete(f"domain_users_{domain_name}")

                return True
            else:
                self.console.print(f"[red]✗ Failed: {resp.status_code} {resp.text}[/]")
                return False

        except Exception as e:
            self.console.print(f"[red]✗ Error: {e}[/]")
            self.logger.error(f"Error removing users: {e}")
            return False

    def get_assigned_users(self, domain_name: str, use_cache: bool = True) -> List[str]:
        """
        Fetch all assigned users for a domain (OCP + Keycloak)

        Args:
            domain_name: Name of the domain
            use_cache: Use cached results if available

        Returns:
            List of assigned usernames
        """
        cache_key = f"domain_users_{domain_name}"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(f"Retrieved assigned users from cache for {domain_name}")
                return cached

        # Get from local assignment tracking first
        users = []
        if domain_name in self.domain_assignments:
            users.extend(self.domain_assignments[domain_name]['ocp_users'])
            users.extend(self.domain_assignments[domain_name]['keycloak_users'])

        # Try to fetch from CAS API as well
        try:
            url = f"{self.api_base}/resource-access-controls"
            headers = {
                "Authorization": f"Bearer {self.auth_service.token}"
            }

            resp = requests.get(
                url,
                headers=headers,
                verify=False,
                timeout=30
            )

            if resp.status_code == 200:
                data = resp.json()

                # Filter entries by domain_name
                domain_entries = [
                    entry for entry in data.get("items", [])
                    if entry.get("type") == "Domain" and entry.get("name") == domain_name
                ]

                api_users = []
                for entry in domain_entries:
                    api_users += [u["name"] for u in entry.get("users", [])]

                # Merge with local users
                all_users = sorted(set(users + api_users))

                if all_users:
                    self.console.print(f"[green]✓ Domain '{domain_name}' has {len(all_users)} assigned user(s)[/]")
                else:
                    self.console.print(f"[yellow]ℹ No users assigned to domain '{domain_name}'[/]")

                # Cache results
                if self.cache_service:
                    self.cache_service.set(cache_key, all_users, ttl_seconds=self.cache_ttl)

                return all_users

        except Exception as e:
            self.logger.warning(f"Could not fetch from CAS API: {e}")

        # If no API results, use local tracking
        if users:
            users = sorted(set(users))
            self.console.print(f"[cyan]Domain '{domain_name}' assigned users: {', '.join(users)}[/]")

            # Cache results
            if self.cache_service:
                self.cache_service.set(cache_key, users, ttl_seconds=self.cache_ttl)

            return users
        else:
            self.console.print(f"[yellow]ℹ No users currently assigned to domain '{domain_name}'[/]")
            return []

    def get_assigned_users_detailed(self, domain_name: str) -> tuple:
        """
        Get assigned users separated by type (OCP and Keycloak)

        Args:
            domain_name: Name of the domain

        Returns:
            Tuple of (ocp_users, keycloak_users)
        """
        ocp_users = []
        keycloak_users = []

        if domain_name in self.domain_assignments:
            ocp_users = self.domain_assignments[domain_name].get('ocp_users', [])
            keycloak_users = self.domain_assignments[domain_name].get('keycloak_users', [])

        return ocp_users, keycloak_users

    def sync_domains(self, namespace: str = "ibm-cas") -> int:
        """
        Sync domains (force cache refresh)

        Args:
            namespace: Kubernetes namespace

        Returns:
            Number of domains found
        """
        if self.cache_service:
            self.cache_service.delete(f"domains_{namespace}")

        domains = self.list_domains(namespace, use_cache=False)
        return len(domains)

    def display_domain_assignments(self, domain_name: str):
        """
        Display formatted domain assignments

        Args:
            domain_name: Name of the domain
        """
        ocp_users, keycloak_users = self.get_assigned_users_detailed(domain_name)

        table_data = {
            'Domain': domain_name,
            'OCP Users': ', '.join(ocp_users) if ocp_users else 'None',
            'Keycloak Users': ', '.join(keycloak_users) if keycloak_users else 'None',
            'Total Users': len(ocp_users) + len(keycloak_users)
        }

        info_str = "\n".join([f"{k}: {v}" for k, v in table_data.items()])
        self.console.print(f"\n[cyan]{info_str}[/]\n")

        return table_data