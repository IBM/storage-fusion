#!/bin/bash
# Fusion Developer Hub - Deployment Verification Script
# This script performs comprehensive validation of the Fusion Developer Hub deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# Show usage
usage() {
    cat << EOF
Usage: $0 -n NAMESPACE -r RELEASE_NAME [OPTIONS]

Verify Fusion Developer Hub deployment status and health.

REQUIRED OPTIONS:
    -n, --namespace NAME        Namespace where the deployment exists
    -r, --release NAME          Helm release name to verify

OPTIONAL FLAGS:
    -t, --timeout SECONDS       Timeout for checks in seconds (default: 600)
    -h, --help                  Show this help message

EXAMPLES:
    # Verify deployment in fusion-dev-hub namespace
    $0 -n fusion-dev-hub -r fusion-hub

    # Verify with custom timeout
    $0 -n fusion-dev-hub -r fusion-hub -t 300

EOF
    exit 0
}

# Initialize variables
NAMESPACE=""
RELEASE_NAME=""
TIMEOUT="600"

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
        -t|--timeout)
            TIMEOUT="$2"
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

# Start verification
print_header "Fusion Developer Hub Deployment Verification"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo "Timeout: ${TIMEOUT}s"
echo ""

# 1. Check Prerequisites
print_header "1. Checking Prerequisites"

check_command "oc" || exit 1
check_command "helm" || exit 1
check_command "kubectl" || exit 1

# Check cluster connection
if oc whoami &> /dev/null; then
    CURRENT_USER=$(oc whoami)
    print_success "Connected to cluster as: $CURRENT_USER"
else
    print_error "Not connected to OpenShift cluster"
    exit 1
fi

