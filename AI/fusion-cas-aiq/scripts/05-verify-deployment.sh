#!/usr/bin/env bash
# 05-verify-deployment.sh — v2
# ──────────────────────────────────────────────────────────────────────────────
# Automated end-to-end health and query verification.
# Source of truth: blog Parts 10, 11.
#
# Usage:
#   source aiq-fusion.env
#   ./scripts/05-verify-deployment.sh
#
# Optional env vars:
#   AIQ_NAMESPACE       — K8s namespace (default: ns-aiq)
#   TEST_QUERY          — custom test query (default: "What is irrigation?")
#   FUSION_CAS_SOURCE_1 — first data source ID (default: fusion_cas_1)
#   FUSION_CAS_SOURCE_2 — second data source ID (default: fusion_cas_2)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[05-verify]${NC} $*"; }
success() { echo -e "${GREEN}[05-verify]${NC} ✓ $*"; }
warn()    { echo -e "${YELLOW}[05-verify]${NC} ⚠ $*"; }
fail()    { echo -e "${RED}[05-verify]${NC} ✗ $*"; }
die()     { echo -e "${RED}[05-verify]${NC} ✗ $*" >&2; exit 1; }

AIQ_NAMESPACE="${AIQ_NAMESPACE:-ns-aiq}"
TEST_QUERY="${TEST_QUERY:-What is irrigation?}"
FUSION_CAS_SOURCE_1="${FUSION_CAS_SOURCE_1:-fusion_cas_1}"
FUSION_CAS_SOURCE_2="${FUSION_CAS_SOURCE_2:-fusion_cas_2}"
LOCAL_PORT=18000
ERRORS=0

# ── Part 10: Check pod readiness ─────────────────────────────────────────────
info "Part 10: Checking pod readiness in ${AIQ_NAMESPACE}"
kubectl get pods -n "${AIQ_NAMESPACE}"

kubectl wait pod \
    --for=condition=Ready \
    --selector=app.kubernetes.io/name=backend \
    -n "${AIQ_NAMESPACE}" \
    --timeout=120s \
    && success "Backend pod is Ready" \
    || { fail "Backend pod not Ready within 120s"; ((ERRORS++)); }

kubectl wait pod \
    --for=condition=Ready \
    --selector=app.kubernetes.io/name=frontend \
    -n "${AIQ_NAMESPACE}" \
    --timeout=120s \
    && success "Frontend pod is Ready" \
    || { fail "Frontend pod not Ready within 120s"; ((ERRORS++)); }

# ── Part 10: Verify Route ─────────────────────────────────────────────────────
if command -v oc &>/dev/null; then
    info "Part 10: Verifying Route and Service port alignment"
    ROUTE_INFO=$(oc get route aiq-frontend -n "${AIQ_NAMESPACE}" \
        -o jsonpath='targetPort={.spec.port.targetPort} termination={.spec.tls.termination}' 2>/dev/null || true)
    SVC_INFO=$(oc get svc aiq-frontend -n "${AIQ_NAMESPACE}" \
        -o jsonpath='{range .spec.ports[*]}{.name}={.port}->{.targetPort}{"\n"}{end}' 2>/dev/null || true)

    if echo "${ROUTE_INFO}" | grep -q "targetPort=http" && echo "${ROUTE_INFO}" | grep -q "termination=edge"; then
        success "Route: ${ROUTE_INFO}"
    else
        warn "Route alignment check: ${ROUTE_INFO:-not found}"
    fi

    if echo "${SVC_INFO}" | grep -q "http=3000->3000"; then
        success "Service port: ${SVC_INFO}"
    else
        warn "Service port check: ${SVC_INFO:-not found}"
    fi
fi

# ── Part 11: Port-forward to backend API ─────────────────────────────────────
info "Part 11: Starting port-forward to aiq-backend:8000 → localhost:${LOCAL_PORT}"
kubectl port-forward svc/aiq-backend "${LOCAL_PORT}:8000" \
    -n "${AIQ_NAMESPACE}" &>/tmp/pf-aiq-backend.log &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null; info "Port-forward closed"' EXIT

# Wait for port-forward to be ready
for i in {1..15}; do
    if curl -sf "http://localhost:${LOCAL_PORT}/v1/data_sources" &>/dev/null; then
        break
    fi
    sleep 1
done

# ── Part 11: GET /v1/data_sources ────────────────────────────────────────────
info "Part 11: Checking /v1/data_sources"
DATA_SOURCES=$(curl -sf "http://localhost:${LOCAL_PORT}/v1/data_sources" 2>/dev/null || true)

if [[ -z "${DATA_SOURCES}" ]]; then
    fail "/v1/data_sources returned no response"
    ((ERRORS++))
else
    echo "${DATA_SOURCES}" | python3 -m json.tool 2>/dev/null || echo "${DATA_SOURCES}"

    # Check each expected data source ID
    for SOURCE_ID in "web_search" "${FUSION_CAS_SOURCE_1}" "${FUSION_CAS_SOURCE_2}"; do
        if echo "${DATA_SOURCES}" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); ids=[s['id'] for s in d]; assert '${SOURCE_ID}' in ids" \
            2>/dev/null; then
            success "Data source '${SOURCE_ID}' registered"
        else
            fail "Data source '${SOURCE_ID}' NOT found in /v1/data_sources"
            ((ERRORS++))
        fi
    done
fi

# ── Part 11: POST /v1/chat ───────────────────────────────────────────────────
info "Part 11: Testing POST /v1/chat (query: '${TEST_QUERY}')"
CHAT_RESP=$(curl -sf -X POST "http://localhost:${LOCAL_PORT}/v1/chat" \
    -H "Content-Type: application/json" \
    -d "{\"messages\":[{\"role\":\"user\",\"content\":\"${TEST_QUERY}\"}],\"data_sources\":[\"${FUSION_CAS_SOURCE_1}\"]}" \
    2>/dev/null || true)

if [[ -z "${CHAT_RESP}" ]]; then
    fail "POST /v1/chat returned no response"
    ((ERRORS++))
else
    CONTENT=$(echo "${CHAT_RESP}" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'][:300])" \
        2>/dev/null || echo "")
    if [[ -n "${CONTENT}" ]]; then
        success "Chat response received:"
        echo "    ${CONTENT}"
    else
        fail "Chat response missing expected fields"
        echo "${CHAT_RESP}" | python3 -m json.tool 2>/dev/null || echo "${CHAT_RESP}"
        ((ERRORS++))
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ ${ERRORS} -eq 0 ]]; then
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  All verification checks passed ✓                ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
    echo ""
    if command -v oc &>/dev/null; then
        ROUTE=$(oc get route aiq-frontend -n "${AIQ_NAMESPACE}" \
            -o jsonpath='{.spec.host}' 2>/dev/null || true)
        if [[ -n "${ROUTE}" ]]; then
            echo -e "  Frontend:  ${CYAN}https://${ROUTE}${NC}"
        fi
    fi
    echo -e "  API docs:  kubectl port-forward svc/aiq-backend 8000:8000 -n ${AIQ_NAMESPACE}"
    echo -e "             then open: http://localhost:8000/docs"
else
    echo -e "${RED}══════════════════════════════════════════════════${NC}"
    echo -e "${RED}  ${ERRORS} verification check(s) FAILED ✗           ${NC}"
    echo -e "${RED}══════════════════════════════════════════════════${NC}"
    exit 1
fi
