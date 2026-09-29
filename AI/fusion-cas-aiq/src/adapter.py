# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""
IBM Fusion CAS — NAT retriever provider and client.

Registers _type: fusion_cas in the retrievers: section of any workflow YAML.

Single store (backward-compatible):

    retrievers:
      fusion_cas_store:
        _type: fusion_cas
        fusion_url: ${FUSION_CAS_URL:-}
        vector_store: ${FUSION_VECTOR_STORE:-}
        token: ${FUSION_CAS_TOKEN:-}
        top_k: 5

Multiple stores — results from all stores are merged and re-ranked by score:

    retrievers:
      fusion_cas_store:
        _type: fusion_cas
        fusion_url: ${FUSION_CAS_URL:-}
        vector_stores:
          - farming-docs
          - machinery-docs
          - weather-data
        token: ${FUSION_CAS_TOKEN:-}
        top_k: 5

    functions:
      knowledge_search:
        _type: nat_retriever
        retriever: fusion_cas_store

API reference:
    POST /cas/api/v1/vector_stores/{vector_store}/search
    Headers: Authorization: Bearer <token>
    Body:    {"query": str, "max_num_results": int,
              "enable_source": true, "enable_content_metadata": true}
    Response: {"data": [{"filename", "score": {"combined_probability_score"},
                         "content": [{"type", "text", "metadata": {"page"}}]}]}
