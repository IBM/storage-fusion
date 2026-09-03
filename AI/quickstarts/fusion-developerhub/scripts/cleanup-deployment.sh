#!/bin/bash
# Fusion Developer Hub - Cleanup Script
# This script removes a Fusion Developer Hub deployment and all related resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

confirm() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}$1${NC}"
    read -p "Continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        echo "Aborted."
        exit 1
    fi
}

# Show usage
usage() {
    cat << EOF
Usage: $0 -n NAMESPACE -r RELEASE_NAME [OPTIONS]

Cleanup Fusion Developer Hub deployment and related resources.

REQUIRED OPTIONS:
    -n, --namespace NAME        Namespace to clean up
    -r, --release NAME          Helm release name

OPTIONAL FLAGS:
    --delete-namespace          Delete the namespace after cleanup
    --delete-operators          Delete operators (RHDH and PostgreSQL)
    -f, --force                 Skip confirmation prompts
    -h, --help                  Show this help message

EXAMPLES:
    # Clean up deployment
    $0 -n fusion-dev-hub -r fusion-hub

    # Clean up and delete namespace
    $0 -n fusion-dev-hub -r fusion-hub --delete-namespace

    # Clean up everything including operators
    $0 -n fusion-dev-hub -r fusion-hub --delete-namespace --delete-operators

    # Force cleanup without prompts
    $0 -n fusion-dev-hub -r fusion-hub --force --delete-namespace

EOF
    exit 0
}

# Initialize variables
NAMESPACE=""
RELEASE_NAME=""
DELETE_NAMESPACE="false"
DELETE_OPERATORS="false"
FORCE="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --delete-namespace)
            DELETE_NAMESPACE="true"
            shift
            ;;
        --delete-operators)
            DELETE_OPERATORS="true"
            shift
            ;;
        -f|--force)
            FORCE="true"
            shift
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

# Validate required parameters
if [[ -z "$NAMESPACE" ]]; then
    print_error "Namespace is required"
    echo ""
    usage
fi

if [[ -z "$RELEASE_NAME" ]]; then
    print_error "Release name is required"
    echo ""
    usage
fi

# Start cleanup
print_header "Fusion Developer Hub Cleanup"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo "Delete Namespace: $DELETE_NAMESPACE"
echo "Delete Operators: $DELETE_OPERATORS"
echo ""

# Check prerequisites
if ! command -v oc &> /dev/null; then
    print_error "oc CLI is not installed"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed"
    exit 1
fi

# Check cluster connection
if ! oc whoami &> /dev/null; then
    print_error "Not connected to OpenShift cluster"
    exit 1
fi

print_success "Connected to cluster as: $(oc whoami)"

# Confirm cleanup
echo ""
print_warning "This will remove the following:"
echo "  - Helm release: $RELEASE_NAME"
echo "  - Backstage instance in namespace: $NAMESPACE"
echo "  - PostgreSQL cluster in namespace: $NAMESPACE"
echo "  - All related resources (ConfigMaps, Secrets, PVCs, etc.)"
if [[ "$DELETE_NAMESPACE" == "true" ]]; then
    echo "  - Namespace: $NAMESPACE"
fi
if [[ "$DELETE_OPERATORS" == "true" ]]; then
    echo "  - RHDH Operator"
    echo "  - PostgreSQL Operator"
fi
echo ""

confirm "Are you sure you want to proceed?"

# 1. Delete Helm Release
print_header "1. Removing Helm Release"

# Check for normal release
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    print_info "Uninstalling Helm release: $RELEASE_NAME"
    if helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null; then
        print_success "Helm release uninstalled"
    else
        print_warning "Failed to uninstall Helm release (may not exist)"
    fi
# Check for pending release in secrets
elif oc get secret -n "$NAMESPACE" -l "owner=helm,name=$RELEASE_NAME" &> /dev/null; then
    print_warning "Found Helm release in pending state (stored in secrets)"
    print_info "Deleting Helm release secrets..."
    
    # Delete all Helm secrets for this release
    if oc delete secret -n "$NAMESPACE" -l "owner=helm,name=$RELEASE_NAME" 2>/dev/null; then
        print_success "Helm release secrets deleted"
    else
        print_warning "Failed to delete some Helm secrets, continuing..."
    fi
else
    print_info "Helm release not found"
fi

# 2. Delete Failed Hook Jobs
print_header "2. Cleaning Up Hook Jobs"

