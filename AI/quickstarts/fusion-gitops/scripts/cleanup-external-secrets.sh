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
VAULT_NAMESPACE="vault"
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
    --vault-namespace NAMESPACE     Vault namespace (default: vault)
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

    # Cleanup with custom Vault namespace
    $0 --vault-namespace my-vault-ns

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
        --vault-namespace)
            VAULT_NAMESPACE="$2"
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
echo "  Vault Namespace: $VAULT_NAMESPACE"
echo "  Keep Namespace:  $KEEP_NAMESPACE"
echo ""

print_warn "The following resources will be removed:"
echo "  - ValidatingWebhookConfiguration (cluster-scoped)"
echo "  - MutatingWebhookConfiguration (cluster-scoped)"
echo "  - Helm release: $RELEASE_NAME"
echo "  - ExternalSecretsConfig (cluster-scoped)"
echo "  - NetworkPolicies in namespace $NAMESPACE"
echo "  - ClusterRoleBinding: vault-tokenreview-binding (cluster-scoped)"
echo "  - ClusterRoles (cluster-scoped, external-secrets related)"
echo "  - ClusterRoleBindings (cluster-scoped, external-secrets related)"
echo "  - Vault initialization Job (if present in Vault namespace: $VAULT_NAMESPACE)"
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

# Step 0: Remove webhook configurations first to prevent validation errors
print_info "Removing webhook configurations..."

# Remove ValidatingWebhookConfiguration
VALIDATING_WEBHOOKS=$($CLI get validatingwebhookconfiguration -o name 2>/dev/null | grep -E "externalsecret-validate|secretstore-validate" || echo "")
if [ -n "$VALIDATING_WEBHOOKS" ]; then
    echo "$VALIDATING_WEBHOOKS" | while read -r vwh; do
        print_info "  Deleting ValidatingWebhookConfiguration: $vwh"
        $CLI delete $vwh --ignore-not-found=true 2>/dev/null || true
    done
    print_info "  ValidatingWebhookConfiguration(s) removed successfully"
else
    print_info "  No ValidatingWebhookConfiguration found (externalsecret-validate, secretstore-validate)"
fi

# Remove MutatingWebhookConfiguration
MUTATING_WEBHOOKS=$($CLI get mutatingwebhookconfiguration -o name 2>/dev/null | grep -E "externalsecret-mutate|secretstore-mutate" || echo "")
if [ -n "$MUTATING_WEBHOOKS" ]; then
    echo "$MUTATING_WEBHOOKS" | while read -r mwh; do
        print_info "  Deleting MutatingWebhookConfiguration: $mwh"
        $CLI delete $mwh --ignore-not-found=true 2>/dev/null || true
    done
    print_info "  MutatingWebhookConfiguration(s) removed"
else
    print_info "  No MutatingWebhookConfiguration found"
fi
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

# Step 4: Remove NetworkPolicies in the namespace
print_info "Removing NetworkPolicies in namespace $NAMESPACE..."
if $CLI api-resources --api-group=networking.k8s.io 2>/dev/null | grep -q "^networkpolicies"; then
    NETWORKPOLICIES=$($CLI get networkpolicy -n $NAMESPACE -o name 2>/dev/null | grep -E "allow-vault-egress|external-secrets" || echo "")
    if [ -n "$NETWORKPOLICIES" ]; then
        echo "$NETWORKPOLICIES" | while read -r np; do
            print_info "  Deleting $np"
            $CLI delete $np -n $NAMESPACE --ignore-not-found=true
        done
        print_info "  External Secrets NetworkPolicy resource(s) removed"
    else
        print_info "  No External Secrets NetworkPolicies found"
    fi
else
    print_info "  NetworkPolicy resource type not available, skipping cleanup"
fi
echo ""

# Step 5: Remove ExternalSecretsConfig (cluster-scoped)
print_info "Removing ExternalSecretsConfig..."
if $CLI get externalsecretsconfig cluster &> /dev/null; then
    $CLI delete externalsecretsconfig cluster --ignore-not-found=true
    print_info "  ExternalSecretsConfig 'cluster' removed"
else
    print_info "  ExternalSecretsConfig not found"
fi
echo ""

# Step 5.a: Remove Vault TokenReview ClusterRoleBinding (has keep policy)
print_info "Removing Vault TokenReview ClusterRoleBinding..."
if $CLI get clusterrolebinding vault-tokenreview-binding &> /dev/null; then
    $CLI delete clusterrolebinding vault-tokenreview-binding --ignore-not-found=true
    print_info "  ClusterRoleBinding 'vault-tokenreview-binding' removed"
