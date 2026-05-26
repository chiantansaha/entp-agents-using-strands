#!/bin/bash

# Final Status Check
# This script provides a comprehensive status check of the ECS deployment

set -e

cd "$(dirname "$0")/../../ecs-iac-aiproj"

TEAM_NAME="team1"
REGION=$(terraform output -raw region)

echo "🔍 Final Status Check for team: $TEAM_NAME"
echo "============================================"

echo ""
echo "📊 ECS Service Status:"

# Check if services exist and get their status
FRONTEND_STATUS=$(aws ecs describe-services \
    --cluster "awsugsg-${TEAM_NAME}" \
    --services "${TEAM_NAME}-frontend" \
    --region "$REGION" \
    --query 'services[0]' 2>/dev/null)

BACKEND_STATUS=$(aws ecs describe-services \
    --cluster "awsugsg-${TEAM_NAME}" \
    --services "${TEAM_NAME}-backend" \
    --region "$REGION" \
    --query 'services[0]' 2>/dev/null)

if [ "$FRONTEND_STATUS" != "null" ] && [ -n "$FRONTEND_STATUS" ]; then
    FRONTEND_RUNNING=$(echo "$FRONTEND_STATUS" | jq -r '.runningCount // 0')
    FRONTEND_DESIRED=$(echo "$FRONTEND_STATUS" | jq -r '.desiredCount // 0')
    FRONTEND_SERVICE_STATUS=$(echo "$FRONTEND_STATUS" | jq -r '.status // "unknown"')
    
    echo "Frontend Service:"
    echo "  Status: $FRONTEND_SERVICE_STATUS"
    echo "  Running: $FRONTEND_RUNNING/$FRONTEND_DESIRED"
    
    # Get latest event
    FRONTEND_EVENT=$(echo "$FRONTEND_STATUS" | jq -r '.events[0].message // "No events"')
    echo "  Latest Event: $FRONTEND_EVENT"
else
    echo "Frontend Service: NOT FOUND"
fi

echo ""

if [ "$BACKEND_STATUS" != "null" ] && [ -n "$BACKEND_STATUS" ]; then
    BACKEND_RUNNING=$(echo "$BACKEND_STATUS" | jq -r '.runningCount // 0')
    BACKEND_DESIRED=$(echo "$BACKEND_STATUS" | jq -r '.desiredCount // 0')
    BACKEND_SERVICE_STATUS=$(echo "$BACKEND_STATUS" | jq -r '.status // "unknown"')
    
    echo "Backend Service:"
    echo "  Status: $BACKEND_SERVICE_STATUS"
    echo "  Running: $BACKEND_RUNNING/$BACKEND_DESIRED"
    
    # Get latest event
    BACKEND_EVENT=$(echo "$BACKEND_STATUS" | jq -r '.events[0].message // "No events"')
    echo "  Latest Event: $BACKEND_EVENT"
else
    echo "Backend Service: NOT FOUND"
fi

echo ""
echo "🎯 Load Balancer Status:"

ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "internal-awsugsg-shared-alb-1579479635.ap-southeast-2.elb.amazonaws.com")
echo "  ALB DNS: $ALB_DNS"

# Check target group health
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
    --names "awsugsg-${TEAM_NAME}-frontend-v2" \
    --region "$REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "")

if [ -n "$TARGET_GROUP_ARN" ] && [ "$TARGET_GROUP_ARN" != "None" ]; then
    echo "  Target Group: Found"
    
    # Check target health
    TARGET_HEALTH=$(aws elbv2 describe-target-health \
        --target-group-arn "$TARGET_GROUP_ARN" \
        --region "$REGION" \
        --query 'TargetHealthDescriptions' 2>/dev/null || echo "[]")
    
    HEALTHY_COUNT=$(echo "$TARGET_HEALTH" | jq '[.[] | select(.TargetHealth.State == "healthy")] | length')
    TOTAL_COUNT=$(echo "$TARGET_HEALTH" | jq 'length')
    
    echo "  Healthy Targets: $HEALTHY_COUNT/$TOTAL_COUNT"
    
    if [ "$TOTAL_COUNT" -gt 0 ]; then
        echo "  Target Details:"
        echo "$TARGET_HEALTH" | jq -r '.[] | "    \(.Target.Id):\(.Target.Port) - \(.TargetHealth.State)"'
    fi
else
    echo "  Target Group: NOT FOUND"
fi

echo ""
echo "🌐 Connectivity Test:"

# Test ALB connectivity
echo "  Testing ALB connectivity..."
if curl -s --connect-timeout 5 --max-time 10 "http://$ALB_DNS/team1/" >/dev/null 2>&1; then
    echo "  ✅ ALB is reachable"
    
    # Get response
    RESPONSE=$(curl -s --connect-timeout 5 --max-time 10 "http://$ALB_DNS/team1/" | head -c 200)
    if [[ "$RESPONSE" == *"Team1"* ]] || [[ "$RESPONSE" == *"Working"* ]]; then
        echo "  ✅ Application is responding correctly"
    else
        echo "  ⚠️  ALB reachable but unexpected response"
    fi
else
    echo "  ❌ ALB is not reachable or timing out"
fi

echo ""
echo "📋 Summary:"

# Overall status
if [ "${FRONTEND_RUNNING:-0}" -gt 0 ] && [ "${BACKEND_RUNNING:-0}" -gt 0 ]; then
    echo "  🎉 SUCCESS: Both services are running!"
    echo "  🌐 Application URL: http://$ALB_DNS/team1/"
elif [ "${FRONTEND_RUNNING:-0}" -gt 0 ] || [ "${BACKEND_RUNNING:-0}" -gt 0 ]; then
    echo "  ⏳ PARTIAL: Some services are running, others still starting"
    echo "  💡 Wait a few more minutes for full deployment"
else
    echo "  ⚠️  STARTING: Services are still deploying"
    echo "  💡 This is normal for new deployments - wait 2-3 minutes"
fi

echo ""
echo "🔧 Troubleshooting:"
echo "  - Check logs: ./scripts/check-ecs-logs.sh"
echo "  - Validate deployment: ./scripts/validate-team-deployment.sh"
echo "  - View AWS Console: https://ap-southeast-2.console.aws.amazon.com/ecs/home?region=ap-southeast-2#/clusters/awsugsg-team1"

echo ""
echo "✅ Status check complete!"