# Check cluster version
OCP_VERSION=$(oc version -o json 2>/dev/null | grep -o '"openshiftVersion":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
if [[ "$OCP_VERSION" != "unknown" ]]; then
    print_success "OpenShift version: $OCP_VERSION"
else
    print_warning "Could not determine OpenShift version"
fi

# 2. Check Helm Release
print_header "2. Checking Helm Release"

if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    RELEASE_STATUS=$(helm list -n "$NAMESPACE" | grep "$RELEASE_NAME" | awk '{print $8}')
    if [[ "$RELEASE_STATUS" == "deployed" ]]; then
        print_success "Helm release '$RELEASE_NAME' is deployed"
    else
        print_error "Helm release '$RELEASE_NAME' status: $RELEASE_STATUS"
    fi
else
    print_error "Helm release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

# Get chart version
CHART_VERSION=$(helm list -n "$NAMESPACE" | grep "$RELEASE_NAME" | awk '{print $9}')
print_info "Chart version: $CHART_VERSION"

# 3. Check Operators
print_header "3. Checking Operators"

# Check RHDH Operator
if oc get csv -n rhdh-operator 2>/dev/null | grep -q "rhdh-operator"; then
    RHDH_PHASE=$(oc get csv -n rhdh-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$RHDH_PHASE" == "Succeeded" ]]; then
        print_success "RHDH Operator is ready (Phase: $RHDH_PHASE)"
    else
        print_error "RHDH Operator phase: $RHDH_PHASE"
    fi
else
    print_error "RHDH Operator not found"
fi

# Check PostgreSQL Operator
if oc get csv -n postgres-operator 2>/dev/null | grep -q "postgresql"; then
    PG_PHASE=$(oc get csv -n postgres-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$PG_PHASE" == "Succeeded" ]]; then
        print_success "PostgreSQL Operator is ready (Phase: $PG_PHASE)"
    else
        print_error "PostgreSQL Operator phase: $PG_PHASE"
    fi
else
    print_error "PostgreSQL Operator not found"
fi

# 4. Check Namespace
print_header "4. Checking Namespace"

if oc get namespace "$NAMESPACE" &> /dev/null; then
    print_success "Namespace '$NAMESPACE' exists"
    
    # Check namespace labels
    LABELS=$(oc get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels}' 2>/dev/null)
    if [[ -n "$LABELS" ]]; then
        print_info "Namespace labels: $LABELS"
    fi
else
    print_error "Namespace '$NAMESPACE' not found"
    exit 1
fi

# 5. Check PostgreSQL Cluster
print_header "5. Checking PostgreSQL Cluster"

if oc get postgrescluster -n "$NAMESPACE" &> /dev/null; then
    PG_CLUSTERS=$(oc get postgrescluster -n "$NAMESPACE" -o name)
    if [[ -n "$PG_CLUSTERS" ]]; then
        for cluster in $PG_CLUSTERS; do
            CLUSTER_NAME=$(echo "$cluster" | cut -d'/' -f2)
            print_success "PostgreSQL cluster found: $CLUSTER_NAME"
            
            # Check cluster status
            PG_STATUS=$(oc get postgrescluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="ProxyAvailable")].status}' 2>/dev/null || echo "Unknown")
            if [[ "$PG_STATUS" == "True" ]]; then
                print_success "PostgreSQL cluster is available"
            else
                print_warning "PostgreSQL cluster status: $PG_STATUS"
            fi
            
            # Check instances
            INSTANCES=$(oc get pods -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster="$CLUSTER_NAME",postgres-operator.crunchydata.com/role=master --no-headers 2>/dev/null | wc -l)
            print_info "PostgreSQL instances: $INSTANCES"
        done
    else
        print_error "No PostgreSQL clusters found"
    fi
else
    print_error "PostgresCluster CRD not found or no clusters in namespace"
fi

# Check PostgreSQL pods
PG_PODS=$(oc get pods -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster --no-headers 2>/dev/null | wc -l)
if [[ $PG_PODS -gt 0 ]]; then
    print_success "PostgreSQL pods running: $PG_PODS"
    
    # Check pod status
    NOT_RUNNING=$(oc get pods -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster --no-headers 2>/dev/null | grep -v "Running" | wc -l)
    if [[ $NOT_RUNNING -gt 0 ]]; then
        print_warning "$NOT_RUNNING PostgreSQL pod(s) not in Running state"
    fi
else
    print_error "No PostgreSQL pods found"
fi

# 6. Check Backstage Instance
print_header "6. Checking Backstage Instance"

if oc get backstage -n "$NAMESPACE" &> /dev/null; then
    BACKSTAGE_INSTANCES=$(oc get backstage -n "$NAMESPACE" -o name)
    if [[ -n "$BACKSTAGE_INSTANCES" ]]; then
        for instance in $BACKSTAGE_INSTANCES; do
            INSTANCE_NAME=$(echo "$instance" | cut -d'/' -f2)
            print_success "Backstage instance found: $INSTANCE_NAME"
            
            # Check instance conditions
            DEPLOYED=$(oc get backstage "$INSTANCE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Deployed")].status}' 2>/dev/null || echo "Unknown")
            if [[ "$DEPLOYED" == "True" ]]; then
                print_success "Backstage instance is deployed"
            else
                print_warning "Backstage deployment status: $DEPLOYED"
            fi
        done
    else
        print_error "No Backstage instances found"
    fi
else
    print_error "Backstage CRD not found or no instances in namespace"
fi

# Check Backstage pods
BACKSTAGE_PODS=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=backstage --no-headers 2>/dev/null | wc -l)
if [[ $BACKSTAGE_PODS -gt 0 ]]; then
    print_success "Backstage pods running: $BACKSTAGE_PODS"
    
    # Check pod status
    RUNNING_PODS=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=backstage --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [[ $RUNNING_PODS -eq $BACKSTAGE_PODS ]]; then
        print_success "All Backstage pods are Running"
    else
        print_warning "Only $RUNNING_PODS/$BACKSTAGE_PODS Backstage pods are Running"
    fi
    
    # Check pod readiness
    READY_PODS=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=backstage --no-headers 2>/dev/null | awk '{if ($2 ~ /^[0-9]+\/[0-9]+$/) {split($2, a, "/"); if (a[1] == a[2]) print $1}}' | wc -l)
    if [[ $READY_PODS -eq $BACKSTAGE_PODS ]]; then
        print_success "All Backstage pods are Ready"
    else
        print_warning "Only $READY_PODS/$BACKSTAGE_PODS Backstage pods are Ready"
    fi
