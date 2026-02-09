#!/bin/bash

set -e  # Exit on error

# Configuration
REGISTRY="89.133.95.6:5001"
IMAGE_NAME="insustain/backend:latest"
FULL_IMAGE="$REGISTRY/$IMAGE_NAME"
NAMESPACE="insustain"
DEPLOYMENT_NAME="insustain-backend"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
SKIP_IMPORT=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-import)
            SKIP_IMPORT=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-import    Skip k3s import step (use registry pull)"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Backend Release Workflow${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Build backend image
echo -e "${YELLOW}[1/6] Building backend Docker image...${NC}"
cd k8s-app
if ! ./build.sh backend; then
    echo -e "${RED}Error: Docker build failed${NC}"
    echo "Check Dockerfile and dependencies in k8s-app/backend/"
    exit 1
fi
cd ..
echo -e "${GREEN}✓ Build completed${NC}"
echo ""

# Step 2: Verify .so files exist in built image
echo -e "${YELLOW}[2/6] Verifying .so files in image...${NC}"
SO_FILES=$(docker run --rm $FULL_IMAGE find /usr/local/lib -name "*.so" 2>/dev/null | wc -l)
if [ "$SO_FILES" -eq 0 ]; then
    echo -e "${RED}Warning: No .so files found in image${NC}"
    echo "This may be expected for development builds"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✓ Found $SO_FILES .so files in image${NC}"
fi
echo ""

# Step 3: Push to registry (already done by build.sh)
echo -e "${YELLOW}[3/6] Verifying image in registry...${NC}"
if docker manifest inspect $FULL_IMAGE > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Image exists in registry: $FULL_IMAGE${NC}"
else
    echo -e "${RED}Error: Image not found in registry${NC}"
    echo "The build.sh script should have pushed the image"
    exit 1
fi
echo ""

# Step 4: Import to k3s (optional)
if [ "$SKIP_IMPORT" = false ]; then
    echo -e "${YELLOW}[4/6] Importing image to k3s...${NC}"
    
    # Check if we have access to ctr
    if ! command -v ctr &> /dev/null; then
        echo -e "${RED}Error: ctr command not found${NC}"
        echo "Install containerd or use --skip-import to skip this step"
        exit 1
    fi
    
    # Pull image from registry
    echo "Pulling image from registry..."
    if ! docker pull $FULL_IMAGE; then
        echo -e "${RED}Error: Failed to pull image from registry${NC}"
        exit 1
    fi
    
    # Save image to tar
    echo "Saving image to temporary file..."
    TEMP_TAR="/tmp/backend-image-$$.tar"
    if ! docker save $FULL_IMAGE -o $TEMP_TAR; then
        echo -e "${RED}Error: Failed to save image to tar${NC}"
        exit 1
    fi
    
    # Import to k3s
    echo "Importing to k3s..."
    if sudo ctr -n k8s.io images import $TEMP_TAR; then
        echo -e "${GREEN}✓ Image imported to k3s${NC}"
        rm -f $TEMP_TAR
    else
        echo -e "${RED}Error: Failed to import image to k3s${NC}"
        echo "Check k3s node access and disk space"
        rm -f $TEMP_TAR
        exit 1
    fi
else
    echo -e "${YELLOW}[4/6] Skipping k3s import (--skip-import flag)${NC}"
fi
echo ""

# Step 5: Restart backend pods
echo -e "${YELLOW}[5/6] Restarting backend pods...${NC}"
if ! kubectl rollout restart deployment/$DEPLOYMENT_NAME -n $NAMESPACE; then
    echo -e "${RED}Error: Failed to restart deployment${NC}"
    echo "Check if deployment exists: kubectl get deployment -n $NAMESPACE"
    exit 1
fi
echo -e "${GREEN}✓ Deployment restart initiated${NC}"
echo ""

# Step 6: Verify pods are running new image
echo -e "${YELLOW}[6/6] Verifying deployment...${NC}"
echo "Waiting for rollout to complete..."
if kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=120s; then
    echo -e "${GREEN}✓ Rollout completed successfully${NC}"
    
    # Get image version from running pods
    RUNNING_IMAGE=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=backend -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null)
    if [ -n "$RUNNING_IMAGE" ]; then
        echo "Running image: $RUNNING_IMAGE"
    fi
    
    # Show pod status
    echo ""
    echo "Pod status:"
    kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=backend
else
    echo -e "${RED}Error: Rollout did not complete within timeout${NC}"
    echo ""
    echo "Check pod status:"
    kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=backend
    echo ""
    echo "Check pod logs:"
    echo "kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=backend --tail=50"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Release completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "  - Test the API: kubectl port-forward -n $NAMESPACE svc/$DEPLOYMENT_NAME 8089:8089"
echo "  - View logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=backend -f"
echo "  - Check metrics: http://localhost:8089/metrics"