else
    print_info "  ClusterRoleBinding 'vault-tokenreview-binding' not found"
fi
echo ""

# Step 5.b: Remove Vault Init Job (if exists in Vault namespace)
print_info "Checking for Vault initialization Job..."
if $CLI get namespace $VAULT_NAMESPACE &> /dev/null; then
    if $CLI get job vault-init-external-secrets -n $VAULT_NAMESPACE &> /dev/null; then
        print_info "  Removing Vault init Job from namespace: $VAULT_NAMESPACE"
        $CLI delete job vault-init-external-secrets -n $VAULT_NAMESPACE --ignore-not-found=true
        print_info "  Vault init Job removed"
    else
        print_info "  Vault init Job not found in namespace: $VAULT_NAMESPACE"
    fi
else
    print_info "  Vault namespace '$VAULT_NAMESPACE' not found, skipping Job cleanup"
fi
echo ""

# Step 7: Remove ClusterRoles and ClusterRoleBindings
print_info "Removing External Secrets ClusterRoles and ClusterRoleBindings..."

# Remove ClusterRoles
CLUSTER_ROLES=$($CLI get clusterrole -o name 2>/dev/null | grep -E "external-secrets" || echo "")
if [ -n "$CLUSTER_ROLES" ]; then
    echo "$CLUSTER_ROLES" | while read -r cr; do
        print_info "  Deleting $cr"
        $CLI delete $cr --ignore-not-found=true 2>/dev/null || true
    done
    print_info "  ClusterRole(s) removed"
else
    print_info "  No External Secrets ClusterRoles found"
fi

# Remove ClusterRoleBindings
CLUSTER_ROLE_BINDINGS=$($CLI get clusterrolebinding -o name 2>/dev/null | grep -E "external-secrets" || echo "")
if [ -n "$CLUSTER_ROLE_BINDINGS" ]; then
    echo "$CLUSTER_ROLE_BINDINGS" | while read -r crb; do
        print_info "  Deleting $crb"
        $CLI delete $crb --ignore-not-found=true 2>/dev/null || true
    done
    print_info "  ClusterRoleBinding(s) removed"
else
    print_info "  No External Secrets ClusterRoleBindings found"
fi
echo ""

# Step 8: Uninstall Helm release
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
echo ""

# Step 9: Remove operator subscription
print_info "Removing operator subscription..."
if $CLI get subscription external-secrets-operator -n $NAMESPACE &> /dev/null; then
    $CLI delete subscription external-secrets-operator -n $NAMESPACE --ignore-not-found=true
    print_info "  Subscription removed"
else
    print_info "  Subscription not found"
fi
echo ""

# Step 10: Remove CSV (ClusterServiceVersion)
print_info "Removing ClusterServiceVersion..."
CSV=$($CLI get csv -n $NAMESPACE -o name 2>/dev/null | grep external-secrets || echo "")
if [ -n "$CSV" ]; then
    $CLI delete $CSV -n $NAMESPACE --ignore-not-found=true
    print_info "  CSV removed"
else
    print_info "  CSV not found"
fi
echo ""

# Step 11: Remove OperatorGroup
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
echo ""

# Step 12: Wait for pods to terminate
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
echo ""

# Step 13: Remove namespace if requested
if [ "$KEEP_NAMESPACE" = false ]; then
    print_info "Removing namespace: $NAMESPACE..."
    $CLI delete namespace $NAMESPACE --ignore-not-found=true
    print_info "  Namespace removed"
else
    print_info "Keeping namespace: $NAMESPACE"
fi

# Step 14: Clean up CRDs (optional - only if no other instances)
print_warn "CRDs are NOT removed by default to prevent data loss"
print_info "If you want to remove CRDs, run:"
echo "  $CLI delete crd externalsecrets.external-secrets.io"
echo "  $CLI delete crd secretstores.external-secrets.io"
echo "  $CLI delete crd clustersecretstores.external-secrets.io"
echo "  $CLI delete crd clusterexternalsecrets.external-secrets.io"
echo "  $CLI delete crd pushsecrets.external-secrets.io"
echo "  $CLI delete crd externalsecretsconfigs.operator.openshift.io"
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
echo "  $CLI get networkpolicy -n $NAMESPACE"
echo "  $CLI get clusterrole | grep external-secrets"
echo "  $CLI get clusterrolebinding | grep external-secrets"
echo "  $CLI get validatingwebhookconfiguration | grep external-secrets"
echo "  $CLI get mutatingwebhookconfiguration | grep external-secrets"
echo ""

# Made with Bob