"""
Enhanced LLM Service with multiple provider support and metrics tracking
"""

import json
import logging
from collections.abc import Iterable
from datetime import datetime
from typing import Any, Protocol, cast

import requests  # type: ignore[import-untyped]
from openai import OpenAI
from rich.console import Console

from chatbot.utils.validators import InputValidator, ValidationError

console = Console()


class MetricsServiceProtocol(Protocol):
    """Protocol for metrics interactions used by LLM service."""

    def increment(self, metric_name: str) -> None: ...

    def record_error(self, error_type: str) -> None: ...

    def record_timing(self, metric_name: str, duration_ms: float) -> None: ...


class LLMService:
    """Enhanced LLM service with multi-provider support and metrics"""

    def __init__(
        self,
        config: dict[str, Any],
        logger: logging.Logger,
        metrics_service: MetricsServiceProtocol | None = None,
    ) -> None:
        self.config: dict[str, Any] = config
        self.logger = logger
        self.metrics_service = metrics_service

        # Configuration
        self.timeout = config.get("llm_timeout", 60)
        self.max_retries = config.get("llm_max_retries", 2)

    def call_llm(self, search_result: Any, user_query: str) -> str | None:
        """
        Send semantic search result + user query to LLM providers

        Args:
            search_result: Search result object (typically a list of search results)
            user_query: User's query string

        Returns:
            LLM response or None if all providers fail
        """
        # Validate input
        try:
            user_query = InputValidator.validate_query(user_query, "user_query")
        except ValidationError as e:
            console.print(f"[red]Input validation failed: {e}[/red]")
            self.logger.error(f"Input validation failed: {e}")
            return None

        # Validate search_result is not None or empty
        if not search_result:
            console.print("[yellow]No search data available for LLM processing[/yellow]")
            self.logger.warning("LLM called with empty search result")
            return None

        # Safely serialize the search_result
        query_data = self._serialize_search_result(search_result)

        # Build prompt
        prompt = self._build_prompt(query_data, user_query)

        # Try each provider in sequence
        providers = self.config.get("llm_provider_sequence", [])

        if not providers:
            console.print("[red]No LLM providers configured[/]")
            self.logger.error("No LLM providers in configuration")
            return None

        for provider in providers:
            try:
                console.print(f"[yellow]Trying LLM provider: {provider}[/yellow]")
                self.logger.info(f"Attempting LLM provider: {provider}")

                if self.metrics_service:
                    self.metrics_service.increment(f"llm_attempts_{provider}")

                # Try to get response from provider
                success = self._try_provider(provider, prompt)

                if success:
                    if self.metrics_service:
                        self.metrics_service.increment(f"llm_success_{provider}")
                    return success

            except Exception as e:
                console.print(f"[red]Provider {provider} failed: {e}[/red]")
                self.logger.error(f"LLM provider {provider} failed: {e}")

                if self.metrics_service:
                    self.metrics_service.increment(f"llm_error_{provider}")
                    self.metrics_service.record_error(f"llm_{provider}")

                continue

        console.print("[red]All LLM providers failed.[/red]")
        self.logger.error("All LLM providers exhausted")
        return None

    def _serialize_search_result(self, search_result: Any) -> dict[str, Any]:
        """Safely serialize search result to dictionary"""
        try:
            # If it's already a list (data array), wrap it
            if isinstance(search_result, list):
                return {"data": search_result, "type": "search_results"}
            elif hasattr(search_result, "to_dict"):
                return cast(dict[str, Any], search_result.to_dict())
            elif isinstance(search_result, dict):
                return cast(dict[str, Any], search_result)
            elif search_result is None:
                return {"data": None, "message": "No search result available"}
            else:
                return {
                    "success": getattr(search_result, "success", False),
                    "data": getattr(search_result, "data", None),
                    "error": getattr(search_result, "error", ""),
                    "timestamp": str(
                        getattr(search_result, "timestamp", datetime.now())
                    ),
                }
        except Exception as e:
            self.logger.warning(f"Failed to serialize search result: {e}")
            return {"error": "Failed to serialize search result"}

    def _build_prompt(self, query_data: dict[str, Any], user_query: str) -> str:
        """Build prompt for LLM"""
        return f"""
            You are an intelligent assistant helping users understand data retrieved from a vector store.

            Based on the following retrieved data:
            {json.dumps(query_data, indent=2)}

            Answer the user's query: "{user_query}"

            Provide a clear, concise, and helpful response.
            """

    def _try_provider(self, provider: str, prompt: str) -> str | None:
        """
        Try a specific LLM provider

        Args:
            provider: Provider name
            prompt: Full prompt text

        Returns:
            Response text or None if failed
        """
        import time

        start_time = time.time()

        try:
            if provider == "openai":
                result = self._call_openai(prompt)
            elif provider == "ollama":
                result = self._call_ollama(prompt)
            elif provider == "nvidia":
                result = self._call_nvidia(prompt)
            else:
                console.print(f"[red]Unknown provider: {provider}[/red]")
                return None

            # Record timing
            if self.metrics_service:
                duration_ms = (time.time() - start_time) * 1000
                self.metrics_service.record_timing(
                    f"llm_{provider}_duration", duration_ms
                )

            return result

        except Exception as e:
            self.logger.error(f"Provider {provider} error: {e}")
            raise

    def _call_openai(self, prompt: str) -> str | None:
        """Call OpenAI API"""
        api_key = self.config.get("openai_api_key")
        model = self.config.get("openai_model", "gpt-3.5-turbo")

        if not api_key or api_key.startswith("sk-YOUR"):
            console.print("[red]OpenAI API key not configured[/]")
            return None

        try:
            client = OpenAI(api_key=api_key)

            messages = [
                {
                    "role": "system",
                    "content": "You help analyze CAS semantic search results.",
                },
                {"role": "user", "content": prompt},
            ]

            stream = cast(
                Iterable[Any],
                client.chat.completions.create(
                    model=model, messages=cast(Any, messages), stream=True, timeout=self.timeout
                ),
            )

            full_response: list[str] = []
            for chunk in stream:
                content = (
                    chunk.choices[0].delta.content if chunk.choices[0].delta else ""
                )
                if content:
                    console.print(content, end="")
                    full_response.append(content)

            console.print()  # New line
            return "".join(full_response)

        except Exception as e:
            self.logger.error(f"OpenAI error: {e}")
            raise

    def _call_ollama(self, prompt: str) -> str | None:
        """Call Ollama API"""
        host = self.config.get("ollama_host", "http://localhost:11434")
        model = self.config.get("ollama_model", "llama3")

        try:
            url = f"{host}/api/generate"
            payload = {"model": model, "prompt": prompt, "stream": True}

            response = requests.post(
                url, json=payload, stream=True, timeout=self.timeout
            )
            response.raise_for_status()

            full_response: list[str] = []
            for line in response.iter_lines():
                if line:
                    data = json.loads(line.decode("utf-8"))
                    if "response" in data:
                        text = data["response"]
                        console.print(text, end="")
                        full_response.append(text)

            console.print()  # New line
            return "".join(full_response)

        except Exception as e:
            self.logger.error(f"Ollama error: {e}")
            raise

    def _call_nvidia(self, prompt: str) -> str | None:
        """Call NVIDIA NIM API"""
        url = self.config.get("nvidia_llm_url")
        model = self.config.get("nvidia_model", "meta/llama3-8b-instruct")

        if not url:
            console.print("[red]NVIDIA LLM URL not configured[/]")
            return None

        try:
            endpoint = f"http://{url}/v1/chat/completions"

            payload: dict[str, Any] = {
                "model": model,
                "messages": [
                    {
                        "role": "system",
                        "content": "You help analyze CAS semantic search results.",
                    },
                    {"role": "user", "content": prompt},
                ],
                "stream": False,
                "max_tokens": 1024,
                "temperature": 0.7,  # Add temperature for more stable generation
                "top_p": 0.9,  # Add nucleus sampling
                "stop": ["\n\n\n", "###", "---"],  # Add stop sequences
            }

            headers = {"Content-Type": "application/json"}

            response = requests.post(
                endpoint, headers=headers, json=payload, timeout=self.timeout
            )

            if response.ok:
                data = cast(dict[str, Any], response.json())
                if "choices" in data and len(data["choices"]) > 0:
                    message = data["choices"][0]["message"]["content"]

                    # Validate and clean the response
                    cleaned_message = self._clean_llm_response(message)

                    if cleaned_message:
                        console.print(cleaned_message)
                        return cleaned_message
                    else:
                        console.print("[red]NVIDIA returned invalid response[/red]")
                        self.logger.error(f"Invalid NVIDIA response: {message[:200]}")
                        return None
                else:
                    console.print("[red]Unexpected NVIDIA response format[/red]")
                    self.logger.error(f"NVIDIA response: {json.dumps(data, indent=2)}")
                    return None
            else:
                console.print(
                    f"[red]NVIDIA API failed ({response.status_code}): {response.text}[/red]"
                )
                return None

        except Exception as e:
            self.logger.error(f"NVIDIA error: {e}")
            raise

    def _clean_llm_response(self, response: str) -> str | None:
        """
        Clean and validate LLM response to remove gibberish or corrupted text

        Args:
            response: Raw LLM response text

        Returns:
            Cleaned response or None if invalid
        """
        if not response or not isinstance(response, str):
            return None

        # Remove leading/trailing whitespace
        response = response.strip()

        if not response:
            return None

        # Split into lines and analyze
        lines = response.split("\n")
        cleaned_lines: list[str] = []

        for line in lines:
            line = line.strip()

            # Skip empty lines at the end
            if not line:
                if cleaned_lines:  # Only add empty lines if we have content
                    cleaned_lines.append(line)
                continue

            # Check for gibberish patterns
            # 1. Lines with excessive random characters or very short words
            words = line.split()
            if words:
                # Calculate average word length
                avg_word_len = sum(len(w) for w in words) / len(words)

                # If average word length is very short (< 2.5) and line has many words,
                # it's likely gibberish
                if len(words) > 10 and avg_word_len < 2.5:
                    self.logger.warning(
                        f"Detected gibberish line (short words): {line[:50]}"
                    )
                    break  # Stop processing at first gibberish

                # Check for excessive special characters
                special_char_count = sum(
                    1 for c in line if not c.isalnum() and not c.isspace()
                )
                if len(line) > 20 and special_char_count / len(line) > 0.3:
                    self.logger.warning(
                        f"Detected gibberish line (special chars): {line[:50]}"
                    )
                    break

                # Check for lines with mostly single characters separated by spaces
                single_char_words = sum(1 for w in words if len(w) == 1)
                if len(words) > 5 and single_char_words / len(words) > 0.5:
                    self.logger.warning(
                        f"Detected gibberish line (single chars): {line[:50]}"
                    )
                    break

            cleaned_lines.append(line)

        # Join cleaned lines
        cleaned = "\n".join(cleaned_lines).strip()

        # Final validation: ensure we have meaningful content
        if len(cleaned) < 10:
            self.logger.warning("Response too short after cleaning")
            return None

        # Check if the cleaned response has reasonable word count
        words = cleaned.split()
        if len(words) < 5:
            self.logger.warning("Response has too few words after cleaning")
            return None

        return cleaned

    def get_provider_status(self) -> dict[str, dict[str, Any]]:
        """Get status of all configured providers"""
        providers = self.config.get("llm_provider_sequence", [])
        status: dict[str, dict[str, Any]] = {}

        for provider in providers:
            status[provider] = {
                "configured": True,
                "model": self._get_provider_model(provider),
                "url": self._get_provider_url(provider),
            }

        return status

    def _get_provider_model(self, provider: str) -> str:
        """Get model name for provider"""
        model_map = {
            "openai": self.config.get("openai_model", "gpt-3.5-turbo"),
            "ollama": self.config.get("ollama_model", "llama3"),
            "nvidia": self.config.get("nvidia_model", "meta/llama3-8b-instruct"),
        }
        return str(model_map.get(provider, "unknown"))

    def _get_provider_url(self, provider: str) -> str:
        """Get URL for provider"""
        url_map = {
            "openai": "https://api.openai.com",
            "ollama": self.config.get("ollama_host", "http://localhost:11434"),
            "nvidia": self.config.get("nvidia_llm_url", ""),
        }
        return str(url_map.get(provider, ""))
