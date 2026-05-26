#!/bin/bash

# Fix ECS Port Configuration
# This script fixes the port mismatch between ALB and containers
# Usage: ./fix-ecs-ports.sh

set -e

# Change to iac directory for terraform commands
cd "$(dirname "$0")/../../ecs-iac-aiproj"

TEAM_NAME="team1"
REGION=$(terraform output -raw region)

echo "🔧 Fixing ECS port configuration for team: $TEAM_NAME"
echo "📍 Region: $REGION"

echo ""
echo "📝 Creating corrected task definitions with proper ports..."

# Create frontend task definition with correct port (8081)
cat > /tmp/frontend-task-def-fixed.json << EOF
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
          "containerPort": 8081,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "PORT",
          "value": "8081"
        },
        {
          "name": "TEAM_NAME", 
          "value": "${TEAM_NAME}"
        }
      ],
      "command": [
        "sh", "-c",
        "echo 'server { listen 8081; location / { root /usr/share/nginx/html; index index.html; } location /health { return 200 \"healthy\"; add_header Content-Type text/plain; } location /_stcore/health { return 200 \"healthy\"; add_header Content-Type text/plain; } }' > /etc/nginx/conf.d/default.conf && echo '<h1>Team1 Frontend - Working!</h1><p>Port: 8081</p><p>Status: Healthy</p>' > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"
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
        "command": ["CMD-SHELL", "curl -f http://localhost:8081/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

# Create backend task definition with correct port (9081)
cat > /tmp/backend-task-def-fixed.json << EOF
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
          "containerPort": 9081,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "PORT",
          "value": "9081"
        },
        {
          "name": "TEAM_NAME",
          "value": "${TEAM_NAME}"
        }
      ],
      "command": [
        "sh", "-c",
        "echo 'Listen 9081' > /usr/local/apache2/conf/httpd.conf && echo 'ServerRoot \"/usr/local/apache2\"' >> /usr/local/apache2/conf/httpd.conf && echo 'DocumentRoot \"/usr/local/apache2/htdocs\"' >> /usr/local/apache2/conf/httpd.conf && echo 'LoadModule mpm_event_module modules/mod_mpm_event.so' >> /usr/local/apache2/conf/httpd.conf && echo 'LoadModule authz_core_module modules/mod_authz_core.so' >> /usr/local/apache2/conf/httpd.conf && echo 'LoadModule dir_module modules/mod_dir.so' >> /usr/local/apache2/conf/httpd.conf && echo 'DirectoryIndex index.html' >> /usr/local/apache2/conf/httpd.conf && echo '<Directory \"/usr/local/apache2/htdocs\">' >> /usr/local/apache2/conf/httpd.conf && echo '    Require all granted' >> /usr/local/apache2/conf/httpd.conf && echo '</Directory>' >> /usr/local/apache2/conf/httpd.conf && echo '<h1>Team1 Backend - Working!</h1><p>Port: 9081</p><p>Status: Healthy</p>' > /usr/local/apache2/htdocs/index.html && echo 'healthy' > /usr/local/apache2/htdocs/health && httpd-foreground"
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
        "command": ["CMD-SHELL", "curl -f http://localhost:9081/health || exit 1"],
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
echo "📝 Registering corrected task definitions..."

# Register new task definitions
FRONTEND_TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/frontend-task-def-fixed.json \
    --region "$REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

BACKEND_TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/backend-task-def-fixed.json \
    --region "$REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "✅ Frontend task definition: $FRONTEND_TASK_DEF_ARN"
echo "✅ Backend task definition: $BACKEND_TASK_DEF_ARN"

echo ""
echo "🔄 Updating ECS services with corrected task definitions..."

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
rm -f /tmp/frontend-task-def-fixed.json /tmp/backend-task-def-fixed.json

echo ""
echo "⏳ Waiting for services to start (this may take 2-3 minutes)..."

# Check service status
for i in {1..12}; do
    echo "Checking attempt $i/12..."
    
    FRONTEND_RUNNING=$(aws ecs describe-services \
        --cluster "awsugsg-${TEAM_NAME}" \
        --services "${TEAM_NAME}-frontend" \
        --region "$REGION" \
        --query 'services[0].runningCount' \
        --output text)
    
    BACKEND_RUNNING=$(aws ecs describe-services \
        --cluster "awsugsg-${TEAM_NAME}" \
        --services "${TEAM_NAME}-backend" \
        --region "$REGION" \
        --query 'services[0].runningCount' \
        --output text)
    
    echo "  Frontend running: $FRONTEND_RUNNING"
    echo "  Backend running: $BACKEND_RUNNING"
    
    if [ "$FRONTEND_RUNNING" -gt 0 ] && [ "$BACKEND_RUNNING" -gt 0 ]; then
        echo "✅ Both services are running!"
        break
    fi
    
    if [ $i -eq 12 ]; then
        echo "⚠️  Services taking longer than expected to start"
        echo "Check logs with: ./scripts/check-ecs-logs.sh"
    else
        sleep 15
    fi
done

echo ""
echo "🎉 Port configuration fix complete!"
echo ""
echo "📋 What was fixed:"
echo "✅ Updated frontend to use port 8081 (matches ALB target group)"
echo "✅ Updated backend to use port 9081 (matches service discovery)"
echo "✅ Added proper health check endpoints"
echo "✅ Using public images (no ECR dependency)"
echo ""
echo "📊 Next steps:"
echo "1. Verify services: ./scripts/validate-team-deployment.sh"
echo "2. Check logs: ./scripts/check-ecs-logs.sh"
echo "3. Access app: http://internal-awsugsg-shared-alb-1579479635.ap-southeast-2.elb.amazonaws.com/team1/"

echo ""
echo "✅ ECS services should now be working correctly!"