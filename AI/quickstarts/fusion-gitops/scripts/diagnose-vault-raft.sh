#!/bin/bash
# Vault Raft Cluster Diagnostic Script
# Diagnoses common Raft join failures for multi-replica Vault deployments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=""
VERBOSE=false

# Function to print colored output
print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 -n NAMESPACE [OPTIONS]

Diagnose Vault Raft cluster join issues

OPTIONS:
    -n, --namespace NAMESPACE   Vault namespace (required)
    -v, --verbose              Enable verbose output
    -h, --help                 Show this help message

EXAMPLES:
    # Diagnose Vault in vault2 namespace
    $0 -n vault2

    # Verbose diagnostics
    $0 -n vault2 --verbose

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
if [ -z "$NAMESPACE" ]; then
    print_error "Namespace is required"
    usage
fi

# Detect CLI tool
if command -v oc &> /dev/null; then
    CLI="oc"
elif command -v kubectl &> /dev/null; then
    CLI="kubectl"
else
    print_error "Neither 'oc' nor 'kubectl' found. Please install one of them."
    exit 1
fi

print_header "Vault Raft Cluster Diagnostics"
echo "Namespace: $NAMESPACE"
echo "CLI Tool: $CLI"
echo ""

# Test 1: Check Pod Status
print_header "1. Pod Status Check"
print_test "Checking Vault pod status..."
echo ""

PODS=$($CLI get pods -n $NAMESPACE -l app.kubernetes.io/name=vault -o name 2>/dev/null || echo "")
if [ -z "$PODS" ]; then
    print_error "No Vault pods found in namespace $NAMESPACE"
    exit 1
fi

$CLI get pods -n $NAMESPACE -l app.kubernetes.io/name=vault -o wide
echo ""

