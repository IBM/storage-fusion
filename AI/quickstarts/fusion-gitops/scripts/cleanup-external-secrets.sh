#!/bin/bash
# External Secrets Operator cleanup script
# Removes External Secrets Operator and all related resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="external-secrets-operator"
RELEASE_NAME="external-secrets-operator"
FORCE=false
KEEP_NAMESPACE=false

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove External Secrets Operator and all related resources

OPTIONS:
    -n, --namespace NAMESPACE       Operator namespace (default: external-secrets-operator)
    --release-name NAME             Helm release name (default: external-secrets-operator)
    --keep-namespace                Keep the namespace after cleanup
    --force                         Skip confirmation prompts
    -h, --help                      Show this help message

EXAMPLES:
    # Standard cleanup with confirmation
    $0

    # Cleanup specific namespace
    $0 --namespace my-eso-namespace

    # Force cleanup without prompts
    $0 --force

    # Cleanup but keep namespace
    $0 --keep-namespace

    # Cleanup specific release
    $0 --release-name my-eso --namespace my-namespace

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --keep-namespace)
            KEEP_NAMESPACE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Detect CLI (oc or kubectl)
if command -v oc &> /dev/null; then
    CLI="oc"
    print_info "Using OpenShift CLI (oc)"
elif command -v kubectl &> /dev/null; then
    CLI="kubectl"
    print_info "Using Kubernetes CLI (kubectl)"
else
    print_error "Neither 'oc' nor 'kubectl' found in PATH"
    exit 1
fi

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    print_warn "Helm is not installed. Will attempt manual cleanup."
    HELM_AVAILABLE=false
else
    HELM_AVAILABLE=true
fi

# Check if namespace exists
if ! $CLI get namespace $NAMESPACE &> /dev/null; then
    print_warn "Namespace $NAMESPACE does not exist. Nothing to clean up."
    exit 0
fi

# Display what will be removed
echo ""
print_info "Cleanup Configuration:"
echo "  Namespace:       $NAMESPACE"
echo "  Release Name:    $RELEASE_NAME"
echo "  Keep Namespace:  $KEEP_NAMESPACE"
echo ""

print_warn "The following resources will be removed:"
echo "  - Helm release: $RELEASE_NAME"
echo "  - External Secrets Operator subscription"
echo "  - ClusterSecretStores (all)"
echo "  - ExternalSecrets (all in namespace)"
echo "  - OperatorGroup"
echo "  - Service accounts and RBAC"
if [ "$KEEP_NAMESPACE" = false ]; then
    echo "  - Namespace: $NAMESPACE"
fi
echo ""

# Confirm cleanup
if [ "$FORCE" = false ]; then
    read -p "Do you want to proceed with cleanup? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_warn "Cleanup cancelled"
        exit 0
    fi
fi

# Start cleanup
print_info "Starting cleanup process..."
echo ""

# Step 1: Remove ExternalSecrets in the namespace
print_info "Removing ExternalSecrets in namespace $NAMESPACE..."
if $CLI get externalsecret -n $NAMESPACE &> /dev/null; then
    EXTERNALSECRETS=$($CLI get externalsecret -n $NAMESPACE -o name 2>/dev/null || echo "")
    if [ -n "$EXTERNALSECRETS" ]; then
        echo "$EXTERNALSECRETS" | while read -r es; do
            print_info "  Deleting $es"
            $CLI delete $es -n $NAMESPACE --ignore-not-found=true
        done
    else
        print_info "  No ExternalSecrets found"
    fi
else
    print_info "  ExternalSecret CRD not found or no resources"
fi

# Step 2: Remove ClusterSecretStores
print_info "Removing ClusterSecretStores..."
if $CLI get clustersecretstore &> /dev/null; then
    CLUSTERSECRETSTORES=$($CLI get clustersecretstore -o name 2>/dev/null || echo "")
    if [ -n "$CLUSTERSECRETSTORES" ]; then
        echo "$CLUSTERSECRETSTORES" | while read -r css; do
            print_info "  Deleting $css"
            $CLI delete $css --ignore-not-found=true
        done
    else
        print_info "  No ClusterSecretStores found"
    fi
else
    print_info "  ClusterSecretStore CRD not found or no resources"
fi

