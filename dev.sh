#!/usr/bin/env bash

# 🌟 Chirantan's - AWS Cloud AI Assistant Chatbot Development Script
# Usage: ./dev.sh [start|stop|restart] [frontend|backend|all]
# Compatible with both bash and zsh

set -e

# Configuration
BACKEND_PORT=9083
FRONTEND_PORT=8501
BACKEND_DIR="./backend"
FRONTEND_DIR="./frontend"
PID_DIR="./.pids"

# Create PID directory
mkdir -p "$PID_DIR"

# Colors and emojis
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo "🌈 Chirantan's - AWS Cloud AI Assistant Chatbot Development Script"
    echo ""
    echo "Usage: $0 [COMMAND] [SERVICE]"
    echo ""
    echo "Commands:"
    echo "  start    🚀 Start services (auto-setup venv with UV)"
    echo "  stop     🛑 Stop services"
    echo "  restart  🔄 Restart services"
    echo "  status   📊 Show service status"
    echo "  logs     📋 Show service logs"
    echo "  setup    🔧 Setup virtual environments only"
    echo ""
    echo "Services:"
    echo "  frontend    🎨 Streamlit web application (port $FRONTEND_PORT)"
    echo "  backend     ⚡ FastAPI service (port $BACKEND_PORT)"
    echo "  all         🌟 All services (default)"
    echo ""
    echo "Prerequisites:"
    echo "  📦 UV package manager must be installed"
    echo "  📁 requirements.txt files in backend/ and frontend/ directories"
    echo ""
    echo "Examples:"
    echo "  $0 setup          # Setup venvs for both services"
    echo "  $0 start all      # Start both services"
    echo "  $0 stop backend   # Stop only backend"
    echo "  $0 restart        # Restart both services"
    echo "  $0 status         # Show status of all services"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_uv() {
    if ! command -v uv &> /dev/null; then
        log_error "UV is not installed. Please install UV first: https://github.com/astral-sh/uv"
        exit 1
    fi
}

setup_venv() {
    local service_dir=$1
    local service_name=$2
    
    log_info "Setting up virtual environment for $service_name..."
    cd "$service_dir"
    
    # Create venv if it doesn't exist
    if [[ ! -d ".venv" ]]; then
        log_info "Creating virtual environment with UV..."
        uv venv
    fi
    
    # Install dependencies if requirements.txt exists
    if [[ -f "requirements.txt" ]]; then
        log_info "Installing dependencies for $service_name..."
        uv pip install -r requirements.txt
    else
        log_warning "No requirements.txt found for $service_name"
    fi
    
    cd ..
}

is_running() {
    local service=$1
    local pid_file="$PID_DIR/${service}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$pid_file"
            return 1
        fi
    fi
    return 1
}

start_backend() {
    if is_running "backend"; then
        log_warning "Backend already running"
        return 0
    fi
    
    check_uv
    setup_venv "$BACKEND_DIR" "backend"
    
    log_info "Starting backend service on port $BACKEND_PORT..."
    cd "$BACKEND_DIR"
    nohup .venv/bin/uvicorn aws_agent:app --host 0.0.0.0 --port $BACKEND_PORT --reload > "../$PID_DIR/backend.log" 2>&1 &
    echo $! > "../$PID_DIR/backend.pid"
    cd ..
    sleep 2
    
    if is_running "backend"; then
        log_success "Backend started successfully ⚡"
        log_info "Backend API: http://localhost:$BACKEND_PORT"
        log_info "Health check: http://localhost:$BACKEND_PORT/health"
    else
        log_error "Failed to start backend"
        return 1
    fi
}


start_frontend() {
    if is_running "frontend"; then
        log_warning "Frontend already running"
        return 0
    fi
    
    check_uv
    setup_venv "$FRONTEND_DIR" "frontend"
    
    log_info "Starting frontend service on port $FRONTEND_PORT..."
    cd "$FRONTEND_DIR"
    nohup .venv/bin/streamlit run app.py --server.port $FRONTEND_PORT --server.address 0.0.0.0 > "../$PID_DIR/frontend.log" 2>&1 &
    echo $! > "../$PID_DIR/frontend.pid"
    cd ..
    sleep 3
    
    if is_running "frontend"; then
        log_success "Frontend started successfully 🎨"
        log_info "Frontend URL: http://localhost:$FRONTEND_PORT"
    else
        log_error "Failed to start frontend"
        return 1
    fi
}

