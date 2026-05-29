#!/bin/bash
# External Secrets Operator deployment script
# Deploys External Secrets Operator for syncing secrets from external vaults

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="external-secrets-operator"
RELEASE_NAME="external-secrets-operator"
VALUES_FILE=""
BACKEND=""
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

Deploy External Secrets Operator on OpenShift/Kubernetes

OPTIONS:
    -n, --namespace NAMESPACE       Operator namespace (default: external-secrets-operator)
    -b, --backend BACKEND           Secret backend: standalone, vault, aws, ibmcloud (optional)
    -f, --values-file FILE           Custom values file (optional)
    --release-name NAME             Helm release name (default: external-secrets-operator)
    --standalone                    Deploy operator only without any backend (for testing)
    --dry-run                       Show what would be deployed without deploying
    -h, --help                      Show this help message

BACKENDS:
    standalone  Operator only (no external vault integration)
    vault       HashiCorp Vault
    aws         AWS Secrets Manager
    ibmcloud    IBM Cloud Secrets Manager

EXAMPLES:
    # Deploy standalone (operator only, no vault)
    $0 --standalone

    # Deploy with Vault backend
    $0 --backend vault

    # Deploy with AWS backend
    $0 --backend aws

    # Deploy with IBM Cloud backend
    $0 --backend ibmcloud

    # Deploy with custom values
    $0 --backend vault -f my-values.yaml

    # Dry run
    $0 --backend vault --dry-run

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
            BACKEND="$2"
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
        --standalone)
            BACKEND="standalone"
            shift
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

# Validate backend is specified
if [ -z "$BACKEND" ]; then
    print_error "Backend is required. Use --backend standalone|vault|aws|ibmcloud or --standalone"
    usage
fi

# Validate backend value
case $BACKEND in
    standalone|vault|aws|ibmcloud)
        ;;
    *)
        print_error "Invalid backend: $BACKEND. Must be standalone, vault, aws, or ibmcloud"
        exit 1
        ;;
esac

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
    print_error "Helm is not installed. Please install Helm 3.x"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/../helm/external-secrets-operator"

# Check if chart exists
if [ ! -d "$CHART_DIR" ]; then
    print_error "Chart directory not found: $CHART_DIR"
    exit 1
fi

# Set default values file if not provided
if [ -z "$VALUES_FILE" ]; then
    if [ "$BACKEND" = "standalone" ]; then
        VALUES_FILE="$CHART_DIR/values-standalone.yaml"
    else
        VALUES_FILE="$CHART_DIR/examples/values-${BACKEND}.yaml"
    fi
    
    if [ ! -f "$VALUES_FILE" ]; then
        print_error "Default values file not found: $VALUES_FILE"
        exit 1
    fi
    print_info "Using default values file for $BACKEND backend"
fi

# Verify values file exists
if [ ! -f "$VALUES_FILE" ]; then
    print_error "Values file not found: $VALUES_FILE"
    exit 1
fi

# Create namespace if it doesn't exist
if ! $CLI get namespace $NAMESPACE &> /dev/null; then
    print_info "Creating namespace: $NAMESPACE"
    $CLI create namespace $NAMESPACE
else
    print_info "Namespace $NAMESPACE already exists"
fi

# Build Helm command
HELM_CMD="helm upgrade --install $RELEASE_NAME $CHART_DIR"
HELM_CMD="$HELM_CMD --namespace $NAMESPACE"
HELM_CMD="$HELM_CMD --values $VALUES_FILE"
HELM_CMD="$HELM_CMD --set global.namespace=$NAMESPACE"
HELM_CMD="$HELM_CMD --set operator.namespace=$NAMESPACE"

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
echo "  Backend:         $BACKEND"
echo "  Values File:     $VALUES_FILE"
echo ""

# Show backend-specific instructions
case $BACKEND in
    standalone)
        print_info "Standalone Mode - Operator Only"
        echo "  No external vault integration will be configured"
        echo "  This is ideal for testing operator deployment and functionality"
        echo "  You can add vault integration later by:"
        echo "    1. Deploying a vault backend (Vault, AWS, IBM Cloud, etc.)"
        echo "    2. Re-running this script with --backend vault|aws|ibmcloud"
        echo ""
        ;;
    vault)
        print_info "HashiCorp Vault Backend Selected"
        echo "  Make sure Vault is accessible and configured for Kubernetes auth"
        echo ""
        ;;
    aws)
        print_info "AWS Secrets Manager Backend Selected"
        echo "  Make sure AWS credentials secret exists:"
        echo "    kubectl create secret generic aws-credentials \\"
        echo "      -n $NAMESPACE \\"
        echo "      --from-literal=access-key-id=YOUR_KEY \\"
        echo "      --from-literal=secret-access-key=YOUR_SECRET"
        echo ""
        ;;
    ibmcloud)
        print_info "IBM Cloud Secrets Manager Backend Selected"
        echo "  Make sure IBM Cloud credentials secret exists:"
        echo "    kubectl create secret generic ibm-cloud-credentials \\"
        echo "      -n $NAMESPACE \\"
        echo "      --from-literal=api-key=YOUR_API_KEY"
        echo ""
        ;;
