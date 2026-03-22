import streamlit as st
import os
from typing import List, Dict, Optional

# Model mapping
MODEL_NAMES = {
    "anthropic.claude-3-5-sonnet-20241022-v2:0": "Claude 3.5 Sonnet",
    "au.anthropic.claude-haiku-4-5-20251001-v1:0": "Claude Haiku (AU)",
    "global.anthropic.claude-haiku-4-5-20251001-v1:0": "Claude Haiku (Global)",
    "global.amazon.nova-2-lite-v1:0": "Amazon Nova Lite"
}

def initialize_session_state():
    """Initialize session state variables if they don't exist."""
    if "chat_history" not in st.session_state:
        st.session_state.chat_history = []
    
    if "uploaded_files" not in st.session_state:
        st.session_state.uploaded_files = []
    
    if "backend_status" not in st.session_state:
        st.session_state.backend_status = "unknown"
    
    if "current_file" not in st.session_state:
        st.session_state.current_file = None
    
    if "session_token_usage" not in st.session_state:
        st.session_state.session_token_usage = {
            'queries': 0,
            'input': 0,
            'output': 0
        }
    
    if "last_query_tokens" not in st.session_state:
        st.session_state.last_query_tokens = {'input': 0, 'output': 0}
    
    if "selected_model" not in st.session_state:
        default_model_id = os.environ.get("MODEL_ID", "global.amazon.nova-2-lite-v1:0")
        default_model_name = MODEL_NAMES.get(default_model_id, "Amazon Nova Lite")
        st.session_state.selected_model = {
            "id": default_model_id,
            "name": default_model_name
        }

def add_message(role: str, content: str, metadata: Optional[Dict] = None):
    """Add a message to chat history."""
    message = {"role": role, "content": content}
    if metadata:
        message["metadata"] = metadata
        # Track token usage for assistant messages
        if role == "assistant":
            st.session_state.session_token_usage['queries'] += 1
            input_tokens = metadata.get('input_tokens', 0)
            output_tokens = metadata.get('output_tokens', 0)
            st.session_state.session_token_usage['input'] += input_tokens
            st.session_state.session_token_usage['output'] += output_tokens
            st.session_state.last_query_tokens = {'input': input_tokens, 'output': output_tokens}
    st.session_state.chat_history.append(message)

def clear_chat():
    """Clear chat history."""
    st.session_state.chat_history = []

def get_chat_history() -> List[Dict[str, str]]:
    """Get current chat history."""
    return st.session_state.chat_history
