#!/bin/bash
# Verify the llmops-chat-app deployment (React UI + FastAPI stack)
#
# Checks:
#   1. Pod is running and image tag
#   2. ConfigMap values (endpoints, model, store)
#   3. Secret keys are present (not empty)
#   4. /healthz returns {"ready":true}
#   5. /api/models returns at least one model
#   6. /api/vector-stores returns at least one store
#   7. ArgoCD Application sync status

set -e

NAMESPACE="llmops-platform"
APP_LABEL="app.kubernetes.io/name=llmops-chat-app"
PASS="✅"
FAIL="❌"
WARN="⚠️ "

# ── Helpers ──────────────────────────────────────────────────────────────────
ok()   { echo "  $PASS $1"; }
fail() { echo "  $FAIL $1"; ERRORS=$((ERRORS+1)); }
warn() { echo "  $WARN $1"; }
section() { echo ""; echo "── $1 ──────────────────────────────────────────"; }

ERRORS=0

# ── 0. Login check ───────────────────────────────────────────────────────────
section "Cluster"
oc whoami &>/dev/null && ok "Logged in as $(oc whoami)" || { echo "$FAIL Not logged in to OpenShift"; exit 1; }

# ── 1. Pod status ─────────────────────────────────────────────────────────────
section "Pod"
POD=$(oc get pods -n $NAMESPACE -l $APP_LABEL \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
  fail "No pod found with label $APP_LABEL in $NAMESPACE"
  exit 1
fi

PHASE=$(oc get pod $POD -n $NAMESPACE -o jsonpath='{.status.phase}')
READY=$(oc get pod $POD -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].ready}')
IMAGE=$(oc get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[0].image}')
START=$(oc get pod $POD -n $NAMESPACE -o jsonpath='{.status.startTime}')

echo "  Pod   : $POD"
echo "  Image : $IMAGE"
echo "  Start : $START"
[ "$PHASE" = "Running" ] && ok "Phase: Running" || fail "Phase: $PHASE (expected Running)"
[ "$READY" = "true" ]   && ok "Container ready" || fail "Container not ready"

# ── 2. ConfigMap ──────────────────────────────────────────────────────────────
section "ConfigMap (llmops-config)"
CM="llmops-config"
CAS_EP=$(oc get configmap $CM -n $NAMESPACE -o jsonpath='{.data.cas-endpoint}' 2>/dev/null)
GW_EP=$(oc get configmap $CM  -n $NAMESPACE -o jsonpath='{.data.model-gateway-endpoint}' 2>/dev/null)
MODEL=$(oc get configmap $CM  -n $NAMESPACE -o jsonpath='{.data.model-name}' 2>/dev/null)
STORE=$(oc get configmap $CM  -n $NAMESPACE -o jsonpath='{.data.cas-vector-store-id}' 2>/dev/null)
TOPK=$(oc get configmap $CM   -n $NAMESPACE -o jsonpath='{.data.default-top-k}' 2>/dev/null)

[ -n "$CAS_EP" ] && ok "cas-endpoint        : $CAS_EP"        || fail "cas-endpoint is empty"
[ -n "$GW_EP" ]  && ok "model-gateway-endpoint: $GW_EP"       || fail "model-gateway-endpoint is empty"
[ -n "$MODEL" ]  && ok "model-name          : $MODEL"          || fail "model-name is empty"
[ -n "$STORE" ]  && ok "cas-vector-store-id : $STORE"         || warn "cas-vector-store-id is empty (will auto-discover)"
echo "  default-top-k       : ${TOPK:-5}"

# ── 3. Secret ─────────────────────────────────────────────────────────────────
section "Secret (llmops-secrets)"
CAS_KEY=$(oc get secret llmops-secrets -n $NAMESPACE \
  -o jsonpath='{.data.cas_api_key}' 2>/dev/null | base64 -d 2>/dev/null)
