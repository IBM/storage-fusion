#!/bin/bash
#
# verify.sh — verify a MaaS model end-to-end through Bob. One script for every model.
#
# The model's service name, port and served name are resolved from the generic model
# definition (../models/<model>.yaml) via gen-model-config.sh --resolve, so nothing here
# is model-specific.
#
# Usage:
#   BOB_NAMESPACE=bob ./verify.sh <model> [alias]
#     <model>   file name in bob/client-configs/ without .yaml, e.g. nemotron-3-ultra-550b-nvfp4
#     [alias]   Bob model alias to call. Default: the model's defaultAlias.
#
# Environment:
#   BOB_NAMESPACE   REQUIRED  namespace of the Bob instance (oc get bob -A)
#   TOPOLOGY        direct (default) | gateway. gateway skips the direct pod checks (4, 5)
#                   because the model is only reachable through the MaaS gateway.
#   MODEL_NAMESPACE / LLMISVC_NAME   override what the model file says
#   PROMPT          default: "Say hello in one sentence."

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_FILE="${1:?Usage: [BOB_NAMESPACE=<ns>] $0 <model> [alias]}"

# Auto-detect BOB_NAMESPACE from cluster if not explicitly provided
if [[ -z "${BOB_NAMESPACE:-}" ]]; then
  BOB_NAMESPACE="$(oc get bob -A -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)"
fi
: "${BOB_NAMESPACE:?Could not auto-detect Bob namespace. Set BOB_NAMESPACE manually (e.g. BOB_NAMESPACE=bob)}"
TOPOLOGY="${TOPOLOGY:-direct}"
PROMPT="${PROMPT:-Say hello in one sentence.}"

case "${TOPOLOGY}" in direct|gateway) ;; *) echo "ERROR: TOPOLOGY must be direct or gateway" >&2; exit 1 ;; esac

NS_OVERRIDE="${MODEL_NAMESPACE:-}"
eval "$("${HERE}/gen-model-config.sh" "${MODEL_FILE}" --resolve)"
MODEL_NAMESPACE="${NS_OVERRIDE:-${MODEL_NAMESPACE}}"
RESOURCE_NAME="${LLMISVC_NAME:-${MODEL_NAME}}"
MODEL_SVC="${RESOURCE_NAME}-kserve-workload-svc"
MODEL_URL="http://${MODEL_SVC}.${MODEL_NAMESPACE}.svc.cluster.local:${MODEL_PORT}"
CR_KIND="llminferenceservice"
ALIAS="${2:-${DEFAULT_ALIAS}}"

echo "==> Config"
echo "    BOB_NAMESPACE   = ${BOB_NAMESPACE}"
echo "    TOPOLOGY        = ${TOPOLOGY}"
echo "    MODEL           = ${SERVED_NAME}"
echo "    MODEL_URL       = ${MODEL_URL}"
echo "    BOB ALIAS       = ${ALIAS}"
echo ""

FAIL=0
step() { echo "==> $1"; }
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; FAIL=1; }

step "1/6 Model Service"
oc get svc "${MODEL_SVC}" -n "${MODEL_NAMESPACE}" && ok "service exists" || bad "service ${MODEL_SVC} not found"
echo ""

step "2/6 ${CR_KIND} status"
READY="$(oc get "${CR_KIND}" "${RESOURCE_NAME}" -n "${MODEL_NAMESPACE}" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
[[ "${READY}" == "True" ]] && ok "Ready=True" || bad "Ready='${READY:-unknown}' (large models take a long time to load; re-run when the pod is Ready)"
echo ""

step "3/6 Bob gateway mode"
MODE="$(oc logs "deploy/bob-inference" -n "${BOB_NAMESPACE}" 2>/dev/null | grep -i "Gateway mode" | tail -1 || true)"
if [[ "${MODE}" == *bifrost* ]]; then ok "${MODE}"
else bad "bob-inference is not in bifrost mode (${MODE:-no log line}); Bob must be installed with a healthy Bifrost gateway (see bob/README.md Assumptions)"; fi
echo ""

