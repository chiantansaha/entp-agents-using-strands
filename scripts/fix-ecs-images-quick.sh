#!/bin/bash

# Quick ECS Image Fix Script
# This script temporarily uses public images to fix the ECR connectivity issue
# Usage: ./fix-ecs-images-quick.sh

set -e

# Change to iac directory for terraform commands
cd "$(dirname "$0")/../../ecs-iac-aiproj"

TEAM_NAME="team1"
REGION=$(terraform output -raw region)

echo "🚀 Quick fix for ECS image issues - team: $TEAM_NAME"
echo "📍 Region: $REGION"

echo ""
echo "🔧 Step 1: Updating ECS task definitions to use public images temporarily..."

# Create temporary task definition files with public images
cat > /tmp/frontend-task-def.json << EOF
{
  "family": "awsugsg-${TEAM_NAME}-frontend",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/ecsTaskExecutionRole",
  "taskRoleArn": "$(aws iam list-roles --query 'Roles[?contains(RoleName, `${TEAM_NAME}-frontend-tasks`)].Arn' --output text)",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "nginx:alpine",
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "PORT",
          "value": "80"
        },
        {
          "name": "TEAM_NAME", 
          "value": "${TEAM_NAME}"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/awsugsg-${TEAM_NAME}",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "frontend"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost/ || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

cat > /tmp/backend-task-def.json << EOF
{
  "family": "awsugsg-${TEAM_NAME}-backend", 
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/ecsTaskExecutionRole",
  "taskRoleArn": "$(aws iam list-roles --query 'Roles[?contains(RoleName, `${TEAM_NAME}-backend-tasks`)].Arn' --output text)",
  "containerDefinitions": [
    {
      "name": "backend",
      "image": "httpd:alpine",
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "PORT",
          "value": "80"
        },
        {
          "name": "TEAM_NAME",
          "value": "${TEAM_NAME}"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/awsugsg-${TEAM_NAME}",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "backend"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost/ || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

echo ""
echo "📝 Step 2: Registering new task definitions..."

# Register new task definitions
FRONTEND_TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/frontend-task-def.json \
    --region "$REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

BACKEND_TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/backend-task-def.json \
    --region "$REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "✅ Frontend task definition: $FRONTEND_TASK_DEF_ARN"
echo "✅ Backend task definition: $BACKEND_TASK_DEF_ARN"

echo ""
echo "🔄 Step 3: Updating ECS services with new task definitions..."

# Update services with new task definitions
aws ecs update-service \
    --cluster "awsugsg-${TEAM_NAME}" \
    --service "${TEAM_NAME}-frontend" \
    --task-definition "$FRONTEND_TASK_DEF_ARN" \
    --region "$REGION" && echo "✅ Frontend service updated"

aws ecs update-service \
    --cluster "awsugsg-${TEAM_NAME}" \
    --service "${TEAM_NAME}-backend" \
    --task-definition "$BACKEND_TASK_DEF_ARN" \
    --region "$REGION" && echo "✅ Backend service updated"

# Clean up temp files
rm -f /tmp/frontend-task-def.json /tmp/backend-task-def.json

echo ""
echo "⏳ Step 4: Waiting for services to stabilize..."
echo "This may take 2-3 minutes..."

# Wait for services to become stable
aws ecs wait services-stable \
    --cluster "awsugsg-${TEAM_NAME}" \
    --services "${TEAM_NAME}-frontend" "${TEAM_NAME}-backend" \
    --region "$REGION" && echo "✅ Services are now stable"

echo ""
echo "🎉 Quick fix complete!"
echo ""
echo "📋 What was fixed:"
echo "✅ Replaced ECR images with public Docker Hub images"
echo "✅ Updated task definitions to use nginx and httpd"
echo "✅ Services should now start successfully"
echo ""
echo "📊 Next steps:"
echo "1. Verify services: ./scripts/validate-team-deployment.sh"
echo "2. Check logs: ./scripts/check-ecs-logs.sh"
echo "3. Access app: http://internal-awsugsg-shared-alb-1579479635.ap-southeast-2.elb.amazonaws.com/team1/"
echo ""
echo "🔧 To use custom images later:"
echo "1. Build your images with Docker"
echo "2. Push to ECR repositories"
echo "3. Update task definitions to use ECR images"

echo ""
echo "✅ The ECR connectivity issue is now bypassed!"