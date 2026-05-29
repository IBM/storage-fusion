#!/bin/bash
# install-runtime.sh - Deploy MaaS Runtime Platform
# Usage: ./install-runtime.sh [values-file]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHARTS_DIR="$PROJECT_ROOT/charts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values file
VALUES_FILE="${1:-$PROJECT_ROOT/examples/Fusion-Agentic-Assistance-Platform/values.yaml}"
OPERATORS_VALUES_FILE="${OPERATORS_VALUES_FILE:-$VALUES_FILE}"
PLATFORM_VALUES_FILE="${PLATFORM_VALUES_FILE:-$VALUES_FILE}"
RUNTIME_VALUES_FILE="${RUNTIME_VALUES_FILE:-$VALUES_FILE}"

echo -e "${GREEN}=== MaaS Runtime Installation ===${NC}"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: OpenShift CLI (oc) is not installed${NC}"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: Helm is not installed${NC}"
    exit 1
fi

# Check if logged into cluster
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift cluster${NC}"
    echo "Please run: oc login <cluster-url>"
    exit 1
fi

# Check if user is cluster admin
if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
    echo -e "${YELLOW}Warning: You may not have cluster-admin privileges${NC}"
    echo "Some operations may fail. Continue? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if values files exist
for file in "$VALUES_FILE" "$OPERATORS_VALUES_FILE" "$PLATFORM_VALUES_FILE" "$RUNTIME_VALUES_FILE"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Values file not found: $file${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Check for default StorageClass
echo "Checking for default StorageClass..."
if ! oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' | grep -q .; then
    echo -e "${RED}Error: No default StorageClass found${NC}"
    echo "Please configure a default StorageClass before proceeding"
    exit 1
fi
echo -e "${GREEN}✓ Default StorageClass found${NC}"
echo ""

# Prompt for passwords if using Keycloak
if grep -A 5 "keycloak:" "$RUNTIME_VALUES_FILE" | grep -q "enabled: true"; then
    echo "Keycloak is enabled. Please provide passwords:"
    echo ""
    
    if [ -z "$ADMIN_PASSWORD" ]; then
        read -rsp "Enter admin password: " ADMIN_PASSWORD
        echo ""
    fi
    
    if [ -z "$USER_PASSWORD" ]; then
        read -rsp "Enter user password: " USER_PASSWORD
        echo ""
    fi
    
    KEYCLOAK_ARGS="--set authentication.keycloak.realm.admin.password=$ADMIN_PASSWORD --set authentication.keycloak.realm.user.password=$USER_PASSWORD"
else
    KEYCLOAK_ARGS=""
fi

echo ""
echo -e "${GREEN}=== Phase 1: Installing Dependency Operator Subscriptions ===${NC}"
echo "Values file: $OPERATORS_VALUES_FILE"
echo "Chart: $CHARTS_DIR/maas-operators"
echo ""

helm upgrade --install maas-operators "$CHARTS_DIR/maas-operators" \
    -f "$OPERATORS_VALUES_FILE" \
    --timeout 20m \
    --wait

echo ""
echo -e "${GREEN}✓ Dependency operator subscriptions installed${NC}"
echo ""

# Wait for OpenShift AI operator to be ready
echo "Waiting for OpenShift AI operator to be ready..."
if oc wait --for=condition=Available deployment/rhods-operator -n redhat-ods-operator --timeout=10m 2>/dev/null; then
    echo -e "${GREEN}✓ OpenShift AI operator ready${NC}"
else
    echo -e "${YELLOW}⚠ OpenShift AI operator deployment not found, checking CSV...${NC}"
    sleep 30
fi

# Wait for DataScienceCluster CRD to be available
echo "Waiting for DataScienceCluster CRD to be available..."
for i in {1..60}; do
    if oc get crd datascienceclusters.datasciencecluster.opendatahub.io &>/dev/null; then
        echo -e "${GREEN}✓ DataScienceCluster CRD available${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}✗ DataScienceCluster CRD not available after 5 minutes${NC}"
        exit 1
    fi
    sleep 5
done

# Wait for Kuadrant CRD to be available
echo "Waiting for Kuadrant CRD to be available..."
for i in {1..60}; do
    if oc get crd kuadrants.kuadrant.io &>/dev/null; then
        echo -e "${GREEN}✓ Kuadrant CRD available${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${YELLOW}⚠ Kuadrant CRD not available after 5 minutes${NC}"
        break
    fi
    sleep 5
done

# Wait for LeaderWorkerSet CRD to be available
echo "Waiting for LeaderWorkerSetOperator CRD to be available..."
for i in {1..60}; do
    if oc get crd leaderworkersetoperators.operator.openshift.io &>/dev/null; then
        echo -e "${GREEN}✓ LeaderWorkerSetOperator CRD available${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${YELLOW}⚠ LeaderWorkerSetOperator CRD not available after 5 minutes${NC}"
        break
    fi
    sleep 5
done

echo ""
echo -e "${GREEN}=== Phase 2: Creating DataScienceCluster and Operator Instances ===${NC}"
echo "Values file: $PLATFORM_VALUES_FILE"
echo "Chart: $CHARTS_DIR/maas-platform"
echo ""

helm upgrade --install maas-platform "$CHARTS_DIR/maas-platform" \
    -f "$PLATFORM_VALUES_FILE" \
    --timeout 20m \
    --wait

echo ""
echo "Waiting for DataScienceCluster to be ready..."
if oc wait --for=condition=Ready datasciencecluster default-dsc --timeout=15m 2>/dev/null; then
    echo -e "${GREEN}✓ DataScienceCluster ready${NC}"
else
    echo -e "${RED}✗ DataScienceCluster not ready${NC}"
    echo "Please check the DataScienceCluster status and try again"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Phase 3: Installing MaaS Runtime Resources ===${NC}"
echo "Values file: $RUNTIME_VALUES_FILE"
echo "Chart: $CHARTS_DIR/maas-runtime"
echo ""

# Install or upgrade the main runtime resources
echo "Installing MaaS runtime resources (gateway, model registry, workbench storage, etc.)..."
helm upgrade --install maas-runtime "$CHARTS_DIR/maas-runtime" \
    -f "$RUNTIME_VALUES_FILE" \
    $KEYCLOAK_ARGS \
    --timeout 10m \
    --force

echo ""
echo -e "${GREEN}✓ MaaS Runtime resources installation complete${NC}"
echo ""

# Wait for additional components
echo "Waiting for additional components to be ready..."
echo ""

# Wait for Kuadrant
echo "Waiting for Kuadrant..."
if oc wait --for=condition=Ready kuadrant kuadrant -n kuadrant-system --timeout=5m 2>/dev/null; then
    echo -e "${GREEN}✓ Kuadrant ready${NC}"
else
    echo -e "${YELLOW}⚠ Kuadrant not ready yet${NC}"
fi

# Wait for Keycloak if enabled
if [ -n "$KEYCLOAK_ARGS" ]; then
    echo "Waiting for Keycloak..."
    if oc wait --for=condition=Ready keycloak keycloak -n keycloak --timeout=10m 2>/dev/null; then
        echo -e "${GREEN}✓ Keycloak ready${NC}"
    else
        echo -e "${YELLOW}⚠ Keycloak not ready yet${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Installation Summary ===${NC}"
echo ""
echo "MaaS Runtime has been deployed!"
echo ""
echo "Next steps:"
echo "1. Deploy models using: ./deploy-model.sh <model-values-file>"
echo "2. Check status: oc get all -n maas-models"
echo "3. View logs: oc logs -n maas-models -l app.kubernetes.io/component=model-service"
echo ""

# Display useful URLs
echo "Useful URLs:"
CONSOLE_URL=$(oc whoami --show-console 2>/dev/null || echo "N/A")
echo "  OpenShift Console: $CONSOLE_URL"

if [ -n "$KEYCLOAK_ARGS" ]; then
    KEYCLOAK_URL=$(oc get route -n keycloak keycloak -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
    echo "  Keycloak: https://$KEYCLOAK_URL"
fi

GRAFANA_URL=$(oc get route -n grafana grafana-route -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
if [ "$GRAFANA_URL" != "N/A" ]; then
    echo "  Grafana: https://$GRAFANA_URL"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"

