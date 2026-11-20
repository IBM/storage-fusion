#!/bin/bash
# deploy-model.sh - Deploy a model to MaaS Platform
# Usage: ./deploy-model.sh [--profile <hardware-profile.yaml>] <model-values-file> [release-name]
#   --profile  hardware profile from profiles/ (node selector, tolerations, NCCL tuning).
#              Passed to Helm before the model file, so the model file wins on conflict.

set -e

PROFILE_FILE=""
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --profile) PROFILE_FILE="${2:?--profile needs a file}"; shift 2 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHARTS_DIR="$PROJECT_ROOT/charts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 [--profile <hardware-profile.yaml>] <model-values-file> [release-name]"
    echo ""
    echo "Examples:"
    echo "  $0 ./models/config/helm/granite-3.1-8b.yaml"
    echo "  $0 ./models/config/helm/nemotron-3-ultra-550b-nvfp4.yaml"
    exit 1
fi

MODEL_VALUES_FILE="$1"
RELEASE_NAME="${2:-}"

# Function to check if model exists in registry and resolve latest version details
check_model_in_registry() {
    local model_name="$1"
    local registry_namespace="$2"
    
    echo -e "${BLUE}Checking if model '$model_name' exists in model registry...${NC}"
    
    # Find the database pod
    local db_pod=$(oc get pods -n "$registry_namespace" -l app.kubernetes.io/component=database -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$db_pod" ]; then
        echo -e "${RED}Error: Could not find model registry database pod in namespace $registry_namespace${NC}"
        return 1
    fi
    
    # Get type IDs dynamically from Type table
    local registered_model_type_id=$(oc exec -n "$registry_namespace" "$db_pod" -- psql -U postgres -d modelregistry -t -A -c "SELECT id FROM \"Type\" WHERE name = 'kf.RegisteredModel';" 2>/dev/null | tr -d ' ')
    local model_version_type_id=$(oc exec -n "$registry_namespace" "$db_pod" -- psql -U postgres -d modelregistry -t -A -c "SELECT id FROM \"Type\" WHERE name = 'kf.ModelVersion';" 2>/dev/null | tr -d ' ')
    
    if [ -z "$registered_model_type_id" ] || [ -z "$model_version_type_id" ]; then
        echo -e "${RED}Error: Could not resolve type IDs from Type table${NC}"
        return 1
    fi
    
    # Query the registered model using dynamic type_id
    local query="SELECT c.id, c.name FROM \"Context\" c WHERE c.type_id = $registered_model_type_id AND c.name = '$model_name';"
    
    local result=$(oc exec -n "$registry_namespace" "$db_pod" -- psql -U postgres -d modelregistry -t -A -F'|' -c "$query" 2>/dev/null)
    
    if [ -z "$result" ]; then
        echo -e "${RED}✗ Model '$model_name' not found in model registry${NC}"
        echo ""
        echo "Available models in registry:"
        oc exec -n "$registry_namespace" "$db_pod" -- psql -U postgres -d modelregistry -t -A -c "SELECT DISTINCT c.name FROM \"Context\" c WHERE c.type_id = $registered_model_type_id;" 2>/dev/null | while read -r name; do
            echo "  - $name"
        done
        return 1
    fi
    
    IFS='|' read -r model_id model_reg_name <<< "$result"
    
    # Resolve latest model version using Attribution table to link Context -> Artifact
    # Model versions are Context entries with type_id for ModelVersion, named like "<model_id>:Version 1"
    local version_query="SELECT v.id, v.name
                         FROM \"Context\" v
                         WHERE v.type_id = $model_version_type_id
                         AND v.name LIKE '$model_id:%'
                         ORDER BY v.id DESC
                         LIMIT 1;"
    
    local version_result=$(oc exec -n "$registry_namespace" "$db_pod" -- psql -U postgres -d modelregistry -t -A -F'|' -c "$version_query" 2>/dev/null)
    
    if [ -z "$version_result" ]; then
        echo -e "${RED}✗ No model versions found for '$model_name'${NC}"
        return 1
    fi
    
    IFS='|' read -r model_version_id model_version_name <<< "$version_result"
    
    # Get URI using Attribution table: Context (version) -> Artifact (URI)
    # Attribution links context_id to artifact_id
    local uri_query="SELECT a.uri
                     FROM \"Artifact\" a
                     JOIN \"Attribution\" attr ON a.id = attr.artifact_id
                     WHERE attr.context_id = $model_version_id
                     AND a.uri IS NOT NULL
                     AND a.uri != ''
                     ORDER BY a.id DESC
                     LIMIT 1;"
    
    local model_uri=$(oc exec -n "$registry_namespace" "$db_pod" -- psql -U postgres -d modelregistry -t -A -c "$uri_query" 2>/dev/null | tr -d ' ')
    
    echo -e "${GREEN}✓ Model found in registry${NC}"
    echo "  Registered Model ID: $model_id"
    echo "  Model Name: $model_reg_name"
    echo "  Latest Model Version ID: $model_version_id"
    echo "  Latest Model Version Name: $model_version_name"
    if [ -n "$model_uri" ]; then
        echo "  Model URI: $model_uri"
    fi
    echo ""
    
    export FOUND_MODEL_ID="$model_id"
    export FOUND_MODEL_NAME="$model_reg_name"
    export FOUND_MODEL_VERSION_ID="$model_version_id"
    export FOUND_MODEL_VERSION_NAME="$model_version_name"
    export FOUND_MODEL_URI="$model_uri"
    
    return 0
}

echo -e "${GREEN}=== MaaS Model Deployment ===${NC}"
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

# Check if values file exists
if [ ! -f "$MODEL_VALUES_FILE" ]; then
    echo -e "${RED}Error: Model values file not found: $MODEL_VALUES_FILE${NC}"
    exit 1
fi

PROFILE_ARGS=()
if [ -n "$PROFILE_FILE" ]; then
    if [ ! -f "$PROFILE_FILE" ]; then
        echo -e "${RED}Error: Hardware profile not found: $PROFILE_FILE${NC}"
        exit 1
    fi
    PROFILE_ARGS=(-f "$PROFILE_FILE")
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# ── GPU Vendor Consistency Validation ────────────────────────────────────────
# Reads accelerator.vendor from the values file and:
#   1. Validates the vendor value is 'nvidia' or 'amd'
#   2. Confirms that vendor's GPU is actually allocatable on the cluster
#      (uses node.status.allocatable — NOT labels)
#   3. Warns if the declared inference image is inconsistent with the vendor
echo "Validating GPU vendor configuration..."
ACCEL_VENDOR=$(grep -A3 "^accelerator:" "$MODEL_VALUES_FILE" 2>/dev/null \
    | grep "^\s*vendor:" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'" | xargs)

if [[ -n "$ACCEL_VENDOR" ]]; then
    # Validate vendor value
    if [[ "$ACCEL_VENDOR" != "nvidia" && "$ACCEL_VENDOR" != "amd" ]]; then
        echo -e "${RED}Error: accelerator.vendor must be 'nvidia' or 'amd', got: '$ACCEL_VENDOR'${NC}"
        exit 1
    fi

    # Check declared vendor has allocatable GPUs on the cluster
    if [[ "$ACCEL_VENDOR" == "amd" ]]; then
        AMD_AVAILABLE=$(oc get nodes \
            -o jsonpath='{range .items[*]}{.status.allocatable.amd\.com/gpu}{"\n"}{end}' \
            2>/dev/null | grep -v '^$' | grep -v '^0$' | wc -l | tr -d ' ')
        if [[ "$AMD_AVAILABLE" -eq 0 ]]; then
            echo -e "${RED}Error: accelerator.vendor=amd but no amd.com/gpu allocatable on any cluster node.${NC}"
            echo "  Ensure isf-compute-operator has completed AMD GPU enablement before deploying."
            echo "  Check: oc get nodes -o custom-columns='NODE:.metadata.name,AMD:.status.allocatable.amd\\.com/gpu'"
            exit 1
        fi
        echo -e "${GREEN}✓ AMD GPU available: $AMD_AVAILABLE node(s) with amd.com/gpu allocatable${NC}"
    fi

    if [[ "$ACCEL_VENDOR" == "nvidia" ]]; then
        NVIDIA_AVAILABLE=$(oc get nodes \
            -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' \
            2>/dev/null | grep -v '^$' | grep -v '^0$' | wc -l | tr -d ' ')
        if [[ "$NVIDIA_AVAILABLE" -eq 0 ]]; then
            echo -e "${RED}Error: accelerator.vendor=nvidia but no nvidia.com/gpu allocatable on any cluster node.${NC}"
            echo "  Check: oc get nodes -o custom-columns='NODE:.metadata.name,NVIDIA:.status.allocatable.nvidia\\.com/gpu'"
            exit 1
        fi
        echo -e "${GREEN}✓ NVIDIA GPU available: $NVIDIA_AVAILABLE node(s) with nvidia.com/gpu allocatable${NC}"
    fi

    # Image / vendor consistency warning
    INFERENCE_IMAGE=$(grep -A30 "^inference:" "$MODEL_VALUES_FILE" 2>/dev/null \
        | grep "^\s*image:" | head -1 | awk '{print $2}' | tr -d '"' | xargs)
    if [[ -n "$INFERENCE_IMAGE" ]]; then
        if [[ "$ACCEL_VENDOR" == "amd" && "$INFERENCE_IMAGE" == *"cuda"* ]]; then
            echo -e "${YELLOW}⚠ Warning: accelerator.vendor=amd but inference image appears CUDA-based: $INFERENCE_IMAGE${NC}"
            echo "  Consider using a ROCm-compatible image (e.g. vllm-rocm-rhel9) for AMD GPU workloads."
        fi
        if [[ "$ACCEL_VENDOR" == "nvidia" && "$INFERENCE_IMAGE" == *"rocm"* ]]; then
            echo -e "${YELLOW}⚠ Warning: accelerator.vendor=nvidia but inference image appears ROCm-based: $INFERENCE_IMAGE${NC}"
            echo "  Consider using a CUDA-compatible image (e.g. vllm-cuda-rhel9) for NVIDIA GPU workloads."
        fi
    fi

    echo -e "${GREEN}✓ GPU vendor validation passed: accelerator.vendor=$ACCEL_VENDOR${NC}"
else
    echo -e "${YELLOW}⚠ accelerator.vendor not set in values file.${NC}"
    echo "  GPU scheduling may fail. Set accelerator.vendor: nvidia or accelerator.vendor: amd"
fi
echo ""

# Extract model name from values file if release name not provided
if [ -z "$RELEASE_NAME" ]; then
    RELEASE_NAME=$(grep "^  name:" "$MODEL_VALUES_FILE" | head -1 | awk '{print $2}' | tr -d '"')
    if [ -z "$RELEASE_NAME" ]; then
        echo -e "${RED}Error: Could not extract model name from values file${NC}"
        echo "Please provide release name as second argument"
        exit 1
    fi
fi

echo "Model deployment details:"
echo "  Release name: $RELEASE_NAME"
echo "  Values file: $MODEL_VALUES_FILE"
echo "  Chart: $CHARTS_DIR/maas-model-service"
echo ""

# Check if MaaS runtime or platform is installed
echo "Checking for MaaS runtime..."
if ! helm list -A | grep -qE "maas-runtime|maas-platform"; then
    echo -e "${YELLOW}Warning: MaaS runtime does not appear to be installed${NC}"
    echo "Please install the runtime first using: ./install-runtime.sh"
    echo ""
    echo "Continue anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if modelRegistry is enabled in values file
REGISTRY_ENABLED=$(grep -A 1 "^modelRegistry:" "$MODEL_VALUES_FILE" | grep "^  enabled:" | awk '{print $2}' | tr -d '"')

if [ "$REGISTRY_ENABLED" = "true" ]; then
    echo -e "${BLUE}Model registry deployment mode detected${NC}"
    
    # Extract model registry configuration
    REGISTRY_NAME=$(grep -A 10 "^modelRegistry:" "$MODEL_VALUES_FILE" | grep "^  name:" | awk '{print $2}' | tr -d '"')
    REGISTRY_NAMESPACE=$(grep -A 10 "^modelRegistry:" "$MODEL_VALUES_FILE" | grep "^  namespace:" | awk '{print $2}' | tr -d '"')
    REGISTERED_MODEL_NAME=$(grep -A 10 "^modelRegistry:" "$MODEL_VALUES_FILE" | grep "^  registeredModelName:" | awk '{print $2}' | tr -d '"')
    
    # Set defaults if not found
    REGISTRY_NAME="${REGISTRY_NAME:-model-registry}"
    REGISTRY_NAMESPACE="${REGISTRY_NAMESPACE:-rhoai-model-registries}"
    
    if [ -z "$REGISTERED_MODEL_NAME" ]; then
        echo -e "${RED}Error: modelRegistry.registeredModelName is required when modelRegistry.enabled is true${NC}"
        exit 1
    fi
    
    # Check if model exists in registry
    if ! check_model_in_registry "$REGISTERED_MODEL_NAME" "$REGISTRY_NAMESPACE"; then
        echo -e "${RED}Deployment aborted: Model not found in registry${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Model validation passed${NC}"
    echo ""
fi

# Get the cluster's wildcard domain dynamically
echo "Detecting cluster wildcard domain..."
CLUSTER_WILDCARD_DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
if [ -n "$CLUSTER_WILDCARD_DOMAIN" ]; then
    echo -e "${GREEN}✓ Detected cluster wildcard domain: $CLUSTER_WILDCARD_DOMAIN${NC}"
else
    echo -e "${YELLOW}⚠ Could not detect cluster wildcard domain, using default from values file${NC}"
fi
echo ""

HELM_SET_ARGS=()
if [ "$REGISTRY_ENABLED" = "true" ]; then
    if [ -n "$FOUND_MODEL_ID" ]; then
        HELM_SET_ARGS+=(--set "modelRegistry.registeredModelId=$FOUND_MODEL_ID")
    fi
    if [ -n "$FOUND_MODEL_VERSION_ID" ]; then
        HELM_SET_ARGS+=(--set "modelRegistry.modelVersionId=$FOUND_MODEL_VERSION_ID")
    fi
    # Only use the registry URI if the values file does not already define source.uri.
    # This prevents the placeholder OCI URI in the registry from overwriting a local
    # override such as s3:// or pvc:// set explicitly in the values file (BUG-007).
    VALUES_SOURCE_URI=$(grep "^  uri:" "$MODEL_VALUES_FILE" | head -1 | awk '{print $2}' | tr -d '"' | xargs)
    if [ -n "$FOUND_MODEL_URI" ] && [ -z "$VALUES_SOURCE_URI" ]; then
        HELM_SET_ARGS+=(--set "source.uri=$FOUND_MODEL_URI")
    fi
fi

# Add wildcard domain to Helm args if detected
if [ -n "$CLUSTER_WILDCARD_DOMAIN" ]; then
    HELM_SET_ARGS+=(--set "gateway.wildcardDomain=$CLUSTER_WILDCARD_DOMAIN")
fi

# Check if models namespace exists
MODEL_NAMESPACE=$(grep "^  namespace:" "$MODEL_VALUES_FILE" | head -1 | awk '{print $2}' | tr -d '"')
if [ -z "$MODEL_NAMESPACE" ]; then
    MODEL_NAMESPACE="maas-models"
fi

# Check if project.create is set to true in values file
PROJECT_CREATE=$(grep -A 1 "^project:" "$MODEL_VALUES_FILE" | grep "^  create:" | awk '{print $2}' | tr -d '"')

if ! oc get namespace "$MODEL_NAMESPACE" &> /dev/null; then
    if [ "$PROJECT_CREATE" = "true" ]; then
        echo -e "${BLUE}Creating namespace $MODEL_NAMESPACE with OpenShift AI dashboard label...${NC}"
        oc create namespace "$MODEL_NAMESPACE"
        oc label namespace "$MODEL_NAMESPACE" opendatahub.io/dashboard=true --overwrite
        HELM_SET_ARGS+=(--set "project.create=false")
    else
        echo -e "${YELLOW}Warning: Namespace $MODEL_NAMESPACE does not exist${NC}"
        echo "Set project.create: true in your values file to have it created"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Namespace $MODEL_NAMESPACE already exists${NC}"
    # Ensure dashboard label is present and prevent Helm from trying to recreate the existing namespace
    oc label namespace "$MODEL_NAMESPACE" opendatahub.io/dashboard=true --overwrite 2>/dev/null || true
    HELM_SET_ARGS+=(--set "project.create=false")
fi

echo ""
echo "Deploying model..."

# ── Pre-flight: PVC existence check ──────────────────────────────────────────
# If pvc.enabled=true and pvc.create=false the PVC must already exist.
PVC_ENABLED=$(grep -A 20 "^pvc:" "$MODEL_VALUES_FILE" 2>/dev/null \
    | grep "^\s*enabled:" | head -1 | awk '{print $2}' | tr -d '"' | xargs)
PVC_CREATE=$(grep -A 20 "^pvc:" "$MODEL_VALUES_FILE" 2>/dev/null \
    | grep "^\s*create:" | head -1 | awk '{print $2}' | tr -d '"' | xargs)
PVC_CLAIM=$(grep -A 20 "^pvc:" "$MODEL_VALUES_FILE" 2>/dev/null \
    | grep "^\s*claimName:" | head -1 | awk '{print $2}' | tr -d '"' | xargs)

if [[ "$PVC_ENABLED" == "true" && "$PVC_CREATE" != "true" ]]; then
    if [[ -z "$PVC_CLAIM" ]]; then
        echo -e "${RED}Error: pvc.enabled=true but pvc.claimName is not set${NC}"
        exit 1
    fi
    if ! oc get pvc "$PVC_CLAIM" -n "$MODEL_NAMESPACE" &>/dev/null; then
        echo -e "${RED}Error: PVC '$PVC_CLAIM' not found in namespace $MODEL_NAMESPACE${NC}"
        echo "  Either pre-populate the PVC first (see README Part B — Storage) or"
        echo "  set pvc.create: true to have Helm provision it."
        exit 1
    fi
    echo -e "${GREEN}✓ PVC '$PVC_CLAIM' exists in $MODEL_NAMESPACE${NC}"
fi
echo ""

# Deploy the model in the target namespace
helm upgrade --install "$RELEASE_NAME" "$CHARTS_DIR/maas-model-service" \
    -n "$MODEL_NAMESPACE" \
    "${PROFILE_ARGS[@]}" \
    -f "$MODEL_VALUES_FILE" \
    "${HELM_SET_ARGS[@]}" \
    --timeout 15m \
    --wait

echo ""
echo -e "${GREEN}✓ Model deployment initiated${NC}"
echo ""

# ── Post-deploy: wait for SA to be bound ─────────────────────────────────────
# RHOAI 3.5 timing bug: the LLMInferenceService reconciler will not proceed
# until the SA exists. Helm creates it — but the IS controller may have already
# started reconciling before the SA was written. Patch the IS to retrigger.
MODEL_NAME=$(grep "^  name:" "$MODEL_VALUES_FILE" | head -1 | awk '{print $2}' | tr -d '"')
SA_NAME="${MODEL_NAME}-sa"
SA_CHECK_COUNT=0
SA_CHECK_MAX=12

echo "Checking ServiceAccount '$SA_NAME' exists..."
while ! oc get sa "$SA_NAME" -n "$MODEL_NAMESPACE" &>/dev/null; do
    SA_CHECK_COUNT=$((SA_CHECK_COUNT + 1))
    if [[ $SA_CHECK_COUNT -ge $SA_CHECK_MAX ]]; then
        echo -e "${YELLOW}⚠ SA '$SA_NAME' not found after ${SA_CHECK_MAX}×5s — LLMInferenceService may not reconcile${NC}"
        break
    fi
    echo "  SA not ready yet, retrying in 5s ($SA_CHECK_COUNT/$SA_CHECK_MAX)..."
    sleep 5
done

if oc get sa "$SA_NAME" -n "$MODEL_NAMESPACE" &>/dev/null; then
    echo -e "${GREEN}✓ SA '$SA_NAME' ready${NC}"
    # Retrigger reconciliation by adding an annotation — safe no-op if already reconciling
    oc annotate llminferenceservice "$MODEL_NAME" -n "$MODEL_NAMESPACE" \
        maas.redhat.com/deploy-timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --overwrite &>/dev/null || true
fi

echo ""

# Wait for model to be ready
echo "Waiting for LLMInferenceService to become Ready (load time grows with model size)..."

if oc wait --for=condition=Ready llminferenceservice "$MODEL_NAME" -n "$MODEL_NAMESPACE" --timeout=10m 2>/dev/null; then
    echo -e "${GREEN}✓ Model is ready${NC}"
else
    echo -e "${YELLOW}⚠ Model is not ready yet — large models load slowly; check 'oc get pods' and re-run when the pod is Ready${NC}"
    echo "  Monitor: oc get llminferenceservice $MODEL_NAME -n $MODEL_NAMESPACE -w"
    echo "  Logs:    oc logs -n $MODEL_NAMESPACE -l serving.kserve.io/inferenceservice=$MODEL_NAME -c kserve-container -f"
fi

# Check if gateway is exposed
EXPOSE_GATEWAY=$(grep -A 5 "^gateway:" "$MODEL_VALUES_FILE" | grep "^  exposeExternally:" | awk '{print $2}' | tr -d '"')
GATEWAY_NAME=$(grep -A 5 "^gateway:" "$MODEL_VALUES_FILE" | grep "^  name:" | awk '{print $2}' | tr -d '"')
GATEWAY_NAMESPACE=$(grep -A 5 "^gateway:" "$MODEL_VALUES_FILE" | grep "^  namespace:" | awk '{print $2}' | tr -d '"')

# Set defaults
GATEWAY_NAME="${GATEWAY_NAME:-openshift-ai-inference}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-openshift-ingress}"

if [ "$EXPOSE_GATEWAY" = "true" ]; then
    echo ""
    echo -e "${BLUE}Gateway route will be created by Helm...${NC}"
    
    # Wait a moment for route to be created
    sleep 3
    
    # Construct the gateway URL using the detected wildcard domain
    if [ -n "$CLUSTER_WILDCARD_DOMAIN" ]; then
        GATEWAY_HOST="${GATEWAY_NAME}-${GATEWAY_NAMESPACE}.${CLUSTER_WILDCARD_DOMAIN}"
    else
        # Fallback to querying the route if domain detection failed
        GATEWAY_HOST=$(oc get route "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)
    fi
    
    if [ -n "$GATEWAY_HOST" ]; then
        echo -e "${GREEN}✓ Gateway route created successfully${NC}"
        echo ""
        echo -e "${GREEN}Gateway URL: https://$GATEWAY_HOST${NC}"
        echo "Model endpoint: https://$GATEWAY_HOST/$MODEL_NAMESPACE/$MODEL_NAME"
    else
        echo -e "${YELLOW}⚠ Gateway route not found yet${NC}"
        echo "Check route status: oc get route $GATEWAY_NAME -n $GATEWAY_NAMESPACE"
    fi
fi

echo ""
echo -e "${GREEN}=== Deployment Summary ===${NC}"
echo ""
echo "Model: $MODEL_NAME"
echo "Namespace: $MODEL_NAMESPACE"
echo "Status: oc get llminferenceservice $MODEL_NAME -n $MODEL_NAMESPACE"
echo ""

if [ "$EXPOSE_GATEWAY" = "true" ] && [ -n "$GATEWAY_HOST" ]; then
    echo -e "${BLUE}Test the model:${NC}"
    echo "  TOKEN=\$(oc whoami -t)"
    echo "  curl -k \"https://$GATEWAY_HOST/$MODEL_NAMESPACE/$MODEL_NAME/v1/models\" \\"
    echo "    -H \"Authorization: Bearer \${TOKEN}\""
    echo ""
    echo "  curl -k -X POST \"https://$GATEWAY_HOST/$MODEL_NAMESPACE/$MODEL_NAME/v1/completions\" \\"
    echo "    -H \"Authorization: Bearer \${TOKEN}\" \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"model\": \"$MODEL_NAME\", \"prompt\": \"Hello\", \"max_tokens\": 50}'"
else
    echo -e "${YELLOW}Gateway not exposed externally.${NC}"
    echo "To expose the gateway, set 'gateway.exposeExternally: true' in your values file"
    echo "Or see: quickstarts/model-as-a-service/README.md"
fi

echo ""
echo -e "${BLUE}View logs:${NC}"
echo "  oc logs -n $MODEL_NAMESPACE -l serving.kserve.io/inferenceservice=$MODEL_NAME -c kserve-container -f"
echo ""
echo -e "${BLUE}Troubleshooting:${NC}"
echo "  oc describe llminferenceservice $MODEL_NAME -n $MODEL_NAMESPACE"
echo "  oc get events -n $MODEL_NAMESPACE --sort-by='.lastTimestamp'"
echo ""
echo -e "${GREEN}Deployment complete!${NC}"

