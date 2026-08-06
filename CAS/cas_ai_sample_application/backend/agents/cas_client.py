"""
CAS Client — Content Aware Storage Client.

Responsibilities:
  1. Build correctly-formed CAS API URLs from a raw user-supplied endpoint.
  2. Retrieve the list of available vector stores.
  3. Search a specific vector store and apply a client-side min-score filter.

Credentials are injected after construction via configure() so that a single
CASClient class can be instantiated once and re-configured per HTTP request
without requiring the caller to pass secrets through every constructor chain.
"""

from typing import Any, Dict, Optional
import logging
import os
import requests
import urllib3

from utils.exceptions import CASClientError

logger = logging.getLogger(__name__)

# CAS clusters are deployed with self-signed certificates by default, so SSL
# verification is disabled here. Set CAS_VERIFY_SSL=true if your cluster has
# a trusted certificate installed.
_CAS_VERIFY_SSL = os.getenv("CAS_VERIFY_SSL", "false").lower() == "true"
if not _CAS_VERIFY_SSL:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class CASClient:
    """
    CAS Client for interacting with IBM Content Aware Storage.
    Credentials are provided via configure() after construction.
    """

    def __init__(self):
        """Initialize CAS client — credentials must be set via configure()"""
        self._configured = False
        self._api_key: Optional[str] = None
        self._cas_endpoint: Optional[str] = None

    def _build_cas_url(self, path: str) -> str:
        """Build the full CAS API URL for a given path suffix.

        Args:
            path: Path suffix to append, e.g. "/vector_stores".

        Returns:
            Fully-qualified CAS API URL string.

        Raises:
            CASClientError: If the client has not been configured with an endpoint.
        """
        if not self._cas_endpoint:
            raise CASClientError("CAS endpoint not configured — call configure() first")

        domain = self._cas_endpoint.strip().rstrip('/')

        if domain.endswith('/cas/api/v1'):
            base_url = domain
        else:
            # Remove https:// or http:// if present
            if domain.startswith('https://'):
                domain = domain[8:]
            elif domain.startswith('http://'):
                domain = domain[7:]

            # Remove any path after the domain
            if '/' in domain:
                domain = domain.split('/')[0]

            base_url = f"https://{domain}/cas/api/v1"

        return f"{base_url}{path}"

    def list_vector_stores(self) -> Dict[str, Any]:
        """
        List available vector stores.

        Returns:
            Dict with status and vector stores list
        """
        if not self.is_configured():
            return {
                "status": "error",
                "error": "Client not configured. Check CAS_API_KEY and CAS_ENDPOINT in .env"
            }

        try:
            vector_stores_url = self._build_cas_url("/vector_stores")
            headers = {
                'Authorization': f'Bearer {self._api_key}',
                'Accept': 'application/json'
            }

            timeout = int(os.getenv('CAS_TIMEOUT', 30))

            response = requests.get(
                vector_stores_url,
                headers=headers,
                timeout=timeout,
                verify=_CAS_VERIFY_SSL,
            )

            if response.status_code == 200:
                vs_data = response.json()
                vector_stores = vs_data.get("data", []) if isinstance(vs_data, dict) else vs_data

                return {
                    "status": "success",
                    "vector_stores": vector_stores,
                }
            else:
                return {
                    "status": "error",
                    "error": f"Failed to list vector stores: status {response.status_code}",
                    "details": response.text,
                    "http_status": response.status_code,
                }

        except CASClientError:
            raise
        except Exception as e:
            logger.warning("list_vector_stores_exception error=%r", e)
            return {
                "status": "error",
                "error": str(e),
            }

    def search_vector_store(
        self,
        vector_store_id: str,
        query: str,
        max_num_results: int = 10,
        min_score: float = 0.0,
        filters: Optional[Dict] = None,
        ranking_options: Optional[Dict] = None,
    ) -> Dict[str, Any]:
        """
        Search within a specific vector store.

        Args:
            vector_store_id: ID of the vector store to search
            query: Search query text
            max_num_results: Maximum number of results to return (default: 10)
            min_score: Minimum probability score threshold (default: 0.0)
            filters: Optional filters to apply
            ranking_options: Optional ranking options

        Returns:
            Dict with status and filtered search results
        """
        if not self.is_configured():
            return {
                "status": "error",
                "error": "Client not configured. Check CAS_API_KEY and CAS_ENDPOINT in .env"
            }

        try:
            search_url = self._build_cas_url(f"/vector_stores/{vector_store_id}/search")
            headers = {
                'Authorization': f'Bearer {self._api_key}',
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }

            payload = {
                "query": query,
                "enable_source": True,
                "enable_content_metadata": True,
            }
            if max_num_results is not None:
                payload["max_num_results"] = max_num_results
            if filters is not None:
                payload["filters"] = filters
            if ranking_options is not None:
                payload["ranking_options"] = ranking_options

            timeout = int(os.getenv('CAS_TIMEOUT', 30))

            response = requests.post(
                search_url,
                headers=headers,
                json=payload,
                timeout=timeout,
                verify=_CAS_VERIFY_SSL,
            )

            if response.status_code == 200:
                data = response.json()
                raw_results = data.get("data", [])
                if min_score > 0.0 and "data" in data:
                    data["data"] = [
                        r for r in raw_results
                        if r.get("score", {}).get("combined_probability_score", 0) >= min_score
                    ]
                return {
                    "status": "success",
                    "data": data.get("data", []),
                }
            else:
                logger.warning("cas_search_failed status=%d body=%r", response.status_code, response.text[:200])
                return {
                    "status": "error",
                    "error": f"Search failed with status {response.status_code}",
                    "details": response.text,
                    "http_status": response.status_code,
                }

        except CASClientError:
            raise
        except Exception as e:
            logger.warning("cas_search_exception error=%r", e)
            return {
                "status": "error",
                "error": str(e)
            }

    # ------------------------------------------------------------------
    # Configuration helpers
    # ------------------------------------------------------------------

    def configure(self, **config: Any) -> None:
        """Configure the CAS client with per-request credentials.

        Accepts keyword arguments so callers are explicit about which fields
        they are setting (api_key=, cas_endpoint=) rather than relying on
        positional order.

        Args:
            api_key: Bearer token for CAS API authentication.
            cas_endpoint: Base URL of the CAS cluster (e.g. https://myhost.example.com).
        """
        self._api_key = config.get("api_key") or self._api_key
        self._cas_endpoint = config.get("cas_endpoint") or self._cas_endpoint

        if self._api_key and self._cas_endpoint:
            self._configured = True
        else:
            logger.warning(
                "cas_client incomplete_configuration endpoint=%r api_key_set=%s",
                self._cas_endpoint,
                bool(self._api_key),
            )

    def is_configured(self) -> bool:
        """Return True if both api_key and cas_endpoint have been supplied."""
        return self._configured
