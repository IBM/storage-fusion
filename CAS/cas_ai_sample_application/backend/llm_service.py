"""
LLM service — CAS retrieval + LLM answer synthesis.

Works with any OpenAI-compatible /v1/chat/completions API.
Set LLM_BASE_URL and LLM_MODEL in .env to point at your LLM backend.
Set LLM_API_KEY if your backend requires authentication.
"""

from typing import Any, Dict, Iterator, List, Optional, Union
import json
import logging
import os
import re

import requests
from requests.exceptions import ConnectionError as RequestsConnectionError, Timeout

from agents.cas_client import CASClient
from chunk_processor import ChunkProcessor
from utils.exceptions import ConfigurationError

logger = logging.getLogger(__name__)


class LLMService:
    """Retrieve chunks from CAS and synthesize an answer with an LLM."""

    def __init__(self, cas_client: Optional[CASClient] = None) -> None:
        self.cas_client = cas_client or CASClient()

        llm_base_url = os.getenv("LLM_BASE_URL")
        llm_model = os.getenv("LLM_MODEL")
        if not llm_base_url:
            raise ConfigurationError("LLM_BASE_URL is not set in .env.")
        if not llm_model:
            raise ConfigurationError(
                "LLM_MODEL is not set in your .env (e.g. llama3, meta/llama-3.1-8b-instruct, gpt-4o)."
            )

        self.llm_base_url = llm_base_url.rstrip("/")
        self.llm_model = llm_model
        self.llm_api_key = os.getenv("LLM_API_KEY", "")
        self.vector_store_id = os.getenv("CAS_VECTOR_STORE_ID")
        self.default_max_results = int(os.getenv("RAG_MAX_RESULTS", "10"))
        self.default_min_score = float(os.getenv("RAG_MIN_SCORE", "0.1"))
        self.request_timeout = int(os.getenv("LLM_TIMEOUT", "60"))
        self.llm_max_tokens = int(os.getenv("LLM_MAX_TOKENS", "300"))
        self.system_prompt = self._load_system_prompt()
        self.chunk_processor = ChunkProcessor()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def check_model_compatibility(self) -> Dict[str, Any]:
        """Send a minimal probe to the LLM to check structured-output format compliance.

        Sends a tiny synthetic context + question and checks whether the model
        produces a response containing both FULL_ANSWER: and [SOURCE: N].
        Models that fail this check are too small or too poorly instruction-tuned
        to reliably follow the pipeline's output format.

        Returns:
            Dict with keys:
              - "compatible" (bool): True if the model passed or is unreachable
                (unreachable is handled by the existing LLM error sentinels).
              - "model" (str): the configured model name.
              - "reason" (str): human-readable explanation.
        """
        probe_prompt = (
            "You are a retrieval-augmented assistant.\n\n"
            "Context Sources:\n"
            "[Source 1]\nThe test system version is 4.2.\n\n"
            "Question: What is the test system version?\n"
            "Answer ONLY the question above. Be specific and direct.\n\n"
            "Response in exactly this format:\n"
            "FULL_ANSWER: [your answer]\n"
            "[SOURCE: 1]\n\n"
            "Response:"
        )
        payload = {
            "model": self.llm_model,
            "messages": [{"role": "user", "content": probe_prompt}],
            "stream": False,
            "max_tokens": 80,
        }
        try:
            resp = requests.post(
                f"{self.llm_base_url}/v1/chat/completions",
                json=payload,
                headers=self._auth_headers(),
                timeout=30,
            )
            resp.raise_for_status()
            data = resp.json()
            text = (
                data.get("choices", [{}])[0]
                .get("message", {})
                .get("content", "")
            ).strip()
            has_full_answer = bool(re.search(r'FULL_ANSWER\s*:', text, re.IGNORECASE))
            has_source = bool(re.search(r'\[SOURCE\s*:\s*(\d+|N/A)\]', text, re.IGNORECASE))
            if has_full_answer and has_source:
                return {"compatible": True, "model": self.llm_model, "reason": "Model passed format compliance check."}
            logger.warning("llm_compat_check_failed model=%s response=%r", self.llm_model, text[:200])
            return {
                "compatible": False,
                "model": self.llm_model,
                "reason": "Model did not produce the required FULL_ANSWER / [SOURCE: N] format.",
            }
        except Exception as exc:
            # Unreachable LLM is surfaced by the existing error sentinels — don't
            # double-report it here by flagging the model as incompatible.
            logger.debug("llm_compat_check_skipped error=%r", exc)
            return {"compatible": True, "model": self.llm_model, "reason": "Probe skipped (LLM unreachable)."}

    def _load_system_prompt(self) -> str:
        """Load system prompt from markdown file."""
        prompt_path = os.path.join(os.path.dirname(__file__), "system_prompt.md")
        try:
            with open(prompt_path, "r") as f:
                return f.read().strip()
        except FileNotFoundError:
            logger.warning("system_prompt.md not found, using default prompt")
            return "You are a helpful assistant that answers questions based on provided context."

    def _extract_chunks(self, results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Normalise, deduplicate, and filter CAS results via ChunkProcessor.

        Args:
            results: Raw CAS search result dicts from search_vector_store().

        Returns:
            Processed list of chunk dicts with index, content, score, source fields.
        """
        return self.chunk_processor.process(results)

    def _build_prompt(self, query: str, chunks: List[Dict[str, Any]]) -> str:
        """Build a grounded prompt for answer synthesis using system prompt.

        Context comes first so the model reads all evidence before seeing the
        query. Source filenames are omitted from chunk headers — they add
        noise and the model sometimes echoes them instead of the answer.
        """
        # Sort by score descending so the highest-confidence chunks appear first.
        # The model tends to anchor on the first few sources it reads, so putting
        # the best evidence up front reduces the chance it gets confused by
        # lower-scored county-level chunks later in the context.
        sorted_chunks = sorted(chunks, key=lambda c: c.get("score") or 0.0, reverse=True)
        context = "\n\n".join(
            f"[Source {c['index']}]\n{c['content']}" for c in sorted_chunks
        )
        return f"""{self.system_prompt}

Context Sources:
{context}

Question: {query}
Answer ONLY the question above. Do not answer a different question. Be specific and direct.

Response:"""

    def _build_chat_payload(self, prompt: str, stream: bool) -> Dict[str, Any]:
        """Build an OpenAI-compatible /v1/chat/completions request payload.

        Args:
            prompt: Fully-assembled prompt string including context and question.
            stream: Whether to request a streaming response from the LLM.

        Returns:
            Dict ready to be serialised as the JSON request body.
        """
        return {
            "model": self.llm_model,
            "messages": [{"role": "user", "content": prompt}],
            "stream": stream,
            "max_tokens": self.llm_max_tokens,
        }

    def _auth_headers(self) -> Dict[str, str]:
        """Return an Authorization header dict if LLM_API_KEY is configured.

        Returns:
            Dict with a single "Authorization" key, or an empty dict if no key
            is set (some LLM backends such as local Ollama require no auth).
        """
        if self.llm_api_key:
            return {"Authorization": f"Bearer {self.llm_api_key}"}
        return {}

    def _call_llm_stream(self, prompt: str) -> Iterator[str]:
        """Call the OpenAI-compatible /v1/chat/completions API with streaming.

        Args:
            prompt: Assembled prompt string to send to the LLM.

        Yields:
            Successive text tokens from the model's streaming response.
            On error yields a single "[ERROR: ...]" string so the caller's
            streaming loop always receives something and can surface the failure
            to the client without an unhandled exception.
        """
        payload = self._build_chat_payload(prompt, stream=True)
        try:
            with requests.post(
                f"{self.llm_base_url}/v1/chat/completions",
                json=payload,
                headers=self._auth_headers(),
                stream=True,
                timeout=self.request_timeout,
            ) as response:
                response.raise_for_status()
                for line in response.iter_lines():
                    if not line:
                        continue
                    # SSE lines are prefixed with "data: "
                    text = line.decode("utf-8")
                    if text.startswith("data: "):
                        text = text[len("data: "):]
                    if text.strip() == "[DONE]":
                        break
                    try:
                        chunk = json.loads(text)
                        token = (
                            chunk.get("choices", [{}])[0]
                            .get("delta", {})
                            .get("content", "")
                        )
                        if token:
                            yield token
                    except json.JSONDecodeError:
                        continue
        except (RequestsConnectionError, Timeout):
            logger.warning("llm_unreachable url=%s", self.llm_base_url)
            yield f"[LLM_UNAVAILABLE url={self.llm_base_url} model={self.llm_model}]"
        except requests.exceptions.HTTPError as exc:
            status_code = exc.response.status_code if exc.response is not None else "unknown"
            logger.warning("llm_http_error status=%s url=%s model=%s", status_code, self.llm_base_url, self.llm_model)
            if status_code == 404:
                yield f"[LLM_NOT_FOUND url={self.llm_base_url} model={self.llm_model}]"
            else:
                yield f"[LLM_HTTP_ERROR status={status_code} url={self.llm_base_url} model={self.llm_model}]"
        except Exception as exc:
            logger.warning("llm_stream_error error=%r", exc)
            yield f"[LLM_UNAVAILABLE url={self.llm_base_url} model={self.llm_model}]"

    def _parse_structured_answer(self, llm_answer: str) -> Dict[str, Any]:
        """Parse the model response, extracting the answer text and source number.

        Args:
            llm_answer: Raw text returned by the LLM including any structured tags.

        Returns:
            Dict with keys "answer" (str) and "source_number" (Optional[int]).
        """
        answer_text = llm_answer.strip()

        full_match = re.search(
            r'FULL_ANSWER:\s*(.+?)(?:\n\[SOURCE|\n\(SOURCE|\nSOURCE|\nSource|$)',
            answer_text, re.IGNORECASE | re.DOTALL
        )
        full_answer = full_match.group(1).strip() if full_match else None

        source_match = re.search(r'[\[\(]?\bSOURCE[:\s]+(\d+)[\]\)]?', answer_text, re.IGNORECASE)
        source_number = None
        if source_match:
            try:
                source_number = int(source_match.group(1))
            except ValueError:
                pass

        return {
            "answer": full_answer if full_answer else answer_text,
            "source_number": source_number,
        }

    def _get_vector_store_id(self) -> Union[str, Dict[str, Any]]:
        """Fetch vector stores from CAS and return the first available ID.

        Returns:
            The first vector store ID string on success, or a dict with
            ``{"status": "error", "error": "..."}`` when none are available.
            The caller must check ``isinstance(result, dict)`` before treating
            the return value as a usable store ID.
        """
        result = self.cas_client.list_vector_stores()
        if result.get("status") != "success":
            return {"status": "error", "error": "Unable to retrieve vector stores from CAS"}
        vector_stores = result.get("vector_stores", [])
        if not isinstance(vector_stores, list) or not vector_stores:
            return {"status": "error", "error": "CAS returned no vector stores"}
        available_ids = [s.get("id") for s in vector_stores if isinstance(s, dict) and s.get("id")]
        if not available_ids:
            return {"status": "error", "error": "No usable vector store IDs found"}
        return available_ids[0]
