#!/bin/bash
# Secret Manager (HashiCorp Vault) deployment script
# Deploys Vault operator and instance for secure secret management

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=""  # Will be set after detecting CLI
STORAGE_CLASS="ocs-storagecluster-ceph-rbd"
STORAGE_SIZE="10Gi"
REPLICAS=3
RELEASE_NAME="vault-operator"
VALUES_FILE=""
DRY_RUN=false

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

Deploy HashiCorp Vault operator and instance on OpenShift/Kubernetes

OPTIONS:
    -n, --namespace NAMESPACE       Vault namespace (default: current context namespace or 'vault')
    -s, --storage-class CLASS       Storage class name (default: ocs-storagecluster-ceph-rbd)
    -z, --size SIZE                 Storage size (default: 10Gi)
    -r, --replicas COUNT            Number of Vault replicas (default: 3)
    -f, --values-file FILE          Custom values file
    --release-name NAME             Helm release name (default: vault-operator)
    --dry-run                       Show what would be deployed without deploying
    -h, --help                      Show this help message

EXAMPLES:
    # Deploy with defaults
    $0

    # Deploy with custom storage class
    $0 --storage-class fusion-block-storage

    # Deploy with custom values file
    $0 -f my-values.yaml

    # Dry run to see what would be deployed
    $0 --dry-run

    # Deploy to custom namespace with 5 replicas
    $0 -n vault-prod -r 5 -z 20Gi

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
        -s|--storage-class)
            STORAGE_CLASS="$2"
            shift 2
            ;;
        -z|--size)
            STORAGE_SIZE="$2"
            shift 2
            ;;
        -r|--replicas)
            REPLICAS="$2"
            shift 2
            ;;
        -f|--values-file)
            VALUES_FILE="$2"
            shift 2
            ;;
        --release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
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

# Check if we're on OpenShift or Kubernetes
if command -v oc &> /dev/null; then
    CLI="oc"
    print_info "Detected OpenShift cluster"
else
    CLI="kubectl"
    print_info "Detected Kubernetes cluster"
fi

# Set default namespace if not provided
if [ -z "$NAMESPACE" ]; then
    # Try to get current namespace from context
    current_ns=""
    if [ "$CLI" = "oc" ]; then
        current_ns=$(oc project -q 2>/dev/null || echo "")
    else
        current_ns=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || echo "")
    fi
    
    # Use current namespace if available, otherwise default to vault
    if [ -n "$current_ns" ]; then
        NAMESPACE="$current_ns"
        print_info "Using current namespace: $NAMESPACE"
    else
        NAMESPACE="vault"
        print_info "Using default namespace: $NAMESPACE"
    fi
fi

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed. Please install Helm 3.x"
    exit 1
fi

print_info "Helm version: $(helm version --short)"

# Check if storage class exists
print_info "Checking if storage class '$STORAGE_CLASS' exists..."
if ! $CLI get storageclass "$STORAGE_CLASS" &> /dev/null; then
    print_error "Storage class '$STORAGE_CLASS' not found"
    print_info "Available storage classes:"
    $CLI get storageclass
    exit 1
fi
print_info "Storage class '$STORAGE_CLASS' found"

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Chart is in helm/vault-operator relative to script location
CHART_DIR="$SCRIPT_DIR/../helm/vault-operator"
PLAYBOOK_PATH="$SCRIPT_DIR/../ansible/playbooks/initialize-vault.yml"

# Check if chart exists
if [ ! -f "$CHART_DIR/Chart.yaml" ]; then
    print_error "Chart.yaml not found in $CHART_DIR"
    print_error "Expected chart at: $CHART_DIR"
    exit 1
fi

print_info "Found Vault operator chart at $CHART_DIR"

# Validate Vault configuration before deployment
print_info "Validating Vault configuration..."
CLUSTER_ADDR_CHECK=$(grep -c "cluster_address" "$CHART_DIR/templates/vault/vault-instance.yaml" || echo "0")

