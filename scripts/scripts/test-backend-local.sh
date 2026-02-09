#!/bin/bash

set -e  # Exit on error

# Configuration
REGISTRY="89.133.95.6:5001"
IMAGE_NAME="insustain/backend:latest"
FULL_IMAGE="$REGISTRY/$IMAGE_NAME"
CONTAINER_NAME="backend-test"
TEST_PORT="8089"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Backend Docker Image Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Check if image exists
echo -e "${YELLOW}[1/5] Checking if image exists...${NC}"
if docker image inspect $FULL_IMAGE > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Image found: $FULL_IMAGE${NC}"
else
    echo -e "${RED}Error: Image not found${NC}"
    echo "Build the image first: cd k8s-app && ./build.sh backend"
    exit 1
fi
echo ""

# Step 2: Stop and remove existing test container if it exists
echo -e "${YELLOW}[2/5] Cleaning up existing test container...${NC}"
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Removing existing container: $CONTAINER_NAME"
    docker rm -f $CONTAINER_NAME > /dev/null 2>&1
    echo -e "${GREEN}✓ Cleanup completed${NC}"
else
    echo "No existing container to clean up"
fi
echo ""

# Step 3: Start container with minimal environment
echo -e "${YELLOW}[3/5] Starting container...${NC}"
echo "Container name: $CONTAINER_NAME"
echo "Port mapping: $TEST_PORT:8089"
echo ""

# Start container in detached mode with environment variables
docker run -d \
    --name $CONTAINER_NAME \
    -p $TEST_PORT:8089 \
    -e MONGO_URL="localhost:27017" \
    -e MONGO_DB="monitoring" \
    -e MONGO_USERNAME="admin" \
    -e MONGO_PASS="secret" \
    -e MLFLOW_URL="http://localhost:5000" \
    -e PROMETHEUS_URL="http://localhost:9090" \
    -e NAMESPACE_NAME="insustain" \
    -e LOG_LEVEL="info" \
    -e DEBUG_MODE="false" \
    $FULL_IMAGE > /dev/null

echo -e "${GREEN}✓ Container started${NC}"
echo ""

# Step 4: Wait for startup and check logs
echo -e "${YELLOW}[4/5] Checking startup logs (10 seconds)...${NC}"
echo "Waiting for application to start..."
sleep 10

echo ""
echo "=== Container Logs ==="
docker logs $CONTAINER_NAME 2>&1 | tail -50
echo "======================"
echo ""

# Step 5: Check if uvicorn started successfully
echo -e "${YELLOW}[5/5] Verifying application status...${NC}"

# Check if container is still running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}✗ Container stopped unexpectedly${NC}"
    echo ""
    echo "Full logs:"
    docker logs $CONTAINER_NAME 2>&1
    echo ""
    echo -e "${RED}Test FAILED${NC}"
    exit 1
fi

# Check for error patterns in logs
if docker logs $CONTAINER_NAME 2>&1 | grep -q "ModuleNotFoundError\|ImportError\|PydanticUserError\|Traceback"; then
    echo -e "${RED}✗ Python errors detected in logs${NC}"
    echo ""
    echo "Error details:"
    docker logs $CONTAINER_NAME 2>&1 | grep -A 10 "Error\|Traceback"
    echo ""
    echo -e "${YELLOW}Stopping test container...${NC}"
    docker stop $CONTAINER_NAME > /dev/null 2>&1
    echo -e "${RED}Test FAILED${NC}"
    exit 1
fi

# Check if uvicorn is running
if docker logs $CONTAINER_NAME 2>&1 | grep -q "Uvicorn running on\|Application startup complete"; then
    echo -e "${GREEN}✓ Uvicorn started successfully${NC}"
    
    # Try to access health endpoint
    echo ""
    echo "Testing API endpoint..."
    sleep 2
    
    if curl -s -f http://localhost:$TEST_PORT/docs > /dev/null 2>&1; then
        echo -e "${GREEN}✓ API is responding (docs endpoint accessible)${NC}"
    else
        echo -e "${YELLOW}⚠ API docs endpoint not accessible (may be normal if not implemented)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Uvicorn startup message not found in logs${NC}"
    echo "This may indicate the application is still starting or failed to start"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Test completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Container is running. You can:"
echo "  - View logs: docker logs -f $CONTAINER_NAME"
echo "  - Access API: http://localhost:$TEST_PORT"
echo "  - Access docs: http://localhost:$TEST_PORT/docs"
echo "  - Stop container: docker stop $CONTAINER_NAME"
echo "  - Remove container: docker rm -f $CONTAINER_NAME"
echo ""
echo -e "${BLUE}Press Ctrl+C to stop watching logs, or wait...${NC}"
echo ""

# Follow logs for a bit
timeout 5 docker logs -f $CONTAINER_NAME 2>&1 || true

echo ""
echo -e "${YELLOW}Tip: Leave container running to test API, or stop it with:${NC}"
echo "  docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
