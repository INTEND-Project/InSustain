#!/bin/bash
set -e

# inSustain Setup Script - Pre-imported Images Approach
# This script assumes images have been pre-imported using import-backend-image.sh
# This is the recommended approach for air-gapped or offline deployments

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
NAMESPACE="insustain"

# Variables set during execution
PROMETHEUS_RELEASE=""
KEPLER_INSTALLED=false
KEPLER_NAMESPACE=""
INSTALL_KEPLER=false
AUTO_YES=false

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
    
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check kubectl connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

check_backend_image() {
    print_header "Checking Backend Image"
    
    local runtime=""
    local image_found=false
    
    # Detect runtime
    if command -v k3s >/dev/null 2>&1 && k3s kubectl get nodes >/dev/null 2>&1; then
        runtime="k3s"
        if sudo k3s ctr images ls | grep -q "89.133.95.6:5001/insustain/backend:latest"; then
            image_found=true
        fi
    elif command -v ctr >/dev/null 2>&1 && sudo ctr -n k8s.io version >/dev/null 2>&1; then
        runtime="containerd"
        if sudo ctr -n k8s.io images ls | grep -q "89.133.95.6:5001/insustain/backend:latest"; then
            image_found=true
        fi
    elif command -v crictl >/dev/null 2>&1 && sudo crictl version >/dev/null 2>&1; then
        runtime="crio"
        if sudo crictl images | grep -q "89.133.95.6:5001/insustain/backend:latest"; then
            image_found=true
        fi
    fi
    
    if [ "$image_found" = true ]; then
        print_success "Backend image found in $runtime"
    else
        print_error "Backend image not found in container runtime"
        echo
        print_info "Please import the backend image first:"
        echo "  ./scripts/import-backend-image.sh"
        echo
        exit 1
    fi
}

