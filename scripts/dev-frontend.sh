#!/bin/bash
set -e

echo "🚀 Starting Frontend with Docker Compose"
echo "========================================"

# Change to project root
cd "$(dirname "$0")/.."

# Function to cleanup
cleanup() {
    echo ""
    echo "🛑 Shutting down frontend..."
    docker-compose stop frontend
    exit 0
}

# Set trap to cleanup on exit
trap cleanup SIGINT SIGTERM EXIT

echo "🐳 Building and starting frontend service..."
docker-compose up --build frontend

echo ""
echo "✅ Frontend started on http://localhost:8501"
echo "   Press Ctrl+C to stop"
