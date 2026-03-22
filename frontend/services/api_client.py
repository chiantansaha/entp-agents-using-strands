import os
import logging
import time
from typing import Dict, Optional
import streamlit as st
from utils.http_client import HTTPClient
from utils.json_parser import validate_response_format

logger = logging.getLogger(__name__)

class APIClient:
    def __init__(self):
        self.base_url = os.getenv("BACKEND_URL", "http://localhost:9083")
        self.http_client = HTTPClient(self.base_url, timeout=120, max_retries=3)
    
    def health_check(self) -> bool:
        """Check if backend is healthy."""
        try:
            return self.http_client.health_check()
        except Exception as e:
            logger.error(f"Health check failed: {str(e)}")
            return False
    
    def send_message(self, message: str) -> Optional[Dict]:
        """Send chat message to backend."""
        try:
            payload = {"query": message}
            logger.info(f"Sending message to backend: {message[:50]}...")
            
            # Track timing
            start_time = time.time()
            
            response = self.http_client.post("/aws-query-streaming", json_data=payload)
            
            end_time = time.time()
            latency_ms = int((end_time - start_time) * 1000)
            
            if "error" in response:
                error_msg = response["error"]
                logger.error(f"Backend error: {error_msg}")
                st.error(f"Backend error: {error_msg}")
                return None
            
            # Token estimation: ~4 chars per token (works for both plain text and HTML)
            input_tokens = max(1, len(message) // 4)

            if isinstance(response, dict) and "raw_response" in response:
                text_content = response["raw_response"]
                output_tokens = max(1, len(text_content) // 4)
                logger.info(f"Received streaming text response: {len(text_content)} characters")
                return {
                    "content": text_content,
                    "metadata": {
                        "model": st.session_state.selected_model["id"],
                        "latency_ms": latency_ms,
                        "input_tokens": int(input_tokens),
                        "output_tokens": int(output_tokens)
                    }
                }
            
            # If we somehow got valid JSON, handle it normally
            if isinstance(response, dict) and "content" in response:
                content = response["content"]
                output_tokens = max(1, len(content) // 4) if isinstance(content, str) else 1
                logger.info("Successfully received JSON response from backend")
                response["metadata"] = {
                    "model": st.session_state.selected_model["id"],
                    "latency_ms": latency_ms,
                    "input_tokens": int(input_tokens),
                    "output_tokens": int(output_tokens)
                }
                return response
            
            # If we got something else, treat it as text content
            if isinstance(response, str):
                output_tokens = max(1, len(response) // 4)
                logger.info(f"Received direct text response: {len(response)} characters")
                return {
                    "content": response,
                    "metadata": {
                        "model": st.session_state.selected_model["id"],
                        "latency_ms": latency_ms,
                        "input_tokens": int(input_tokens),
                        "output_tokens": int(output_tokens)
                    }
                }
            
            logger.error(f"Unexpected response type: {type(response)}")
            st.error("Received unexpected response format from backend")
            return None
            
        except Exception as e:
            error_msg = f"Failed to send message: {str(e)}"
            logger.error(error_msg)
            st.error(error_msg)
            return None
    
    def upload_file(self, file) -> Optional[Dict]:
        """Upload file to backend."""
        try:
            logger.info(f"Uploading file: {file.name}")
            files = {"file": (file.name, file, file.type)}
            
            response = self.http_client.post("/upload", files=files)
            
            if "error" in response:
                error_msg = response["error"]
                logger.error(f"File upload error: {error_msg}")
                st.error(f"File upload error: {error_msg}")
                return None
            
            logger.info("Successfully uploaded file")
            return response
            
        except Exception as e:
            error_msg = f"Failed to upload file: {str(e)}"
            logger.error(error_msg)
            st.error(error_msg)
            return None
