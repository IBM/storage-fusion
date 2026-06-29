#!/bin/bash

# PostgreSQL Connection Validation Script
# This script validates the Backstage to PostgreSQL connection configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="${NAMESPACE:-fusion-developer-hub}"
RELEASE="${RELEASE:-fusion-dev-hub}"

echo "=========================================="
echo "PostgreSQL Connection Validation"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE"
echo ""

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# 1. Check if namespace exists
echo "1. Checking namespace..."
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    print_status 0 "Namespace '$NAMESPACE' exists"
else
    print_status 1 "Namespace '$NAMESPACE' does not exist"
    echo "Please set the correct namespace: export NAMESPACE=your-namespace"
    exit 1
fi

# 2. Check PostgreSQL pod
echo ""
echo "2. Checking PostgreSQL pod..."
PG_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PG_POD" ]; then
    print_status 0 "PostgreSQL pod found: $PG_POD"
    
    # Check pod status
    PG_STATUS=$(kubectl get pod "$PG_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$PG_STATUS" = "Running" ]; then
        print_status 0 "PostgreSQL pod is Running"
    else
        print_status 1 "PostgreSQL pod status: $PG_STATUS"
    fi
    
    # Check readiness
    PG_READY=$(kubectl get pod "$PG_POD" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}')
    if [ "$PG_READY" = "true" ]; then
        print_status 0 "PostgreSQL pod is Ready"
    else
        print_status 1 "PostgreSQL pod is not Ready"
    fi
else
    print_status 1 "PostgreSQL pod not found"
    echo "Checking if PostgreSQL is enabled in values..."
fi

