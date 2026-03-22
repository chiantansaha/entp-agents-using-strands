import streamlit as st 
from services.api_client import APIClient
from components.file_upload import render_file_upload
from utils.session_state import clear_chat, add_message

def render_sidebar():
    """Render sidebar with navigation and settings."""
    with st.sidebar:
        st.title("🤖 AI Chat")
        
        # Connection status
        api_client = APIClient()
        if api_client.health_check():
            st.success("🟢 Connected")
            st.session_state.backend_status = "connected"
        else:
            st.error("🔴 Disconnected")
            st.session_state.backend_status = "disconnected"
        
        st.divider()
        
        # New chat button
        if st.button("🗨️ New Chat", use_container_width=True):
            clear_chat()
            st.rerun()
        
        st.divider()

        # AWS Resource Management
        st.subheader("🔄 AWS Resources")
        
        option = st.selectbox(
            "Which AWS Resource related question do you have?",
            ( "Please list all S3 buckets in the current account."
            , "Please list all active EC2 instances in the current account."
            ),
            index=None,
            placeholder="Select AWS Resource query...",
            key="aws_resource_select"
        )

        st.write("You selected:", option)

        if option and option != st.session_state.get("last_selected_option"):
            st.session_state.last_selected_option = option
            add_message("user", option)
            st.session_state.process_message = True
            st.rerun()  

        st.divider()

        # Model Selection
        st.subheader("🤖 Model Selection")
        models = [
            {"id": "anthropic.claude-3-5-sonnet-20241022-v2:0", "name": "Claude 3.5 Sonnet"},
            {"id": "au.anthropic.claude-haiku-4-5-20251001-v1:0", "name": "Claude Haiku (AU)"},
            {"id": "global.anthropic.claude-haiku-4-5-20251001-v1:0", "name": "Claude Haiku (Global)"},
            {"id": "global.amazon.nova-2-lite-v1:0", "name": "Amazon Nova Lite"}
        ]
        
        model_options = [model["name"] for model in models]
        current_model_name = st.session_state.selected_model["name"]
        default_index = model_options.index(current_model_name) if current_model_name in model_options else 0
        selected_model_name = st.selectbox(
            "Select AI Model",
            model_options,
            index=default_index,
            key="model_selector"
        )
        
        # Update selected model in session state
        for model in models:
            if model["name"] == selected_model_name:
                st.session_state.selected_model = model
                break
        
        selected_model = st.session_state.selected_model
        
        # Display selected model info
        st.info(f"🤖 **Active Model**: {selected_model['name']}")
        
        # Display token usage and cost
        if 'session_token_usage' in st.session_state and st.session_state.session_token_usage['queries'] > 0:
            usage = st.session_state.session_token_usage
            
            # Model pricing (per 1K tokens)
            pricing = {
                "anthropic.claude-3-5-sonnet-20241022-v2:0": {"input": 0.003, "output": 0.015},
                "au.anthropic.claude-haiku-4-5-20251001-v1:0": {"input": 0.001, "output": 0.005},
                "global.anthropic.claude-haiku-4-5-20251001-v1:0": {"input": 0.001, "output": 0.005},
                "global.amazon.nova-2-lite-v1:0": {"input": 0.00006, "output": 0.00024}
            }
            
            model_pricing = pricing.get(selected_model["id"], {"input": 0.003, "output": 0.015})
            input_cost = (usage['input'] / 1000) * model_pricing['input']
            output_cost = (usage['output'] / 1000) * model_pricing['output']
            total_cost = input_cost + output_cost
            
            # Get last query tokens if available
            last_query_info = ""
            if 'last_query_tokens' in st.session_state:
                last_in = st.session_state.last_query_tokens.get('input', 0)
                last_out = st.session_state.last_query_tokens.get('output', 0)
                last_cost = (last_in / 1000) * model_pricing['input'] + (last_out / 1000) * model_pricing['output']
                last_query_info = f"\n\n**Last Query:**  \nInput: {last_in:,} | Output: {last_out:,}  \nCost: ${last_cost:.4f}"
            
            st.success(f"""
            📊 **Session Total**  
            Queries: {usage['queries']}  
            Input: {usage['input']:,} tokens  
            Output: {usage['output']:,} tokens  
            💵 Total Cost: ${total_cost:.4f}{last_query_info}
            """)

        st.divider()

        # File upload section
        st.subheader("📁 File Upload")
        render_file_upload()
        
        # Show uploaded files
        if st.session_state.uploaded_files:
            st.subheader("📋 Uploaded Files")
            for file in st.session_state.uploaded_files:
                st.text(f"• {file}")
        
        st.divider()
        
        # Settings
        st.subheader("⚙️ Settings")
        st.slider("Max Messages", 10, 100, 50, key="max_messages")
        st.checkbox("Auto-scroll", value=True, key="auto_scroll")
