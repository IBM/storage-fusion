#!/usr/bin/env bash
# =============================================================================
# 02-register-proxy-cluster.sh
#
# Register a PROXY-ONLY Fusion cluster into IBM Fusion Developer Hub
# via the RHDH UI catalog import. Implements Phase 8 of RUNBOOK.md end-to-end.
#
# A proxy-only cluster has NO direct Kubernetes plugin access — no SA token,
# no kubernetes annotations. Endpoints are accessed via RHDH proxy only.
# Use this for clusters you can reach through the network but cannot install
# service accounts on (e.g. clusters owned by another team).
#
# Usage:
#   ./02-register-proxy-cluster.sh [--config <file>]
#
# TOKEN AUTO-DETECTION
#   RHDH_CLUSTER_API_TOKEN is pulled automatically from the active `oc` session
#   via `oc whoami --show-token`. The RHDH cluster API URL is also pulled from
#   `oc whoami --show-server`. You only need to set these explicitly when:
#     - You are NOT already logged in to the RHDH cluster, OR
#     - You want to override the active session (e.g. CI pipelines).
#
# Required environment variables:
#   GITHUB_TOKEN             - GitHub PAT (repo read) for github.ibm.com
#                              (cannot be auto-detected)
#
# Optional — auto-detected if already logged in:
#   RHDH_CLUSTER_API_TOKEN   - oc login token for the cluster running RHDH
#   RHDH_CLUSTER_API_URL     - API URL for the RHDH cluster
#                              (default: pulled from current oc context)
#
# Configurable variables (defaults shown):
#   CLUSTER_ID               - Short cluster id, e.g. my-cluster-01
#   CLUSTER_DOMAIN           - Full domain, e.g. my-cluster-01.example.com
#   DCS_VERSION              - DCS service version, e.g. 2.5.3
#   CAS_VERSION              - CAS service version, e.g. 1.1.5
#   DCS_NAMESPACE            - DCS namespace (default: ibm-data-cataloging)
#   CAS_NAMESPACE            - CAS namespace (default: ibm-cas)
#   RHDH_NAMESPACE           - RHDH namespace (default: fusion-developer-hub)
#   STORAGE_CLASS            - RWX storage class (default: "" — uses cluster default)
#   GIT_REPO                 - Git repository URL
#   GIT_BRANCH               - Git branch
#   GIT_ORG                  - GitHub org/project path, e.g. ProjectAbell/Fusion-AI
#   REPO_ROOT                - Absolute path to the repo root (auto-detected)
#   ROLLOUT_TIMEOUT          - Seconds to wait for pod rollout (default: 300)
#   DRY_RUN                  - Set to "true" to print commands without running
#   SKIP_GIT_PUSH            - Set to "true" to skip git commit/push
#
# Example A — already logged in to RHDH cluster:
#   # oc login <rhdh-cluster> already done in this shell
#   export GITHUB_TOKEN="ghp_..."
#   export CLUSTER_ID="my-cluster-01"
#   export CLUSTER_DOMAIN="my-cluster-01.example.com"
#   ./02-register-proxy-cluster.sh
#
# Example B — explicit token (CI / non-interactive):
#   export RHDH_CLUSTER_API_TOKEN="sha256~..."
#   export GITHUB_TOKEN="ghp_..."
#   export CLUSTER_ID="my-cluster-01"
#   export CLUSTER_DOMAIN="my-cluster-01.example.com"
#   ./02-register-proxy-cluster.sh
# =============================================================================

set -euo pipefail

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
die()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${RESET}"; }

# ── Optional config file ───────────────────────────────────────────────────────
if [[ "${1:-}" == "--config" && -n "${2:-}" ]]; then
  [[ -f "$2" ]] || die "Config file not found: $2"
  # shellcheck disable=SC1090
  source "$2"
  info "Loaded config: $2"
fi

