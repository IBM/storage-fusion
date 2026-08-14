"""
Domain-specific exception types for the CAS Assistant backend.

Defining named exception classes instead of raising bare built-ins (ValueError,
EnvironmentError, Exception) gives callers precise except-clauses and produces
self-documenting stack traces.

Usage:
    from utils.exceptions import ConfigurationError, CASClientError
"""


class ConfigurationError(Exception):
    """
    Raised when required environment variables or config values are missing
    or invalid at startup time.

    This is a hard stop — the process should not attempt to serve requests
    when its LLM backend or CAS endpoint cannot be resolved.
    """

    pass


class CASClientError(Exception):
    """
    Raised when the CASClient cannot complete a CAS API operation.

    Distinct from ConfigurationError: the client may be correctly configured
    but still fail due to network errors, bad credentials supplied at
    request-time, or an unexpected CAS API response shape.
    """

    pass


