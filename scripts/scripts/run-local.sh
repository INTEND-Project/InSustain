#!/bin/bash

# run-local.sh - Start backend locally for development
# Usage: ./scripts/run-local.sh [--port PORT]

set -e

# Configuration
BACKEND_DIR="k8s-app/backend"
ENV_FILE="$BACKEND_DIR/.env.local"
DEFAULT_PORT=8089
VENV_PATH="/home/eamrerp/my_env"  # Default venv with dependencies installed
VENV_DIR="$BACKEND_DIR/venv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${BLUE}[SUCCESS]${NC} $1"
}

# Parse command line arguments
parse_args() {
    PORT=$DEFAULT_PORT
    USE_VENV=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                PORT="$2"
                shift 2
                ;;
            --venv)
                USE_VENV="$2"
                shift 2
                ;;
            --create-venv)
                CREATE_VENV=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Start the inSustain backend locally for development with hot reload.

Prerequisites:
  - Port-forwards must be active (run: ./scripts/dev-local.sh start)
  - Python dependencies installed in venv or system

Options:
  --port PORT         Port to run backend on (default: 8089)
  --venv PATH         Path to Python virtual environment (default: k8s-app/backend/venv)
  --create-venv       Create virtual environment and install dependencies
  -h, --help          Show this help message

Environment:
  Configuration loaded from: $ENV_FILE

Virtual Environment:
  By default, the script looks for a venv at: $VENV_DIR
  
  To create and use a virtual environment:
    $0 --create-venv    # Creates venv and installs dependencies
  
  To use an existing virtual environment:
    $0 --venv /path/to/venv
  
  To use system Python (not recommended):
    # Just run without --venv flag if no venv exists

Examples:
  $0                      # Use venv if exists, otherwise system Python
  $0 --create-venv        # Create venv, install deps, and start
  $0 --venv ~/my-venv     # Use custom venv location
  $0 --port 8090          # Start on custom port 8090

EOF
}