# ── Defaults ───────────────────────────────────────────────────────────────────
# CLUSTER_ID and CLUSTER_DOMAIN have no built-in defaults — they are
# environment-specific and must always be supplied explicitly.
CLUSTER_ID="${CLUSTER_ID:-}"
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-}"
DCS_VERSION="${DCS_VERSION:-2.5.3}"
CAS_VERSION="${CAS_VERSION:-1.1.5}"
DCS_NAMESPACE="${DCS_NAMESPACE:-ibm-data-cataloging}"
CAS_NAMESPACE="${CAS_NAMESPACE:-ibm-cas}"
RHDH_NAMESPACE="${RHDH_NAMESPACE:-fusion-developer-hub}"
# Leave STORAGE_CLASS empty to use the cluster's default StorageClass.
# Override only if the cluster default does not support ReadWriteMany (RWX).
# Example: export STORAGE_CLASS="ocs-storagecluster-cephfs"
STORAGE_CLASS="${STORAGE_CLASS:-}"
GIT_REPO="${GIT_REPO:-https://github.ibm.com/ProjectAbell/Fusion-AI}"
GIT_BRANCH="${GIT_BRANCH:-cas-dcs-rhdh}"
GIT_ORG="${GIT_ORG:-ProjectAbell/Fusion-AI}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-300}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_GIT_PUSH="${SKIP_GIT_PUSH:-false}"

# Validate required variables — must be set before the script can continue.
[[ -z "$CLUSTER_ID" ]]     && die "CLUSTER_ID is required. Example: export CLUSTER_ID=my-cluster-01"
[[ -z "$CLUSTER_DOMAIN" ]] && die "CLUSTER_DOMAIN is required. Example: export CLUSTER_DOMAIN=my-cluster-01.example.com"

# RHDH API URL: prefer explicit override, then current oc context, then cluster domain
_oc_server=$(oc whoami --show-server 2>/dev/null || echo "")
RHDH_API_URL="${RHDH_CLUSTER_API_URL:-${_oc_server:-https://api.${CLUSTER_DOMAIN}:6443}}"

# Detect repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../../../.." && pwd)}"

CLUSTER_DIR="${REPO_ROOT}/quickstarts/fusion-developerhub/fusion-ai-discovery/clusters/${CLUSTER_ID}"
TEMPLATE_DIR="${REPO_ROOT}/quickstarts/fusion-developerhub/fusion-ai-discovery/clusters/cluster-template"
CATALOG_FILE="${CLUSTER_DIR}/catalog-info.yaml"
VALUES_FILE="${REPO_ROOT}/quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml"

# Blob URL for UI import (Backstage converts this to raw internally)
CATALOG_BLOB_URL="${GIT_REPO}/blob/${GIT_BRANCH}/quickstarts/fusion-developerhub/fusion-ai-discovery/clusters/${CLUSTER_ID}/catalog-info.yaml"
GHE_RAW_BASE="https://raw.$(echo "$GIT_REPO" | sed 's|https://||' | cut -d/ -f1)"

# ── Dry-run wrapper ────────────────────────────────────────────────────────────
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

# ── Prerequisite checks ────────────────────────────────────────────────────────
# ── Token auto-detection ───────────────────────────────────────────────────────
# Pull a token from an active oc session for a given API server.
# Usage: resolve_oc_token <api-url> <var-name>
# Sets the variable named <var-name> if not already set and the session is live.
resolve_oc_token() {
  local api_url="$1"
  local var_name="$2"

  # Already set — nothing to do
  [[ -n "${!var_name:-}" ]] && return 0

  # Try to pull from the current context if the server matches
  local current_server
  current_server=$(oc whoami --show-server 2>/dev/null || echo "")

  if [[ "$current_server" == "$api_url" ]]; then
    local token
    token=$(oc whoami --show-token 2>/dev/null || echo "")
    if [[ -n "$token" ]]; then
      eval "${var_name}=\"${token}\""
      success "Auto-detected $var_name from active oc session ($api_url)"
      return 0
    fi
  fi

  # Not the current context — scan all contexts for a matching server
  local ctx
  ctx=$(oc config get-contexts --no-headers 2>/dev/null \
    | awk -v server="$api_url" '$0 ~ server {print $2; exit}')
  if [[ -n "$ctx" ]]; then
    local token
    token=$(oc --context="$ctx" whoami --show-token 2>/dev/null || echo "")
    if [[ -n "$token" ]]; then
      eval "${var_name}=\"${token}\""
      success "Auto-detected $var_name from oc context '$ctx' ($api_url)"
      return 0
    fi
  fi

  warn "Could not auto-detect $var_name for $api_url — set it explicitly if login fails"
  return 0
}

