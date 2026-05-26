#!/bin/bash

# Cleanup script for team-based ECS deployment
# This script destroys the infrastructure for a specific team

set -e

# Change to iac directory for terraform commands
cd "$(dirname "$0")/../../ecs-iac-aiproj"

TEAM_NAME="team1"

echo "🧹 Cleaning up infrastructure for team: $TEAM_NAME"

# Validate configuration first
echo "🔧 Validating Terraform configuration..."
terraform validate

# Plan destroy
echo "📋 Planning destruction..."
terraform plan -destroy -out=destroy-plan

echo ""
echo "⚠️  DESTRUCTION PLAN SUMMARY:"
echo "Team: $TEAM_NAME"
echo "Resources to be DESTROYED:"
echo "- ECS Cluster: awsugsg-$TEAM_NAME"
echo "- ECR Repositories: awsugsg-$TEAM_NAME-frontend, awsugsg-$TEAM_NAME-backend"
echo "- ECS Services: $TEAM_NAME-frontend, $TEAM_NAME-backend"
echo "- ALB Target Group: awsugsg-$TEAM_NAME-frontend-v2"
echo "- Security Groups and IAM roles"
echo "- Application Load Balancer (shared)"
echo ""
echo "⚠️  WARNING: This will delete ALL infrastructure including:"
echo "   - Container images in ECR repositories"
echo "   - All application data"
echo "   - Load balancer and networking components"
echo ""

read -p "Are you ABSOLUTELY SURE you want to destroy all resources? Type 'yes' to confirm: " -r
echo
if [[ $REPLY == "yes" ]]; then
    echo "🧹 Destroying infrastructure..."
    terraform apply destroy-plan
    
    echo ""
    echo "✅ Cleanup complete!"
    echo "All infrastructure for team $TEAM_NAME has been destroyed."
    
else
    echo "❌ Cleanup cancelled"
    rm -f destroy-plan
    echo "Infrastructure preserved."
fi