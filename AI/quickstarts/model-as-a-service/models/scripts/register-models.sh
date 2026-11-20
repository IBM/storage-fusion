#!/bin/bash
# register-models.sh - Register models into central RHOAI Model Registry
# Usage:
#   ./register-models.sh <model-name | values-file | --all> [-n registry-namespace]
# Examples:
#   ./register-models.sh nemotron-ultra-550b
#   ./register-models.sh models/config/helm/nemotron-3-ultra-550b-nvfp4.yaml
#   ./register-models.sh --all

set -euo pipefail

REGISTRY_NAMESPACE="rhoai-model-registries"
TARGET_MODEL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            REGISTRY_NAMESPACE="$2"
            shift 2
            ;;
        --all)
            TARGET_MODEL="all"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 <model-name | values-file | --all> [-n registry-namespace]"
            echo ""
            echo "Examples:"
            echo "  $0 nemotron-ultra-550b"
            echo "  $0 models/config/helm/nemotron-3-ultra-550b-nvfp4.yaml"
            echo "  $0 --all"
            exit 0
            ;;
        *)
            if [ -z "$TARGET_MODEL" ]; then
                TARGET_MODEL="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$TARGET_MODEL" ]; then
    echo "Usage: $0 <model-name | values-file | --all> [-n registry-namespace]"
    echo ""
    echo "Available known models: nemotron-ultra-550b, gpt-oss-20b, granite-3.1-8b-instruct, laguna-s2-1, nemotron-3, qwen3-8b-fp8"
    echo "Or specify a model values YAML file, or '--all'."
    exit 1
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Registering Model in Model Registry ===${NC}"
echo "Registry namespace: ${REGISTRY_NAMESPACE}"

