#!/bin/bash

# Build and Deploy Script
# Usage: ./build-and-deploy.sh <team_name> <service_type> <dockerfile_path> [image_tag]

set -e

# Change to project root
cd "$(dirname "$0")/.."

# Parse arguments
TEAM_NAME=${1}
SERVICE_TYPE=${2}  # frontend or backend
DOCKERFILE_PATH=${3}
IMAGE_TAG=${4:-latest}

# Validate arguments
if [ -z "$TEAM_NAME" ] || [ -z "$SERVICE_TYPE" ] || [ -z "$DOCKERFILE_PATH" ]; then
    echo "Usage: $0 <team_name> <frontend|backend> <dockerfile_path> [image_tag]"
    echo "Example: $0 alpha frontend ./frontend/Dockerfile"
    exit 1
fi

if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "Error: Dockerfile not found at $DOCKERFILE_PATH"
    exit 1
fi

# Set variables
ECR_REPO="eba-${TEAM_NAME}-${SERVICE_TYPE}"
BUILD_CONTEXT=$(dirname "$DOCKERFILE_PATH")

echo "🔨 Building Docker image..."
echo "   Repository: ${ECR_REPO}"
echo "   Tag: ${IMAGE_TAG}"
echo "   Context: ${BUILD_CONTEXT}"
echo "   Dockerfile: ${DOCKERFILE_PATH}"

# Build image
docker build -t ${ECR_REPO}:${IMAGE_TAG} -f ${DOCKERFILE_PATH} ${BUILD_CONTEXT}

# Deploy using the deploy script
echo "🚀 Deploying to ECS..."
./scripts/deploy-service.sh ${TEAM_NAME} ${SERVICE_TYPE} ${IMAGE_TAG}