HOOK_JOBS=$(oc get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=namespace-labeler --no-headers 2>/dev/null | awk '{print $1}')
if [[ -n "$HOOK_JOBS" ]]; then
    for job in $HOOK_JOBS; do
        print_info "Deleting hook job: $job"
        oc delete job "$job" -n "$NAMESPACE" 2>/dev/null || true
    done
    print_success "Hook jobs cleaned up"
else
    print_info "No hook jobs found"
fi

# 3. Delete Backstage Instance
print_header "3. Removing Backstage Instance"

if oc get backstage -n "$NAMESPACE" &> /dev/null; then
    BACKSTAGE_INSTANCES=$(oc get backstage -n "$NAMESPACE" -o name 2>/dev/null)
    if [[ -n "$BACKSTAGE_INSTANCES" ]]; then
        for instance in $BACKSTAGE_INSTANCES; do
            INSTANCE_NAME=$(echo "$instance" | cut -d'/' -f2)
            print_info "Deleting Backstage instance: $INSTANCE_NAME"
            oc delete backstage "$INSTANCE_NAME" -n "$NAMESPACE" --wait=false 2>/dev/null || true
        done
        
        # Wait for deletion
        print_info "Waiting for Backstage instances to be deleted..."
        timeout 60 bash -c "while oc get backstage -n $NAMESPACE &>/dev/null; do sleep 2; done" || print_warning "Timeout waiting for Backstage deletion"
        print_success "Backstage instances deleted"
    else
        print_info "No Backstage instances found"
    fi
else
    print_info "Backstage CRD not found or no instances"
fi

# 4. Delete PostgreSQL Cluster
print_header "4. Removing PostgreSQL Cluster"

if oc get postgrescluster -n "$NAMESPACE" &> /dev/null; then
    PG_CLUSTERS=$(oc get postgrescluster -n "$NAMESPACE" -o name 2>/dev/null)
    if [[ -n "$PG_CLUSTERS" ]]; then
        for cluster in $PG_CLUSTERS; do
            CLUSTER_NAME=$(echo "$cluster" | cut -d'/' -f2)
            print_info "Deleting PostgreSQL cluster: $CLUSTER_NAME"
            oc delete postgrescluster "$CLUSTER_NAME" -n "$NAMESPACE" --wait=false 2>/dev/null || true
        done
        
        # Wait for deletion
        print_info "Waiting for PostgreSQL clusters to be deleted..."
        timeout 60 bash -c "while oc get postgrescluster -n $NAMESPACE &>/dev/null; do sleep 2; done" || print_warning "Timeout waiting for PostgreSQL deletion"
        print_success "PostgreSQL clusters deleted"
    else
        print_info "No PostgreSQL clusters found"
    fi
else
    print_info "PostgresCluster CRD not found or no clusters"
fi

# 5. Delete Remaining Resources
print_header "5. Cleaning Up Remaining Resources"

# Delete ConfigMaps
print_info "Deleting ConfigMaps..."
oc delete configmap -n "$NAMESPACE" -l app.kubernetes.io/managed-by=Helm 2>/dev/null || true

# Delete Secrets (except default tokens)
print_info "Deleting Secrets..."
oc delete secret -n "$NAMESPACE" -l app.kubernetes.io/managed-by=Helm 2>/dev/null || true

# Delete PVCs
print_info "Deleting PVCs..."
oc delete pvc -n "$NAMESPACE" -l app.kubernetes.io/managed-by=Helm 2>/dev/null || true

# Delete Services
print_info "Deleting Services..."
oc delete service -n "$NAMESPACE" -l app.kubernetes.io/managed-by=Helm 2>/dev/null || true

# Delete Routes
print_info "Deleting Routes..."
oc delete route -n "$NAMESPACE" -l app.kubernetes.io/managed-by=Helm 2>/dev/null || true

# Delete ServiceAccounts
print_info "Deleting ServiceAccounts..."
oc delete serviceaccount -n "$NAMESPACE" -l app.kubernetes.io/managed-by=Helm 2>/dev/null || true

# Delete Roles and RoleBindings
print_info "Deleting Roles and RoleBindings..."
oc delete role,rolebinding -n "$NAMESPACE" -l app.kubernetes.io/managed-by=Helm 2>/dev/null || true

print_success "Remaining resources cleaned up"

# 6. Delete ClusterRole and ClusterRoleBinding
print_header "6. Cleaning Up Cluster Resources"

print_info "Deleting ClusterRoles..."
oc delete clusterrole "${RELEASE_NAME}-namespace-labeler" 2>/dev/null || true
oc delete clusterrole -l app.kubernetes.io/instance="$RELEASE_NAME" 2>/dev/null || true

print_info "Deleting ClusterRoleBindings..."
oc delete clusterrolebinding "${RELEASE_NAME}-namespace-labeler" 2>/dev/null || true
oc delete clusterrolebinding -l app.kubernetes.io/instance="$RELEASE_NAME" 2>/dev/null || true

print_success "Cluster resources cleaned up"

# 7. Delete Namespace
if [[ "$DELETE_NAMESPACE" == "true" ]]; then
    print_header "7. Deleting Namespace"
    
    if oc get namespace "$NAMESPACE" &> /dev/null; then
        print_warning "Deleting namespace: $NAMESPACE"
        confirm "This will permanently delete the namespace and all remaining resources. Continue?"
        
        oc delete namespace "$NAMESPACE" --wait=false 2>/dev/null || true
        
        print_info "Waiting for namespace deletion..."
        timeout 120 bash -c "while oc get namespace $NAMESPACE &>/dev/null; do sleep 2; done" || print_warning "Timeout waiting for namespace deletion"
        
        if oc get namespace "$NAMESPACE" &> /dev/null; then
            print_warning "Namespace still exists (may be stuck in Terminating state)"
        else
            print_success "Namespace deleted"
        fi
    else
        print_info "Namespace does not exist"
    fi
fi

# 8. Delete Operators
if [[ "$DELETE_OPERATORS" == "true" ]]; then
    print_header "8. Removing Operators"
    
    print_warning "This will remove operators that may be used by other deployments!"
    confirm "Are you sure you want to delete the operators?"
    
    # Delete RHDH Operator
    print_info "Deleting RHDH Operator..."
    if oc get subscription rhdh-operator -n rhdh-operator &> /dev/null; then
        oc delete subscription rhdh-operator -n rhdh-operator 2>/dev/null || true
        oc delete csv -n rhdh-operator -l operators.coreos.com/rhdh-operator.rhdh-operator 2>/dev/null || true
        print_success "RHDH Operator deleted"
    else
        print_info "RHDH Operator not found"
    fi
    
    # Delete PostgreSQL Operator
    print_info "Deleting PostgreSQL Operator..."
    if oc get subscription postgresql -n postgres-operator &> /dev/null; then
        oc delete subscription postgresql -n postgres-operator 2>/dev/null || true
        oc delete csv -n postgres-operator -l operators.coreos.com/postgresql.postgres-operator 2>/dev/null || true
        print_success "PostgreSQL Operator deleted"
    else
        print_info "PostgreSQL Operator not found"
    fi
    
    # Optionally delete operator namespaces
    print_info "Deleting operator namespaces..."
    oc delete namespace rhdh-operator 2>/dev/null || true
    oc delete namespace postgres-operator 2>/dev/null || true
fi

# 9. Summary
print_header "Cleanup Summary"

echo "Cleaned up resources:"
echo "  ✓ Helm release: $RELEASE_NAME"
echo "  ✓ Backstage instances"
echo "  ✓ PostgreSQL clusters"
echo "  ✓ ConfigMaps, Secrets, PVCs"
echo "  ✓ Services, Routes"
echo "  ✓ ServiceAccounts, Roles, RoleBindings"
echo "  ✓ ClusterRoles, ClusterRoleBindings"

if [[ "$DELETE_NAMESPACE" == "true" ]]; then
    echo "  ✓ Namespace: $NAMESPACE"
fi

if [[ "$DELETE_OPERATORS" == "true" ]]; then
    echo "  ✓ RHDH Operator"
    echo "  ✓ PostgreSQL Operator"
fi

echo ""
print_success "Cleanup complete!"

# Check for any remaining resources
echo ""
print_info "Checking for remaining resources in namespace..."
REMAINING=$(oc get all -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [[ $REMAINING -gt 0 ]]; then
    print_warning "Found $REMAINING remaining resource(s) in namespace"
    echo ""
    oc get all -n "$NAMESPACE" 2>/dev/null
else
    print_success "No remaining resources found"
fi

echo ""
print_info "To redeploy, run:"
echo "  helm install $RELEASE_NAME ./helm-charts/fusion-developer-hub \\"
echo "    -f examples/operator-fusion-guest-access-values.yaml \\"
echo "    --set global.wildcardDomain=apps.your-cluster.example.com \\"
echo "    --namespace $NAMESPACE --create-namespace"

# Made with Bob
