#!/bin/bash
# cleanup-runtime.sh - Clean up MaaS Runtime Platform and Helm Releases
# Usage: ./cleanup-runtime.sh [--all]
#
# Arguments:
#   --all   Also delete namespaces, CRDs, and Operator Subscriptions (Full Wipe)
#   (default): Uninstalls MaaS Helm releases, gateways, and custom resources for clean rerun.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FULL_WIPE=false
if [[ "${1:-}" == "--all" ]]; then
    FULL_WIPE=true
fi

echo -e "${GREEN}=== MaaS Runtime Cleanup ===${NC}"
echo "Full wipe mode: $FULL_WIPE"
echo ""

# 1. Uninstall Helm releases
echo -e "${BLUE}Step 1: Uninstalling MaaS Helm releases...${NC}"
for release in maas-model-service maas-runtime maas-platform maas-operators; do
    for ns in default maas-models redhat-ods-applications openshift-ingress; do
        if helm list -n "$ns" 2>/dev/null | grep -q "^$release"; then
            echo "  Uninstalling Helm release: $release from namespace: $ns"
            helm uninstall "$release" -n "$ns" --timeout 2m 2>/dev/null || true
        fi
    done
done

# Also check any model release in maas-models or deploy-models-rhoai
for ns in maas-models deploy-models-rhoai; do
    if oc get ns "$ns" &>/dev/null; then
        for rel in $(helm list -n "$ns" -q 2>/dev/null || true); do
            echo "  Uninstalling model release: $rel from namespace: $ns"
            helm uninstall "$rel" -n "$ns" 2>/dev/null || true
        done
    fi
done

# 2. Delete MaaS Custom Resources and Gateways
echo -e "${BLUE}Step 2: Cleaning up MaaS Custom Resources & Gateways...${NC}"

# Delete LLMInferenceServices
if oc get crd llminferenceservices.serving.kserve.io &>/dev/null; then
    echo "  Deleting LLMInferenceServices..."
    oc delete llminferenceservice --all -A --timeout=30s 2>/dev/null || true
fi

# Delete Kuadrant instance
if oc get crd kuadrants.kuadrant.io &>/dev/null; then
    echo "  Deleting Kuadrant CR instances..."
    oc delete kuadrant --all -A --timeout=30s 2>/dev/null || true
fi

# Delete DataScienceCluster
if oc get crd datascienceclusters.datasciencecluster.opendatahub.io &>/dev/null; then
    echo "  Deleting DataScienceCluster..."
    oc delete datasciencecluster default-dsc --timeout=60s 2>/dev/null || true
    # Remove finalizers if stuck
    if oc get datasciencecluster default-dsc &>/dev/null; then
        oc patch datasciencecluster default-dsc --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    fi
fi

# Delete Gateway & EnvoyFilter in openshift-ingress
echo "  Cleaning up gateways and routes in openshift-ingress..."
oc delete gateway maas-default-gateway openshift-ai-inference -n openshift-ingress --ignore-not-found=true 2>/dev/null || true
oc delete envoyfilter --all -n openshift-ingress 2>/dev/null || true
oc delete configmap gw-options -n openshift-ingress --ignore-not-found=true 2>/dev/null || true
oc delete route maas maas-default-gateway-route openshift-ai-inference -n openshift-ingress --ignore-not-found=true 2>/dev/null || true
oc delete service kuadrant-auth-service -n openshift-ingress --ignore-not-found=true 2>/dev/null || true
oc delete destinationrule authorino-plaintext -n openshift-ingress --ignore-not-found=true 2>/dev/null || true
oc delete serviceentry kuadrant-authorino -n openshift-ingress --ignore-not-found=true 2>/dev/null || true

# 3. Clean up Secrets and ConfigMaps created for MaaS
echo -e "${BLUE}Step 3: Cleaning up MaaS secrets and config...${NC}"
oc delete secret maas-db-config -n redhat-ai-gateway-infra --ignore-not-found=true 2>/dev/null || true
oc delete secret maas-gw-service-tls -n openshift-ingress --ignore-not-found=true 2>/dev/null || true

# 4. Optional Full Wipe: Delete Subscriptions, Namespaces, CRDs
if [ "$FULL_WIPE" = "true" ]; then
    echo -e "${YELLOW}Step 4: Full wipe - deleting subscriptions and namespaces...${NC}"
    
    # Subscriptions
    oc delete subscription.operators.coreos.com rhods-operator -n redhat-ods-operator --ignore-not-found=true 2>/dev/null || true
    oc delete subscription.operators.coreos.com rhcl-operator -n openshift-operators --ignore-not-found=true 2>/dev/null || true
    oc delete subscription.operators.coreos.com openshift-cert-manager-operator -n cert-manager-operator --ignore-not-found=true 2>/dev/null || true
    oc delete subscription.operators.coreos.com leader-worker-set -n openshift-lws-operator --ignore-not-found=true 2>/dev/null || true

    # Namespaces
    for ns in redhat-ods-applications redhat-ods-operator redhat-ai-gateway-infra rhoai-model-registries maas-models deploy-models-rhoai; do
        if oc get ns "$ns" &>/dev/null; then
            echo "  Deleting namespace: $ns"
            oc delete ns "$ns" --ignore-not-found=true --timeout=30s 2>/dev/null || true
        fi
    done
fi

echo ""
echo -e "${GREEN}✓ Cleanup completed successfully!${NC}"
echo "You can now run: ./runtime/scripts/install-runtime.sh -e prod"