check_prerequisites() {
  step "Checking prerequisites"

  for cmd in oc git python3 curl base64 sed; do
    command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
  done
  success "All required commands present"

  # Auto-detect RHDH token from active oc session
  resolve_oc_token "$RHDH_API_URL" "RHDH_CLUSTER_API_TOKEN"

  [[ -n "${RHDH_CLUSTER_API_TOKEN:-}" ]] || \
    die "RHDH_CLUSTER_API_TOKEN could not be resolved.\n  Either: export RHDH_CLUSTER_API_TOKEN=\$(oc whoami --show-token)\n  Or:      oc login --token=<token> --server=${RHDH_API_URL} first."
  [[ -n "${GITHUB_TOKEN:-}" ]] || \
    die "GITHUB_TOKEN is required (GitHub PAT with repo read scope — cannot be auto-detected)"

  [[ -d "$TEMPLATE_DIR" ]] || \
    die "cluster-template not found: $TEMPLATE_DIR"
  [[ -f "$VALUES_FILE" ]] || \
    die "values.yaml not found: $VALUES_FILE"

  success "Prerequisite checks passed"
  echo
  info "  Cluster ID    : $CLUSTER_ID  (proxy-only)"
  info "  Cluster domain: $CLUSTER_DOMAIN"
  info "  RHDH API      : $RHDH_API_URL"
  info "  DCS version   : $DCS_VERSION  (ns: $DCS_NAMESPACE)"
  info "  CAS version   : $CAS_VERSION  (ns: $CAS_NAMESPACE)"
  info "  RHDH namespace: $RHDH_NAMESPACE"
  info "  Storage class : $STORAGE_CLASS"
  info "  Git repo      : $GIT_REPO @ $GIT_BRANCH"
  info "  Catalog file  : $CATALOG_FILE"
  info "  Import URL    : $CATALOG_BLOB_URL"
}

# ── Phase 8.1 — Create catalog-info.yaml ──────────────────────────────────────
phase8_1_create_catalog_file() {
  step "Phase 8.1 — Create clusters/${CLUSTER_ID}/catalog-info.yaml"

  if [[ -f "$CATALOG_FILE" ]]; then
    success "catalog-info.yaml already exists at $CATALOG_FILE — skipping generation"
    return
  fi

  info "Copying template to $CLUSTER_DIR"
  run mkdir -p "$CLUSTER_DIR"
  run cp -r "${TEMPLATE_DIR}/." "$CLUSTER_DIR/"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would generate catalog-info.yaml with cluster-id=$CLUSTER_ID"
    return
  fi

  info "Substituting all <cluster-id> placeholders"

  # Build the full catalog-info.yaml by substituting every placeholder in the
  # template. We also strip the Kubernetes plugin annotation blocks (proxy-only).
  python3 - <<PYEOF
import sys, re

with open("${CATALOG_FILE}") as f:
    content = f.read()

cluster_id     = "${CLUSTER_ID}"
cluster_domain = "${CLUSTER_DOMAIN}"
dcs_version    = "${DCS_VERSION}"
cas_version    = "${CAS_VERSION}"
dcs_namespace  = "${DCS_NAMESPACE}"
cas_namespace  = "${CAS_NAMESPACE}"
git_repo       = "${GIT_REPO}"
git_branch     = "${GIT_BRANCH}"

# Replace all <cluster-id> placeholders
content = content.replace("<cluster-id>", cluster_id)

# Replace example.com domain pattern with the real domain
content = content.replace(
    f"apps.{cluster_id}.fusion.example.com",
    f"apps.{cluster_domain}"
)

# Set cluster type to proxy-only
content = re.sub(
    r'fusion\.ibm\.com/cluster-type:\s*"<self-hosted\|proxy-only>"',
    'fusion.ibm.com/cluster-type: "proxy-only"',
    content
)

# Set DCS service version
content = re.sub(
    r'(fusion-dcs-[^\n]*\n(?:[^\n]*\n)*?.*fusion\.ibm\.com/service-version:)\s*"[^"]*"',
    lambda m: m.group(0).replace(m.group(0).split('"')[-2], dcs_version),
    content,
    count=1
)

# Set CAS service version
content = re.sub(
    r'(fusion-cas-[^\n]*\n(?:[^\n]*\n)*?.*fusion\.ibm\.com/service-version:)\s*"[^"]*"',
    lambda m: m.group(0).replace(m.group(0).split('"')[-2], cas_version),
    content,
    count=1
)

# Remove the Kubernetes plugin annotation block for proxy-only clusters
# The block starts with the comment and ends before spec:
content = re.sub(
    r'[ \t]+# ── Kubernetes plugin — SELF-HOSTED ONLY.*?backstage\.io/kubernetes-label-selector:[^\n]+\n',
    '',
    content,
    flags=re.DOTALL
)

# Update backstage.io/source-location to the real blob URL
real_url = (f"url:{git_repo}/blob/{git_branch}"
            f"/quickstarts/fusion-developerhub/fusion-ai-discovery"
            f"/clusters/{cluster_id}/catalog-info.yaml")
content = re.sub(
    r'backstage\.io/source-location:\s*"url:[^"]*"',
    f'backstage.io/source-location: "{real_url}"',
    content
)

# Update techdocs-ref to the real URL
techdocs_dcs = (f"url:{git_repo}/blob/{git_branch}"
                f"/quickstarts/fusion-developerhub/fusion-ai-discovery/techdocs/dcs")
techdocs_cas = (f"url:{git_repo}/blob/{git_branch}"
                f"/quickstarts/fusion-developerhub/fusion-ai-discovery/techdocs/cas")
content = re.sub(
    r'(backstage\.io/techdocs-ref:.*?techdocs/dcs["\']?)',
    f'backstage.io/techdocs-ref: "{techdocs_dcs}"',
    content
)
content = re.sub(
    r'(backstage\.io/techdocs-ref:.*?techdocs/cas["\']?)',
    f'backstage.io/techdocs-ref: "{techdocs_cas}"',
    content
)

# Update DCS OpenAPI version field
content = content.replace('"2.5.x"', f'"{dcs_version}"', 2)
# Update CAS OpenAPI version field
content = content.replace('"2.13.x"', f'"{cas_version}"', 2)

# Update DCS service-version annotation (value was a template placeholder)
content = re.sub(
    r'(name: fusion-dcs-.*?\n.*?fusion\.ibm\.com/service-version:)\s*"[^"]*"',
    lambda m: m.group(1) + f' "{dcs_version}"',
    content,
    flags=re.DOTALL,
    count=1
)
# Update CAS service-version annotation
content = re.sub(
    r'(name: fusion-cas-.*?\n.*?fusion\.ibm\.com/service-version:)\s*"[^"]*"',
    lambda m: m.group(1) + f' "{cas_version}"',
    content,
    flags=re.DOTALL,
    count=1
)

with open("${CATALOG_FILE}", "w") as f:
    f.write(content)

print("catalog-info.yaml written successfully")
PYEOF

  success "catalog-info.yaml generated: $CATALOG_FILE"

  # Basic YAML validation
  python3 -c "
import yaml, sys
with open('${CATALOG_FILE}') as f:
    docs = list(yaml.safe_load_all(f))
print(f'YAML valid — {len(docs)} documents:')
for d in docs:
    if d:
        print(f'  {d[\"kind\"]:12s}  {d[\"metadata\"][\"name\"]}')
" || die "Generated catalog-info.yaml failed YAML validation"
}

