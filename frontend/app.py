import streamlit as st
from utils.session_state import initialize_session_state
from components.sidebar import render_sidebar
from components.chat import render_chat_interface

# Page configuration
st.set_page_config(
    page_title="AWS Resource Explorer",
    page_icon="🔍",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Professional CSS styling
st.markdown("""
<style>
    .stApp {
        background-color: #ffffff;
    }
    .main .block-container {
        background-color: #f8f9fc;
        border-radius: 8px;
        padding: 2rem;
        border: 1px solid #e6e9f0;
    }
    .stTitle {
        color: #262730 !important;
        font-weight: 600;
    }
    .stMarkdown {
        color: #3c3f45;
    }
    .stSubheader {
        color: #262730 !important;
    }
</style>
""", unsafe_allow_html=True)

# Enable performance features in Streamlit 1.50
if hasattr(st, 'cache_data'):
    st.cache_data.clear()

# Initialize session state
initialize_session_state()

# Render sidebar
render_sidebar()

# Professional header
st.markdown("""
<div style="text-align: center; margin-bottom: 2rem;">
    <h1 style="color: #262730; font-size: 2.5rem; font-weight: 600;">
        🔍 AWS Resource Explorer
    </h1>
    <p style="color: #3c3f45; font-size: 1rem;">
        Query and manage your AWS resources across all regions
    </p>
</div>
""", unsafe_allow_html=True)

# Connection status indicator
if st.session_state.backend_status == "disconnected":
    st.markdown("""
    <div style="background: #fff3cd; padding: 1rem; border-radius: 6px; border-left: 4px solid #ff9800;">
        ⚠️ <strong>Backend Unavailable</strong> - Please check if the backend service is running.
    </div>
    """, unsafe_allow_html=True)
else:
    st.markdown("""
    <div style="background: #e8f5e9; padding: 1rem; border-radius: 6px; border-left: 4px solid #09a043;">
        ✅ <strong>Backend Connected</strong> - Ready to query AWS resources.
    </div>
    """, unsafe_allow_html=True)


# Render chat interface
render_chat_interface()