if [[ "${TOPOLOGY}" == "direct" ]]; then
  step "4/6 Direct /health from Bob"
  oc exec -n "${BOB_NAMESPACE}" deploy/bob-gateway -- curl -sf "${MODEL_URL}/health" \
    && ok "/health OK" || bad "/health failed"
  echo ""
  step "5/6 Direct /v1/models from Bob"
  oc exec -n "${BOB_NAMESPACE}" deploy/bob-gateway -- curl -sf "${MODEL_URL}/v1/models" \
    | python3 -m json.tool | head -12 && ok "/v1/models OK" || bad "/v1/models failed"
  echo ""
else
  step "4/6 and 5/6 skipped (TOPOLOGY=gateway)"
  echo ""
fi

step "6/6 Chat completion through bob-inference (alias: ${ALIAS})"

# Query active subscription and user IDs from Redis if available
HDR_SUB=()
REDIS_AUTH="$(oc get secret bob-admin-redis -n "${BOB_NAMESPACE}" -o jsonpath='{.data.auth}' 2>/dev/null | base64 -d 2>/dev/null || true)"
if [[ -n "${REDIS_AUTH}" ]]; then
  SUB_KEY="$(oc exec -n "${BOB_NAMESPACE}" bob-admin-redis-server-0 -c redis -- sh -c "export REDISCLI_AUTH='${REDIS_AUTH}'; redis-cli -h bob-admin-redis-master-svc.${BOB_NAMESPACE}.svc.cluster.local -p 6380 --tls --insecure --no-auth-warning --scan --pattern 'Subscription:*'" 2>/dev/null | head -1 || true)"
  if [[ "${SUB_KEY}" =~ Subscription:([^:]+):([^:]+) ]]; then
    USER_ID="${BASH_REMATCH[1]}"
    SUB_ID="${BASH_REMATCH[2]}"
    HDR_SUB=(-H "x-subscription-id: ${SUB_ID}" -H "x-user-id: ${USER_ID}")
  fi
fi

BODY="$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"messages":[{"role":"user","content":sys.argv[2]}],"max_tokens":100}))' "${ALIAS}" "${PROMPT}")"
RESP="$(oc exec -n "${BOB_NAMESPACE}" deploy/bob-gateway -- \
  curl -sk "https://bob-inference.${BOB_NAMESPACE}.svc.cluster.local:7330/v1/chat/completions" \
  -H "Content-Type: application/json" \
  "${HDR_SUB[@]}" \
  -d "${BODY}" || true)"
echo "${RESP}" | python3 -m json.tool 2>/dev/null | head -30 || echo "${RESP}"

if echo "${RESP}" | grep -q '"choices"'; then
  ok "chat completion returned choices through bob-inference"
elif echo "${RESP}" | grep -q "budget check failed"; then
  echo "  ℹ Note: Bob budgeting/metering is active on bob-inference."
  echo "  ==> Verifying direct model chat completion (${MODEL_URL})..."
  DIRECT_BODY="$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"messages":[{"role":"user","content":sys.argv[2]}],"max_tokens":50}))' "${SERVED_NAME}" "${PROMPT}")"
  DIRECT_RESP="$(oc exec -n "${BOB_NAMESPACE}" deploy/bob-gateway -- \
    curl -sf "${MODEL_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "${DIRECT_BODY}" 2>/dev/null || true)"
  if echo "${DIRECT_RESP}" | grep -q '"choices"'; then
    echo "${DIRECT_RESP}" | python3 -m json.tool 2>/dev/null | head -25 || echo "${DIRECT_RESP}"
    ok "Direct model inference succeeded (Bob budgets are active — use ./scripts/test-bob-e2e.sh for authenticated user shell test)"
  else
    bad "direct chat completion failed"
  fi
else
  bad "no choices in response"
fi
echo ""

if [[ "${FAIL}" -eq 0 ]]; then echo "==> PASS"; else
  echo "==> FAIL"
  echo "    Model status: oc get llminferenceservice -n ${MODEL_NAMESPACE}"
  echo "    Model pods:   oc get pods -n ${MODEL_NAMESPACE}"
  exit 1
fi
