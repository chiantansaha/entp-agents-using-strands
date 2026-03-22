"""
HTTP client with retry mechanism and comprehensive error handling.
"""
import requests
import time
import logging
from typing import Dict, Any, Optional
from .json_parser import safe_json_parse

logger = logging.getLogger(__name__)

class HTTPClient:
    """HTTP client with retry logic and error handling."""
    
    def __init__(self, base_url: str, timeout: int = 30, max_retries: int = 3):
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.max_retries = max_retries
        self.session = requests.Session()
        
        # Set default headers
        self.session.headers.update({
            'Content-Type': 'application/json',
            'User-Agent': 'EBA-Frontend/1.0'
        })
    
    def _make_request_with_retry(self, method: str, endpoint: str, **kwargs) -> Dict[str, Any]:
        """
        Make HTTP request with retry logic and exponential backoff.
        Handles streaming responses by consuming chunks before the connection closes.
        """
        url = f"{self.base_url}{endpoint}"
        last_error = None

        for attempt in range(self.max_retries):
            try:
                logger.debug(f"Attempt {attempt + 1}/{self.max_retries} for {method} {url}")

                response = self.session.request(
                    method=method,
                    url=url,
                    timeout=self.timeout,
                    stream=True,  # always stream to avoid premature-end errors
                    **kwargs
                )

                logger.debug(f"Response status: {response.status_code}")

                if response.status_code == 200:
                    content_type = response.headers.get('content-type', '').lower()

                    # Consume the stream chunk by chunk
                    chunks = []
                    for chunk in response.iter_content(chunk_size=None, decode_unicode=True):
                        if chunk:
                            chunks.append(chunk)
                    text = "".join(chunks)

                    if 'application/json' in content_type:
                        return safe_json_parse(text)
                    else:
                        logger.info(f"Received streaming/text response: {len(text)} characters")
                        return {"content": text, "success": True, "content_type": content_type}

                elif response.status_code == 404:
                    return {"error": f"Endpoint not found: {endpoint}", "success": False}
                elif response.status_code == 500:
                    body = response.text
                    return {"error": f"Internal server error: {body[:200]}", "success": False}
                else:
                    error_msg = f"HTTP {response.status_code}: {response.text[:200]}"
                    logger.warning(error_msg)
                    if attempt == self.max_retries - 1:
                        return {"error": error_msg, "success": False}

            except requests.exceptions.Timeout:
                last_error = f"Request timeout after {self.timeout}s"
                logger.warning(f"{last_error} (attempt {attempt + 1})")

            except requests.exceptions.ConnectionError as e:
                last_error = f"Connection error: {str(e)}"
                logger.warning(f"{last_error} (attempt {attempt + 1})")

            except requests.exceptions.RequestException as e:
                last_error = f"Request error: {str(e)}"
                logger.error(f"{last_error} (attempt {attempt + 1})")

            except Exception as e:
                last_error = f"Unexpected error: {str(e)}"
                logger.error(f"{last_error} (attempt {attempt + 1})")

            # Exponential backoff (skip after last attempt)
            if attempt < self.max_retries - 1:
                wait_time = 2 ** attempt
                logger.debug(f"Waiting {wait_time}s before retry...")
                time.sleep(wait_time)

        error_msg = f"All {self.max_retries} attempts failed. Last error: {last_error}"
        logger.error(error_msg)
        return {"error": error_msg, "success": False}
    
    def get(self, endpoint: str, **kwargs) -> Dict[str, Any]:
        """Make GET request with retry logic."""
        return self._make_request_with_retry('GET', endpoint, **kwargs)
    
    def post(self, endpoint: str, json_data: Dict = None, files: Dict = None, **kwargs) -> Dict[str, Any]:
        """Make POST request with retry logic."""
        if json_data is not None:
            kwargs['json'] = json_data
        if files is not None:
            kwargs['files'] = files
            # Remove Content-Type header for file uploads
            headers = kwargs.get('headers', {})
            headers.pop('Content-Type', None)
            kwargs['headers'] = headers
            
        return self._make_request_with_retry('POST', endpoint, **kwargs)
    
    def health_check(self) -> bool:
        """
        Check if the backend service is healthy.
        
        Returns:
            True if backend is healthy, False otherwise
        """
        try:
            response = self.get('/health')
            return response.get('success', True) and 'error' not in response
        except Exception as e:
            logger.error(f"Health check failed: {str(e)}")
            return False
