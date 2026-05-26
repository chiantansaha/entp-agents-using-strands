#!/bin/bash

# ECS CloudWatch Logs Checker
# This script checks ECS service logs to diagnose issues
# Usage: ./check-ecs-logs.sh [team_name] [service_type]

set -e

# Change to iac directory for terraform commands
cd "$(dirname "$0")/../../ecs-iac-aiproj"

TEAM_NAME=${1:-"team1"}
SERVICE_TYPE=${2:-"both"}  # frontend, backend, or both

echo "🔍 Checking ECS CloudWatch logs for team: $TEAM_NAME"

# Get region
if terraform output region >/dev/null 2>&1; then
    REGION=$(terraform output -raw region)
else
    REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
fi

echo "📍 Region: $REGION"

# Function to check service logs
check_service_logs() {
    local service=$1
    local log_group="/ecs/awsugsg-${TEAM_NAME}"
    
    echo ""
    echo "🔍 Checking ${service} service logs..."
    echo "Log Group: $log_group"
    
    # Check if log group exists
    if ! aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$REGION" --query 'logGroups[0].logGroupName' --output text >/dev/null 2>&1; then
        echo "❌ Log group $log_group not found"
        return 1
    fi
    
    # Get log streams for this service
    echo "📋 Available log streams:"
    aws logs describe-log-streams \
        --log-group-name "$log_group" \
        --order-by LastEventTime \
        --descending \
        --region "$REGION" \
        --query "logStreams[?contains(logStreamName, '${service}')].{Stream:logStreamName,LastEvent:lastEventTime}" \
        --output table 2>/dev/null || echo "No log streams found for $service"
    
    # Get recent log streams for this service
    local streams=$(aws logs describe-log-streams \
        --log-group-name "$log_group" \
        --order-by LastEventTime \
        --descending \
        --max-items 5 \
        --region "$REGION" \
        --query "logStreams[?contains(logStreamName, '${service}')].logStreamName" \
        --output text 2>/dev/null)
    
    if [ -z "$streams" ]; then
        echo "⚠️  No recent log streams found for $service"
        return 1
    fi
    
    # Show recent logs from the most recent stream
    local latest_stream=$(echo "$streams" | head -n1)
    echo ""
    echo "📄 Recent logs from: $latest_stream"
    echo "----------------------------------------"
    
    aws logs get-log-events \
        --log-group-name "$log_group" \
        --log-stream-name "$latest_stream" \
        --start-time $(date -d '1 hour ago' +%s)000 \
        --region "$REGION" \
        --query 'events[*].[timestamp,message]' \
        --output text 2>/dev/null | \
        while IFS=$'\t' read -r timestamp message; do
            if [ -n "$timestamp" ]; then
                local readable_time=$(date -d "@$(echo $timestamp | cut -c1-10)" '+%Y-%m-%d %H:%M:%S')
                echo "[$readable_time] $message"
            fi
        done || echo "No recent log events found"
}