# ── Phase 8.2 — Update prod values.yaml ───────────────────────────────────────
phase8_2_update_values() {
  step "Phase 8.2 — Update environments/prod/values.yaml"

  # Check if cluster already in values.yaml
  if grep -q "name: ${CLUSTER_ID}" "$VALUES_FILE"; then
    success "Cluster '$CLUSTER_ID' already present in values.yaml — skipping"
    return
  fi

  info "Inserting $CLUSTER_ID (proxy-only) cluster entry into values.yaml"

  python3 - <<PYEOF
import re, sys

with open("${VALUES_FILE}") as f:
    content = f.read()

new_entry = """      - name: ${CLUSTER_ID}
        ocpApiUrl: https://api.${CLUSTER_DOMAIN}:6443
        clusterType: proxy-only
        services:
          dcs:
            enabled: true
            version: "${DCS_VERSION}"
            namespace: ${DCS_NAMESPACE}
          cas:
            enabled: true
            version: "${CAS_VERSION}"
            namespace: ${CAS_NAMESPACE}
"""

# Strategy: find the clusters: key and insert AFTER the last active entry
# (before the first comment-only line that follows the list).
# Works regardless of which sentinel comment is present, or if there are
# already entries (insert after last "-" item), or if clusters: [] (empty).
#
# Step 1 — normalise "clusters: []" inline → block key
content = re.sub(
    r'^([ \t]+clusters:)[ \t]*\[\][ \t]*$',
    r'\1',
    content,
    flags=re.MULTILINE
)

# Step 2 — find the clusters: key and its indented block end
# Insert new_entry just before the first line that is either:
#   a) a comment at the same indent level as "clusters:" (4 spaces)
#   b) a non-list, non-comment key at same or lower indent (sibling key)
#   c) end of file
clusters_re = re.compile(
    r'^([ \t]+clusters:\s*\n'           # the clusters: line
    r'(?:(?!^[ \t]{0,4}[a-z#]).*\n)*)', # everything that belongs to it
    re.MULTILINE
)
m = clusters_re.search(content)
if m:
    insert_pos = m.end()
    content = content[:insert_pos] + new_entry + content[insert_pos:]
else:
    sys.exit("Could not locate clusters: block in values.yaml — manual edit required")

import yaml
try:
    yaml.safe_load(content)
except yaml.YAMLError as e:
    sys.exit(f"YAML validation failed after insertion: {e}")

with open("${VALUES_FILE}", "w") as f:
    f.write(content)

print("values.yaml updated and validated")
PYEOF

  success "Cluster $CLUSTER_ID added to values.yaml"

  # Verify
  grep -A8 "name: ${CLUSTER_ID}" "$VALUES_FILE" | head -10
}

