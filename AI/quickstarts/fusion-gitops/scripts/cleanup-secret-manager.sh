#!/bin/bash
# Secret Manager (HashiCorp Vault) cleanup script
# Removes Vault operator, instances, and related resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=""
RELEASE_NAME="vault-operator"
KEEP_OPERATOR=false
KEEP_NAMESPACE=false
FORCE=false

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

Clean up HashiCorp Vault deployment from OpenShift/Kubernetes

OPTIONS:
    -n, --namespace NAMESPACE       Vault namespace (default: current context namespace or 'vault')
    --release-name NAME             Helm release name (default: vault-operator)
    --keep-operator                 Keep the Vault operator installed
    --keep-namespace                Keep the namespace (don't delete it)
    --force                         Skip confirmation prompts
    -h, --help                      Show this help message

EXAMPLES:
    # Full cleanup (removes everything)
    $0

    # Keep the operator, only remove Vault instances
    $0 --keep-operator

    # Cleanup specific namespace
    $0 -n vault-prod

    # Force cleanup without confirmation
    $0 --force

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
        --keep-operator)
            KEEP_OPERATOR=true
            shift
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

# Set default namespace if not provided
if [ -z "$NAMESPACE" ]; then
    NAMESPACE="vault"
    print_info "Using default namespace: $NAMESPACE"
    print_warn "To cleanup a different namespace, use: $0 -n <namespace>"
fi

# Check if namespace exists
if ! $CLI get namespace $NAMESPACE &> /dev/null; then
    print_warn "Namespace $NAMESPACE does not exist"
    exit 0
fi

# Display what will be removed
echo ""
print_warn "This will remove the following:"
echo "  - Helm release: $RELEASE_NAME"
echo "  - Vault instances in namespace: $NAMESPACE"
echo "  - Vault StatefulSets, Services, ConfigMaps"
echo "  - Vault PVCs and data"
echo "  - Vault unseal keys secret"
if [ "$KEEP_OPERATOR" = false ]; then
    echo "  - Vault Secrets Operator"
    echo "  - Operator subscription and CSV"
fi
if [ "$KEEP_NAMESPACE" = false ]; then
    echo "  - Namespace: $NAMESPACE"
fi
echo ""

# Confirm cleanup
if [ "$FORCE" = false ]; then
    print_warn "⚠️  WARNING: This action cannot be undone!"
    print_warn "⚠️  All Vault data and unseal keys will be permanently deleted!"
    echo ""
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
fi

# Start cleanup
print_info "Starting cleanup..."
echo ""

# 1. Uninstall Helm release
print_info "Removing Helm release: $RELEASE_NAME"
if helm list -n $NAMESPACE 2>/dev/null | grep -q $RELEASE_NAME; then
    helm uninstall $RELEASE_NAME -n $NAMESPACE || print_warn "Failed to uninstall Helm release"
else
    print_warn "Helm release $RELEASE_NAME not found"
fi

# 2. Delete Vault instances
print_info "Deleting Vault StatefulSets..."
$CLI delete statefulset -n $NAMESPACE -l app.kubernetes.io/name=vault --ignore-not-found=true

# 3. Delete Vault services
print_info "Deleting Vault Services..."
$CLI delete service -n $NAMESPACE -l app.kubernetes.io/name=vault --ignore-not-found=true

# 4. Delete Vault ConfigMaps
print_info "Deleting Vault ConfigMaps..."
$CLI delete configmap -n $NAMESPACE -l app.kubernetes.io/name=vault --ignore-not-found=true

# 5. Delete Vault ServiceAccounts
print_info "Deleting Vault ServiceAccounts..."
$CLI delete serviceaccount -n $NAMESPACE -l app.kubernetes.io/name=vault --ignore-not-found=true

# 6. Delete Vault Roles and RoleBindings
print_info "Deleting Vault RBAC resources..."
$CLI delete role -n $NAMESPACE -l app.kubernetes.io/name=vault --ignore-not-found=true
$CLI delete rolebinding -n $NAMESPACE -l app.kubernetes.io/name=vault --ignore-not-found=true

# 7. Delete Vault Routes (OpenShift)
if [ "$CLI" = "oc" ]; then
    print_info "Deleting Vault Routes..."
    $CLI delete route -n $NAMESPACE -l app.kubernetes.io/name=vault --ignore-not-found=true
fi

# 8. Delete Vault PVCs
print_warn "Deleting Vault PVCs (this will delete all Vault data)..."
$CLI delete pvc -n $NAMESPACE -l app.kubernetes.io/name=vault --ignore-not-found=true

