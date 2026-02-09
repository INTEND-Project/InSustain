#!/bin/bash
set -e

# inSustain Setup Script for Collaborators
# This script automates the process of setting up the inSustain application
# on a Kubernetes cluster without requiring server restarts.

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DOCKER_REGISTRY="89.133.95.6:5001"
DOCKER_USER="intend"
NAMESPACE="insustain"

# Variables set during execution
PROMETHEUS_RELEASE=""
KEPLER_INSTALLED=false
KEPLER_NAMESPACE=""
INSTALL_KEPLER=false

# Required images for minimal deployment
IMAGES=(
    "insustain/backend:latest"
)

# Optional images (can be enabled later)
OPTIONAL_IMAGES=(
    "insustain/frontend:latest"
    "insustain/app-simulator:latest"
    "insustain/sysbench:latest"
    "insustain/locust:latest"
    "insustain/loadgen:latest"
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
    
    # Check if running as root for docker operations
    if [ "$EUID" -ne 0 ] && ! groups | grep -q docker; then
        print_error "This script requires root privileges or docker group membership"
        print_info "Run with: sudo $0 or add your user to docker group"
        exit 1
    fi
    
    # Check for required tools
    local missing_tools=()
    
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

setup_docker_certs() {
    print_header "Setting Up Docker Registry Certificates"
    
    local cert_dir="/etc/docker/certs.d/${DOCKER_REGISTRY}"
    local cert_file="certs/docker_ca.crt"
    
    if [ ! -f "$cert_file" ]; then
        print_error "Certificate file not found: $cert_file"
        print_info "Please ensure you have the certs/docker_ca.crt file in the repository"
        exit 1
    fi
    
    # Create cert directory if it doesn't exist
    if [ ! -d "$cert_dir" ]; then
        print_info "Creating certificate directory: $cert_dir"
        sudo mkdir -p "$cert_dir"
    fi
    
    # Copy certificate
    print_info "Installing certificate..."
    sudo cp "$cert_file" "$cert_dir/ca.crt"
    sudo chmod 644 "$cert_dir/ca.crt"
    
    print_success "Certificate installed successfully"
}

restart_docker_if_needed() {
    print_header "Docker Service Configuration"
    
    print_info "Checking if Docker restart is needed..."
    
    # Try to login without restart first
    if docker login "$DOCKER_REGISTRY" -u "$DOCKER_USER" -p "$DOCKER_PASSWORD" >/dev/null 2>&1; then
        print_success "Docker already configured correctly, no restart needed"
        return 0
    fi
    
    print_info "Docker restart required for certificate changes"
    read -p "Restart Docker service? This will briefly interrupt running containers (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Restarting Docker service..."
        sudo systemctl restart docker
        sleep 3
        print_success "Docker service restarted"
    else
        print_error "Docker restart declined. Manual restart required: sudo systemctl restart docker"
        exit 1
    fi
}

docker_login() {
    print_header "Logging into Docker Registry"
    
    if [ -z "$DOCKER_PASSWORD" ]; then
        read -sp "Enter Docker registry password: " DOCKER_PASSWORD
        echo
    fi
    
    if docker login "$DOCKER_REGISTRY" -u "$DOCKER_USER" -p "$DOCKER_PASSWORD"; then
        print_success "Successfully logged into Docker registry"
    else
        print_error "Failed to login to Docker registry"
        exit 1
    fi
}

pull_and_save_images() {
    print_header "Pulling Docker Images"
    
    local image_dir="./insustain-images"
    mkdir -p "$image_dir"
    
    print_info "Pulling required images..."
    for image in "${IMAGES[@]}"; do
        local full_image="${DOCKER_REGISTRY}/${image}"
        print_info "Pulling ${full_image}..."
        
        if docker pull "$full_image"; then
            local image_file="${image_dir}/$(echo $image | tr '/' '-' | tr ':' '-').tar"
            print_info "Saving to ${image_file}..."
            docker save "$full_image" -o "$image_file"
            print_success "Saved ${image}"
        else
            print_error "Failed to pull ${full_image}"
            exit 1
        fi
    done
    
    # Ask about optional images
    echo
    read -p "Do you want to pull optional images (frontend, simulators)? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for image in "${OPTIONAL_IMAGES[@]}"; do
            local full_image="${DOCKER_REGISTRY}/${image}"
            print_info "Pulling ${full_image}..."
            
            if docker pull "$full_image"; then
                local image_file="${image_dir}/$(echo $image | tr '/' '-' | tr ':' '-').tar"
                docker save "$full_image" -o "$image_file"
                print_success "Saved ${image}"
            else
                print_error "Failed to pull ${full_image}, skipping..."
            fi
        done
    fi
}

import_images_to_k8s() {
    print_header "Importing Images to Kubernetes"
    
    local image_dir="./insustain-images"
    
    # Detect container runtime
    local runtime=""
    if command -v k3s >/dev/null 2>&1; then
        runtime="k3s"
        print_info "Detected K3s runtime"
    elif command -v ctr >/dev/null 2>&1; then
        runtime="containerd"
        print_info "Detected containerd runtime"
    elif command -v crictl >/dev/null 2>&1; then
        runtime="cri"
        print_info "Detected CRI-O runtime"
    else
        print_error "Could not detect container runtime"
        print_info "Images saved in ${image_dir}/ for manual import"
        return 1
    fi
    
    # Import images
    for tar_file in "$image_dir"/*.tar; do
        if [ -f "$tar_file" ]; then
            print_info "Importing $(basename $tar_file)..."
            
            case $runtime in
                k3s)
                    sudo k3s ctr images import "$tar_file"
                    ;;
                containerd)
                    sudo ctr -n k8s.io images import "$tar_file"
                    ;;
                cri)
                    sudo crictl load -i "$tar_file"
                    ;;
            esac
            
            if [ $? -eq 0 ]; then
                print_success "Imported $(basename $tar_file)"
            else
                print_error "Failed to import $(basename $tar_file)"
            fi
        fi
    done
}

setup_kubernetes() {
    print_header "Setting Up Kubernetes Resources"
    
    # Check if namespace exists
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_info "Namespace $NAMESPACE already exists"
    else
        print_info "Creating namespace $NAMESPACE..."
        kubectl create namespace "$NAMESPACE"
        print_success "Namespace created"
    fi
    
    # Check and install Prometheus if needed
    if ! check_prometheus; then
        echo
        read -p "kube-prometheus-stack not found. Install it now? (Y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            install_prometheus
        else
            print_error "kube-prometheus-stack is required for inSustain"
            print_info "Please install it manually before continuing"
            exit 1
        fi
    fi
    
    # Check Kepler installation
    echo
    check_kepler
    
    if [ "$KEPLER_INSTALLED" = false ]; then
        echo
        print_info "Kepler provides low-level energy consumption metrics"
        read -p "Install Kepler via inSustain helm chart? (Y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            INSTALL_KEPLER=true
            print_info "Kepler will be installed with inSustain"
        else
            INSTALL_KEPLER=false
            print_info "Skipping Kepler installation"
            print_info "You can enable it later with: helm upgrade insustain --set kepler.enabled=true"
        fi
    else
        INSTALL_KEPLER=false
        print_info "Using existing Kepler installation in '${KEPLER_NAMESPACE}' namespace"
    fi
}

check_prometheus() {
    print_header "Checking Prometheus Installation"
    
    # Check if kube-prometheus-stack is installed
    if helm list -n monitoring 2>/dev/null | grep -q "prometheus"; then
        local version=$(helm list -n monitoring -o json | grep -A5 "prometheus" | grep "app_version" | cut -d'"' -f4)
        print_success "kube-prometheus-stack already installed (version: ${version:-unknown})"
        
        # Get the release name for ServiceMonitor labels
        PROMETHEUS_RELEASE=$(helm list -n monitoring -o json | grep -B5 "kube-prometheus-stack" | grep "name" | head -1 | cut -d'"' -f4)
        if [ -z "$PROMETHEUS_RELEASE" ]; then
            PROMETHEUS_RELEASE="prometheus"
        fi
        print_info "Prometheus release name: $PROMETHEUS_RELEASE"
        return 0
    fi
    
    # Check if Prometheus exists in monitoring namespace (might be installed differently)
    if kubectl get deployment -n monitoring 2>/dev/null | grep -q "prometheus"; then
        print_success "Prometheus detected in monitoring namespace"
        PROMETHEUS_RELEASE="prometheus"
        return 0
    fi
    
    return 1
}

install_prometheus() {
    print_header "Installing kube-prometheus-stack"
    
    # Recommended version from README
    local PROMETHEUS_VERSION="65.1.1"  # Corresponds to prometheus-operator v0.80+
    
    print_info "Installing kube-prometheus-stack version ${PROMETHEUS_VERSION}..."
    print_info "This includes Prometheus, Grafana, Node Exporter, and more"
    
    # Add helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    
    # Install with specific version
    if helm install prometheus prometheus-community/kube-prometheus-stack \
        --version "$PROMETHEUS_VERSION" \
        --namespace monitoring \
        --create-namespace \
        --wait \
        --timeout 10m; then
        
        print_success "kube-prometheus-stack installed successfully"
        PROMETHEUS_RELEASE="prometheus"
    else
        print_error "Failed to install kube-prometheus-stack"
        print_info "You can install it manually with:"
        echo "  helm install prometheus prometheus-community/kube-prometheus-stack \\"
        echo "    --namespace monitoring --create-namespace --wait"
        exit 1
    fi
}

check_kepler() {
    print_header "Checking Kepler Installation"
    
    # Check in kepler namespace
    if kubectl get deployment -n kepler kepler-exporter 2>/dev/null >/dev/null; then
        print_success "Kepler found in 'kepler' namespace"
        KEPLER_INSTALLED=true
        KEPLER_NAMESPACE="kepler"
        return 0
    fi
    
    # Check in monitoring namespace
    if kubectl get deployment -n monitoring kepler-exporter 2>/dev/null >/dev/null; then
        print_success "Kepler found in 'monitoring' namespace"
        KEPLER_INSTALLED=true
        KEPLER_NAMESPACE="monitoring"
        return 0
    fi
    
    # Check if kepler helm release exists
    if helm list -A 2>/dev/null | grep -q "kepler"; then
        KEPLER_NAMESPACE=$(helm list -A -o json | grep -B5 "kepler" | grep "namespace" | head -1 | cut -d'"' -f4)
        print_success "Kepler helm release found in '${KEPLER_NAMESPACE}' namespace"
        KEPLER_INSTALLED=true
        return 0
    fi
    
    print_info "Kepler not detected in cluster"
    KEPLER_INSTALLED=false
    return 1
}

install_helm_chart() {
    print_header "Installing inSustain Helm Chart"
    
    # Update helm dependencies
    print_info "Updating Helm dependencies..."
    helm dependency update insustain/
    
    # Build helm install/upgrade command
    local helm_cmd="helm"
    local helm_args=(
        "--namespace" "$NAMESPACE"
        "--create-namespace"
        "--set" "backend.image.pullPolicy=Never"
        "--set" "global.image.repository=$DOCKER_REGISTRY"
        "--set" "global.monitoring.labels.release=$PROMETHEUS_RELEASE"
    )
    
    # Add Kepler settings
    if [ "$INSTALL_KEPLER" = true ]; then
        helm_args+=("--set" "kepler.enabled=true")
        helm_args+=("--set" "kepler.serviceMonitor.enabled=true")
        helm_args+=("--set" "kepler.serviceMonitor.labels.release=$PROMETHEUS_RELEASE")
        print_info "Kepler will be installed and configured"
    else
        helm_args+=("--set" "kepler.enabled=false")
        if [ "$KEPLER_INSTALLED" = true ]; then
            print_info "Using existing Kepler installation"
        fi
    fi
    
    # Check if already installed
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "insustain"; then
        print_info "inSustain already installed. Upgrading..."
        $helm_cmd upgrade insustain insustain/ "${helm_args[@]}" --reuse-values
    else
        print_info "Installing inSustain..."
        $helm_cmd install insustain insustain/ "${helm_args[@]}"
    fi
    
    if [ $? -eq 0 ]; then
        print_success "Helm chart installed/upgraded successfully"
    else
        print_error "Failed to install/upgrade Helm chart"
        exit 1
    fi
}

show_access_info() {
    print_header "Access Information"
    
    echo
    print_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=backend -n "$NAMESPACE" --timeout=300s 2>/dev/null || true
    
    echo
    print_success "inSustain is now deployed!"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ACCESSING SERVICES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Use port-forwarding to access services:"
    echo
    echo "  📊 Backend API:"
    echo "    kubectl port-forward -n $NAMESPACE svc/insustain-backend 8089:8089"
    echo "    Access at: http://localhost:8089"
    echo "    API Docs:  http://localhost:8089/docs"
    echo
    echo "  🔬 MLflow Model Registry:"
    echo "    kubectl port-forward -n $NAMESPACE svc/insustain-mlflow 9999:5000"
    echo "    Access at: http://localhost:9999"
    echo
    echo "  📈 Prometheus:"
    echo "    kubectl port-forward -n monitoring svc/${PROMETHEUS_RELEASE}-kube-prometheus-prometheus 9090:9090"
    echo "    Access at: http://localhost:9090"
    echo
    echo "  📉 Grafana:"
    echo "    kubectl port-forward -n monitoring svc/${PROMETHEUS_RELEASE}-grafana 3000:80"
    echo "    Access at: http://localhost:3000"
    echo "    Default credentials: admin / prom-operator"
    echo
    
    if [ "$KEPLER_INSTALLED" = true ] || [ "$INSTALL_KEPLER" = true ]; then
        local kepler_ns="${KEPLER_NAMESPACE:-$NAMESPACE}"
        echo "  ⚡ Kepler Metrics:"
        echo "    kubectl port-forward -n $kepler_ns svc/kepler-exporter 9102:9102"
        echo "    Metrics at: http://localhost:9102/metrics"
        echo
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  USEFUL COMMANDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "  Check pod status:"
    echo "    kubectl get pods -n $NAMESPACE"
    echo
    echo "  View backend logs:"
    echo "    kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=backend -f"
    echo
    echo "  Check ServiceMonitors:"
    echo "    kubectl get servicemonitor -n $NAMESPACE"
    echo
    echo "  View all services:"
    echo "    kubectl get svc -n $NAMESPACE"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

cleanup() {
    print_header "Cleanup"
    
    read -p "Remove downloaded image files? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf ./insustain-images
        print_success "Image files removed"
    fi
}

main() {
    echo
    print_header "inSustain Setup Script"
    echo
    print_info "This script will:"
    echo "  1. Configure Docker registry certificates"
    echo "  2. Pull inSustain images from private registry"
    echo "  3. Import images to Kubernetes"
    echo "  4. Deploy inSustain using Helm"
    echo
    
    read -p "Continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Setup cancelled"
        exit 0
    fi
    
    check_prerequisites
    setup_docker_certs
    restart_docker_if_needed
    docker_login
    pull_and_save_images
    import_images_to_k8s
    setup_kubernetes
    install_helm_chart
    show_access_info
    cleanup
    
    echo
    print_success "Setup complete!"
}

# Run main function
main
