#!/usr/bin/env bash
# =============================================================================
# 01-deploy-gitops-cluster.sh
#
# End-to-end script: add a Fusion HCI cluster to IBM Fusion Developer Hub
# via OpenShift GitOps (ArgoCD).
#
# Covers every step from the RUNBOOK.md:
#   Phase 1  — SA tokens on the remote Fusion cluster
#   Phase 2  — Edit application.yaml + prod/values.yaml
#   Phase 3  — Create secrets on the RHDH cluster
#   Phase 4  — Bootstrap ArgoCD (first run) or force re-sync (subsequent)
#   Phase 5  — Wait for all sync waves to complete
#   Phase 6  — Verify deployment health
#   Phase 7  — Verify CAS/DCS catalog entities
#
# Usage (interactive — script prompts for any missing value):
#   ./01-deploy-gitops-cluster.sh
#
# Usage (non-interactive — pass all values as env vars):
#   CLUSTER_ID=f80l034 \
#   CLUSTER_DOMAIN=f80l034.fusion.tadn.ibm.com \
#   DCS_VERSION=2.5.3 \
#   CAS_VERSION=1.1.5 \
#   DCS_NAMESPACE=ibm-data-cataloging \
#   CAS_NAMESPACE=ibm-cas \
#   STORAGE_CLASS=ocs-storagecluster-cephfs \
#   REPO_URL=https://github.ibm.com/ProjectAbell/Fusion-AI \
#   REPO_BRANCH=cas-dcs-rhdh \
#   GITHUB_PAT=<your-pat> \
#   SKIP_REMOTE_SA=false \
#   ./01-deploy-gitops-cluster.sh
#
# Required tools: oc, git, python3, sed, base64
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../.." && pwd)"
APP_YAML="${SCRIPT_DIR}/application.yaml"
VALUES_YAML="${REPO_ROOT}/quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml"
RHDH_NS="fusion-developer-hub"
ARGOCD_NS="openshift-gitops"
APP_NAME="fusion-developer-hub"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}══ $* ${NC}"; }
ask()     {
  local var="$1" prompt="$2" default="${3:-}"
  if [[ -n "${!var:-}" ]]; then
    info "$var=${!var} (pre-set)"
    return
  fi
  if [[ -n "$default" ]]; then
    read -r -p "  ${prompt} [${default}]: " input
    printf -v "$var" '%s' "${input:-$default}"
  else
    read -r -p "  ${prompt}: " input
    [[ -z "$input" ]] && error "$var is required."
    printf -v "$var" '%s' "$input"
  fi
}

# Like ask() but input is hidden (for tokens/passwords)
# Pass a 3rd arg "optional" to allow empty input (skip)
ask_secret() {
  local var="$1" prompt="$2" optional="${3:-}"
  if [[ -n "${!var:-}" ]]; then
    info "$var=****** (pre-set)"
    return
  fi
  read -r -s -p "  ${prompt}: " input
  echo ""   # newline after hidden input
  if [[ -z "$input" ]]; then
    [[ "$optional" == "optional" ]] || error "$var is required."
    printf -v "$var" '%s' ""
    return
  fi
  printf -v "$var" '%s' "$input"
}

