#!/bin/bash
# Script to expose InferenceService(s) externally via OpenShift Route
# Usage: 
#   ./expose-model.sh <namespace>                    # Expose all models in namespace
#   ./expose-model.sh <inferenceservice> <namespace> # Expose specific model

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Expose Models - External Access                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Parse arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Missing arguments${NC}"
    echo "Usage:"
    echo "  $0 <namespace>                    # Expose all models in namespace"
    echo "  $0 <inferenceservice> <namespace> # Expose specific model"
    echo ""
    echo "Examples:"
    echo "  $0 krishi-rakshak-ds"
    echo "  $0 granite-llm krishi-rakshak-ds"
    exit 1
elif [ $# -eq 1 ]; then
    # Single argument: namespace - expose all models
    NAMESPACE="$1"
    EXPOSE_ALL=true
else
    # Two arguments: specific model
    ISVC_NAME="$1"
    NAMESPACE="$2"
    EXPOSE_ALL=false
fi

echo -e "${GREEN}Configuration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Namespace: ${YELLOW}$NAMESPACE${NC}"
if [ "$EXPOSE_ALL" = true ]; then
    echo -e "  Mode:      ${YELLOW}Expose ALL InferenceServices${NC}"
else
    echo -e "  Mode:      ${YELLOW}Expose specific InferenceService${NC}"
    echo -e "  Model:     ${YELLOW}$ISVC_NAME${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Function to expose a single InferenceService
expose_inferenceservice() {
    local isvc="$1"
    local namespace="$2"
    local service_name="${isvc}-predictor"
    local route_name="${isvc}-external"
    
    echo -e "${BLUE}Processing: $isvc${NC}"
    
    # Check if InferenceService exists
    if ! oc get inferenceservice "$isvc" -n "$namespace" &>/dev/null; then
        echo -e "  ${RED}✗${NC} InferenceService '$isvc' not found"
        return 1
    fi
    
    # Check if service exists
    if ! oc get service "$service_name" -n "$namespace" &>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC}  Service '$service_name' not found (InferenceService may not be ready)"
        return 1
    fi
    
    # Check if route already exists
    if oc get route "$route_name" -n "$namespace" &>/dev/null 2>&1; then
        echo -e "  ${YELLOW}ℹ${NC}  Route already exists, recreating..."
        oc delete route "$route_name" -n "$namespace" 2>/dev/null || true
    fi
    
    # Create the route
    if oc create route edge "$route_name" \
        --service="$service_name" \
        --port=8080 \
        --insecure-policy=Redirect \
        -n "$namespace" 2>/dev/null; then
        
        # Get the route URL
        ROUTE_URL=$(oc get route "$route_name" -n "$namespace" -o jsonpath='{.spec.host}')
        echo -e "  ${GREEN}✓${NC} Exposed at: https://$ROUTE_URL"
        return 0
    else
        echo -e "  ${RED}✗${NC} Failed to create route"
        return 1
    fi
}

if [ "$EXPOSE_ALL" = true ]; then
    # Expose all InferenceServices in namespace
    ISVCS=$(oc get inferenceservice -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$ISVCS" ]; then
        echo -e "${YELLOW}No InferenceServices found in namespace '$NAMESPACE'${NC}"
        echo ""
        echo "Make sure:"
        echo "  1. The namespace exists"
        echo "  2. InferenceServices are deployed"
        echo "  3. You have access to the namespace"
        exit 1
    fi
    
    echo "Found InferenceServices:"
    for isvc in $ISVCS; do
        echo "  - $isvc"
    done
    echo ""
    
    # Expose each InferenceService
    EXPOSED_COUNT=0
    FAILED_COUNT=0
    for isvc in $ISVCS; do
        if expose_inferenceservice "$isvc" "$NAMESPACE"; then
            EXPOSED_COUNT=$((EXPOSED_COUNT + 1))
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
        echo ""
    done
    
    # Summary
    echo ""
    if [ $EXPOSED_COUNT -gt 0 ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}Successfully exposed $EXPOSED_COUNT InferenceService(s)!${NC}"
        if [ $FAILED_COUNT -gt 0 ]; then
            echo -e "${YELLOW}Failed to expose $FAILED_COUNT InferenceService(s)${NC}"
        fi
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "Test your models:"
        for isvc in $ISVCS; do
            ROUTE_NAME="${isvc}-external"
            ROUTE_URL=$(oc get route "$ROUTE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)
            if [ -n "$ROUTE_URL" ]; then
                echo -e "  ${isvc}:"
                echo -e "    ${YELLOW}curl -k https://$ROUTE_URL/v1/models -H 'Authorization: Bearer EMPTY'${NC}"
            fi
        done
        echo ""
    else
        echo -e "${YELLOW}No InferenceServices were exposed. Check that services are ready.${NC}"
    fi
else
    # Expose specific InferenceService
    if expose_inferenceservice "$ISVC_NAME" "$NAMESPACE"; then
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}Successfully exposed InferenceService!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        ROUTE_URL=$(oc get route "${ISVC_NAME}-external" -n "$NAMESPACE" -o jsonpath='{.spec.host}')
        echo "Test your model:"
        echo -e "  ${YELLOW}curl -k https://$ROUTE_URL/v1/models -H 'Authorization: Bearer EMPTY'${NC}"
        echo ""
    else
        echo ""
        echo -e "${RED}Failed to expose InferenceService${NC}"
        exit 1
    fi
fi

