import streamlit as st
from services.api_client import APIClient
from utils.session_state import add_message, get_chat_history

PRICING = {
    "anthropic.claude-3-5-sonnet-20241022-v2:0":        {"input": 0.003,   "output": 0.015},
    "au.anthropic.claude-haiku-4-5-20251001-v1:0":      {"input": 0.001,   "output": 0.005},
    "global.anthropic.claude-haiku-4-5-20251001-v1:0":  {"input": 0.001,   "output": 0.005},
    "global.amazon.nova-2-lite-v1:0":                   {"input": 0.00006, "output": 0.00024},
}

def _render_meta(meta: dict):
    """Render response metadata as a single light-grey info line."""
    model_id = meta.get("model", "N/A")
    latency  = meta.get("latency_ms", "N/A")
    input_t  = meta.get("input_tokens", 0)
    output_t = meta.get("output_tokens", 0)
    p        = PRICING.get(model_id, {"input": 0.003, "output": 0.015})
    cost     = (input_t / 1000) * p["input"] + (output_t / 1000) * p["output"]
    line = (
        f"Model: {model_id} &nbsp;|&nbsp; "
        f"Latency: {latency} ms &nbsp;|&nbsp; "
        f"Input Tokens: {input_t} &nbsp;|&nbsp; "
        f"Output Tokens: {output_t} &nbsp;|&nbsp; "
        f"Query Cost: ${cost:.4f}"
    )
    st.markdown(
        f"<p style='color:#888;font-size:12px;margin:2px 0 8px 0'>{line}</p>",
        unsafe_allow_html=True
    )


def render_chat_interface():
    """Render the main chat interface."""
    api_client = APIClient()

    # Process pending message from sidebar
    if st.session_state.get("process_message"):
        st.session_state.process_message = False
        if st.session_state.chat_history:
            last_message = st.session_state.chat_history[-1]
            if last_message["role"] == "user":
                with st.chat_message("assistant"):
                    with st.spinner("Thinking..."):
                        response = api_client.send_message(last_message["content"])
                        if response and "content" in response:
                            st.write(response["content"], unsafe_allow_html=True)
                            add_message("assistant", response["content"], response.get("metadata"))
                        else:
                            error_msg = "Sorry, I couldn't process your message. Please try again."
                            st.markdown(error_msg)
                            add_message("assistant", error_msg)

    # Display chat history
    for message in get_chat_history():
        with st.chat_message(message["role"]):
            if message["role"] == "assistant":
                st.write(message["content"], unsafe_allow_html=True)
            else:
                st.write(message["content"])
            if message["role"] == "assistant" and "metadata" in message:
                _render_meta(message["metadata"])

    # Chat input
    if prompt := st.chat_input("Type your message..."):
        add_message("user", prompt)
        with st.chat_message("user"):
            st.write(prompt)

        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                response = api_client.send_message(prompt)
                if response and "content" in response:
                    st.write(response["content"], unsafe_allow_html=True)
                    add_message("assistant", response["content"], response.get("metadata"))
                    if response.get("metadata"):
                        _render_meta(response["metadata"])
                else:
                    error_msg = "Sorry, I couldn't process your message. Please try again."
                    st.markdown(error_msg)
                    add_message("assistant", error_msg)
