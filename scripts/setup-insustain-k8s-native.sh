#!/bin/bash
set -e

# inSustain Setup Script - Kubernetes Native Approach
# This script uses Kubernetes imagePullSecrets instead of pre-importing images
# This is the recommended approach for production Kubernetes clusters

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
DOCKER_REGISTRY_AUTH="https://89.133.95.6:5001"  # For authentication
DOCKER_REGISTRY="89.133.95.6:5001"               # For image references
DOCKER_USER="intend"
NAMESPACE="insustain"
SECRET_NAME="insustain-registry-secret"

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

setup_registry_certificate() {
    print_header "Setting Up Registry Certificate in Kubernetes"
    
    local cert_file="certs/docker_ca.crt"
    
    if [ ! -f "$cert_file" ]; then
        print_error "Certificate file not found: $cert_file"
        exit 1
    fi
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_info "Creating namespace $NAMESPACE..."
        kubectl create namespace "$NAMESPACE"
    fi
    
    # Create ConfigMap with CA certificate
    print_info "Creating certificate ConfigMap..."
    kubectl create configmap registry-ca-cert \
        --from-file=ca.crt="$cert_file" \
        --namespace "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Certificate ConfigMap created"
}

create_image_pull_secret() {
    print_header "Creating Kubernetes Image Pull Secret"
    
    # Check for password in order: argument, environment variable, prompt
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
    
    # Delete existing secret if present
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || true
    
    # Create docker-registry secret
    print_info "Creating image pull secret..."
    kubectl create secret docker-registry "$SECRET_NAME" \
        --docker-server="$DOCKER_REGISTRY_AUTH" \
        --docker-username="$DOCKER_USER" \
        --docker-password="$DOCKER_PASSWORD" \
        --namespace "$NAMESPACE"
    
    if [ $? -eq 0 ]; then
        print_success "Image pull secret created"
    else
        print_error "Failed to create image pull secret"
        exit 1
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

deploy_insustain() {
    print_header "Deploying inSustain"
    
    # Update helm dependencies
    print_info "Updating Helm dependencies..."
    helm dependency update insustain/
    
    # Build helm install/upgrade command
    local helm_cmd="helm"
    local helm_args=(
        "--namespace" "$NAMESPACE"
        "--set" "backend.image.pullPolicy=IfNotPresent"
        "--set" "backend.imagePullSecrets[0].name=$SECRET_NAME"
        "--set" "global.image.repository=$DOCKER_REGISTRY"
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
    local PASSWORD_ARG=""
    local ENABLE_FULL_RBAC=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--password)
                PASSWORD_ARG="$2"
                shift 2
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            --enable-full-rbac)
                ENABLE_FULL_RBAC=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -p, --password PASSWORD    Docker registry password"
                echo "  -y, --yes                  Auto-answer yes to prompts (includes image import)"
                echo "  --enable-full-rbac         Enable full cluster RBAC permissions for backend"
                echo "                             (allows listing pods across all namespaces)"
                echo "  -h, --help                 Show this help message"
                echo ""
                echo "Features:"
                echo "  • Creates Kubernetes imagePullSecret for registry authentication"
                echo "  • Optionally imports backend image directly to K3s (bypasses registry issues)"
                echo "  • Installs/checks kube-prometheus-stack and Kepler"
                echo "  • Deploys inSustain via Helm"
                echo ""
                echo "Examples:"
                echo "  $0 --password mypassword"
                echo "  $0 -p mypassword -y"
                echo "  $0 -p mypassword --enable-full-rbac"
                echo "  DOCKER_PASSWORD=mypassword $0"
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
    print_header "inSustain Setup Script (Kubernetes Native)"
    echo
    print_info "This script uses Kubernetes imagePullSecrets (recommended approach)"
    print_info "With optional direct image import to K3s (bypasses registry issues)"
    echo
    echo "Benefits:"
    echo "  ✅ No Docker required on K8s nodes"
    echo "  ✅ Optional direct image import (avoids registry HTTP/HTTPS issues)"
    echo "  ✅ Works with multi-node clusters"
    echo "  ✅ Kubernetes handles image distribution"
    echo "  ✅ No server restarts needed"
    echo
    print_info "This script will:"
    echo "  1. Check/install kube-prometheus-stack (Prometheus + Grafana + more)"
    echo "  2. Check/install Kepler (energy metrics)"
    echo "  3. Create Kubernetes imagePullSecret for registry access"
    echo "  4. Optionally import backend image directly to K3s"
    echo "  5. Deploy inSustain with Helm"
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
    setup_registry_certificate
    create_image_pull_secret "$PASSWORD_ARG"
      
    setup_kubernetes
    deploy_insustain "$ENABLE_FULL_RBAC"
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
}

# Run main function with all arguments
main "$@"