setup_namespace() {
    print_header "Setting Up Namespace"
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_info "Creating namespace $NAMESPACE..."
        kubectl create namespace "$NAMESPACE"
        print_success "Namespace created"
    else
        print_success "Namespace already exists"
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
    
    # Install with specific version (repo already added in add_helm_repositories)
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

setup_kubernetes() {
    print_header "Setting Up Kubernetes Resources"
    
    # Check and install Prometheus if needed
    if ! check_prometheus; then
        echo
        if [ "$AUTO_YES" = true ]; then
            print_info "Auto-yes mode: Installing kube-prometheus-stack..."
            install_prometheus
        else
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
    fi
    
    # Check Kepler installation
    echo
    check_kepler || true  # Don't exit on false return
    
    if [ "$KEPLER_INSTALLED" = false ]; then
        echo
        print_info "Kepler provides low-level energy consumption metrics"
        
        if [ "$AUTO_YES" = true ]; then
            INSTALL_KEPLER=true
            print_info "Auto-yes mode: Kepler will be installed with inSustain"
        else
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
        fi
    else
        INSTALL_KEPLER=false
        print_info "Using existing Kepler installation in '${KEPLER_NAMESPACE}' namespace"
    fi
}

add_helm_repositories() {
    print_header "Adding Required Helm Repositories"
    
    print_info "Adding Helm repositories..."
    
    # Add all required repositories
    helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart 2>/dev/null || true
    helm repo add community-charts https://community-charts.github.io/helm-charts 2>/dev/null || true
    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo add minio https://charts.min.io/ 2>/dev/null || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    
    print_info "Updating Helm repositories..."
    helm repo update >/dev/null 2>&1
    
    print_success "Helm repositories configured"
}

deploy_insustain() {
    print_header "Deploying inSustain"
    
    # Add required Helm repositories
    add_helm_repositories
    
    # Update helm dependencies
    print_info "Building Helm dependencies..."
    helm dependency build insustain/
    
    # Build helm install/upgrade command
    local helm_cmd="helm"
    local helm_args=(
        "--namespace" "$NAMESPACE"
        "--set" "backend.image.pullPolicy=IfNotPresent"
        "--set" "global.monitoring.labels.release=$PROMETHEUS_RELEASE"
    )
    
    # Add RBAC settings
    if [ "$1" = true ]; then
        helm_args+=("--set" "backend.rbac.create=true")
        print_info "Full cluster RBAC permissions will be enabled for backend"
    else
        helm_args+=("--set" "backend.rbac.create=false")
        print_info "Backend will run without cluster-wide RBAC permissions"
    fi
    
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
    
    # Add nodeSelector if specified
    if [ -n "$2" ]; then
        helm_args+=("--set" "backend.nodeSelector.kubernetes\.io/hostname=$2")
        print_info "Backend will be scheduled on node: $2"
    fi
    
    # Check if already installed
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "insustain"; then
        print_info "inSustain already installed. Upgrading..."
        $helm_cmd upgrade insustain insustain/ "${helm_args[@]}"
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

main() {
    # Parse arguments
    local ENABLE_FULL_RBAC=false
    local NODE_SELECTOR=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            --enable-full-rbac)
                ENABLE_FULL_RBAC=true
                shift
                ;;
            -n|--node)
                NODE_SELECTOR="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -y, --yes                  Auto-answer yes to prompts"
                echo "  -n, --node NODE_NAME       Schedule backend on specific node (nodeSelector)"
                echo "  --enable-full-rbac         Enable full cluster RBAC permissions for backend"
                echo "                             (allows listing pods across all namespaces)"
                echo "  -h, --help                 Show this help message"
                echo ""
                echo "Prerequisites:"
                echo "  • Backend image must be imported first using:"
                echo "    ./scripts/import-backend-image.sh"
                echo ""
                echo "Features:"
                echo "  • Installs/checks kube-prometheus-stack and Kepler"
                echo "  • Deploys inSustain via Helm"
                echo "  • Uses pre-imported images (no registry authentication needed)"
                echo ""
                echo "Examples:"
                echo "  $0"
                echo "  $0 -y"
                echo "  $0 --node intend-cluster01-master"
                echo "  $0 -y --enable-full-rbac"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    echo
    print_header "inSustain Setup Script"
    echo
    print_info "This script deploys inSustain using pre-imported images"
    echo
    echo "Prerequisites:"
    echo "  ⚠️  Backend image must be imported first:"
    echo "     ./scripts/import-backend-image.sh"
    echo
    echo "Benefits:"
    echo "  ✅ No registry authentication needed"
    echo "  ✅ Works in air-gapped environments"
    echo "  ✅ Faster deployment (no image pulls)"
    echo "  ✅ No Docker required on K8s nodes"
    echo
    print_info "This script will:"
    echo "  1. Verify backend image is imported"
    echo "  2. Check/install kube-prometheus-stack (Prometheus + Grafana)"
    echo "  3. Check/install Kepler (energy metrics)"
    echo "  4. Deploy inSustain with Helm"
    echo
    
    if [ "$AUTO_YES" = false ]; then
        read -p "Continue? (y/N): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Setup cancelled"
            exit 0
        fi
    else
        print_info "Auto-yes mode enabled, continuing..."
    fi
    
    check_prerequisites
    check_backend_image
    setup_namespace
    setup_kubernetes
    deploy_insustain "$ENABLE_FULL_RBAC" "$NODE_SELECTOR"
    show_access_info
    
    echo
    print_success "Setup complete!"
    echo
    print_info "Next steps:"
    echo "  1. Port-forward services to access them locally"
    echo "  2. Check API documentation at http://localhost:8089/docs"
    echo "  3. Explore Grafana dashboards for monitoring"
    echo "  4. Review logs if any issues: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=backend"
    echo
    print_info "To enable additional components (frontend, loadgen, etc.):"
    echo "  1. Import their images using import scripts"
    echo "  2. Upgrade deployment: helm upgrade insustain insustain/ -n insustain --set <component>.enabled=true"
    echo
}

# Run main function with all arguments
main "$@"
