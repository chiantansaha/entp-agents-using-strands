# Chirantan's - AWS Cloud AI Assistant Chatbot
# Enterprise Agents using Strands
# Architecture & Implementation: How to build Enterprise Agents using Strands

A full-stack AI chatbot application that provides weather information and AWS resource queries using AWS Bedrock and Strands agents.

## Architecture

- **Frontend**: Streamlit web application with chat interface
- **Backend**: FastAPI service with AWS Bedrock integration (dual backend support)
- **AI Model**: Amazon Nova 2 Live v1.0 via Bedrock
- **Deployment**: AWS ECS with Docker containers

## Backend Services

### ☁️ AWS Agent Service (`aws_agent.py`) - **Default**
- AWS resource queries using AWS CLI integration
- EC2, S3, Lambda, RDS, IAM resource management
- CloudFormation stack information
- Comprehensive AWS service coverage

## Project Structure

```
.
├── backend/                        # FastAPI backend service
│   ├── aws_agent.py               # Main FastAPI app with streaming endpoint
│   ├── aws_tool.py                # use_aws Strands tool + AWSToolManager
│   ├── http_tool.py               # HTTP utility tool
│   ├── mock_server.py             # Development mock server
│   ├── mock_strands.py            # Mock Strands/Agent for local dev (no Bedrock)
│   ├── requirements.txt           # Python dependencies
│   └── Dockerfile                 # Container configuration
├── frontend/                      # Streamlit web application
│   ├── app.py                     # Main Streamlit entry point
│   ├── components/
│   │   ├── chat.py                # Chat interface + metadata rendering
│   │   ├── sidebar.py             # Navigation sidebar
│   │   └── file_upload.py         # File upload component
│   ├── services/
│   │   └── api_client.py          # Backend API client
│   ├── utils/
│   │   ├── http_client.py         # HTTP client with retry + streaming support
│   │   ├── json_parser.py         # Safe JSON parsing utilities
│   │   └── session_state.py       # Streamlit session management
│   ├── requirements.txt           # Python dependencies
│   └── Dockerfile                 # Container configuration
├── scripts/                       # Deployment & dev helper scripts
│   ├── dev-start.sh               # Start full dev environment
│   ├── dev-frontend.sh            # Start frontend only
│   ├── dev-backend.sh             # Start backend only
│   ├── build-and-deploy.sh        # Build & push Docker images to AWS
│   ├── deploy-service.sh          # Deploy ECS service
│   └── validate-team-deployment.sh# Validate ECS deployment
├── dev.sh                         # Main dev script (start/stop/status/logs)
├── docker-compose.yml             # Docker Compose for local stack
├── test_regions.py                # Region connectivity tests
├── test_ssm.py                    # SSM parameter tests
└── README.md
```

## Features

- **Interactive Chat Interface**: Streamlit-based web UI with real-time messaging
- **AWS Resource Management**: Query and manage AWS resources via natural language
- **AWS Bedrock Integration**: Amazon Nova 2 Lite v1.0 model for natural language processing
- **Strands Agent Framework**: Structured AI agent implementation
- **Docker Containerization**: Full containerized deployment
- **AWS ECS Deployment**: Production-ready cloud deployment

## Quick Start

### Native Development Environment (Recommended)

**Prerequisites:**
- Python 3.8+
- UV package manager ([installation guide](https://github.com/astral-sh/uv))
- AWS CLI configured with credentials

**Setup AWS Credentials:**
```bash
# Export AWS credentials in your terminal (if this is done then next step not needed)
eval "$(aws configure export-credentials --format env)"

# Export AWS Default Region
export AWS_DEFAULT_REGION=ap-southeast-2

# (Optional) Export AWS credentials in your terminal
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_SESSION_TOKEN=your_session_token  # if using temporary credentials

# Check 
aws sts get-caller-identity
```

#### Option 1: Development Helper Scripts (Fastest)

**Setup and start services:**
```bash
# Setup virtual environments and dependencies
./dev.sh setup

# Start both services (uses AWS agent backend by default)
./dev.sh start

# Start with specific backend
BACKEND_APP=aws_agent ./dev.sh start    # AWS resource queries (default)

# Check status
./dev.sh status
```

**Access Services:**
- Frontend: http://localhost:8501
- Backend API: http://localhost:9083
- Health Check: http://localhost:9083/health

#### Option 2: Manual Service Management

**Setup virtual environments:**
```bash
# Backend setup
cd backend
uv venv
uv pip install -r requirements.txt
cd ..

# Frontend setup
cd frontend
uv venv
uv pip install -r requirements.txt
cd ..
```

**Start services manually:**
```bash
# Terminal 1: Backend (choose one)
cd backend
.venv/bin/uvicorn aws_agent:app --host 0.0.0.0 --port 9083 --reload    # AWS agent
.venv/bin/uvicorn weather:app --host 0.0.0.0 --port 9083 --reload      # Weather service

# Terminal 2: Frontend
cd frontend
.venv/bin/streamlit run app.py --server.port 8501 --server.address 0.0.0.0
```

**Alternative direct Python execution:**
```bash
# Backend (from backend/ directory - choose one)
python aws_agent.py    # AWS resource queries (default)
python weather.py      # Weather service

# Frontend (from frontend/ directory)
streamlit run app.py
```

### WSL/Docker Development Environment

**Prerequisites:**
- WSL2 with Ubuntu (for Windows)
- Docker Desktop with WSL2 integration
- AWS CLI configured with credentials

**Start Development Environment:**
```bash
# Start the complete development stack with Docker Compose
docker-compose up --build

# Or run in detached mode
docker-compose up -d --build
```

**Access Services:**
- Frontend: http://localhost:8083
- Backend API: http://localhost:9083

**Stop Services:**
```bash
docker-compose down
```

## Development Scripts

### Main Development Script (`dev.sh`)

**Available Commands:**
```bash
./dev.sh setup          # Setup virtual environments
./dev.sh start [service] # Start services (all/backend/frontend)
./dev.sh stop [service]  # Stop services
./dev.sh restart         # Restart services
./dev.sh status          # Show service status
./dev.sh logs [service]  # Show service logs
./dev.sh help            # Show help
```

## Dependencies

### Frontend
- Streamlit 1.50.0
- Requests for API communication
- Python multipart support

### Backend
- FastAPI for REST API
- Uvicorn ASGI server
- Pydantic for data validation
- Strands agents framework
- AWS Bedrock integration
- AWS CLI integration (aws_agent)
- HTTP request tools (weather service)

## Troubleshooting

### Common Issues

**UV not found:**
```bash
# Install UV
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Port already in use:**
```bash
# Stop services and check status
./dev.sh stop
./dev.sh status

# Or kill processes manually
lsof -ti:8501 | xargs kill  # Frontend
lsof -ti:9083 | xargs kill  # Backend
```

**Virtual environment issues:**
```bash
# Clean and recreate environments
./dev.sh stop
rm -rf backend/.venv frontend/.venv
./dev.sh setup
```

**Backend service selection:**
```bash
# Check current backend app
echo $BACKEND_APP

# Set backend app preference (persistent)
export BACKEND_APP=aws_agent    # Default

# Or use one-time selection
BACKEND_APP=weather ./dev.sh start backend
```

## Deployment

Deploy to AWS ECS:
```bash
./scripts/build-and-deploy.sh <team_name> frontend ./frontend/Dockerfile
./scripts/build-and-deploy.sh <team_name> backend ./backend/Dockerfile
```

Validate deployment:
```bash
./scripts/validate-team-deployment.sh <team_name>
```
