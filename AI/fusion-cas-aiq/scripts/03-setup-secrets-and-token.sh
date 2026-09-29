#!/usr/bin/env bash
# 03-setup-secrets-and-token.sh — v2
# ──────────────────────────────────────────────────────────────────────────────
# Creates namespace, credentials secret, NGC pull secret, OAuthClient,
# OAuth CA ConfigMap, and the aiq-config-frag ConfigMap.
# Source of truth: blog Parts 4 and 8.
#
# Usage:
#   source aiq-fusion.env
#   ./scripts/03-setup-secrets-and-token.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[03-secrets]${NC} $*"; }
success() { echo -e "${GREEN}[03-secrets]${NC} ✓ $*"; }
warn()    { echo -e "${YELLOW}[03-secrets]${NC} ⚠ $*"; }
die()     { echo -e "${RED}[03-secrets]${NC} ✗ $*" >&2; exit 1; }

: "${NGC_API_KEY:?NGC_API_KEY must be set}"
: "${TAVILY_API_KEY:?TAVILY_API_KEY must be set}"
: "${AIQ_REPO_DIR:?AIQ_REPO_DIR must be set}"
: "${FUSION_CAS_URL:?FUSION_CAS_URL must be set}"
: "${FUSION_CAS_TOKEN:?FUSION_CAS_TOKEN must be set}"
: "${FUSION_VECTOR_STORE_1:?FUSION_VECTOR_STORE_1 must be set}"
: "${FUSION_VECTOR_STORE_2:?FUSION_VECTOR_STORE_2 must be set}"
: "${CLUSTER_DOMAIN:?CLUSTER_DOMAIN must be set}"

AIQ_NAMESPACE="${AIQ_NAMESPACE:-ns-aiq}"
OAUTH_CLIENT_ID="${OAUTH_CLIENT_ID:-aiq-nextauth}"
FUSION_VERIFY_SSL="${FUSION_VERIFY_SSL:-false}"
FUSION_VECTOR_STORE_1_LABEL="${FUSION_VECTOR_STORE_1_LABEL:-Store 1}"
FUSION_VECTOR_STORE_2_LABEL="${FUSION_VECTOR_STORE_2_LABEL:-Store 2}"
AIQ_REPO_DIR="$(realpath "${AIQ_REPO_DIR}")"

FRONTEND_URL="https://aiq-frontend-${AIQ_NAMESPACE}.${CLUSTER_DOMAIN}"
OAUTH_ISSUER="https://oauth-openshift.${CLUSTER_DOMAIN}"

# ── Step A: Create namespace ──────────────────────────────────────────────────
info "Creating namespace: ${AIQ_NAMESPACE}"
kubectl create namespace "${AIQ_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
success "Namespace ${AIQ_NAMESPACE} ready"

# ── Step B: Generate secrets if not pre-supplied ─────────────────────────────
if [[ -z "${NEXTAUTH_SECRET:-}" ]]; then
    info "Generating NEXTAUTH_SECRET"
    NEXTAUTH_SECRET="$(openssl rand -base64 32)"
    success "NEXTAUTH_SECRET generated"
fi

if [[ -z "${OAUTH_CLIENT_SECRET:-}" ]]; then
    info "Generating OAUTH_CLIENT_SECRET"
    OAUTH_CLIENT_SECRET="$(openssl rand -hex 32)"
    success "OAUTH_CLIENT_SECRET generated (save this for the OAuthClient manifest)"
    echo -e "  ${CYAN}OAUTH_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}${NC}"
fi
export OAUTH_CLIENT_SECRET NEXTAUTH_SECRET

# ── Step C: Fusion CAS bearer token ──────────────────────────────────────────
# FUSION_CAS_TOKEN is already guaranteed non-empty by the :? guard above.
info "Using pre-supplied FUSION_CAS_TOKEN"

# ── Step D: Create aiq-credentials secret ────────────────────────────────────
# All env vars — both secrets and non-secret config — go into this one K8s Secret.
# Nothing is passed via helm --set, so no values appear in Helm release state,
# pod describe output, or any committed file.

# DB credentials — the upstream values.yaml builds the full Postgres connection
# strings from $(DB_USER_NAME):$(DB_USER_PASSWORD) interpolation at pod startup,
# so only the raw credentials need to be stored in the secret.
DB_USER_NAME="${DB_USER_NAME:-aiq}"
DB_USER_PASSWORD="${DB_USER_PASSWORD:-aiq_dev}"

info "Creating/updating secret: aiq-credentials"
kubectl create secret generic aiq-credentials \
    -n "${AIQ_NAMESPACE}" \
    --from-literal=NVIDIA_API_KEY="${NGC_API_KEY}" \
    --from-literal=TAVILY_API_KEY="${TAVILY_API_KEY}" \
    --from-literal=DB_USER_NAME="${DB_USER_NAME}" \
    --from-literal=DB_USER_PASSWORD="${DB_USER_PASSWORD}" \
    --from-literal=FUSION_CAS_TOKEN="${FUSION_CAS_TOKEN}" \
    --from-literal=NEXTAUTH_SECRET="${NEXTAUTH_SECRET}" \
    --from-literal=OAUTH_CLIENT_SECRET="${OAUTH_CLIENT_SECRET}" \
    --from-literal=FUSION_CAS_URL="${FUSION_CAS_URL}" \
    --from-literal=FUSION_VERIFY_SSL="${FUSION_VERIFY_SSL}" \
    --from-literal=FUSION_VECTOR_STORE_1="${FUSION_VECTOR_STORE_1}" \
    --from-literal=FUSION_VECTOR_STORE_2="${FUSION_VECTOR_STORE_2}" \
    --from-literal=FUSION_VECTOR_STORE_1_LABEL="${FUSION_VECTOR_STORE_1_LABEL}" \
    --from-literal=FUSION_VECTOR_STORE_2_LABEL="${FUSION_VECTOR_STORE_2_LABEL}" \
    --from-literal=OAUTH_ISSUER="${OAUTH_ISSUER}" \
    --from-literal=OAUTH_CLIENT_ID="${OAUTH_CLIENT_ID}" \
    --from-literal=NEXTAUTH_URL="${FRONTEND_URL}" \
    --dry-run=client -o yaml | kubectl apply -f -
