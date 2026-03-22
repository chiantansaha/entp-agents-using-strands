# Development & Deployment Scripts

Scripts for local development and AWS deployment.

## 🚀 Development Scripts

### `dev-start.sh`
Starts both frontend and mock backend with Docker Compose.
- Builds containers if needed
- Runs both services in parallel
- Handles cleanup on Ctrl+C

### `dev-frontend.sh`
Starts only the Streamlit frontend service.
- Uses Docker Compose
- Runs on http://localhost:8501

### `dev-backend.sh`
Starts only the mock backend service.
- Simple HTTP server with mock endpoints
- Runs on http://localhost:8000
- Endpoints: `/health`, `/chat`, `/upload`

## 🏗️ Deployment Scripts

### `build-and-deploy.sh`
Builds Docker images and deploys to AWS ECS.
```bash
./scripts/build-and-deploy.sh <team_name> <service_type> <dockerfile_path> [image_tag]
# Example: ./scripts/build-and-deploy.sh alpha frontend ./frontend/Dockerfile
```

### `deploy-service.sh`
Deploys a specific service to ECS (called by build-and-deploy).
```bash
./scripts/deploy-service.sh <team_name> <service_type> [image_tag] [region]
# Example: ./scripts/deploy-service.sh alpha frontend v1.2.3
```

### `validate-team-deployment.sh`
Validates team-based ECS deployment.
```bash
./scripts/validate-team-deployment.sh <team_name>
# Example: ./scripts/validate-team-deployment.sh alpha
```

## 📋 Usage Examples

### Development
```bash
# Start complete development environment
./scripts/dev-start.sh

# Start individual services
./scripts/dev-frontend.sh  # Frontend only
./scripts/dev-backend.sh   # Backend only
```

### Deployment
```bash
# Build and deploy frontend
./scripts/build-and-deploy.sh alpha frontend ./frontend/Dockerfile

# Validate deployment
./scripts/validate-team-deployment.sh alpha
```

## 🐳 Docker Compose

The development environment uses `docker-compose.yml` with:
- **Frontend**: Streamlit app with live reload
- **Backend**: Mock Python HTTP server
- **Networking**: Services can communicate via service names

## 🔧 Environment Variables

### Development
- `BACKEND_URL`: Backend service URL (default: http://backend:8000)
- `LOG_LEVEL`: Application logging level (default: INFO)

### Deployment
- `AWS_REGION`: AWS region for deployment (default: ap-southeast-2)

## 🌐 Access Points

### Development
- **Frontend**: http://localhost:8501
- **Backend**: http://localhost:8000

### Production
- Access via ALB DNS name from Terraform outputs