# 3. Check PostgreSQL service
echo ""
echo "3. Checking PostgreSQL service..."
PG_SVC=$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/component=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PG_SVC" ]; then
    print_status 0 "PostgreSQL service found: $PG_SVC"
    PG_SVC_IP=$(kubectl get svc "$PG_SVC" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
    echo "   Service IP: $PG_SVC_IP"
    echo "   Service Port: 5432"
else
    print_status 1 "PostgreSQL service not found"
fi

# 4. Check PostgreSQL secret
echo ""
echo "4. Checking PostgreSQL secret..."
PG_SECRET=$(kubectl get secret -n "$NAMESPACE" -l app.kubernetes.io/component=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PG_SECRET" ]; then
    print_status 0 "PostgreSQL secret found: $PG_SECRET"
    
    # Check required keys
    REQUIRED_KEYS=("POSTGRESQL_USER" "POSTGRESQL_PASSWORD" "POSTGRESQL_DATABASE")
    for key in "${REQUIRED_KEYS[@]}"; do
        if kubectl get secret "$PG_SECRET" -n "$NAMESPACE" -o jsonpath="{.data.$key}" &>/dev/null; then
            print_status 0 "Secret contains key: $key"
        else
            print_status 1 "Secret missing key: $key"
        fi
    done
else
    print_status 1 "PostgreSQL secret not found"
fi

# 5. Check Backstage pod
echo ""
echo "5. Checking Backstage pod..."
BACKSTAGE_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=rhdh-fusion -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$BACKSTAGE_POD" ]; then
    print_status 0 "Backstage pod found: $BACKSTAGE_POD"
    
    # Check pod status
    BS_STATUS=$(kubectl get pod "$BACKSTAGE_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$BS_STATUS" = "Running" ]; then
        print_status 0 "Backstage pod is Running"
    else
        print_status 1 "Backstage pod status: $BS_STATUS"
    fi
else
    print_status 1 "Backstage pod not found"
    exit 1
fi

# 6. Check Backstage environment variables
echo ""
echo "6. Checking Backstage environment variables..."
ENV_VARS=("POSTGRES_HOST" "POSTGRES_PORT" "POSTGRES_USER" "POSTGRES_PASSWORD" "SESSION_SECRET")
for var in "${ENV_VARS[@]}"; do
    if kubectl exec "$BACKSTAGE_POD" -n "$NAMESPACE" -- env 2>/dev/null | grep -q "^$var="; then
        print_status 0 "Environment variable set: $var"
        if [ "$var" = "POSTGRES_HOST" ]; then
            HOST_VALUE=$(kubectl exec "$BACKSTAGE_POD" -n "$NAMESPACE" -- env 2>/dev/null | grep "^POSTGRES_HOST=" | cut -d'=' -f2)
            echo "   Value: $HOST_VALUE"
        fi
    else
        print_status 1 "Environment variable missing: $var"
    fi
done

# 7. Check auth secret for SESSION_SECRET
echo ""
echo "7. Checking auth secret..."
AUTH_SECRET=$(kubectl get secret -n "$NAMESPACE" -o name 2>/dev/null | grep "auth" | head -1 | cut -d'/' -f2)
if [ -n "$AUTH_SECRET" ]; then
    print_status 0 "Auth secret found: $AUTH_SECRET"
    if kubectl get secret "$AUTH_SECRET" -n "$NAMESPACE" -o jsonpath="{.data.session-secret}" &>/dev/null; then
        print_status 0 "Auth secret contains session-secret key"
    else
        print_status 1 "Auth secret missing session-secret key"
    fi
else
    print_status 1 "Auth secret not found"
fi

# 8. Test database connection from Backstage pod
echo ""
echo "8. Testing database connection from Backstage pod..."
if [ -n "$BACKSTAGE_POD" ] && [ -n "$PG_POD" ]; then
    echo "   Attempting to resolve PostgreSQL service..."
    if kubectl exec "$BACKSTAGE_POD" -n "$NAMESPACE" -- sh -c "getent hosts \$POSTGRES_HOST" &>/dev/null; then
        print_status 0 "DNS resolution successful"
    else
        print_status 1 "DNS resolution failed"
    fi
fi

# 9. Check Backstage logs for database errors
echo ""
echo "9. Checking Backstage logs for database errors..."
if [ -n "$BACKSTAGE_POD" ]; then
    LOGS=$(kubectl logs "$BACKSTAGE_POD" -n "$NAMESPACE" --tail=50 2>/dev/null)
    
    if echo "$LOGS" | grep -qi "error.*database\|error.*postgres\|connection.*refused\|authentication.*failed"; then
        print_status 1 "Database errors found in logs"
        echo ""
        echo "Recent error logs:"
        echo "$LOGS" | grep -i "error.*database\|error.*postgres\|connection.*refused\|authentication.*failed" | tail -5
    else
        print_status 0 "No obvious database errors in recent logs"
    fi
    
    if echo "$LOGS" | grep -qi "backend.*started\|listening.*on"; then
        print_status 0 "Backstage backend appears to be running"
    else
        print_warning "Cannot confirm Backstage backend is fully started"
    fi
fi

# 10. Check ConfigMap for database configuration
echo ""
echo "10. Checking ConfigMap for database configuration..."
CONFIG_MAP=$(kubectl get configmap -n "$NAMESPACE" -o name 2>/dev/null | grep "config" | head -1 | cut -d'/' -f2)
if [ -n "$CONFIG_MAP" ]; then
    print_status 0 "ConfigMap found: $CONFIG_MAP"
    
    # Check for SSL configuration
    if kubectl get configmap "$CONFIG_MAP" -n "$NAMESPACE" -o yaml 2>/dev/null | grep -q "ssl:"; then
        print_status 0 "SSL configuration present in ConfigMap"
    else
        print_warning "SSL configuration not found in ConfigMap (may need to be added)"
    fi
    
    # Check for database connection config
    if kubectl get configmap "$CONFIG_MAP" -n "$NAMESPACE" -o yaml 2>/dev/null | grep -q "database:"; then
        print_status 0 "Database configuration present in ConfigMap"
    else
        print_status 1 "Database configuration not found in ConfigMap"
    fi
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo ""
echo "To view detailed logs:"
echo "  kubectl logs $BACKSTAGE_POD -n $NAMESPACE --tail=100"
echo ""
echo "To test PostgreSQL connection directly:"
echo "  kubectl exec -it $PG_POD -n $NAMESPACE -- psql -U \$POSTGRESQL_USER -d \$POSTGRESQL_DATABASE -c '\\l'"
echo ""
echo "To check Backstage environment:"
echo "  kubectl exec $BACKSTAGE_POD -n $NAMESPACE -- env | grep -E '(POSTGRES|SESSION)'"
echo ""

# Made with Bob
