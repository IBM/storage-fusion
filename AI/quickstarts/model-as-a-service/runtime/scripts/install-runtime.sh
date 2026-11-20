#!/bin/bash
# install-runtime.sh - Deploy MaaS Runtime Platform
# Usage: ./install-runtime.sh <values-file> [cluster-override-file]
#
# Arguments:
#   values-file           Base values file (required)
#   cluster-override-file Optional second values file — merged on top of base.
#                         Use this for cluster-specific overrides such as
#                         disabling cert-manager/Keycloak that are pre-installed.
# Example:
#   ./install-runtime.sh \
#     examples/Fusion-Agentic-Assistance-Platform/values.yaml \
#     examples/my-cluster-values.yaml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHARTS_DIR="$PROJECT_ROOT/charts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments (supports positional values file, -e/--env flag, and optional override)
ENV_NAME=""
VALUES_FILE=""
OVERRIDE_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--env|--environment)
            ENV_NAME="$2"
            shift 2
            ;;
        -f|--values)
            VALUES_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [values-file] [override-file] or $0 -e [dev|staging|prod]"
            exit 0
            ;;
        *)
            if [ -z "${POSITIONAL_ARG1:-}" ]; then
                POSITIONAL_ARG1="$1"
                VALUES_FILE="$1"
            elif [ -z "${OVERRIDE_FILE:-}" ]; then
                OVERRIDE_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Resolve per-environment or unified values files
if [ -n "$ENV_NAME" ]; then
    echo -e "${BLUE}Configured for environment: $ENV_NAME${NC}"
    OPERATORS_VALUES_FILE="$PROJECT_ROOT/config/helm/$ENV_NAME/operators-values.yaml"
    PLATFORM_VALUES_FILE="$PROJECT_ROOT/config/helm/$ENV_NAME/platform-values.yaml"
    RUNTIME_VALUES_FILE="$PROJECT_ROOT/config/helm/$ENV_NAME/runtime-values.yaml"
    VALUES_FILE="$PLATFORM_VALUES_FILE"
else
    VALUES_FILE="${VALUES_FILE:-$PROJECT_ROOT/config/helm/prod/platform-values.yaml}"
    OPERATORS_VALUES_FILE="${OPERATORS_VALUES_FILE:-$PROJECT_ROOT/config/helm/prod/operators-values.yaml}"
    PLATFORM_VALUES_FILE="${PLATFORM_VALUES_FILE:-$PROJECT_ROOT/config/helm/prod/platform-values.yaml}"
    RUNTIME_VALUES_FILE="${RUNTIME_VALUES_FILE:-$PROJECT_ROOT/config/helm/prod/runtime-values.yaml}"
fi

# Build per-phase Helm value arguments
OPERATORS_HELM_ARGS="-f $OPERATORS_VALUES_FILE"
PLATFORM_HELM_ARGS="-f $PLATFORM_VALUES_FILE"
RUNTIME_HELM_ARGS="-f $RUNTIME_VALUES_FILE"

if [ -n "$OVERRIDE_FILE" ]; then
    OPERATORS_HELM_ARGS="$OPERATORS_HELM_ARGS -f $OVERRIDE_FILE"
    PLATFORM_HELM_ARGS="$PLATFORM_HELM_ARGS -f $OVERRIDE_FILE"
    RUNTIME_HELM_ARGS="$RUNTIME_HELM_ARGS -f $OVERRIDE_FILE"
fi

echo -e "${GREEN}=== MaaS Runtime Installation ===${NC}"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: OpenShift CLI (oc) is not installed${NC}"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: Helm is not installed${NC}"
    exit 1
fi

# Check if logged into cluster
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift cluster${NC}"
    echo "Please run: oc login <cluster-url>"
    exit 1
fi

# Check if user is cluster admin
if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
    echo -e "${YELLOW}Warning: You may not have cluster-admin privileges${NC}"
    echo "Some operations may fail. Continue? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ── GPU Readiness Check ───────────────────────────────────────────────────────
