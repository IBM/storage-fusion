#!/bin/bash
# GitOps (ArgoCD) validation script
# Validates that Red Hat OpenShift GitOps is deployed correctly and operational

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source common functions
source "${SCRIPT_DIR}/lib/common.sh"

# Default values
NAMESPACE="openshift-gitops"
OPERATOR_NAMESPACE="openshift-gitops-operator"
VERBOSE=false
CHECK_RESULTS=()
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Red Hat OpenShift GitOps (ArgoCD) deployment.

OPTIONS:
    -n, --namespace NAME        ArgoCD namespace (default: openshift-gitops)
    -o, --operator-ns NAME      Operator namespace (default: openshift-gitops-operator)
    -v, --verbose              Enable verbose output
    -h, --help                 Show this help message

EXAMPLES:
    # Validate default GitOps installation
    $0

    # Validate with verbose output
    $0 --verbose

    # Validate custom namespace
    $0 -n my-gitops-namespace

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
        -o|--operator-ns)
            OPERATOR_NAMESPACE="$2"
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
elif command -v kubectl &> /dev/null; then
    CLI="kubectl"
else
    log_error "Neither 'oc' nor 'kubectl' found. Please install one of them."
    exit 1
fi

log_info "Using $([ "$CLI" = "oc" ] && echo "OpenShift CLI (oc)" || echo "Kubernetes CLI (kubectl)")"

# Function to record check results
record_result() {
    local result=$1
    case $result in
        pass)
            ((CHECKS_PASSED++))
            ;;
        fail)
            ((CHECKS_FAILED++))
            ;;
        warning)
            ((CHECKS_WARNING++))
            ;;
    esac
}

# Print header
echo ""
echo "============================================================"
echo "            GitOps (ArgoCD) Deployment Validation"
echo "============================================================"
echo ""
echo "Namespace: $NAMESPACE"
echo "Operator Namespace: $OPERATOR_NAMESPACE"
CURRENT_CONTEXT=$($CLI config current-context 2>/dev/null || echo "unknown")
echo "Cluster: $CURRENT_CONTEXT"
echo ""

# Check 1: Operator Subscription
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Checking GitOps Operator Subscription..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SUBSCRIPTION=$($CLI get subscription -n "$OPERATOR_NAMESPACE" -l operators.coreos.com/openshift-gitops-operator.$OPERATOR_NAMESPACE="" -o name 2>/dev/null || echo "")

