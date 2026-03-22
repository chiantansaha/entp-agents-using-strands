#!/bin/bash
set -e

echo "🔧 Starting Mock Backend with Docker Compose"
echo "==========================================="

# Change to project root
cd "$(dirname "$0")/.."

# Function to cleanup
cleanup() {
    echo ""
    echo "🛑 Shutting down backend..."
    docker-compose stop backend
    exit 0
}

# Set trap to cleanup on exit
trap cleanup SIGINT SIGTERM EXIT

echo "🐳 Starting mock backend service..."
docker-compose up backend

echo ""
echo "✅ Backend started on http://localhost:8000"
echo "   Press Ctrl+C to stop"
