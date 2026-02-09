#!/bin/bash
set -e

# Import Images to K3s Script
# This script pulls images from the registry and imports them directly to K3s
# Bypasses registry pull issues by loading images locally

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
DOCKER_REGISTRY="89.133.95.6:5001"
DOCKER_USER="intend"
NAMESPACE="insustain"

# Images to import
IMAGES=(
    "insustain/backend:latest"
)

print_header() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v k3s >/dev/null 2>&1 || missing_tools+=("k3s")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check if k3s is running
    if ! sudo k3s kubectl get nodes >/dev/null 2>&1; then
        print_error "K3s is not running or not accessible"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

docker_login() {
    print_header "Docker Registry Login"
    
    # Check for password in environment or prompt
    if [ -z "$DOCKER_PASSWORD" ]; then
        if [ -n "$1" ]; then
            DOCKER_PASSWORD="$1"
            print_info "Using password from argument"
        else
            read -sp "Enter Docker registry password: " DOCKER_PASSWORD
            echo
        fi
    else
        print_info "Using password from environment variable"
    fi
    
    print_info "Logging into Docker registry..."
    echo "$DOCKER_PASSWORD" | docker login "$DOCKER_REGISTRY" -u "$DOCKER_USER" --password-stdin
    
    if [ $? -eq 0 ]; then
        print_success "Docker login successful"
    else
        print_error "Docker login failed"
        exit 1
    fi
}

pull_and_import_images() {
    print_header "Pulling and Importing Images"
    
    local temp_dir="/tmp/k3s-images-$$"
    mkdir -p "$temp_dir"
    
    local success_count=0
    local fail_count=0
    
    for image_name in "${IMAGES[@]}"; do
        local full_image="${DOCKER_REGISTRY}/${image_name}"
        local image_file="${temp_dir}/$(echo $image_name | tr '/' '-' | tr ':' '-').tar"
        
        echo
        print_info "Processing: $full_image"
        
        # Pull image
        print_info "  Pulling from registry..."
        if docker pull "$full_image"; then
            print_success "  Image pulled successfully"
        else
            print_error "  Failed to pull image"
            ((fail_count++))
            continue
        fi
        
        # Save image to tar
        print_info "  Saving to tar file..."
        if docker save "$full_image" -o "$image_file"; then
            print_success "  Image saved to $image_file"
        else
            print_error "  Failed to save image"
            ((fail_count++))
            continue
        fi
        
        # Import to K3s
        print_info "  Importing to K3s (requires sudo)..."
        if sudo k3s ctr images import "$image_file"; then
            print_success "  Image imported to K3s"
            ((success_count++))
            
            # Clean up tar file
            rm -f "$image_file"
        else
            print_error "  Failed to import to K3s"
            print_info "  Tar file kept at: $image_file"
            ((fail_count++))
        fi
    done
    
    # Clean up temp directory if empty
    rmdir "$temp_dir" 2>/dev/null || true
    
    echo
    print_header "Import Summary"
    echo "  Successfully imported: $success_count"
    echo "  Failed: $fail_count"
    echo
    
    if [ $success_count -gt 0 ]; then
        print_success "Images are now available in K3s"
        print_info "You can now deploy with pullPolicy: IfNotPresent"
    fi
    
    if [ $fail_count -gt 0 ]; then
        print_error "Some images failed to import"
        exit 1
    fi
}

verify_images() {
    print_header "Verifying Images in K3s"
    
    echo
    print_info "Images available in K3s:"
    echo
    
    for image_name in "${IMAGES[@]}"; do
        local full_image="${DOCKER_REGISTRY}/${image_name}"
        if sudo k3s ctr images ls | grep -q "$full_image"; then
            echo -e "  ${GREEN}✓${NC} $full_image"
        else
            echo -e "  ${RED}✗${NC} $full_image"
        fi
    done
    
    echo
}

main() {
    # Parse arguments
    local PASSWORD_ARG=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--password)
                PASSWORD_ARG="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Import Docker images directly to K3s, bypassing registry pull issues."
                echo ""
                echo "Options:"
                echo "  -p, --password PASSWORD    Docker registry password"
                echo "  -h, --help                 Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  DOCKER_PASSWORD            Docker registry password"
                echo ""
                echo "Examples:"
                echo "  $0 --password mypassword"
                echo "  DOCKER_PASSWORD=mypassword $0"
                echo ""
                echo "What this script does:"
                echo "  1. Logs into Docker registry"
                echo "  2. Pulls images from registry"
                echo "  3. Saves images to tar files"
                echo "  4. Imports tar files to K3s"
                echo "  5. Cleans up temporary files"
                echo ""
                echo "After running this script, deploy with:"
                echo "  helm install insustain insustain/ --set backend.image.pullPolicy=IfNotPresent"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Set password if provided as argument
    if [ -n "$PASSWORD_ARG" ]; then
        export DOCKER_PASSWORD="$PASSWORD_ARG"
    fi
    
    echo
    print_header "Import Images to K3s"
    echo
    print_info "This script will:"
    echo "  1. Pull images from Docker registry"
    echo "  2. Import them directly to K3s"
    echo "  3. Bypass registry pull issues"
    echo
    print_info "Images to import:"
    for img in "${IMAGES[@]}"; do
        echo "  • ${DOCKER_REGISTRY}/${img}"
    done
    echo
    
    read -p "Continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Import cancelled"
        exit 0
    fi
    
    check_prerequisites
    docker_login "$PASSWORD_ARG"
    pull_and_import_images
    verify_images
    
    echo
    print_success "Import complete!"
    echo
    print_info "Next steps:"
    echo "  1. Run the setup script: ./scripts/setup-insustain-k8s-native.sh"
    echo "  2. Or deploy manually with: helm install insustain insustain/ --set backend.image.pullPolicy=IfNotPresent"
    echo
}

# Run main function with all arguments
main "$@"