# ── Phase 8.3 — Commit and push ───────────────────────────────────────────────
phase8_3_git_push() {
  step "Phase 8.3 — Commit and push"

  if [[ "$SKIP_GIT_PUSH" == "true" ]]; then
    warn "SKIP_GIT_PUSH=true — skipping git commit/push"
    return
  fi

  cd "$REPO_ROOT"

  # Compute repo-relative paths (macOS realpath does not support --relative-to)
  local rel_catalog rel_values
  rel_catalog=$(python3 -c "import os; print(os.path.relpath('${CATALOG_FILE}', '${REPO_ROOT}'))")
  rel_values=$(python3 -c  "import os; print(os.path.relpath('${VALUES_FILE}',  '${REPO_ROOT}'))")

  local changed=()
  # Check modified tracked files
  git diff --name-only | grep -qF "$rel_catalog" && changed+=("$rel_catalog")
  # Check untracked new files (new cluster directory)
  git ls-files --others --exclude-standard | grep -qF "$rel_catalog" && {
    # Avoid duplicate — use ${changed[@]+"${changed[@]}"} (safe with set -u)
    [[ " ${changed[@]+"${changed[@]}"} " != *" $rel_catalog "* ]] && changed+=("$rel_catalog")
  }
  git diff --name-only | grep -qF "$rel_values" && changed+=("$rel_values")

  if [[ ${#changed[@]} -eq 0 ]]; then
    info "No file changes detected — nothing to commit"
    return
  fi

  info "Staging files: ${changed[@]+"${changed[@]}"}"
  run git add "$rel_catalog" "$rel_values"

  run git commit -m "feat(${CLUSTER_ID}): register proxy-only cluster

- Add clusters/${CLUSTER_ID}/catalog-info.yaml (proxy-only)
  System + DCS Component/API (v${DCS_VERSION}) + CAS Component/API (v${CAS_VERSION})
  Domain: ${CLUSTER_DOMAIN}

- Update environments/prod/values.yaml
  + clusters[name=${CLUSTER_ID}]: proxy-only, DCS ${DCS_VERSION}, CAS ${CAS_VERSION}"

  run git push origin "$GIT_BRANCH" || die "git push failed"
  success "Changes pushed to $GIT_BRANCH"
}

# ── Phase 8.4 — Verify GITHUB_TOKEN wiring ────────────────────────────────────
phase8_4_verify_github_token() {
  step "Phase 8.4 — Verify GITHUB_TOKEN wiring"

  info "Logging in to RHDH cluster: $RHDH_API_URL"
  run oc login --token="$RHDH_CLUSTER_API_TOKEN" \
               --server="$RHDH_API_URL" \
               --insecure-skip-tls-verify=true 2>&1 | grep -v "^$" || \
    die "oc login failed for RHDH cluster"
  success "Logged in to RHDH cluster"

  # Check the Secret exists
  if oc get secret github-auth-secret -n "$RHDH_NAMESPACE" &>/dev/null; then
    success "github-auth-secret exists in $RHDH_NAMESPACE"
  else
    warn "github-auth-secret NOT found — creating it now"
    [[ -n "${GITHUB_TOKEN:-}" ]] || die "GITHUB_TOKEN env var is required to create the secret"
    run oc create secret generic github-auth-secret \
      "--from-literal=GITHUB_TOKEN=${GITHUB_TOKEN}" \
      -n "$RHDH_NAMESPACE" || die "Failed to create github-auth-secret"
    success "github-auth-secret created"
  fi

  # Verify github-auth-secret is not commented out in extraEnvs in values.yaml
  if grep -E '^\s+-\s+name:\s+github-auth-secret' "$VALUES_FILE" &>/dev/null; then
    success "github-auth-secret is active in extraEnvs"
  else
    warn "github-auth-secret is COMMENTED OUT in $VALUES_FILE"
    info "Uncomment it automatically..."
    if [[ "$DRY_RUN" != "true" ]]; then
      # Use portable in-place sed (BSD macOS requires -i '' with a space, GNU allows -i'')
      if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' \
          's|^\([[:space:]]*\)# *- name: github-auth-secret.*|\1- name: github-auth-secret      # GITHUB_TOKEN|' \
          "$VALUES_FILE"
      else
        sed -i \
          's|^\([[:space:]]*\)# *- name: github-auth-secret.*|\1- name: github-auth-secret      # GITHUB_TOKEN|' \
          "$VALUES_FILE"
      fi
      if grep -E '^\s+-\s+name:\s+github-auth-secret' "$VALUES_FILE" &>/dev/null; then
        success "github-auth-secret uncommented in values.yaml"
        # Re-stage for git
        local rel_v
        rel_v=$(python3 -c "import os; print(os.path.relpath('${VALUES_FILE}', '${REPO_ROOT}'))")
        cd "$REPO_ROOT" && git add "$rel_v" 2>/dev/null || true
      else
        warn "Auto-uncomment did not match — edit values.yaml manually"
        warn "Add:  - name: github-auth-secret  under developerHub.extraEnvs.secrets"
      fi
    fi
  fi

  # Verify the PAT reaches github.ibm.com API
  GHE_HOST=$(echo "$GIT_REPO" | sed 's|https://||' | cut -d/ -f1)
  info "Testing GitHub token against https://${GHE_HOST}/api/v3/repos/${GIT_ORG}"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://${GHE_HOST}/api/v3/repos/${GIT_ORG}" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    success "GitHub token is valid (HTTP $HTTP_CODE)"
  else
    warn "GitHub token check returned HTTP $HTTP_CODE — imports may fail"
    warn "Verify the PAT at https://${GHE_HOST}/settings/tokens (needs repo read scope)"
  fi

  # Check GITHUB_TOKEN is in the running pod
  local pod
  pod=$(oc get pod -n "$RHDH_NAMESPACE" 2>/dev/null \
    | grep "backstage-developer-hub.*Running" | head -1 | awk '{print $1}')

  if [[ -z "$pod" ]]; then
    warn "No Running backstage pod found — skipping pod env check"
    return
  fi

  local count
  count=$(oc exec -n "$RHDH_NAMESPACE" "$pod" -- env 2>/dev/null \
    | grep -c GITHUB_TOKEN || true)
  if [[ "$count" -ge 1 ]]; then
    success "GITHUB_TOKEN is present in pod $pod"
  else
    warn "GITHUB_TOKEN NOT in pod $pod — restarting to pick up the secret"
    run oc rollout restart deployment/backstage-developer-hub -n "$RHDH_NAMESPACE"
    run oc rollout status deployment/backstage-developer-hub \
      -n "$RHDH_NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s" || \
      warn "Rollout did not complete within ${ROLLOUT_TIMEOUT}s"
    # Re-check
    pod=$(oc get pod -n "$RHDH_NAMESPACE" 2>/dev/null \
      | grep "backstage-developer-hub.*Running" | head -1 | awk '{print $1}')
    count=$(oc exec -n "$RHDH_NAMESPACE" "$pod" -- env 2>/dev/null \
      | grep -c GITHUB_TOKEN || true)
    [[ "$count" -ge 1 ]] || die "GITHUB_TOKEN still not in pod after restart"
    success "GITHUB_TOKEN confirmed in pod after restart"
  fi
}

# ── Phase 8.5 — Verify and fix rawBaseUrl ────────────────────────────────────
phase8_5_verify_raw_base_url() {
  step "Phase 8.5 — Verify rawBaseUrl in app-config-fusion-services"

  local raw_url
  raw_url=$(oc get cm app-config-fusion-services -n "$RHDH_NAMESPACE" \
    -o jsonpath='{.data.app-config-fusion-services\.yaml}' 2>/dev/null \
    | grep rawBaseUrl | awk '{print $2}' | head -1)

  info "Found rawBaseUrl: '$raw_url'"
  info "Expected       : '$GHE_RAW_BASE'"

  if [[ "$raw_url" == "$GHE_RAW_BASE" ]]; then
    success "rawBaseUrl is correct"
    return
  fi

  warn "rawBaseUrl is wrong — patching ConfigMap in-place"
  warn "  was: $raw_url"
  warn "  fix: $GHE_RAW_BASE"

  # Extract, fix, re-patch
  oc get cm app-config-fusion-services -n "$RHDH_NAMESPACE" \
    -o jsonpath='{.data.app-config-fusion-services\.yaml}' \
    | sed "s|rawBaseUrl: ${raw_url}|rawBaseUrl: ${GHE_RAW_BASE}|g" \
    > /tmp/app-config-patched.yaml

  # Verify the fix was applied
  if ! grep -q "rawBaseUrl: ${GHE_RAW_BASE}" /tmp/app-config-patched.yaml; then
    die "sed substitution failed — check rawBaseUrl format in the ConfigMap"
  fi

  run oc patch cm app-config-fusion-services -n "$RHDH_NAMESPACE" \
    --type=merge \
    -p "{\"data\":{\"app-config-fusion-services.yaml\":$(
      python3 -c 'import sys,json; print(json.dumps(open("/tmp/app-config-patched.yaml").read()))'
    )}}" || die "Failed to patch rawBaseUrl in ConfigMap"
  success "rawBaseUrl patched in ConfigMap"

  info "Restarting backstage-developer-hub to reload config..."
  run oc rollout restart deployment/backstage-developer-hub -n "$RHDH_NAMESPACE"
  run oc rollout status deployment/backstage-developer-hub \
    -n "$RHDH_NAMESPACE" --timeout="${ROLLOUT_TIMEOUT}s" || \
    warn "Rollout did not complete within ${ROLLOUT_TIMEOUT}s"
  success "Pod restarted with corrected rawBaseUrl"
}

