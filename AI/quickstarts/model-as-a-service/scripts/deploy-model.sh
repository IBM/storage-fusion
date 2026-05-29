#!/bin/bash
# deploy-model.sh - Deploy a model to MaaS Platform
# Usage: ./deploy-model.sh <model-values-file> [release-name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHARTS_DIR="$PROJECT_ROOT/deploy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <model-values-file> [release-name]"
    echo ""
    echo "Examples:"
    echo "  $0 ../examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml"
    echo "  $0 ../examples/Fusion-Agentic-Assistance-Platform/models/nemotron-values.yaml nemotron"
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

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
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

# Check if MaaS runtime is installed
echo "Checking for MaaS runtime..."
if ! helm list -A | grep -q "maas-runtime"; then
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
    if [ -n "$FOUND_MODEL_URI" ]; then
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
        echo -e "${BLUE}Namespace $MODEL_NAMESPACE will be created by Helm${NC}"
    else
        echo -e "${YELLOW}Warning: Namespace $MODEL_NAMESPACE does not exist${NC}"
        echo "Set project.create: true in your values file to have Helm create it"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Namespace $MODEL_NAMESPACE already exists${NC}"
fi

echo ""
echo "Deploying model..."

# Deploy the model
helm upgrade --install "$RELEASE_NAME" "$CHARTS_DIR/maas-model-service" \
    -f "$MODEL_VALUES_FILE" \
    "${HELM_SET_ARGS[@]}" \
    --timeout 15m \
    --wait

echo ""
echo -e "${GREEN}✓ Model deployment initiated${NC}"
echo ""

# Wait for model to be ready
echo "Waiting for model to be ready..."
MODEL_NAME=$(grep "^  name:" "$MODEL_VALUES_FILE" | head -1 | awk '{print $2}' | tr -d '"')

if oc wait --for=condition=Ready llminferenceservice "$MODEL_NAME" -n "$MODEL_NAMESPACE" --timeout=10m 2>/dev/null; then
    echo -e "${GREEN}✓ Model is ready${NC}"
else
    echo -e "${YELLOW}⚠ Model is not ready yet (this may take a while)${NC}"
    echo "Check status with: oc get llminferenceservice $MODEL_NAME -n $MODEL_NAMESPACE"
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
    echo "Or see: quickstarts/model-as-a-service/docs/GETTING_STARTED.md"
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

