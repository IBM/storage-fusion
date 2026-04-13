"""
Enhanced User Service with caching and improved error handling
"""

import subprocess
import json
import logging
from typing import List, Dict, Optional


class UserService:
    """Enhanced user service with caching support"""

    def __init__(self, config: dict, auth_service, logger: logging.Logger, cache_service=None):
        self.config = config
        self.auth_service = auth_service
        self.logger = logger
        self.cache_service = cache_service

        # Cache TTL in seconds
        self.cache_ttl = config.get('cache', {}).get('user_cache_ttl', 600)  # 10 minutes

    def list_oc_users(self, use_cache: bool = True) -> List[str]:
        """
        List all users in OpenShift cluster

        Args:
            use_cache: Use cached results if available

        Returns:
            List of usernames
        """
        cache_key = "users_ocp"

        # Check cache
        if use_cache and self.cache_service:
            cached = self.cache_service.get(cache_key)
            if cached is not None:
                self.logger.debug(f"Retrieved {len(cached)} OCP users from cache")
                return cached

        try:
            self.logger.info("Fetching OCP users from cluster")

            result = subprocess.run(
                ["oc", "get", "users", "-o", "json"],
                check=True,
                capture_output=True,
                timeout=30
            )

            data = json.loads(result.stdout.decode())
            users = [u["metadata"]["name"] for u in data.get("items", [])]

            # Sort for consistency
            users.sort()

            self.logger.info(f"Fetched {len(users)} OCP users")

            # Cache results
            if self.cache_service:
                self.cache_service.set(cache_key, users, ttl_seconds=self.cache_ttl)

            return users

        except subprocess.CalledProcessError as e:
            error_msg = f"Failed to fetch OCP users: {e.stderr.decode()}"
            self.logger.error(error_msg)
            return []
        except subprocess.TimeoutExpired:
            self.logger.error("OCP user fetch timed out")
            return []
        except json.JSONDecodeError as e:
            self.logger.error(f"Failed to parse OCP users response: {e}")
            return []
        except Exception as e:
            self.logger.error(f"Unexpected error fetching OCP users: {e}")
            return []

    def get_user_details(self, username: str) -> Optional[Dict]:
        """
        Get detailed information about a user

        Args:
            username: Username to lookup

        Returns:
            User details dictionary or None if not found
        """
        # Try OCP
        try:
            result = subprocess.run(
                ["oc", "get", "user", username, "-o", "json"],
                capture_output=True,
                timeout=10
            )

            if result.returncode == 0:
                user_data = json.loads(result.stdout.decode())
                return {
                    'source': 'ocp',
                    'username': username,
                    'uid': user_data.get('metadata', {}).get('uid'),
                    'created': user_data.get('metadata', {}).get('creationTimestamp'),
                    'identities': user_data.get('identities', [])
                }
        except Exception as e:
            self.logger.debug(f"User not found in OCP: {e}")

        return None

    def search_users(self, query: str, use_cache: bool = True) -> List[str]:
        """
        Search for users matching query

        Args:
            query: Search query (case-insensitive)
            use_cache: Use cached user lists

        Returns:
            List of matching usernames
        """
        query_lower = query.lower()

        ocp_users = self.list_oc_users(use_cache=use_cache)

        all_users = set(ocp_users)

        matches = [u for u in all_users if query_lower in u.lower()]
        matches.sort()

        return matches

    def sync_users(self) -> Dict[str, int]:
        """
        Sync users from all sources (force cache refresh)

        Returns:
            Dictionary with sync statistics
        """
        self.logger.info("Syncing users from all sources")

        # Clear cache
        if self.cache_service:
            self.cache_service.delete("users_ocp")

        # Fetch fresh data
        ocp_users = self.list_oc_users(use_cache=False)
        stats = {
            'ocp_count': len(ocp_users),
            'total_unique': len(set(ocp_users))
        }

        self.logger.info(f"User sync complete: {stats}")
        return stats