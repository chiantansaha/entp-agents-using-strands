#!/bin/bash

# Deployment script for team-based ECS infrastructure
# This script deploys the infrastructure for a specific team

set -e

# Change to iac directory for terraform commands
cd "$(dirname "$0")/../../ecs-iac-aiproj"

TEAM_NAME="team1"

echo "🚀 Deploying infrastructure for team: $TEAM_NAME"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "⚠️  terraform.tfvars not found. Creating from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "📝 Please edit terraform.tfvars with your specific values before continuing."
    echo "   Key settings to update:"
    echo "   - vpc_id: Your VPC ID (or leave empty for default VPC)"
    echo "   - allowed_ips: Your IP addresses for ALB access"
    echo "   - acm_certificate_arn: Your SSL certificate ARN (or leave empty)"
    echo ""
    read -p "Press Enter after updating terraform.tfvars to continue..."
fi

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Validate configuration
echo "✅ Validating Terraform configuration..."
terraform validate

# Plan deployment
echo "📋 Planning deployment..."
terraform plan -out=tfplan

echo ""
echo "📊 Deployment Plan Summary:"
echo "Team: $TEAM_NAME"
echo "Resources to be created:"
echo "- ECS Cluster: awsugsg-$TEAM_NAME"
echo "- ECR Repositories: awsugsg-$TEAM_NAME-frontend, awsugsg-$TEAM_NAME-backend"
echo "- ECS Services: $TEAM_NAME-frontend, $TEAM_NAME-backend"
echo "- ALB Target Group: awsugsg-$TEAM_NAME-frontend-v2"
echo "- Security Groups and IAM roles"
echo ""

read -p "Do you want to apply this plan? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Applying Terraform configuration..."
    terraform apply tfplan
    
    echo ""
    echo "✅ Deployment complete!"
    echo ""
    echo "📋 Next Steps:"
    echo "1. Build and push your container images to ECR:"
    
    # Get ECR URLs
    if terraform output frontend_ecr_repository_urls >/dev/null 2>&1; then
        FRONTEND_ECR=$(terraform output -json frontend_ecr_repository_urls | jq -r ".${TEAM_NAME}")
        BACKEND_ECR=$(terraform output -json backend_ecr_repository_urls | jq -r ".${TEAM_NAME}")
        
        echo "   Frontend ECR: $FRONTEND_ECR"
        echo "   Backend ECR: $BACKEND_ECR"
        echo ""
        echo "2. Example Docker commands:"
        echo "   # Login to ECR"
        echo "   aws ecr get-login-password --region $(terraform output -raw region) | docker login --username AWS --password-stdin $FRONTEND_ECR"
        echo ""
        echo "   # Build and push frontend"
        echo "   docker build -t $FRONTEND_ECR:latest ./frontend"
        echo "   docker push $FRONTEND_ECR:latest"
        echo ""
        echo "   # Build and push backend"
        echo "   docker build -t $BACKEND_ECR:latest ./backend"
        echo "   docker push $BACKEND_ECR:latest"
    fi
    
    echo ""
    echo "3. Access your application:"
    if terraform output alb_dns_name >/dev/null 2>&1; then
        ALB_DNS=$(terraform output -raw alb_dns_name)
        echo "   URL: http://$ALB_DNS/$TEAM_NAME/"
    fi
    
    echo ""
    echo "4. Run validation script:"
    echo "   ./scripts/validate-team-deployment.sh"
    
else
    echo "❌ Deployment cancelled"
    rm -f tfplan
fi