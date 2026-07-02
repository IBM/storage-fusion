#!/bin/bash
# Vault (Secret Manager) validation script
# Validates that HashiCorp Vault is deployed correctly and unsealed

set -e

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source common functions
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    # Fallback color definitions
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    
    log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
    log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
    log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    print_banner() { echo ""; echo "========================================"; echo "$1"; echo "========================================"; echo ""; }
fi

# Default values
NAMESPACE=""
VERBOSE=false
CHECK_CONNECTIVITY=false
EXIT_CODE=0

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate HashiCorp Vault deployment and unsealing status

OPTIONS:
    -n, --namespace NAMESPACE    Vault namespace (default: auto-detect or 'vault')
    -v, --verbose               Show detailed output
    -c, --connectivity          Test Vault API connectivity
    -h, --help                  Show this help message

EXAMPLES:
    # Validate Vault in default namespace
    $0

    # Validate with verbose output
    $0 -v

    # Validate specific namespace with connectivity test
    $0 -n vault-prod -c

EOF
    exit 1
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
        -c|--connectivity)
            CHECK_CONNECTIVITY=true
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

# Detect CLI
if command -v oc &> /dev/null; then
    CLI="oc"
    log_info "Using OpenShift CLI (oc)"
else
    CLI="kubectl"
    log_info "Using Kubernetes CLI (kubectl)"
fi

# Auto-detect namespace if not provided
if [ -z "$NAMESPACE" ]; then
    # Try to find Vault deployment
    for ns in vault openshift-vault hashicorp-vault; do
        if $CLI get namespace "$ns" &> /dev/null; then
            if $CLI get statefulset -n "$ns" -l app.kubernetes.io/name=vault &> /dev/null 2>&1; then
                NAMESPACE="$ns"
                log_info "Auto-detected Vault namespace: $NAMESPACE"
                break
            fi
        fi
    done
    
    # Fallback to default
    if [ -z "$NAMESPACE" ]; then
        NAMESPACE="vault"
        log_warning "Could not auto-detect namespace, using default: $NAMESPACE"
    fi
fi

# Verify namespace exists
if ! $CLI get namespace "$NAMESPACE" &> /dev/null; then
    log_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

print_banner "Vault Deployment Validation"
echo "Namespace: $NAMESPACE"
echo "Cluster: $($CLI config current-context 2>/dev/null || echo 'unknown')"
echo ""

# Track validation results
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Function to record check result
record_result() {
    local status=$1
    case $status in
        pass)
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            ;;
        fail)
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            EXIT_CODE=1
            ;;
        warn)
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
            ;;
    esac
}

