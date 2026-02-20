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

# Find git repository root
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
cd "$GIT_ROOT"

DEFAULT_REGISTRY="89.133.95.6:5001"
HARBOR_REGISTRY="registry.gate-ai.eu"

# Default to local registry
USE_HARBOR=false
REGISTRY="$DEFAULT_REGISTRY"
USER="intend"
CERT_FILE="certs/docker_ca.crt"
OUTPUT_DIR="insustain-images"

# Image name mapping (will be set based on registry)
declare -A IMAGE_MAP_LOCAL=(
    ["backend"]="insustain/backend:latest"
    ["nginx-log-parser"]="insustain/nginx-log-parser:latest"
)

declare -A IMAGE_MAP_HARBOR=(
    ["backend"]="intend/insustain-backend:latest"
    ["nginx-log-parser"]="intend/insustain-nginx-log-parser:latest"
)

print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_step() { echo -e "${BLUE}▶${NC} $1"; }

show_help() {
    cat << EOF
Download InSustain Images

Usage: $0 [OPTIONS] [IMAGE_NAMES...]

Downloads backend and nginx-log-parser images from private registry using Docker or Skopeo.

Options:
  -p, --password PASSWORD    Registry password (or use REGISTRY_PASSWORD env var)
  -t, --tool TOOL           Force tool: docker or skopeo (auto-detect by default)
  -o, --output DIR          Output directory (default: insustain-images)
  --harbor                  Download from Harbor registry (registry.gate-ai.eu)
  --local                   Download from local registry (default: 89.133.95.6:5001)
  -h, --help                Show this help

Image Names:
  backend, nginx-log-parser
  If no image specified, all images will be downloaded

Examples:
  $0 -p mypassword                    # Download all images from local registry
  $0 -p mypassword backend            # Download backend only from local
  $0 --harbor -p mypassword           # Download all from Harbor
  $0 --harbor -p mypassword nginx-log-parser
  $0 --tool skopeo -p mypassword backend nginx-log-parser
  REGISTRY_PASSWORD=mypassword $0

Output:
  Creates directory with: 
    - insustain-backend-latest.tar (or intend-insustain-backend-latest.tar for Harbor)
    - insustain-nginx-log-parser-latest.tar (or intend-insustain-nginx-log-parser-latest.tar for Harbor)

Next Steps:
  Transfer the output directory to your Kubernetes node and run:
    ./scripts/import-backend-image.sh [--harbor]

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
    local image=$1
    local full_image="${REGISTRY}/${image}"
    local tar_file="${OUTPUT_DIR}/$(echo $image | tr '/' '-' | tr ':' '-').tar"
    
    print_step "Pulling image: $image..."
    docker pull "$full_image" || {
        print_error "Pull failed for $image"
        return 1
    }
    
    print_step "Saving to $tar_file..."
    docker save "$full_image" -o "$tar_file" || {
        print_error "Save failed for $image"
        return 1
    }
    
    print_success "Image $image saved successfully"
    return 0
}

download_with_skopeo() {
    local image=$1
    local full_image="${REGISTRY}/${image}"
    local tar_file="${OUTPUT_DIR}/$(echo $image | tr '/' '-' | tr ':' '-').tar"
    local cert_path=$(realpath "$CERT_FILE")
    
    print_step "Downloading $image with skopeo..."
    skopeo copy \
        --src-cert-dir="$(dirname $cert_path)" \
        --src-creds="${USER}:${PASSWORD}" \
        "docker://${full_image}" \
        "docker-archive:${tar_file}:${full_image}" || {
        print_error "Download failed for $image"
        return 1
    }
    
    print_success "Image $image saved successfully"
    return 0
}

main() {
    local PASSWORD=""
    local FORCE_TOOL=""
    local TARGET_IMAGES=()
    
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
            --harbor)
                USE_HARBOR=true
                REGISTRY="$HARBOR_REGISTRY"
                shift
                ;;
            --local)
                USE_HARBOR=false
                REGISTRY="$DEFAULT_REGISTRY"
                shift
                ;;
            -h|--help)
                show_help
                ;;
            -*)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage"
                exit 1
                ;;
            *)
                # Image name argument - use appropriate map
                if [ "$USE_HARBOR" = true ]; then
                    if [[ -n "${IMAGE_MAP_HARBOR[$1]}" ]]; then
                        TARGET_IMAGES+=("${IMAGE_MAP_HARBOR[$1]}")
                    else
                        print_error "Unknown image: $1 (use: backend, nginx-log-parser)"
                        exit 1
                    fi
                else
                    if [[ -n "${IMAGE_MAP_LOCAL[$1]}" ]]; then
                        TARGET_IMAGES+=("${IMAGE_MAP_LOCAL[$1]}")
                    else
                        print_error "Unknown image: $1 (use: backend, nginx-log-parser)"
                        exit 1
                    fi
                fi
                shift
                ;;
        esac
    done
    
    # If no images specified, download all
    if [ ${#TARGET_IMAGES[@]} -eq 0 ]; then
        if [ "$USE_HARBOR" = true ]; then
            TARGET_IMAGES=("${IMAGE_MAP_HARBOR[@]}")
        else
            TARGET_IMAGES=("${IMAGE_MAP_LOCAL[@]}")
        fi
        print_info "No images specified, downloading all images"
    fi
    
    echo
    print_info "InSustain Images Download"
    print_info "Registry: $REGISTRY"
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
    
    # Configure Docker if using docker
    if [ "$tool" = "docker" ]; then
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
            exit 1
        }
        echo
    fi
    
    # Download all images
    local failed=0
    for image in "${TARGET_IMAGES[@]}"; do
        print_info "Downloading: ${REGISTRY}/${image}"
        echo
        
        if [ "$tool" = "docker" ]; then
            download_with_docker "$image" || failed=1
        else
            download_with_skopeo "$image" || failed=1
        fi
        echo
    done
    
    if [ $failed -eq 0 ]; then
        print_success "All downloads complete!"
        echo
        print_info "Images saved in: $OUTPUT_DIR/"
        print_info "Transfer this directory to your Kubernetes node and run:"
        echo "  ./scripts/import-backend-image.sh"
    else
        print_error "Some downloads failed"
        exit 1
    fi
}

main "$@"
