#!/bin/bash

# dev-local.sh - Manage port-forwards for local backend development
# Usage: ./scripts/dev-local.sh [start|stop|status]

set -e

# Configuration
NAMESPACE="insustain"
PID_DIR="/tmp/insustain-port-forwards"
LOG_DIR="/tmp/insustain-port-forwards/logs"

# Port forward definitions: LOCAL_PORT:REMOTE_PORT SERVICE_NAME
declare -A PORT_FORWARDS=(
    ["27017"]="27017:27017 svc/insustain-mongodb"
    ["5000"]="5000:5000 svc/insustain-mlflow"
    ["9090"]="9090:9090 svc/prometheus-kube-prometheus-prometheus"
    ["9000"]="9000:9000 svc/insustain-minio"
    ["9102"]="9102:9102 svc/insustain-kepler"
)

declare -A SERVICE_NAMES=(
    ["27017"]="MongoDB"
    ["5000"]="MLflow"
    ["9090"]="Prometheus"
    ["9000"]="MinIO"
    ["9102"]="Kepler"
)

declare -A SERVICE_NAMESPACES=(
    ["27017"]="insustain"
    ["5000"]="insustain"
    ["9090"]="monitoring"
    ["9000"]="insustain"
    ["9102"]="insustain"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Create PID and log directories
init_dirs() {
    mkdir -p "$PID_DIR"
    mkdir -p "$LOG_DIR"
}

# Start all port-forwards
start_port_forwards() {
    log_info "Starting port-forwards for local development..."
    init_dirs
    
    local failed=0
    
    for port in "${!PORT_FORWARDS[@]}"; do
        local service_name="${SERVICE_NAMES[$port]}"
        local namespace="${SERVICE_NAMESPACES[$port]}"
        local forward_spec="${PORT_FORWARDS[$port]}"
        local service=$(echo "$forward_spec" | awk '{print $2}')
        local ports=$(echo "$forward_spec" | awk '{print $1}')
        
        local pid_file="$PID_DIR/${port}.pid"
        local log_file="$LOG_DIR/${port}.log"
        
        # Check if already running
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if ps -p "$pid" > /dev/null 2>&1; then
                log_warn "$service_name port-forward already running (PID: $pid)"
                continue
            else
                rm -f "$pid_file"
            fi
        fi
        
        # Start port-forward in background
        log_info "Starting $service_name port-forward ($ports)..."
        kubectl port-forward -n "$namespace" "$service" "$ports" > "$log_file" 2>&1 &
        local pid=$!
        echo "$pid" > "$pid_file"
        
        # Wait a moment and verify it started
        sleep 1
        if ps -p "$pid" > /dev/null 2>&1; then
            log_info "$service_name port-forward started (PID: $pid)"
        else
            log_error "$service_name port-forward failed to start"
            log_error "Check log: $log_file"
            failed=$((failed + 1))
            rm -f "$pid_file"
        fi
    done
    
    if [ $failed -eq 0 ]; then
        log_info "All port-forwards started successfully"
        log_info "Run './scripts/dev-local.sh status' to check connectivity"
    else
        log_error "$failed port-forward(s) failed to start"
        return 1
    fi
}

# Stop all port-forwards
stop_port_forwards() {
    log_info "Stopping port-forwards..."
    
    local stopped=0
    local not_running=0
    
    for port in "${!PORT_FORWARDS[@]}"; do
        local service_name="${SERVICE_NAMES[$port]}"
        local pid_file="$PID_DIR/${port}.pid"
        
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if ps -p "$pid" > /dev/null 2>&1; then
                kill "$pid" 2>/dev/null || true
                log_info "Stopped $service_name port-forward (PID: $pid)"
                stopped=$((stopped + 1))
            else
                log_warn "$service_name port-forward not running"
                not_running=$((not_running + 1))
            fi
            rm -f "$pid_file"
        else
            log_warn "$service_name port-forward not found"
            not_running=$((not_running + 1))
        fi
    done
    
    if [ $stopped -gt 0 ]; then
        log_info "Stopped $stopped port-forward(s)"
    fi
    
    if [ $not_running -gt 0 ]; then
        log_warn "$not_running port-forward(s) were not running"
    fi
}

# Check status and connectivity
check_status() {
    log_info "Checking port-forward status and connectivity..."
    echo ""
    
    local running=0
    local not_running=0
    local connected=0
    local not_connected=0
    
    for port in "${!PORT_FORWARDS[@]}"; do
        local service_name="${SERVICE_NAMES[$port]}"
        local pid_file="$PID_DIR/${port}.pid"
        
        printf "%-15s " "$service_name:"
        
        # Check if process is running
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if ps -p "$pid" > /dev/null 2>&1; then
                printf "${GREEN}Running${NC} (PID: $pid) "
                running=$((running + 1))
                
                # Check connectivity
                if check_connectivity "$port"; then
                    printf -- "- ${GREEN}Connected${NC}\n"
                    connected=$((connected + 1))
                else
                    printf -- "- ${RED}Not responding${NC}\n"
                    not_connected=$((not_connected + 1))
                fi
            else
                printf "${RED}Not running${NC} (stale PID file)\n"
                not_running=$((not_running + 1))
                rm -f "$pid_file"
            fi
        else
            printf "${RED}Not running${NC}\n"
            not_running=$((not_running + 1))
        fi
    done
    
    echo ""
    log_info "Summary: $running running, $not_running not running"
    if [ $running -gt 0 ]; then
        log_info "Connectivity: $connected connected, $not_connected not responding"
    fi
    
    if [ $not_running -gt 0 ]; then
        echo ""
        log_warn "Start port-forwards with: ./scripts/dev-local.sh start"
        return 1
    fi
    
    if [ $not_connected -gt 0 ]; then
        echo ""
        log_warn "Some services are not responding. Check if services are running in cluster."
        return 1
    fi
    
    return 0
}

# Check connectivity to a specific port
check_connectivity() {
    local port=$1
    
    # Use timeout and nc (netcat) to check if port is accepting connections
    timeout 2 bash -c "echo > /dev/tcp/localhost/$port" 2>/dev/null
    return $?
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [start|stop|status]

Manage port-forwards for local backend development.

Commands:
  start    Start all port-forwards in background
  stop     Stop all port-forward processes
  status   Show status of port-forwards and connectivity

Port forwards:
  27017 - MongoDB
  5000  - MLflow
  9090  - Prometheus
  9000  - MinIO
  9102  - Kepler

Examples:
  $0 start    # Start all port-forwards
  $0 status   # Check status and connectivity
  $0 stop     # Stop all port-forwards

EOF
}

# Main command handler
main() {
    case "${1:-}" in
        start)
            start_port_forwards
            ;;
        stop)
            stop_port_forwards
            ;;
        status)
            check_status
            ;;
        -h|--help|help)
            show_usage
            ;;
        *)
            log_error "Invalid command: ${1:-}"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
