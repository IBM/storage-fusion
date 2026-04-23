"""
Input validation utilities for user-facing methods
"""

from typing import Optional, Dict, Any, TYPE_CHECKING
import re

if TYPE_CHECKING:
    from chatbot.services.auth_service import AuthService


class ValidationError(Exception):
    """Validation error exception"""
    pass


class InputValidator:
    """Centralized input validation for user-facing methods"""
    
    # Validation constants
    MAX_QUERY_LENGTH = 10000
    MAX_VECTOR_STORE_NAME_LENGTH = 255
    MAX_FILE_ID_LENGTH = 255
    MAX_USERNAME_LENGTH = 255
    MIN_LIMIT = 1
    MAX_LIMIT = 100
    
    # Regex patterns
    VECTOR_STORE_NAME_PATTERN = re.compile(r'^[a-zA-Z0-9_-]+$')
    FILE_ID_PATTERN = re.compile(r'^[a-zA-Z0-9_-]+$')
    USERNAME_PATTERN = re.compile(r'^[a-zA-Z0-9._@-]+$')
    
    @staticmethod
    def validate_query(query: str, field_name: str = "query") -> str:
        """
        Validate query string
        
        Args:
            query: Query string to validate
            field_name: Name of the field for error messages
            
        Returns:
            Validated and stripped query string
            
        Raises:
            ValidationError: If validation fails
        """
        if query is None:
            raise ValidationError(f"{field_name} cannot be None")
        
        if not isinstance(query, str):
            raise ValidationError(f"{field_name} must be a string")
        
        query = query.strip()
        
        if not query:
            raise ValidationError(f"{field_name} cannot be empty")
        
        if len(query) > InputValidator.MAX_QUERY_LENGTH:
            raise ValidationError(
                f"{field_name} exceeds maximum length of {InputValidator.MAX_QUERY_LENGTH} characters"
            )
        
        return query
    
    @staticmethod
    def validate_vector_store_name(name: str, field_name: str = "vector_store") -> str:
        """
        Validate vector store name
        
        Args:
            name: Vector store name to validate
            field_name: Name of the field for error messages
            
        Returns:
            Validated vector store name
            
        Raises:
            ValidationError: If validation fails
        """
        if name is None:
            raise ValidationError(f"{field_name} cannot be None")
        
        if not isinstance(name, str):
            raise ValidationError(f"{field_name} must be a string")
        
        name = name.strip()
        
        if not name:
            raise ValidationError(f"{field_name} cannot be empty")
        
        if len(name) > InputValidator.MAX_VECTOR_STORE_NAME_LENGTH:
            raise ValidationError(
                f"{field_name} exceeds maximum length of {InputValidator.MAX_VECTOR_STORE_NAME_LENGTH} characters"
            )
        
        if not InputValidator.VECTOR_STORE_NAME_PATTERN.match(name):
            raise ValidationError(
                f"{field_name} contains invalid characters. Only alphanumeric, underscore, and hyphen allowed"
            )
        
        return name
    
    @staticmethod
    def validate_file_id(file_id: str, field_name: str = "file_id") -> str:
        """
        Validate file ID
        
        Args:
            file_id: File ID to validate
            field_name: Name of the field for error messages
            
        Returns:
            Validated file ID
            
        Raises:
            ValidationError: If validation fails
        """
        if file_id is None:
            raise ValidationError(f"{field_name} cannot be None")
        
        if not isinstance(file_id, str):
            raise ValidationError(f"{field_name} must be a string")
        
        file_id = file_id.strip()
        
        if not file_id:
            raise ValidationError(f"{field_name} cannot be empty")
        
        if len(file_id) > InputValidator.MAX_FILE_ID_LENGTH:
            raise ValidationError(
                f"{field_name} exceeds maximum length of {InputValidator.MAX_FILE_ID_LENGTH} characters"
            )
        
        if not InputValidator.FILE_ID_PATTERN.match(file_id):
            raise ValidationError(
                f"{field_name} contains invalid characters. Only alphanumeric, underscore, and hyphen allowed"
            )
        
        return file_id
    
    @staticmethod
    def validate_username(username: str, field_name: str = "username") -> str:
        """
        Validate username
        
        Args:
            username: Username to validate
            field_name: Name of the field for error messages
            
        Returns:
            Validated username
            
        Raises:
            ValidationError: If validation fails
        """
        if username is None:
            raise ValidationError(f"{field_name} cannot be None")
        
        if not isinstance(username, str):
            raise ValidationError(f"{field_name} must be a string")
        
        username = username.strip()
        
        if not username:
            raise ValidationError(f"{field_name} cannot be empty")
        
        if len(username) > InputValidator.MAX_USERNAME_LENGTH:
            raise ValidationError(
                f"{field_name} exceeds maximum length of {InputValidator.MAX_USERNAME_LENGTH} characters"
            )
        
        if not InputValidator.USERNAME_PATTERN.match(username):
            raise ValidationError(
                f"{field_name} contains invalid characters. Only alphanumeric, dot, underscore, @, and hyphen allowed"
            )
        
        return username
    
    @staticmethod
    def validate_limit(limit: Optional[int], field_name: str = "limit") -> int:
        """
        Validate limit parameter
        
        Args:
            limit: Limit value to validate
            field_name: Name of the field for error messages
            
        Returns:
            Validated limit value
            
        Raises:
            ValidationError: If validation fails
        """
        if limit is None:
            return InputValidator.MAX_LIMIT  # Return default
        
        if not isinstance(limit, int):
            raise ValidationError(f"{field_name} must be an integer")
        
        if limit < InputValidator.MIN_LIMIT:
            raise ValidationError(
                f"{field_name} must be at least {InputValidator.MIN_LIMIT}"
            )
        
        if limit > InputValidator.MAX_LIMIT:
            raise ValidationError(
                f"{field_name} cannot exceed {InputValidator.MAX_LIMIT}"
            )
        
        return limit
    
    @staticmethod
    def validate_filters(filters: Dict[str, Any], field_name: str = "filters") -> Dict[str, Any]:
        """
        Validate filter dictionary
        
        Args:
            filters: Filter dictionary to validate
            field_name: Name of the field for error messages
            
        Returns:
            Validated filters
            
        Raises:
            ValidationError: If validation fails
        """
        if filters is None:
            raise ValidationError(f"{field_name} cannot be None")
        
        if not isinstance(filters, dict):
            raise ValidationError(f"{field_name} must be a dictionary")
        
        # Validate required keys
        required_keys = ['key', 'type', 'value']
        for key in required_keys:
            if key not in filters:
                raise ValidationError(f"{field_name} missing required key: {key}")
        
        # Validate type (operator)
        valid_types = ['eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'in', 'nin', 'contains']
        if filters['type'] not in valid_types:
            raise ValidationError(
                f"{field_name} has invalid type. Must be one of: {', '.join(valid_types)}"
            )
        
        return filters
    
    @staticmethod
    def validate_namespace(namespace: str, field_name: str = "namespace") -> str:
        """
        Validate Kubernetes namespace
        
        Args:
            namespace: Namespace to validate
            field_name: Name of the field for error messages
            
        Returns:
            Validated namespace
            
        Raises:
            ValidationError: If validation fails
        """
        if namespace is None:
            raise ValidationError(f"{field_name} cannot be None")
        
        if not isinstance(namespace, str):
            raise ValidationError(f"{field_name} must be a string")
        
        namespace = namespace.strip()
        
        if not namespace:
            raise ValidationError(f"{field_name} cannot be empty")
        
        # Kubernetes namespace naming rules
        if not re.match(r'^[a-z0-9]([-a-z0-9]*[a-z0-9])?$', namespace):
            raise ValidationError(
                f"{field_name} must follow Kubernetes naming rules (lowercase alphanumeric and hyphens)"
            )
        
        if len(namespace) > 63:
            raise ValidationError(f"{field_name} cannot exceed 63 characters")
        
        return namespace


class TokenValidator:
    """Centralized token validation utilities"""
    
    @staticmethod
    def validate_bearer_token(auth_service: Optional['AuthService']) -> Dict[str, Any]:
        """
        Check if bearer token is available and valid
        
        Args:
            auth_service: Authentication service instance
            
        Returns:
            Dict with 'valid' boolean and optional 'error' message
        """
        if auth_service is None:
            return {
                'valid': False,
                'error': 'Authentication service not available'
            }
        
        if not auth_service.has_valid_token():
            return {
                'valid': False,
                'error': 'No valid bearer token. Please authenticate first.'
            }
        
        return {'valid': True}
    
    @staticmethod
    def check_token_with_message(auth_service: Optional['AuthService'],
                                  console=None,
                                  error_message: str = "[red]✗ Authentication failed. Please check your credentials.[/]") -> bool:
        """
        Check token validity and optionally display error message
        
        Args:
            auth_service: Authentication service instance
            console: Rich console for displaying messages (optional)
            error_message: Custom error message to display
            
        Returns:
            True if token is valid, False otherwise
        """
        if auth_service is None or not auth_service.has_valid_token():
            if console:
                console.print(error_message)
            return False
        return True
