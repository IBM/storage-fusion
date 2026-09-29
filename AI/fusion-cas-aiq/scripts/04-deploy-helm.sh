#!/usr/bin/env bash
# 04-deploy-helm.sh — v2
# ──────────────────────────────────────────────────────────────────────────────
# Deploys AI-Q with Helm using fusion-config-override.yaml, then explicitly
# creates the OpenShift Route for the frontend UI.
#
# The upstream AI-Q Helm chart does NOT include a Route template — route.enabled
# in values.yaml is silently ignored. The Route is therefore created with an
# explicit oc apply after the Helm release is deployed.
#
# Usage:
#   source aiq-fusion.env
#   ./scripts/04-deploy-helm.sh
#
# Required env vars:
#   AIQ_REPO_DIR        — path to patched aiq repo (contains deploy/helm/deployment-k8s/)
#   AIQ_NAMESPACE       — K8s namespace (default: ns-aiq)
#   IMAGE_REGISTRY      — container registry
#   IMAGE_NAMESPACE     — image namespace
#   BACKEND_IMAGE_TAG   — backend image tag (default: fusion-cas)
#   FRONTEND_IMAGE_TAG  — frontend image tag (default: openshift-auth)
#   CLUSTER_DOMAIN      — OpenShift apps domain (used to build the Route hostname)
#
# All other config (FUSION_CAS_URL, store names, OAuth URLs, tokens) must already
# be in the aiq-credentials Kubernetes Secret — run 03-setup-secrets-and-token.sh first.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[04-helm]${NC} $*"; }
success() { echo -e "${GREEN}[04-helm]${NC} ✓ $*"; }
warn()    { echo -e "${YELLOW}[04-helm]${NC} ⚠ $*"; }
die()     { echo -e "${RED}[04-helm]${NC} ✗ $*" >&2; exit 1; }

: "${AIQ_REPO_DIR:?AIQ_REPO_DIR must be set}"
: "${IMAGE_REGISTRY:?IMAGE_REGISTRY must be set}"
: "${IMAGE_NAMESPACE:?IMAGE_NAMESPACE must be set}"
: "${CLUSTER_DOMAIN:?CLUSTER_DOMAIN must be set}"

AIQ_NAMESPACE="${AIQ_NAMESPACE:-ns-aiq}"
BACKEND_IMAGE_TAG="${BACKEND_IMAGE_TAG:-fusion-cas}"
FRONTEND_IMAGE_TAG="${FRONTEND_IMAGE_TAG:-openshift-auth}"
HELM_RELEASE="aiq"
AIQ_REPO_DIR="$(realpath "${AIQ_REPO_DIR}")"

HELM_DIR="${AIQ_REPO_DIR}/deploy/helm/deployment-k8s"
OVERRIDE_FILE="${HELM_DIR}/fusion-config-override.yaml"

[[ -d "${HELM_DIR}" ]] \
    || die "Helm chart directory not found: ${HELM_DIR} — check AIQ_REPO_DIR"
[[ -f "${OVERRIDE_FILE}" ]] \
    || die "fusion-config-override.yaml not found: ${OVERRIDE_FILE} — run 01-patch-aiq.sh first"

BACKEND_IMAGE="${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/aiq-agent:${BACKEND_IMAGE_TAG}"
FRONTEND_IMAGE="${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/aiq-frontend:${FRONTEND_IMAGE_TAG}"

info "Deploying Helm release '${HELM_RELEASE}' in namespace '${AIQ_NAMESPACE}'"
info "  Backend:  ${BACKEND_IMAGE}"
info "  Frontend: ${FRONTEND_IMAGE}"
info "  All config + secrets sourced from Kubernetes Secret aiq-credentials"

# All env vars (FUSION_CAS_URL, store names, OAuth URLs, tokens) are already in
# the aiq-credentials Kubernetes Secret created by 03-setup-secrets-and-token.sh.
# Only image coordinates and the route hostname are passed here — no secret values
# appear in Helm release state or helm history.
# The upstream chart has no Route template — do NOT pass route.host via --set.
helm upgrade --install "${HELM_RELEASE}" "${HELM_DIR}/" \
    -n "${AIQ_NAMESPACE}" \
    -f "${OVERRIDE_FILE}" \
    --set aiq.apps.backend.image.repository="${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/aiq-agent" \
    --set aiq.apps.backend.image.tag="${BACKEND_IMAGE_TAG}" \
    --set aiq.apps.backend.image.pullPolicy=Always \
    --set aiq.apps.frontend.image.repository="${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/aiq-frontend" \
    --set aiq.apps.frontend.image.tag="${FRONTEND_IMAGE_TAG}" \
    --set aiq.apps.frontend.image.pullPolicy=Always \
    --set 'aiq.apps.frontend.imagePullSecrets[0].name=ngc-secret' \
    --set 'aiq.apps.postgres.imagePullSecrets[0].name=ngc-secret'

success "Helm release '${HELM_RELEASE}' deployed"

# ── Wait for rollouts ─────────────────────────────────────────────────────────
info "Waiting for backend rollout..."
kubectl rollout status deployment/aiq-backend -n "${AIQ_NAMESPACE}" --timeout=300s
success "aiq-backend rollout complete"

info "Waiting for frontend rollout..."
kubectl rollout status deployment/aiq-frontend -n "${AIQ_NAMESPACE}" --timeout=300s
success "aiq-frontend rollout complete"

# ── Create OpenShift Route for the frontend UI ────────────────────────────────
# The upstream Helm chart has no Route template — route.enabled in values.yaml
# is silently ignored. We create the Route explicitly so it always exists.
FRONTEND_HOST="aiq-frontend-${AIQ_NAMESPACE}.${CLUSTER_DOMAIN}"
if command -v oc &>/dev/null; then
    info "Creating/updating OpenShift Route: aiq-frontend → ${FRONTEND_HOST}"
    oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: aiq-frontend
  namespace: ${AIQ_NAMESPACE}
spec:
  host: ${FRONTEND_HOST}
  to:
    kind: Service
    name: aiq-frontend
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF
    success "Route aiq-frontend created/updated: https://${FRONTEND_HOST}"
else
    warn "oc not found — skipping Route creation"
    warn "Create it manually:"
    warn "  oc apply -f - with host=${FRONTEND_HOST}, service=aiq-frontend, port=http, tls=edge"
fi

# ── Verify Route and Service port alignment ───────────────────────────────────
if command -v oc &>/dev/null; then
    info "Verifying Route and Service port alignment (blog Part 10)"
    oc get route aiq-frontend -n "${AIQ_NAMESPACE}" \
        -o jsonpath='Route: targetPort={.spec.port.targetPort} termination={.spec.tls.termination}{"\n"}' \
        2>/dev/null || warn "Route aiq-frontend not found"

    oc get svc aiq-frontend -n "${AIQ_NAMESPACE}" \
        -o jsonpath='{range .spec.ports[*]}{.name}={.port}->{.targetPort}{"\n"}{end}' \
        2>/dev/null || warn "Service aiq-frontend not found"
fi

echo ""
success "Deployment complete in namespace ${AIQ_NAMESPACE}"
echo -e "${CYAN}Next step:${NC} run ./scripts/05-verify-deployment.sh"