if [ "$CLUSTER_ADDR_CHECK" -eq 0 ]; then
    print_error "Vault listener configuration is missing 'cluster_address'"
    print_error "This will cause multi-replica deployments to fail"
    echo ""
    print_info "Required fix in $CHART_DIR/templates/vault/vault-instance.yaml:"
    echo ""
    echo "  listener \"tcp\" {"
    echo "    address         = \"0.0.0.0:8200\""
    echo "    cluster_address = \"0.0.0.0:8201\"  # ← ADD THIS LINE"
    echo "    tls_disable     = 1"
    echo "  }"
    echo ""
    
    if [ "$REPLICAS" -gt 1 ]; then
        print_error "Cannot proceed with multi-replica deployment without cluster_address"
        print_info "Please fix the Helm template and run the script again"
        exit 1
    else
        print_warn "Single replica deployment will work, but scaling later will fail"
    fi
else
    print_info "✓ cluster_address is configured"
fi

# Create namespace if it doesn't exist
if ! $CLI get namespace "$NAMESPACE" &> /dev/null; then
    print_info "Creating namespace '$NAMESPACE'..."
    $CLI create namespace "$NAMESPACE"
    print_info "Namespace '$NAMESPACE' created"
else
    print_info "Namespace '$NAMESPACE' already exists"
fi

# Store requested replicas for later scaling
REQUESTED_REPLICAS=$REPLICAS

# For multi-replica deployments, start with 1 replica
if [ "$REPLICAS" -gt 1 ]; then
    print_info "Multi-replica deployment requested ($REPLICAS replicas)"
    print_info "Using two-phase deployment: 1 replica → unseal → scale to $REPLICAS"
    INITIAL_REPLICAS=1
else
    INITIAL_REPLICAS=$REPLICAS
fi

# Build Helm command
HELM_CMD="helm install $RELEASE_NAME $CHART_DIR"
HELM_CMD="$HELM_CMD --namespace $NAMESPACE"
HELM_CMD="$HELM_CMD --set global.namespace=$NAMESPACE"
HELM_CMD="$HELM_CMD --set operator.namespace=$NAMESPACE"
HELM_CMD="$HELM_CMD --set vault.storage.storageClassName=$STORAGE_CLASS"
HELM_CMD="$HELM_CMD --set vault.storage.size=$STORAGE_SIZE"
HELM_CMD="$HELM_CMD --set vault.replicas=$INITIAL_REPLICAS"

# Add custom values file if provided
if [ -n "$VALUES_FILE" ]; then
    if [ ! -f "$VALUES_FILE" ]; then
        print_error "Values file not found: $VALUES_FILE"
        exit 1
    fi
    HELM_CMD="$HELM_CMD -f $VALUES_FILE"
    print_info "Using custom values file: $VALUES_FILE"
fi

# Add dry-run flag if requested
if [ "$DRY_RUN" = true ]; then
    HELM_CMD="$HELM_CMD --dry-run --debug"
    print_warn "DRY RUN MODE - No changes will be made"
fi

# Display deployment configuration
echo ""
print_info "Deployment Configuration:"
echo "  Release Name:    $RELEASE_NAME"
echo "  Namespace:       $NAMESPACE"
echo "  Storage Class:   $STORAGE_CLASS"
echo "  Storage Size:    $STORAGE_SIZE"
if [ "$REQUESTED_REPLICAS" -gt 1 ]; then
    echo "  Initial Replicas: $INITIAL_REPLICAS (will scale to $REQUESTED_REPLICAS after unsealing)"
else
    echo "  Replicas:        $REPLICAS"
fi
if [ -n "$VALUES_FILE" ]; then
    echo "  Values File:     $VALUES_FILE"
fi
echo ""

# Confirm deployment
if [ "$DRY_RUN" = false ]; then
    read -p "Do you want to proceed with the deployment? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_warn "Deployment cancelled"
        exit 0
    fi
fi

# Deploy
print_info "Deploying Vault operator..."
echo ""
eval $HELM_CMD

