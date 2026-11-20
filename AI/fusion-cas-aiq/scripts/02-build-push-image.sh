#!/usr/bin/env bash
# 02-build-push-image.sh — v2
# ──────────────────────────────────────────────────────────────────────────────
# Builds the patched AI-Q backend and frontend images.
# Recommended: OpenShift-native BuildConfig (Part 6 of the blog).
# Fallback:    local Docker/Podman build.
#
# Usage:
#   source aiq-fusion.env
#   ./scripts/02-build-push-image.sh
#
# Required env vars:
#   AIQ_REPO_DIR        — path to the patched aiq repo
#   IMAGE_REGISTRY      — container registry (e.g. image-registry.openshift-image-registry.svc:5000)
#   IMAGE_NAMESPACE     — image namespace / project
#   BACKEND_IMAGE_TAG   — tag for backend image (default: fusion-cas)
#   FRONTEND_IMAGE_TAG  — tag for frontend image (default: openshift-auth)
#   AIQ_NAMESPACE       — K8s namespace for BuildConfig
#
# For OpenShift BuildConfig (recommended):
#   AIQ_GIT_URI          — Git URI of the (forked) aiq repo with patches
#   AIQ_GIT_REF          — branch / tag / SHA
#   REGISTRY_PUSH_SECRET — name of the registry push secret in K8s
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[02-build]${NC} $*"; }
success() { echo -e "${GREEN}[02-build]${NC} ✓ $*"; }
warn()    { echo -e "${YELLOW}[02-build]${NC} ⚠ $*"; }
die()     { echo -e "${RED}[02-build]${NC} ✗ $*" >&2; exit 1; }

: "${AIQ_REPO_DIR:?AIQ_REPO_DIR must be set}"
: "${IMAGE_REGISTRY:?IMAGE_REGISTRY must be set}"
: "${IMAGE_NAMESPACE:?IMAGE_NAMESPACE must be set}"

AIQ_NAMESPACE="${AIQ_NAMESPACE:-ns-aiq}"
BACKEND_IMAGE_TAG="${BACKEND_IMAGE_TAG:-fusion-cas}"
FRONTEND_IMAGE_TAG="${FRONTEND_IMAGE_TAG:-openshift-auth}"
CONTAINER_TOOL="${CONTAINER_TOOL:-docker}"
AIQ_REPO_DIR="$(realpath "${AIQ_REPO_DIR}")"

BACKEND_IMAGE="${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/aiq-agent:${BACKEND_IMAGE_TAG}"
FRONTEND_IMAGE="${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/aiq-frontend:${FRONTEND_IMAGE_TAG}"

# ── Ensure namespace exists (required before any secret can be created) ───────
info "Ensuring namespace ${AIQ_NAMESPACE} exists"
kubectl create namespace "${AIQ_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
success "Namespace ${AIQ_NAMESPACE} ready"

# ── Copy pull-secret from openshift-config if using internal registry ─────────
# The OpenShift internal registry trusts the builder SA automatically.
# For external registries, copy the cluster pull-secret into the namespace.
if [[ "${IMAGE_REGISTRY}" != image-registry.openshift-image-registry* ]]; then
    info "External registry detected — copying pull-secret from openshift-config"
    if oc get secret pull-secret -n openshift-config &>/dev/null; then
        oc get secret pull-secret -n openshift-config \
            -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/pull-secret.json

        kubectl create secret generic "${REGISTRY_PUSH_SECRET:-registry-push-secret}" \
            -n "${AIQ_NAMESPACE}" \
            --from-file=.dockerconfigjson=/tmp/pull-secret.json \
            --type=kubernetes.io/dockerconfigjson \
            --dry-run=client -o yaml | kubectl apply -f -

        rm -f /tmp/pull-secret.json
        success "Push secret '${REGISTRY_PUSH_SECRET:-registry-push-secret}' created in ${AIQ_NAMESPACE}"
    else
        warn "pull-secret not found in openshift-config — BuildConfig may fail to push"
        warn "Create it manually: kubectl create secret docker-registry ${REGISTRY_PUSH_SECRET:-registry-push-secret} -n ${AIQ_NAMESPACE} ..."
    fi
else
    info "Internal registry — no push secret needed (builder SA has access automatically)"
fi

