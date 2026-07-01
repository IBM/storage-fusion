#!/bin/bash

# Build reconciler image using OpenShift BuildConfig

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="${NAMESPACE:-model-registry-gitops}"
IMAGE_NAME="model-reconciler"
GIT_REPO="${GIT_REPO:-https://github.com/IBM/storage-fusion}"
GIT_REF="${GIT_REF:-master}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Build Reconciler with OpenShift${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Not logged into OpenShift. Run 'oc login' first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Logged in as: $(oc whoami)"

# Check if namespace exists
if ! oc get namespace $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace $NAMESPACE not found. Creating...${NC}"
    oc create namespace $NAMESPACE
fi
echo -e "${GREEN}✓${NC} Namespace: $NAMESPACE"

echo ""
echo -e "${BLUE}Step 1: Creating ImageStream...${NC}"

cat <<EOF | oc apply -f -
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: ${IMAGE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: model-registry-gitops
    component: reconciler
spec:
  lookupPolicy:
    local: true
EOF

echo -e "${GREEN}✓${NC} ImageStream created"

echo ""
echo -e "${BLUE}Step 2: Creating BuildConfig...${NC}"

# Check if git-credentials secret exists for private repos
GIT_SECRET=""
if oc get secret git-credentials -n $NAMESPACE &> /dev/null; then
    echo -e "${GREEN}✓${NC} Found git-credentials secret (will use for private repo)"
    GIT_SECRET="git-credentials"
fi

cat <<EOF | oc apply -f -
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: ${IMAGE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: model-registry-gitops
    component: reconciler
spec:
  output:
    to:
      kind: ImageStreamTag
      name: ${IMAGE_NAME}:latest
  
  source:
    type: Git
    git:
      uri: ${GIT_REPO}
      ref: ${GIT_REF}
    contextDir: gitops/reconciler
$(if [ ! -z "$GIT_SECRET" ]; then
cat <<GITSECRET
    sourceSecret:
      name: ${GIT_SECRET}
GITSECRET
fi)
  
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  
  triggers:
    - type: ConfigChange
    - type: ImageChange
EOF

echo -e "${GREEN}✓${NC} BuildConfig created"

echo ""
echo -e "${BLUE}Step 3: Starting build...${NC}"

# Start the build
BUILD_NAME=$(oc start-build ${IMAGE_NAME} -n $NAMESPACE --follow 2>&1 | tee /dev/tty | grep "build.build.openshift.io" | awk '{print $1}' | sed 's/"//g' || echo "${IMAGE_NAME}-1")

if [ -z "$BUILD_NAME" ]; then
    BUILD_NAME="${IMAGE_NAME}-1"
fi

echo ""
echo -e "${BLUE}Step 4: Waiting for build to complete...${NC}"

# Wait for build to complete
oc wait --for=condition=Complete build/${BUILD_NAME} -n $NAMESPACE --timeout=600s 2>/dev/null || {
    echo -e "${YELLOW}⚠ Build may still be running. Check status with:${NC}"
    echo -e "  ${YELLOW}oc get build ${BUILD_NAME} -n $NAMESPACE${NC}"
    echo -e "  ${YELLOW}oc logs -f build/${BUILD_NAME} -n $NAMESPACE${NC}"
}

# Check build status
BUILD_STATUS=$(oc get build ${BUILD_NAME} -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [ "$BUILD_STATUS" = "Complete" ]; then
    echo -e "${GREEN}✓${NC} Build completed successfully"
    
    # Get image reference
    IMAGE_REF=$(oc get imagestream ${IMAGE_NAME} -n $NAMESPACE -o jsonpath='{.status.dockerImageRepository}' 2>/dev/null)
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ Build Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Image:${NC} ${IMAGE_REF}:latest"
    echo ""
    echo -e "${BLUE}Image reference for deployment:${NC}"
    echo -e "  ${YELLOW}image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/${IMAGE_NAME}:latest${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Update deployment to use the new image:"
    echo -e "     ${YELLOW}oc set image deployment/model-reconciler reconciler=image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/${IMAGE_NAME}:latest -n ${NAMESPACE}${NC}"
    echo ""
    echo "  2. Or deploy with the sync script:"
    echo -e "     ${YELLOW}./scripts/sync-models-to-registry.sh${NC}"
    echo ""
elif [ "$BUILD_STATUS" = "Failed" ]; then
    echo -e "${RED}✗ Build failed${NC}"
    echo ""
    echo "Check build logs:"
    echo -e "  ${YELLOW}oc logs build/${BUILD_NAME} -n $NAMESPACE${NC}"
    exit 1
else
    echo -e "${YELLOW}⚠ Build status: $BUILD_STATUS${NC}"
    echo ""
    echo "Monitor build progress:"
    echo -e "  ${YELLOW}oc logs -f build/${BUILD_NAME} -n $NAMESPACE${NC}"
fi

echo ""

