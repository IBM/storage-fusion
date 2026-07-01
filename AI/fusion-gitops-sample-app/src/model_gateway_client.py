"""
Model Gateway Client for Fusion AI Platform
Provides unified interface to Model Gateway API with Bearer authentication
"""

import logging
import requests
from typing import Dict, List, Optional, Any, Union
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class ModelGatewayConfig:
    """Configuration for Model Gateway"""
    base_url: str
    api_key: str
    model_name: str = "granite"
    timeout: int = 60
    max_retries: int = 3


class ModelGatewayClient:
    """
    Client for interacting with Model Gateway API
    Supports both chat completions and text completions
    """

    def __init__(self, config: ModelGatewayConfig):
        """
        Initialize Model Gateway client
        
        Args:
            config: ModelGatewayConfig object with connection details
        """
        self.config = config
        self.base_url = config.base_url.rstrip("/")
        self.headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {config.api_key}"
        }
        logger.info(f"Model Gateway client initialized: {self.base_url}")

    def list_models(self) -> List[Dict[str, Any]]:
        """
        List available models from the gateway
        
        Returns:
            List of model information dictionaries
        """
        endpoint = f"{self.base_url}/v1/models"
        
        try:
            response = requests.get(
                endpoint,
                headers=self.headers,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            result = response.json()
            
            models = result.get("data", [])
            logger.info(f"Retrieved {len(models)} models from gateway")
            return models
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to list models: {str(e)}")
            raise

    def chat_completion(
        self,
        messages: List[Dict[str, str]],
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 512,
        stream: bool = False
    ) -> Dict[str, Any]:
        """
        Create a chat completion using the Model Gateway
        
        Args:
            messages: List of message dictionaries with 'role' and 'content'
            model: Model name (defaults to config model)
            temperature: Sampling temperature
            max_tokens: Maximum tokens to generate
            stream: Whether to stream the response
            
        Returns:
            Chat completion response dictionary
        """
        endpoint = f"{self.base_url}/v1/chat/completions"
        model = model or self.config.model_name
        
        payload = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": stream
        }
        
        last_error = None
        for attempt in range(self.config.max_retries):
            try:
                logger.info(f"Chat completion attempt {attempt + 1}/{self.config.max_retries}")
                
                response = requests.post(
                    endpoint,
                    json=payload,
                    headers=self.headers,
                    timeout=self.config.timeout
                )
                response.raise_for_status()
                result = response.json()
                
                logger.info(f"Chat completion successful: {result.get('id', 'unknown')}")
                return result
                
            except requests.exceptions.RequestException as e:
                last_error = e
                error_detail = ""
                if hasattr(e, 'response') and e.response is not None:
                    error_detail = f" - {e.response.text[:200]}"
                
                logger.warning(f"Chat completion attempt {attempt + 1} failed: {str(e)}{error_detail}")
                
                if attempt < self.config.max_retries - 1:
                    import time
                    time.sleep(2 ** attempt)  # Exponential backoff
        
        error_msg = f"Chat completion failed after {self.config.max_retries} attempts: {str(last_error)}"
        logger.error(error_msg)
        raise Exception(error_msg)

    def text_completion(
        self,
        prompt: str,
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 512
    ) -> Dict[str, Any]:
        """
        Create a text completion using the Model Gateway
        
        Args:
            prompt: Text prompt
            model: Model name (defaults to config model)
            temperature: Sampling temperature
            max_tokens: Maximum tokens to generate
            
        Returns:
            Completion response dictionary
        """
        endpoint = f"{self.base_url}/v1/completions"
        model = model or self.config.model_name
        
        payload = {
            "model": model,
            "prompt": prompt,
            "temperature": temperature,
            "max_tokens": max_tokens
        }
        
        last_error = None
        for attempt in range(self.config.max_retries):
            try:
                logger.info(f"Text completion attempt {attempt + 1}/{self.config.max_retries}")
                
                response = requests.post(
                    endpoint,
                    json=payload,
                    headers=self.headers,
                    timeout=self.config.timeout
                )
                response.raise_for_status()
                result = response.json()
                
                logger.info(f"Text completion successful")
                return result
                
            except requests.exceptions.RequestException as e:
                last_error = e
                error_detail = ""
                if hasattr(e, 'response') and e.response is not None:
                    error_detail = f" - {e.response.text[:200]}"
                
                logger.warning(f"Text completion attempt {attempt + 1} failed: {str(e)}{error_detail}")
                
                if attempt < self.config.max_retries - 1:
                    import time
                    time.sleep(2 ** attempt)  # Exponential backoff
        
        error_msg = f"Text completion failed after {self.config.max_retries} attempts: {str(last_error)}"
        logger.error(error_msg)
        raise Exception(error_msg)

    def create_embeddings(
        self,
        input_text: Union[str, List[str]],
        model: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Create embeddings using the Model Gateway
        
        Args:
            input_text: Text or list of texts to embed
            model: Model name (defaults to config model)
            
        Returns:
            Embeddings response dictionary
        """
        endpoint = f"{self.base_url}/v1/embeddings"
        model = model or self.config.model_name
        
        payload = {
            "model": model,
            "input": input_text
        }
        
        try:
            response = requests.post(
                endpoint,
                json=payload,
                headers=self.headers,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            result = response.json()
            
            logger.info(f"Embeddings created successfully")
            return result
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to create embeddings: {str(e)}")
            raise

# Made with Bob
