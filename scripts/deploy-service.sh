#!/bin/bash

# EBA Service Deployment Script
# Usage: ./deploy-service.sh <team_name> <service_type> <image_tag> [region]

set -e

# Change to project root
cd "$(dirname "$0")/.."

# Parse arguments
TEAM_NAME=${1}
SERVICE_TYPE=${2}  # frontend or backend
IMAGE_TAG=${3:-latest}
AWS_REGION=${4:-ap-southeast-2}

# Validate arguments
if [ -z "$TEAM_NAME" ] || [ -z "$SERVICE_TYPE" ]; then
    echo "Usage: $0 <team_name> <frontend|backend> [image_tag] [region]"
    echo "Example: $0 alpha frontend v1.2.3"
    exit 1
fi

if [[ "$SERVICE_TYPE" != "frontend" && "$SERVICE_TYPE" != "backend" ]]; then
    echo "Error: service_type must be 'frontend' or 'backend'"
    exit 1
fi

# Set variables
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="eba-${TEAM_NAME}-${SERVICE_TYPE}"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
CLUSTER_NAME="EBA-${TEAM_NAME}"
SERVICE_NAME="${TEAM_NAME}-${SERVICE_TYPE}"

echo "🚀 Deploying ${SERVICE_TYPE} for team ${TEAM_NAME}"
echo "   ECR Repository: ${ECR_REPO}"
echo "   Image Tag: ${IMAGE_TAG}"
echo "   ECS Cluster: ${CLUSTER_NAME}"
echo "   ECS Service: ${SERVICE_NAME}"

# Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URI}

# Tag and push image
echo "📦 Pushing image to ECR..."
docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}
docker push ${ECR_URI}:${IMAGE_TAG}

# Update ECS service
echo "🔄 Updating ECS service..."
aws ecs update-service \
    --cluster ${CLUSTER_NAME} \
    --service ${SERVICE_NAME} \
    --force-new-deployment \
    --region ${AWS_REGION}

# Wait for deployment
echo "⏳ Waiting for deployment to complete..."
aws ecs wait services-stable \
    --cluster ${CLUSTER_NAME} \
    --services ${SERVICE_NAME} \
    --region ${AWS_REGION}

echo "✅ Deployment complete!"
echo "🌐 Access your service at: /${TEAM_NAME}/"