GW_KEY=$(oc get secret llmops-secrets -n $NAMESPACE \
  -o jsonpath='{.data.model_gateway_api_key}' 2>/dev/null | base64 -d 2>/dev/null)

[ -n "$CAS_KEY" ] && ok "cas_api_key is set (${#CAS_KEY} chars)" \
                  || fail "cas_api_key is EMPTY — check secrets.hardcoded or ExternalSecret"
[ -n "$GW_KEY" ]  && ok "model_gateway_api_key is set (${#GW_KEY} chars)" \
                  || fail "model_gateway_api_key is EMPTY"

# ── 4. Health endpoint ────────────────────────────────────────────────────────
section "Health (/healthz)"
ROUTE=$(oc get route llmops-chat-app -n $NAMESPACE \
  -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$ROUTE" ]; then
  warn "No Route found — using port-forward for health check"
  # Try port-forward in background
  oc port-forward svc/llmops-chat-app 18000:8000 -n $NAMESPACE &>/dev/null &
  PF_PID=$!
  sleep 2
  BASE_URL="http://localhost:18000"
else
  BASE_URL="https://$ROUTE"
fi

HEALTH=$(curl -sk "$BASE_URL/healthz" 2>/dev/null)
READY_FLAG=$(echo "$HEALTH" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ready',''))" 2>/dev/null)

echo "  URL    : $BASE_URL"
echo "  Response: $HEALTH"
[ "$READY_FLAG" = "True" ] || [ "$READY_FLAG" = "true" ] \
  && ok "Service is ready" \
  || fail "Service reports ready=false — check pod logs: kubectl logs -n $NAMESPACE deployment/llmops-chat-app"

# ── 5. Models ─────────────────────────────────────────────────────────────────
section "API — /api/models"
MODELS=$(curl -sk "$BASE_URL/api/models" 2>/dev/null)
MODEL_COUNT=$(echo "$MODELS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
[ "$MODEL_COUNT" -gt 0 ] \
  && ok "$MODEL_COUNT model(s): $MODELS" \
  || fail "No models returned — Model Gateway unreachable or key invalid"

# ── 6. Vector stores ──────────────────────────────────────────────────────────
section "API — /api/vector-stores"
STORES=$(curl -sk "$BASE_URL/api/vector-stores" 2>/dev/null)
STORE_COUNT=$(echo "$STORES" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
[ "$STORE_COUNT" -gt 0 ] \
  && ok "$STORE_COUNT vector store(s) available" \
  || fail "No vector stores returned — CAS unreachable or key invalid (401)"

# ── 7. ArgoCD sync status ─────────────────────────────────────────────────────
section "ArgoCD"
ARGOCD_STATUS=$(oc get application llmops-platform -n openshift-gitops \
  -o jsonpath='{.status.sync.status}' 2>/dev/null)
ARGOCD_HEALTH=$(oc get application llmops-platform -n openshift-gitops \
  -o jsonpath='{.status.health.status}' 2>/dev/null)

if [ -n "$ARGOCD_STATUS" ]; then
  [ "$ARGOCD_STATUS" = "Synced" ]  && ok "Sync   : $ARGOCD_STATUS"  || warn "Sync   : $ARGOCD_STATUS"
  [ "$ARGOCD_HEALTH" = "Healthy" ] && ok "Health : $ARGOCD_HEALTH" || warn "Health : $ARGOCD_HEALTH"
else
  warn "ArgoCD Application 'llmops-platform' not found in openshift-gitops"
fi

# ── Cleanup port-forward if used ─────────────────────────────────────────────
[ -n "$PF_PID" ] && kill $PF_PID 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ "$ERRORS" -eq 0 ]; then
  echo "  ✅  All checks passed — deployment is healthy"
else
  echo "  ❌  $ERRORS check(s) failed — see above"
  echo ""
  echo "  Quick debug:"
  echo "    kubectl logs -n $NAMESPACE deployment/llmops-chat-app"
  echo "    kubectl describe pod -n $NAMESPACE -l $APP_LABEL"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit $ERRORS