if [ "$DRY_RUN" = false ]; then
    echo ""
    print_info "Deployment initiated successfully!"
    echo ""
    
    # Wait for Vault pods to be running
    print_info "Waiting for Vault pods to be running..."
    for i in {1..60}; do
        RUNNING_PODS=$($CLI get pods -n $NAMESPACE -l app.kubernetes.io/name=vault --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [ "$RUNNING_PODS" -ge 1 ]; then
            print_info "Vault pod is running"
            break
        fi
        if [ $i -eq 60 ]; then
            print_error "Timeout waiting for Vault pods to start"
            print_warn "You can manually initialize Vault later using:"
            echo "  ansible-playbook ansible/playbooks/initialize-vault.yml -e vault_namespace=$NAMESPACE"
            exit 1
        fi
        sleep 5
    done
    
    # Wait additional time for Vault process to start inside the pod
    print_info "Waiting for Vault process to be ready (30 seconds)..."
    sleep 30
    
    # Verify Vault is responding
    print_info "Verifying Vault is responding..."
        for i in {1..12}; do
        if $CLI exec -n $NAMESPACE vault-0 -- vault status 2>/dev/null; then
            print_info "Vault is responding"
                break
            fi
            if [ $i -eq 12 ]; then
            print_warn "Vault may not be fully ready yet"
                print_info "Continuing with initialization attempt..."
            fi
            sleep 5
        done
    
    # Initialize and unseal Vault using Ansible
    echo ""
    print_info "Initializing and unsealing Vault using Ansible..."
    echo ""
    
    if command -v ansible-playbook &> /dev/null; then
        VAULT_NAMESPACE=$NAMESPACE ansible-playbook "$PLAYBOOK_PATH"
        
        if [ $? -eq 0 ]; then
            echo ""
            print_info "✓ Vault has been initialized and unsealed!"
            
            # Handle multi-replica scaling
            if [ "$REQUESTED_REPLICAS" -gt 1 ]; then
                echo ""
                print_info "═══════════════════════════════════════════════════════════"
                print_info "  Two-Phase Multi-Replica Deployment"
                print_info "═══════════════════════════════════════════════════════════"
                echo ""
                print_info "Phase 1: ✓ Single replica deployed and unsealed"
                print_info "Phase 2: Scaling to $REQUESTED_REPLICAS replicas using Helm upgrade..."
                echo ""
                
                # Function to wait for pod condition
                wait_for_pod_condition() {
                    local pod_name=$1
                    local condition=$2
                    local timeout=${3:-300}
                    local elapsed=0
                    
                    print_info "Waiting for $pod_name to be $condition..."
                    while [ $elapsed -lt $timeout ]; do
                        if [ "$condition" = "Running" ]; then
                            status=$($CLI get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
                            if [ "$status" = "Running" ]; then
                                print_info "✓ $pod_name is Running"
                                return 0
                            fi
                        elif [ "$condition" = "Ready" ]; then
                            ready=$($CLI get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
                            if [ "$ready" = "True" ]; then
                                print_info "✓ $pod_name is Ready"
                                return 0
                            fi
                        fi
                        sleep 5
                        elapsed=$((elapsed + 5))
                        if [ $((elapsed % 30)) -eq 0 ]; then
                            print_info "  Still waiting... ($elapsed/${timeout}s)"
                        fi
                    done
                    print_error "Timeout waiting for $pod_name to be $condition"
                    return 1
                }
                
                # Function to unseal a specific pod
                unseal_pod() {
                    local pod_name=$1
                    
                    print_info "Unsealing $pod_name..."
                    
                    # Check if already unsealed
                    if $CLI exec -n $NAMESPACE $pod_name -- vault status -format=json 2>/dev/null | grep -q '"sealed":false'; then
                        print_info "✓ $pod_name is already unsealed"
                        return 0
                    fi
                    
                    # Get unseal keys (try both formats)
                    KEY1=$($CLI get secret vault-unseal-keys -n $NAMESPACE -o jsonpath='{.data.key1}' 2>/dev/null | base64 -d)
                    if [ -z "$KEY1" ]; then
                        KEY1=$($CLI get secret vault-unseal-keys -n $NAMESPACE -o jsonpath='{.data.unseal-key-1}' | base64 -d)
                    fi
                    
                    KEY2=$($CLI get secret vault-unseal-keys -n $NAMESPACE -o jsonpath='{.data.key2}' 2>/dev/null | base64 -d)
                    if [ -z "$KEY2" ]; then
                        KEY2=$($CLI get secret vault-unseal-keys -n $NAMESPACE -o jsonpath='{.data.unseal-key-2}' | base64 -d)
                    fi
                    
                    KEY3=$($CLI get secret vault-unseal-keys -n $NAMESPACE -o jsonpath='{.data.key3}' 2>/dev/null | base64 -d)
                    if [ -z "$KEY3" ]; then
                        KEY3=$($CLI get secret vault-unseal-keys -n $NAMESPACE -o jsonpath='{.data.unseal-key-3}' | base64 -d)
                    fi
                    
                    # Unseal with retries
                    for attempt in 1 2 3; do
                        if $CLI exec -n $NAMESPACE $pod_name -- vault operator unseal "$KEY1" &>/dev/null &&
                           $CLI exec -n $NAMESPACE $pod_name -- vault operator unseal "$KEY2" &>/dev/null &&
                           $CLI exec -n $NAMESPACE $pod_name -- vault operator unseal "$KEY3" &>/dev/null; then
                            print_info "✓ Successfully unsealed $pod_name"
                            return 0
                        fi
                        if [ $attempt -lt 3 ]; then
                            print_warn "  Unseal attempt $attempt failed, retrying in 10s..."
                            sleep 10
                        fi
                    done
                    
                    print_error "✗ Failed to unseal $pod_name after 3 attempts"
                    return 1
                }
                # Verify vault-0 is Ready before scaling
                print_info "Verifying vault-0 is Ready before scaling..."
                if ! wait_for_pod_condition "vault-0" "Ready" 120; then
                    print_error "Vault-0 is not Ready. Cannot proceed with scaling."
                    print_warn "You may need to manually scale and unseal replicas later."
                    exit 1
                fi
                
                print_info "✓ Vault-0 is Ready and unsealed"
                echo ""
                
                # Scale up using Helm upgrade
                print_info "Scaling Vault StatefulSet to $REQUESTED_REPLICAS replicas..."
                HELM_UPGRADE_CMD="helm upgrade $RELEASE_NAME $CHART_DIR"
                HELM_UPGRADE_CMD="$HELM_UPGRADE_CMD --namespace $NAMESPACE"
                HELM_UPGRADE_CMD="$HELM_UPGRADE_CMD --reuse-values"
                HELM_UPGRADE_CMD="$HELM_UPGRADE_CMD --set vault.replicas=$REQUESTED_REPLICAS"
                
                if eval $HELM_UPGRADE_CMD; then
                    print_info "✓ Helm upgrade completed successfully"
                    echo ""
                    
                    # Wait for new pods to be created
                    print_info "Waiting for new replica pods to be created..."
                    sleep 10
                    
                    # Process each additional replica for unsealing
                    for i in $(seq 1 $((REQUESTED_REPLICAS - 1))); do
                        POD_NAME="vault-$i"
                        echo ""
                        print_info "───────────────────────────────────────────────────────────"
                        print_info "Processing replica $((i + 1))/$REQUESTED_REPLICAS: $POD_NAME"
                        print_info "───────────────────────────────────────────────────────────"
                        
                        # Wait for pod to be created and Running
                        if ! wait_for_pod_condition "$POD_NAME" "Running" 300; then
                            print_error "Failed to wait for $POD_NAME. Stopping replica processing."
                            break
                        fi
                        
                        
                        # Give pod time to attempt Raft join
                        print_info "Waiting for $POD_NAME to join Raft cluster (30s)..."
                        sleep 30
                        
                        # Unseal the pod
                        if unseal_pod "$POD_NAME"; then
                            # Wait for pod to become Ready
                            if wait_for_pod_condition "$POD_NAME" "Ready" 120; then
                                print_info "✓ $POD_NAME is unsealed and ready"
                            else
                                print_warn "⚠ $POD_NAME is unsealed but not yet Ready"
                                print_info "  This may resolve itself. Check status with:"
                                echo "    $CLI get pods -n $NAMESPACE"
                            fi
                        else
                            print_error "Failed to unseal $POD_NAME"
                            print_info "You can manually unseal it later using:"
                            echo "  ./scripts/unseal-secret-manager.sh -n $NAMESPACE"
                        fi
                    done
                    
                    echo ""
                    print_info "═══════════════════════════════════════════════════════════"
                    print_info "  Multi-Replica Deployment Complete"
                    print_info "═══════════════════════════════════════════════════════════"
                    echo ""
                    
                    # Display final status
                    print_info "Final Vault cluster status:"
                    $CLI get pods -n $NAMESPACE -l app.kubernetes.io/name=vault
                    echo ""
                    
                    # Verify Raft cluster formation
                    print_info "Verifying Raft cluster formation..."
                    sleep 5  # Give Raft a moment to stabilize
                    
                    RAFT_PEERS=$($CLI exec -n $NAMESPACE vault-0 -- vault operator raft list-peers 2>/dev/null || echo "")
                    
                    if [ -n "$RAFT_PEERS" ]; then
                        echo "$RAFT_PEERS"
                        echo ""
                        
                        PEER_COUNT=$(echo "$RAFT_PEERS" | grep -c "vault-" || echo "0")
                        
                        if [ "$PEER_COUNT" -eq "$REQUESTED_REPLICAS" ]; then
                            print_info "✓ All $REQUESTED_REPLICAS replicas successfully joined Raft cluster"
                        else
                            print_warn "⚠ Only $PEER_COUNT of $REQUESTED_REPLICAS replicas in Raft cluster"
                            print_info "Run diagnostics to identify issues:"
                            echo "  ./scripts/diagnose-vault-raft.sh -n $NAMESPACE --verbose"
                        fi
                    else
                        print_warn "Could not verify Raft cluster status"
                        print_info "Manually check with:"
                        echo "  $CLI exec -n $NAMESPACE vault-0 -- vault operator raft list-peers"
                    fi
                else
                    print_error "Helm upgrade failed. Vault remains at 1 replica."
                    print_warn "You can manually scale later using:"
                    echo "  helm upgrade $RELEASE_NAME $CHART_DIR --namespace $NAMESPACE --reuse-values --set vault.replicas=$REQUESTED_REPLICAS"
                    echo "  ./scripts/unseal-secret-manager.sh -n $NAMESPACE"
                fi
            fi
            
            echo ""
            print_info "To access Vault:"
            echo "  1. Get the root token:"
            echo "     $CLI get secret vault-unseal-keys -n $NAMESPACE -o jsonpath='{.data.root-token}' | base64 -d"
            echo ""
            echo "  2. Access Vault UI (if route/ingress configured):"
            echo "     $CLI get route vault -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo 'No route configured'"
            echo ""
            echo "  3. Or use port-forward:"
            echo "     $CLI port-forward -n $NAMESPACE svc/vault 8200:8200"
            echo "     # Then open: http://localhost:8200"
            echo ""
            echo "  4. Validate deployment:"
            echo "     ./scripts/validate-secret-manager.sh -n $NAMESPACE"
            echo ""
            print_warn "IMPORTANT: Back up the vault-unseal-keys secret to a secure location!"
        else
            print_error "Vault initialization failed"
            echo ""
            print_info "═══════════════════════════════════════════════════════════"
            print_info "  NEXT STEPS: Manual Vault Initialization Required"
            print_info "═══════════════════════════════════════════════════════════"
            echo ""
            print_info "Option 1: Retry with Ansible (Recommended)"
            echo "  ansible-playbook $PLAYBOOK_PATH -e vault_namespace=$NAMESPACE"
            echo ""
            print_info "Option 2: Manual Initialization"
            echo "  # Step 1: Port forward to Vault"
            echo "  $CLI port-forward -n $NAMESPACE svc/vault 8200:8200 &"
            echo ""
            echo "  # Step 2: Set Vault address"
            echo "  export VAULT_ADDR='http://127.0.0.1:8200'"
            echo ""
            echo "  # Step 3: Initialize Vault (SAVE THE OUTPUT!)"
            echo "  vault operator init -key-shares=5 -key-threshold=3"
            echo ""
            echo "  # Step 4: Unseal Vault (use any 3 of 5 keys)"
            echo "  vault operator unseal <unseal-key-1>"
            echo "  vault operator unseal <unseal-key-2>"
            echo "  vault operator unseal <unseal-key-3>"
            echo ""
            echo "  # Step 5: Login with root token"
            echo "  vault login <root-token>"
            echo ""
            print_warn "CRITICAL: Save unseal keys and root token in a secure location!"
            echo ""
        fi
    else
        print_warn "ansible-playbook not found. Skipping automatic initialization."
        echo ""
        print_info "═══════════════════════════════════════════════════════════"
        print_info "  NEXT STEPS: Vault Initialization Required"
        print_info "═══════════════════════════════════════════════════════════"
        echo ""
        print_info "Option 1: Use Provided Ansible Playbook (Recommended)"
        echo "  This project includes an Ansible playbook that automates:"
        echo "  • Vault initialization with 5 unseal keys"
        echo "  • Automatic unsealing of all Vault pods"
        echo "  • Secure storage of keys in Kubernetes secret"
        echo ""
        echo "  # Step 1: Install Ansible and dependencies"
        echo "  pip install ansible"
        echo "  ansible-galaxy collection install -r ansible/requirements.yml"
        echo ""
        echo "  # Step 2: Run the initialization playbook"
        echo "  cd $(dirname $SCRIPT_DIR)"
        echo "  ansible-playbook ansible/playbooks/initialize-vault.yml -e vault_namespace=$NAMESPACE"
        echo ""
        echo "  The playbook will:"
        echo "  • Check if Vault is already initialized"
        echo "  • Initialize Vault if needed (5 keys, threshold 3)"
        echo "  • Unseal all Vault pods automatically"
        echo "  • Store keys in 'vault-unseal-keys' secret"
        echo ""
        echo "  After completion, retrieve credentials:"
        echo "  $CLI get secret vault-unseal-keys -n $NAMESPACE -o jsonpath='{.data.root-token}' | base64 -d"
        echo ""
        print_info "Option 2: Manual Initialization"
        echo "  # Step 1: Port forward to Vault"
        echo "  $CLI port-forward -n $NAMESPACE svc/vault 8200:8200 &"
        echo ""
        echo "  # Step 2: Set Vault address"
        echo "  export VAULT_ADDR='http://127.0.0.1:8200'"
        echo ""
        echo "  # Step 3: Initialize Vault (SAVE THE OUTPUT!)"
        echo "  vault operator init -key-shares=5 -key-threshold=3"
        echo "  # Output will show:"
        echo "  #   Unseal Key 1: <key1>"
        echo "  #   Unseal Key 2: <key2>"
        echo "  #   Unseal Key 3: <key3>"
        echo "  #   Unseal Key 4: <key4>"
        echo "  #   Unseal Key 5: <key5>"
        echo "  #   Initial Root Token: <token>"
        echo ""
        echo "  # Step 4: Unseal Vault (use any 3 of 5 keys)"
        echo "  vault operator unseal <unseal-key-1>"
        echo "  vault operator unseal <unseal-key-2>"
        echo "  vault operator unseal <unseal-key-3>"
        echo ""
        echo "  # Step 5: Verify Vault is unsealed"
        echo "  vault status"
        echo "  # Should show: Sealed = false"
        echo ""
        echo "  # Step 6: Login with root token"
        echo "  vault login <root-token>"
        echo ""
        echo "  # Step 7: Verify login"
        echo "  vault token lookup"
        echo ""
        print_warn "CRITICAL: Save unseal keys and root token in a secure location!"
        print_warn "          You will need 3 keys to unseal Vault after any restart."
        echo ""
        print_info "After initialization, configure Vault for spoke clusters:"
        echo "  1. Enable Kubernetes auth: vault auth enable kubernetes"
        echo "  2. Enable secrets engine: vault secrets enable -path=secret kv-v2"
        echo "  3. Create policies and roles for each spoke cluster"
        echo ""
    fi
fi

# Made with Bob