success "Secret aiq-credentials created/updated"

# ── Step E: Create NGC image pull secret ─────────────────────────────────────
info "Creating/updating image pull secret: ngc-secret"
kubectl create secret docker-registry ngc-secret \
    -n "${AIQ_NAMESPACE}" \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password="${NGC_API_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
success "Image pull secret ngc-secret created/updated"

# ── Step F: Create OpenShift OAuthClient ──────────────────────────────────────
if command -v oc &>/dev/null && [[ -n "${CLUSTER_DOMAIN}" ]]; then
    FRONTEND_URL="https://aiq-frontend-${AIQ_NAMESPACE}.${CLUSTER_DOMAIN}"
    info "Creating OAuthClient: ${OAUTH_CLIENT_ID}"
    info "  Redirect URI: ${FRONTEND_URL}/api/auth/callback/openshift"

    oc apply -f - <<EOF
apiVersion: oauth.openshift.io/v1
kind: OAuthClient
metadata:
  name: ${OAUTH_CLIENT_ID}
redirectURIs:
  - ${FRONTEND_URL}/api/auth/callback/openshift
secret: ${OAUTH_CLIENT_SECRET}
grantMethod: auto
EOF
    success "OAuthClient ${OAUTH_CLIENT_ID} created/updated"

    # Verify
    oc get oauthclient "${OAUTH_CLIENT_ID}" -o jsonpath='{.metadata.name}{"\n"}'

else
    warn "oc not found or CLUSTER_DOMAIN not set — skipping OAuthClient creation"
    warn "Create it manually using the manifest in the blog post (Part 4 Step 2)"
fi

# ── Step G: Trust OAuth CA certificate ───────────────────────────────────────
if command -v oc &>/dev/null && [[ -n "${CLUSTER_DOMAIN}" ]]; then
    OAUTH_HOST="oauth-openshift.${CLUSTER_DOMAIN}"
    info "Exporting OAuth CA certificate from ${OAUTH_HOST}"

    # Extract router CA certificate directly from OpenShift ingress operator
    # or fallback to openssl s_client
    if oc get secret router-ca -n openshift-ingress-operator -o jsonpath='{.data.tls\.crt}' &>/dev/null; then
        oc get secret router-ca -n openshift-ingress-operator \
            -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/oauth-ca.crt
        info "Exported CA from openshift-ingress-operator router-ca"
    elif oc get configmap default-ingress-cert -n openshift-config-managed -o jsonpath='{.data.ca-bundle\.crt}' &>/dev/null; then
        oc get configmap default-ingress-cert -n openshift-config-managed \
            -o jsonpath='{.data.ca-bundle\.crt}' > /tmp/oauth-ca.crt
        info "Exported CA from openshift-config-managed default-ingress-cert"
    else
        openssl s_client -showcerts \
            -connect "${OAUTH_HOST}:443" \
            -servername "${OAUTH_HOST}" \
            </dev/null 2>/dev/null |
            awk '/BEGIN CERTIFICATE/{capture=1} capture{print} /END CERTIFICATE/{capture=0}' \
            > /tmp/oauth-ca.crt
    fi

    if [[ -s /tmp/oauth-ca.crt ]]; then
        kubectl create configmap aiq-oauth-ca \
            -n "${AIQ_NAMESPACE}" \
            --from-file=ca.crt=/tmp/oauth-ca.crt \
            --dry-run=client -o yaml | kubectl apply -f -
        success "ConfigMap aiq-oauth-ca created/updated"
    else
        warn "Could not export OAuth CA certificate — create aiq-oauth-ca ConfigMap manually"
    fi
else
    warn "Skipping OAuth CA certificate export (oc not found or CLUSTER_DOMAIN not set)"
fi

# ── Step H: Create aiq-config-frag ConfigMap ─────────────────────────────────
CONFIG_FILE="${AIQ_REPO_DIR}/configs/config_web_frag.yml"
[[ -f "${CONFIG_FILE}" ]] \
    || die "config_web_frag.yml not found at ${CONFIG_FILE} — run 01-patch-aiq.sh first"

info "Creating/updating ConfigMap: aiq-config-frag"
kubectl create configmap aiq-config-frag \
    --from-file=config_web_frag.yml="${CONFIG_FILE}" \
    -n "${AIQ_NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
success "ConfigMap aiq-config-frag created/updated"

# Verify ConfigMap has the expected key
kubectl get configmap aiq-config-frag \
    -n "${AIQ_NAMESPACE}" \
    -o jsonpath='{.data}' | python3 -m json.tool 2>/dev/null | grep -q "config_web_frag.yml" \
    && success "ConfigMap key 'config_web_frag.yml' verified" \
    || warn "ConfigMap key verification failed — check manually"

echo ""
success "All secrets and ConfigMaps ready in namespace ${AIQ_NAMESPACE}"
echo -e "${CYAN}Next step:${NC} run ./scripts/04-deploy-helm.sh"