# Function to check ECS service status
check_service_status() {
    local service=$1
    
    echo ""
    echo "🚀 Checking ECS service status: ${TEAM_NAME}-${service}"
    
    # Check if service exists
    if ! aws ecs describe-services \
        --cluster "awsugsg-${TEAM_NAME}" \
        --services "${TEAM_NAME}-${service}" \
        --region "$REGION" >/dev/null 2>&1; then
        echo "❌ Service ${TEAM_NAME}-${service} not found"
        return 1
    fi
    
    # Get service details
    local service_info=$(aws ecs describe-services \
        --cluster "awsugsg-${TEAM_NAME}" \
        --services "${TEAM_NAME}-${service}" \
        --region "$REGION" \
        --query 'services[0]' 2>/dev/null)
    
    if [ "$service_info" = "null" ] || [ -z "$service_info" ]; then
        echo "❌ Could not retrieve service information"
        return 1
    fi
    
    # Extract key information
    local status=$(echo "$service_info" | jq -r '.status // "unknown"')
    local running_count=$(echo "$service_info" | jq -r '.runningCount // 0')
    local desired_count=$(echo "$service_info" | jq -r '.desiredCount // 0')
    local pending_count=$(echo "$service_info" | jq -r '.pendingCount // 0')
    
    echo "   Status: $status"
    echo "   Running: $running_count/$desired_count (Pending: $pending_count)"
    
    # Check deployments
    echo ""
    echo "📦 Recent deployments:"
    echo "$service_info" | jq -r '.deployments[] | "   \(.status) - \(.taskDefinition | split("/") | .[1]) - \(.createdAt)"' 2>/dev/null || echo "   No deployment info available"
    
    # Check events
    echo ""
    echo "📋 Recent service events:"
    echo "$service_info" | jq -r '.events[0:5][] | "   [\(.createdAt)] \(.message)"' 2>/dev/null || echo "   No recent events"
    
    # Get task details if any are running
    if [ "$running_count" -gt 0 ] || [ "$pending_count" -gt 0 ]; then
        echo ""
        echo "🔍 Task details:"
        aws ecs list-tasks \
            --cluster "awsugsg-${TEAM_NAME}" \
            --service-name "${TEAM_NAME}-${service}" \
            --region "$REGION" \
            --query 'taskArns' \
            --output text 2>/dev/null | \
        while read -r task_arn; do
            if [ -n "$task_arn" ] && [ "$task_arn" != "None" ]; then
                local task_id=$(basename "$task_arn")
                echo "   Task: $task_id"
                
                # Get task details
                aws ecs describe-tasks \
                    --cluster "awsugsg-${TEAM_NAME}" \
                    --tasks "$task_arn" \
                    --region "$REGION" \
                    --query 'tasks[0]' 2>/dev/null | \
                jq -r '"     Status: \(.lastStatus // "unknown")", "     Health: \(.healthStatus // "unknown")", "     CPU/Memory: \(.cpu // "unknown")/\(.memory // "unknown")"' 2>/dev/null
                
                # Check for stopped reason
                local stopped_reason=$(aws ecs describe-tasks \
                    --cluster "awsugsg-${TEAM_NAME}" \
                    --tasks "$task_arn" \
                    --region "$REGION" \
                    --query 'tasks[0].stoppedReason' \
                    --output text 2>/dev/null)
                
                if [ -n "$stopped_reason" ] && [ "$stopped_reason" != "None" ] && [ "$stopped_reason" != "null" ]; then
                    echo "     Stopped Reason: $stopped_reason"
                fi
            fi
        done
    fi
}

# Main execution
echo "🔍 Starting ECS diagnostics..."

# Check if infrastructure exists
if ! aws ecs describe-clusters --clusters "awsugsg-${TEAM_NAME}" --region "$REGION" >/dev/null 2>&1; then
    echo "❌ ECS cluster awsugsg-${TEAM_NAME} not found"
    echo "💡 Run 'terraform apply' to create infrastructure first"
    exit 1
fi

echo "✅ ECS cluster awsugsg-${TEAM_NAME} exists"

# Check services based on SERVICE_TYPE parameter
case $SERVICE_TYPE in
    "frontend")
        check_service_status "frontend"
        check_service_logs "frontend"
        ;;
    "backend")
        check_service_status "backend"
        check_service_logs "backend"
        ;;
    "both"|*)
        check_service_status "frontend"
        check_service_logs "frontend"
        
        check_service_status "backend"
        check_service_logs "backend"
        ;;
esac

echo ""
echo "🔧 Common Issues and Solutions:"
echo ""
echo "1. 📦 No container image in ECR:"
echo "   - Build and push images: ./scripts/build-and-deploy.sh team1 frontend ./frontend/Dockerfile"
echo ""
echo "2. 🚫 Task failing to start:"
echo "   - Check task definition and container configuration"
echo "   - Verify ECR image exists and is accessible"
echo "   - Check IAM permissions for ECS task role"
echo ""
echo "3. 🌐 Network issues:"
echo "   - Verify security groups allow required traffic"
echo "   - Check subnet configuration and NAT gateway"
echo ""
echo "4. 💾 Resource constraints:"
echo "   - Check if sufficient CPU/memory allocated"
echo "   - Verify subnet has available IP addresses"
echo ""
echo "5. 🔐 Permission issues:"
echo "   - Verify ECS task execution role has ECR permissions"
echo "   - Check CloudWatch logs permissions"

echo ""
echo "✅ ECS diagnostics complete"