# Step 3: Remove SecretStores in the namespace
print_info "Removing SecretStores in namespace $NAMESPACE..."
if $CLI get secretstore -n $NAMESPACE &> /dev/null; then
    SECRETSTORES=$($CLI get secretstore -n $NAMESPACE -o name 2>/dev/null || echo "")
    if [ -n "$SECRETSTORES" ]; then
        echo "$SECRETSTORES" | while read -r ss; do
            print_info "  Deleting $ss"
            $CLI delete $ss -n $NAMESPACE --ignore-not-found=true
        done
    else
        print_info "  No SecretStores found"
    fi
else
    print_info "  SecretStore CRD not found or no resources"
fi

# Step 4: Uninstall Helm release
if [ "$HELM_AVAILABLE" = true ]; then
    print_info "Uninstalling Helm release: $RELEASE_NAME..."
    if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
        helm uninstall $RELEASE_NAME -n $NAMESPACE
        print_info "  Helm release uninstalled"
    else
        print_warn "  Helm release $RELEASE_NAME not found"
    fi
else
    print_warn "Skipping Helm uninstall (Helm not available)"
fi

# Step 5: Remove operator subscription
print_info "Removing operator subscription..."
if $CLI get subscription external-secrets-operator -n $NAMESPACE &> /dev/null; then
    $CLI delete subscription external-secrets-operator -n $NAMESPACE --ignore-not-found=true
    print_info "  Subscription removed"
else
    print_info "  Subscription not found"
fi

# Step 6: Remove CSV (ClusterServiceVersion)
print_info "Removing ClusterServiceVersion..."
CSV=$($CLI get csv -n $NAMESPACE -o name 2>/dev/null | grep external-secrets || echo "")
if [ -n "$CSV" ]; then
    $CLI delete $CSV -n $NAMESPACE --ignore-not-found=true
    print_info "  CSV removed"
else
    print_info "  CSV not found"
fi

# Step 7: Remove OperatorGroup
print_info "Removing OperatorGroup..."
if $CLI get operatorgroup -n $NAMESPACE &> /dev/null; then
    OPERATORGROUPS=$($CLI get operatorgroup -n $NAMESPACE -o name 2>/dev/null || echo "")
    if [ -n "$OPERATORGROUPS" ]; then
        echo "$OPERATORGROUPS" | while read -r og; do
            print_info "  Deleting $og"
            $CLI delete $og -n $NAMESPACE --ignore-not-found=true
        done
    else
        print_info "  No OperatorGroups found"
    fi
else
    print_info "  No OperatorGroups found"
fi

# Step 8: Wait for pods to terminate
print_info "Waiting for pods to terminate..."
TIMEOUT=60
ELAPSED=0
while $CLI get pods -n $NAMESPACE 2>/dev/null | grep -q external-secrets; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
        print_warn "  Timeout waiting for pods to terminate"
        break
    fi
    echo -n "."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
echo ""
print_info "  Pods terminated"

# Step 9: Remove namespace if requested
if [ "$KEEP_NAMESPACE" = false ]; then
    print_info "Removing namespace: $NAMESPACE..."
    $CLI delete namespace $NAMESPACE --ignore-not-found=true
    print_info "  Namespace removed"
else
    print_info "Keeping namespace: $NAMESPACE"
fi

# Step 10: Clean up CRDs (optional - only if no other instances)
print_warn "CRDs are NOT removed by default to prevent data loss"
print_info "If you want to remove CRDs, run:"
echo "  $CLI delete crd externalsecrets.external-secrets.io"
echo "  $CLI delete crd secretstores.external-secrets.io"
echo "  $CLI delete crd clustersecretstores.external-secrets.io"
echo "  $CLI delete crd clusterexternalsecrets.external-secrets.io"
echo "  $CLI delete crd pushsecrets.external-secrets.io"
echo ""

# Summary
echo ""
print_info "Cleanup completed successfully!"
echo ""
print_info "Summary:"
echo "  - External Secrets Operator removed from namespace: $NAMESPACE"
echo "  - All ExternalSecrets and SecretStores removed"
if [ "$KEEP_NAMESPACE" = false ]; then
    echo "  - Namespace deleted: $NAMESPACE"
else
    echo "  - Namespace preserved: $NAMESPACE"
fi
echo ""
print_info "To verify cleanup:"
echo "  $CLI get all -n $NAMESPACE"
echo "  $CLI get externalsecret -A"
echo "  $CLI get clustersecretstore"
echo ""

# Made with Bob