TOKEN=$(oc whoami -t 2>/dev/null || echo "")
if [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: Not logged into OpenShift. Please run 'oc login' first.${NC}"
    exit 1
fi

REGISTRY_HOST=$(oc get route -n "${REGISTRY_NAMESPACE}" -l app.kubernetes.io/name=model-registry -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")
if [ -z "$REGISTRY_HOST" ]; then
    REGISTRY_HOST=$(oc get route model-registry-https -n "${REGISTRY_NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
fi

if [ -z "$REGISTRY_HOST" ]; then
    echo -e "${RED}Error: Model Registry route not found in namespace ${REGISTRY_NAMESPACE}${NC}"
    exit 1
fi

REGISTRY_URL="https://${REGISTRY_HOST}/api/model_registry/v1alpha3"
echo "Registry URL: ${REGISTRY_URL}"
echo ""

register_model() {
    local model_name="$1"
    local model_desc="$2"
    local model_uri="$3"

    echo -e "${BLUE}Registering ${model_name}...${NC}"

    # 1. Register Model (or get existing ID)
    local model_id=$(curl -sk -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"${model_name}\",\"description\":\"${model_desc}\"}" \
        "${REGISTRY_URL}/registered_models" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

    # Fallback: query ID if already registered
    if [ -z "$model_id" ]; then
        model_id=$(curl -sk -H "Authorization: Bearer ${TOKEN}" "${REGISTRY_URL}/registered_models" \
            | python3 -c "import sys,json; models=[m['id'] for m in json.load(sys.stdin).get('items',[]) if m['name']=='${model_name}']; print(models[0] if models else '')" 2>/dev/null || echo "")
    fi

    if [ -z "$model_id" ]; then
        echo -e "${RED}Failed to register or locate model ${model_name}${NC}"
        return 1
    fi

    # 2. Register Version v1.0
    local version_id=$(curl -sk -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"v1.0\",\"registeredModelId\":\"${model_id}\"}" \
        "${REGISTRY_URL}/registered_models/${model_id}/versions" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

    if [ -z "$version_id" ]; then
        version_id=$(curl -sk -H "Authorization: Bearer ${TOKEN}" "${REGISTRY_URL}/registered_models/${model_id}/versions" \
            | python3 -c "import sys,json; versions=[v['id'] for v in json.load(sys.stdin).get('items',[]) if v['name']=='v1.0']; print(versions[0] if versions else '')" 2>/dev/null || echo "")
    fi

    # 3. Register Artifact with URI
    if [ -n "$version_id" ]; then
        curl -sk -X POST \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"modelcar-${model_name}\",\"uri\":\"${model_uri}\",\"artifactType\":\"model-artifact\"}" \
            "${REGISTRY_URL}/model_versions/${version_id}/artifacts" >/dev/null 2>&1 || true
    fi

    echo -e "${GREEN}✓ ${model_name} registered successfully (Model ID: ${model_id}, Version: v1.0)${NC}"
}

# Resolve model details if passed a YAML file
if [ -f "$TARGET_MODEL" ]; then
    REG_NAME=$(grep -A 10 "^modelRegistry:" "$TARGET_MODEL" | grep "^  registeredModelName:" | awk '{print $2}' | tr -d '"' || echo "")
    if [ -z "$REG_NAME" ]; then
        REG_NAME=$(grep "^  name:" "$TARGET_MODEL" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
    fi
    DESC=$(grep "^  displayName:" "$TARGET_MODEL" | head -1 | cut -d: -f2- | tr -d '"' | sed 's/^[ \t]*//' || echo "$REG_NAME")
    URI=$(grep "^  uri:" "$TARGET_MODEL" | head -1 | awk '{print $2}' | tr -d '"' || echo "oci://registry.redhat.io/rhelai1/modelcar-${REG_NAME}:latest")
    
    register_model "$REG_NAME" "${DESC:-$REG_NAME}" "${URI:-oci://registry.redhat.io/rhelai1/modelcar-${REG_NAME}:latest}"
elif [ "$TARGET_MODEL" = "all" ]; then
    register_model "gpt-oss-20b" "OpenAI GPT-OSS 20B Model" "oci://registry.redhat.io/rhelai1/modelcar-gpt-oss-20b:latest"
    register_model "laguna-s2-1" "Poolside Laguna S2.1 Advanced Reasoning Model" "oci://registry.redhat.io/rhelai1/modelcar-laguna-s2-1:latest"
    register_model "nemotron-3" "NVIDIA Nemotron 3 8B Fast Completion Model" "oci://registry.redhat.io/rhelai1/modelcar-nemotron-3:latest"
    register_model "nemotron-ultra-550b" "NVIDIA Nemotron 3 Ultra 550B NVFP4 Model" "pvc://nemotron-model-weights-pvc/"
    register_model "granite-3.1-8b-instruct" "IBM Granite 3.1 8B Instruct Model" "oci://registry.redhat.io/rhelai1/modelcar-granite-3.1-8b-instruct:latest"
    register_model "qwen3-8b-fp8" "Qwen 3 8B FP8 Model" "oci://registry.redhat.io/rhelai1/modelcar-qwen3-8b-fp8-dynamic:latest"
elif [ "$TARGET_MODEL" = "nemotron-ultra-550b" ] || [ "$TARGET_MODEL" = "nemotron-ultra" ]; then
    register_model "nemotron-ultra-550b" "NVIDIA Nemotron 3 Ultra 550B NVFP4 Model" "pvc://nemotron-model-weights-pvc/"
elif [ "$TARGET_MODEL" = "gpt-oss-20b" ]; then
    register_model "gpt-oss-20b" "OpenAI GPT-OSS 20B Model" "oci://registry.redhat.io/rhelai1/modelcar-gpt-oss-20b:latest"
elif [ "$TARGET_MODEL" = "granite-3.1-8b-instruct" ] || [ "$TARGET_MODEL" = "granite-3.1-8b" ]; then
    register_model "granite-3.1-8b-instruct" "IBM Granite 3.1 8B Instruct Model" "oci://registry.redhat.io/rhelai1/modelcar-granite-3.1-8b-instruct:latest"
elif [ "$TARGET_MODEL" = "laguna-s2-1" ]; then
    register_model "laguna-s2-1" "Poolside Laguna S2.1 Advanced Reasoning Model" "oci://registry.redhat.io/rhelai1/modelcar-laguna-s2-1:latest"
elif [ "$TARGET_MODEL" = "nemotron-3" ]; then
    register_model "nemotron-3" "NVIDIA Nemotron 3 8B Fast Completion Model" "oci://registry.redhat.io/rhelai1/modelcar-nemotron-3:latest"
elif [ "$TARGET_MODEL" = "qwen3-8b-fp8" ]; then
    register_model "qwen3-8b-fp8" "Qwen 3 8B FP8 Model" "oci://registry.redhat.io/rhelai1/modelcar-qwen3-8b-fp8-dynamic:latest"
else
    register_model "$TARGET_MODEL" "$TARGET_MODEL Foundation Model" "oci://registry.redhat.io/rhelai1/modelcar-${TARGET_MODEL}:latest"
fi

echo ""
echo -e "${GREEN}Registration complete!${NC}"
echo "You can deploy using:"
echo "  ./models/scripts/deploy-model.sh models/config/helm/<model>.yaml"
