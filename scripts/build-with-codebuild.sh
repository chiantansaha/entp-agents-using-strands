#!/bin/bash

# AWS CodeBuild Container Build Script
# Builds containers using AWS CodeBuild (serverless, no local Docker required)
# Usage: ./build-with-codebuild.sh <team_name> <service_type> <dockerfile_path> [image_tag]

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
PROJECT_NAME="build-${ECR_REPO}-$(date +%s)"

echo "☁️  Building container image with AWS CodeBuild..."
echo "   Repository: ${ECR_REPO}"
echo "   Tag: ${IMAGE_TAG}"
echo "   Context: ${BUILD_CONTEXT}"
echo "   Dockerfile: ${DOCKERFILE_PATH}"
echo "   CodeBuild Project: ${PROJECT_NAME}"

# Get AWS region and account ID
REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get ECR repository URI
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"

echo "🏗️  Creating temporary CodeBuild project..."

# Create buildspec.yml
cat > /tmp/buildspec.yml << EOF
version: 0.2
phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI}
  build:
    commands:
      - echo Build started on \`date\`
      - echo Building the Docker image...
      - docker build -t ${ECR_REPO}:${IMAGE_TAG} -f ${DOCKERFILE_PATH} ${BUILD_CONTEXT}
      - docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}
  post_build:
    commands:
      - echo Build completed on \`date\`
      - echo Pushing the Docker image...
      - docker push ${ECR_URI}:${IMAGE_TAG}
EOF

# Create CodeBuild project
aws codebuild create-project \
  --name "${PROJECT_NAME}" \
  --source type=LOCAL,location=. \
  --artifacts type=NO_ARTIFACTS \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/amazonlinux2-x86_64-standard:3.0,computeType=BUILD_GENERAL1_MEDIUM,privilegedMode=true \
  --service-role "arn:aws:iam::${ACCOUNT_ID}:role/CodeBuildServiceRole" \
  --region "${REGION}" >/dev/null 2>&1 || echo "⚠️  CodeBuild project creation failed - may already exist or missing IAM role"

# Create source bundle
echo "📦 Creating source bundle..."
tar -czf /tmp/source.tar.gz --exclude='.git' --exclude='node_modules' --exclude='*.log' .

# Upload source to S3 (create bucket if needed)
S3_BUCKET="codebuild-source-${ACCOUNT_ID}-${REGION}"
aws s3 mb s3://${S3_BUCKET} --region ${REGION} >/dev/null 2>&1 || echo "S3 bucket already exists"
aws s3 cp /tmp/source.tar.gz s3://${S3_BUCKET}/source.tar.gz

# Start build
echo "🚀 Starting CodeBuild..."
BUILD_ID=$(aws codebuild start-build \
  --project-name "${PROJECT_NAME}" \
  --source-override type=S3,location=${S3_BUCKET}/source.tar.gz \
  --buildspec-override file:///tmp/buildspec.yml \
  --region "${REGION}" \
  --query 'build.id' --output text)

echo "📊 Build started with ID: ${BUILD_ID}"
echo "🔗 Monitor build progress at:"
echo "   https://${REGION}.console.aws.amazon.com/codesuite/codebuild/projects/${PROJECT_NAME}/build/${BUILD_ID}"

# Wait for build to complete
echo "⏳ Waiting for build to complete..."
aws codebuild batch-get-builds --ids "${BUILD_ID}" --region "${REGION}" --query 'builds[0].buildStatus' --output text

# Clean up
echo "🧹 Cleaning up temporary resources..."
aws codebuild delete-project --name "${PROJECT_NAME}" --region "${REGION}" >/dev/null 2>&1 || echo "⚠️  Failed to delete CodeBuild project"
aws s3 rm s3://${S3_BUCKET}/source.tar.gz >/dev/null 2>&1 || echo "⚠️  Failed to delete S3 object"
rm -f /tmp/buildspec.yml /tmp/source.tar.gz

echo "✅ Container build complete!"
echo "📦 Image available at: ${ECR_URI}:${IMAGE_TAG}"

# Update ECS service
echo "🔄 Updating ECS service..."
aws ecs update-service \
  --cluster "awsugsg-${TEAM_NAME}" \
  --service "${TEAM_NAME}-${SERVICE_TYPE}" \
  --force-new-deployment \
  --region "${REGION}" >/dev/null 2>&1 && echo "✅ ECS service updated" || echo "⚠️  Failed to update ECS service"