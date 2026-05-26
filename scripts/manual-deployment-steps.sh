#!/bin/bash

# Manual Deployment Steps Generator
# Generates the exact commands you need to run for manual deployment
# Usage: ./manual-deployment-steps.sh <team_name> <service_type>

set -e

# Change to iac directory for terraform commands
cd "$(dirname "$0")/../../ecs-iac-aiproj"

# Parse arguments
TEAM_NAME=${1:-"team1"}
SERVICE_TYPE=${2:-"frontend"}

echo "📋 Manual Deployment Steps for ${TEAM_NAME} ${SERVICE_TYPE}"
echo "=================================================="

# Get region
if terraform output region >/dev/null 2>&1; then
    REGION=$(terraform output -raw region)
else
    REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
fi

# Get ECR repository URL
if terraform output ${SERVICE_TYPE}_ecr_repository_urls >/dev/null 2>&1; then
    ECR_URL=$(terraform output -json ${SERVICE_TYPE}_ecr_repository_urls | jq -r ".${TEAM_NAME}" 2>/dev/null || echo "")
else
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "YOUR_ACCOUNT_ID")
    ECR_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/awsugsg-${TEAM_NAME}-${SERVICE_TYPE}"
fi

echo ""
echo "🔧 Prerequisites:"
echo "1. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
echo "2. Start Docker Desktop and wait for it to be ready"
echo "3. Ensure AWS CLI is configured: aws configure"
echo ""

echo "📦 Step 1: Build your container image"
echo "cd /path/to/your/${SERVICE_TYPE}/code"
echo "docker build -t awsugsg-${TEAM_NAME}-${SERVICE_TYPE}:latest ."
echo ""

echo "🔐 Step 2: Login to ECR"
echo "aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URL}"
echo ""

echo "🏷️  Step 3: Tag your image for ECR"
echo "docker tag awsugsg-${TEAM_NAME}-${SERVICE_TYPE}:latest ${ECR_URL}:latest"
echo ""

echo "⬆️  Step 4: Push image to ECR"
echo "docker push ${ECR_URL}:latest"
echo ""

echo "🔄 Step 5: Update ECS service (force new deployment)"
echo "aws ecs update-service --cluster awsugsg-${TEAM_NAME} --service ${TEAM_NAME}-${SERVICE_TYPE} --force-new-deployment --region ${REGION}"
echo ""

echo "✅ Step 6: Verify deployment"
echo "aws ecs describe-services --cluster awsugsg-${TEAM_NAME} --services ${TEAM_NAME}-${SERVICE_TYPE} --region ${REGION} --query 'services[0].deployments[0].status'"
echo ""

echo "🌐 Step 7: Access your application"
if terraform output alb_dns_name >/dev/null 2>&1; then
    ALB_DNS=$(terraform output -raw alb_dns_name)
    echo "URL: http://${ALB_DNS}/${TEAM_NAME}/"
else
    echo "Get ALB DNS: terraform output alb_dns_name"
    echo "URL: http://\$ALB_DNS/${TEAM_NAME}/"
fi

echo ""
echo "📊 Monitoring Commands:"
echo "# Check service status"
echo "aws ecs describe-services --cluster awsugsg-${TEAM_NAME} --services ${TEAM_NAME}-${SERVICE_TYPE} --region ${REGION}"
echo ""
echo "# Check task status"
echo "aws ecs list-tasks --cluster awsugsg-${TEAM_NAME} --service-name ${TEAM_NAME}-${SERVICE_TYPE} --region ${REGION}"
echo ""
echo "# View logs"
echo "aws logs get-log-events --log-group-name /ecs/awsugsg-${TEAM_NAME} --log-stream-name ${SERVICE_TYPE}/\$TASK_ID --region ${REGION}"

echo ""
echo "🆘 Troubleshooting:"
echo "# If Docker daemon not running:"
echo "   - Start Docker Desktop application"
echo "   - Wait for Docker to be ready (green icon in menu bar)"
echo ""
echo "# If ECR login fails:"
echo "   - Check AWS credentials: aws sts get-caller-identity"
echo "   - Check region: aws configure get region"
echo ""
echo "# If ECS service update fails:"
echo "   - Check if infrastructure is deployed: terraform apply"
echo "   - Verify cluster exists: aws ecs describe-clusters --clusters awsugsg-${TEAM_NAME}"