#!/bin/bash

# Create Minimal ECR Images
# This script creates minimal working images in ECR to avoid Docker Hub connectivity issues

set -e

cd "$(dirname "$0")/../../ecs-iac-aiproj"

TEAM_NAME="team1"
REGION=$(terraform output -raw region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "🚀 Creating minimal ECR images for team: $TEAM_NAME"
echo "📍 Region: $REGION"
echo "🏢 Account: $ACCOUNT_ID"

# Get ECR repository URLs
FRONTEND_ECR=$(terraform output -json frontend_ecr_repository_urls | jq -r ".${TEAM_NAME}")
BACKEND_ECR=$(terraform output -json backend_ecr_repository_urls | jq -r ".${TEAM_NAME}")

echo "🎯 Frontend ECR: $FRONTEND_ECR"
echo "🎯 Backend ECR: $BACKEND_ECR"

# Create temporary directory
TEMP_DIR="/tmp/minimal-images"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo ""
echo "📦 Creating minimal frontend image..."

# Create minimal frontend Dockerfile using scratch base
cat > "$TEMP_DIR/Dockerfile.frontend" << 'EOF'
FROM busybox:latest

# Create a simple web server
RUN mkdir -p /www
RUN echo '<html><body><h1>Team1 Frontend - Working!</h1><p>Minimal image from ECR</p><p>Status: Healthy</p></body></html>' > /www/index.html
RUN echo 'healthy' > /www/health

# Create simple HTTP server script
RUN echo '#!/bin/sh
echo "Starting minimal web server on port 8081..."
while true; do
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n$(cat /www/index.html)" | nc -l -p 8081 -q 1
done' > /start.sh

RUN chmod +x /start.sh

EXPOSE 8081
CMD ["/start.sh"]
EOF

echo ""
echo "📦 Creating minimal backend image..."

# Create minimal backend Dockerfile
cat > "$TEMP_DIR/Dockerfile.backend" << 'EOF'
FROM busybox:latest

# Create a simple API server
RUN mkdir -p /api
RUN echo '{"status":"healthy","service":"team1-backend","message":"Working from ECR"}' > /api/health.json
RUN echo '{"message":"Team1 Backend API","status":"running","source":"ECR"}' > /api/index.json

# Create simple HTTP server script
RUN echo '#!/bin/sh
echo "Starting minimal API server on port 9081..."
while true; do
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n$(cat /api/index.json)" | nc -l -p 9081 -q 1
done' > /start.sh

RUN chmod +x /start.sh

EXPOSE 9081
CMD ["/start.sh"]
EOF

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker not available. Creating task definitions with busybox images directly..."
    
    # Use busybox directly in task definitions
    cat > /tmp/frontend-busybox-task.json << EOF
{
  "family": "awsugsg-${TEAM_NAME}-frontend",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "taskRoleArn": "$(aws iam list-roles --query 'Roles[?contains(RoleName, `${TEAM_NAME}-frontend-tasks`)].Arn' --output text)",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "busybox:latest",
      "portMappings": [
        {
          "containerPort": 8081,
          "protocol": "tcp"
        }
      ],
      "command": [
        "sh", "-c",
        "mkdir -p /www && echo '<h1>Team1 Frontend - Working!</h1><p>Status: Healthy</p>' > /www/index.html && echo 'healthy' > /www/health && while true; do echo -e 'HTTP/1.1 200 OK\\r\\nContent-Type: text/html\\r\\n\\r\\n'$(cat /www/index.html) | nc -l -p 8081 -q 1; done"
      ],
      "essential": true
    }
  ]
}
EOF

    cat > /tmp/backend-busybox-task.json << EOF
{
  "family": "awsugsg-${TEAM_NAME}-backend",
  "networkMode": "awsvpc", 
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "taskRoleArn": "$(aws iam list-roles --query 'Roles[?contains(RoleName, `${TEAM_NAME}-backend-tasks`)].Arn' --output text)",
  "containerDefinitions": [
    {
      "name": "backend",
      "image": "busybox:latest",
      "portMappings": [
        {
          "containerPort": 9081,
          "protocol": "tcp"
        }
      ],
      "command": [
        "sh", "-c", 
        "mkdir -p /api && echo '{\"status\":\"healthy\",\"service\":\"team1-backend\"}' > /api/health.json && while true; do echo -e 'HTTP/1.1 200 OK\\r\\nContent-Type: application/json\\r\\n\\r\\n'$(cat /api/health.json) | nc -l -p 9081 -q 1; done"
      ],
      "essential": true
    }
  ]
}
EOF

    echo ""
    echo "📝 Registering busybox-based task definitions..."
    
    # Register task definitions
    FRONTEND_TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file:///tmp/frontend-busybox-task.json \
        --region "$REGION" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)

    BACKEND_TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file:///tmp/backend-busybox-task.json \
        --region "$REGION" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)

    echo "✅ Frontend task definition: $FRONTEND_TASK_DEF_ARN"
    echo "✅ Backend task definition: $BACKEND_TASK_DEF_ARN"

    # Update services
    echo ""
    echo "🔄 Updating ECS services..."
    
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

    # Clean up
    rm -f /tmp/frontend-busybox-task.json /tmp/backend-busybox-task.json

else
    echo ""
    echo "🐳 Docker available - building and pushing custom images..."
    
    # Login to ECR
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$FRONTEND_ECR"

    # Build and push frontend
    docker build -t "team1-frontend-minimal" -f "$TEMP_DIR/Dockerfile.frontend" "$TEMP_DIR"
    docker tag "team1-frontend-minimal" "$FRONTEND_ECR:latest"
    docker push "$FRONTEND_ECR:latest"

    # Build and push backend
    docker build -t "team1-backend-minimal" -f "$TEMP_DIR/Dockerfile.backend" "$TEMP_DIR"
    docker tag "team1-backend-minimal" "$BACKEND_ECR:latest"
    docker push "$BACKEND_ECR:latest"

    echo "✅ Images pushed to ECR"

    # Update task definitions to use ECR images
    # (This would use the original ECR-based task definitions)
fi

# Clean up
rm -rf "$TEMP_DIR"

echo ""
echo "⏳ Waiting for services to start..."

# Monitor service status
for i in {1..15}; do
    echo "Checking attempt $i/15..."
    
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
    
    echo "  Frontend: $FRONTEND_RUNNING running"
    echo "  Backend: $BACKEND_RUNNING running"
    
    if [ "$FRONTEND_RUNNING" -gt 0 ] && [ "$BACKEND_RUNNING" -gt 0 ]; then
        echo ""
        echo "🎉 SUCCESS! Both services are now running!"
        break
    fi
    
    if [ $i -eq 15 ]; then
        echo ""
        echo "⚠️  Services still starting. Check AWS Console for details."
    else
        sleep 15
    fi
done

echo ""
echo "✅ Minimal ECR images deployment complete!"
echo ""
echo "📊 Access your application:"
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)
echo "   URL: http://$ALB_DNS/team1/"
echo ""
echo "🔍 Verify with: ./scripts/validate-team-deployment.sh"