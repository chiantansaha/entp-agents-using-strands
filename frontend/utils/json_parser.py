"""
Safe JSON parsing utilities with comprehensive error handling.
"""
import json
import logging
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)

def safe_json_parse(response_text: str, default: Optional[Dict] = None) -> Dict[str, Any]:
    """
    Safely parse JSON response with proper error handling.
    
    Args:
        response_text: The response text to parse
        default: Default value to return if parsing fails
        
    Returns:
        Parsed JSON as dictionary or error dictionary
    """
    if default is None:
        default = {"error": "Failed to parse response"}
    
    # Handle empty or None response
    if not response_text or response_text.strip() == "":
        logger.warning("Received empty response from backend")
        return {"error": "Empty response from backend", "success": False}
    
    # Handle whitespace-only response
    if response_text.strip() == "":
        logger.warning("Received whitespace-only response from backend")
        return {"error": "Empty response from backend", "success": False}
    
    try:
        parsed = json.loads(response_text)
        logger.debug(f"Successfully parsed JSON response: {type(parsed)}")
        return parsed
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}, Response: '{response_text[:100]}...'")
        return {
            "error": f"Invalid JSON response: {str(e)}", 
            "success": False,
            "raw_response": response_text[:200]  # First 200 chars for debugging
        }
    except Exception as e:
        logger.error(f"Unexpected error parsing JSON: {str(e)}")
        return {
            "error": f"Unexpected error parsing response: {str(e)}", 
            "success": False
        }

def validate_response_format(response_data: Dict[str, Any], required_fields: list = None) -> bool:
    """
    Validate that response has expected format.
    
    Args:
        response_data: Parsed response data
        required_fields: List of required field names
        
    Returns:
        True if response format is valid
    """
    if not isinstance(response_data, dict):
        logger.error(f"Response is not a dictionary: {type(response_data)}")
        return False
    
    if "error" in response_data:
        logger.warning(f"Response contains error: {response_data['error']}")
        return False
    
    if required_fields:
        missing_fields = [field for field in required_fields if field not in response_data]
        if missing_fields:
            logger.error(f"Response missing required fields: {missing_fields}")
            return False
    
    return True
