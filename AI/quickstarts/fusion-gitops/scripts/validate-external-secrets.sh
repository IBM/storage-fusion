#!/bin/bash
# External Secrets Operator validation script
# Validates External Secrets Operator deployment and configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="external-secrets-operator"
VERBOSE=false
CHECK_BACKEND=false
BACKEND_TYPE=""

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

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate External Secrets Operator deployment on OpenShift/Kubernetes

OPTIONS:
    -n, --namespace NAMESPACE    Operator namespace (default: external-secrets-operator)
    -b, --backend TYPE           Check specific backend: vault, aws, ibmcloud
    -v, --verbose                Show detailed output
    -h, --help                   Show this help message

EXAMPLES:
    # Validate operator in default namespace
    $0

    # Validate operator in custom namespace
    $0 -n my-external-secrets

    # Validate with Vault backend connectivity
    $0 --backend vault

    # Verbose output
    $0 -v

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
        -b|--backend)
            CHECK_BACKEND=true
            BACKEND_TYPE="$2"
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
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Detect CLI (oc or kubectl)
if command -v oc &> /dev/null; then
    CLI="oc"
elif command -v kubectl &> /dev/null; then
    CLI="kubectl"
else
    print_error "Neither 'oc' nor 'kubectl' found in PATH"
    exit 1
fi

# Track validation results
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNED=0

