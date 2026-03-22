from strands import tool
import requests

@tool
def http_request(url: str, method: str = "GET", headers: dict = None, data: dict = None) -> str:
    """
    Make HTTP requests to external APIs.
    
    Args:
        url: The URL to make the request to
        method: HTTP method (GET, POST, PUT, DELETE)
        headers: Optional headers dictionary
        data: Optional data for POST/PUT requests
    
    Returns:
        Response text or error message
    """
    try:
        response = requests.request(
            method=method.upper(),
            url=url,
            headers=headers or {},
            json=data,
            timeout=30
        )
        
        if response.status_code == 200:
            return response.text
        else:
            return f"HTTP {response.status_code}: {response.text}"
            
    except requests.exceptions.RequestException as e:
        return f"Request failed: {str(e)}"