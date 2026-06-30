#!/bin/bash

# Setup required secrets for Model Registry GitOps

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="${NAMESPACE:-rhoai-model-registries}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Model Registry GitOps - Setup Secrets${NC}"
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
echo -e "${BLUE}Step 1: S3/ODF Credentials${NC}"
echo ""

# Try to auto-detect S3 configuration
echo "Attempting to auto-detect S3 configuration..."

# Get S3 endpoint from route
S3_ENDPOINT=$(oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ ! -z "$S3_ENDPOINT" ]; then
    S3_ENDPOINT="https://${S3_ENDPOINT}"
    echo -e "${GREEN}✓${NC} Found S3 endpoint: $S3_ENDPOINT"
else
    echo -e "${YELLOW}⚠${NC} Could not auto-detect S3 endpoint"
    read -p "Enter S3 endpoint URL: " S3_ENDPOINT
fi

# Try to find existing OBC
OBC_LIST=$(oc get objectbucketclaim -n $NAMESPACE -o name 2>/dev/null || echo "")

if [ ! -z "$OBC_LIST" ]; then
    OBC_NAME=$(echo "$OBC_LIST" | head -1 | sed 's|objectbucketclaim/||')
    echo -e "${GREEN}✓${NC} Found ObjectBucketClaim: $OBC_NAME"
    
    # Get credentials from OBC secret
    AWS_ACCESS_KEY=$(oc get secret ${OBC_NAME} -n $NAMESPACE -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    AWS_SECRET_KEY=$(oc get secret ${OBC_NAME} -n $NAMESPACE -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    AWS_BUCKET=$(oc get configmap ${OBC_NAME} -n $NAMESPACE -o jsonpath='{.data.BUCKET_NAME}' 2>/dev/null || echo "")
    
    if [ ! -z "$AWS_ACCESS_KEY" ] && [ ! -z "$AWS_SECRET_KEY" ] && [ ! -z "$AWS_BUCKET" ]; then
        echo -e "${GREEN}✓${NC} Retrieved credentials from OBC"
        echo -e "${GREEN}✓${NC} Bucket: $AWS_BUCKET"
    else
        echo -e "${YELLOW}⚠${NC} Could not retrieve all credentials from OBC"
        AWS_ACCESS_KEY=""
        AWS_SECRET_KEY=""
        AWS_BUCKET=""
    fi
else
    echo -e "${YELLOW}⚠${NC} No ObjectBucketClaim found"
fi

# Prompt for missing values
if [ -z "$AWS_ACCESS_KEY" ]; then
    read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY
fi

if [ -z "$AWS_SECRET_KEY" ]; then
    read -sp "Enter AWS Secret Access Key: " AWS_SECRET_KEY
    echo ""
fi

if [ -z "$AWS_BUCKET" ]; then
    read -p "Enter S3 Bucket Name: " AWS_BUCKET
fi

# Create or update S3 credentials secret
echo ""
echo "Creating S3 credentials secret..."

oc create secret generic model-registry-artifacts \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_KEY}" \
  --from-literal=AWS_S3_ENDPOINT="${S3_ENDPOINT}" \
  --from-literal=AWS_S3_BUCKET="${AWS_BUCKET}" \
  -n $NAMESPACE \
  --dry-run=client -o yaml | oc apply -f -

echo -e "${GREEN}✓${NC} S3 credentials secret created/updated"

echo ""
echo -e "${BLUE}Step 2: Hugging Face Token (Optional)${NC}"
echo ""
echo "A Hugging Face token is required for gated models (Llama, Gemma, Mistral, etc.)"
echo "Get your token from: https://huggingface.co/settings/tokens"
echo ""

read -p "Do you want to configure a Hugging Face token? (y/N): " CONFIGURE_HF

if [[ "$CONFIGURE_HF" =~ ^[Yy]$ ]]; then
    read -sp "Enter Hugging Face token (hf_...): " HF_TOKEN
    echo ""
    
    if [ ! -z "$HF_TOKEN" ]; then
        oc create secret generic huggingface-token \
          --from-literal=token="${HF_TOKEN}" \
          -n $NAMESPACE \
          --dry-run=client -o yaml | oc apply -f -
        
        echo -e "${GREEN}✓${NC} Hugging Face token secret created/updated"
    else
        echo -e "${YELLOW}⚠${NC} No token provided, skipping"
    fi
else
    echo -e "${BLUE}ℹ${NC} Skipping Hugging Face token configuration"
    echo "   You can add it later with:"
    echo -e "   ${YELLOW}oc create secret generic huggingface-token --from-literal=token='hf_...' -n $NAMESPACE${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Secrets Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Created secrets in namespace: ${NC}$NAMESPACE"
echo ""
echo "Secrets created:"
echo "  • model-registry-artifacts (S3 credentials)"
if [[ "$CONFIGURE_HF" =~ ^[Yy]$ ]] && [ ! -z "$HF_TOKEN" ]; then
    echo "  • huggingface-token (HF API token)"
fi
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Build and push the reconciler image:"
echo -e "     ${YELLOW}./scripts/build-and-push-reconciler.sh${NC}"
echo ""
echo "  2. Deploy the GitOps infrastructure:"
echo -e "     ${YELLOW}oc apply -k gitops/manifests/${NC}"
echo ""
echo "  3. Configure ArgoCD:"
echo -e "     ${YELLOW}oc apply -f gitops/argocd/application.yaml${NC}"
echo ""