# Function to increment counters
pass_check() {
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

fail_check() {
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
}

warn_check() {
    CHECKS_WARNED=$((CHECKS_WARNED + 1))
}

# Start validation
echo ""
print_info "Starting External Secrets Operator validation..."
print_info "Namespace: $NAMESPACE"
print_info "CLI: $CLI"
echo ""

# Check 1: Namespace exists
print_section "1. Checking Namespace..."
if $CLI get namespace $NAMESPACE &> /dev/null; then
    print_success "Namespace '$NAMESPACE' exists"
    pass_check
else
    print_fail "Namespace '$NAMESPACE' does not exist"
    fail_check
    echo ""
    print_error "External Secrets Operator namespace not found. Deploy using:"
    echo "  ./scripts/deploy-external-secrets.sh --backend standalone|vault|aws|ibmcloud"
    exit 1
fi

# Check 2: Operator Subscription
print_section "2. Checking Operator Subscription..."
SUBSCRIPTION=$($CLI get subscription -n $NAMESPACE -o jsonpath='{.items[?(@.spec.name=="openshift-external-secrets-operator")].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SUBSCRIPTION" ]; then
    print_success "Subscription found: $SUBSCRIPTION"
    
    # Get subscription details
    CHANNEL=$($CLI get subscription $SUBSCRIPTION -n $NAMESPACE -o jsonpath='{.spec.channel}' 2>/dev/null || echo "")
    SOURCE=$($CLI get subscription $SUBSCRIPTION -n $NAMESPACE -o jsonpath='{.spec.source}' 2>/dev/null || echo "")
    INSTALL_PLAN=$($CLI get subscription $SUBSCRIPTION -n $NAMESPACE -o jsonpath='{.status.installplan.name}' 2>/dev/null || echo "")
    
    if [ "$VERBOSE" = true ]; then
        echo "  Channel: $CHANNEL"
        echo "  Source: $SOURCE"
        echo "  Install Plan: $INSTALL_PLAN"
    fi
    pass_check
else
    print_fail "Operator subscription not found"
    fail_check
fi

# Check 3: ClusterServiceVersion (CSV)
print_section "3. Checking ClusterServiceVersion (CSV)..."
CSV_NAME=$($CLI get csv -n $NAMESPACE -o jsonpath='{.items[?(@.spec.displayName=="External Secrets Operator for Red Hat OpenShift")].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CSV_NAME" ]; then
    CSV_PHASE=$($CLI get csv $CSV_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    
    if [ "$CSV_PHASE" = "Succeeded" ]; then
        print_success "CSV '$CSV_NAME' is in Succeeded phase"
        
        if [ "$VERBOSE" = true ]; then
            CSV_VERSION=$($CLI get csv $CSV_NAME -n $NAMESPACE -o jsonpath='{.spec.version}' 2>/dev/null || echo "")
            echo "  Version: $CSV_VERSION"
        fi
        pass_check
    else
        print_fail "CSV '$CSV_NAME' is in '$CSV_PHASE' phase (expected: Succeeded)"
        fail_check
    fi
else
    print_fail "CSV not found"
    fail_check
fi

# Check 4: Operator Pods
print_section "4. Checking Operator Pods..."
OPERATOR_PODS=$($CLI get pods -n $NAMESPACE -l app=external-secrets-operator --no-headers 2>/dev/null || echo "")
if [ -n "$OPERATOR_PODS" ]; then
    TOTAL_PODS=$(echo "$OPERATOR_PODS" | wc -l | tr -d ' ')
    RUNNING_PODS=$(echo "$OPERATOR_PODS" | grep -c "Running" || echo "0")
    
    if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ]; then
        print_success "All $TOTAL_PODS operator pod(s) are Running"
        
        # Check if pods are ready
        READY_STATUS=$($CLI get pods -n $NAMESPACE -l app=external-secrets-operator -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        READY_COUNT=$(echo "$READY_STATUS" | grep -o "True" | wc -l || echo "0")
        
        if [ "$READY_COUNT" -eq "$TOTAL_PODS" ]; then
            print_success "All $TOTAL_PODS operator pod(s) are Ready"
            pass_check
        else
            print_warn "$READY_COUNT/$TOTAL_PODS operator pod(s) are Ready"
            warn_check
        fi
        
        if [ "$VERBOSE" = true ]; then
            echo ""
            echo "Operator Pods:"
            $CLI get pods -n $NAMESPACE -l app=external-secrets-operator
        fi
    else
        print_fail "Only $RUNNING_PODS/$TOTAL_PODS operator pod(s) are Running"
        fail_check
    fi
else
    print_fail "No operator pods found"
    fail_check
fi

# Check 5: Webhook Pods
print_section "5. Checking Webhook Pods..."
WEBHOOK_PODS=$($CLI get pods -n $NAMESPACE -l app.kubernetes.io/component=webhook --no-headers 2>/dev/null || echo "")
if [ -n "$WEBHOOK_PODS" ]; then
    TOTAL_WEBHOOK=$(echo "$WEBHOOK_PODS" | wc -l | tr -d ' ')
    RUNNING_WEBHOOK=$(echo "$WEBHOOK_PODS" | grep -c "Running" || echo "0")
    
    if [ "$RUNNING_WEBHOOK" -eq "$TOTAL_WEBHOOK" ]; then
        print_success "All $TOTAL_WEBHOOK webhook pod(s) are Running"
        pass_check
    else
        print_warn "Only $RUNNING_WEBHOOK/$TOTAL_WEBHOOK webhook pod(s) are Running"
        warn_check
    fi
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "Webhook Pods:"
        $CLI get pods -n $NAMESPACE -l app.kubernetes.io/component=webhook
    fi
else
    print_warn "No webhook pods found (may not be deployed)"
    warn_check
fi

# Check 6: Cert Controller Pods
print_section "6. Checking Cert Controller Pods..."
CERT_PODS=$($CLI get pods -n $NAMESPACE -l app.kubernetes.io/component=cert-controller --no-headers 2>/dev/null || echo "")
if [ -n "$CERT_PODS" ]; then
    TOTAL_CERT=$(echo "$CERT_PODS" | wc -l | tr -d ' ')
    RUNNING_CERT=$(echo "$CERT_PODS" | grep -c "Running" || echo "0")
    
    if [ "$RUNNING_CERT" -eq "$TOTAL_CERT" ]; then
        print_success "All $TOTAL_CERT cert-controller pod(s) are Running"
        pass_check
    else
        print_warn "Only $RUNNING_CERT/$TOTAL_CERT cert-controller pod(s) are Running"
        warn_check
    fi
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "Cert Controller Pods:"
        $CLI get pods -n $NAMESPACE -l app.kubernetes.io/component=cert-controller
    fi
else
    print_warn "No cert-controller pods found (may not be deployed)"
    warn_check
fi

# Check 7: CRDs Installed
print_section "7. Checking Custom Resource Definitions (CRDs)..."
EXPECTED_CRDS=(
    "clustersecretstores.external-secrets.io"
    "externalsecrets.external-secrets.io"
    "secretstores.external-secrets.io"
    "clusterexternalsecrets.external-secrets.io"
)

CRD_COUNT=0
for CRD in "${EXPECTED_CRDS[@]}"; do
    if $CLI get crd $CRD &> /dev/null; then
        CRD_STATUS=$($CLI get crd $CRD -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "")
        if [ "$CRD_STATUS" = "True" ]; then
            if [ "$VERBOSE" = true ]; then
                print_success "CRD '$CRD' is established"
            fi
            CRD_COUNT=$((CRD_COUNT + 1))
        else
            print_warn "CRD '$CRD' exists but is not established"
        fi
    else
        print_fail "CRD '$CRD' not found"
    fi
done

if [ $CRD_COUNT -eq ${#EXPECTED_CRDS[@]} ]; then
    print_success "All ${#EXPECTED_CRDS[@]} required CRDs are established"
    pass_check
else
    print_fail "Only $CRD_COUNT/${#EXPECTED_CRDS[@]} required CRDs are established"
    fail_check
fi

# Check 8: ClusterSecretStores
print_section "8. Checking ClusterSecretStores..."
CLUSTER_STORES=$($CLI get clustersecretstores --all-namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CLUSTER_STORES" ]; then
    STORE_COUNT=$(echo "$CLUSTER_STORES" | wc -w | tr -d ' ')
    print_success "Found $STORE_COUNT ClusterSecretStore(s)"
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "ClusterSecretStores:"
        $CLI get clustersecretstores --all-namespaces
    fi
    
    # Check status of each store
    for STORE in $CLUSTER_STORES; do
        STORE_STATUS=$($CLI get clustersecretstore $STORE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        if [ "$STORE_STATUS" = "True" ]; then
            if [ "$VERBOSE" = true ]; then
                print_success "ClusterSecretStore '$STORE' is Ready"
            fi
        else
            print_warn "ClusterSecretStore '$STORE' is not Ready (status: $STORE_STATUS)"
            warn_check
        fi
    done
    pass_check
else
    print_warn "No ClusterSecretStores found (may not be configured yet)"
    warn_check
fi

# Check 9: SecretStores (namespace-scoped)
print_section "9. Checking SecretStores..."
SECRET_STORES=$($CLI get secretstores -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SECRET_STORES" ]; then
    STORE_COUNT=$(echo "$SECRET_STORES" | wc -w | tr -d ' ')
    print_success "Found $STORE_COUNT SecretStore(s) in namespace '$NAMESPACE'"
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "SecretStores:"
        $CLI get secretstores -n $NAMESPACE
    fi
    pass_check
else
    print_warn "No SecretStores found in namespace '$NAMESPACE'"
    warn_check
fi
# Check 10: Configured Secret Backends
print_section "10. Checking Configured Secret Backends..."

# Detect all configured backends from ClusterSecretStores
if [ -n "$CLUSTER_STORES" ]; then
    echo ""
    print_info "Analyzing configured backends..."
    
    for STORE in $CLUSTER_STORES; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "ClusterSecretStore: $STORE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Check for Vault backend
        VAULT_SERVER=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.vault.server}' 2>/dev/null || echo "")
        if [ -n "$VAULT_SERVER" ]; then
            print_info "Backend Type: HashiCorp Vault"
            echo "  Server: $VAULT_SERVER"
            
            VAULT_PATH=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.vault.path}' 2>/dev/null || echo "")
            VAULT_VERSION=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.vault.version}' 2>/dev/null || echo "")
            VAULT_AUTH=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.vault.auth}' 2>/dev/null || echo "")
            
            [ -n "$VAULT_PATH" ] && echo "  Path: $VAULT_PATH"
            [ -n "$VAULT_VERSION" ] && echo "  KV Version: $VAULT_VERSION"
            
            # Detect auth method
            if echo "$VAULT_AUTH" | grep -q "kubernetes"; then
                VAULT_ROLE=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.vault.auth.kubernetes.role}' 2>/dev/null || echo "")
                echo "  Auth Method: Kubernetes"
                [ -n "$VAULT_ROLE" ] && echo "  Kubernetes Role: $VAULT_ROLE"
            elif echo "$VAULT_AUTH" | grep -q "token"; then
                echo "  Auth Method: Token"
            elif echo "$VAULT_AUTH" | grep -q "appRole"; then
                echo "  Auth Method: AppRole"
            fi
        fi
        
        # Check for AWS backend
        AWS_REGION=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.aws.region}' 2>/dev/null || echo "")
        if [ -n "$AWS_REGION" ]; then
            print_info "Backend Type: AWS Secrets Manager"
            echo "  Region: $AWS_REGION"
            
            AWS_SERVICE=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.aws.service}' 2>/dev/null || echo "")
            [ -n "$AWS_SERVICE" ] && echo "  Service: $AWS_SERVICE"
            
            # Detect auth method
            AWS_AUTH=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.aws.auth}' 2>/dev/null || echo "")
            if echo "$AWS_AUTH" | grep -q "secretRef"; then
                echo "  Auth Method: Access Key/Secret"
            elif echo "$AWS_AUTH" | grep -q "jwt"; then
                echo "  Auth Method: IRSA (IAM Roles for Service Accounts)"
            fi
        fi
        
        # Check for IBM Cloud backend
        IBM_URL=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.ibm.serviceUrl}' 2>/dev/null || echo "")
        if [ -n "$IBM_URL" ]; then
            print_info "Backend Type: IBM Cloud Secrets Manager"
            echo "  Service URL: $IBM_URL"
            
            IBM_REGION=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.ibm.region}' 2>/dev/null || echo "")
            [ -n "$IBM_REGION" ] && echo "  Region: $IBM_REGION"
            
            # Detect auth method
            IBM_AUTH=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.ibm.auth}' 2>/dev/null || echo "")
            if echo "$IBM_AUTH" | grep -q "secretRef"; then
                echo "  Auth Method: API Key"
            elif echo "$IBM_AUTH" | grep -q "containerAuth"; then
                echo "  Auth Method: Container Auth"
            fi
        fi
        
        # Check for Azure backend
        AZURE_URL=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.azurekv.vaultUrl}' 2>/dev/null || echo "")
        if [ -n "$AZURE_URL" ]; then
            print_info "Backend Type: Azure Key Vault"
            echo "  Vault URL: $AZURE_URL"
            
            AZURE_TENANT=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.azurekv.tenantId}' 2>/dev/null || echo "")
            [ -n "$AZURE_TENANT" ] && echo "  Tenant ID: $AZURE_TENANT"
        fi
        
        # Check for GCP backend
        GCP_PROJECT=$($CLI get clustersecretstore $STORE -o jsonpath='{.spec.provider.gcpsm.projectID}' 2>/dev/null || echo "")
        if [ -n "$GCP_PROJECT" ]; then
            print_info "Backend Type: Google Cloud Secret Manager"
            echo "  Project ID: $GCP_PROJECT"
        fi
        
        # Check store status
        STORE_STATUS=$($CLI get clustersecretstore $STORE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        STORE_REASON=$($CLI get clustersecretstore $STORE -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "")
        STORE_MESSAGE=$($CLI get clustersecretstore $STORE -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
        
        echo ""
        if [ "$STORE_STATUS" = "True" ]; then
            print_success "Status: Ready"
        elif [ "$STORE_STATUS" = "False" ]; then
            print_fail "Status: Not Ready"
            [ -n "$STORE_REASON" ] && echo "  Reason: $STORE_REASON"
            [ -n "$STORE_MESSAGE" ] && echo "  Message: $STORE_MESSAGE"
        else
            print_warn "Status: Unknown"
        fi
    done
    
    echo ""
    pass_check
else
    print_warn "No ClusterSecretStores configured"
    warn_check
fi


# Check 11: ExternalSecrets
print_section "11. Checking ExternalSecrets..."
EXTERNAL_SECRETS=$($CLI get externalsecrets --all-namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$EXTERNAL_SECRETS" ]; then
    SECRET_COUNT=$(echo "$EXTERNAL_SECRETS" | wc -w | tr -d ' ')
    print_success "Found $SECRET_COUNT ExternalSecret(s)"
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "ExternalSecrets:"
        $CLI get externalsecrets --all-namespaces
    fi
    
    # Check sync status
    SYNCED_COUNT=0
    for ES in $EXTERNAL_SECRETS; do
        ES_NAMESPACE=$($CLI get externalsecrets --all-namespaces -o jsonpath="{.items[?(@.metadata.name=='$ES')].metadata.namespace}" 2>/dev/null || echo "")
        if [ -n "$ES_NAMESPACE" ]; then
            SYNC_STATUS=$($CLI get externalsecret $ES -n $ES_NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
            if [ "$SYNC_STATUS" = "True" ]; then
                SYNCED_COUNT=$((SYNCED_COUNT + 1))
                if [ "$VERBOSE" = true ]; then
                    print_success "ExternalSecret '$ES' in namespace '$ES_NAMESPACE' is synced"
                fi
            else
                print_warn "ExternalSecret '$ES' in namespace '$ES_NAMESPACE' is not synced (status: $SYNC_STATUS)"
            fi
        fi
    done
    
    if [ $SYNCED_COUNT -eq $SECRET_COUNT ]; then
        print_success "All $SECRET_COUNT ExternalSecret(s) are synced"
    else
        print_warn "$SYNCED_COUNT/$SECRET_COUNT ExternalSecret(s) are synced"
    fi
    pass_check
else
    print_warn "No ExternalSecrets found (may not be configured yet)"
    warn_check
fi

# Check 12: Service Account
print_section "12. Checking Service Account..."
# OLM creates service account with controller-manager suffix
SA_NAME="external-secrets-operator-controller-manager"
if $CLI get serviceaccount $SA_NAME -n $NAMESPACE &> /dev/null; then
    print_success "ServiceAccount '$SA_NAME' exists"
    pass_check
else
    # Fallback to check for alternative name
    SA_NAME_ALT="external-secrets-operator"
    if $CLI get serviceaccount $SA_NAME_ALT -n $NAMESPACE &> /dev/null; then
        print_success "ServiceAccount '$SA_NAME_ALT' exists"
        pass_check
    else
        print_fail "ServiceAccount not found (checked: $SA_NAME, $SA_NAME_ALT)"
        fail_check
    fi
fi

# Check 13: RBAC (ClusterRole and ClusterRoleBinding)
print_section "13. Checking RBAC Configuration..."
CLUSTER_ROLE=$($CLI get clusterrole -o jsonpath='{.items[?(@.metadata.name=="external-secrets-operator")].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CLUSTER_ROLE" ]; then
    print_success "ClusterRole 'external-secrets-operator' exists"
    pass_check
else
    print_warn "ClusterRole 'external-secrets-operator' not found"
    warn_check
fi

CLUSTER_ROLE_BINDING=$($CLI get clusterrolebinding -o jsonpath='{.items[?(@.metadata.name=="external-secrets-operator")].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CLUSTER_ROLE_BINDING" ]; then
    print_success "ClusterRoleBinding 'external-secrets-operator' exists"
    pass_check
else
    print_warn "ClusterRoleBinding 'external-secrets-operator' not found"
    warn_check
fi

# Check 14: Backend Connectivity (if requested)
if [ "$CHECK_BACKEND" = true ]; then
    print_section "14. Checking Backend Connectivity..."
    
    case $BACKEND_TYPE in
        vault)
            print_info "Checking Vault backend connectivity..."
            VAULT_STORE=$($CLI get clustersecretstore -o jsonpath='{.items[?(@.spec.provider.vault)].metadata.name}' 2>/dev/null | head -1 || echo "")
            if [ -n "$VAULT_STORE" ]; then
                VAULT_URL=$($CLI get clustersecretstore $VAULT_STORE -o jsonpath='{.spec.provider.vault.server}' 2>/dev/null || echo "")
                print_info "Vault ClusterSecretStore: $VAULT_STORE"
                print_info "Vault URL: $VAULT_URL"
                
                # Check if Vault is accessible
                VAULT_STATUS=$($CLI get clustersecretstore $VAULT_STORE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
                if [ "$VAULT_STATUS" = "True" ]; then
                    print_success "Vault backend is accessible and ready"
                    pass_check
                else
                    print_fail "Vault backend is not ready (status: $VAULT_STATUS)"
                    fail_check
                fi
            else
                print_fail "No Vault ClusterSecretStore found"
                fail_check
            fi
            ;;
        aws)
            print_info "Checking AWS Secrets Manager backend connectivity..."
            AWS_STORE=$($CLI get clustersecretstore -o jsonpath='{.items[?(@.spec.provider.aws)].metadata.name}' 2>/dev/null | head -1 || echo "")
            if [ -n "$AWS_STORE" ]; then
                AWS_REGION=$($CLI get clustersecretstore $AWS_STORE -o jsonpath='{.spec.provider.aws.region}' 2>/dev/null || echo "")
                print_info "AWS ClusterSecretStore: $AWS_STORE"
                print_info "AWS Region: $AWS_REGION"
                
                AWS_STATUS=$($CLI get clustersecretstore $AWS_STORE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
                if [ "$AWS_STATUS" = "True" ]; then
                    print_success "AWS backend is accessible and ready"
                    pass_check
                else
                    print_fail "AWS backend is not ready (status: $AWS_STATUS)"
                    fail_check
                fi
            else
                print_fail "No AWS ClusterSecretStore found"
                fail_check
            fi
            ;;
        ibmcloud)
            print_info "Checking IBM Cloud Secrets Manager backend connectivity..."
            IBM_STORE=$($CLI get clustersecretstore -o jsonpath='{.items[?(@.spec.provider.ibm)].metadata.name}' 2>/dev/null | head -1 || echo "")
            if [ -n "$IBM_STORE" ]; then
                IBM_URL=$($CLI get clustersecretstore $IBM_STORE -o jsonpath='{.spec.provider.ibm.serviceUrl}' 2>/dev/null || echo "")
                print_info "IBM Cloud ClusterSecretStore: $IBM_STORE"
                print_info "IBM Cloud URL: $IBM_URL"
                
                IBM_STATUS=$($CLI get clustersecretstore $IBM_STORE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
                if [ "$IBM_STATUS" = "True" ]; then
                    print_success "IBM Cloud backend is accessible and ready"
                    pass_check
                else
                    print_fail "IBM Cloud backend is not ready (status: $IBM_STATUS)"
                    fail_check
                fi
            else
                print_fail "No IBM Cloud ClusterSecretStore found"
                fail_check
            fi
            ;;
        *)
            print_error "Unknown backend type: $BACKEND_TYPE"
            print_error "Supported backends: vault, aws, ibmcloud"
            fail_check
            ;;
    esac
fi

# Summary
print_section "Validation Summary"
echo ""
echo "Results:"
echo "  ✓ Passed:  $CHECKS_PASSED"
echo "  ⚠ Warned:  $CHECKS_WARNED"
echo "  ✗ Failed:  $CHECKS_FAILED"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    if [ $CHECKS_WARNED -eq 0 ]; then
        print_success "All validation checks passed!"
        echo ""
        print_info "External Secrets Operator is fully operational"
        exit 0
    else
        print_warn "Validation completed with warnings"
        echo ""
        print_info "External Secrets Operator is operational but some optional components may not be configured"
        exit 0
    fi
else
    print_error "Validation failed with $CHECKS_FAILED error(s)"
    echo ""
    print_info "Common fixes:"
    echo "  - Ensure operator is deployed: ./scripts/deploy-external-secrets.sh --backend standalone|vault|aws|ibmcloud"
    echo "  - Check operator logs: $CLI logs -n $NAMESPACE -l app=external-secrets-operator"
    echo "  - Verify CSV status: $CLI get csv -n $NAMESPACE"
    echo "  - Check CRD status: $CLI get crd | grep external-secrets"
    exit 1
fi

# Made with Bob