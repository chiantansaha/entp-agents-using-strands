# Streamlit AI Chatbot Frontend

A modern AI chatbot interface built with Streamlit, designed for deployment on AWS ECS.

## Features

- 🤖 AI chat interface with message history
- 📁 File upload functionality
- 🔧 Sidebar navigation and settings
- 🐳 Docker containerization with uv package manager
- ☁️ AWS ECS deployment ready

## Quick Start

### Local Development

```bash
# Install dependencies with uv
pip install uv
uv pip install -r requirements.txt

# Run the application
streamlit run app.py
```

### Docker

```bash
# Build the image
docker build -t streamlit-frontend .

# Run the container
docker run -p 8501:8501 -e BACKEND_URL=http://localhost:8000 streamlit-frontend
```

## Environment Variables

- `BACKEND_URL`: FastAPI backend service URL (default: http://localhost:8000)
- `LOG_LEVEL`: Application logging level (default: INFO)

## Project Structure

```
frontend/
├── app.py                 # Main Streamlit application
├── components/
│   ├── chat.py           # Chat interface component
│   ├── sidebar.py        # Sidebar navigation component
│   └── file_upload.py    # File upload component
├── services/
│   └── api_client.py     # FastAPI backend client
├── utils/
│   └── session_state.py  # Session management utilities
├── requirements.txt      # Python dependencies
├── pyproject.toml        # uv configuration
└── Dockerfile           # Container definition
```
