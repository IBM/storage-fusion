#!/bin/bash
# Verify what's actually deployed

NAMESPACE="llmops-platform"

echo "=== Deployment Verification ==="
echo ""

# Check if logged in
oc whoami 2>/dev/null || { echo "❌ Not logged in"; exit 1; }

# Get pod name
POD=$(oc get pods -n $NAMESPACE -l app.kubernetes.io/name=llmops-chat-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
    echo "❌ No pod found"
    exit 1
fi

echo "Pod: $POD"
echo ""

# Check pod age
echo "Pod Age:"
oc get pod $POD -n $NAMESPACE -o jsonpath='{.status.startTime}'
echo ""
echo ""

# Check image
echo "Container Image:"
oc get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[0].image}'
echo ""
echo ""

# Check environment variables
echo "Environment Variables:"
oc exec $POD -n $NAMESPACE -- env | grep -E "(CAS_|LLM_)" | sort
echo ""

# Check if src/rag_flow.py exists (new) or src/langflow_rag_flow.py (old)
echo "Checking for new code..."
if oc exec $POD -n $NAMESPACE -- test -f /app/src/rag_flow.py 2>/dev/null; then
    echo "✅ NEW CODE: src/rag_flow.py exists"
else
    echo "❌ OLD CODE: src/rag_flow.py NOT found"
fi

if oc exec $POD -n $NAMESPACE -- test -f /app/src/langflow_rag_flow.py 2>/dev/null; then
    echo "❌ OLD CODE: src/langflow_rag_flow.py still exists"
else
    echo "✅ NEW CODE: src/langflow_rag_flow.py removed"
fi
echo ""

# Check ConfigMap
echo "ConfigMap Values:"
echo "  cas-endpoint: $(oc get configmap llmops-config -n $NAMESPACE -o jsonpath='{.data.cas-endpoint}')"
echo "  cas-use-mcp: $(oc get configmap llmops-config -n $NAMESPACE -o jsonpath='{.data.cas-use-mcp}')"
echo "  cas-vector-store-id: $(oc get configmap llmops-config -n $NAMESPACE -o jsonpath='{.data.cas-vector-store-id}')"
echo ""

# Test Python import
echo "Testing Python imports in pod..."
oc exec $POD -n $NAMESPACE -- python3 -c "
try:
    from src.rag_flow import RAGFlow
    print('✅ NEW CODE: Can import RAGFlow from src.rag_flow')
except ImportError as e:
    print(f'❌ OLD CODE: Cannot import RAGFlow: {e}')
    
try:
    from src.langflow_rag_flow import LangFlowRAGFlow
    print('❌ OLD CODE: Can still import LangFlowRAGFlow')
except ImportError:
    print('✅ NEW CODE: LangFlowRAGFlow import fails (expected)')
" 2>&1
echo ""

echo "=== Summary ==="
echo ""
echo "If you see OLD CODE markers above, you need to:"
echo "1. Build new image: podman build -f Dockerfile.chat-app -t IMAGE_NAME ."
echo "2. Push image: podman push IMAGE_NAME"
echo "3. Delete pod: oc delete pod $POD -n $NAMESPACE"
echo "4. Wait for new pod: oc wait --for=condition=ready pod -l app.kubernetes.io/name=llmops-chat-app -n $NAMESPACE"