#!/bin/bash

# 🔍 Troubleshooting Script for Backend Connection Issues
# This script diagnoses and helps fix "Response ended prematurely" errors

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 AI Assistant Orch - Backend Troubleshooting${NC}\n"

# Function to check if port is open
check_port() {
    local port=$1
    local service=$2
    
    if nc -z localhost $port 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} $service running on port $port"
        return 0
    else
        echo -e "  ${RED}❌${NC} $service NOT running on port $port"
        return 1
    fi
}

# Function to test endpoint
test_endpoint() {
    local url=$1
    local service=$2
    
    response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null | tail -1)
    
    if [ "$response" = "200" ]; then
        echo -e "  ${GREEN}✅${NC} $service responds with 200 OK"
        return 0
    else
        echo -e "  ${RED}❌${NC} $service returned HTTP $response"
        return 1
    fi
}

echo "📊 Step 1: Checking Service Ports"
echo "=================================="

check_port 9083 "AWS Agent (9083)"
AWS_OK=$?

check_port 9084 "Cost Agent (9084)"
COST_OK=$?

check_port 9085 "Supervisor (9085)"
SUP_OK=$?

check_port 8501 "Frontend (8501)"
FRONTEND_OK=$?

echo ""
echo "🏥 Step 2: Testing Health Endpoints"
echo "===================================="

test_endpoint "http://localhost:9083/health" "AWS Agent health"
test_endpoint "http://localhost:9084/health" "Cost Agent health"
test_endpoint "http://localhost:9085/health" "Supervisor health"

echo ""
echo "🔄 Step 3: Process Status"
echo "========================="

# Show .pids directory
if [ -d ".pids" ]; then
    echo "Active process IDs:"
    for pid_file in .pids/*.pid; do
        if [ -f "$pid_file" ]; then
            service=$(basename "$pid_file" .pid)
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "  ${GREEN}✅${NC} $service: PID $pid (running)"
            else
                echo -e "  ${RED}❌${NC} $service: PID $pid (NOT running)"
                rm -f "$pid_file"
            fi
        fi
    done
else
    echo -e "  ${YELLOW}⚠️${NC}  No .pids directory found (services may not have been started with dev.sh)"
fi

echo ""
echo "🎯 Step 4: Test Supervisor Query"
echo "================================="

if [ $SUP_OK -eq 0 ]; then
    echo "Testing supervisor endpoint with simple query..."
    
    response=$(curl -s -X POST http://localhost:9085/supervisor-query \
        -H "Content-Type: application/json" \
        -d '{"query": "list EC2 instances"}' \
        -w "\nHTTP_CODE:%{http_code}" 2>/dev/null)
    
    http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        echo -e "  ${GREEN}✅${NC} Supervisor query successful"
    else
        echo -e "  ${RED}❌${NC} Supervisor returned HTTP $http_code"
        echo "  Response: $(echo "$response" | head -1)"
    fi
else
    echo -e "  ${RED}❌${NC} Supervisor not running, skipping query test"
fi

echo ""
echo "📋 Step 5: Recommendations"
echo "=========================="

if [ $AWS_OK -ne 0 ] || [ $COST_OK -ne 0 ] || [ $SUP_OK -ne 0 ] || [ $FRONTEND_OK -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Some services are not running.${NC}\n"
    
    if [ $AWS_OK -ne 0 ]; then
        echo "  🚀 To start AWS Agent:"
        echo "     ./dev.sh start backend"
    fi
    
    if [ $COST_OK -ne 0 ]; then
        echo "  🚀 To start Cost Agent:"
        echo "     ./dev.sh start cost"
    fi
    
    if [ $SUP_OK -ne 0 ]; then
        echo "  🚀 To start Supervisor:"
        echo "     ./dev.sh start supervisor"
    fi
    
    if [ $FRONTEND_OK -ne 0 ]; then
        echo "  🚀 To start Frontend:"
        echo "     ./dev.sh start frontend"
    fi
    
    echo ""
    echo "  Or start all services:"
    echo "     ./dev.sh stop all && ./dev.sh start all"
else
    echo -e "${GREEN}✅ All services are running!${NC}\n"
    echo "  If you're still seeing 'Response ended prematurely' error:"
    echo ""
    echo "  1. Check backend logs:"
    echo "     ./dev.sh logs backend"
    echo ""
    echo "  2. Check supervisor logs:"
    echo "     ./dev.sh logs supervisor"
    echo ""
    echo "  3. Try restarting all services:"
    echo "     ./dev.sh restart all"
    echo ""
    echo "  4. Check for AWS credentials:"
    echo "     echo \$AWS_ACCESS_KEY_ID"
    echo "     echo \$AWS_DEFAULT_REGION"
fi

echo ""
echo "📚 For more details, see: ROLE_SETUP_AND_ERROR_GUIDE.md"
echo ""