# ── Decide: OpenShift BuildConfig (recommended) or local build (fallback) ────
if command -v oc &>/dev/null && [[ -n "${AIQ_GIT_URI:-}" ]]; then
    info "Using OpenShift BuildConfig (recommended — Part 6)"
    info "  Backend:  ${BACKEND_IMAGE}"
    info "  Frontend: ${FRONTEND_IMAGE}"

    PUSH_SECRET="${REGISTRY_PUSH_SECRET:-registry-push-secret}"
    GIT_URI="${AIQ_GIT_URI}"
    GIT_REF="${AIQ_GIT_REF:-main}"

    # ── Backend BuildConfig ───────────────────────────────────────────────────
    info "Creating/updating backend BuildConfig: aiq-agent"
    oc apply -f - <<EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: aiq-agent
  namespace: ${AIQ_NAMESPACE}
spec:
  source:
    type: Git
    git:
      uri: ${GIT_URI}
      ref: ${GIT_REF}
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: deploy/Dockerfile
  output:
    to:
      kind: DockerImage
      name: ${BACKEND_IMAGE}
    pushSecret:
      name: ${PUSH_SECRET}
EOF

    # ── Frontend BuildConfig ──────────────────────────────────────────────────
    info "Creating/updating frontend BuildConfig: aiq-frontend"
    oc apply -f - <<EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: aiq-frontend
  namespace: ${AIQ_NAMESPACE}
spec:
  source:
    type: Git
    git:
      uri: ${GIT_URI}
      ref: ${GIT_REF}
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: frontends/ui/deploy/Dockerfile
  output:
    to:
      kind: DockerImage
      name: ${FRONTEND_IMAGE}
    pushSecret:
      name: ${PUSH_SECRET}
EOF

    # ── Start builds ─────────────────────────────────────────────────────────
    info "Starting backend build..."
    oc start-build aiq-agent -n "${AIQ_NAMESPACE}" --follow

    info "Starting frontend build..."
    oc start-build aiq-frontend -n "${AIQ_NAMESPACE}" --follow

    # ── Verify ───────────────────────────────────────────────────────────────
    info "Verifying builds completed"
    oc get build -n "${AIQ_NAMESPACE}" -l buildconfig=aiq-agent
    oc get build -n "${AIQ_NAMESPACE}" -l buildconfig=aiq-frontend

    success "OpenShift builds complete"
    success "  Backend:  ${BACKEND_IMAGE}"
    success "  Frontend: ${FRONTEND_IMAGE}"

else
    # ── Local build fallback ──────────────────────────────────────────────────
    warn "AIQ_GIT_URI not set or oc not found — falling back to local ${CONTAINER_TOOL} build"
    info "  Note: commit your patches to a branch and set AIQ_GIT_URI to use OpenShift BuildConfig"

    [[ -d "${AIQ_REPO_DIR}" ]] || die "AIQ_REPO_DIR=${AIQ_REPO_DIR} does not exist"
    [[ -f "${AIQ_REPO_DIR}/uv.lock" ]] \
        || die "uv.lock not found — run 01-patch-aiq.sh first"
    [[ -f "${AIQ_REPO_DIR}/sources/knowledge_layer/src/fusion_cas/adapter.py" ]] \
        || die "fusion_cas not found — run 01-patch-aiq.sh first"
    command -v "${CONTAINER_TOOL}" &>/dev/null \
        || die "${CONTAINER_TOOL} not found in PATH"

    cd "${AIQ_REPO_DIR}"

    info "Building backend image: ${BACKEND_IMAGE}"
    "${CONTAINER_TOOL}" build \
        --target release \
        -f deploy/Dockerfile \
        -t "${BACKEND_IMAGE}" .
    "${CONTAINER_TOOL}" push "${BACKEND_IMAGE}"
    success "Backend image pushed: ${BACKEND_IMAGE}"

    info "Building frontend image: ${FRONTEND_IMAGE}"
    "${CONTAINER_TOOL}" build \
        -f frontends/ui/deploy/Dockerfile \
        -t "${FRONTEND_IMAGE}" frontends/ui
    "${CONTAINER_TOOL}" push "${FRONTEND_IMAGE}"
    success "Frontend image pushed: ${FRONTEND_IMAGE}"
fi

echo ""
echo -e "${CYAN}Next step:${NC} run ./scripts/03-setup-secrets-and-token.sh"