esac

# Confirm deployment
if [ "$DRY_RUN" = false ]; then
    read -p "Do you want to proceed with the deployment? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_warn "Deployment cancelled"
        exit 0
    fi
fi

# Deploy Phase 1: Operator only (disable SecretStores)
print_info "Phase 1: Deploying External Secrets Operator..."
echo ""
HELM_CMD_PHASE1="$HELM_CMD --set secretStores.vault.enabled=false --set secretStores.aws.enabled=false --set secretStores.ibmCloud.enabled=false"
eval $HELM_CMD_PHASE1

if [ "$DRY_RUN" = false ]; then
    echo ""
    print_info "Phase 1 complete - Operator deployed"
    
    # Wait for OLM to install the operator (CSV status check)
    if [ "$BACKEND" != "standalone" ]; then
        print_info "Waiting for OLM to install External Secrets Operator (CSV)..."
        MAX_WAIT=180
        WAIT_COUNT=0
        CSV_READY=false
        
        while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
            # Check if CSV exists and is in Succeeded phase
            CSV_PHASE=$($CLI get csv -n $NAMESPACE -o jsonpath='{.items[?(@.spec.displayName=="External Secrets Operator for Red Hat OpenShift")].status.phase}' 2>/dev/null || echo "")
            
            if [ "$CSV_PHASE" = "Succeeded" ]; then
                CSV_NAME=$($CLI get csv -n $NAMESPACE -o jsonpath='{.items[?(@.spec.displayName=="External Secrets Operator for Red Hat OpenShift")].metadata.name}' 2>/dev/null || echo "")
                print_info "CSV $CSV_NAME is in Succeeded phase"
                CSV_READY=true
                break
            elif [ -n "$CSV_PHASE" ]; then
                echo -n ".(CSV phase: $CSV_PHASE)"
            else
                echo -n "."
            fi
            
            WAIT_COUNT=$((WAIT_COUNT + 1))
            if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
                print_error "Timeout waiting for CSV to reach Succeeded phase"
                print_error "Current CSV status:"
                $CLI get csv -n $NAMESPACE
                exit 1
            fi
            sleep 2
        done
        echo ""
        
        if [ "$CSV_READY" = true ]; then
            # Wait for operator pods to be ready (OLM-managed pods use app=external-secrets-operator label)
            print_info "Waiting for External Secrets Operator pods to be ready..."
            MAX_WAIT=120
            WAIT_COUNT=0
            PODS_READY=false
            
            while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
                # Check if operator pods are running and ready (using correct OLM label)
                READY_PODS=$($CLI get pods -n $NAMESPACE -l app=external-secrets-operator -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
                TOTAL_PODS=$($CLI get pods -n $NAMESPACE -l app=external-secrets-operator --no-headers 2>/dev/null | wc -l || echo "0")
                
                if [ "$TOTAL_PODS" -gt 0 ]; then
                    # Count how many pods are ready
                    READY_COUNT=$(echo "$READY_PODS" | grep -o "True" | wc -l || echo "0")
                    
                    if [ "$READY_COUNT" -eq "$TOTAL_PODS" ]; then
                        print_info "All $TOTAL_PODS operator pod(s) are ready"
                        PODS_READY=true
                        break
                    else
                        echo -n "."
                    fi
                else
                    echo -n "."
                fi
                
                WAIT_COUNT=$((WAIT_COUNT + 1))
                if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
                    print_error "Timeout waiting for operator pods to be ready"
                    print_error "Operator pods may not be running properly"
                    $CLI get pods -n $NAMESPACE -l app=external-secrets-operator
                    exit 1
                fi
                sleep 2
            done
            echo ""
            
            if [ "$PODS_READY" = true ]; then
                # Wait for CRDs to be available and established
                print_info "Waiting for External Secrets CRDs to be established..."
                MAX_WAIT=60
                WAIT_COUNT=0
                CRD_READY=false
                
                while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
                    # Check if CRD exists and is established
                    if $CLI get crd clustersecretstores.external-secrets.io &> /dev/null; then
                        CRD_STATUS=$($CLI get crd clustersecretstores.external-secrets.io -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "")
                        if [ "$CRD_STATUS" = "True" ]; then
                            print_info "CRD clustersecretstores.external-secrets.io is established"
                            CRD_READY=true
                            break
                        fi
                    fi
                    WAIT_COUNT=$((WAIT_COUNT + 1))
                    if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
                        print_error "Timeout waiting for CRDs to be established"
                        print_error "CRD may exist but is not ready to accept resources"
                        exit 1
                    fi
                    echo -n "."
                    sleep 2
                done
                echo ""
                
                if [ "$CRD_READY" = true ]; then
                    # Verify API server has registered the resource type
                    print_info "Verifying API server has registered ClusterSecretStore resource..."
                    MAX_WAIT=90
                    WAIT_COUNT=0
                    API_READY=false
                    
                    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
                        # Check if kubectl api-resources shows the ClusterSecretStore
                        if $CLI api-resources --api-group=external-secrets.io 2>/dev/null | grep -q "clustersecretstores"; then
                            print_info "ClusterSecretStore resource is registered in API server"
                            API_READY=true
                            break
                        fi
                        WAIT_COUNT=$((WAIT_COUNT + 1))
                        if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
                            print_error "Timeout waiting for API server to register ClusterSecretStore"
                            print_error "Available external-secrets.io resources:"
                            $CLI api-resources --api-group=external-secrets.io || true
                            exit 1
                        fi
                        echo -n "."
                        sleep 2
                    done
                    echo ""
                    
                    if [ "$API_READY" = true ]; then
                        # Verify we can actually query the resource (final validation)
                        print_info "Performing final API validation..."
                        MAX_WAIT=30
                        WAIT_COUNT=0
                        QUERY_SUCCESS=false
                        
                        while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
                            # Try to list ClusterSecretStores (should return empty list, not error)
                            if $CLI get clustersecretstores.external-secrets.io --all-namespaces &> /dev/null; then
                                print_info "API server can accept ClusterSecretStore resources"
                                QUERY_SUCCESS=true
                                break
                            fi
                            WAIT_COUNT=$((WAIT_COUNT + 1))
                            if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
                                print_error "Timeout: API server cannot accept ClusterSecretStore resources"
                                print_error "This may indicate a CRD registration issue"
                                exit 1
                            fi
                            echo -n "."
                            sleep 2
                        done
                        echo ""
                        
                        if [ "$QUERY_SUCCESS" = true ]; then
                            # Additional wait to ensure full API server cache refresh
                            print_info "Waiting 45 seconds for API server to fully cache the resource type..."
                            sleep 45
                            
                            # Final verification before Phase 2
                            print_info "Performing final pre-deployment check..."
                            if $CLI get clustersecretstores.external-secrets.io --all-namespaces &> /dev/null; then
                                print_info "External Secrets Operator is fully ready for SecretStore deployment"
                                
                                # Phase 2: Deploy SecretStores with retry mechanism
                                print_info "Phase 2: Deploying SecretStores..."
                                MAX_RETRIES=3
                                RETRY_COUNT=0
                                PHASE2_SUCCESS=false
                                
                                while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                                    if eval $HELM_CMD; then
                                        PHASE2_SUCCESS=true
                                        break
                                    else
                                        RETRY_COUNT=$((RETRY_COUNT + 1))
                                        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                                            print_warn "Phase 2 deployment failed, retrying in 15 seconds... (Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
                                            sleep 15
                                        else
                                            print_error "Phase 2 deployment failed after $MAX_RETRIES attempts"
                                            exit 1
                                        fi
                                    fi
                                done
                                
                                if [ "$PHASE2_SUCCESS" = true ]; then
                                    echo ""
                                    print_info "Phase 2 complete - SecretStores deployed successfully"
                                fi
                            else
                                print_error "Final pre-deployment check failed"
                                print_error "API server still cannot accept ClusterSecretStore resources"
                                exit 1
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi
    
    echo ""
    print_info "Deployment completed successfully!"
    echo ""
    print_info "Next steps:"
    echo "  1. Verify CSV (ClusterServiceVersion) status:"
    echo "     $CLI get csv -n $NAMESPACE"
    echo ""
    echo "  2. Verify operator pods are running:"
    echo "     $CLI get pods -n $NAMESPACE -l app=external-secrets-operator"
    echo ""
    echo "  3. Check operator logs:"
    echo "     $CLI logs -n $NAMESPACE -l app=external-secrets-operator"
    echo ""
    
    if [ "$BACKEND" = "standalone" ]; then
        echo "  4. When ready to add vault integration, redeploy with:"
        echo "     $0 --backend vault|aws|ibmcloud"
        echo ""
    else
        echo "  4. Verify ClusterSecretStore:"
        echo "     $CLI get clustersecretstore"
        echo ""
        echo "  5. Create an ExternalSecret to sync secrets:"
        echo "     See examples in: $CHART_DIR/examples/"
        echo ""
    fi
    
    print_info "For complete documentation, see: $CHART_DIR/README.md"
fi

# Made with Bob