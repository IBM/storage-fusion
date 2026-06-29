#!/bin/bash
# Fusion Developer Hub - RHOAI Connector Setup Script
# This script helps set up the RHOAI connector by creating the required secret

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="${NAMESPACE:-fusion-dev-hub}"
SECRET_NAME="rhdh-rhoai-connector-token"
RHOAI_NAMESPACE="redhat-ods-applications"
SA_NAME="rhdh-connector"
TOKEN_DURATION="8760h"  # 1 year

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup RHOAI connector for Fusion Developer Hub by creating the required secret.

OPTIONS:
    -n, --namespace NAME        Developer Hub namespace (default: fusion-dev-hub)
    -r, --rhoai-ns NAME        RHOAI namespace (default: redhat-ods-applications)
    -s, --sa-name NAME         Service account name (default: rhdh-connector)
    -t, --token TOKEN          Use existing token instead of creating new one
    -d, --duration DURATION    Token duration (default: 8760h = 1 year)
    -h, --help                 Show this help message

EXAMPLES:
    # Setup with defaults
    $0

    # Setup in custom namespace
    $0 -n my-namespace

    # Use existing token
    $0 -t "eyJhbGciOiJSUzI1NiIsImtpZCI6..."

    # Create token with custom duration
    $0 -d 4380h  # 6 months

EOF
    exit 0
}

# Parse arguments
EXISTING_TOKEN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--rhoai-ns)
            RHOAI_NAMESPACE="$2"
            shift 2
            ;;
        -s|--sa-name)
            SA_NAME="$2"
            shift 2
            ;;
        -t|--token)
            EXISTING_TOKEN="$2"
            shift 2
            ;;
        -d|--duration)
            TOKEN_DURATION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Start setup
print_header "RHOAI Connector Setup"
echo "Developer Hub Namespace: $NAMESPACE"
echo "RHOAI Namespace: $RHOAI_NAMESPACE"
echo "Service Account: $SA_NAME"
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

if ! command -v oc &> /dev/null; then
    print_error "oc CLI is not installed"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    print_error "Not connected to OpenShift cluster"
    exit 1
fi

print_success "Connected to cluster as: $(oc whoami)"

# Check if Developer Hub namespace exists
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    print_error "Namespace '$NAMESPACE' does not exist"
    echo ""
    print_info "Create it with: oc create namespace $NAMESPACE"
    exit 1
fi

print_success "Developer Hub namespace exists"

# Check if RHOAI is installed
if ! oc get namespace "$RHOAI_NAMESPACE" &> /dev/null; then
    print_warning "RHOAI namespace '$RHOAI_NAMESPACE' not found"
    print_info "Make sure Red Hat OpenShift AI is installed"
    echo ""
    read -p "Continue anyway? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        echo "Aborted."
        exit 1
    fi
else
    print_success "RHOAI namespace exists"
fi

# Get or create token
if [[ -n "$EXISTING_TOKEN" ]]; then
    print_info "Using provided token"
    TOKEN="$EXISTING_TOKEN"
else
    print_header "Creating Service Account and Token"
    
    # Check if service account exists
    if oc get sa "$SA_NAME" -n "$RHOAI_NAMESPACE" &> /dev/null; then
        print_info "Service account '$SA_NAME' already exists"
    else
        print_info "Creating service account '$SA_NAME' in namespace '$RHOAI_NAMESPACE'..."
        if oc create serviceaccount "$SA_NAME" -n "$RHOAI_NAMESPACE"; then
            print_success "Service account created"
        else
            print_error "Failed to create service account"
            exit 1
        fi
    fi
    
    # Create token
    print_info "Creating token with duration: $TOKEN_DURATION..."
    TOKEN=$(oc create token "$SA_NAME" -n "$RHOAI_NAMESPACE" --duration="$TOKEN_DURATION" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create token"
        echo "$TOKEN"
        exit 1
    fi
    
    print_success "Token created successfully"
fi

# Create secret in Developer Hub namespace
print_header "Creating Secret"

# Check if secret already exists
if oc get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    print_warning "Secret '$SECRET_NAME' already exists"
    echo ""
    read -p "Delete and recreate? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        print_info "Deleting existing secret..."
        oc delete secret "$SECRET_NAME" -n "$NAMESPACE"
    else
        print_info "Keeping existing secret"
        exit 0
    fi
fi

print_info "Creating secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
if oc create secret generic "$SECRET_NAME" \
    --from-literal=RHOAI_TOKEN="$TOKEN" \
    -n "$NAMESPACE"; then
    print_success "Secret created successfully"
else
    print_error "Failed to create secret"
    exit 1
fi

# Verify secret
print_header "Verification"

if oc get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    print_success "Secret exists and is accessible"
    
    # Show secret details
    echo ""
    print_info "Secret details:"
    oc get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml | grep -E "^  name:|^  namespace:|^  creationTimestamp:"
else
    print_error "Secret verification failed"
    exit 1
fi

# Summary
print_header "Setup Complete"

echo "✓ Service account: $SA_NAME (in $RHOAI_NAMESPACE)"
echo "✓ Secret: $SECRET_NAME (in $NAMESPACE)"
echo "✓ Token duration: $TOKEN_DURATION"
echo ""

print_info "Next steps:"
echo "1. Enable RHOAI connector in your Helm values:"
echo ""
echo "   developerHub:"
echo "     fusion:"
echo "       ai:"
echo "         rhoaiConnector:"
echo "           enabled: true"
echo ""
echo "2. Deploy or upgrade Developer Hub:"
echo ""
echo "   helm upgrade fusion-hub ./helm-charts/fusion-developer-hub \\"
echo "     -f examples/operator-fusion-guest-access-values.yaml \\"
echo "     --set developerHub.fusion.ai.rhoaiConnector.enabled=true \\"
echo "     --namespace $NAMESPACE"
echo ""

print_success "RHOAI connector setup complete!"

# Made with Bob
