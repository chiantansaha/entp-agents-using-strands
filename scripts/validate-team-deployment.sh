#!/bin/bash

# Validation script for team-based ECS deployment
# This script validates the team-based infrastructure deployment

set -e

# Change to iac directory for terraform commands
cd "$(dirname "$0")/../../ecs-iac-aiproj"

TEAM_NAME="team1" #${1:-"alpha"}

echo "🔍 Validating team-based deployment for team: $TEAM_NAME"

# Check if team_name variable is set
if [ -z "$TEAM_NAME" ]; then
    echo "❌ Error: Team name not provided"
    echo "Usage: $0 <team_name>"
    exit 1
fi

echo "✅ Team name: $TEAM_NAME"

# Validate Terraform configuration
echo "🔧 Validating Terraform configuration..."
terraform validate

# Get region from terraform output or use default
echo "🌍 Getting AWS region..."
if terraform output region >/dev/null 2>&1; then
    REGION=$(terraform output -raw region)
    echo "✅ Using region from Terraform output: $REGION"
else
    # Fallback to AWS CLI default region or us-east-1
    REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    echo "⚠️  Using fallback region: $REGION (Terraform not applied yet)"
fi

# Check if ECR repositories exist
echo "🐳 Checking ECR repositories..."
if aws ecr describe-repositories --repository-names "awsugsg-${TEAM_NAME}-frontend" --region "$REGION" >/dev/null 2>&1; then
    echo "✅ Frontend ECR repository exists"
else
    echo "⚠️  Frontend ECR repository not found"
fi

if aws ecr describe-repositories --repository-names "awsugsg-${TEAM_NAME}-backend" --region "$REGION" >/dev/null 2>&1; then
    echo "✅ Backend ECR repository exists"
else
    echo "⚠️  Backend ECR repository not found"
fi

# Check if ECS cluster exists
echo "🚀 Checking ECS cluster..."
if aws ecs describe-clusters --clusters "awsugsg-${TEAM_NAME}" --region "$REGION" >/dev/null 2>&1; then
    echo "✅ ECS cluster exists"
else
    echo "⚠️  ECS cluster not found"
fi

# Check if services are running
echo "🔄 Checking ECS services..."
if aws ecs describe-services --cluster "awsugsg-${TEAM_NAME}" --services "${TEAM_NAME}-frontend" --region "$REGION" >/dev/null 2>&1; then
    echo "✅ Frontend service exists"
    # Check service status
    FRONTEND_STATUS=$(aws ecs describe-services --cluster "awsugsg-${TEAM_NAME}" --services "${TEAM_NAME}-frontend" --region "$REGION" --query 'services[0].status' --output text)
    echo "   Status: $FRONTEND_STATUS"
else
    echo "⚠️  Frontend service not found"
fi

if aws ecs describe-services --cluster "awsugsg-${TEAM_NAME}" --services "${TEAM_NAME}-backend" --region "$REGION" >/dev/null 2>&1; then
    echo "✅ Backend service exists"
    # Check service status
    BACKEND_STATUS=$(aws ecs describe-services --cluster "awsugsg-${TEAM_NAME}" --services "${TEAM_NAME}-backend" --region "$REGION" --query 'services[0].status' --output text)
    echo "   Status: $BACKEND_STATUS"
else
    echo "⚠️  Backend service not found"
fi

# Check ALB target groups (correct naming pattern)
echo "🎯 Checking ALB target groups..."
if aws elbv2 describe-target-groups --names "awsugsg-${TEAM_NAME}-frontend-v2" --region "$REGION" >/dev/null 2>&1; then
    echo "✅ Frontend target group exists"
    # Check target health
    TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --names "awsugsg-${TEAM_NAME}-frontend-v2" --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' --output text)
    HEALTHY_TARGETS=$(aws elbv2 describe-target-health --target-group-arn "$TARGET_GROUP_ARN" --region "$REGION" --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' --output text | wc -l)
    TOTAL_TARGETS=$(aws elbv2 describe-target-health --target-group-arn "$TARGET_GROUP_ARN" --region "$REGION" --query 'TargetHealthDescriptions' --output text | wc -l)
    echo "   Healthy targets: $HEALTHY_TARGETS/$TOTAL_TARGETS"
else
    echo "⚠️  Frontend target group not found"
fi

# Check ALB
echo "🔗 Checking Application Load Balancer..."
if aws elbv2 describe-load-balancers --names "awsugsg-shared-alb" --region "$REGION" >/dev/null 2>&1; then
    echo "✅ Application Load Balancer exists"
    ALB_DNS=$(aws elbv2 describe-load-balancers --names "awsugsg-shared-alb" --region "$REGION" --query 'LoadBalancers[0].DNSName' --output text)
    echo "   DNS Name: $ALB_DNS"
    echo "   Team URL: http://$ALB_DNS/${TEAM_NAME}/"
else
    echo "⚠️  Application Load Balancer not found"
fi

# Summary
echo ""
echo "📊 Validation Summary for team: $TEAM_NAME"
echo "Region: $REGION"
echo ""
echo "Next steps:"
echo "1. If resources are missing, run: terraform apply"
echo "2. If ECR repositories exist but are empty, push container images"
echo "3. Access your application at: http://\$ALB_DNS/${TEAM_NAME}/"

echo ""
echo "✅ Validation complete for team: $TEAM_NAME"
