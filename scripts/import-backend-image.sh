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
IMAGE="insustain/backend:latest"
CERT_FILE="certs/docker_ca.crt"
IMAGE_DIR="insustain-images"

print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_step() { echo -e "${BLUE}▶${NC} $1"; }

show_help() {
    cat << EOF
Import InSustain Backend Image to Kubernetes

Usage: $0 [OPTIONS]

Imports backend image to Kubernetes runtime (K3s, containerd, or CRI-O).
Can import from tar file or pull directly from registry.

Options:
  -m, --method METHOD       Import method: tar or pull (default: auto-detect)
  -p, --password PASSWORD   Registry password (required for pull method)
  -d, --dir DIR            Image directory (default: insustain-images)
  -h, --help               Show this help

Methods:
  tar   - Import from tar file (offline, no registry access needed)
  pull  - Pull directly from registry (requires password and network)
  auto  - Auto-detect: use tar if available, otherwise pull

Examples:
  # Import from tar file (default if tar exists)
  $0

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
    local tar_file="${IMAGE_DIR}/$(echo $IMAGE | tr '/' '-' | tr ':' '-').tar"
    
    if [ ! -f "$tar_file" ]; then
        print_error "Tar file not found: $tar_file"
        return 1
    fi
    
    print_step "Importing from tar file..."
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
    local full_image="${REGISTRY}/${IMAGE}"
    
    if [ -z "$password" ]; then
        print_error "Password required for pull method"
        return 1
    fi
    
    print_step "Pulling from registry..."
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
    local full_image="${REGISTRY}/${IMAGE}"
    
    print_step "Verifying image..."
    
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
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage"
                exit 1
                ;;
        esac
    done
    
    echo
    print_info "InSustain Backend Image Import"
    print_info "Working directory: $(pwd)"
    echo
    
    # Detect runtime
    print_step "Detecting Kubernetes runtime..."
    local runtime=$(detect_runtime)
    print_success "Runtime: $runtime"
    echo
    
    # Determine method
    if [ "$METHOD" = "auto" ]; then
        local tar_file="${IMAGE_DIR}/$(echo $IMAGE | tr '/' '-' | tr ':' '-').tar"
        if [ -f "$tar_file" ]; then
            METHOD="tar"
            print_info "Auto-detected method: tar (file found)"
        else
            METHOD="pull"
            print_info "Auto-detected method: pull (no tar file)"
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
    
    # Import image
    if [ "$METHOD" = "tar" ]; then
        if import_from_tar "$runtime"; then
            print_success "Import successful"
        else
            print_error "Import failed"
            exit 1
        fi
    else
        # Get password if not provided
        if [ -z "$PASSWORD" ]; then
            if [ -n "$REGISTRY_PASSWORD" ]; then
                PASSWORD="$REGISTRY_PASSWORD"
                print_info "Using password from environment"
            else
                read -sp "Registry password: " PASSWORD
                echo
            fi
        fi
        
        if pull_from_registry "$runtime" "$PASSWORD"; then
            print_success "Pull successful"
        else
            print_error "Pull failed"
            echo
            print_info "Troubleshooting:"
            echo "  - Verify registry certificate is configured"
            echo "  - Check password is correct"
            echo "  - See INSTALL.md for certificate setup"
            exit 1
        fi
    fi
    
    echo
    
    # Verify
    if verify_image "$runtime"; then
        echo
        print_success "Image ready in Kubernetes!"
        echo
        print_info "Next steps:"
        echo "  1. Deploy InSustain:"
        echo "     helm install insustain insustain/ \\"
        echo "       --namespace insustain --create-namespace \\"
        echo "       --set backend.image.pullPolicy=IfNotPresent"
        echo
    else
        exit 1
    fi
}

main "$@"