# 9. Delete Vault unseal keys secret
print_warn "Deleting Vault unseal keys secret..."
$CLI delete secret -n $NAMESPACE vault-unseal-keys --ignore-not-found=true

# 10. Delete any remaining pods
print_info "Deleting remaining Vault pods..."
$CLI delete pod -n $NAMESPACE -l app.kubernetes.io/name=vault --ignore-not-found=true

# 11. Remove operator if requested
if [ "$KEEP_OPERATOR" = false ]; then
    print_info "Removing Vault Secrets Operator..."
    
    # Delete operator subscription
    print_info "Deleting Subscription..."
    $CLI delete subscription -n $NAMESPACE vault-secrets-operator --ignore-not-found=true
    
    # Delete all CSVs related to vault-secrets-operator
    print_info "Deleting ClusterServiceVersions..."
    CSV_NAMES=$($CLI get csv -n $NAMESPACE -o name 2>/dev/null | grep vault-secrets-operator || true)
    if [ -n "$CSV_NAMES" ]; then
        echo "$CSV_NAMES" | while read csv; do
            print_info "Deleting $csv"
            $CLI delete -n $NAMESPACE $csv --ignore-not-found=true
        done
    fi
    
    # Delete operator deployment
    print_info "Deleting Operator Deployment..."
    $CLI delete deployment -n $NAMESPACE -l operators.coreos.com/vault-secrets-operator.$NAMESPACE --ignore-not-found=true
    $CLI delete deployment -n $NAMESPACE vault-secrets-operator-controller-manager --ignore-not-found=true
    
    # Delete operator pods
    print_info "Deleting Operator Pods..."
    $CLI delete pod -n $NAMESPACE -l app.kubernetes.io/name=vault-secrets-operator --ignore-not-found=true
    
    # Delete operator service accounts
    print_info "Deleting Operator ServiceAccounts..."
    $CLI delete serviceaccount -n $NAMESPACE -l app.kubernetes.io/name=vault-secrets-operator --ignore-not-found=true
    
    # Delete operator roles and rolebindings
    print_info "Deleting Operator RBAC..."
    $CLI delete role -n $NAMESPACE -l app.kubernetes.io/name=vault-secrets-operator --ignore-not-found=true
    $CLI delete rolebinding -n $NAMESPACE -l app.kubernetes.io/name=vault-secrets-operator --ignore-not-found=true
    
    # Delete OperatorGroup
    print_info "Deleting OperatorGroup..."
    $CLI delete operatorgroup -n $NAMESPACE --all --ignore-not-found=true
    
    # Wait for operator pods to terminate
    print_info "Waiting for operator pods to terminate..."
    for i in {1..30}; do
        OPERATOR_PODS=$($CLI get pods -n $NAMESPACE -l app.kubernetes.io/name=vault-secrets-operator -o name 2>/dev/null || true)
        if [ -z "$OPERATOR_PODS" ]; then
            print_info "Operator pods terminated"
            break
        fi
        if [ $i -eq 30 ]; then
            print_warn "Some operator pods are still running"
        fi
        sleep 2
    done
fi

# 12. Delete namespace if requested
if [ "$KEEP_NAMESPACE" = false ]; then
    print_info "Deleting namespace: $NAMESPACE"
    $CLI delete namespace $NAMESPACE --ignore-not-found=true
    
    # Wait for namespace deletion
    print_info "Waiting for namespace deletion..."
    for i in {1..60}; do
        if ! $CLI get namespace $NAMESPACE &> /dev/null; then
            break
        fi
        if [ $i -eq 60 ]; then
            print_warn "Namespace deletion is taking longer than expected"
            print_info "You can check status with: $CLI get namespace $NAMESPACE"
        fi
        sleep 2
    done
fi

# Summary
echo ""
print_info "Cleanup complete!"
echo ""
print_info "Removed:"
echo "  ✓ Vault instances"
echo "  ✓ Vault data and PVCs"
echo "  ✓ Vault unseal keys"
if [ "$KEEP_OPERATOR" = false ]; then
    echo "  ✓ Vault Secrets Operator"
fi
if [ "$KEEP_NAMESPACE" = false ]; then
    echo "  ✓ Namespace: $NAMESPACE"
fi
echo ""

if [ "$KEEP_OPERATOR" = true ]; then
    print_info "Vault Secrets Operator was kept as requested"
fi

if [ "$KEEP_NAMESPACE" = true ]; then
    print_info "Namespace $NAMESPACE was kept as requested"
fi

print_info "To redeploy Vault, run: ./scripts/deploy-secret-manager.sh"

# Made with Bob