echo "Checking GPU resources on cluster nodes..."
NVIDIA_GPU_NODES=$(oc get nodes \
    -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' \
    2>/dev/null | grep -v '^$' | grep -v '^0$' | wc -l | tr -d ' ')
AMD_GPU_NODES=$(oc get nodes \
    -o jsonpath='{range .items[*]}{.status.allocatable.amd\.com/gpu}{"\n"}{end}' \
    2>/dev/null | grep -v '^$' | grep -v '^0$' | wc -l | tr -d ' ')

if [[ "$NVIDIA_GPU_NODES" -gt 0 && "$AMD_GPU_NODES" -gt 0 ]]; then
    echo -e "${GREEN}✓ Mixed GPU cluster detected${NC}"
    echo "  NVIDIA: $NVIDIA_GPU_NODES node(s) with nvidia.com/gpu allocatable"
    echo "  AMD:    $AMD_GPU_NODES node(s) with amd.com/gpu allocatable"
    echo "  Use vendor-specific overlays when deploying models (accelerator.vendor: nvidia|amd)"
elif [[ "$NVIDIA_GPU_NODES" -gt 0 ]]; then
    echo -e "${GREEN}✓ NVIDIA GPU cluster: $NVIDIA_GPU_NODES node(s) with nvidia.com/gpu allocatable${NC}"
elif [[ "$AMD_GPU_NODES" -gt 0 ]]; then
    echo -e "${GREEN}✓ AMD GPU cluster: $AMD_GPU_NODES node(s) with amd.com/gpu allocatable${NC}"
else
    echo -e "${YELLOW}⚠ No GPU resources (nvidia.com/gpu or amd.com/gpu) allocatable on any node.${NC}"
    echo "  MaaS operators will install. GPU-backed model serving requires GPU operators from isf-compute-operator."
fi
echo ""

# Check if values files exist
for file in "$VALUES_FILE" "$OPERATORS_VALUES_FILE" "$PLATFORM_VALUES_FILE" "$RUNTIME_VALUES_FILE"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Values file not found: $file${NC}"
        exit 1
    fi
done
if [ -n "$OVERRIDE_FILE" ] && [ ! -f "$OVERRIDE_FILE" ]; then
    echo -e "${RED}Error: Override file not found: $OVERRIDE_FILE${NC}"
    exit 1
fi
if [ -n "$OVERRIDE_FILE" ]; then
    echo "  Override file: $OVERRIDE_FILE"
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Check for default StorageClass
echo "Checking for default StorageClass..."
if ! oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' | grep -q .; then
    echo -e "${RED}Error: No default StorageClass found${NC}"
    echo "Please configure a default StorageClass before proceeding"
    exit 1
fi
echo -e "${GREEN}✓ Default StorageClass found${NC}"
echo ""

# Prompt for passwords if using Keycloak
_keycloak_enabled() {
    local enabled="false"
    for f in "$VALUES_FILE" ${OVERRIDE_FILE:+"$OVERRIDE_FILE"}; do
        if grep -A 3 "keycloak:" "$f" 2>/dev/null | grep -q "enabled: true"; then
            enabled="true"
        elif grep -A 3 "keycloak:" "$f" 2>/dev/null | grep -q "enabled: false"; then
            enabled="false"
        fi
    done
    echo "$enabled"
}

if [ "$(_keycloak_enabled)" = "true" ]; then
    echo "Keycloak is enabled. Please provide passwords:"
    echo ""
    
    if [ -z "$ADMIN_PASSWORD" ]; then
        read -rsp "Enter admin password: " ADMIN_PASSWORD
        echo ""
    fi
    
    if [ -z "$USER_PASSWORD" ]; then
        read -rsp "Enter user password: " USER_PASSWORD
        echo ""
    fi
    
    KEYCLOAK_ARGS="--set authentication.keycloak.realm.admin.password=$ADMIN_PASSWORD --set authentication.keycloak.realm.user.password=$USER_PASSWORD"
else
    KEYCLOAK_ARGS=""
fi

# Self-healing helper for terminating namespaces & stuck finalizers
sanitize_namespaces() {
    local target_namespaces=("$@")
    for ns in "${target_namespaces[@]}"; do
        local phase=$(oc get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$phase" = "Terminating" ]; then
            echo -e "${YELLOW}Namespace $ns is stuck in Terminating status — automatically releasing finalizers...${NC}"
            for csv in $(oc get csv -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
                oc patch csv "$csv" -n "$ns" --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
            done
            oc patch ns "$ns" --type merge -p '{"spec":{"finalizers":[]}}' 2>/dev/null || true
            for i in $(seq 1 15); do
                if ! oc get ns "$ns" &>/dev/null; then
                    echo -e "${GREEN}✓ Terminating namespace $ns cleared${NC}"
                    break
                fi
                sleep 2
            done
        fi
    done
}

echo ""
echo -e "${GREEN}=== Phase 1: Installing Dependency Operator Subscriptions ===${NC}"
echo "Values file: $OPERATORS_VALUES_FILE"
echo "Chart: $CHARTS_DIR/maas-operators"
echo ""

# Ensure all operator namespaces are healthy before running Helm
sanitize_namespaces cert-manager-operator redhat-ods-operator openshift-operators openshift-lws-operator default

helm upgrade --install maas-operators "$CHARTS_DIR/maas-operators" \
    $OPERATORS_HELM_ARGS \
    --timeout 20m \
    --wait

echo ""
echo -e "${GREEN}✓ Dependency operator subscriptions installed${NC}"
echo ""

# Wait for OpenShift AI operator to be ready
echo "Waiting for OpenShift AI operator CSV to succeed..."
RHOAI_READY=false
for i in $(seq 1 60); do
    CSV_STATUS=$(oc get csv -n redhat-ods-operator 2>/dev/null | grep "rhods-operator" | awk '{print $NF}' | head -1)
    if [ "$CSV_STATUS" = "Succeeded" ]; then
        echo -e "${GREEN}✓ OpenShift AI operator CSV Succeeded${NC}"
        RHOAI_READY=true
        break
    fi
    # Automatically approve any manual InstallPlan if created
    PENDING_IP=$(oc get installplan -n redhat-ods-operator -o jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$PENDING_IP" ]; then
        echo "  Approving InstallPlan $PENDING_IP in redhat-ods-operator..."
        oc patch installplan "$PENDING_IP" -n redhat-ods-operator --type merge --patch '{"spec":{"approved":true}}' 2>/dev/null || true
    fi
    echo "  [${i}/60] RHOAI operator status: ${CSV_STATUS:-Installing/Pending} — waiting 10s..."
    sleep 10
done

# Wait for DataScienceCluster CRD to be available
echo "Waiting for DataScienceCluster CRD to be available..."
for i in $(seq 1 60); do
    if oc get crd datascienceclusters.datasciencecluster.opendatahub.io &>/dev/null; then
        echo -e "${GREEN}✓ DataScienceCluster CRD available${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}✗ DataScienceCluster CRD not available after 10 minutes${NC}"
        echo "Checking subscription and installplan status:"
        oc get subscription -n redhat-ods-operator 2>/dev/null || true
        oc get installplan -n redhat-ods-operator 2>/dev/null || true
        oc get csv -n redhat-ods-operator 2>/dev/null || true
        exit 1
    fi
    echo "  [${i}/60] datascienceclusters.datasciencecluster.opendatahub.io CRD not yet — waiting 10s..."
    sleep 10
done

# Helper function to approve pending installplans across operator namespaces
approve_pending_installplans() {
    for ns in openshift-operators redhat-ods-operator cert-manager-operator openshift-lws-operator default; do
        for ip in $(oc get installplan -n "$ns" -o jsonpath='{.items[?(@.spec.approved==false)].metadata.name}' 2>/dev/null); do
            echo "  Auto-approving InstallPlan $ip in namespace $ns..."
            oc patch installplan "$ip" -n "$ns" --type merge --patch '{"spec":{"approved":true}}' 2>/dev/null || true
        done
    done
}

# Wait for Kuadrant CRD
echo "Waiting for Kuadrant CRD (rhcl-operator may still be installing)..."
KUADRANT_FOUND=false
for i in $(seq 1 60); do
    if oc get crd kuadrants.kuadrant.io &>/dev/null; then
        echo -e "${GREEN}✓ Kuadrant CRD available${NC}"
        KUADRANT_FOUND=true
        break
    fi
    approve_pending_installplans
    RHCL_CSV=$(oc get csv -A 2>/dev/null | grep rhcl | awk '{print $1 "/" $2 ":" $NF}' | head -1)
    echo "  [${i}/60] kuadrants.kuadrant.io not yet (rhcl CSV: ${RHCL_CSV:-Pending}) — waiting 10s..."
    sleep 10
done
if [ "$KUADRANT_FOUND" = "false" ]; then
    echo -e "${YELLOW}⚠ Kuadrant CRD not available after 10 minutes — checking operator status:${NC}"
    oc get subscription -A | grep rhcl || true
    oc get csv -A | grep rhcl || true
fi

# Wait for LeaderWorkerSet CRD
echo "Waiting for LeaderWorkerSet CRD (lws-operator may still be installing)..."
LWS_FOUND=false
for i in $(seq 1 36); do
    if oc get crd leaderworkersetoperators.operator.openshift.io &>/dev/null \
       || oc get crd leaderworkersets.leaderworkerset.x-k8s.io &>/dev/null; then
        echo -e "${GREEN}✓ LeaderWorkerSet CRD available${NC}"
        LWS_FOUND=true
        break
    fi
    echo "  [${i}/36] LeaderWorkerSet CRD not yet — waiting 10s..."
    sleep 10
done
if [ "$LWS_FOUND" = "false" ]; then
    echo -e "${YELLOW}⚠ LeaderWorkerSet CRD not available after 6 minutes — continuing without it${NC}"
fi

echo ""
echo -e "${GREEN}=== Phase 2: Creating DataScienceCluster and Operator Instances ===${NC}"
echo "Values file: $PLATFORM_VALUES_FILE"
echo "Chart: $CHARTS_DIR/maas-platform"
echo ""

# Ensure platform namespaces are healthy and ready
sanitize_namespaces redhat-ods-applications redhat-ai-gateway-infra openshift-ingress rhoai-model-registries deploy-models-rhoai

echo "Ensuring platform namespaces exist..."
for ns in redhat-ods-applications redhat-ai-gateway-infra openshift-ingress rhoai-model-registries deploy-models-rhoai; do
    oc create namespace "$ns" 2>/dev/null || true
done

# Ensure pre-existing unmanaged resources in openshift-ingress have Helm ownership annotations
for cm in gw-options; do
    if oc get configmap "$cm" -n openshift-ingress &>/dev/null; then
        oc annotate configmap "$cm" -n openshift-ingress meta.helm.sh/release-name=maas-platform meta.helm.sh/release-namespace=default --overwrite 2>/dev/null || true
        oc label configmap "$cm" -n openshift-ingress app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
    fi
done

helm upgrade --install maas-platform "$CHARTS_DIR/maas-platform" \
    $PLATFORM_HELM_ARGS \
    --timeout 20m \
    --wait

echo ""
# Ensure pre-existing DataScienceCluster has required MaaS components enabled
echo "Ensuring DataScienceCluster components (modelregistry, aigateway) are enabled..."
oc patch datasciencecluster default-dsc --type=merge -p '{
  "spec": {
    "components": {
      "modelregistry": {"managementState": "Managed", "registriesNamespace": "rhoai-model-registries"},
      "aigateway": {"managementState": "Managed", "modelsAsAService": {"managementState": "Managed"}}
    }
  }
}' 2>/dev/null || true

echo "Waiting for ModelRegistry CRD to be available..."
for i in $(seq 1 36); do
    if oc get crd modelregistries.modelregistry.opendatahub.io &>/dev/null; then
        echo -e "${GREEN}✓ ModelRegistry CRD available${NC}"
        break
    fi
    if [ $i -eq 36 ]; then
        echo -e "${RED}✗ ModelRegistry CRD not available after 6 minutes${NC}"
        exit 1
    fi
    echo "  [${i}/36] waiting for ModelRegistry CRD... 10s"
    sleep 10
done

echo ""
echo "Waiting for DataScienceCluster to be ready..."
if oc wait --for=condition=Ready datasciencecluster default-dsc --timeout=15m 2>/dev/null; then
    echo -e "${GREEN}✓ DataScienceCluster ready${NC}"
else
    echo -e "${RED}✗ DataScienceCluster not ready${NC}"
    echo "Please check the DataScienceCluster status and try again"
    exit 1
fi


echo ""
echo -e "${GREEN}=== Phase 3: Installing MaaS Runtime Resources ===${NC}"
echo "Values file: $RUNTIME_VALUES_FILE"
echo "Chart: $CHARTS_DIR/maas-runtime"
echo ""

# Install or upgrade the main runtime resources
echo "Installing MaaS runtime resources (gateway, model registry, workbench storage, etc.)..."
helm upgrade --install maas-runtime "$CHARTS_DIR/maas-runtime" \
    $RUNTIME_HELM_ARGS \
    $KEYCLOAK_ARGS \
    --timeout 10m

echo ""
echo -e "${GREEN}✓ MaaS Runtime resources installation complete${NC}"
echo ""

# Wait for Kuadrant ready in whatever namespace it was deployed
echo "Checking Kuadrant status..."
KUADRANT_NS=$(oc get kuadrant -A -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || echo "")
if [ -n "$KUADRANT_NS" ]; then
    if oc wait --for=condition=Ready kuadrant kuadrant -n "$KUADRANT_NS" --timeout=5m 2>/dev/null; then
        echo -e "${GREEN}✓ Kuadrant ready in namespace: $KUADRANT_NS${NC}"
    else
        echo -e "${YELLOW}⚠ Kuadrant not ready yet in namespace: $KUADRANT_NS${NC}"
    fi
fi

# Wait for Keycloak if enabled
if [ -n "$KEYCLOAK_ARGS" ]; then
    echo "Waiting for Keycloak..."
    if oc wait --for=condition=Ready keycloak keycloak -n keycloak --timeout=10m 2>/dev/null; then
        echo -e "${GREEN}✓ Keycloak ready${NC}"
    else
        echo -e "${YELLOW}⚠ Keycloak not ready yet${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Phase 4: Post-Install Platform Wiring & Security Setup ===${NC}"

# 1. Dynamically detect Authorino namespace
echo "Detecting Authorino namespace..."
AUTHORINO_NAMESPACE=$(oc get pods -A -l app=authorino --no-headers 2>/dev/null | awk '{print $1}' | head -1)
if [ -z "$AUTHORINO_NAMESPACE" ]; then
    if oc get ns openshift-operators &>/dev/null && oc get csv -n openshift-operators 2>/dev/null | grep -q rhcl; then
        AUTHORINO_NAMESPACE="openshift-operators"
    else
        AUTHORINO_NAMESPACE="kuadrant-system"
    fi
fi
echo -e "${GREEN}✓ Authorino namespace: ${AUTHORINO_NAMESPACE}${NC}"

# 2. Configure Authorino TLS (POST_SYNC_MANUAL_STEPS.md Step 2)
if oc get service authorino-authorino-authorization -n "${AUTHORINO_NAMESPACE}" &>/dev/null; then
    echo "Annotating Authorino service for OpenShift service-ca..."
    oc annotate service authorino-authorino-authorization \
        -n "${AUTHORINO_NAMESPACE}" \
        service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
        --overwrite

    echo "Waiting for authorino-server-cert secret to be generated..."
    for i in {1..30}; do
        if oc get secret authorino-server-cert -n "${AUTHORINO_NAMESPACE}" &>/dev/null; then
            echo -e "${GREEN}✓ authorino-server-cert secret created${NC}"
            break
        fi
        sleep 2
    done

    echo "Patching Authorino CR for TLS listener..."
    if oc get authorino authorino -n "${AUTHORINO_NAMESPACE}" &>/dev/null; then
        oc patch authorino authorino -n "${AUTHORINO_NAMESPACE}" --type=merge --patch \
          '{"spec":{"listener":{"tls":{"enabled":true,"certSecretRef":{"name":"authorino-server-cert"}}}}}' || true
    fi

    echo "Configuring service CA bundle env on Authorino deployment..."
    if oc get deployment authorino -n "${AUTHORINO_NAMESPACE}" &>/dev/null; then
        oc -n "${AUTHORINO_NAMESPACE}" set env deployment/authorino \
          SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
          REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt || true
        oc rollout restart deployment/authorino -n "${AUTHORINO_NAMESPACE}" || true
    fi

    # Annotate Gateway
    if oc get gateway maas-default-gateway -n openshift-ingress &>/dev/null; then
        oc annotate gateway maas-default-gateway -n openshift-ingress \
          security.opendatahub.io/authorino-tls-bootstrap="true" --overwrite || true
    fi

    # Restart gateway deployments in openshift-ingress
    if oc get deployment maas-default-gateway-data-science-gateway-class -n openshift-ingress &>/dev/null; then
        oc rollout restart deployment/maas-default-gateway-data-science-gateway-class -n openshift-ingress || true
    fi
fi

# 3. Scale down legacy gateway deployment if present
if oc get deployment maas-default-gateway-openshift-default -n openshift-ingress &>/dev/null; then
    echo "Scaling down unused openshift-default gateway deployment..."
    oc scale deployment/maas-default-gateway-openshift-default -n openshift-ingress --replicas=0 2>/dev/null || true
fi

# 4. Copy maas-db-config Secret to redhat-ai-gateway-infra if present
if oc get secret maas-db-config -n redhat-ods-applications &>/dev/null; then
    if oc get ns redhat-ai-gateway-infra &>/dev/null; then
        echo "Copying maas-db-config secret to redhat-ai-gateway-infra..."
        oc get secret maas-db-config -n redhat-ods-applications -o yaml \
          | sed 's/namespace: redhat-ods-applications/namespace: redhat-ai-gateway-infra/' \
          | oc apply -f - || true
    fi
fi

# 5. Patch KServe inferenceservice-config if needed
if oc get configmap inferenceservice-config -n redhat-ods-applications &>/dev/null; then
    echo "Ensuring inferenceservice-config is unmanaged and configured for Gateway API..."
    oc annotate configmap inferenceservice-config -n redhat-ods-applications opendatahub.io/managed="false" --overwrite || true
fi

# 6. Ensure Private AI Catalog ConfigMap is applied
CATALOG_FILE="$PROJECT_ROOT/../models/catalog/private-model-catalog.yaml"
if [ -f "$CATALOG_FILE" ]; then
    echo "Registering IBM Fusion Private Model Catalog in OpenShift AI..."
    oc create configmap ibm-fusion-model-catalog \
        -n redhat-ods-applications \
        --from-file=model-catalog.yaml="$CATALOG_FILE" \
        --dry-run=client -o yaml | oc apply -f - 2>/dev/null || true
    oc label configmap ibm-fusion-model-catalog -n redhat-ods-applications \
        app.kubernetes.io/part-of=rhods-dashboard \
        app.opendatahub.io/catalog-source="true" \
        opendatahub.io/catalog-source="true" \
        opendatahub.io/dashboard="true" --overwrite 2>/dev/null || true
    echo -e "${GREEN}✓ Private Model Catalog registered in OpenShift AI${NC}"
fi

# 7. Ensure rhods-admins group exists and has admin users
echo "Ensuring rhods-admins group is configured..."
oc adm groups new rhods-admins 2>/dev/null || true
CURRENT_USER=$(oc whoami 2>/dev/null || echo "")
if [ -n "$CURRENT_USER" ]; then
    oc adm groups add-users rhods-admins "$CURRENT_USER" 2>/dev/null || true
fi
oc adm groups add-users rhods-admins "kube:admin" "b64:a3ViZTphZG1pbg" 2>/dev/null || true

echo ""
echo -e "${GREEN}=== Installation Summary ===${NC}"
echo ""
echo "MaaS Runtime platform and security wiring have been deployed!"
echo ""
echo "Next steps:"
echo "1. Create a MaaS API Key:"
echo "   TOKEN=\$(oc whoami -t)"
echo "   KEY=\$(curl -sk -X POST -H \"Authorization: Bearer \${TOKEN}\" -H \"Content-Type: application/json\" -d '{\"name\":\"test-key\"}' \"https://maas.\${WILDCARD_DOMAIN}/maas-api/v1/api-keys\" | python3 -c \"import sys,json; print(json.load(sys.stdin)['key'])\")"
echo "2. Deploy models using: ./deploy-model.sh <model-values-file>"
echo "3. Query model endpoint with: curl -sk -H \"Authorization: Bearer \${KEY}\" \"https://maas.\${WILDCARD_DOMAIN}/deploy-models-rhoai/<model>/v1/models\""
echo ""

# Display useful URLs
echo "Useful URLs:"
CONSOLE_URL=$(oc whoami --show-console 2>/dev/null || echo "N/A")
echo "  OpenShift Console: $CONSOLE_URL"

if [ -n "$KEYCLOAK_ARGS" ]; then
    KEYCLOAK_URL=$(oc get route -n keycloak keycloak -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
    echo "  Keycloak: https://$KEYCLOAK_URL"
fi

GRAFANA_URL=$(oc get route -n grafana grafana-route -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
if [ "$GRAFANA_URL" != "N/A" ]; then
    echo "  Grafana: https://$GRAFANA_URL"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
