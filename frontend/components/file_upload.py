import streamlit as st
from services.api_client import APIClient
from utils.session_state import add_message

def render_file_upload():
    """Render file upload interface."""
    api_client = APIClient()
    
    uploaded_file = st.file_uploader(
        "Upload a file", 
        type=['txt', 'pdf', 'docx', 'csv', 'json'],
        help="Upload files to analyze or discuss with the AI"
    )
    
    if uploaded_file is not None:
        if st.button("Process File"):
            with st.spinner("Uploading file..."):
                result = api_client.upload_file(uploaded_file)
                
                if result:
                    success_msg = f"✅ File '{uploaded_file.name}' uploaded successfully!"
                    st.success(success_msg)
                    add_message("system", success_msg)
                    st.session_state.uploaded_files.append(uploaded_file.name)
                else:
                    error_msg = f"❌ Failed to upload '{uploaded_file.name}'"
                    st.error(error_msg)
                    add_message("system", error_msg)
