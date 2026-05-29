#!/bin/bash
# Fusion Developer Hub - Helm Deployment Failure Diagnosis Script
# This script helps identify why a Helm deployment failed

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_section() {
    echo -e "\n${CYAN}--- $1 ---${NC}\n"
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

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Show usage
usage() {
    cat << EOF
Usage: $0 -n NAMESPACE -r RELEASE_NAME

Diagnose Helm deployment failures for Fusion Developer Hub.

REQUIRED OPTIONS:
    -n, --namespace NAME        Namespace where the deployment exists
    -r, --release NAME          Helm release name to diagnose
    -h, --help                  Show this help message

EXAMPLES:
    # Diagnose deployment in fusion-dev-hub namespace
    $0 -n fusion-dev-hub -r fusion-hub

    # Diagnose deployment with different names
    $0 --namespace my-namespace --release my-release

EOF
    exit 0
}

# Parse arguments
NAMESPACE=""
RELEASE_NAME=""

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

# Start diagnosis
print_header "Helm Deployment Failure Diagnosis"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo ""

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed"
    exit 1
fi

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    print_error "oc CLI is not installed"
    exit 1
fi

# 1. Check Helm Release Status
print_header "1. Helm Release Status"

# Check for release in helm list
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    RELEASE_STATUS=$(helm list -n "$NAMESPACE" | grep "$RELEASE_NAME" | awk '{print $8}')
    REVISION=$(helm list -n "$NAMESPACE" | grep "$RELEASE_NAME" | awk '{print $3}')
    UPDATED=$(helm list -n "$NAMESPACE" | grep "$RELEASE_NAME" | awk '{print $4, $5, $6, $7}')
    
    echo "Release Name: $RELEASE_NAME"
    echo "Status: $RELEASE_STATUS"
    echo "Revision: $REVISION"
    echo "Last Updated: $UPDATED"
    
    if [[ "$RELEASE_STATUS" == "failed" ]]; then
        print_error "Deployment is in FAILED state"
    elif [[ "$RELEASE_STATUS" == "pending-install" ]] || [[ "$RELEASE_STATUS" == "pending-upgrade" ]]; then
        print_warning "Deployment is in PENDING state"
    else
        print_success "Deployment status: $RELEASE_STATUS"
    fi
# Check for pending release in secrets
elif oc get secret -n "$NAMESPACE" -l "owner=helm,name=$RELEASE_NAME,status=pending-install" &> /dev/null; then
    print_warning "Helm release '$RELEASE_NAME' is in PENDING-INSTALL state"
    
    # Get pending release info from secret
    PENDING_SECRET=$(oc get secret -n "$NAMESPACE" -l "owner=helm,name=$RELEASE_NAME,status=pending-install" -o name 2>/dev/null | head -1)
    if [[ -n "$PENDING_SECRET" ]]; then
        echo "Release Name: $RELEASE_NAME"
        echo "Status: pending-install"
        echo "Secret: $PENDING_SECRET"
        
        print_info "Pending releases are stored in secrets and won't show in 'helm list'"
        print_info "The installation is stuck waiting for pre-install hooks to complete"
    fi
elif oc get secret -n "$NAMESPACE" -l "owner=helm,name=$RELEASE_NAME,status=pending-upgrade" &> /dev/null; then
    print_warning "Helm release '$RELEASE_NAME' is in PENDING-UPGRADE state"
    
    # Get pending release info from secret
    PENDING_SECRET=$(oc get secret -n "$NAMESPACE" -l "owner=helm,name=$RELEASE_NAME,status=pending-upgrade" -o name 2>/dev/null | head -1)
    if [[ -n "$PENDING_SECRET" ]]; then
        echo "Release Name: $RELEASE_NAME"
        echo "Status: pending-upgrade"
        echo "Secret: $PENDING_SECRET"
        
        print_info "Pending releases are stored in secrets and won't show in 'helm list'"
        print_info "The upgrade is stuck waiting for pre-upgrade hooks to complete"
    fi
else
    print_error "Helm release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
    echo ""
    print_info "Checking if namespace exists..."
    
    if oc get namespace "$NAMESPACE" &> /dev/null; then
        print_success "Namespace '$NAMESPACE' exists"
        
        echo ""
        print_info "Available Helm releases in namespace:"
        RELEASES=$(helm list -n "$NAMESPACE" --output json 2>/dev/null)
        if [[ -n "$RELEASES" ]] && [[ "$RELEASES" != "[]" ]]; then
            helm list -n "$NAMESPACE"
        else
            echo "  No Helm releases found in this namespace"
        fi
        
        echo ""
        print_info "Checking for resources in namespace..."
        RESOURCE_COUNT=$(oc get all -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        if [[ $RESOURCE_COUNT -gt 0 ]]; then
            print_warning "Found $RESOURCE_COUNT resources in namespace (not managed by Helm)"
            echo ""
            print_section "Resources in Namespace"
            oc get all -n "$NAMESPACE" 2>/dev/null
        else
            print_info "No resources found in namespace"
        fi
        
        echo ""
        print_section "Possible Causes"
        echo "1. Helm release was never created"
        echo "2. Helm release was uninstalled"
        echo "3. Helm release is in a different namespace"
        echo "4. Helm deployment failed before creating the release"
        
        echo ""
        print_section "Recommended Actions"
        echo "1. Check if you're in the correct namespace:"
        echo "   helm list -A | grep $RELEASE_NAME"
        echo ""
        echo "2. Try deploying with Helm:"
        echo "   helm install $RELEASE_NAME ./helm-charts/fusion-developer-hub \\"
        echo "     -f examples/operator-fusion-guest-access-values.yaml \\"
        echo "     --set global.wildcardDomain=apps.your-cluster.example.com \\"
        echo "     --namespace $NAMESPACE --create-namespace"
        echo ""
        echo "3. Check Helm deployment logs:"
        echo "   helm install $RELEASE_NAME ./helm-charts/fusion-developer-hub \\"
        echo "     -f examples/operator-fusion-guest-access-values.yaml \\"
        echo "     --set global.wildcardDomain=apps.your-cluster.example.com \\"
        echo "     --namespace $NAMESPACE --create-namespace --debug"
        
    else
        print_error "Namespace '$NAMESPACE' does not exist"
        echo ""
        print_info "Create the namespace and deploy:"
        echo "   helm install $RELEASE_NAME ./helm-charts/fusion-developer-hub \\"
        echo "     -f examples/operator-fusion-guest-access-values.yaml \\"
        echo "     --set global.wildcardDomain=apps.your-cluster.example.com \\"
        echo "     --namespace $NAMESPACE --create-namespace"
    fi
    
    exit 1
fi

# 2. Get Helm Release History
print_header "2. Helm Release History"

print_info "Release history:"
helm history "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || print_warning "Could not retrieve release history"

# 3. Get Helm Release Values
print_header "3. Helm Release Values"

print_info "Checking deployed values..."
if helm get values "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
    print_success "Values retrieved successfully"
    echo ""
    print_section "Deployed Values"
    helm get values "$RELEASE_NAME" -n "$NAMESPACE"
else
    print_error "Could not retrieve release values"
fi

# 4. Get Helm Release Manifest
print_header "4. Helm Release Manifest"

print_info "Checking deployed manifest..."
MANIFEST_FILE="/tmp/helm-manifest-${RELEASE_NAME}.yaml"
if helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" > "$MANIFEST_FILE" 2>/dev/null; then
    print_success "Manifest retrieved successfully"
    RESOURCE_COUNT=$(grep -c "^kind:" "$MANIFEST_FILE" || echo "0")
    print_info "Total resources in manifest: $RESOURCE_COUNT"
    
    echo ""
    print_section "Resource Types"
    grep "^kind:" "$MANIFEST_FILE" | sort | uniq -c | while read -r line; do
        echo "  $line"
    done
else
    print_error "Could not retrieve release manifest"
fi

# 5. Check Helm Hooks
print_header "5. Helm Hooks Status"

print_info "Checking for Helm hooks..."
if [[ -f "$MANIFEST_FILE" ]]; then
    HOOKS=$(grep -A 5 "helm.sh/hook" "$MANIFEST_FILE" | grep "name:" | awk '{print $2}' | sort -u)
    if [[ -n "$HOOKS" ]]; then
        print_success "Found Helm hooks"
        echo ""
        for hook in $HOOKS; do
            print_section "Hook: $hook"
            
            # Check if it's a Job
            if oc get job "$hook" -n "$NAMESPACE" &> /dev/null; then
                JOB_STATUS=$(oc get job "$hook" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")
                FAILED_STATUS=$(oc get job "$hook" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "Unknown")
                
                if [[ "$JOB_STATUS" == "True" ]]; then
                    print_success "Job completed successfully"
                elif [[ "$FAILED_STATUS" == "True" ]]; then
                    print_error "Job failed"
                    
                    # Get job pods
                    HOOK_PODS=$(oc get pods -n "$NAMESPACE" -l job-name="$hook" --no-headers 2>/dev/null | awk '{print $1}')
                    if [[ -n "$HOOK_PODS" ]]; then
                        for pod in $HOOK_PODS; do
                            print_section "Hook Pod Logs: $pod"
                            oc logs "$pod" -n "$NAMESPACE" --tail=50 2>/dev/null || print_warning "Could not retrieve logs"
                        done
                    fi
                else
                    print_warning "Job status unknown"
                fi
                
                # Show job details
                echo ""
                print_info "Job details:"
                oc describe job "$hook" -n "$NAMESPACE" 2>/dev/null | tail -20
            fi
        done
    else
        print_info "No Helm hooks found"
    fi
fi

# 6. Check Namespace
print_header "6. Namespace Status"

if oc get namespace "$NAMESPACE" &> /dev/null; then
    print_success "Namespace '$NAMESPACE' exists"
    
    # Check namespace status
    NS_STATUS=$(oc get namespace "$NAMESPACE" -o jsonpath='{.status.phase}')
    print_info "Namespace phase: $NS_STATUS"
    
    # Check resource quotas
    if oc get resourcequota -n "$NAMESPACE" &> /dev/null; then
        QUOTA_COUNT=$(oc get resourcequota -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        if [[ $QUOTA_COUNT -gt 0 ]]; then
            print_warning "Resource quotas are configured"
            echo ""
            print_section "Resource Quotas"
            oc get resourcequota -n "$NAMESPACE" 2>/dev/null
        fi
    fi
    
    # Check limit ranges
    if oc get limitrange -n "$NAMESPACE" &> /dev/null; then
        LIMIT_COUNT=$(oc get limitrange -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        if [[ $LIMIT_COUNT -gt 0 ]]; then
            print_info "Limit ranges are configured"
        fi
    fi
else
    print_error "Namespace '$NAMESPACE' does not exist"
fi

# 7. Check Resources Created by Helm
print_header "7. Resources Created by Helm"

print_info "Checking resources in namespace..."
echo ""

# Check all resource types
RESOURCE_TYPES=("deployment" "statefulset" "daemonset" "job" "pod" "service" "route" "configmap" "secret" "pvc" "backstage" "postgrescluster")

for resource_type in "${RESOURCE_TYPES[@]}"; do
    RESOURCES=$(oc get "$resource_type" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ $RESOURCES -gt 0 ]]; then
        print_section "$resource_type (Count: $RESOURCES)"
        oc get "$resource_type" -n "$NAMESPACE" 2>/dev/null
    fi
done

# 8. Check Failed Pods
print_header "8. Failed Pods Analysis"

FAILED_PODS=$(oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -E "Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|Pending|Init:Error|Init:CrashLoopBackOff" | awk '{print $1}')

if [[ -n "$FAILED_PODS" ]]; then
    print_error "Found failed pods"
    echo ""
    
    for pod in $FAILED_PODS; do
        print_section "Failed Pod: $pod"
        
        # Get pod status
        POD_STATUS=$(oc get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        print_info "Status: $POD_STATUS"
        
        # Get pod events
        print_info "Recent events:"
        oc get events -n "$NAMESPACE" --field-selector involvedObject.name="$pod" --sort-by='.lastTimestamp' 2>/dev/null | tail -5
        
        # Get pod logs
        echo ""
        print_info "Pod logs (last 30 lines):"
        oc logs "$pod" -n "$NAMESPACE" --tail=30 2>/dev/null || print_warning "Could not retrieve logs"
        
        # Check init containers
        INIT_CONTAINERS=$(oc get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null)
        if [[ -n "$INIT_CONTAINERS" ]]; then
            echo ""
            print_info "Init container logs:"
            for init_container in $INIT_CONTAINERS; do
                echo ""
                print_section "Init Container: $init_container"
                oc logs "$pod" -n "$NAMESPACE" -c "$init_container" --tail=20 2>/dev/null || print_warning "Could not retrieve init container logs"
            done
        fi
        
        echo ""
        echo "---"
    done
else
    print_success "No failed pods found"
fi

# 9. Check Events
print_header "9. Recent Events for Helm Release Resources"

# Get list of resources created by this Helm release
HELM_RESOURCES=$(helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null | grep "^kind:" | awk '{print tolower($2)}' | sort -u)

print_info "Filtering events for Helm release resources only..."
echo ""

# Get events for resources with the release label
RELEASE_EVENTS=$(oc get events -n "$NAMESPACE" \
    --field-selector involvedObject.name!="" \
    --sort-by='.lastTimestamp' 2>/dev/null | \
    grep -E "backstage-$RELEASE_NAME|$RELEASE_NAME|fusion-guest-postgres" | tail -20)

if [[ -n "$RELEASE_EVENTS" ]]; then
    echo "$RELEASE_EVENTS"
else
    print_info "No recent events found for Helm release resources"
fi

# Check for error/warning events related to this release
echo ""
ERROR_EVENTS=$(oc get events -n "$NAMESPACE" \
    --field-selector involvedObject.name!="" \
    --sort-by='.lastTimestamp' 2>/dev/null | \
    grep -E "backstage-$RELEASE_NAME|$RELEASE_NAME|fusion-guest-postgres" | \
    grep -i "error\|failed\|warning" | tail -10)

if [[ -n "$ERROR_EVENTS" ]]; then
    print_warning "Recent error/warning events for this release:"
    echo "$ERROR_EVENTS"
else
    print_success "No error/warning events for this release"
fi

# 10. Check Operators
print_header "10. Operator Status"

# Check RHDH Operator
print_section "Red Hat Developer Hub Operator"
if oc get csv -n rhdh-operator 2>/dev/null | grep -q "rhdh-operator"; then
    RHDH_CSV=$(oc get csv -n rhdh-operator -o name 2>/dev/null | head -1)
    RHDH_PHASE=$(oc get "$RHDH_CSV" -n rhdh-operator -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    
    if [[ "$RHDH_PHASE" == "Succeeded" ]]; then
        print_success "RHDH Operator is ready"
    else
        print_error "RHDH Operator phase: $RHDH_PHASE"
        echo ""
        print_info "Operator details:"
        oc describe "$RHDH_CSV" -n rhdh-operator 2>/dev/null | tail -20
    fi
else
    print_error "RHDH Operator not found"
fi

# Check PostgreSQL Operator
echo ""
print_section "PostgreSQL Operator"

# Check if PostgreSQL operator exists (try multiple common namespaces)
PG_FOUND=false
for ns in postgres-operator pgo openshift-operators; do
    if oc get csv -n "$ns" 2>/dev/null | grep -q "postgres"; then
        PG_CSV=$(oc get csv -n "$ns" -o name 2>/dev/null | grep postgres | head -1)
        if [[ -n "$PG_CSV" ]]; then
            PG_PHASE=$(oc get "$PG_CSV" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            PG_NAMESPACE="$ns"
            PG_FOUND=true
            break
        fi
    fi
done

if [[ "$PG_FOUND" == "true" ]]; then
    if [[ "$PG_PHASE" == "Succeeded" ]]; then
        print_success "PostgreSQL Operator is ready (namespace: $PG_NAMESPACE)"
    else
        print_warning "PostgreSQL Operator phase: $PG_PHASE (namespace: $PG_NAMESPACE)"
        echo ""
        print_info "Operator details:"
        oc describe "$PG_CSV" -n "$PG_NAMESPACE" 2>/dev/null | tail -20
    fi
else
    print_warning "PostgreSQL Operator not found in common namespaces"
    print_info "Checking if PostgresCluster CRD exists (operator may be installed elsewhere)..."
    if oc get crd postgresclusters.postgres-operator.crunchydata.com &> /dev/null; then
        print_success "PostgresCluster CRD exists - operator is installed"
    else
        print_error "PostgreSQL Operator not installed"
    fi
fi

# 11. Check CRDs
print_header "11. Custom Resource Definitions"

# Check Backstage CRD
if oc get crd backstages.rhdh.redhat.com &> /dev/null; then
    print_success "Backstage CRD exists"
    
    # Check Backstage instances
    if oc get backstage -n "$NAMESPACE" &> /dev/null; then
        BACKSTAGE_COUNT=$(oc get backstage -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        print_info "Backstage instances: $BACKSTAGE_COUNT"
        
        if [[ $BACKSTAGE_COUNT -gt 0 ]]; then
            echo ""
            print_section "Backstage Instance Status"
            oc get backstage -n "$NAMESPACE" 2>/dev/null
            
            # Get detailed status
            BACKSTAGE_NAME=$(oc get backstage -n "$NAMESPACE" -o name 2>/dev/null | head -1 | cut -d'/' -f2)
            if [[ -n "$BACKSTAGE_NAME" ]]; then
                echo ""
                print_info "Backstage instance details:"
                oc describe backstage "$BACKSTAGE_NAME" -n "$NAMESPACE" 2>/dev/null | tail -30
            fi
        fi
    fi
else
    print_error "Backstage CRD not found"
fi

# Check PostgresCluster CRD
echo ""
if oc get crd postgresclusters.postgres-operator.crunchydata.com &> /dev/null; then
    print_success "PostgresCluster CRD exists"
    
    # Check PostgresCluster instances
    if oc get postgrescluster -n "$NAMESPACE" &> /dev/null; then
        PG_COUNT=$(oc get postgrescluster -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        print_info "PostgreSQL clusters: $PG_COUNT"
        
        if [[ $PG_COUNT -gt 0 ]]; then
            echo ""
            print_section "PostgreSQL Cluster Status"
            oc get postgrescluster -n "$NAMESPACE" 2>/dev/null
            
            # Get detailed status
            PG_NAME=$(oc get postgrescluster -n "$NAMESPACE" -o name 2>/dev/null | head -1 | cut -d'/' -f2)
            if [[ -n "$PG_NAME" ]]; then
                echo ""
                print_info "PostgreSQL cluster details:"
                oc describe postgrescluster "$PG_NAME" -n "$NAMESPACE" 2>/dev/null | tail -30
            fi
        fi
    fi
else
    print_error "PostgresCluster CRD not found"
fi

# 12. Common Issues Check
print_header "12. Common Issues Check"

# Get current pod names for this release
CURRENT_BACKSTAGE_POD=$(oc get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=backstage,app.kubernetes.io/instance=$RELEASE_NAME" -o name 2>/dev/null | head -1 | cut -d'/' -f2)
CURRENT_PG_POD=$(oc get pods -n "$NAMESPACE" -l "postgres-operator.crunchydata.com/cluster=$DB_CLUSTER_NAME" -o name 2>/dev/null | head -1 | cut -d'/' -f2)

# Check for image pull errors (only for current release pods)
IMAGE_PULL_ERRORS=0
if [[ -n "$CURRENT_BACKSTAGE_POD" ]]; then
    IMAGE_PULL_ERRORS=$((IMAGE_PULL_ERRORS + $(oc get events -n "$NAMESPACE" 2>/dev/null | grep "$CURRENT_BACKSTAGE_POD" | grep -i "imagepull\|errimagepull" | wc -l)))
fi
if [[ -n "$CURRENT_PG_POD" ]]; then
    IMAGE_PULL_ERRORS=$((IMAGE_PULL_ERRORS + $(oc get events -n "$NAMESPACE" 2>/dev/null | grep "$CURRENT_PG_POD" | grep -i "imagepull\|errimagepull" | wc -l)))
fi

if [[ $IMAGE_PULL_ERRORS -gt 0 ]]; then
    print_error "Found $IMAGE_PULL_ERRORS image pull error(s) for this release"
    print_info "This usually indicates:"
    echo "  - Image does not exist"
    echo "  - Image registry is unreachable"
    echo "  - Authentication required for private registry"
else
    print_success "No image pull errors for this release"
fi

# Check for resource quota issues (only for current release)
QUOTA_ERRORS=$(oc get events -n "$NAMESPACE" 2>/dev/null | grep -E "backstage-$RELEASE_NAME|$DB_CLUSTER_NAME" | grep -i "quota\|exceeded" | wc -l)
if [[ $QUOTA_ERRORS -gt 0 ]]; then
    print_error "Found $QUOTA_ERRORS resource quota error(s) for this release"
    print_info "Check resource quotas and limits"
else
    print_success "No resource quota errors for this release"
fi

# Check for PVC issues (only for this release's PVCs)
PVC_ERRORS=$(oc get events -n "$NAMESPACE" 2>/dev/null | grep -E "dynamic-plugins-root|$DB_CLUSTER_NAME.*pgdata" | grep -i "error\|failed" | wc -l)
if [[ $PVC_ERRORS -gt 0 ]]; then
    print_error "Found $PVC_ERRORS PVC error(s) for this release"
    print_info "Check storage class and PVC status"
else
    print_success "No PVC errors for this release"
fi

# Check for secret errors (only for this release)
SECRET_ERRORS=$(oc get events -n "$NAMESPACE" 2>/dev/null | grep -E "backstage-$RELEASE_NAME|$DB_CLUSTER_NAME" | grep -i "secret.*not found" | wc -l)
if [[ $SECRET_ERRORS -gt 0 ]]; then
    print_error "Found $SECRET_ERRORS secret error(s) for this release"
    print_info "Check if required secrets exist"
else
    print_success "No secret errors for this release"
fi

# 13. Recommendations
print_header "13. Recommendations"

echo "Based on the diagnosis, here are recommended actions:"
echo ""

if [[ "$RELEASE_STATUS" == "failed" ]]; then
    print_info "1. Review the errors above to identify the root cause"
    print_info "2. Check operator installation and readiness"
    print_info "3. Verify CRDs are installed"
    print_info "4. Check for resource constraints"
    print_info "5. Review pod logs for specific errors"
    echo ""
    print_info "To retry deployment:"
    echo "   helm upgrade $RELEASE_NAME ./helm-charts/fusion-developer-hub \\"
    echo "     -f examples/operator-fusion-development-values.yaml \\"
    echo "     --set global.wildcardDomain=apps.your-cluster.example.com \\"
    echo "     --namespace $NAMESPACE"
    echo ""
    print_info "To start fresh:"
    echo "   helm uninstall $RELEASE_NAME -n $NAMESPACE"
    echo "   oc delete namespace $NAMESPACE"
    echo "   helm install $RELEASE_NAME ./helm-charts/fusion-developer-hub \\"
    echo "     -f examples/operator-fusion-development-values.yaml \\"
    echo "     --set global.wildcardDomain=apps.your-cluster.example.com \\"
    echo "     --namespace $NAMESPACE --create-namespace"
fi

# 14. Summary
print_header "14. Diagnosis Summary"

echo "Helm Release: $RELEASE_NAME"
echo "Namespace: $NAMESPACE"
echo "Status: $RELEASE_STATUS"
echo "Revision: $REVISION"
echo ""

if [[ "$RELEASE_STATUS" == "failed" ]]; then
    print_error "Deployment has failed. Review the diagnosis above for details."
    echo ""
    print_info "For more help, see:"
    echo "  - Troubleshooting Guide: docs/troubleshooting/README.md"
    echo "  - Deployment Guide: docs/getting-started/operator-getting-started.md"
    exit 1
else
    print_success "Deployment status is: $RELEASE_STATUS"
    exit 0
fi

# Made with Bob