# Check 1: Vault StatefulSet exists
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Checking Vault StatefulSet..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VAULT_STS=$($CLI get statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$VAULT_STS" ]; then
    log_error "✗ Vault StatefulSet not found"
    record_result fail
else
    log_success "✓ Vault StatefulSet found: $VAULT_STS"
    record_result pass
    
    # Get replica info
    DESIRED_REPLICAS=$($CLI get statefulset "$VAULT_STS" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    READY_REPLICAS=$($CLI get statefulset "$VAULT_STS" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [ "$VERBOSE" = true ]; then
        echo "  Desired replicas: $DESIRED_REPLICAS"
        echo "  Ready replicas: $READY_REPLICAS"
    fi
fi
echo ""

# Check 2: Vault Pods status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Checking Vault Pods..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VAULT_PODS=$($CLI get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$VAULT_PODS" ]; then
    log_error "✗ No Vault pods found"
    record_result fail
else
    POD_COUNT=$(echo "$VAULT_PODS" | wc -w | tr -d ' ')
    log_info "Found $POD_COUNT Vault pod(s)"
    
    ALL_RUNNING=true
    for pod in $VAULT_PODS; do
        POD_STATUS=$($CLI get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        POD_READY=$($CLI get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$POD_STATUS" = "Running" ] && [ "$POD_READY" = "True" ]; then
            log_success "✓ $pod: Running and Ready"
        elif [ "$POD_STATUS" = "Running" ]; then
            log_warning "⚠ $pod: Running but not Ready"
            ALL_RUNNING=false
        else
            log_error "✗ $pod: $POD_STATUS"
            ALL_RUNNING=false
        fi
        
        if [ "$VERBOSE" = true ]; then
            echo "  Status: $POD_STATUS, Ready: $POD_READY"
        fi
    done
    
    if [ "$ALL_RUNNING" = true ]; then
        record_result pass
    else
        record_result fail
    fi
fi
echo ""

# Check 3: Vault Services
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Checking Vault Services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VAULT_SVC=$($CLI get svc -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$VAULT_SVC" ]; then
    log_error "✗ No Vault services found"
    record_result fail
else
    for svc in $VAULT_SVC; do
        SVC_TYPE=$($CLI get svc "$svc" -n "$NAMESPACE" -o jsonpath='{.spec.type}' 2>/dev/null)
        SVC_PORT=$($CLI get svc "$svc" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
        log_success "✓ Service: $svc (Type: $SVC_TYPE, Port: $SVC_PORT)"
    done
    record_result pass
fi
echo ""

# Check 4: Vault initialization status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Checking Vault Initialization Status..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$VAULT_PODS" ]; then
    FIRST_POD=$(echo "$VAULT_PODS" | awk '{print $1}')
    
    # Check if vault CLI is available in pod
    if $CLI exec -n "$NAMESPACE" "$FIRST_POD" -- which vault &> /dev/null; then
        VAULT_STATUS=$($CLI exec -n "$NAMESPACE" "$FIRST_POD" -- vault status -format=json 2>/dev/null || echo "{}")
        
        if [ "$VAULT_STATUS" != "{}" ]; then
            INITIALIZED=$(echo "$VAULT_STATUS" | grep -o '"initialized":[^,}]*' | cut -d':' -f2 | tr -d ' ')
            SEALED=$(echo "$VAULT_STATUS" | grep -o '"sealed":[^,}]*' | cut -d':' -f2 | tr -d ' ')
            
            if [ "$INITIALIZED" = "true" ]; then
                log_success "✓ Vault is initialized"
                record_result pass
            else
                log_error "✗ Vault is NOT initialized"
                record_result fail
            fi
            
            if [ "$VERBOSE" = true ]; then
                echo "  Initialized: $INITIALIZED"
                echo "  Sealed: $SEALED"
            fi
        else
            log_warning "⚠ Could not retrieve Vault status"
            record_result warn
        fi
    else
        log_warning "⚠ Vault CLI not available in pod"
        record_result warn
    fi
else
    log_error "✗ No pods available to check initialization"
    record_result fail
fi
echo ""

# Check 5: Vault seal status (most important check)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. Checking Vault Seal Status..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$VAULT_PODS" ]; then
    ALL_UNSEALED=true
    
    for pod in $VAULT_PODS; do
        if $CLI exec -n "$NAMESPACE" "$pod" -- which vault &> /dev/null; then
            VAULT_STATUS=$($CLI exec -n "$NAMESPACE" "$pod" -- vault status -format=json 2>/dev/null || echo "{}")
            
            if [ "$VAULT_STATUS" != "{}" ]; then
                SEALED=$(echo "$VAULT_STATUS" | grep -o '"sealed":[^,}]*' | cut -d':' -f2 | tr -d ' ')
                
                if [ "$SEALED" = "false" ]; then
                    log_success "✓ $pod: UNSEALED"
                else
                    log_error "✗ $pod: SEALED"
                    ALL_UNSEALED=false
                fi
                
                if [ "$VERBOSE" = true ]; then
                    SEAL_TYPE=$(echo "$VAULT_STATUS" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
                    VERSION=$(echo "$VAULT_STATUS" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
                    echo "  Seal Type: $SEAL_TYPE"
                    echo "  Version: $VERSION"
                fi
            else
                log_warning "⚠ $pod: Could not retrieve status"
                ALL_UNSEALED=false
            fi
        else
            log_warning "⚠ $pod: Vault CLI not available"
            ALL_UNSEALED=false
        fi
    done
    
    if [ "$ALL_UNSEALED" = true ]; then
        record_result pass
    else
        record_result fail
    fi
else
    log_error "✗ No pods available to check seal status"
    record_result fail
fi
echo ""

# Check 6: Unseal keys secret
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. Checking Unseal Keys Secret..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if $CLI get secret vault-unseal-keys -n "$NAMESPACE" &> /dev/null; then
    log_success "✓ Unseal keys secret exists"
    record_result pass
    
    if [ "$VERBOSE" = true ]; then
        KEYS=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data}' 2>/dev/null | grep -o '"key[0-9]"' | wc -l | tr -d ' ')
        HAS_TOKEN=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data.root-token}' 2>/dev/null)
        echo "  Number of unseal keys: $KEYS"
        if [ -n "$HAS_TOKEN" ]; then
            echo "  Root token: Present"
        else
            echo "  Root token: Missing"
        fi
    fi
else
    log_error "✗ Unseal keys secret not found"
    log_warning "  This is critical - you may not be able to unseal Vault after restart"
    record_result fail
fi
echo ""

# Check 7: Storage (PVCs)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. Checking Vault Storage..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VAULT_PVCS=$($CLI get pvc -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$VAULT_PVCS" ]; then
    log_warning "⚠ No Vault PVCs found"
    record_result warn
else
    ALL_BOUND=true
    for pvc in $VAULT_PVCS; do
        PVC_STATUS=$($CLI get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
        PVC_SIZE=$($CLI get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
        
        if [ "$PVC_STATUS" = "Bound" ]; then
            log_success "✓ $pvc: Bound ($PVC_SIZE)"
        else
            log_error "✗ $pvc: $PVC_STATUS"
            ALL_BOUND=false
        fi
    done
    
    if [ "$ALL_BOUND" = true ]; then
        record_result pass
    else
        record_result fail
    fi
fi
echo ""

# Check 8: Vault Route/Ingress (if applicable)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8. Checking Vault Route/Ingress..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$CLI" = "oc" ]; then
    VAULT_ROUTE=$($CLI get route -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")
    
    if [ -n "$VAULT_ROUTE" ]; then
        log_success "✓ Vault route found: https://$VAULT_ROUTE"
        record_result pass
    else
        log_warning "⚠ No Vault route found (not required for internal access)"
        record_result warn
    fi
else
    VAULT_INGRESS=$($CLI get ingress -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    
    if [ -n "$VAULT_INGRESS" ]; then
        log_success "✓ Vault ingress found: https://$VAULT_INGRESS"
        record_result pass
    else
        log_warning "⚠ No Vault ingress found (not required for internal access)"
        record_result warn
    fi
fi
echo ""

# Check 9: Pod Logs Validation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "9. Checking Pod Logs for Errors..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$VAULT_PODS" ]; then
    ALL_LOGS_CLEAN=true
    
    for pod in $VAULT_PODS; do
        echo "Checking logs for $pod..."
        
        # Get recent logs (last 50 lines)
        POD_LOGS=$($CLI logs -n "$NAMESPACE" "$pod" --tail=50 2>/dev/null || echo "")
        
        if [ -z "$POD_LOGS" ]; then
            log_warning "⚠ $pod: Could not retrieve logs"
            ALL_LOGS_CLEAN=false
            continue
        fi
        
        # Check for RBAC/403 errors
        RBAC_ERRORS=$(echo "$POD_LOGS" | grep -c "statuscode: 403" 2>/dev/null | tr -d '\n' || echo "0")
        if [ "$RBAC_ERRORS" -gt 0 ]; then
            log_error "✗ $pod: Found $RBAC_ERRORS RBAC permission errors (403)"
            if [ "$VERBOSE" = true ]; then
                echo "  Sample error:"
                echo "$POD_LOGS" | grep "statuscode: 403" | head -1 | sed 's/^/    /'
            fi
            ALL_LOGS_CLEAN=false
        fi
        
        # Check for service registration errors
        SERVICE_REG_ERRORS=$(echo "$POD_LOGS" | grep -c "service_registration.kubernetes.*unable to set initial state" 2>/dev/null | tr -d '\n' || echo "0")
        if [ "$SERVICE_REG_ERRORS" -gt 0 ]; then
            log_error "✗ $pod: Found $SERVICE_REG_ERRORS service registration errors"
            if [ "$VERBOSE" = true ]; then
                echo "  Sample error:"
                echo "$POD_LOGS" | grep "service_registration.kubernetes.*unable" | head -1 | sed 's/^/    /'
            fi
            ALL_LOGS_CLEAN=false
        fi
        
        # Check for Raft bootstrap errors
        RAFT_ERRORS=$(echo "$POD_LOGS" | grep -c "failed to retry join raft cluster" 2>/dev/null | tr -d '\n' || echo "0")
        if [ "$RAFT_ERRORS" -gt 0 ]; then
            log_warning "⚠ $pod: Found $RAFT_ERRORS Raft cluster join errors"
            if [ "$VERBOSE" = true ]; then
                echo "  Sample error:"
                echo "$POD_LOGS" | grep "failed to retry join raft cluster" | head -1 | sed 's/^/    /'
            fi
        fi
        
        # Check for successful service registration
        SERVICE_REG_SUCCESS=$(echo "$POD_LOGS" | grep -c "service_registration.kubernetes.*successfully" 2>/dev/null | tr -d '\n' || echo "0")
        if [ "$SERVICE_REG_SUCCESS" -gt 0 ]; then
            log_success "✓ $pod: Service registration successful"
        fi
        
        # Check if pod is initialized
        if echo "$POD_LOGS" | grep -q "core: security barrier not initialized"; then
            log_info "  $pod: Not yet initialized (expected before first init)"
        fi
        
        # Check if pod is sealed
        if echo "$POD_LOGS" | grep -q "core: vault is sealed"; then
            log_info "  $pod: Sealed (expected before unsealing)"
        fi
    done
    
    if [ "$ALL_LOGS_CLEAN" = true ]; then
        log_success "✓ No critical errors found in pod logs"
        record_result pass
    else
        log_error "✗ Found errors in pod logs"
        log_info "  Common fixes:"
        echo "    - RBAC errors: Ensure ServiceAccount has pod/service permissions"
        echo "    - Service registration: Check RBAC and network policies"
        echo "    - Raft errors: Ensure vault-0 is initialized first"
        record_result fail
    fi
else
    log_error "✗ No pods available to check logs"
    record_result fail
fi
echo ""

# Check 10: API Connectivity (optional)
if [ "$CHECK_CONNECTIVITY" = true ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "9. Testing Vault API Connectivity..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -n "$VAULT_PODS" ]; then
        FIRST_POD=$(echo "$VAULT_PODS" | awk '{print $1}')
        
        # Test health endpoint
        HEALTH_CHECK=$($CLI exec -n "$NAMESPACE" "$FIRST_POD" -- wget -q -O- http://127.0.0.1:8200/v1/sys/health 2>/dev/null || echo "")
        
        if [ -n "$HEALTH_CHECK" ]; then
            log_success "✓ Vault API is responding"
            record_result pass
            
            if [ "$VERBOSE" = true ]; then
                echo "$HEALTH_CHECK" | head -c 200
                echo ""
            fi
        else
            log_error "✗ Vault API is not responding"
            record_result fail
        fi
    else
        log_error "✗ No pods available to test connectivity"
        record_result fail
    fi
    echo ""
fi

# Check 10: Vault Configuration Validation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "10. Validating Vault Configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$VAULT_PODS" ]; then
    CONFIG_VALID=true
    
    for pod in $VAULT_PODS; do
        echo "Checking configuration for $pod..."
        
        # Check if vault.hcl exists and is readable
        VAULT_CONFIG=$($CLI exec -n "$NAMESPACE" "$pod" -- cat /vault/config/vault.hcl 2>/dev/null || echo "")
        
        if [ -z "$VAULT_CONFIG" ]; then
            log_error "✗ $pod: Could not read vault.hcl configuration"
            CONFIG_VALID=false
            continue
        fi
        
        # Check node_id configuration
        NODE_ID=$(echo "$VAULT_CONFIG" | grep "node_id" | sed 's/.*node_id.*=.*"\(.*\)".*/\1/' | tr -d ' ')
        if [ -n "$NODE_ID" ]; then
            # Check if node_id contains unexpanded variables
            if echo "$NODE_ID" | grep -q '\$'; then
                log_error "✗ $pod: node_id contains unexpanded variable: $NODE_ID"
                log_info "  Expected: Actual pod name (e.g., vault-0)"
                CONFIG_VALID=false
            elif [ "$NODE_ID" = "$pod" ]; then
                log_success "✓ $pod: node_id correctly set to '$NODE_ID'"
            else
                log_warning "⚠ $pod: node_id is '$NODE_ID' (expected '$pod')"
            fi
        else
            log_error "✗ $pod: node_id not found in configuration"
            CONFIG_VALID=false
        fi
        
        # Check cluster_address configuration
        if echo "$VAULT_CONFIG" | grep -q "cluster_address.*8201"; then
            log_success "✓ $pod: cluster_address configured for Raft (port 8201)"
        else
            log_error "✗ $pod: cluster_address not properly configured"
            CONFIG_VALID=false
        fi
        
        # Check retry_join configuration
        if echo "$VAULT_CONFIG" | grep -q "retry_join"; then
            log_success "✓ $pod: retry_join configured for multi-replica support"
        else
            log_warning "⚠ $pod: retry_join not found (single replica only)"
        fi
    done
    
    if [ "$CONFIG_VALID" = true ]; then
        log_success "✓ Vault configuration is valid"
        record_result pass
    else
        log_error "✗ Vault configuration has issues"
        log_info "  Run: ./scripts/diagnose-vault-raft.sh -n $NAMESPACE"
        record_result fail
    fi
else
    log_error "✗ No pods available to check configuration"
    record_result fail
fi
echo ""

# Check 11: Raft Cluster Status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "11. Checking Raft Cluster Status..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$VAULT_PODS" ]; then
    RAFT_HEALTHY=true
    FIRST_POD=$(echo "$VAULT_PODS" | awk '{print $1}')
    
    # Check if vault is unsealed first
    VAULT_STATUS=$($CLI exec -n "$NAMESPACE" "$FIRST_POD" -- vault status -format=json 2>/dev/null || echo "")
    
    if [ -n "$VAULT_STATUS" ]; then
        IS_SEALED=$(echo "$VAULT_STATUS" | grep -o '"sealed":[^,]*' | cut -d':' -f2 | tr -d ' ')
        
        if [ "$IS_SEALED" = "false" ]; then
            # Get root token
            ROOT_TOKEN=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            
            if [ -n "$ROOT_TOKEN" ]; then
                # Get Raft peers
                RAFT_PEERS=$($CLI exec -n "$NAMESPACE" "$FIRST_POD" -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault operator raft list-peers -format=json" 2>/dev/null || echo "")
                
                if [ -n "$RAFT_PEERS" ]; then
                    # Count peers (look for node_id in nested structure)
                    PEER_COUNT=$(echo "$RAFT_PEERS" | grep -o '"node_id"' | wc -l | tr -d ' ')
                    log_info "  Raft cluster has $PEER_COUNT peer(s)"
                    
                    # Check for variable strings in node IDs
                    if echo "$RAFT_PEERS" | grep -q '\$'; then
                        log_error "✗ Raft peers contain unexpanded variables"
                        log_info "  This indicates configuration issue with node_id"
                        RAFT_HEALTHY=false
                    else
                        log_success "✓ Raft peer node IDs are properly configured"
                    fi
                    
                    # Check for leader (handle nested JSON structure)
                    if echo "$RAFT_PEERS" | grep -q '"leader": true'; then
                        # Try Python first for reliable JSON parsing
                        if command -v python3 &> /dev/null; then
                            LEADER_ID=$(echo "$RAFT_PEERS" | python3 -c "import sys, json; data=json.load(sys.stdin); servers=[s for s in data['data']['config']['servers'] if s.get('leader')]; print(servers[0]['node_id'] if servers else '')" 2>/dev/null || echo "")
                        fi
                        
                        # Fallback to grep/sed if Python fails
                        if [ -z "$LEADER_ID" ]; then
                            LEADER_ID=$(echo "$RAFT_PEERS" | grep -o '"node_id": "[^"]*"' | head -1 | sed 's/"node_id": "\([^"]*\)"/\1/')
                        fi
                        
                        if [ -n "$LEADER_ID" ]; then
                            log_success "✓ Raft cluster has a leader: $LEADER_ID"
                        else
                            log_success "✓ Raft cluster has a leader"
                        fi
                    else
                        log_error "✗ No Raft leader found"
                        RAFT_HEALTHY=false
                    fi
                    
                    if [ "$VERBOSE" = true ]; then
                        echo "  Raft peers:"
                        echo "$RAFT_PEERS" | grep -E '"id"|"address"|"leader"' | sed 's/^/    /'
                    fi
                else
                    log_warning "⚠ Could not retrieve Raft peers (may need authentication)"
                fi
            else
                log_warning "⚠ Root token not available, skipping Raft peer check"
            fi
        else
            log_info "  Vault is sealed, skipping Raft cluster check"
        fi
    else
        log_warning "⚠ Could not get Vault status"
    fi
    
    if [ "$RAFT_HEALTHY" = true ]; then
        record_result pass
    else
        record_result fail
    fi
else
    log_error "✗ No pods available to check Raft status"
    record_result fail
fi
echo ""

# Check 12: Init Container Validation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "12. Checking Init Container Status..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$VAULT_PODS" ]; then
    INIT_HEALTHY=true
    
    for pod in $VAULT_PODS; do
        # Check if init container exists
        INIT_CONTAINERS=$($CLI get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null || echo "")
        
        if echo "$INIT_CONTAINERS" | grep -q "config-init"; then
            # Check init container status
            INIT_STATUS=$($CLI get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.initContainerStatuses[?(@.name=="config-init")].state}' 2>/dev/null || echo "")
            
            if echo "$INIT_STATUS" | grep -q "terminated"; then
                # Check exit code
                EXIT_CODE=$($CLI get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.initContainerStatuses[?(@.name=="config-init")].state.terminated.exitCode}' 2>/dev/null || echo "")
                
                if [ "$EXIT_CODE" = "0" ]; then
                    log_success "✓ $pod: config-init container completed successfully"
                else
                    log_error "✗ $pod: config-init container failed with exit code $EXIT_CODE"
                    INIT_HEALTHY=false
                    
                    if [ "$VERBOSE" = true ]; then
                        echo "  Init container logs:"
                        $CLI logs "$pod" -n "$NAMESPACE" -c config-init 2>/dev/null | tail -10 | sed 's/^/    /'
                    fi
                fi
            else
                log_warning "⚠ $pod: config-init container status: $INIT_STATUS"
            fi
        else
            log_info "  $pod: No config-init container (using ConfigMap)"
        fi
    done
    
    if [ "$INIT_HEALTHY" = true ]; then
        record_result pass
    else
        record_result fail
    fi
else
    log_error "✗ No pods available to check init containers"
    record_result fail
fi
echo ""

# Summary
print_banner "Validation Summary"

echo "Checks Passed:   $CHECKS_PASSED"
echo "Checks Failed:   $CHECKS_FAILED"
echo "Checks Warning:  $CHECKS_WARNING"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    log_success "✓ All critical checks passed!"
    echo ""
    log_info "Vault is deployed and unsealed successfully"
    echo ""
    log_info "To access Vault:"
    echo "  1. Get root token:"
    echo "     $CLI get secret vault-unseal-keys -n $NAMESPACE -o jsonpath='{.data.root-token}' | base64 -d"
    echo ""
    echo "  2. Port-forward to Vault:"
    echo "     $CLI port-forward -n $NAMESPACE svc/vault 8200:8200"
    echo ""
    echo "  3. Access Vault UI:"
    echo "     http://localhost:8200"
else
    log_error "✗ Validation failed with $CHECKS_FAILED error(s)"
    echo ""
    log_info "Troubleshooting steps:"
    echo "  1. Check pod logs:"
    echo "     $CLI logs -n $NAMESPACE vault-0"
    echo ""
    echo "  2. Check pod events:"
    echo "     $CLI describe pod -n $NAMESPACE vault-0"
    echo ""
    echo "  3. Re-initialize Vault (if needed):"
    echo "     ansible-playbook ansible/playbooks/initialize-vault.yml -e vault_namespace=$NAMESPACE"
fi

echo ""
exit $EXIT_CODE

# Made with Bob