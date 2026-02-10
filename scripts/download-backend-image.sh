#!/bin/bash
set -e

# Download Backend Image Script
# Downloads InSustain backend image using Docker or Skopeo
# Works on any machine with Docker or Skopeo installed

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Find git repository root
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
cd "$GIT_ROOT"

REGISTRY="89.133.95.6:5001"
USER="intend"
IMAGE="insustain/backend:latest"
CERT_FILE="certs/docker_ca.crt"
OUTPUT_DIR="insustain-images"

print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_step() { echo -e "${BLUE}▶${NC} $1"; }

show_help() {
    cat << EOF
Download InSustain Backend Image

Usage: $0 [OPTIONS]

Downloads the backend image from private registry using Docker or Skopeo.

Options:
  -p, --password PASSWORD    Registry password (or use REGISTRY_PASSWORD env var)
  -t, --tool TOOL           Force tool: docker or skopeo (auto-detect by default)
  -o, --output DIR          Output directory (default: insustain-images)
  -h, --help                Show this help

Examples:
  $0 -p mypassword
  $0 --tool skopeo -p mypassword
  REGISTRY_PASSWORD=mypassword $0

Output:
  Creates directory with: insustain-backend-latest.tar

Next Steps:
  Transfer the output directory to your Kubernetes node and run:
    ./scripts/import-backend-image.sh

EOF
    exit 0
}

detect_tool() {
    if [ -n "$FORCE_TOOL" ]; then
        case $FORCE_TOOL in
            docker|skopeo)
                if ! command -v "$FORCE_TOOL" >/dev/null 2>&1; then
                    print_error "$FORCE_TOOL not found"
                    exit 1
                fi
                echo "$FORCE_TOOL"
                return
                ;;
            *)
                print_error "Invalid tool: $FORCE_TOOL (use docker or skopeo)"
                exit 1
                ;;
        esac
    fi
    
    if command -v docker >/dev/null 2>&1; then
        echo "docker"
    elif command -v skopeo >/dev/null 2>&1; then
        echo "skopeo"
    else
        print_error "Neither Docker nor Skopeo found"
        echo "Install one of:"
        echo "  Docker: https://docs.docker.com/engine/install/"
        echo "  Skopeo: sudo apt install skopeo"
        exit 1
    fi
}

download_with_docker() {
    local full_image="${REGISTRY}/${IMAGE}"
    local tar_file="${OUTPUT_DIR}/$(echo $IMAGE | tr '/' '-' | tr ':' '-').tar"
    
    print_step "Configuring Docker certificate..."
    local cert_dir="/etc/docker/certs.d/${REGISTRY}"
    sudo mkdir -p "$cert_dir"
    sudo cp "$CERT_FILE" "$cert_dir/ca.crt"
    
    if systemctl is-active --quiet docker; then
        print_info "Restarting Docker daemon..."
        sudo systemctl restart docker
        sleep 2
    fi
    
    print_step "Logging into registry..."
    echo "$PASSWORD" | docker login "$REGISTRY" -u "$USER" --password-stdin || {
        print_error "Login failed"
        return 1
    }
    
    print_step "Pulling image..."
    docker pull "$full_image" || {
        print_error "Pull failed"
        return 1
    }
    
    print_step "Saving to $tar_file..."
    docker save "$full_image" -o "$tar_file" || {
        print_error "Save failed"
        return 1
    }
    
    print_success "Image saved successfully"
    return 0
}

download_with_skopeo() {
    local full_image="${REGISTRY}/${IMAGE}"
    local tar_file="${OUTPUT_DIR}/$(echo $IMAGE | tr '/' '-' | tr ':' '-').tar"
    local cert_path=$(realpath "$CERT_FILE")
    
    print_step "Downloading with skopeo..."
    skopeo copy \
        --src-cert-dir="$(dirname $cert_path)" \
        --src-creds="${USER}:${PASSWORD}" \
        "docker://${full_image}" \
        "docker-archive:${tar_file}:${full_image}" || {
        print_error "Download failed"
        return 1
    }
    
    print_success "Image saved successfully"
    return 0
}

main() {
    local PASSWORD=""
    local FORCE_TOOL=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--password)
                PASSWORD="$2"
                shift 2
                ;;
            -t|--tool)
                FORCE_TOOL="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage"
                exit 1
                ;;
        esac
    done
    
    echo
    print_info "InSustain Backend Image Download"
    print_info "Working directory: $(pwd)"
    echo
    
    # Check certificate
    if [ ! -f "$CERT_FILE" ]; then
        print_error "Certificate not found: $CERT_FILE"
        exit 1
    fi
    
    # Get password
    if [ -z "$PASSWORD" ]; then
        if [ -n "$REGISTRY_PASSWORD" ]; then
            PASSWORD="$REGISTRY_PASSWORD"
            print_info "Using password from environment"
        else
            read -sp "Registry password: " PASSWORD
            echo
        fi
    fi
    
    if [ -z "$PASSWORD" ]; then
        print_error "Password required"
        exit 1
    fi
    
    # Detect tool
    local tool=$(detect_tool)
    print_info "Using tool: $tool"
    echo
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Download
    print_info "Downloading: ${REGISTRY}/${IMAGE}"
    echo
    
    if [ "$tool" = "docker" ]; then
        download_with_docker
    else
        download_with_skopeo
    fi
    
    local result=$?
    
    echo
    if [ $result -eq 0 ]; then
        print_success "Download complete!"
        echo
        print_info "Image saved in: $OUTPUT_DIR/"
        print_info "Transfer this directory to your Kubernetes node and run:"
        echo "  ./scripts/import-backend-image.sh"
    else
        print_error "Download failed"
        exit 1
    fi
}

main "$@"
