#!/bin/bash
set -e

echo "🚀 Starting EBA Development Environment with Docker Compose"
echo "=========================================================="

# Change to project root
cd "$(dirname "$0")/.."

# Function to cleanup
cleanup() {
    echo ""
    echo "🛑 Shutting down development environment..."
    docker compose down
    exit 0
}

# Set trap to cleanup on exit
trap cleanup SIGINT SIGTERM EXIT

# Build and start services
echo "🐳 Building and starting services..."
docker compose up --build

echo ""
echo "✅ Development environment started!"
echo "   🔧 Backend:  http://localhost:8000"
echo "   🖥️  Frontend: http://localhost:8501"
echo ""
echo "Press Ctrl+C to stop all services"
