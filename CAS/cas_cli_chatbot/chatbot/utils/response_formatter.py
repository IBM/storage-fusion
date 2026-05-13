"""
Standardized response formatting for consistent error handling across services
"""

from datetime import datetime
from typing import Any


class ResponseFormatter:
    """Standardized response formatter for all services"""

    @staticmethod
    def success(data: Any = None, message: str = "") -> dict[str, Any]:
        """
        Create a standardized success response

        Args:
            data: Response data
            message: Optional success message

        Returns:
            Standardized success response dictionary
        """
        response: dict[str, Any] = {
            "success": True,
            "data": data,
            "error": None,
            "timestamp": datetime.now().isoformat(),
        }

        if message:
            response["message"] = message

        return response

    @staticmethod
    def error(
        error_message: str,
        error_code: str | None = None,
        details: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """
        Create a standardized error response

        Args:
            error_message: Error message
            error_code: Optional error code for categorization
            details: Optional additional error details

        Returns:
            Standardized error response dictionary
        """
        response: dict[str, Any] = {
            "success": False,
            "data": None,
            "error": error_message,
            "timestamp": datetime.now().isoformat(),
        }

        if error_code:
            response["error_code"] = error_code

        if details:
            response["details"] = details

        return response

    @staticmethod
    def validation_error(
        error_message: str, field: str | None = None
    ) -> dict[str, Any]:
        """
        Create a standardized validation error response

        Args:
            error_message: Validation error message
            field: Optional field name that failed validation

        Returns:
            Standardized validation error response dictionary
        """
        details = {}
        if field:
            details["field"] = field

        return ResponseFormatter.error(
            error_message=error_message,
            error_code="VALIDATION_ERROR",
            details=details if details else None,
        )

    @staticmethod
    def authentication_error(
        error_message: str = "Authentication failed",
    ) -> dict[str, Any]:
        """
        Create a standardized authentication error response

        Args:
            error_message: Authentication error message

        Returns:
            Standardized authentication error response dictionary
        """
        return ResponseFormatter.error(
            error_message=error_message, error_code="AUTHENTICATION_ERROR"
        )

    @staticmethod
    def authorization_error(
        error_message: str = "Insufficient permissions",
    ) -> dict[str, Any]:
        """
        Create a standardized authorization error response

        Args:
            error_message: Authorization error message

        Returns:
            Standardized authorization error response dictionary
        """
        return ResponseFormatter.error(
            error_message=error_message, error_code="AUTHORIZATION_ERROR"
        )

    @staticmethod
    def not_found_error(resource: str, identifier: str | None = None) -> dict[str, Any]:
        """
        Create a standardized not found error response

        Args:
            resource: Resource type that was not found
            identifier: Optional resource identifier

        Returns:
            Standardized not found error response dictionary
        """
        message = f"{resource} not found"
        if identifier:
            message += f": {identifier}"

        return ResponseFormatter.error(error_message=message, error_code="NOT_FOUND")

    @staticmethod
    def timeout_error(operation: str, timeout_seconds: int) -> dict[str, Any]:
        """
        Create a standardized timeout error response

        Args:
            operation: Operation that timed out
            timeout_seconds: Timeout duration in seconds

        Returns:
            Standardized timeout error response dictionary
        """
        return ResponseFormatter.error(
            error_message=f"{operation} timed out after {timeout_seconds} seconds",
            error_code="TIMEOUT_ERROR",
            details={"timeout_seconds": timeout_seconds},
        )

    @staticmethod
    def network_error(error_message: str = "Network error occurred") -> dict[str, Any]:
        """
        Create a standardized network error response

        Args:
            error_message: Network error message

        Returns:
            Standardized network error response dictionary
        """
        return ResponseFormatter.error(
            error_message=error_message, error_code="NETWORK_ERROR"
        )

    @staticmethod
    def internal_error(error_message: str = "Internal server error") -> dict[str, Any]:
        """
        Create a standardized internal error response

        Args:
            error_message: Internal error message

        Returns:
            Standardized internal error response dictionary
        """
        return ResponseFormatter.error(
            error_message=error_message, error_code="INTERNAL_ERROR"
        )