# ── Dependency check ─────────────────────────────────────────────────────────
check_deps() {
  step "Checking required tools"
  local missing=()
  for tool in oc git python3 sed base64; do
    command -v "$tool" &>/dev/null || missing+=("$tool")
  done
  [[ ${#missing[@]} -eq 0 ]] || error "Missing tools: ${missing[*]}"
  success "All required tools present"
}

# ── Collect parameters ───────────────────────────────────────────────────────
collect_params() {
  step "Cluster parameters"
  echo -e "  Fill in the placeholders for your environment."
  echo -e "  Press Enter to accept a default value shown in [brackets].\n"

  ask CLUSTER_ID      "Cluster ID (short name, e.g. f80l034)"
  ask CLUSTER_DOMAIN  "OCP wildcard domain without 'apps.' prefix (e.g. f80l034.fusion.tadn.ibm.com)"
  ask DCS_VERSION     "DCS version (e.g. 2.5.3)"             "2.5.3"
  ask CAS_VERSION     "CAS version (e.g. 1.1.5)"             "1.1.5"
  ask DCS_NAMESPACE   "DCS namespace on remote cluster"       "ibm-data-cataloging"
  ask CAS_NAMESPACE   "CAS namespace on remote cluster"       "ibm-cas"
  ask STORAGE_CLASS   "RWX StorageClass on RHDH cluster"      "ocs-storagecluster-cephfs"
  # Strip any accidental leading/trailing bracket characters (e.g. user copies the "[default]" prompt bracket)
  STORAGE_CLASS="${STORAGE_CLASS#[}"; STORAGE_CLASS="${STORAGE_CLASS%]}"
  ask REPO_URL        "Git repository URL"                    "https://github.ibm.com/ProjectAbell/Fusion-AI"
  ask REPO_BRANCH     "Git branch"                            "cas-dcs-rhdh"

  echo ""
  echo -e "  ${BOLD}GitHub PAT${NC} — used to create the 'github-auth-secret' in the RHDH namespace."
  echo -e "  RHDH needs this token to read catalog YAML files from the private repo."
  echo -e "  ${CYAN}Get one at:${NC} https://github.ibm.com/settings/tokens  (scope: repo / read)"
  echo -e "  ${YELLOW}Skip (press Enter):${NC} if 'github-auth-secret' already exists in the cluster"
  echo -e "               oc get secret github-auth-secret -n fusion-developer-hub"
  echo ""
  ask_secret GITHUB_PAT "GitHub PAT (paste token, or press Enter to skip if secret already exists)" "optional"

  # Derived values
  OCP_API_URL="https://api.${CLUSTER_DOMAIN}:6443"
  WILDCARD_DOMAIN="apps.${CLUSTER_DOMAIN}"
  CLUSTER_ID_UPPER="$(echo "${CLUSTER_ID}" | tr '[:lower:]-' '[:upper:]_')"
  DCS_TOKEN_KEY="FUSION_${CLUSTER_ID_UPPER}_SA_TOKEN"
  CAS_TOKEN_KEY="FUSION_${CLUSTER_ID_UPPER}_CAS_SA_TOKEN"

  # Whether to run Phase 1 (creates SA + tokens on remote cluster)
  ask SKIP_REMOTE_SA \
    "Skip Phase 1 (SA token creation on remote cluster)? [true/false]" \
    "false"

  echo ""
  echo -e "${BOLD}Summary:${NC}"
  echo "  CLUSTER_ID         = ${CLUSTER_ID}"
  echo "  OCP_API_URL        = ${OCP_API_URL}"
  echo "  WILDCARD_DOMAIN    = ${WILDCARD_DOMAIN}"
  echo "  DCS_VERSION        = ${DCS_VERSION}  (namespace: ${DCS_NAMESPACE})"
  echo "  CAS_VERSION        = ${CAS_VERSION}  (namespace: ${CAS_NAMESPACE})"
  echo "  DCS_TOKEN_KEY      = ${DCS_TOKEN_KEY}"
  echo "  CAS_TOKEN_KEY      = ${CAS_TOKEN_KEY}"
  echo "  STORAGE_CLASS      = ${STORAGE_CLASS}"
  echo "  REPO_URL           = ${REPO_URL}"
  echo "  REPO_BRANCH        = ${REPO_BRANCH}"
  echo "  SKIP_REMOTE_SA     = ${SKIP_REMOTE_SA}"
  echo ""
  read -r -p "  Proceed? [Y/n]: " confirm
  [[ "${confirm:-Y}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
}

# ── Phase 1: SA tokens on the remote Fusion cluster ──────────────────────────
phase1_remote_sa_tokens() {
  if [[ "${SKIP_REMOTE_SA:-false}" == "true" ]]; then
    warn "Phase 1 skipped (SKIP_REMOTE_SA=true). Tokens must already exist."
    return
  fi

  step "Phase 1 — SA tokens on remote Fusion cluster (${CLUSTER_ID})"
  info "Log in to the remote Fusion cluster now."
  info "Run: oc login --token=<token> --server=${OCP_API_URL}"
  read -r -p "  Press Enter once you are logged in to ${CLUSTER_ID}..."
  oc whoami &>/dev/null || error "Not logged in to an OCP cluster."
  info "Logged in as: $(oc whoami)"

  # ── DCS ServiceAccount ────────────────────────────────────────────────────
  info "Creating DCS ServiceAccount in ${DCS_NAMESPACE}..."
  oc create serviceaccount rhdh-dcs-reader -n "${DCS_NAMESPACE}" 2>/dev/null \
    && success "SA rhdh-dcs-reader created" \
    || warn "SA rhdh-dcs-reader already exists — skipping"

  info "Creating/patching DCS ClusterRoleBinding..."
  if oc get clusterrolebinding rhdh-dcs-reader &>/dev/null; then
    CURRENT_NS=$(oc get clusterrolebinding rhdh-dcs-reader \
      -o jsonpath='{.subjects[0].namespace}')
    if [[ "$CURRENT_NS" != "${DCS_NAMESPACE}" ]]; then
      warn "CRB rhdh-dcs-reader points to '${CURRENT_NS}', patching to '${DCS_NAMESPACE}'"
      oc patch clusterrolebinding rhdh-dcs-reader --type=json \
        -p="[{\"op\":\"replace\",\"path\":\"/subjects/0/namespace\",\"value\":\"${DCS_NAMESPACE}\"}]"
    else
      success "CRB rhdh-dcs-reader already correct"
    fi
  else
    oc create clusterrolebinding rhdh-dcs-reader \
      --clusterrole=view \
      --serviceaccount="${DCS_NAMESPACE}:rhdh-dcs-reader"
    success "CRB rhdh-dcs-reader created"
  fi

  # ── CAS ServiceAccount ────────────────────────────────────────────────────
  info "Creating CAS ServiceAccount in ${CAS_NAMESPACE}..."
  oc create serviceaccount rhdh-cas-reader -n "${CAS_NAMESPACE}" 2>/dev/null \
    && success "SA rhdh-cas-reader created" \
    || warn "SA rhdh-cas-reader already exists — skipping"

  info "Creating/patching CAS ClusterRoleBinding..."
  if oc get clusterrolebinding rhdh-cas-reader &>/dev/null; then
    CURRENT_NS=$(oc get clusterrolebinding rhdh-cas-reader \
      -o jsonpath='{.subjects[0].namespace}')
    if [[ "$CURRENT_NS" != "${CAS_NAMESPACE}" ]]; then
      warn "CRB rhdh-cas-reader points to '${CURRENT_NS}', patching to '${CAS_NAMESPACE}'"
      oc patch clusterrolebinding rhdh-cas-reader --type=json \
        -p="[{\"op\":\"replace\",\"path\":\"/subjects/0/namespace\",\"value\":\"${CAS_NAMESPACE}\"}]"
    else
      success "CRB rhdh-cas-reader already correct"
    fi
  else
    oc create clusterrolebinding rhdh-cas-reader \
      --clusterrole=view \
      --serviceaccount="${CAS_NAMESPACE}:rhdh-cas-reader"
    success "CRB rhdh-cas-reader created"
  fi

  # ── Token Secrets (must use oc apply — oc create does not accept annotation) ──
  info "Creating DCS token secret..."
  oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rhdh-dcs-reader-token
  namespace: ${DCS_NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: rhdh-dcs-reader
type: kubernetes.io/service-account-token
EOF

  info "Creating CAS token secret..."
  oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rhdh-cas-reader-token
  namespace: ${CAS_NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: rhdh-cas-reader
type: kubernetes.io/service-account-token
EOF

  # ── Wait for tokens to be populated ──────────────────────────────────────
  info "Waiting for token controller to populate secrets (~10s)..."
  sleep 10

  DCS_TOKEN=$(oc get secret rhdh-dcs-reader-token \
    -n "${DCS_NAMESPACE}" -o jsonpath='{.data.token}' | base64 -d)
  CAS_TOKEN=$(oc get secret rhdh-cas-reader-token \
    -n "${CAS_NAMESPACE}" -o jsonpath='{.data.token}' | base64 -d)

  [[ ${#DCS_TOKEN} -gt 100 ]] || error "DCS token not populated (length=${#DCS_TOKEN}). Check SA: rhdh-dcs-reader in ${DCS_NAMESPACE}"
  [[ ${#CAS_TOKEN} -gt 100 ]] || error "CAS token not populated (length=${#CAS_TOKEN}). Check SA: rhdh-cas-reader in ${CAS_NAMESPACE}"
  success "DCS token extracted (length=${#DCS_TOKEN})"
  success "CAS token extracted (length=${#CAS_TOKEN})"

  info "Log back in to the RHDH cluster now."
  read -r -p "  Press Enter once you are logged in to the RHDH cluster..."
  oc whoami &>/dev/null || error "Not logged in to an OCP cluster."
  info "Logged in as: $(oc whoami)"
}

# ── Phase 2: Edit application.yaml ───────────────────────────────────────────
phase2_edit_application_yaml() {
  step "Phase 2a — Patching application.yaml"

  [[ -f "$APP_YAML" ]] || error "application.yaml not found: ${APP_YAML}"

  # Use sed for safe in-place replacements (works on both GNU and BSD/macOS sed)
  SED_I=( sed -i )
  [[ "$(uname)" == "Darwin" ]] && SED_I=( sed -i '' )

  # repoURL
  "${SED_I[@]}" \
    "s|repoURL:.*|repoURL: ${REPO_URL}|g" \
    "$APP_YAML"

  # targetRevision
  "${SED_I[@]}" \
    "s|targetRevision:.*|targetRevision: ${REPO_BRANCH}|g" \
    "$APP_YAML"

  # wildcardDomain
  "${SED_I[@]}" \
    "s|wildcardDomain:.*|wildcardDomain: ${WILDCARD_DOMAIN}|g" \
    "$APP_YAML"

  # storageClassName
  "${SED_I[@]}" \
    "s|storageClassName:.*|storageClassName: ${STORAGE_CLASS}|g" \
    "$APP_YAML"

  success "application.yaml updated"
  info "  repoURL          = ${REPO_URL}"
  info "  targetRevision   = ${REPO_BRANCH}"
  info "  wildcardDomain   = ${WILDCARD_DOMAIN}"
  info "  storageClassName = ${STORAGE_CLASS}"
}

# ── Phase 2: Edit prod/values.yaml ───────────────────────────────────────────
phase2_edit_values_yaml() {
  step "Phase 2b — Patching environments/prod/values.yaml"

  [[ -f "$VALUES_YAML" ]] || error "values.yaml not found: ${VALUES_YAML}"

  # 1. wildcardDomain + gitRepo + gitBranch
  SED_I=( sed -i )
  [[ "$(uname)" == "Darwin" ]] && SED_I=( sed -i '' )

  "${SED_I[@]}" \
    "s|wildcardDomain:.*|wildcardDomain: ${WILDCARD_DOMAIN}|g" \
    "$VALUES_YAML"

  # Ensure gitRepo/gitBranch point to THIS private repo and branch so TechDocs
  # builder resolves the correct source (not the public IBM/storage-fusion default).
  if grep -q "gitRepo:" "$VALUES_YAML"; then
    "${SED_I[@]}" \
      "s|gitRepo:.*|gitRepo: \"${REPO_URL}\"|g" \
      "$VALUES_YAML"
  else
    # Insert gitRepo + gitBranch directly after "fusionServices:" line
    python3 - "$VALUES_YAML" "$REPO_URL" "$REPO_BRANCH" <<'PYEOF'
import sys, re
path, repo, branch = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    content = f.read()
insert = f'    gitRepo: "{repo}"\n    gitBranch: "{branch}"\n'
content = re.sub(
    r'^([ \t]*fusionServices:[ \t]*\n)',
    r'\1' + insert,
    content,
    count=1,
    flags=re.MULTILINE
)
with open(path, 'w') as f:
    f.write(content)
print(f"gitRepo/gitBranch inserted into fusionServices")
PYEOF
  fi

  if grep -q "gitBranch:" "$VALUES_YAML"; then
    "${SED_I[@]}" \
      "s|gitBranch:.*|gitBranch: \"${REPO_BRANCH}\"|g" \
      "$VALUES_YAML"
  fi
  success "gitRepo=${REPO_URL}  gitBranch=${REPO_BRANCH} written to values.yaml"

  # 2. Ensure extraEnvs.secrets has fusion-cluster-tokens (active, not commented)
  if grep -q "# - name: fusion-cluster-tokens" "$VALUES_YAML"; then
    "${SED_I[@]}" \
      "s|# - name: fusion-cluster-tokens.*|- name: fusion-cluster-tokens|g" \
      "$VALUES_YAML"
    success "Uncommented fusion-cluster-tokens in extraEnvs.secrets"
  elif ! grep -q "name: fusion-cluster-tokens" "$VALUES_YAML"; then
    warn "fusion-cluster-tokens not found in extraEnvs.secrets — will be added by cluster block"
  fi

  # 3. Ensure github-auth-secret is active (not commented out)
  if grep -q "# - name: github-auth-secret" "$VALUES_YAML"; then
    "${SED_I[@]}" \
      "s|# - name: github-auth-secret.*|- name: github-auth-secret|g" \
      "$VALUES_YAML"
    success "Uncommented github-auth-secret in extraEnvs.secrets"
  fi

  # 4. Strip any unfilled placeholder cluster entries (name: <cluster-id>)
  python3 - "$VALUES_YAML" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# Remove entire cluster block where name contains < or >
# Matches: leading spaces + "- name: <...>" through the next same-indent "- name:" or comment block
content = re.sub(
    r'[ \t]+-[ \t]+name:[ \t]+<[^>]*>[^\n]*\n(?:(?![ \t]+-[ \t]+name:)(?![ \t]+#[ \t]+Add).*\n)*',
    '',
    content
)

with open(path, 'w') as f:
    f.write(content)
print("placeholder entries removed")
PYEOF

  # 4. Cluster entry — add if not already present
  if grep -q "name: ${CLUSTER_ID}$" "$VALUES_YAML"; then
    warn "Cluster '${CLUSTER_ID}' already present in values.yaml — updating versions"
    # Update DCS version
    python3 - "$VALUES_YAML" "$CLUSTER_ID" "$DCS_VERSION" "$CAS_VERSION" <<'PYEOF'
import sys, re

path, cid, dcs_ver, cas_ver = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path) as f:
    content = f.read()

# Find the cluster block and update versions inside it
# Pattern: inside "- name: <cid>" block, replace version: "x.y.z"
in_cluster = False
lines = content.splitlines(keepends=True)
out = []
i = 0
while i < len(lines):
    line = lines[i]
    if re.search(rf'^\s+- name: {re.escape(cid)}\s*$', line):
        in_cluster = True
    elif in_cluster and re.match(r'^\s+- name:', line) and f'name: {cid}' not in line:
        in_cluster = False
    if in_cluster and re.search(r'version:\s+"?\d', line):
        # Determine context: dcs or cas by looking back
        context = ''.join(out[-5:]).lower()
        if 'dcs:' in context or 'ibm-data-cataloging' in context:
            line = re.sub(r'version:.*', f'version: "{dcs_ver}"', line)
        elif 'cas:' in context or 'ibm-cas' in context or 'ibm-spectrum' in context:
            line = re.sub(r'version:.*', f'version: "{cas_ver}"', line)
    out.append(line)
    i += 1

with open(path, 'w') as f:
    f.writelines(out)
print("versions updated")
PYEOF
  else
    # Append new cluster entry under the clusters: key
    info "Appending cluster '${CLUSTER_ID}' to clusters[] in values.yaml"
    python3 - "$VALUES_YAML" \
      "$CLUSTER_ID" "$OCP_API_URL" \
      "$DCS_VERSION" "$DCS_NAMESPACE" "$DCS_TOKEN_KEY" \
      "$CAS_VERSION" "$CAS_NAMESPACE" "$CAS_TOKEN_KEY" <<'PYEOF'
import sys, re

(path, cid, api_url,
 dcs_ver, dcs_ns, dcs_key,
 cas_ver, cas_ns, cas_key) = sys.argv[1:]

new_block = f"""      - name: {cid}
        ocpApiUrl: {api_url}
        clusterType: self-hosted
        services:
          dcs:
            enabled: true
            version: "{dcs_ver}"
            namespace: {dcs_ns}
            k8s:
              tokenEnvVar: {dcs_key}
              labelSelector: "app=isd,component=discover"
          cas:
            enabled: true
            version: "{cas_ver}"
            namespace: {cas_ns}
            k8s:
              tokenEnvVar: {cas_key}
              labelSelector: "app.kubernetes.io/name=cas.isf.ibm.com"
"""

with open(path) as f:
    content = f.read()

# Step 1: normalise "clusters: []" (empty inline list) to a block-style key
# so the insertion regex always sees "clusters:\n" as the anchor.
content = re.sub(
    r'^([ \t]+clusters:)[ \t]*\[\][ \t]*$',
    r'\1',
    content,
    flags=re.MULTILINE
)

# Step 2: insert the new cluster block immediately before the
# "# Add additional clusters" sentinel comment that follows clusters:.
# The sentinel must sit at the SAME indent level as cluster list items
# (i.e. it belongs to the fusionServices.clusters block, not any other block).
# We anchor on the exact comment text written by this script to avoid
# accidentally matching similar comments elsewhere in the file.
if 'clusters:' in content:
    insert_re = re.compile(
        r'^([ \t]+)(      # Add additional clusters below\.)',
        re.MULTILINE
    )
    m = insert_re.search(content)
    if m:
        pos = m.start()
        content = content[:pos] + new_block + content[pos:]
    else:
        # Fallback: append directly after the "clusters:" line (no sentinel found)
        content = re.sub(
            r'^([ \t]+clusters:[ \t]*\n)',
            r'\1' + new_block,
            content,
            count=1,
            flags=re.MULTILINE
        )

with open(path, 'w') as f:
    f.write(content)
print(f"cluster {cid} appended")
PYEOF
    success "Cluster '${CLUSTER_ID}' added to values.yaml"
  fi

  success "environments/prod/values.yaml updated"
}

# ── Phase 3: Secrets on the RHDH cluster ─────────────────────────────────────
phase3_create_secrets() {
  step "Phase 3 — Secrets on the RHDH cluster"

  # Pre-create namespace (ArgoCD creates it on sync, but secrets must exist first)
  if oc get namespace "${RHDH_NS}" &>/dev/null; then
    success "Namespace ${RHDH_NS} already exists"
  else
    info "Creating namespace ${RHDH_NS}..."
    oc create namespace "${RHDH_NS}"
    success "Namespace ${RHDH_NS} created"
  fi

  # Ensure we have tokens (either from Phase 1 or re-read if SKIP_REMOTE_SA=true)
  if [[ "${SKIP_REMOTE_SA:-false}" == "true" ]]; then
    info "SKIP_REMOTE_SA=true — reading existing tokens from remote cluster"
    info "Log in to the remote Fusion cluster now."
    read -r -p "  Press Enter once you are logged in to ${CLUSTER_ID}..."
    DCS_TOKEN=$(oc get secret rhdh-dcs-reader-token \
      -n "${DCS_NAMESPACE}" -o jsonpath='{.data.token}' | base64 -d) \
      || error "Cannot read DCS token from remote cluster"
    CAS_TOKEN=$(oc get secret rhdh-cas-reader-token \
      -n "${CAS_NAMESPACE}" -o jsonpath='{.data.token}' | base64 -d) \
      || error "Cannot read CAS token from remote cluster"
    [[ ${#DCS_TOKEN} -gt 100 ]] || error "DCS token is empty"
    [[ ${#CAS_TOKEN} -gt 100 ]] || error "CAS token is empty"
    success "Tokens read from remote cluster"
    info "Log back in to the RHDH cluster now."
    read -r -p "  Press Enter once you are logged in to the RHDH cluster..."
  fi

  # fusion-cluster-tokens secret
  if oc get secret fusion-cluster-tokens -n "${RHDH_NS}" &>/dev/null; then
    info "Secret fusion-cluster-tokens exists — patching keys for ${CLUSTER_ID}..."
    oc patch secret fusion-cluster-tokens -n "${RHDH_NS}" \
      --type=merge \
      -p "{\"data\":{
        \"${DCS_TOKEN_KEY}\":\"$(echo -n "${DCS_TOKEN}" | base64)\",
        \"${CAS_TOKEN_KEY}\":\"$(echo -n "${CAS_TOKEN}" | base64)\"
      }}"
    success "Secret fusion-cluster-tokens patched (added ${DCS_TOKEN_KEY}, ${CAS_TOKEN_KEY})"
  else
    oc create secret generic fusion-cluster-tokens \
      --from-literal="${DCS_TOKEN_KEY}=${DCS_TOKEN}" \
      --from-literal="${CAS_TOKEN_KEY}=${CAS_TOKEN}" \
      -n "${RHDH_NS}"
    success "Secret fusion-cluster-tokens created"
  fi

  # github-auth-secret
  if oc get secret github-auth-secret -n "${RHDH_NS}" &>/dev/null; then
    success "Secret github-auth-secret already exists — skipping"
  elif [[ -z "${GITHUB_PAT:-}" ]]; then
    warn "GITHUB_PAT not provided and github-auth-secret does not exist."
    warn "Create it manually: oc create secret generic github-auth-secret --from-literal=GITHUB_TOKEN=<pat> -n ${RHDH_NS}"
  else
    oc create secret generic github-auth-secret \
      --from-literal="GITHUB_TOKEN=${GITHUB_PAT}" \
      -n "${RHDH_NS}"
    success "Secret github-auth-secret created"
  fi

  # Verify
  info "Verifying token keys in fusion-cluster-tokens..."
  oc get secret fusion-cluster-tokens -n "${RHDH_NS}" \
    -o jsonpath='{.data}' | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
for k, v in sorted(d.items()):
    tok = base64.b64decode(v).decode()
    status = 'OK' if len(tok) > 100 else 'EMPTY!'
    print(f'  [{status}] {k}: length={len(tok)}, prefix={tok[:16]}...')
"
}

# ── Phase 2c: Commit and push ─────────────────────────────────────────────────
phase2_commit_push() {
  step "Phase 2c — Commit and push Git changes"

  cd "${REPO_ROOT}"

  if ! git diff --quiet -- \
      "quickstarts/fusion-developerhub/deploy/gitops/environments/prod/application.yaml" \
      "quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml"; then

    git add \
      "quickstarts/fusion-developerhub/deploy/gitops/environments/prod/application.yaml" \
      "quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml"

    git commit -m "feat(prod): add cluster ${CLUSTER_ID} — DCS ${DCS_VERSION}, CAS ${CAS_VERSION}

- application.yaml: repoURL=${REPO_URL}, branch=${REPO_BRANCH}
  wildcardDomain=${WILDCARD_DOMAIN}, storageClass=${STORAGE_CLASS}
- prod/values.yaml: cluster ${CLUSTER_ID} (self-hosted)
  DCS ${DCS_VERSION} in ${DCS_NAMESPACE}
  CAS ${CAS_VERSION} in ${CAS_NAMESPACE}
  extraEnvs.secrets: fusion-cluster-tokens + github-auth-secret"

    git push origin "${REPO_BRANCH}"
    success "Changes committed and pushed to ${REPO_BRANCH}"
  else
    info "No changes to commit — files already up to date"
  fi
}

# ── Phase 4b: Pre-create dynamic-plugins-root PVC ────────────────────────────
# WHY THIS EXISTS:
#
# The dynamic-plugins-root PVC (wave 65) and the Backstage CR (wave 70) are
# both applied by ArgoCD in the same sync operation.  Even though the PVC is
# one wave earlier, the RHDH operator reacts to the Backstage CR almost
# instantly and schedules pods before the PVC StorageClass provisioner has
# finished binding the volume.  The pods enter Pending with:
#
#   "persistentvolumeclaim \"dynamic-plugins-root\" not found"
#
# Pre-creating the PVC (and waiting for Bound) before ArgoCD ever applies the
# Backstage CR guarantees the volume is available the moment the operator
# schedules the first pod.  When ArgoCD later reconciles wave 65 it sees the
# PVC already exists and is Bound — it skips creation and the pod starts
# immediately.
phase4b_ensure_pvc() {
  step "Phase 4b — Pre-create dynamic-plugins-root PVC"

  # Ensure namespace exists (ArgoCD creates it on first sync, but we need it now)
  if ! oc get namespace "${RHDH_NS}" &>/dev/null; then
    info "Creating namespace ${RHDH_NS} (pre-flight)..."
    oc create namespace "${RHDH_NS}"
    success "Namespace ${RHDH_NS} created"
  else
    success "Namespace ${RHDH_NS} already exists"
  fi

  # Read storage values from the parameters already collected
  # (STORAGE_CLASS was collected in collect_params; default matches values.yaml)
  local PVC_SIZE="5Gi"
  local PVC_NS="${RHDH_NS}"

  if oc get pvc dynamic-plugins-root -n "${PVC_NS}" &>/dev/null; then
    PVC_STATUS=$(oc get pvc dynamic-plugins-root -n "${PVC_NS}" \
      -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "${PVC_STATUS}" == "Bound" ]]; then
      success "PVC dynamic-plugins-root already Bound — skipping"
      return
    fi
    warn "PVC dynamic-plugins-root exists but status=${PVC_STATUS} — waiting for Bound..."
  else
    info "Creating PVC dynamic-plugins-root (${PVC_SIZE} RWX ${STORAGE_CLASS})..."
    oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-plugins-root
  namespace: ${PVC_NS}
  labels:
    app.kubernetes.io/managed-by: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "65"
spec:
  storageClassName: ${STORAGE_CLASS}
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: ${PVC_SIZE}
EOF
    success "PVC dynamic-plugins-root created — waiting for Bound..."
  fi

  # Wait up to 120s for the PVC to be Bound
  local waited=0
  while true; do
    PVC_STATUS=$(oc get pvc dynamic-plugins-root -n "${PVC_NS}" \
      -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    if [[ "${PVC_STATUS}" == "Bound" ]]; then
      success "PVC dynamic-plugins-root is Bound"
      break
    fi
    if [[ $waited -ge 120 ]]; then
      warn "PVC not yet Bound after 120s (status=${PVC_STATUS})."
      warn "Check storage class: oc get pvc dynamic-plugins-root -n ${PVC_NS}"
      warn "Check provisioner:   oc get storageclass ${STORAGE_CLASS}"
      warn "Continuing — ArgoCD will retry, but pods may stay Pending until PVC is Bound."
      break
    fi
    sleep 5; waited=$((waited + 5))
    info "  [${waited}s] PVC status=${PVC_STATUS} — waiting..."
  done
}

# ── Phase 4: Bootstrap or re-sync ArgoCD ─────────────────────────────────────
phase4_argocd_bootstrap() {
  step "Phase 4 — ArgoCD bootstrap / sync"

  # Always apply the updated application.yaml so ArgoCD picks up the correct
  # repoURL / targetRevision / wildcardDomain values from the just-committed file.
  info "Applying application.yaml to ${ARGOCD_NS}..."
  oc apply -f "${APP_YAML}"

  if oc get application.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" &>/dev/null; then
    # Hard-refresh clears ArgoCD's cached git revision so it re-resolves the
    # branch from the remote.  This is the fix for:
    #   "revision <branch> must be resolved"
    # which occurs when ArgoCD cached a previous failed resolution or the
    # Application was registered before the branch ref was pushed.
    info "Hard-refreshing ArgoCD cache to force branch re-resolution..."
    oc annotate application.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" \
      --overwrite \
      "argocd.argoproj.io/refresh=hard"

    # Wait up to 30s for the refresh annotation to be cleared (ArgoCD removes
    # it when the refresh completes).
    local waited=0
    while oc get application.argoproj.io "${APP_NAME}" \
        -n "${ARGOCD_NS}" \
        -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/refresh}' \
        2>/dev/null | grep -q "hard"; do
      sleep 3; waited=$((waited + 3))
      [[ $waited -ge 30 ]] && break
    done
    success "ArgoCD cache refreshed"

    # Now trigger a sync (operation patch only works after a successful ref resolution)
    oc patch application.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" --type=merge \
      -p "{\"operation\":{\"initiatedBy\":{\"username\":\"01-deploy-gitops-cluster.sh\"},\"sync\":{\"revision\":\"${REPO_BRANCH}\"}}}"
    success "ArgoCD sync triggered (branch: ${REPO_BRANCH})"
  else
    success "Application '${APP_NAME}' created in ${ARGOCD_NS}"
  fi
}

# ── Helper: detect and self-heal the PVC-not-found pod-Pending race ──────────
# Called from phase5 after ArgoCD reports Synced+Healthy.
# Even with phase4b pre-creating the PVC, on a re-run the operator may
# still cycle pods while ArgoCD is reconciling.  This catches it.
_check_pvc_pending() {
  local PENDING
  PENDING=$(oc get pods -n "${RHDH_NS}" --no-headers 2>/dev/null \
    | awk '$3=="Pending"{print $1}' | grep "backstage-developer-hub" || true)

  if [[ -z "$PENDING" ]]; then
    success "No Pending backstage pods — PVC race condition not present"
    return
  fi

  # Check whether the Pending reason is specifically the missing PVC
  local PVC_ERR
  PVC_ERR=$(oc get events -n "${RHDH_NS}" \
    --field-selector reason=FailedMount,type=Warning \
    --sort-by='.lastTimestamp' 2>/dev/null \
    | grep "dynamic-plugins-root" | tail -1 || true)

  if [[ -z "$PVC_ERR" ]]; then
    # Try describe for scheduler messages
    PVC_ERR=$(oc describe pod "$(echo "$PENDING" | head -1)" \
      -n "${RHDH_NS}" 2>/dev/null \
      | grep -i "dynamic-plugins-root\|persistentvolumeclaim" | head -2 || true)
  fi

  if [[ -n "$PVC_ERR" ]] || \
     ! oc get pvc dynamic-plugins-root -n "${RHDH_NS}" &>/dev/null; then
    warn "Detected PVC race: pods Pending because dynamic-plugins-root PVC missing/not-Bound."
    warn "Root cause: RHDH operator scheduled pods before ArgoCD wave 65 created the PVC."
    info "Self-healing: creating/waiting for dynamic-plugins-root PVC..."

    oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-plugins-root
  namespace: ${RHDH_NS}
  labels:
    app.kubernetes.io/managed-by: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "65"
spec:
  storageClassName: ${STORAGE_CLASS}
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
EOF

    local waited=0
    while true; do
      local st
      st=$(oc get pvc dynamic-plugins-root -n "${RHDH_NS}" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
      [[ "$st" == "Bound" ]] && { success "PVC dynamic-plugins-root now Bound — pods will start shortly"; break; }
      [[ $waited -ge 120 ]] && { warn "PVC still not Bound after 120s — check storageclass ${STORAGE_CLASS}"; break; }
      sleep 5; waited=$((waited + 5))
      info "  [${waited}s] PVC status=${st}..."
    done
  else
    warn "Pods Pending but not due to PVC. Check: oc describe pod ${PENDING} -n ${RHDH_NS}"
  fi
}

# ── Phase 5: Wait for sync waves ─────────────────────────────────────────────
phase5_wait_sync() {
  step "Phase 5 — Waiting for ArgoCD sync waves to complete"

  local timeout=600        # 10 minutes max for a full sync
  local interval=15
  local elapsed=0
  local unknown_streak=0
  local unknown_limit=4    # fail after 4 consecutive Unknown polls (~60s)
                           # Unknown = ArgoCD cannot render the chart (YAML/Helm error)
                           # or cannot reach git. Surface the reason immediately.

  # Helper: pull the human-readable reason for sync=Unknown from the
  # Application's status.conditions array (the first non-empty message).
  get_unknown_reason() {
    oc get application.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" \
      -o jsonpath='{range .status.conditions[*]}{.message}{"\n"}{end}' \
      2>/dev/null | grep -v '^$' | head -3 || true
    # Also check the repo-server error surfaced in operationState
    oc get application.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" \
      -o jsonpath='{.status.operationState.message}' \
      2>/dev/null | grep -v '^$' || true
  }

  info "Polling every ${interval}s (timeout: ${timeout}s)..."
  while true; do
    SYNC=$(oc get application.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(oc get application.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" \
      -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    PHASE=$(oc get application.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" \
      -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "")
    MSG=$(oc get application.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" \
      -o jsonpath='{.status.operationState.message}' 2>/dev/null || echo "")

    echo -e "  [${elapsed}s] sync=${YELLOW}${SYNC}${NC}  health=${CYAN}${HEALTH}${NC}  phase=${PHASE}"
    [[ -n "$MSG" ]] && echo -e "         msg: ${MSG}"

    # ── Success ──────────────────────────────────────────────────────────────
    if [[ "$SYNC" == "Synced" && "$HEALTH" == "Healthy" ]]; then
      success "ArgoCD sync complete — Synced + Healthy"
      # ArgoCD is happy but the RHDH operator may have scheduled pods before
      # the PVC was Bound.  Check for the specific race condition and self-heal.
      _check_pvc_pending
      break
    fi

    # ── Hard failure ─────────────────────────────────────────────────────────
    if [[ "$PHASE" == "Failed" || "$PHASE" == "Error" ]]; then
      error "ArgoCD sync failed (phase=${PHASE}). Check: oc get events -n ${RHDH_NS} --sort-by=.lastTimestamp"
    fi

    # ── Persistent Unknown — surface the reason and fail fast ────────────────
    # sync=Unknown means ArgoCD cannot compute a diff: the most common causes
    # are a Helm/YAML render error in values.yaml or a git access problem.
    # Spinning for 10 minutes gives no useful signal — detect and abort early.
    if [[ "$SYNC" == "Unknown" ]]; then
      unknown_streak=$((unknown_streak + 1))
      if [[ $unknown_streak -ge $unknown_limit ]]; then
        echo ""
        warn "sync=Unknown for $((unknown_streak * interval))s — ArgoCD cannot render the chart."
        warn "Likely causes:"
        warn "  1. YAML/Helm error in prod/values.yaml or application.yaml"
        warn "  2. git credentials missing (github-auth-secret or ArgoCD repo secret)"
        warn "  3. targetRevision branch not accessible from ArgoCD"
        echo ""
        warn "ArgoCD status conditions:"
        get_unknown_reason | sed 's/^/    /'
        echo ""
        warn "Diagnostics:"
        warn "  oc get application.argoproj.io ${APP_NAME} -n ${ARGOCD_NS} -o yaml | grep -A5 conditions"
        warn "  oc logs -n ${ARGOCD_NS} -l app.kubernetes.io/name=argocd-repo-server --tail=40"
        error "Aborting — fix the root cause above then re-run Phase 4+5."
      fi
    else
      unknown_streak=0   # reset streak on any non-Unknown status
    fi

    # ── Timeout ──────────────────────────────────────────────────────────────
    if [[ $elapsed -ge $timeout ]]; then
      warn "Timeout waiting for sync. Current: sync=${SYNC} health=${HEALTH}"
      warn "Continue watching: oc get pods -n ${RHDH_NS}"
      break
    fi

    sleep $interval
    elapsed=$((elapsed + interval))
  done
}

# ── Phase 6: Verify deployment ────────────────────────────────────────────────
phase6_verify_deployment() {
  step "Phase 6 — Verifying deployment"

  # Pods
  info "Pod status:"
  oc get pods -n "${RHDH_NS}" --no-headers 2>/dev/null \
    | grep -v "Completed\|Terminating" \
    | awk '{printf "  %-55s %-10s %s\n", $1, $2, $3}' || true

  # ArgoCD
  SYNC=$(oc get application.argoproj.io "${APP_NAME}" \
    -n "${ARGOCD_NS}" -o jsonpath='{.status.sync.status}' 2>/dev/null)
  HEALTH=$(oc get application.argoproj.io "${APP_NAME}" \
    -n "${ARGOCD_NS}" -o jsonpath='{.status.health.status}' 2>/dev/null)
  info "ArgoCD: sync=${SYNC}  health=${HEALTH}"

  # Route
  RHDH_URL=$(oc get route backstage-developer-hub \
    -n "${RHDH_NS}" \
    -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "route not found")
  success "RHDH URL: ${RHDH_URL}"

  # GITHUB_TOKEN in pod
  POD=$(oc get pods -n "${RHDH_NS}" --no-headers 2>/dev/null \
    | grep "backstage-developer-hub.*Running" | awk 'NR==1{print $1}')
  if [[ -n "$POD" ]]; then
    TOKEN_COUNT=$(oc exec -n "${RHDH_NS}" "$POD" -- env 2>/dev/null \
      | grep -c GITHUB_TOKEN || echo 0)
    if [[ "$TOKEN_COUNT" -gt 0 ]]; then
      success "GITHUB_TOKEN present in pod (${POD})"
    else
      warn "GITHUB_TOKEN NOT found in pod. Check extraEnvs.secrets in values.yaml and restart deployment."
    fi
  else
    warn "No Running Backstage pod found yet"
  fi
}

# ── Phase 7: Verify catalog entities ─────────────────────────────────────────
phase7_verify_catalog() {
  step "Phase 7 — Verifying CAS/DCS catalog entities for ${CLUSTER_ID}"

  # 1. ConfigMap key exists
  info "Checking fusion-ai-clusters ConfigMap..."
  CM_KEY=$(oc get configmap fusion-ai-clusters \
    -n "${RHDH_NS}" \
    -o jsonpath="{.data.fusion-${CLUSTER_ID}-catalog-info\\.yaml}" 2>/dev/null | wc -c)
  if [[ "$CM_KEY" -gt 10 ]]; then
    success "ConfigMap key fusion-${CLUSTER_ID}-catalog-info.yaml present (${CM_KEY} bytes)"
  else
    warn "ConfigMap key not found — ArgoCD may not have synced Wave 50 yet"
    return
  fi

  # 2. File mounted in pod
  POD=$(oc get pods -n "${RHDH_NS}" --no-headers 2>/dev/null \
    | grep "backstage-developer-hub.*Running" | awk 'NR==1{print $1}')
  if [[ -z "$POD" ]]; then
    warn "No Running Backstage pod found — skipping mount check"
    return
  fi

  FILE_PATH="/opt/app-root/src/fusion-clusters/fusion-${CLUSTER_ID}-catalog-info.yaml"
  if oc exec -n "${RHDH_NS}" "$POD" -- test -f "${FILE_PATH}" 2>/dev/null; then
    success "File mounted at ${FILE_PATH}"
  else
    warn "File not yet mounted — kubelet propagation can take ~60s after ConfigMap update"
  fi

  # 3. No EISDIR errors in logs
  info "Checking backend logs for EISDIR errors..."
  EISDIR_COUNT=$(oc logs -n "${RHDH_NS}" "$POD" \
    -c backstage-backend --since=5m 2>/dev/null \
    | grep -c "EISDIR" || echo 0)
  if [[ "$EISDIR_COUNT" -eq 0 ]]; then
    success "No EISDIR errors in last 5m of logs"
  else
    warn "Found ${EISDIR_COUNT} EISDIR error(s). The catalog location may still point to a directory."
    warn "Check: oc exec -n ${RHDH_NS} ${POD} -- grep -A3 fusion-clusters /opt/app-root/src/app-config-fusion-services.yaml"
  fi

  # 4. Catalog config target
  info "Checking catalog location target in pod config..."
  TARGET=$(oc exec -n "${RHDH_NS}" "$POD" -- \
    grep "fusion-clusters" /opt/app-root/src/app-config-fusion-services.yaml \
    2>/dev/null | grep target || echo "not found")
  info "  ${TARGET}"
  if echo "$TARGET" | grep -q "fusion-${CLUSTER_ID}-catalog-info.yaml"; then
    success "Catalog location points to per-cluster file (correct)"
  else
    warn "Catalog location may still point to directory — restart pod if config was recently updated"
  fi

  echo ""
  success "Verification complete for cluster ${CLUSTER_ID}"
  echo -e "  Expected catalog entities:"
  echo -e "    [System]    fusion-${CLUSTER_ID}"
  echo -e "    [Component] fusion-dcs-${CLUSTER_ID}"
  echo -e "    [API]       fusion-dcs-mcp-api-${CLUSTER_ID}"
  echo -e "    [Component] fusion-cas-${CLUSTER_ID}"
  echo -e "    [API]       fusion-cas-mcp-api-${CLUSTER_ID}"
}

# ── Final summary ─────────────────────────────────────────────────────────────
print_summary() {
  RHDH_URL=$(oc get route backstage-developer-hub \
    -n "${RHDH_NS}" \
    -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "check after sync completes")

  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║          Fusion Developer Hub — Deployment Complete          ║${NC}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}Cluster:${NC}   ${CLUSTER_ID}"
  echo -e "  ${BOLD}DCS:${NC}       ${DCS_VERSION}  (${DCS_NAMESPACE})"
  echo -e "  ${BOLD}CAS:${NC}       ${CAS_VERSION}  (${CAS_NAMESPACE})"
  echo -e "  ${BOLD}Branch:${NC}    ${REPO_BRANCH}"
  echo -e "  ${BOLD}RHDH URL:${NC}  ${RHDH_URL}"
  echo ""
  echo -e "  ${BOLD}Catalog entities to appear in ~2 minutes:${NC}"
  echo -e "    system:default/fusion-${CLUSTER_ID}"
  echo -e "    component:default/fusion-dcs-${CLUSTER_ID}"
  echo -e "    component:default/fusion-cas-${CLUSTER_ID}"
  echo -e "    api:default/fusion-dcs-mcp-api-${CLUSTER_ID}"
  echo -e "    api:default/fusion-cas-mcp-api-${CLUSTER_ID}"
  echo ""
  echo -e "  ${BOLD}Day-2 — version bump:${NC}"
  echo -e "    Edit clusters[name=${CLUSTER_ID}].services.<dcs|cas>.version in"
  echo -e "    deploy/helm/environments/prod/values.yaml"
  echo -e "    git commit && git push → live in ~2 min, no restart needed"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}${CYAN}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║     IBM Fusion Developer Hub — GitOps Cluster Deployment    ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  check_deps
  collect_params
  phase1_remote_sa_tokens
  phase2_edit_application_yaml
  phase2_edit_values_yaml
  phase3_create_secrets
  phase2_commit_push
  phase4b_ensure_pvc
  phase4_argocd_bootstrap
  phase5_wait_sync
  phase6_verify_deployment
  phase7_verify_catalog
  print_summary
}

main "$@"