else
    print_error "No Backstage pods found"
fi

# 7. Check Services
print_header "7. Checking Services"

# Check Backstage service
if oc get service -n "$NAMESPACE" -l app.kubernetes.io/name=backstage &> /dev/null; then
    BACKSTAGE_SVC=$(oc get service -n "$NAMESPACE" -l app.kubernetes.io/name=backstage -o name | head -1)
    if [[ -n "$BACKSTAGE_SVC" ]]; then
        print_success "Backstage service found"
        
        # Get service details
        SVC_TYPE=$(oc get "$BACKSTAGE_SVC" -n "$NAMESPACE" -o jsonpath='{.spec.type}')
        SVC_PORT=$(oc get "$BACKSTAGE_SVC" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
        print_info "Service type: $SVC_TYPE, Port: $SVC_PORT"
    fi
else
    print_error "Backstage service not found"
fi

# Check PostgreSQL service
if oc get service -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster &> /dev/null; then
    PG_SVC=$(oc get service -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster -o name | head -1)
    if [[ -n "$PG_SVC" ]]; then
        print_success "PostgreSQL service found"
    fi
else
    print_warning "PostgreSQL service not found"
fi

# 8. Check Routes
print_header "8. Checking Routes"

if oc get route -n "$NAMESPACE" &> /dev/null; then
    ROUTES=$(oc get route -n "$NAMESPACE" -o name)
    if [[ -n "$ROUTES" ]]; then
        for route in $ROUTES; do
            ROUTE_NAME=$(echo "$route" | cut -d'/' -f2)
            ROUTE_HOST=$(oc get route "$ROUTE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}')
            ROUTE_TLS=$(oc get route "$ROUTE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.tls.termination}')
            
            print_success "Route found: $ROUTE_NAME"
            print_info "  URL: https://$ROUTE_HOST"
            print_info "  TLS: $ROUTE_TLS"
        done
    else
        print_warning "No routes found"
    fi
else
    print_warning "No routes found in namespace"
fi

# 9. Check ConfigMaps
print_header "9. Checking ConfigMaps"

APP_CONFIG=$(oc get configmap -n "$NAMESPACE" -l app.kubernetes.io/name=backstage -o name 2>/dev/null | head -1)
if [[ -n "$APP_CONFIG" ]]; then
    print_success "Backstage app-config ConfigMap found"
    
    # Check for homepage configuration
    if oc get "$APP_CONFIG" -n "$NAMESPACE" -o yaml 2>/dev/null | grep -q "homepage:"; then
        print_success "Homepage configuration present"
    else
        print_info "Homepage configuration not found (using default)"
    fi
else
    print_warning "Backstage app-config ConfigMap not found"
fi

# 10. Check Secrets
print_header "10. Checking Secrets"

# Check PostgreSQL secrets
PG_SECRETS=$(oc get secret -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster --no-headers 2>/dev/null | wc -l)
if [[ $PG_SECRETS -gt 0 ]]; then
    print_success "PostgreSQL secrets found: $PG_SECRETS"
else
    print_warning "No PostgreSQL secrets found"
fi

# Check Backstage secrets
BACKSTAGE_SECRETS=$(oc get secret -n "$NAMESPACE" -l app.kubernetes.io/name=backstage --no-headers 2>/dev/null | wc -l)
if [[ $BACKSTAGE_SECRETS -gt 0 ]]; then
    print_success "Backstage secrets found: $BACKSTAGE_SECRETS"
else
    print_info "No Backstage secrets found (may be using default configuration)"
fi

# 11. Check Resource Usage
print_header "11. Checking Resource Usage"

# Check if metrics are available
if oc top pods -n "$NAMESPACE" &> /dev/null; then
    print_success "Metrics available"
    
    # Get top resource consumers
    print_info "Top CPU consumers:"
    oc top pods -n "$NAMESPACE" --sort-by=cpu 2>/dev/null | head -5 | while read -r line; do
        echo "    $line"
    done
    
    print_info "Top Memory consumers:"
    oc top pods -n "$NAMESPACE" --sort-by=memory 2>/dev/null | head -5 | while read -r line; do
        echo "    $line"
    done
else
    print_warning "Metrics not available (metrics-server may not be installed)"
fi

# 12. Check Events
print_header "12. Checking Recent Events"

RECENT_EVENTS=$(oc get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -10)
if [[ -n "$RECENT_EVENTS" ]]; then
    # Check for errors or warnings
    ERROR_COUNT=$(echo "$RECENT_EVENTS" | grep -i "error\|failed\|warning" | wc -l)
    if [[ $ERROR_COUNT -gt 0 ]]; then
        print_warning "Found $ERROR_COUNT error/warning events in last 10 events"
        print_info "Recent events with issues:"
        echo "$RECENT_EVENTS" | grep -i "error\|failed\|warning" | while read -r line; do
            echo "    $line"
        done
    else
        print_success "No error/warning events in recent history"
    fi
else
    print_info "No recent events found"
fi

# 13. Test Connectivity
print_header "13. Testing Connectivity"

# Get route URL
ROUTE_URL=$(oc get route -n "$NAMESPACE" -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
if [[ -n "$ROUTE_URL" ]]; then
    print_info "Testing connectivity to: https://$ROUTE_URL"
    
    # Test HTTP connectivity
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://$ROUTE_URL" --max-time 10 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "302" ]]; then
        print_success "HTTP connectivity successful (HTTP $HTTP_CODE)"
    elif [[ "$HTTP_CODE" == "000" ]]; then
        print_error "Could not connect to route (timeout or connection refused)"
    else
        print_warning "HTTP response code: $HTTP_CODE"
    fi
else
    print_warning "No route found to test connectivity"
fi

# 14. Database Connectivity Test
print_header "14. Testing Database Connectivity"

# Find a Backstage pod to test from
BACKSTAGE_POD=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=backstage --no-headers 2>/dev/null | grep "Running" | head -1 | awk '{print $1}')
if [[ -n "$BACKSTAGE_POD" ]]; then
    print_info "Testing from pod: $BACKSTAGE_POD"
    
    # Get PostgreSQL service name
    PG_SERVICE=$(oc get service -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster,postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$PG_SERVICE" ]]; then
        # Test TCP connectivity to PostgreSQL
        if oc exec -n "$NAMESPACE" "$BACKSTAGE_POD" -- timeout 5 bash -c "cat < /dev/null > /dev/tcp/$PG_SERVICE/5432" 2>/dev/null; then
            print_success "Database TCP connectivity successful"
        else
            print_error "Cannot connect to database on port 5432"
        fi
    else
        print_warning "PostgreSQL service not found for connectivity test"
    fi
else
    print_warning "No running Backstage pod found for database connectivity test"
fi

# 15. Summary
print_header "Verification Summary"

TOTAL=$((PASSED + FAILED + WARNINGS))
echo -e "Total checks: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if [[ $FAILED -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ All checks passed! Deployment is healthy.${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ Deployment is functional but has $WARNINGS warning(s).${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ Deployment has $FAILED critical issue(s).${NC}"
    echo -e "${YELLOW}Please review the errors above and check the troubleshooting guide.${NC}"
    exit 1
fi

# Made with Bob