# Count pods and get pod names
POD_COUNT=$($CLI get pods -n $NAMESPACE -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | wc -l)
VAULT_PODS=$($CLI get pods -n $NAMESPACE -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
READY_COUNT=$($CLI get pods -n $NAMESPACE -l app.kubernetes.io/name=vault --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")

echo "Total Pods: $POD_COUNT"
echo "Ready Pods: $READY_COUNT"

if [ "$READY_COUNT" -lt "$POD_COUNT" ]; then
    print_warn "Not all pods are ready"
else
    print_info "All pods are ready"
fi

# Test 2: Check vault-0 Status
print_header "2. Leader (vault-0) Status Check"
print_test "Checking vault-0 initialization and seal status..."
echo ""

if $CLI get pod vault-0 -n $NAMESPACE &>/dev/null; then
    VAULT_0_STATUS=$($CLI exec -n $NAMESPACE vault-0 -- vault status -format=json 2>/dev/null || echo "{}")
    
    if [ "$VAULT_0_STATUS" != "{}" ]; then
        INITIALIZED=$(echo "$VAULT_0_STATUS" | grep -o '"initialized":[^,]*' | cut -d':' -f2 | tr -d ' ')
        SEALED=$(echo "$VAULT_0_STATUS" | grep -o '"sealed":[^,]*' | cut -d':' -f2 | tr -d ' ')
        
        echo "Initialized: $INITIALIZED"
        echo "Sealed: $SEALED"
        echo ""
        
        if [ "$INITIALIZED" = "true" ]; then
            print_info "vault-0 is initialized"
        else
            print_error "vault-0 is NOT initialized - this must be fixed first"
            exit 1
        fi
        
        if [ "$SEALED" = "false" ]; then
            print_info "vault-0 is unsealed"
        else
            print_error "vault-0 is sealed - unseal it first"
            exit 1
        fi
        
        # Check Raft peers
        echo ""
        print_test "Checking Raft cluster members..."
        $CLI exec -n $NAMESPACE vault-0 -- vault operator raft list-peers 2>/dev/null || print_warn "Could not list Raft peers"
    else
        print_error "Could not get vault-0 status"
    fi
else
    print_error "vault-0 pod not found"
    exit 1
fi

# Test 3: Check Vault Configuration
print_header "3. Vault Configuration Check"
print_test "Verifying Vault configuration in all pods..."
echo ""

for pod in $(seq 0 $((POD_COUNT - 1))); do
    POD_NAME="vault-$pod"
    
    if ! $CLI get pod $POD_NAME -n $NAMESPACE &>/dev/null; then
        print_warn "$POD_NAME does not exist"
        continue
    fi
    
    echo "─────────────────────────────────────────"
    echo "Pod: $POD_NAME"
    echo "─────────────────────────────────────────"
    
    # Get config
    CONFIG=$($CLI exec -n $NAMESPACE $POD_NAME -- cat /vault/config/vault.hcl 2>/dev/null || echo "")
    
    if [ -z "$CONFIG" ]; then
        print_error "Could not read config from $POD_NAME"
        continue
    fi
    
    # Check node_id
    NODE_ID=$(echo "$CONFIG" | grep "node_id" | head -1)
    if echo "$NODE_ID" | grep -q "VAULT_K8S_POD_NAME"; then
        print_info "node_id uses pod name variable"
    else
        print_error "node_id is NOT using pod name: $NODE_ID"
    fi
    
    # Check retry_join
    RETRY_JOIN=$(echo "$CONFIG" | grep -A2 "retry_join" | grep "leader_api_addr")
    if [ -n "$RETRY_JOIN" ]; then
        print_info "retry_join configured: $RETRY_JOIN"
        
        # Extract leader address
        LEADER_ADDR=$(echo "$RETRY_JOIN" | sed 's/.*"\(.*\)".*/\1/')
        echo "  Leader address: $LEADER_ADDR"
    else
        print_error "retry_join NOT found in config"
    fi
    
    # Check service_registration
    SERVICE_REG=$(echo "$CONFIG" | grep -A2 "service_registration")
    if [ -n "$SERVICE_REG" ]; then
        print_info "service_registration configured"
    else
        print_warn "service_registration not found"
    fi
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "Full config:"
        echo "$CONFIG"
    fi
    
    echo ""
done

# Test 4: DNS Resolution Test
print_header "4. DNS Resolution Test"
print_test "Testing DNS resolution from follower pods..."
echo ""

for pod in $(seq 1 $((POD_COUNT - 1))); do
    POD_NAME="vault-$pod"
    
    if ! $CLI get pod $POD_NAME -n $NAMESPACE &>/dev/null; then
        continue
    fi
    
    echo "Testing from $POD_NAME:"
    
    # Test vault-0 DNS
    LEADER_DNS="vault-0.vault-internal.$NAMESPACE.svc.cluster.local"
    print_test "  Resolving $LEADER_DNS..."
    
    if $CLI exec -n $NAMESPACE $POD_NAME -- nslookup $LEADER_DNS &>/dev/null; then
        print_info "  DNS resolution successful"
    else
        print_error "  DNS resolution FAILED"
    fi
    
    # Test HTTP connectivity
    print_test "  Testing HTTP connectivity to vault-0..."
    HTTP_TEST=$($CLI exec -n $NAMESPACE $POD_NAME -- curl -s -o /dev/null -w "%{http_code}" http://vault-0.vault-internal.$NAMESPACE.svc.cluster.local:8200/v1/sys/health 2>/dev/null || echo "000")
    
    if [ "$HTTP_TEST" != "000" ]; then
        print_info "  HTTP connectivity successful (status: $HTTP_TEST)"
    else
        print_error "  HTTP connectivity FAILED"
    fi
    
    echo ""
done

# Test 5: Check PVCs
print_header "5. Persistent Volume Claims Check"
print_test "Checking PVC status..."
echo ""

$CLI get pvc -n $NAMESPACE -l app.kubernetes.io/name=vault
echo ""

BOUND_PVCS=$($CLI get pvc -n $NAMESPACE -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
echo "Bound PVCs: $BOUND_PVCS / $POD_COUNT"

if [ "$BOUND_PVCS" -eq "$POD_COUNT" ]; then
    print_info "All PVCs are bound"
else
    print_error "Not all PVCs are bound - storage issue detected"
fi

# Test 6: Check Raft Data Directory
print_header "6. Raft Data Directory Check"
print_test "Checking Raft data directory in each pod..."
echo ""

for pod in $(seq 0 $((POD_COUNT - 1))); do
    POD_NAME="vault-$pod"
    
    if ! $CLI get pod $POD_NAME -n $NAMESPACE &>/dev/null; then
        continue
    fi
    
    echo "Pod: $POD_NAME"
    
    # Check if data directory exists and has content
    DATA_CHECK=$($CLI exec -n $NAMESPACE $POD_NAME -- ls -la /vault/data 2>/dev/null || echo "ERROR")
    
    if [ "$DATA_CHECK" = "ERROR" ]; then
        print_error "  Cannot access /vault/data"
    else
        FILE_COUNT=$(echo "$DATA_CHECK" | wc -l)
        if [ "$FILE_COUNT" -gt 3 ]; then
            print_info "  Raft data directory has content ($FILE_COUNT entries)"
        else
            print_warn "  Raft data directory appears empty"
            if [ "$VERBOSE" = true ]; then
                echo "$DATA_CHECK"
            fi
        fi
    fi
    echo ""
done

# Test 7: Check Recent Logs
print_header "7. Recent Pod Logs Analysis"
print_test "Analyzing recent logs for errors..."
echo ""

for pod in $(seq 0 $((POD_COUNT - 1))); do
    POD_NAME="vault-$pod"
    
    if ! $CLI get pod $POD_NAME -n $NAMESPACE &>/dev/null; then
        continue
    fi
    
    echo "─────────────────────────────────────────"
    echo "Pod: $POD_NAME"
    echo "─────────────────────────────────────────"
    
    LOGS=$($CLI logs $POD_NAME -n $NAMESPACE --tail=50 2>/dev/null || echo "")
    
    # Check for specific error patterns
    if echo "$LOGS" | grep -q "security barrier not initialized"; then
        print_error "  Found: 'security barrier not initialized' - Raft join failure"
    fi
    
    if echo "$LOGS" | grep -q "failed to retry join raft cluster"; then
        print_error "  Found: 'failed to retry join raft cluster'"
        ERROR_MSG=$(echo "$LOGS" | grep "failed to retry join raft cluster" | tail -1)
        echo "    $ERROR_MSG"
    fi
    
    if echo "$LOGS" | grep -q "connection refused"; then
        print_error "  Found: 'connection refused' - Network connectivity issue"
    fi
    
    if echo "$LOGS" | grep -q "no such host"; then
        print_error "  Found: 'no such host' - DNS resolution issue"
    fi
    
    if echo "$LOGS" | grep -q "TLS handshake"; then
        print_error "  Found: TLS handshake errors"
    fi
    
    if echo "$LOGS" | grep -q "successfully joined"; then
        print_info "  Found: 'successfully joined' - Raft join was successful"
    fi
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "Last 20 lines:"
        echo "$LOGS" | tail -20
    fi
    
    echo ""
done

# Check 8: Vault Configuration File Analysis
print_header "8. Vault Configuration File Analysis"

echo ""
for pod in $VAULT_PODS; do
    echo "Analyzing configuration for $pod..."
    
    # Get vault.hcl content
    VAULT_CONFIG=$($CLI exec -n "$NAMESPACE" "$pod" -- cat /vault/config/vault.hcl 2>/dev/null || echo "")
    
    if [ -z "$VAULT_CONFIG" ]; then
        print_error "  Could not read vault.hcl"
        continue
    fi
    
    # Check node_id
    NODE_ID=$(echo "$VAULT_CONFIG" | grep "node_id" | sed 's/.*node_id.*=.*"\(.*\)".*/\1/' | tr -d ' ')
    if [ -n "$NODE_ID" ]; then
        if echo "$NODE_ID" | grep -q '\$'; then
            print_error "  node_id contains unexpanded variable: $NODE_ID"
            echo "    ❌ CRITICAL: Environment variable not expanded!"
            echo "    Expected: Actual pod name (e.g., vault-0)"
            echo "    Fix: Check init container or ConfigMap generation"
        elif [ "$NODE_ID" = "$pod" ]; then
            print_info "  node_id: $NODE_ID ✓"
        else
            print_warn "  node_id: $NODE_ID (expected: $pod)"
        fi
    else
        print_error "  node_id not found in configuration"
    fi
    
    # Check cluster_address
    CLUSTER_ADDR=$(echo "$VAULT_CONFIG" | grep "cluster_address" | sed 's/.*cluster_address.*=.*"\(.*\)".*/\1/' | tr -d ' ')
    if [ -n "$CLUSTER_ADDR" ]; then
        if echo "$CLUSTER_ADDR" | grep -q "8201"; then
            print_info "  cluster_address: $CLUSTER_ADDR ✓"
        else
            print_warn "  cluster_address: $CLUSTER_ADDR (should include port 8201)"
        fi
    else
        print_error "  cluster_address not found (required for Raft)"
    fi
    
    # Check retry_join
    RETRY_JOIN=$(echo "$VAULT_CONFIG" | grep -A2 "retry_join" | grep "leader_api_addr" | sed 's/.*leader_api_addr.*=.*"\(.*\)".*/\1/' | tr -d ' ')
    if [ -n "$RETRY_JOIN" ]; then
        print_info "  retry_join: $RETRY_JOIN ✓"
    else
        print_warn "  retry_join not configured (single replica only)"
    fi
    
    # Check service_registration pod_name
    POD_NAME_CONFIG=$(echo "$VAULT_CONFIG" | grep "pod_name" | sed 's/.*pod_name.*=.*"\(.*\)".*/\1/' | tr -d ' ')
    if [ -n "$POD_NAME_CONFIG" ]; then
        if echo "$POD_NAME_CONFIG" | grep -q '\$'; then
            print_error "  pod_name contains unexpanded variable: $POD_NAME_CONFIG"
        elif [ "$POD_NAME_CONFIG" = "$pod" ]; then
            print_info "  pod_name: $POD_NAME_CONFIG ✓"
        else
            print_warn "  pod_name: $POD_NAME_CONFIG (expected: $pod)"
        fi
    fi
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "  Full configuration:"
        echo "$VAULT_CONFIG" | sed 's/^/    /'
    fi
    
    echo ""
done

# Check 9: Init Container Status
print_header "9. Init Container Status"

echo ""
for pod in $VAULT_PODS; do
    echo "Checking init containers for $pod..."
    
    # Get init container names
    INIT_CONTAINERS=$($CLI get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null || echo "")
    
    if [ -z "$INIT_CONTAINERS" ]; then
        print_info "  No init containers (using ConfigMap directly)"
    else
        echo "  Init containers: $INIT_CONTAINERS"
        
        # Check config-init specifically
        if echo "$INIT_CONTAINERS" | grep -q "config-init"; then
            INIT_STATUS=$($CLI get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.initContainerStatuses[?(@.name=="config-init")].state}' 2>/dev/null || echo "")
            
            if echo "$INIT_STATUS" | grep -q "terminated"; then
                EXIT_CODE=$($CLI get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.initContainerStatuses[?(@.name=="config-init")].state.terminated.exitCode}' 2>/dev/null || echo "")
                
                if [ "$EXIT_CODE" = "0" ]; then
                    print_info "  config-init: Completed successfully (exit 0) ✓"
                else
                    print_error "  config-init: Failed with exit code $EXIT_CODE"
                    
                    # Get init container logs
                    INIT_LOGS=$($CLI logs "$pod" -n "$NAMESPACE" -c config-init 2>/dev/null || echo "")
                    if [ -n "$INIT_LOGS" ]; then
                        echo "  Init container logs:"
                        echo "$INIT_LOGS" | tail -10 | sed 's/^/    /'
                    fi
                fi
            else
                print_warn "  config-init: Status - $INIT_STATUS"
            fi
        fi
    fi
    
    echo ""
done

# Check 10: Raft Cluster Peer Analysis
print_header "10. Raft Cluster Peer Analysis"

echo ""
if [ -n "$VAULT_PODS" ]; then
    LEADER_POD=$(echo "$VAULT_PODS" | awk '{print $1}')
    echo "Querying Raft peers from $LEADER_POD..."

    # Check if vault is unsealed
    VAULT_STATUS=$($CLI exec -n "$NAMESPACE" "$LEADER_POD" -- vault status -format=json 2>/dev/null || echo "")
else
    print_error "No Vault pods found"
    VAULT_STATUS=""
fi

if [ -n "$VAULT_STATUS" ]; then
    IS_SEALED=$(echo "$VAULT_STATUS" | grep -o '"sealed":[^,]*' | cut -d':' -f2 | tr -d ' ')
    
    if [ "$IS_SEALED" = "false" ]; then
        # Try to get root token
        ROOT_TOKEN=$($CLI get secret vault-unseal-keys -n "$NAMESPACE" -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        
        if [ -n "$ROOT_TOKEN" ]; then
            RAFT_PEERS=$($CLI exec -n "$NAMESPACE" "$LEADER_POD" -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault operator raft list-peers -format=json" 2>/dev/null || echo "")
            
            if [ -n "$RAFT_PEERS" ]; then
                echo "Raft Peers:"
                echo "$RAFT_PEERS" | grep -E '"node_id"|"address"|"leader"|"voter"' | sed 's/^/  /'
                echo ""
                
                # Analyze peer IDs (check for unexpanded variables)
                if echo "$RAFT_PEERS" | grep -q '\$'; then
                    print_error "❌ CRITICAL: Peer IDs contain unexpanded variables!"
                    echo "  This indicates the node_id configuration issue"
                    echo "  Each peer should have actual pod name (vault-0, vault-1, etc.)"
                else
                    print_info "✓ Peer IDs are properly configured (no variables)"
                fi
                
                # Count peers (look for node_id in nested structure)
                PEER_COUNT=$(echo "$RAFT_PEERS" | grep -o '"node_id"' | wc -l | tr -d ' ')
                echo "  Total peers: $PEER_COUNT"
                
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
                        print_info "  Leader: $LEADER_ID ✓"
                    else
                        print_info "  Leader found ✓"
                    fi
                else
                    print_error "  No leader found in Raft cluster"
                fi
            else
                print_warn "Could not retrieve Raft peers"
            fi
        else
            print_warn "Root token not available, skipping Raft peer check"
        fi
    else
        print_info "Vault is sealed, skipping Raft peer check"
    fi
else
    print_warn "Could not get Vault status"
fi

echo ""

# Summary and Recommendations
print_header "11. Summary and Recommendations"

echo ""
echo "Based on the diagnostics above, here are the most likely issues:"
echo ""

print_test "Common Root Causes (in priority order):"
echo ""
echo "1️⃣  retry_join Configuration Issue"
echo "   - Check if retry_join points to correct leader address"
echo "   - Verify DNS name resolves: vault-0.vault-internal.$NAMESPACE.svc.cluster.local"
echo "   - Ensure protocol matches (http vs https)"
echo ""

echo "2️⃣  DNS Resolution Failure"
echo "   - Test: $CLI exec -n $NAMESPACE vault-1 -- nslookup vault-0.vault-internal.$NAMESPACE.svc.cluster.local"
echo "   - Check if vault-internal service exists"
echo "   - Verify network policies allow pod-to-pod communication"
echo ""

echo "3️⃣  Node ID Variable Not Expanded"
echo "   - CRITICAL: node_id contains literal \"\$(VAULT_K8S_POD_NAME)\" or \"\${VAULT_K8S_POD_NAME}\""
echo "   - Each pod must have actual pod name (vault-0, vault-1, etc.)"
echo "   - Fix: Use init container to generate config with proper variable expansion"
echo "   - Check: cat /vault/config/vault.hcl in each pod"
echo ""

echo "4️⃣  Empty Raft Data Directory"
echo "   - Followers start with empty /vault/data"
echo "   - They never successfully join the cluster"
echo "   - May need to delete PVCs and recreate"
echo ""

echo "5️⃣  TLS Certificate Issues (if using TLS)"
echo "   - Cert SANs must include pod DNS names"
echo "   - Check: $CLI exec -n $NAMESPACE vault-0 -- openssl x509 -in /vault/tls/tls.crt -text | grep -A1 'Subject Alternative'"
echo ""

print_header "Recommended Actions"
echo ""
echo "If followers cannot join:"
echo ""
echo "1. Scale down to 1 replica:"
echo "   $CLI scale sts vault --replicas=1 -n $NAMESPACE"
echo ""
echo "2. Delete follower PVCs:"
echo "   $CLI delete pvc data-vault-1 data-vault-2 -n $NAMESPACE"
echo ""
echo "3. Scale back up:"
echo "   $CLI scale sts vault --replicas=3 -n $NAMESPACE"
echo ""
echo "4. Unseal new followers:"
echo "   ./scripts/unseal-secret-manager.sh -n $NAMESPACE"
echo ""

print_info "Diagnostics complete!"

# Made with Bob