if [ -n "$SUBSCRIPTION" ]; then
    SUB_NAME=$(echo "$SUBSCRIPTION" | sed 's|subscription.operators.coreos.com/||')
    SUB_STATE=$($CLI get subscription "$SUB_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
    
    if [ "$SUB_STATE" = "AtLatestKnown" ]; then
        log_success "✓ Operator subscription found: $SUB_NAME (State: $SUB_STATE)"
        record_result pass
    else
        log_warning "⚠ Operator subscription found but state is: $SUB_STATE"
        record_result warning
    fi
    
    if [ "$VERBOSE" = true ]; then
        $CLI get subscription "$SUB_NAME" -n "$OPERATOR_NAMESPACE" -o yaml
    fi
else
    log_error "✗ GitOps operator subscription not found in namespace $OPERATOR_NAMESPACE"
    record_result fail
fi
echo ""

# Check 2: Operator CSV (ClusterServiceVersion)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Checking Operator ClusterServiceVersion..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CSV=$($CLI get csv -n "$OPERATOR_NAMESPACE" -l operators.coreos.com/openshift-gitops-operator.$OPERATOR_NAMESPACE="" -o name 2>/dev/null | head -1 || echo "")

if [ -n "$CSV" ]; then
    CSV_NAME=$(echo "$CSV" | sed 's|clusterserviceversion.operators.coreos.com/||')
    CSV_PHASE=$($CLI get csv "$CSV_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    
    if [ "$CSV_PHASE" = "Succeeded" ]; then
        log_success "✓ Operator CSV: $CSV_NAME (Phase: $CSV_PHASE)"
        record_result pass
    else
        log_error "✗ Operator CSV phase is: $CSV_PHASE"
        record_result fail
    fi
else
    log_error "✗ Operator CSV not found"
    record_result fail
fi
echo ""

# Check 3: Operator Pods
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Checking Operator Pods..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

OPERATOR_PODS=$($CLI get pods -n "$OPERATOR_NAMESPACE" -l control-plane=gitops-operator -o name 2>/dev/null || echo "")

if [ -n "$OPERATOR_PODS" ]; then
    POD_COUNT=$(echo "$OPERATOR_PODS" | wc -l | tr -d ' ')
    log_info "Found $POD_COUNT operator pod(s)"
    
    ALL_READY=true
    for pod in $OPERATOR_PODS; do
        POD_NAME=$(echo "$pod" | sed 's|pod/||')
        POD_STATUS=$($CLI get pod "$POD_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        POD_READY=$($CLI get pod "$POD_NAME" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        
        if [ "$POD_STATUS" = "Running" ] && [ "$POD_READY" = "True" ]; then
            log_success "✓ $POD_NAME: Running and Ready"
        else
            log_error "✗ $POD_NAME: Status=$POD_STATUS, Ready=$POD_READY"
            ALL_READY=false
        fi
    done
    
    if [ "$ALL_READY" = true ]; then
        record_result pass
    else
        record_result fail
    fi
else
    log_error "✗ No operator pods found"
    record_result fail
fi
echo ""

# Check 4: ArgoCD Instance
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Checking ArgoCD Instance..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ARGOCD_INSTANCE=$($CLI get argocd -n "$NAMESPACE" -o name 2>/dev/null | head -1 || echo "")

if [ -n "$ARGOCD_INSTANCE" ]; then
    ARGOCD_NAME=$(echo "$ARGOCD_INSTANCE" | sed 's|argocd.argoproj.io/||')
    ARGOCD_PHASE=$($CLI get argocd "$ARGOCD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    
    if [ "$ARGOCD_PHASE" = "Available" ] || [ "$ARGOCD_PHASE" = "Running" ]; then
        log_success "✓ ArgoCD instance found: $ARGOCD_NAME (Phase: $ARGOCD_PHASE)"
        record_result pass
    else
        log_warning "⚠ ArgoCD instance phase is: $ARGOCD_PHASE"
        record_result warning
    fi
    
    if [ "$VERBOSE" = true ]; then
        $CLI get argocd "$ARGOCD_NAME" -n "$NAMESPACE" -o yaml
    fi
else
    log_error "✗ No ArgoCD instance found in namespace $NAMESPACE"
    record_result fail
fi
echo ""

# Check 5: ArgoCD Pods
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. Checking ArgoCD Pods..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ARGOCD_PODS=$($CLI get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -E "openshift-gitops|cluster-" || echo "")

if [ -n "$ARGOCD_PODS" ]; then
    POD_COUNT=$(echo "$ARGOCD_PODS" | wc -l | tr -d ' ')
    log_info "Found $POD_COUNT ArgoCD pod(s)"
    
    # Check key components (OpenShift GitOps naming)
    COMPONENTS=("application-controller" "applicationset-controller" "dex-server" "redis-ha" "repo-server" "server")
    ALL_COMPONENTS_READY=true
    
    for component in "${COMPONENTS[@]}"; do
        COMPONENT_PODS=$($CLI get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=openshift-gitops-$component" -o name 2>/dev/null || echo "")
        
        if [ -n "$COMPONENT_PODS" ]; then
            COMPONENT_COUNT=$(echo "$COMPONENT_PODS" | wc -l | tr -d ' ')
            READY_COUNT=0
            
            for pod in $COMPONENT_PODS; do
                POD_NAME=$(echo "$pod" | sed 's|pod/||')
                POD_READY=$($CLI get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
                
                if [ "$POD_READY" = "True" ]; then
                    ((READY_COUNT++))
                fi
            done
            
            if [ "$READY_COUNT" -eq "$COMPONENT_COUNT" ]; then
                log_success "✓ $component: $READY_COUNT/$COMPONENT_COUNT pods ready"
            else
                log_error "✗ $component: $READY_COUNT/$COMPONENT_COUNT pods ready"
                ALL_COMPONENTS_READY=false
            fi
        else
            log_warning "⚠ $component: No pods found"
            if [ "$component" != "dex-server" ] && [ "$component" != "server" ]; then
                ALL_COMPONENTS_READY=false
            fi
        fi
    done
    
    if [ "$ALL_COMPONENTS_READY" = true ]; then
        record_result pass
    else
        record_result fail
    fi
else
    log_error "✗ No ArgoCD pods found"
    record_result fail
fi
echo ""

# Check 6: ArgoCD Services
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. Checking ArgoCD Services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SERVICES=$($CLI get svc -n "$NAMESPACE" --no-headers 2>/dev/null | grep -E "openshift-gitops|cluster" || echo "")

if [ -n "$SERVICES" ]; then
    SERVICE_COUNT=$(echo "$SERVICES" | wc -l | tr -d ' ')
    log_info "Found $SERVICE_COUNT ArgoCD service(s)"
    
    # Check for key services (OpenShift GitOps naming)
    KEY_SERVICES=("server" "repo-server" "redis-ha")
    ALL_SERVICES_FOUND=true
    
    for svc in "${KEY_SERVICES[@]}"; do
        SVC_EXISTS=$($CLI get svc -n "$NAMESPACE" -l "app.kubernetes.io/name=openshift-gitops-$svc" -o name 2>/dev/null || echo "")
        
        if [ -n "$SVC_EXISTS" ]; then
            SVC_NAME=$(echo "$SVC_EXISTS" | head -1 | sed 's|service/||')
            SVC_TYPE=$($CLI get svc "$SVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.type}' 2>/dev/null || echo "Unknown")
            SVC_PORT=$($CLI get svc "$SVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "Unknown")
            log_success "✓ Service: $SVC_NAME (Type: $SVC_TYPE, Port: $SVC_PORT)"
        else
            log_error "✗ Service not found: $svc"
            ALL_SERVICES_FOUND=false
        fi
    done
    
    if [ "$ALL_SERVICES_FOUND" = true ]; then
        record_result pass
    else
        record_result fail
    fi
else
    log_error "✗ No ArgoCD services found"
    record_result fail
fi
echo ""

# Check 7: ArgoCD Route/Ingress
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. Checking ArgoCD Route/Ingress..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$CLI" = "oc" ]; then
    ROUTE=$($CLI get route -n "$NAMESPACE" --no-headers 2>/dev/null | grep "openshift-gitops-server" | awk '{print "route.route.openshift.io/"$1}' || echo "")
    
    if [ -n "$ROUTE" ]; then
        ROUTE_NAME=$(echo "$ROUTE" | sed 's|route.route.openshift.io/||')
        ROUTE_HOST=$($CLI get route "$ROUTE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
        ROUTE_TLS=$($CLI get route "$ROUTE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.tls.termination}' 2>/dev/null || echo "none")
        
        if [ -n "$ROUTE_HOST" ]; then
            log_success "✓ ArgoCD route found: https://$ROUTE_HOST (TLS: $ROUTE_TLS)"
            record_result pass
        else
            log_error "✗ Route found but no host configured"
            record_result fail
        fi
    else
        log_warning "⚠ No ArgoCD route found (may use port-forward)"
        record_result warning
    fi
else
    INGRESS=$($CLI get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | grep "openshift-gitops" | awk '{print "ingress.networking.k8s.io/"$1}' | head -1 || echo "")
    
    if [ -n "$INGRESS" ]; then
        INGRESS_NAME=$(echo "$INGRESS" | sed 's|ingress.networking.k8s.io/||')
        INGRESS_HOST=$($CLI get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
        
        if [ -n "$INGRESS_HOST" ]; then
            log_success "✓ ArgoCD ingress found: $INGRESS_HOST"
            record_result pass
        else
            log_error "✗ Ingress found but no host configured"
            record_result fail
        fi
    else
        log_warning "⚠ No ArgoCD ingress found (may use port-forward)"
        record_result warning
    fi
fi
echo ""

# Check 8: ArgoCD Server Health
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8. Checking ArgoCD Server Health..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SERVER_POD=$($CLI get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openshift-gitops-server -o name 2>/dev/null | head -1 || echo "")

if [ -n "$SERVER_POD" ]; then
    POD_NAME=$(echo "$SERVER_POD" | sed 's|pod/||')
    
    # Check if server is responding
    HEALTH_CHECK=$($CLI exec -n "$NAMESPACE" "$POD_NAME" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/healthz 2>/dev/null || echo "000")
    
    if [ "$HEALTH_CHECK" = "200" ]; then
        log_success "✓ ArgoCD server is healthy (HTTP 200)"
        record_result pass
    else
        log_warning "⚠ ArgoCD server health check returned: $HEALTH_CHECK"
        record_result warning
    fi
else
    log_error "✗ No ArgoCD server pod found"
    record_result fail
fi
echo ""

# Check 9: ArgoCD Applications
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "9. Checking ArgoCD Applications..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

APPLICATIONS=$($CLI get applications -n "$NAMESPACE" -o name 2>/dev/null || echo "")

if [ -n "$APPLICATIONS" ]; then
    APP_COUNT=$(echo "$APPLICATIONS" | wc -l | tr -d ' ')
    log_info "Found $APP_COUNT ArgoCD application(s)"
    
    HEALTHY_COUNT=0
    SYNCED_COUNT=0
    
    for app in $APPLICATIONS; do
        APP_NAME=$(echo "$app" | sed 's|application.argoproj.io/||')
        HEALTH=$($CLI get application "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        SYNC=$($CLI get application "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        
        if [ "$HEALTH" = "Healthy" ]; then
            ((HEALTHY_COUNT++))
        fi
        
        if [ "$SYNC" = "Synced" ]; then
            ((SYNCED_COUNT++))
        fi
        
        if [ "$VERBOSE" = true ]; then
            echo "  $APP_NAME: Health=$HEALTH, Sync=$SYNC"
        fi
    done
    
    log_info "  Healthy: $HEALTHY_COUNT/$APP_COUNT"
    log_info "  Synced: $SYNCED_COUNT/$APP_COUNT"
    
    if [ "$HEALTHY_COUNT" -eq "$APP_COUNT" ] && [ "$SYNCED_COUNT" -eq "$APP_COUNT" ]; then
        log_success "✓ All applications are healthy and synced"
        record_result pass
    else
        log_warning "⚠ Some applications are not healthy or synced"
        record_result warning
    fi
else
    log_info "No ArgoCD applications found (this is normal for new installations)"
    record_result pass
fi
# Check 10: ArgoCD AppProjects
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "10. Checking ArgoCD AppProjects..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

APPPROJECTS=$($CLI get appproject -n "$NAMESPACE" -o name 2>/dev/null || echo "")

if [ -n "$APPPROJECTS" ]; then
    PROJECT_COUNT=$(echo "$APPPROJECTS" | wc -l | tr -d ' ')
    log_info "Found $PROJECT_COUNT AppProject(s)"
    
    for project in $APPPROJECTS; do
        PROJECT_NAME=$(echo "$project" | sed 's|appproject.argoproj.io/||')
        
        if [ "$VERBOSE" = true ]; then
            # Get project details
            SOURCE_REPOS=$($CLI get appproject "$PROJECT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.sourceRepos}' 2>/dev/null || echo "[]")
            DESTINATIONS=$($CLI get appproject "$PROJECT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.destinations}' 2>/dev/null || echo "[]")
            echo "  $PROJECT_NAME:"
            echo "    Source Repos: $SOURCE_REPOS"
            echo "    Destinations: $DESTINATIONS"
        else
            log_info "  - $PROJECT_NAME"
        fi
    done
    
    log_success "✓ AppProjects configured"
    record_result pass
else
    log_info "No AppProjects found (using default project)"
    record_result pass
fi
echo ""

# Check 11: ArgoCD Cluster Connections
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "11. Checking ArgoCD Cluster Connections..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ArgoCD stores cluster credentials as secrets with label argocd.argoproj.io/secret-type=cluster
CLUSTER_SECRETS=$($CLI get secrets -n "$NAMESPACE" -l argocd.argoproj.io/secret-type=cluster -o name 2>/dev/null || echo "")

if [ -n "$CLUSTER_SECRETS" ]; then
    CLUSTER_COUNT=$(echo "$CLUSTER_SECRETS" | wc -l | tr -d ' ')
    log_info "Found $CLUSTER_COUNT external cluster(s) connected"
    
    for secret in $CLUSTER_SECRETS; do
        SECRET_NAME=$(echo "$secret" | sed 's|secret/||')
        CLUSTER_NAME=$($CLI get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.name}' 2>/dev/null | base64 -d 2>/dev/null || echo "unknown")
        CLUSTER_SERVER=$($CLI get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.server}' 2>/dev/null | base64 -d 2>/dev/null || echo "unknown")
        
        if [ "$VERBOSE" = true ]; then
            echo "  Cluster: $CLUSTER_NAME"
            echo "    Server: $CLUSTER_SERVER"
            echo "    Secret: $SECRET_NAME"
        else
            log_info "  - $CLUSTER_NAME ($CLUSTER_SERVER)"
        fi
    done
    
    log_success "✓ External clusters configured"
    record_result pass
else
    log_info "No external clusters connected (using in-cluster only)"
    log_info "  In-cluster server: https://kubernetes.default.svc"
    record_result pass
fi
echo ""

echo ""

# Check 12: Pod Logs for Errors
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "12. Checking Pod Logs for Errors..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CRITICAL_ERRORS=false
SERVER_POD=$($CLI get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openshift-gitops-server -o name 2>/dev/null | head -1 || echo "")

if [ -n "$SERVER_POD" ]; then
    POD_NAME=$(echo "$SERVER_POD" | sed 's|pod/||')
    echo "Checking logs for $POD_NAME..."
    
    LOGS=$($CLI logs "$POD_NAME" -n "$NAMESPACE" --tail=100 2>/dev/null || echo "")
    
    # Check for critical errors
    if echo "$LOGS" | grep -qi "panic\|fatal\|error.*failed to start"; then
        log_error "✗ Found critical errors in server logs"
        CRITICAL_ERRORS=true
        
        if [ "$VERBOSE" = true ]; then
            echo "$LOGS" | grep -i "panic\|fatal\|error" | tail -10
        fi
    else
        log_success "✓ No critical errors found in server logs"
    fi
fi

if [ "$CRITICAL_ERRORS" = true ]; then
    record_result fail
else
    record_result pass
fi
echo ""

# Summary
echo ""
echo "============================================================"
echo "                     Validation Summary"
echo "============================================================"
echo ""
echo "Checks Passed:   $CHECKS_PASSED"
echo "Checks Failed:   $CHECKS_FAILED"
echo "Checks Warning:  $CHECKS_WARNING"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    log_success "✓ All critical checks passed!"
    echo ""
    log_info "GitOps is deployed and operational"
    echo ""
    
    # Get ArgoCD route
    if [ "$CLI" = "oc" ]; then
        ROUTE_HOST=$($CLI get route -n "$NAMESPACE" --no-headers 2>/dev/null | grep "openshift-gitops-server" | awk '{print $2}' || echo "")
        
        if [ -n "$ROUTE_HOST" ]; then
            log_info "To access ArgoCD:"
            echo "  1. Access ArgoCD UI:"
            echo "     https://$ROUTE_HOST"
            echo ""
            echo "  2. Login with OpenShift:"
            echo "     Click 'LOG IN VIA OPENSHIFT' button"
            echo "     Use your OpenShift credentials"
            echo ""
            echo "  Alternative - Admin user (if needed):"
            echo "     Username: admin"
            echo "     Password: oc get secret openshift-gitops-cluster -n $NAMESPACE -o jsonpath='{.data.admin\.password}' | base64 -d"
            echo ""
            echo "  Note: OpenShift SSO is the recommended authentication method"
        fi
    fi
    
    exit 0
else
    log_error "✗ Validation failed with $CHECKS_FAILED error(s)"
    echo ""
    log_info "Troubleshooting steps:"
    echo "  1. Check operator logs:"
    echo "     $CLI logs -n $OPERATOR_NAMESPACE -l control-plane=gitops-operator"
    echo ""
    echo "  2. Check ArgoCD server logs:"
    echo "     $CLI logs -n $NAMESPACE -l app.kubernetes.io/name=server"
    echo ""
    echo "  3. Check ArgoCD instance status:"
    echo "     $CLI get argocd -n $NAMESPACE -o yaml"
    echo ""
    exit 1
fi

# Made with Bob
