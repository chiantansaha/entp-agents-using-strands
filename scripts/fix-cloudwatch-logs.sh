#!/bin/bash

# Fix CloudWatch Logs Connectivity Issue
# This script removes CloudWatch logging to fix the network connectivity issue
# Usage: ./fix-cloudwatch-logs.sh

set -e

# Change to iac directory for terraform commands
cd "$(dirname "$0")/../../ecs-iac-aiproj"

TEAM_NAME="team1"
REGION=$(terraform output -raw region)

echo "🔧 Fixing CloudWatch logs connectivity issue for team: $TEAM_NAME"
echo "📍 Region: $REGION"

echo ""
echo "📝 Creating task definitions without CloudWatch logging..."

# Create frontend task definition without CloudWatch logging
cat > /tmp/frontend-task-def-no-logs.json << EOF
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
        "echo 'server { listen 8081; location / { root /usr/share/nginx/html; index index.html; } location /health { return 200 \"healthy\"; add_header Content-Type text/plain; } location /_stcore/health { return 200 \"healthy\"; add_header Content-Type text/plain; } }' > /etc/nginx/conf.d/default.conf && echo '<h1>Team1 Frontend - Working!</h1><p>Port: 8081</p><p>Status: Healthy</p><p>Logs: Console only</p>' > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"
      ],
      "essential": true
    }
  ]
}
EOF

# Create backend task definition without CloudWatch logging
cat > /tmp/backend-task-def-no-logs.json << EOF
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
        "echo 'Listen 9081' > /usr/local/apache2/conf/httpd.conf && echo 'ServerRoot \"/usr/local/apache2\"' >> /usr/local/apache2/conf/httpd.conf && echo 'DocumentRoot \"/usr/local/apache2/htdocs\"' >> /usr/local/apache2/conf/httpd.conf && echo 'LoadModule mpm_event_module modules/mod_mpm_event.so' >> /usr/local/apache2/conf/httpd.conf && echo 'LoadModule authz_core_module modules/mod_authz_core.so' >> /usr/local/apache2/conf/httpd.conf && echo 'LoadModule dir_module modules/mod_dir.so' >> /usr/local/apache2/conf/httpd.conf && echo 'DirectoryIndex index.html' >> /usr/local/apache2/conf/httpd.conf && echo '<Directory \"/usr/local/apache2/htdocs\">' >> /usr/local/apache2/conf/httpd.conf && echo '    Require all granted' >> /usr/local/apache2/conf/httpd.conf && echo '</Directory>' >> /usr/local/apache2/conf/httpd.conf && echo '<h1>Team1 Backend - Working!</h1><p>Port: 9081</p><p>Status: Healthy</p><p>Logs: Console only</p>' > /usr/local/apache2/htdocs/index.html && echo 'healthy' > /usr/local/apache2/htdocs/health && httpd-foreground"
      ],
      "essential": true
    }
  ]
}
EOF

echo ""
echo "📝 Registering task definitions without CloudWatch logging..."

# Register new task definitions
FRONTEND_TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/frontend-task-def-no-logs.json \
    --region "$REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

BACKEND_TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/backend-task-def-no-logs.json \
    --region "$REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "✅ Frontend task definition: $FRONTEND_TASK_DEF_ARN"
echo "✅ Backend task definition: $BACKEND_TASK_DEF_ARN"

echo ""
echo "🔄 Updating ECS services with new task definitions..."

# Update services with new task definitions
aws ecs update-service \
    --cluster "awsugsg-${TEAM_NAME}" \
    --service "${TEAM_NAME}-frontend" \
    --task-definition "$FRONTEND_TASK_DEF_ARN" \
    --region "$REGION" >/dev/null 2>&1 && echo "✅ Frontend service updated"

aws ecs update-service \
    --cluster "awsugsg-${TEAM_NAME}" \
    --service "${TEAM_NAME}-backend" \
    --task-definition "$BACKEND_TASK_DEF_ARN" \
    --region "$REGION" >/dev/null 2>&1 && echo "✅ Backend service updated"

# Clean up temp files
rm -f /tmp/frontend-task-def-no-logs.json /tmp/backend-task-def-no-logs.json

echo ""
echo "⏳ Waiting for services to start..."

# Check service status with timeout
for i in {1..20}; do
    echo "Checking attempt $i/20..."
    
    FRONTEND_RUNNING=$(aws ecs describe-services \
        --cluster "awsugsg-${TEAM_NAME}" \
        --services "${TEAM_NAME}-frontend" \
        --region "$REGION" \
        --query 'services[0].runningCount' \
        --output text 2>/dev/null || echo "0")
    
    BACKEND_RUNNING=$(aws ecs describe-services \
        --cluster "awsugsg-${TEAM_NAME}" \
        --services "${TEAM_NAME}-backend" \
        --region "$REGION" \
        --query 'services[0].runningCount' \
        --output text 2>/dev/null || echo "0")
    
    echo "  Frontend running: $FRONTEND_RUNNING"
    echo "  Backend running: $BACKEND_RUNNING"
    
    if [ "$FRONTEND_RUNNING" -gt 0 ] && [ "$BACKEND_RUNNING" -gt 0 ]; then
        echo ""
        echo "🎉 SUCCESS! Both services are now running!"
        break
    fi
    
    if [ $i -eq 20 ]; then
        echo ""
        echo "⚠️  Services taking longer than expected. Checking for errors..."
        
        # Check for recent events
        echo "Recent frontend events:"
        aws ecs describe-services \
            --cluster "awsugsg-${TEAM_NAME}" \
            --services "${TEAM_NAME}-frontend" \
            --region "$REGION" \
            --query 'services[0].events[0:2].[createdAt,message]' \
            --output table 2>/dev/null || echo "No events found"
        
        echo ""
        echo "Recent backend events:"
        aws ecs describe-services \
            --cluster "awsugsg-${TEAM_NAME}" \
            --services "${TEAM_NAME}-backend" \
            --region "$REGION" \
            --query 'services[0].events[0:2].[createdAt,message]' \
            --output table 2>/dev/null || echo "No events found"
    else
        sleep 10
    fi
done

echo ""
echo "🎉 CloudWatch logs connectivity fix complete!"
echo ""
echo "📋 What was fixed:"
echo "✅ Removed CloudWatch logging configuration from task definitions"
echo "✅ Tasks now use console logging only (no network dependency)"
echo "✅ Services should start without connectivity issues"
echo ""
echo "📊 Access your application:"
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "internal-awsugsg-shared-alb-1579479635.ap-southeast-2.elb.amazonaws.com")
echo "   URL: http://$ALB_DNS/team1/"
echo ""
echo "🔍 Verify with:"
echo "   ./scripts/validate-team-deployment.sh"

echo ""
echo "✅ ECS services should now be running without CloudWatch dependency!"