stop_service() {
    local service=$1
    local pid_file="$PID_DIR/${service}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$pid_file"
            log_success "$service stopped"
        else
            rm -f "$pid_file"
            log_warning "$service was not running"
        fi
    else
        log_warning "$service was not running"
    fi
}

show_status() {
    echo "📊 Service Status:"
    echo ""
    
    if is_running "backend"; then
        echo -e "  ⚡ Backend:    ${GREEN}Running${NC} (port $BACKEND_PORT)"
    else
        echo -e "  ⚡ Backend:    ${RED}Stopped${NC}"
    fi
    
    if is_running "frontend"; then
        echo -e "  🎨 Frontend:   ${GREEN}Running${NC} (port $FRONTEND_PORT)"
    else
        echo -e "  🎨 Frontend:   ${RED}Stopped${NC}"
    fi
    echo ""
}

show_logs() {
    local service=${2:-"all"}
    
    case $service in
        "backend")
            if [[ -f "$PID_DIR/backend.log" ]]; then
                echo "📋 Backend logs:"
                tail -f "$PID_DIR/backend.log"
            else
                log_warning "No backend logs found"
            fi
            ;;
        "frontend")
            if [[ -f "$PID_DIR/frontend.log" ]]; then
                echo "📋 Frontend logs:"
                tail -f "$PID_DIR/frontend.log"
            else
                log_warning "No frontend logs found"
            fi
            ;;
        "all"|*)
            echo "📋 All service logs (Ctrl+C to exit):"
            if [[ -f "$PID_DIR/backend.log" ]] && [[ -f "$PID_DIR/frontend.log" ]]; then
                tail -f "$PID_DIR/backend.log" "$PID_DIR/frontend.log"
            elif [[ -f "$PID_DIR/backend.log" ]]; then
                tail -f "$PID_DIR/backend.log"
            elif [[ -f "$PID_DIR/frontend.log" ]]; then
                tail -f "$PID_DIR/frontend.log"
            else
                log_warning "No logs found"
            fi
            ;;
    esac
}

setup_only() {
    local service=${1:-"all"}
    
    check_uv
    echo "🔧 Setting up virtual environments..."
    
    case $service in
        "backend")
            setup_venv "$BACKEND_DIR" "backend"
            ;;
        "frontend")
            setup_venv "$FRONTEND_DIR" "frontend"
            ;;
        "all"|*)
            setup_venv "$BACKEND_DIR" "backend"
            setup_venv "$FRONTEND_DIR" "frontend"
            ;;
    esac
    
    log_success "Virtual environments setup complete! 🎉"
}

# Main script logic
COMMAND=${1:-"start"}
SERVICE=${2:-"all"}

case $COMMAND in
    "setup")
        setup_only "$SERVICE"
        ;;
    "start")
        echo "🚀 Starting Chirantan's - AWS Cloud AI Assistant Chatbot ..."
        case $SERVICE in
            "backend")
                start_backend
                ;;
            "frontend")
                start_frontend
                ;;
            "all"|*)
                start_backend
                start_frontend
                echo ""
                show_status
                ;;
        esac
        ;;
    "stop")
        echo "🛑 Stopping services..."
        case $SERVICE in
            "backend")
                stop_service "backend"
                ;;
            "frontend")
                stop_service "frontend"
                ;;
            "all"|*)
                stop_service "backend"
                stop_service "frontend"
                ;;
        esac
        ;;
    "restart")
        echo "🔄 Restarting services..."
        case $SERVICE in
            "backend")
                stop_service "backend"
                start_backend
                ;;
            "frontend")
                stop_service "frontend"
                start_frontend
                ;;
            "all"|*)
                stop_service "backend"
                stop_service "frontend"
                sleep 1
                start_backend
                start_frontend
                echo ""
                show_status
                ;;
        esac
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs "$@"
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac