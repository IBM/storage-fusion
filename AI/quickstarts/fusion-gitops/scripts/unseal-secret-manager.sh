#!/bin/bash
# Vault Unseal Script
# Unseals all Vault pods in a namespace using stored unseal keys

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Default values
NAMESPACE=""
VERBOSE=false

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Unseal all Vault pods in a namespace using stored unseal keys from Kubernetes secret.

OPTIONS:
    -n, --namespace NAMESPACE    Vault namespace (default: current context namespace or 'vault')
    -v, --verbose               Show detailed output
    -h, --help                  Show this help message

EXAMPLES:
    # Unseal Vault in default namespace
    $0

    # Unseal Vault in specific namespace
    $0 --namespace vault-prod

    # Unseal with verbose output
    $0 --namespace vault2 --verbose

DESCRIPTION:
    This script unseals all Vault pods in the specified namespace by:
    1. Detecting the CLI tool (oc or kubectl)
    2. Finding all Vault pods
    3. Retrieving unseal keys from the vault-unseal-keys secret
    4. Unsealing each pod with 3 unseal keys (threshold)
    5. Verifying the unseal status

    The script requires that Vault has been initialized and the
    vault-unseal-keys secret exists in the namespace.

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
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Detect CLI tool
if command -v oc &> /dev/null; then
    CLI="oc"
    log_info "Using OpenShift CLI (oc)"
elif command -v kubectl &> /dev/null; then
    CLI="kubectl"
    log_info "Using Kubernetes CLI (kubectl)"
else
    log_error "Neither 'oc' nor 'kubectl' found. Please install one of them."
    exit 1
fi

# Set namespace if not provided
if [ -z "$NAMESPACE" ]; then
    NAMESPACE=$($CLI config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "vault")
    if [ -z "$NAMESPACE" ]; then
        NAMESPACE="vault"
    fi
    log_info "Using namespace: $NAMESPACE"
fi

# Print banner
print_banner "Vault Unseal"
echo "Namespace: $NAMESPACE"
echo "Cluster: $($CLI config current-context 2>/dev/null || echo 'unknown')"
echo ""

# Check if namespace exists
if ! $CLI get namespace "$NAMESPACE" &> /dev/null; then
    log_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

# Check if vault-unseal-keys secret exists
log_info "Checking for unseal keys secret..."
if ! $CLI get secret vault-unseal-keys -n "$NAMESPACE" &> /dev/null; then
    log_error "Secret 'vault-unseal-keys' not found in namespace '$NAMESPACE'"
    log_error "Vault may not be initialized yet. Run the initialization playbook first:"
    echo "  ansible-playbook ansible/playbooks/initialize-vault.yml -e vault_namespace=$NAMESPACE"
    exit 1
fi

# Get unseal keys from secret
log_info "Retrieving unseal keys from secret..."
# Try both key formats (key1/key2/key3 and unseal-key-1/unseal-key-2/unseal-key-3)
UNSEAL_KEY_1=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data.key1}' 2>/dev/null | base64 -d)
if [ -z "$UNSEAL_KEY_1" ]; then
    UNSEAL_KEY_1=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data.unseal-key-1}' | base64 -d)
fi

UNSEAL_KEY_2=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data.key2}' 2>/dev/null | base64 -d)
if [ -z "$UNSEAL_KEY_2" ]; then
    UNSEAL_KEY_2=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data.unseal-key-2}' | base64 -d)
fi

UNSEAL_KEY_3=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data.key3}' 2>/dev/null | base64 -d)
if [ -z "$UNSEAL_KEY_3" ]; then
    UNSEAL_KEY_3=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data.unseal-key-3}' | base64 -d)
fi

if [ -z "$UNSEAL_KEY_1" ] || [ -z "$UNSEAL_KEY_2" ] || [ -z "$UNSEAL_KEY_3" ]; then
    log_error "Failed to retrieve unseal keys from secret"
    exit 1
fi

[ "$VERBOSE" = true ] && log_info "Successfully retrieved 3 unseal keys"