# ── Phase 8.6 — Print UI import instructions ─────────────────────────────────
phase8_6_ui_import_instructions() {
  step "Phase 8.6 — RHDH UI Catalog Import"

  # Get RHDH URL
  RHDH_HOST=$(oc get route backstage-developer-hub -n "$RHDH_NAMESPACE" \
    -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  RHDH_URL_VAL="${RHDH_HOST:+https://${RHDH_HOST}}"
  RHDH_URL_VAL="${RHDH_URL_VAL:-<run: oc get route backstage-developer-hub -n $RHDH_NAMESPACE>}"

  echo
  echo -e "${BOLD}${YELLOW}  ┌─────────────────────────────────────────────────────────────────┐"
  echo    "  │  MANUAL STEP REQUIRED — Complete the UI import in your browser  │"
  echo    "  └─────────────────────────────────────────────────────────────────┘${RESET}"
  echo
  echo -e "  ${BOLD}1.${RESET} Open RHDH in your browser:"
  echo -e "     ${CYAN}${RHDH_URL_VAL}${RESET}"
  echo
  echo -e "  ${BOLD}2.${RESET} Navigate to:"
  echo -e "     ${BOLD}Catalog${RESET} → ${BOLD}+ Register Existing Component${RESET} (top-right button)"
  echo
  echo -e "  ${BOLD}3.${RESET} Select: ${BOLD}Link to an existing entity file${RESET}"
  echo
  echo -e "  ${BOLD}4.${RESET} Paste this URL into the input field:"
  echo
  echo -e "     ${GREEN}${CATALOG_BLOB_URL}${RESET}"
  echo
  echo -e "  ${BOLD}5.${RESET} Click ${BOLD}Analyze${RESET}"
  echo
  echo -e "  ${BOLD}6.${RESET} The wizard should preview ${BOLD}5 entities${RESET}:"
  echo    "     ┌────────────┬─────────────────────────────────────────┐"
  echo    "     │ Kind       │ Name                                    │"
  echo    "     ├────────────┼─────────────────────────────────────────┤"
  printf  "     │ System     │ %-39s │\n" "fusion-${CLUSTER_ID}"
  printf  "     │ Component  │ %-39s │\n" "fusion-dcs-${CLUSTER_ID}"
  printf  "     │ API        │ %-39s │\n" "fusion-dcs-mcp-api-${CLUSTER_ID}"
  printf  "     │ Component  │ %-39s │\n" "fusion-cas-${CLUSTER_ID}"
  printf  "     │ API        │ %-39s │\n" "fusion-cas-mcp-api-${CLUSTER_ID}"
  echo    "     └────────────┴─────────────────────────────────────────┘"
  echo
  echo -e "  ${BOLD}7.${RESET} Click ${BOLD}Import${RESET} to register all 5 entities."
  echo
  echo -e "  ${YELLOW}Press ENTER once you have completed the import, or Ctrl-C to exit.${RESET}"
  read -r -p "" || true
}

# ── Phase 8.7 — Verify imported entities ─────────────────────────────────────
phase8_7_verify_entities() {
  step "Phase 8.7 — Verifying imported entities"

  RHDH_HOST=$(oc get route backstage-developer-hub -n "$RHDH_NAMESPACE" \
    -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

  if [[ -z "$RHDH_HOST" ]]; then
    warn "Cannot determine RHDH URL — skipping API verification"
    return
  fi

  RHDH_URL_VAL="https://${RHDH_HOST}"
  info "Querying Backstage catalog API: $RHDH_URL_VAL"

  local expected_entities=(
    "System:fusion-${CLUSTER_ID}"
    "Component:fusion-dcs-${CLUSTER_ID}"
    "Component:fusion-cas-${CLUSTER_ID}"
    "API:fusion-dcs-mcp-api-${CLUSTER_ID}"
    "API:fusion-cas-mcp-api-${CLUSTER_ID}"
  )

  local found=0
  local total=${#expected_entities[@]}

  # Query the catalog API — Backstage returns all entities; filter client-side
  local catalog_json
  catalog_json=$(curl -s --max-time 15 \
    "${RHDH_URL_VAL}/api/catalog/entities?filter=metadata.annotations.fusion.ibm.com%2Fcluster-id=${CLUSTER_ID}" \
    2>/dev/null || echo "[]")

  for entity in "${expected_entities[@]}"; do
    local kind name
    kind="${entity%%:*}"
    name="${entity##*:}"
    if echo "$catalog_json" | python3 -c "
import sys, json
items = json.load(sys.stdin)
found = any(e.get('kind','') == '${kind}' and e.get('metadata',{}).get('name','') == '${name}'
            for e in items)
sys.exit(0 if found else 1)
" 2>/dev/null; then
      success "  ✓ $kind/$name"
      (( found++ )) || true
    else
      warn "  ✗ $kind/$name — not found yet (may still be ingesting)"
    fi
  done

  if [[ $found -eq $total ]]; then
    success "All $total entities registered in catalog"
  elif [[ $found -gt 0 ]]; then
    warn "$found/$total entities found — the remainder may still be processing"
    warn "Check Catalog in the UI in 60-120 seconds"
  else
    warn "No entities found yet — catalog ingestion may take 30-120 s after import"
    warn "Manual check: ${RHDH_URL_VAL}/catalog?kind=System"
  fi

  export RHDH_URL="$RHDH_URL_VAL"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  step "Registration complete"

  echo -e "${GREEN}"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║     IBM Fusion Developer Hub — Proxy Cluster Registration    ║"
  echo "  ╠══════════════════════════════════════════════════════════════╣"
  printf  "  ║  Cluster      : %-44s ║\n" "$CLUSTER_ID  (proxy-only)"
  printf  "  ║  Domain       : %-44s ║\n" "$CLUSTER_DOMAIN"
  printf  "  ║  RHDH URL     : %-44s ║\n" "${RHDH_URL:-<check oc get route>}"
  printf  "  ║  DCS version  : %-44s ║\n" "$DCS_VERSION"
  printf  "  ║  CAS version  : %-44s ║\n" "$CAS_VERSION"
  echo "  ╠══════════════════════════════════════════════════════════════╣"
  echo "  ║  Catalog import URL (for future use):                        ║"
  echo "  ╠══════════════════════════════════════════════════════════════╣"
  # Print URL broken at 62 chars for the box
  echo "  ║  ${CATALOG_BLOB_URL:0:62}"
  [[ ${#CATALOG_BLOB_URL} -gt 62 ]] && \
  echo "  ║  ${CATALOG_BLOB_URL:62:62}"
  echo "  ╠══════════════════════════════════════════════════════════════╣"
  echo "  ║  Day-2 version updates (no pod restart):                     ║"
  echo "  ║    clusters[name=${CLUSTER_ID}].services.dcs.version           ║"
  echo "  ║    clusters[name=${CLUSTER_ID}].services.cas.version           ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}"
  echo "  ┌─────────────────────────────────────────────────────────────┐"
  echo "  │  02-register-proxy-cluster.sh                                │"
  echo "  │  IBM Fusion Developer Hub — Proxy Cluster Registration       │"
  echo "  │  (Phase 8)                                                   │"
  echo "  └─────────────────────────────────────────────────────────────┘"
  echo -e "${RESET}"

  check_prerequisites
  phase8_1_create_catalog_file
  phase8_2_update_values
  phase8_3_git_push
  phase8_4_verify_github_token
  phase8_5_verify_raw_base_url
  phase8_6_ui_import_instructions
  phase8_7_verify_entities
  print_summary
}

main "$@"