"""

import asyncio
import logging
import os
from functools import partial
from pathlib import Path
from typing import Any

import requests
import urllib3
from pydantic import Field
from pydantic import SecretStr
from pydantic import model_validator
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from nat.builder.builder import Builder
from nat.builder.retriever import RetrieverProviderInfo
from nat.cli.register_workflow import register_retriever_client
from nat.cli.register_workflow import register_retriever_provider
from nat.data_models.retriever import RetrieverBaseConfig
from nat.retriever.interface import Retriever
from nat.retriever.models import Document
from nat.retriever.models import RetrieverOutput

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Config — _type: fusion_cas in the retrievers: section
# ---------------------------------------------------------------------------


class FusionCASRetrieverConfig(RetrieverBaseConfig, name="fusion_cas"):
    """Configuration for the IBM Fusion CAS retriever.

    Supports a single vector store (backward-compatible ``vector_store`` field)
    **or** a list of stores (``vector_stores``).  When both are supplied,
    ``vector_stores`` takes precedence.  The resolved list is available as
    ``effective_vector_stores`` after model validation.

    For UI-driven per-store selection use ``source_id_store_map`` to map each
    data-source registry ID (e.g. ``fusion_cas_farming``) to a Fusion CAS
    vector store name.  At search time the caller can pass
    ``enabled_source_ids`` as a keyword argument; the retriever intersects that
    list with the map and fans out only to the enabled stores in parallel.
    """

    fusion_url: str = Field(
        default_factory=lambda: os.environ.get("FUSION_CAS_URL", ""),
        description="Base URL of the Fusion CAS service, e.g. https://ibm-cas-...apps.cluster.ibm.com",
    )
    vector_store: str | None = Field(
        default=None,
        description=(
            "Single vector store name (backward-compatible). "
            "Ignored when vector_stores is also set. "
            "Falls back to the FUSION_VECTOR_STORE env var when None."
        ),
    )
    vector_stores: list[str] = Field(
        default_factory=list,
        description=(
            "List of vector store names to search. When non-empty this takes precedence "
            "over vector_store. Results from all stores are merged and re-ranked by score."
        ),
    )
    source_id_store_map: dict[str, str] = Field(
        default_factory=dict,
        description=(
            "Mapping of data-source registry ID → Fusion CAS vector store name. "
            "Used by the knowledge_retrieval function to resolve which stores to query "
            "based on the data_sources selected by the user in the AI-Q UI. "
            'Example: {"fusion_cas_farming": "farming-docs", '
            '"fusion_cas_machinery": "machinery-docs"}. '
            "When non-empty, an enabled_source_ids kwarg passed to search() takes "
            "precedence over vector_stores/vector_store."
        ),
    )
    token: SecretStr | None = Field(
        default=None,
        description="Bearer token. When None the FUSION_CAS_TOKEN env var is used.",
    )
    token_file: str | None = Field(
        default=None,
        description="Path to a file containing the bearer token (e.g. a mounted Kubernetes Secret).",
    )
    top_k: int = Field(
        default=5,
        gt=0,
        le=50,
        description="Default number of results to return.",
    )
    timeout: int = Field(
        default=120,
        description="HTTP request timeout in seconds.",
    )
    verify_ssl: bool = Field(
        default=True,
        description="Verify TLS certificates. Set false only for self-signed lab clusters.",
    )

    # Resolved list — set by the validator below; never supplied directly in YAML.
    effective_vector_stores: list[str] = Field(default_factory=list, exclude=True)

    @model_validator(mode="after")
    def _resolve_vector_stores(self) -> "FusionCASRetrieverConfig":
        """Merge scalar and list fields into effective_vector_stores."""
        if self.vector_stores:
            self.effective_vector_stores = list(self.vector_stores)
            return self
        # scalar field: use it, or fall back to the env var if field was not set in YAML
        scalar = self.vector_store or os.environ.get("FUSION_VECTOR_STORE", "")
        if scalar:
            self.effective_vector_stores = [scalar]
        else:
            # Neither field set — leave empty; the retriever will warn at search time.
            self.effective_vector_stores = []
        return self


# ---------------------------------------------------------------------------
# Retriever client — implements the standard NAT Retriever interface
# ---------------------------------------------------------------------------


def _make_session(timeout: int, verify_ssl: bool) -> requests.Session:
    session = requests.Session()
    session.verify = verify_ssl
    retries = Retry(total=3, backoff_factor=0.5, status_forcelist=[500, 502, 503, 504], allowed_methods=["POST"])
    adapter = HTTPAdapter(max_retries=retries)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


class FusionCASRetriever(Retriever):
    """NAT Retriever implementation for IBM Fusion CAS.

    When multiple vector stores are configured the retriever fans out one
    concurrent HTTP search per store, merges all results, re-ranks them by
    descending ``score``, and returns the top ``top_k`` documents overall.
    """

    def __init__(self, config: FusionCASRetrieverConfig) -> None:
        self._config = config
        self._fusion_url = config.fusion_url.rstrip("/")
        self._session = _make_session(config.timeout, config.verify_ssl)
        stores = config.effective_vector_stores
        logger.info(
            "FusionCASRetriever initialized: url=%s stores=%s",
            self._fusion_url,
            stores,
        )

    def _resolve_token(self) -> str:
        if self._config.token:
            return self._config.token.get_secret_value()
        token_file = self._config.token_file or os.environ.get("FUSION_CAS_TOKEN_FILE")
        if token_file:
            return Path(token_file).read_text().strip()
        return os.environ.get("FUSION_CAS_TOKEN", "")

    def _headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        token = self._resolve_token()
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return headers

    async def _search_one_store(self, query: str, vector_store: str, top_k: int) -> list[Document]:
        """Search a single vector store and return a list of Documents."""
        endpoint = f"{self._fusion_url}/cas/api/v1/vector_stores/{vector_store}/search"
        payload: dict[str, Any] = {
            "query": query,
            "max_num_results": top_k,
            "enable_source": True,
            "enable_content_metadata": True,
        }
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            partial(self._session.post, endpoint, json=payload, headers=self._headers(), timeout=self._config.timeout),
        )
        response.raise_for_status()
        data = response.json() or {}
        docs = [d for d in (_parse_document(item, vector_store) for item in data.get("data", [])) if d]
        logger.debug("FusionCASRetriever: store=%s returned %d docs", vector_store, len(docs))
        return docs

    async def search(self, query: str, **kwargs) -> RetrieverOutput:
        """Search one or more Fusion CAS vector stores and return a merged RetrieverOutput.

        Keyword args (all optional):
            top_k (int): Override the configured default number of results.
            collection_name (str): Search exactly this store (backward-compatible
                single-store override used by the legacy ``nat_retriever`` path).
            enabled_source_ids (list[str]): Data-source registry IDs selected by
                the user in the AI-Q UI.  When supplied, the retriever looks each
                ID up in ``config.source_id_store_map`` and fans out only to the
                matching stores in parallel — giving true single-call parallelism
                instead of serial LLM tool calls.
        """
        top_k = kwargs.get("top_k", self._config.top_k)

        # Priority 1: UI-driven selection via source_id_store_map.
        enabled_source_ids: list[str] | None = kwargs.get("enabled_source_ids")
        if enabled_source_ids is not None and self._config.source_id_store_map:
            stores = [
                self._config.source_id_store_map[sid]
                for sid in enabled_source_ids
                if sid in self._config.source_id_store_map
            ]
            if not stores:
                logger.warning(
                    "FusionCASRetriever: none of the enabled_source_ids %s matched source_id_store_map; "
                    "falling back to configured store list",
                    enabled_source_ids,
                )
                stores = self._config.effective_vector_stores
        # Priority 2: per-call single-store override (legacy nat_retriever path).
        elif kwargs.get("collection_name"):
            stores = [kwargs["collection_name"]]
        # Priority 3: static list from config.
        else:
            stores = self._config.effective_vector_stores

        if not stores:
            logger.warning("FusionCASRetriever: no vector stores configured, returning empty result")
            return RetrieverOutput(results=[])

        if len(stores) == 1:
            # Fast path — no fan-out overhead.
            docs = await self._search_one_store(query, stores[0], top_k)
            return RetrieverOutput(results=docs[:top_k])

        # Fan-out: search all stores concurrently, each asking for top_k results.
        # After merging we re-rank and truncate to top_k overall.
        tasks = [self._search_one_store(query, store, top_k) for store in stores]
        per_store_results = await asyncio.gather(*tasks, return_exceptions=True)

        merged: list[Document] = []
        for store, result in zip(stores, per_store_results):
            if isinstance(result, Exception):
                logger.error("FusionCASRetriever: search failed for store=%s: %s", store, result)
            else:
                merged.extend(result)

        # Re-rank by descending score (metadata["score"] set by _parse_document).
        merged.sort(key=lambda doc: float((doc.metadata or {}).get("score", 0.0)), reverse=True)
        logger.info(
            "FusionCASRetriever: merged %d docs from %d stores, returning top %d",
            len(merged),
            len(stores),
            top_k,
        )
        return RetrieverOutput(results=merged[:top_k])


def _parse_document(item: Any, vector_store: str = "") -> Document | None:
    """Convert one Fusion CAS search result into a NAT Document."""
    if not isinstance(item, dict):
        return None

    filename = item.get("filename", "unknown")

    score_obj = item.get("score") or {}
    score = float(
        score_obj.get("combined_probability_score") or score_obj.get("score") or 0.0
        if isinstance(score_obj, dict)
        else score_obj or 0.0
    )

    content_items = item.get("content") or []
    text_parts: list[str] = []
    page_number: int | None = None

    for ci in content_items:
        if isinstance(ci, dict):
            if ci.get("type") == "text":
                text_parts.append(ci.get("text", ""))
            if page_number is None:
                raw_page = (ci.get("metadata") or {}).get("page")
                if isinstance(raw_page, int) and raw_page > 0:
                    page_number = raw_page

    page_content = "\n".join(t for t in text_parts if t).strip()

    return Document(
        page_content=page_content,
        metadata={
            "filename": filename,
            "page_number": page_number,
            "score": max(0.0, min(1.0, score)),
            "file_id": item.get("file_id"),
            "vector_store": vector_store,
        },
    )


# ---------------------------------------------------------------------------
# NAT provider + client registration (mirrors nemo_retriever/register.py)
# ---------------------------------------------------------------------------


@register_retriever_provider(config_type=FusionCASRetrieverConfig)
async def fusion_cas_retriever_provider(config: FusionCASRetrieverConfig, builder: Builder):
    yield RetrieverProviderInfo(config=config, description="IBM Fusion CAS vector store retriever")


@register_retriever_client(config_type=FusionCASRetrieverConfig, wrapper_type=None)
async def fusion_cas_retriever_client(config: FusionCASRetrieverConfig, builder: Builder):
    yield FusionCASRetriever(config)
