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

Registers _type: fusion_cas in the retrievers: section of any workflow YAML:

    retrievers:
      fusion_cas_store:
        _type: fusion_cas
        fusion_url: ${FUSION_CAS_URL:-}
        vector_store: ${FUSION_VECTOR_STORE:-}
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
    """Configuration for the IBM Fusion CAS retriever."""

    fusion_url: str = Field(
        default_factory=lambda: os.environ.get("FUSION_CAS_URL", ""),
        description="Base URL of the Fusion CAS service, e.g. https://ibm-cas-...apps.cluster.ibm.com",
    )
    vector_store: str = Field(
        default_factory=lambda: os.environ.get("FUSION_VECTOR_STORE", ""),
        description="Vector store name (case-sensitive, must match the Fusion UI).",
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
    """NAT Retriever implementation for IBM Fusion CAS."""

    def __init__(self, config: FusionCASRetrieverConfig) -> None:
        self._config = config
        self._fusion_url = config.fusion_url.rstrip("/")
        self._vector_store = config.vector_store
        self._session = _make_session(config.timeout, config.verify_ssl)
        logger.info("FusionCASRetriever initialized: url=%s store=%s", self._fusion_url, self._vector_store)

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

    async def search(self, query: str, **kwargs) -> RetrieverOutput:
        """Search Fusion CAS and return a standard NAT RetrieverOutput."""
        top_k = kwargs.get("top_k", self._config.top_k)
        vector_store = kwargs.get("collection_name", self._vector_store)
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
        return RetrieverOutput(results=[d for d in (_parse_document(item) for item in data.get("data", [])) if d])


def _parse_document(item: Any) -> Document | None:
    """Convert one Fusion CAS search result into a NAT Document."""
    if not isinstance(item, dict):
        return None

    filename = item.get("filename", "unknown")

    score_obj = item.get("score") or {}
    score = float(
        score_obj.get("combined_probability_score") or score_obj.get("score") or 0.0
        if isinstance(score_obj, dict) else score_obj or 0.0
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
