#!/bin/bash
set -e

# Import Backend Image Script
# Imports InSustain backend image to Kubernetes/K3s
# Supports: K3s, containerd, CRI-O
# Methods: From tar file OR direct pull from registry

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
ALL_IMAGES=("intend/insustain-backend:latest" "intend/insustain-nginx-log-parser:latest" "intend/insustain-attribution-pipeline:latest")
CERT_FILE="certs/docker_ca.crt"
IMAGE_DIR="insustain-images"

# Image name mapping (matches build.sh image names)
declare -A IMAGE_MAP=(
    ["backend"]="intend/insustain-backend:latest"
    ["nginx-log-parser"]="intend/insustain-nginx-log-parser:latest"
    ["attribution-pipeline"]="intend/insustain-attribution-pipeline:latest"
    ["frontend"]="intend/insustain-frontend:latest"
    ["app-simulator"]="intend/insustain-app-simulator:latest"
    ["sysbench"]="intend/insustain-sysbench:latest"
    ["flask-app"]="intend/insustain-flask-app:latest"
    ["locust"]="intend/insustain-locust:latest"
)

print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_step() { echo -e "${BLUE}▶${NC} $1"; }

show_help() {
    cat << EOF
Import InSustain Images to Kubernetes

Usage: $0 [OPTIONS] [IMAGE_NAMES...]

Imports backend and nginx-log-parser images to Kubernetes runtime (K3s, containerd, or CRI-O).
Can import from tar file or pull directly from registry.

Options:
  -m, --method METHOD       Import method: tar or pull (default: auto-detect)
  -p, --password PASSWORD   Registry password (required for pull method)
  -d, --dir DIR            Image directory (default: insustain-images)
  -h, --help               Show this help

Image Names:
  backend, nginx-log-parser, attribution-pipeline, frontend, app-simulator,
  sysbench, flask-app, locust
  If no image specified, default images (backend, nginx-log-parser, attribution-pipeline) will be imported

Methods:
  tar   - Import from tar file (offline, no registry access needed)
  pull  - Pull directly from registry (requires password and network)
  auto  - Auto-detect: use tar if available, otherwise pull

Examples:
  # Import all images from tar files (default if tar exists)
  $0

  # Import backend only
  $0 backend

  # Import nginx-log-parser only
  $0 nginx-log-parser

  # Import attribution-pipeline only
  $0 attribution-pipeline

  # Force pull from registry
  $0 --method pull -p mypassword

  # Import from custom directory
  $0 --dir /path/to/images

Supported Runtimes:
  - K3s (k3s ctr)
  - containerd (ctr -n k8s.io)
  - CRI-O (crictl)

Prerequisites for Pull Method:
  - Registry certificate must be configured
  - See INSTALL.md for certificate setup

After Import:
  Deploy with: helm install insustain insustain/ \\
    --set backend.image.pullPolicy=IfNotPresent

EOF
    exit 0
}

detect_runtime() {
    if command -v k3s >/dev/null 2>&1 && k3s kubectl get nodes >/dev/null 2>&1; then
        echo "k3s"
    elif command -v ctr >/dev/null 2>&1 && sudo ctr -n k8s.io version >/dev/null 2>&1; then
        echo "containerd"
    elif command -v crictl >/dev/null 2>&1 && sudo crictl version >/dev/null 2>&1; then
        echo "crio"
    else
        print_error "No supported Kubernetes runtime found"
        echo "Supported: K3s, containerd, CRI-O"
        exit 1
    fi
}

import_from_tar() {
    local runtime=$1
    local image=$2
    local tar_file="${IMAGE_DIR}/$(echo $image | tr '/' '-' | tr ':' '-').tar"
    
    if [ ! -f "$tar_file" ]; then
        print_error "Tar file not found: $tar_file"
        return 1
    fi
    
    print_step "Importing $image from tar file..."
    print_info "File: $tar_file"
    
    case $runtime in
        k3s)
            sudo k3s ctr images import "$tar_file"
            ;;
        containerd)
            sudo ctr -n k8s.io images import "$tar_file"
            ;;
        crio)
            sudo crictl load -i "$tar_file"
            ;;
    esac
    
    return $?
}

pull_from_registry() {
    local runtime=$1
    local password=$2
    local image=$3
    local full_image="${REGISTRY}/${image}"
    
    if [ -z "$password" ]; then
        print_error "Password required for pull method"
        return 1
    fi
    
    print_step "Pulling $image from registry..."
    print_info "Image: $full_image"
    
    case $runtime in
        k3s)
            sudo k3s ctr images pull --user "${USER}:${password}" "$full_image"
            ;;
        containerd)
            sudo ctr -n k8s.io images pull --user "${USER}:${password}" "$full_image"
            ;;
        crio)
            sudo crictl pull --creds "${USER}:${password}" "$full_image"
            ;;
    esac
    
    return $?
}

