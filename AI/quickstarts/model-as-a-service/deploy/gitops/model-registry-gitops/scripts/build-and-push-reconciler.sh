#!/bin/bash

# Build and push the model reconciler container image

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REGISTRY="${REGISTRY:-quay.io}"
ORG="${ORG:-your-org}"
IMAGE_NAME="model-reconciler"
TAG="${TAG:-latest}"
FULL_IMAGE="${REGISTRY}/${ORG}/${IMAGE_NAME}:${TAG}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Building Model Reconciler Image${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Image:${NC} ${FULL_IMAGE}"
echo ""

# Check if podman or docker is available
if command -v podman &> /dev/null; then
    CONTAINER_CLI="podman"
elif command -v docker &> /dev/null; then
    CONTAINER_CLI="docker"
else
    echo -e "${RED}✗ Neither podman nor docker found${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Using ${CONTAINER_CLI}"

# Navigate to reconciler directory
cd "$(dirname "$0")/../gitops/reconciler"

# Build image
echo ""
echo -e "${BLUE}Building image...${NC}"
${CONTAINER_CLI} build -t ${FULL_IMAGE} .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Image built successfully"
else
    echo -e "${RED}✗${NC} Build failed"
    exit 1
fi

# Push image
echo ""
echo -e "${BLUE}Pushing image to registry...${NC}"
${CONTAINER_CLI} push ${FULL_IMAGE}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Image pushed successfully"
else
    echo -e "${RED}✗${NC} Push failed"
    exit 1
fi

# Update deployment manifest
echo ""
echo -e "${BLUE}Updating deployment manifest...${NC}"
MANIFEST_FILE="../manifests/03-deployment.yaml"

if [ -f "${MANIFEST_FILE}" ]; then
    # Update image in deployment
    sed -i.bak "s|image:.*model-reconciler.*|image: ${FULL_IMAGE}|g" ${MANIFEST_FILE}
    rm -f ${MANIFEST_FILE}.bak
    echo -e "${GREEN}✓${NC} Updated ${MANIFEST_FILE}"
else
    echo -e "${YELLOW}⚠${NC} Deployment manifest not found at ${MANIFEST_FILE}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Build and Push Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Image:${NC} ${FULL_IMAGE}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Commit the updated deployment manifest"
echo "  2. Push to Git repository"
echo "  3. ArgoCD will automatically sync the new image"
echo ""
echo "Or manually update the deployment:"
echo -e "  ${YELLOW}oc set image deployment/model-reconciler reconciler=${FULL_IMAGE} -n model-registry-gitops${NC}"
echo ""