# Get list of Vault pods
log_info "Finding Vault pods..."
VAULT_PODS=$($CLI get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$VAULT_PODS" ]; then
    log_error "No Vault pods found in namespace '$NAMESPACE'"
    exit 1
fi

POD_COUNT=$(echo "$VAULT_PODS" | wc -w | tr -d ' ')
log_info "Found $POD_COUNT Vault pod(s): $VAULT_PODS"
echo ""

# Unseal each pod
UNSEALED_COUNT=0
ALREADY_UNSEALED_COUNT=0
FAILED_COUNT=0

for pod in $VAULT_PODS; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Unsealing pod: $pod"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check if pod is running
    POD_STATUS=$($CLI get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$POD_STATUS" != "Running" ]; then
        log_warning "Pod $pod is not running (status: $POD_STATUS), skipping..."
        ((FAILED_COUNT++))
        continue
    fi
    
    # Check current seal status
    if [ "$VERBOSE" = true ]; then
        log_info "Checking current seal status..."
    fi
    
    SEAL_STATUS=$($CLI exec -n "$NAMESPACE" "$pod" -- vault status -format=json 2>/dev/null || echo "{}")
    IS_SEALED=$(echo "$SEAL_STATUS" | grep -o '"sealed":[^,}]*' | cut -d':' -f2 | tr -d ' ' || echo "true")
    
    if [ "$IS_SEALED" = "false" ]; then
        log_success "✓ $pod is already unsealed"
        ((ALREADY_UNSEALED_COUNT++))
        continue
    fi
    
    [ "$VERBOSE" = true ] && log_info "Pod is sealed, proceeding with unseal..."
    
    # Unseal with key 1
    if [ "$VERBOSE" = true ]; then
        log_info "Applying unseal key 1/3..."
    fi
    if ! $CLI exec -n "$NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY_1" &> /dev/null; then
        log_error "✗ Failed to apply unseal key 1 to $pod"
        if [ "$VERBOSE" = true ]; then
            $CLI exec -n "$NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY_1" 2>&1 || true
        fi
        ((FAILED_COUNT++))
        continue
    fi
    
    # Unseal with key 2
    if [ "$VERBOSE" = true ]; then
        log_info "Applying unseal key 2/3..."
    fi
    if ! $CLI exec -n "$NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY_2" &> /dev/null; then
        log_error "✗ Failed to apply unseal key 2 to $pod"
        if [ "$VERBOSE" = true ]; then
            $CLI exec -n "$NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY_2" 2>&1 || true
        fi
        ((FAILED_COUNT++))
        continue
    fi
    
    # Unseal with key 3
    if [ "$VERBOSE" = true ]; then
        log_info "Applying unseal key 3/3..."
    fi
    if ! $CLI exec -n "$NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY_3" &> /dev/null; then
        log_error "✗ Failed to apply unseal key 3 to $pod"
        if [ "$VERBOSE" = true ]; then
            $CLI exec -n "$NAMESPACE" "$pod" -- vault operator unseal "$UNSEAL_KEY_3" 2>&1 || true
        fi
        ((FAILED_COUNT++))
        continue
    fi
    
    # Verify unseal status
    sleep 2
    FINAL_STATUS=$($CLI exec -n "$NAMESPACE" "$pod" -- vault status -format=json 2>/dev/null || echo "{}")
    FINAL_SEALED=$(echo "$FINAL_STATUS" | grep -o '"sealed":[^,}]*' | cut -d':' -f2 | tr -d ' ' || echo "true")
    
    if [ "$FINAL_SEALED" = "false" ]; then
        log_success "✓ $pod successfully unsealed"
        ((UNSEALED_COUNT++))
    else
        log_error "✗ $pod is still sealed after unseal attempt"
        ((FAILED_COUNT++))
    fi
    
    echo ""
done

# Print summary
echo "============================================================"
echo "                    Unseal Summary"
echo "============================================================"
echo ""
echo "Total pods:          $POD_COUNT"
echo "Newly unsealed:      $UNSEALED_COUNT"
echo "Already unsealed:    $ALREADY_UNSEALED_COUNT"
echo "Failed:              $FAILED_COUNT"
echo ""

if [ $FAILED_COUNT -gt 0 ]; then
    log_error "Some pods failed to unseal"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check pod logs: $CLI logs -n $NAMESPACE <pod-name>"
    echo "  2. Verify pod is running: $CLI get pods -n $NAMESPACE"
    echo "  3. Check Vault status: $CLI exec -n $NAMESPACE <pod-name> -- vault status"
    echo "  4. Ensure Vault is initialized: $CLI get secret vault-unseal-keys -n $NAMESPACE"
    exit 1
elif [ $UNSEALED_COUNT -eq 0 ] && [ $ALREADY_UNSEALED_COUNT -eq 0 ]; then
    log_error "No pods were unsealed"
    exit 1
else
    log_success "All Vault pods are unsealed!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify Vault status: $CLI exec -n $NAMESPACE vault-0 -- vault status"
    echo "  2. Run validation: ./scripts/validate-secret-manager.sh -n $NAMESPACE"
    echo "  3. Access Vault UI: $CLI get route vault -n $NAMESPACE"
fi

# Made with Bob