verify_image() {
    local runtime=$1
    local image=$2
    local full_image="${REGISTRY}/${image}"
    
    print_step "Verifying $image..."
    
    local found=false
    case $runtime in
        k3s)
            if sudo k3s ctr images ls | grep -q "$full_image"; then
                found=true
            fi
            ;;
        containerd)
            if sudo ctr -n k8s.io images ls | grep -q "$full_image"; then
                found=true
            fi
            ;;
        crio)
            if sudo crictl images | grep -q "$full_image"; then
                found=true
            fi
            ;;
    esac
    
    if [ "$found" = true ]; then
        print_success "Image verified: $full_image"
        return 0
    else
        print_error "Image not found in runtime"
        return 1
    fi
}

main() {
    local METHOD="auto"
    local PASSWORD=""
    local TARGET_IMAGES=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--method)
                METHOD="$2"
                shift 2
                ;;
            -p|--password)
                PASSWORD="$2"
                shift 2
                ;;
            -d|--dir)
                IMAGE_DIR="$2"
                shift 2
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
                # Image name argument
                if [[ -n "${IMAGE_MAP[$1]}" ]]; then
                    TARGET_IMAGES+=("${IMAGE_MAP[$1]}")
                else
                    print_error "Unknown image: $1"
                    echo "Available images: ${!IMAGE_MAP[@]}"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # If no images specified, import all
    if [ ${#TARGET_IMAGES[@]} -eq 0 ]; then
        TARGET_IMAGES=("${ALL_IMAGES[@]}")
        print_info "No images specified, importing all images"
    fi
    
    echo
    print_info "InSustain Images Import"
    print_info "Working directory: $(pwd)"
    echo
    
    # Detect runtime
    print_step "Detecting Kubernetes runtime..."
    local runtime=$(detect_runtime)
    print_success "Runtime: $runtime"
    echo
    
    # Determine method (check if any tar file exists)
    if [ "$METHOD" = "auto" ]; then
        local has_tar=false
        for image in "${TARGET_IMAGES[@]}"; do
            local tar_file="${IMAGE_DIR}/$(echo $image | tr '/' '-' | tr ':' '-').tar"
            if [ -f "$tar_file" ]; then
                has_tar=true
                break
            fi
        done
        
        if [ "$has_tar" = true ]; then
            METHOD="tar"
            print_info "Auto-detected method: tar (files found)"
        else
            METHOD="pull"
            print_info "Auto-detected method: pull (no tar files)"
        fi
    fi
    
    # Validate method
    case $METHOD in
        tar|pull)
            print_info "Import method: $METHOD"
            ;;
        *)
            print_error "Invalid method: $METHOD (use tar or pull)"
            exit 1
            ;;
    esac
    
    echo
    
    # Get password if pull method
    if [ "$METHOD" = "pull" ]; then
        if [ -z "$PASSWORD" ]; then
            if [ -n "$REGISTRY_PASSWORD" ]; then
                PASSWORD="$REGISTRY_PASSWORD"
                print_info "Using password from environment"
            else
                read -sp "Registry password: " PASSWORD
                echo
            fi
        fi
    fi
    
    # Import all images
    local failed=0
    for image in "${TARGET_IMAGES[@]}"; do
        echo
        print_info "Processing: $image"
        
        if [ "$METHOD" = "tar" ]; then
            if import_from_tar "$runtime" "$image"; then
                print_success "Import successful: $image"
            else
                print_error "Import failed: $image"
                failed=1
            fi
        else
            if pull_from_registry "$runtime" "$PASSWORD" "$image"; then
                print_success "Pull successful: $image"
            else
                print_error "Pull failed: $image"
                failed=1
            fi
        fi
        
        # Verify
        verify_image "$runtime" "$image" || failed=1
    done
    
    echo
    
    if [ $failed -eq 0 ]; then
        print_success "All images ready in Kubernetes!"
        echo
        print_info "Next steps:"
        echo "  1. Deploy InSustain:"
        echo "     helm install insustain insustain/ \\"
        echo "       --namespace insustain --create-namespace \\"
        echo "       --set backend.image.pullPolicy=IfNotPresent"
        echo
    else
        print_error "Some imports failed"
        if [ "$METHOD" = "pull" ]; then
            echo
            print_info "Troubleshooting:"
            echo "  - Verify registry certificate is configured"
            echo "  - Check password is correct"
            echo "  - See INSTALL.md for certificate setup"
        fi
        exit 1
    fi
}

main "$@"
