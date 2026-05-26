#!/bin/bash

# Alternative Build and Deploy Script
# Supports multiple container builders: Docker, Podman, or Buildah
# Usage: ./build-and-deploy-alternative.sh <team_name> <service_type> <dockerfile_path> [image_tag]

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
    echo "Example: $0 team1 frontend ./frontend/Dockerfile"
    exit 1
fi

if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "Error: Dockerfile not found at $DOCKERFILE_PATH"
    exit 1
fi

# Set variables
ECR_REPO="awsugsg-${TEAM_NAME}-${SERVICE_TYPE}"
BUILD_CONTEXT=$(dirname "$DOCKERFILE_PATH")

echo "🔨 Building container image..."
echo "   Repository: ${ECR_REPO}"
echo "   Tag: ${IMAGE_TAG}"
echo "   Context: ${BUILD_CONTEXT}"
echo "   Dockerfile: ${DOCKERFILE_PATH}"

# Detect available container builder
BUILDER=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    BUILDER="docker"
    echo "✅ Using Docker"
elif command -v podman >/dev/null 2>&1; then
    BUILDER="podman"
    echo "✅ Using Podman"
elif command -v buildah >/dev/null 2>&1; then
    BUILDER="buildah"
    echo "✅ Using Buildah"
else
    echo "❌ No container builder found!"
    echo ""
    echo "Please install one of the following:"
    echo "1. Docker Desktop: https://www.docker.com/products/docker-desktop/"
    echo "2. Podman: brew install podman"
    echo "3. Buildah: brew install buildah"
    echo ""
    echo "Or use AWS CodeBuild for serverless container building:"
    echo "./scripts/build-with-codebuild.sh ${TEAM_NAME} ${SERVICE_TYPE} ${DOCKERFILE_PATH} ${IMAGE_TAG}"
    exit 1
fi

# Build image based on available builder
case $BUILDER in
    "docker")
        docker build -t ${ECR_REPO}:${IMAGE_TAG} -f ${DOCKERFILE_PATH} ${BUILD_CONTEXT}
        ;;
    "podman")
        podman build -t ${ECR_REPO}:${IMAGE_TAG} -f ${DOCKERFILE_PATH} ${BUILD_CONTEXT}
        ;;
    "buildah")
        buildah build -t ${ECR_REPO}:${IMAGE_TAG} -f ${DOCKERFILE_PATH} ${BUILD_CONTEXT}
        ;;
esac

echo "✅ Image built successfully: ${ECR_REPO}:${IMAGE_TAG}"

# Deploy using the deploy script
echo "🚀 Deploying to ECS..."
if [ -f "./scripts/deploy-service.sh" ]; then
    ./scripts/deploy-service.sh ${TEAM_NAME} ${SERVICE_TYPE} ${IMAGE_TAG}
else
    echo "⚠️  deploy-service.sh not found. Manual deployment required."
    echo ""
    echo "Manual deployment steps:"
    echo "1. Get ECR login token:"
    echo "   aws ecr get-login-password --region \$(terraform output -raw region) | ${BUILDER} login --username AWS --password-stdin \$(terraform output -json ${SERVICE_TYPE}_ecr_repository_urls | jq -r '.${TEAM_NAME}')"
    echo ""
    echo "2. Tag image for ECR:"
    echo "   ${BUILDER} tag ${ECR_REPO}:${IMAGE_TAG} \$(terraform output -json ${SERVICE_TYPE}_ecr_repository_urls | jq -r '.${TEAM_NAME}'):${IMAGE_TAG}"
    echo ""
    echo "3. Push to ECR:"
    echo "   ${BUILDER} push \$(terraform output -json ${SERVICE_TYPE}_ecr_repository_urls | jq -r '.${TEAM_NAME}'):${IMAGE_TAG}"
    echo ""
    echo "4. Update ECS service:"
    echo "   aws ecs update-service --cluster awsugsg-${TEAM_NAME} --service ${TEAM_NAME}-${SERVICE_TYPE} --force-new-deployment"
fi