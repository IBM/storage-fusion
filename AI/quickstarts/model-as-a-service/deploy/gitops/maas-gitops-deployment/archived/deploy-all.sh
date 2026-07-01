#!/bin/bash
# deploy-all.sh - Deploy complete MaaS platform via ArgoCD GitOps
# Usage: ./deploy-all.sh [git-repo-url]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_REPO_URL="${1:-https://github.com/your-org/Fusion-AI.git}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== MaaS Platform GitOps Deployment ===${NC}"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: OpenShift CLI (oc) is not installed${NC}"
    exit 1
fi

# Check if argocd CLI is installed
if ! command -v argocd &> /dev/null; then
    echo -e "${YELLOW}Warning: ArgoCD CLI is not installed${NC}"
    echo "You can still deploy, but won't be able to use 'argocd' commands"
fi

# Check if logged into cluster
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift cluster${NC}"
    echo "Please run: oc login <cluster-url>"
    exit 1
fi

# Check if OpenShift GitOps is installed
if ! oc get namespace openshift-gitops &> /dev/null; then
    echo -e "${RED}Error: openshift-gitops namespace not found${NC}"
    echo "Please install OpenShift GitOps operator first"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Update Git repository URL in application files
echo -e "${BLUE}Updating Git repository URL to: ${GIT_REPO_URL}${NC}"
echo ""

# Create temporary directory for modified files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy files to temp directory
cp -r "$SCRIPT_DIR/argocd" "$TEMP_DIR/"

# Update repoURL in all application files
find "$TEMP_DIR/argocd" -name "*.yaml" -type f -exec sed -i.bak \
    "s|repoURL: https://github.com/your-org/Fusion-AI.git|repoURL: ${GIT_REPO_URL}|g" {} \;

# Remove backup files
find "$TEMP_DIR/argocd" -name "*.bak" -type f -delete

echo -e "${GREEN}=== Deploying ArgoCD Resources ===${NC}"
echo ""

# Deploy AppProject first
echo "1. Creating ArgoCD AppProject..."
oc apply -f "$TEMP_DIR/argocd/appproject.yaml"
echo -e "${GREEN}✓ AppProject created${NC}"
echo ""

# Wait a moment for project to be created
sleep 2

# Deploy applications in order
echo "2. Deploying maas-operators application (Wave 0)..."
oc apply -f "$TEMP_DIR/argocd/01-maas-operators-application.yaml"
echo -e "${GREEN}✓ maas-operators application created${NC}"
echo ""

echo "3. Deploying maas-platform application (Wave 10)..."
oc apply -f "$TEMP_DIR/argocd/02-maas-platform-application.yaml"
echo -e "${GREEN}✓ maas-platform application created${NC}"
echo ""

echo "4. Deploying maas-runtime application (Wave 20)..."
oc apply -f "$TEMP_DIR/argocd/03-maas-runtime-application.yaml"
echo -e "${GREEN}✓ maas-runtime application created${NC}"
echo ""

echo -e "${GREEN}=== Deployment Summary ===${NC}"
echo ""
echo "ArgoCD applications have been created and will sync automatically."
echo ""
echo "Monitor deployment progress:"
echo ""

if command -v argocd &> /dev/null; then
    echo "  # Using ArgoCD CLI:"
    echo "  argocd app list | grep maas"
    echo "  argocd app get maas-operators"
    echo "  argocd app get maas-platform"
    echo "  argocd app get maas-runtime"
    echo ""
fi

echo "  # Using kubectl/oc:"
echo "  oc get applications -n openshift-gitops | grep maas"
echo "  oc describe application maas-operators -n openshift-gitops"
echo ""
echo "  # Watch operator installation:"
echo "  watch oc get csv -A"
echo ""
echo "  # Check DataScienceCluster:"
echo "  oc get datasciencecluster default-dsc"
echo ""
echo "  # Check runtime resources:"
echo "  oc get all -n maas-models"
echo ""

# Get ArgoCD URL
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
if [ "$ARGOCD_ROUTE" != "N/A" ]; then
    echo "OpenShift GitOps UI: https://$ARGOCD_ROUTE"
    echo ""
fi

echo -e "${YELLOW}Note: The deployment will proceed in phases:${NC}"
echo "  Wave 0  (5-10 min): Operator subscriptions"
echo "  Wave 10 (10-15 min): DataScienceCluster and operator instances"
echo "  Wave 20 (5-10 min): Runtime resources"
echo ""
echo "Total estimated time: 20-35 minutes"
echo ""

echo -e "${GREEN}Deployment initiated successfully!${NC}"
echo ""
echo "For detailed documentation, see:"
echo "  $SCRIPT_DIR/README.md"