# Check if port-forwards are active
check_port_forwards() {
    log_info "Checking port-forward status..."
    
    local required_ports=(27017 5000 9090 9000 9102)
    local port_names=("MongoDB" "MLflow" "Prometheus" "MinIO" "Kepler")
    local missing_ports=()
    local missing_names=()
    
    for i in "${!required_ports[@]}"; do
        local port="${required_ports[$i]}"
        local name="${port_names[$i]}"
        
        if ! timeout 2 bash -c "echo > /dev/tcp/localhost/$port" 2>/dev/null; then
            missing_ports+=("$port")
            missing_names+=("$name")
        fi
    done
    
    if [ ${#missing_ports[@]} -gt 0 ]; then
        log_error "Port-forwards not active for the following services:"
        for i in "${!missing_ports[@]}"; do
            echo "  - ${missing_names[$i]} (port ${missing_ports[$i]})"
        done
        echo ""
        log_error "Start port-forwards with: ./scripts/dev-local.sh start"
        log_error "Check status with: ./scripts/dev-local.sh status"
        return 1
    fi
    
    log_success "All required port-forwards are active"
    return 0
}

# Check if .env.local exists
check_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found: $ENV_FILE"
        log_error "This file should have been created during setup."
        return 1
    fi
    
    log_info "Found environment file: $ENV_FILE"
    return 0
}

# Load environment variables from .env.local
load_env_vars() {
    log_info "Loading environment variables from $ENV_FILE..."
    
    # Export variables from .env.local (skip comments and empty lines)
    set -a
    source <(grep -v '^#' "$ENV_FILE" | grep -v '^$' | sed 's/\r$//')
    set +a
    
    log_success "Environment variables loaded"
}

# Check if backend directory exists
check_backend_dir() {
    if [ ! -d "$BACKEND_DIR" ]; then
        log_error "Backend directory not found: $BACKEND_DIR"
        return 1
    fi
    
    if [ ! -f "$BACKEND_DIR/src/openapi_server/main.py" ]; then
        log_error "Backend main.py not found in $BACKEND_DIR/src/openapi_server/"
        return 1
    fi
    
    return 0
}

# Create virtual environment and install dependencies
create_venv() {
    log_info "Creating virtual environment at $VENV_DIR..."
    
    if [ -d "$VENV_DIR" ]; then
        log_warn "Virtual environment already exists at $VENV_DIR"
        read -p "Remove and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$VENV_DIR"
        else
            log_info "Using existing virtual environment"
            return 0
        fi
    fi
    
    python3 -m venv "$VENV_DIR"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create virtual environment"
        log_error "Install venv with: sudo apt-get install python3-venv"
        return 1
    fi
    
    log_success "Virtual environment created"
    
    # Activate and install dependencies
    log_info "Installing dependencies from requirements.txt..."
    source "$VENV_DIR/bin/activate"
    
    pip install --upgrade pip > /dev/null 2>&1
    pip install -r "$BACKEND_DIR/requirements.txt"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to install dependencies"
        return 1
    fi
    
    log_success "Dependencies installed successfully"
    return 0
}

# Setup Python environment (venv or system)
setup_python_env() {
    # If --venv specified, use that path
    if [ -n "$USE_VENV" ]; then
        if [ ! -d "$USE_VENV" ]; then
            log_error "Specified virtual environment not found: $USE_VENV"
            return 1
        fi
        
        log_info "Using virtual environment: $USE_VENV"
        source "$USE_VENV/bin/activate"
        
        if [ $? -ne 0 ]; then
            log_error "Failed to activate virtual environment"
            return 1
        fi
        
        log_success "Virtual environment activated"
        PYTHON_CMD="$USE_VENV/bin/python3"
        return 0
    fi
    
    # Check if default venv exists
    if [ -d "$VENV_DIR" ]; then
        log_info "Using virtual environment: $VENV_DIR"
        source "$VENV_DIR/bin/activate"
        
        if [ $? -ne 0 ]; then
            log_error "Failed to activate virtual environment"
            return 1
        fi
        
        log_success "Virtual environment activated"
        PYTHON_CMD="$VENV_DIR/bin/python3"
        return 0
    fi
    
    # No venv, use system Python
    log_warn "No virtual environment found, using system Python"
    log_warn "Consider creating a venv with: $0 --create-venv"
    PYTHON_CMD="python3"
    return 0
}

# Check if Python dependencies are installed
check_dependencies() {
    log_info "Checking Python dependencies..."
    
    local python_cmd="${PYTHON_CMD:-python3}"
    
    if ! command -v "$python_cmd" &> /dev/null; then
        log_error "Python not found: $python_cmd"
        return 1
    fi
    
    # Check for critical dependencies
    local missing_deps=()
    local deps=("uvicorn" "fastapi" "pydantic" "mlflow" "prometheus_api_client" "motor" "kubernetes")
    
    for dep in "${deps[@]}"; do
        if ! "$python_cmd" -c "import $dep" 2>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing ${#missing_deps[@]} required Python package(s):"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo ""
        
        if [ -n "$VIRTUAL_ENV" ]; then
            log_error "Install dependencies in venv with:"
            log_error "  pip install -r $BACKEND_DIR/requirements.txt"
        else
            log_error "Create venv and install dependencies with:"
            log_error "  $0 --create-venv"
            echo ""
            log_error "Or install to system Python with:"
            log_error "  cd $BACKEND_DIR"
            log_error "  pip install -r requirements.txt"
        fi
        return 1
    fi
    
    log_success "All Python dependencies available"
    return 0
}

# Start the backend
start_backend() {
    local port=$1
    local python_cmd="${PYTHON_CMD:-python3}"
    
    log_info "Starting backend on port $port with hot reload..."
    echo ""
    log_success "Backend starting..."
    log_success "  API URL: http://localhost:$port"
    log_success "  API Docs: http://localhost:$port/docs"
    log_success "  Health Check: http://localhost:$port/health"
    
    if [ -n "$VIRTUAL_ENV" ]; then
        log_success "  Python: $VIRTUAL_ENV/bin/python3 (venv)"
    else
        log_success "  Python: $python_cmd (system)"
    fi
    
    echo ""
    log_info "Press Ctrl+C to stop"
    echo ""
    echo "----------------------------------------"
    
    # Change to backend directory and start uvicorn
    cd "$BACKEND_DIR"
    
    # Add src directory to PYTHONPATH so imports work correctly
    # Use absolute path to ensure it works in subprocess
    local abs_backend_dir="$(pwd)"
    export PYTHONPATH="${abs_backend_dir}/src:${PYTHONPATH:-}"
    
    # Start uvicorn with reload flag
    # Use the full module path from src directory
    PYTHONPATH="${abs_backend_dir}/src:${PYTHONPATH:-}" \
    "$python_cmd" -m uvicorn openapi_server.main:app \
        --reload \
        --host 0.0.0.0 \
        --port "$port" \
        --log-level info
}

# Main function
main() {
    parse_args "$@"
    
    log_info "Starting inSustain backend in local development mode..."
    echo ""
    
    # Run all checks
    if ! check_backend_dir; then
        exit 1
    fi
    
    if ! check_env_file; then
        exit 1
    fi
    
    # Handle venv creation if requested
    if [ "$CREATE_VENV" = true ]; then
        if ! create_venv; then
            exit 1
        fi
        # Set USE_VENV to the default location after creation
        USE_VENV="$VENV_DIR"
    fi
    
    # Setup Python environment (venv or system)
    if ! setup_python_env; then
        exit 1
    fi
    
    if ! check_dependencies; then
        exit 1
    fi
    
    if ! check_port_forwards; then
        exit 1
    fi
    
    # Load environment and start backend
    load_env_vars
    
    echo ""
    start_backend "$PORT"
}

main "$@"
