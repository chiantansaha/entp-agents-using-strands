#!/bin/bash

# Validation script for team-based ECS deployment
# This script validates the team-based infrastructure deployment

set -e

# Change to iac directory for terraform commands
cd "$(dirname "$0")/../iac"

TEAM_NAME=${1:-"alpha"}

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

# Check if ECR repositories exist
echo "🐳 Checking ECR repositories..."
aws ecr describe-repositories --repository-names "eba-${TEAM_NAME}-frontend" --region $(terraform output -raw region) || echo "⚠️  Frontend ECR repository not found"
aws ecr describe-repositories --repository-names "eba-${TEAM_NAME}-backend" --region $(terraform output -raw region) || echo "⚠️  Backend ECR repository not found"

# Check if ECS cluster exists
echo "🚀 Checking ECS cluster..."
aws ecs describe-clusters --clusters "EBA-${TEAM_NAME}" --region $(terraform output -raw region) || echo "⚠️  ECS cluster not found"

# Check if services are running
echo "🔄 Checking ECS services..."
aws ecs describe-services --cluster "EBA-${TEAM_NAME}" --services "${TEAM_NAME}-frontend" --region $(terraform output -raw region) || echo "⚠️  Frontend service not found"
aws ecs describe-services --cluster "EBA-${TEAM_NAME}" --services "${TEAM_NAME}-backend" --region $(terraform output -raw region) || echo "⚠️  Backend service not found"

# Check ALB target groups
echo "🎯 Checking ALB target groups..."
aws elbv2 describe-target-groups --names "frontend-${TEAM_NAME}" --region $(terraform output -raw region) || echo "⚠️  Frontend target group not found"

echo "✅ Validation complete for team: $TEAM_NAME"
