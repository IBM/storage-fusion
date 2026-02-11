"""
Health Check Utility - Monitor service health
"""

import logging
import subprocess
from typing import Dict, Any
from datetime import datetime


class HealthChecker:
    """Check health status of all services"""

    def __init__(self, services: Dict[str, Any], logger: logging.Logger):
        self.services = services
        self.logger = logger

    def run_all_checks(self) -> Dict[str, Dict[str, Any]]:
        """Run health checks on all services"""
        results = {}

        checks = [
            ('auth', self.check_auth_service),
            ('cache', self.check_cache_service),
            ('user', self.check_user_service),
            ('domain', self.check_domain_service),
            ('query', self.check_query_service),
            ('llm', self.check_llm_service),
            ('oc_cli', self.check_oc_cli)
        ]

        for service_name, check_func in checks:
            try:
                results[service_name] = check_func()
            except Exception as e:
                results[service_name] = {
                    'healthy': False,
                    'message': f'Check failed: {str(e)}',
                    'timestamp': datetime.now().isoformat()
                }

        return results

    def check_auth_service(self) -> Dict[str, Any]:
        """Check authentication service"""
        auth = self.services.get('auth')

        if not auth:
            return self._unhealthy("Service not initialized")

        if not auth.token:
            return self._unhealthy("No authentication token")

        return self._healthy("Authenticated")

    def check_cache_service(self) -> Dict[str, Any]:
        """Check cache service"""
        cache = self.services.get('cache')

        if not cache:
            return self._unhealthy("Service not initialized")

        stats = cache.get_statistics()
        message = f"{stats['entries']} entries, {stats['hit_rate_percent']}% hit rate"

        return self._healthy(message)

    def check_user_service(self) -> Dict[str, Any]:
        """Check user service"""
        user_service = self.services.get('user')

        if not user_service:
            return self._unhealthy("Service not initialized")

        try:
            # Try to fetch users
            users = user_service.list_oc_users()
            return self._healthy(f"Connected, {len(users)} OCP users")
        except Exception as e:
            return self._unhealthy(f"Cannot fetch users: {str(e)}")

    def check_domain_service(self) -> Dict[str, Any]:
        """Check domain service"""
        domain_service = self.services.get('domain')

        if not domain_service:
            return self._unhealthy("Service not initialized")

        try:
            domains = domain_service.list_domains()
            return self._healthy(f"{len(domains)} domains available")
        except Exception as e:
            return self._unhealthy(f"Cannot fetch domains: {str(e)}")

    def check_query_service(self) -> Dict[str, Any]:
        """Check query service"""
        query_service = self.services.get('query')

        if not query_service:
            return self._unhealthy("Service not initialized")

        # Check if CAS URL is configured
        if not query_service.config.get('cas_url'):
            return self._unhealthy("CAS URL not configured")

        return self._healthy("Configured")

    def check_llm_service(self) -> Dict[str, Any]:
        """Check LLM service"""
        llm_service = self.services.get('llm')

        if not llm_service:
            return self._unhealthy("Service not initialized")

        providers = llm_service.config.get('llm_provider_sequence', [])

        if not providers:
            return self._unhealthy("No LLM providers configured")

        return self._healthy(f"Providers: {', '.join(providers)}")

    def check_oc_cli(self) -> Dict[str, Any]:
        """Check if oc CLI is available"""
        try:
            result = subprocess.run(
                ['oc', 'version'],
                capture_output=True,
                timeout=5
            )

            if result.returncode == 0:
                version = result.stdout.decode().split('\n')[0]
                return self._healthy(f"Installed: {version}")
            else:
                return self._unhealthy("oc CLI not responding")

        except FileNotFoundError:
            return self._unhealthy("oc CLI not installed")
        except subprocess.TimeoutExpired:
            return self._unhealthy("oc CLI timeout")
        except Exception as e:
            return self._unhealthy(f"Error: {str(e)}")

    def _healthy(self, message: str) -> Dict[str, Any]:
        """Return healthy status"""
        return {
            'healthy': True,
            'message': message,
            'timestamp': datetime.now().isoformat()
        }

    def _unhealthy(self, message: str) -> Dict[str, Any]:
        """Return unhealthy status"""
        return {
            'healthy': False,
            'message': message,
            'timestamp': datetime.now().isoformat()
        }