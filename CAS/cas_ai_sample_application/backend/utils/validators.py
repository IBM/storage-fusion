"""
Centralised input validation for user-facing and internal methods.

Usage:
    from utils.validators import InputValidator, ValidationError

    clean_query = InputValidator.validate_query(raw_text)
    clean_token = InputValidator.validate_token(raw_token)
    clean_url   = InputValidator.validate_endpoint_url(raw_url)
"""

import re
from typing import Any


class ValidationError(Exception):
    """Raised when a caller-supplied value fails a format or length check."""

    pass


class InputValidator:
    """Static validation helpers for every string value that enters the backend."""

    MAX_QUERY_LENGTH: int = 8_000
    MAX_TOKEN_LENGTH: int = 500
    MIN_TOKEN_LENGTH: int = 10
    MAX_URL_LENGTH: int = 500

    _INVALID_TOKEN_CHARS: frozenset = frozenset({'<', '>', '"', "'", ';', '&', '|'})

    _SESSION_ID_RE: re.Pattern = re.compile(r'^[a-f0-9-]{36}$')

    _URL_RE: re.Pattern = re.compile(
        r'^https?://'
        r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'
        r'localhost|'
        r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'
        r'(?::\d+)?'
        r'(?:/?|[/?]\S+)$',
        re.IGNORECASE,
    )

    @staticmethod
    def validate_query(query: Any, field_name: str = "question") -> str:
        """
        Validate and sanitise a user question string.

        Strips HTML/script tags so prompt-injection via the question field
        cannot embed executable markup in the LLM prompt.

        Args:
            query: Raw value from the request.
            field_name: Label used in error messages (default: "question").

        Returns:
            Sanitised, stripped query string.

        Raises:
            ValidationError: If the value is None, not a string, empty, or too long.
        """
        if query is None:
            raise ValidationError(f"{field_name} cannot be None")
        if not isinstance(query, str):
            raise ValidationError(f"{field_name} must be a string")
        sanitized = re.sub(r'<script[^>]*>.*?</script>', '', query, flags=re.IGNORECASE | re.DOTALL)
        sanitized = re.sub(r'<[^>]+>', '', sanitized).strip()
        if not sanitized:
            raise ValidationError(f"{field_name} cannot be empty or whitespace")
        if len(sanitized) > InputValidator.MAX_QUERY_LENGTH:
            raise ValidationError(
                f"{field_name} exceeds maximum length of {InputValidator.MAX_QUERY_LENGTH} characters"
            )
        return sanitized

    @staticmethod
    def validate_token(token: Any, field_name: str = "cas_api_key") -> str:
        """
        Validate a CAS API bearer token value.

        Args:
            token: Raw value from the request.
            field_name: Label used in error messages.

        Returns:
            Stripped token string.

        Raises:
            ValidationError: If the token is empty, too short/long, or contains
                             shell-injection characters.
        """
        if token is None:
            raise ValidationError(f"{field_name} cannot be None")
        if not isinstance(token, str):
            raise ValidationError(f"{field_name} must be a string")
        token = token.strip()
        if not token:
            raise ValidationError(f"{field_name} cannot be empty or whitespace")
        if len(token) < InputValidator.MIN_TOKEN_LENGTH:
            raise ValidationError(
                f"{field_name} must be at least {InputValidator.MIN_TOKEN_LENGTH} characters"
            )
        if len(token) > InputValidator.MAX_TOKEN_LENGTH:
            raise ValidationError(
                f"{field_name} exceeds maximum length of {InputValidator.MAX_TOKEN_LENGTH} characters"
            )
        if any(char in token for char in InputValidator._INVALID_TOKEN_CHARS):
            raise ValidationError(f"{field_name} contains invalid characters")
        return token

    @staticmethod
    def validate_endpoint_url(url: Any, field_name: str = "endpoint") -> str:
        """
        Validate a CAS or LLM endpoint URL.

        Args:
            url: Raw value from the request.
            field_name: Label used in error messages.

        Returns:
            Stripped, validated URL string.

        Raises:
            ValidationError: If the URL is missing, malformed, or too long.
        """
        if url is None:
            raise ValidationError(f"{field_name} cannot be None")
        if not isinstance(url, str):
            raise ValidationError(f"{field_name} must be a string")
        url = url.strip()
        if not url:
            raise ValidationError(f"{field_name} cannot be empty or whitespace")
        if len(url) > InputValidator.MAX_URL_LENGTH:
            raise ValidationError(
                f"{field_name} exceeds maximum length of {InputValidator.MAX_URL_LENGTH} characters"
            )
        if not InputValidator._URL_RE.match(url):
            raise ValidationError(f"{field_name} is not a valid http/https URL")
        return url

    @staticmethod
    def validate_session_id(session_id: Any, field_name: str = "session_id") -> str:
        """Validate an optional session_id is a well-formed UUID string."""
        if not isinstance(session_id, str):
            raise ValidationError(f"{field_name} must be a string")
        session_id = session_id.strip()
        if not InputValidator._SESSION_ID_RE.match(session_id):
            raise ValidationError(f"{field_name} is not a valid session id")
        return session_id
