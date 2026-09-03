#!/usr/bin/env bash
# =============================================================================
# 99-cleanup-gitops-cluster.sh
#
# Full teardown of IBM Fusion Developer Hub and every entity it created.
# Only resources that belong to fusion-developer-hub are touched.
# Shared operators (RHDH, PostgreSQL) and their namespaces are LEFT ALONE
# unless you explicitly opt in with DELETE_OPERATORS=true.
#
#   Phase C1  — Preflight checks
#   Phase C2  — ArgoCD Application deletion (openshift-gitops)
#   Phase C3  — fusion-developer-hub namespace: Backstage CR, PostgresCluster,
#               all PVCs (including dynamic-plugins-root), Secrets, ConfigMaps,
#               Jobs, Routes, Services, Roles, ServiceAccounts, namespace delete
#   Phase C4  — [opt-in] Operator subscription/CSV cleanup
#               (only runs when DELETE_OPERATORS=true)
#   Phase C5  — [opt-in] Operator namespace deletion
#               (only runs when DELETE_OPERATORS=true)
#   Phase C6  — Remote Fusion cluster cleanup: SA tokens, CRBs for every
#               cluster entry found in values.yaml
#   Phase C7  — Git file reset: application.yaml → placeholders,
#               values.yaml → clusters: [] + storageClassName: "" + wildcardDomain: ""
#               Proxy-cluster catalog-info files removed from clusters/
#   Phase C8  — Stale-entry audit: confirm zero remaining resources
#
# Usage (interactive):
#   ./99-cleanup-gitops-cluster.sh
#
# Usage (non-interactive / CI — skip every prompt):
#   FORCE=true ./99-cleanup-gitops-cluster.sh
#
# Usage (also remove RHDH + PostgreSQL operators and their namespaces):
#   DELETE_OPERATORS=true ./99-cleanup-gitops-cluster.sh
#
# Usage (skip Git reset — keep file changes local only):
#   SKIP_GIT_PUSH=true ./99-cleanup-gitops-cluster.sh
#
# Usage (skip remote cluster SA teardown):
#   SKIP_REMOTE_CLEANUP=true ./99-cleanup-gitops-cluster.sh
#
# Usage (dry-run — print every oc/git command without executing):
#   DRY_RUN=true ./99-cleanup-gitops-cluster.sh
#
# Required tools: oc, git, python3, sed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../../.." && pwd)"
APP_YAML="${SCRIPT_DIR}/application.yaml"
VALUES_YAML="${REPO_ROOT}/quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml"
CLUSTERS_DIR="${REPO_ROOT}/quickstarts/fusion-developerhub/fusion-ai-discovery/clusters"

# Fixed names (must match 01-deploy-gitops-cluster.sh)
RHDH_NS="fusion-developer-hub"
ARGOCD_NS="openshift-gitops"
APP_NAME="fusion-developer-hub"
RHDH_OPERATOR_NS="rhdh-operator"
PG_OPERATOR_NS="postgres-operator"

# Runtime flags (override via env)
FORCE="${FORCE:-false}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_GIT_PUSH="${SKIP_GIT_PUSH:-false}"
SKIP_REMOTE_CLEANUP="${SKIP_REMOTE_CLEANUP:-false}"
# Set DELETE_OPERATORS=true to also remove the RHDH and PostgreSQL operator
# subscriptions/CSVs and their namespaces.  Default is false — operators are
# shared resources and must not be removed without explicit intent.
DELETE_OPERATORS="${DELETE_OPERATORS:-false}"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}══ $* ${NC}"; }
skip()    { echo -e "${YELLOW}[SKIP]${NC}  $*"; }

# ── Dry-run wrapper ───────────────────────────────────────────────────────────
# All destructive oc / git calls MUST go through run() so DRY_RUN is honoured.
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
  else
    "$@"
  fi
}

# ── Confirmation gate ─────────────────────────────────────────────────────────
confirm() {
  local prompt="$1"
  if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
    info "Auto-confirmed (FORCE=${FORCE} DRY_RUN=${DRY_RUN}): ${prompt}"
    return 0
  fi
  echo -e "${YELLOW}${prompt}${NC}"
  read -r -p "  Type 'yes' to continue, anything else to abort: " reply
  echo ""
  [[ "$reply" == "yes" ]] || { echo "Aborted."; exit 0; }
}

# ── Wait helper ───────────────────────────────────────────────────────────────
# wait_gone <timeout_seconds> <check_command...>
# Returns 0 when the check_command returns non-zero (resource gone).
wait_gone() {
  local timeout="$1"; shift
  local waited=0
  while "$@" &>/dev/null; do
    [[ $waited -ge $timeout ]] && return 1
    sleep 5; waited=$((waited + 5))
    info "  [${waited}s] still present — waiting..."
  done
  return 0
}

# ── Phase C1: Preflight ───────────────────────────────────────────────────────
phase_c1_preflight() {
  step "Phase C1 — Preflight checks"

  local missing=()
  for tool in oc git python3 sed; do
    command -v "$tool" &>/dev/null || missing+=("$tool")
  done
  [[ ${#missing[@]} -eq 0 ]] || error "Missing tools: ${missing[*]}"
  success "All required tools present"

  if [[ "$DRY_RUN" != "true" ]]; then
    oc whoami &>/dev/null || error "Not logged in to any OCP cluster. Run: oc login ..."
    info "Logged in as: $(oc whoami)"
    info "Current server: $(oc whoami --show-server 2>/dev/null || echo 'unknown')"
  fi

  echo ""
  echo -e "${BOLD}This script will PERMANENTLY DELETE (fusion-developer-hub only):${NC}"
  echo "  • ArgoCD Application '${APP_NAME}' from ${ARGOCD_NS}"
  echo "  • Namespace ${RHDH_NS} and ALL its resources"
  echo "    (Backstage CR, PostgresCluster CR, all PVCs, Secrets, ConfigMaps, Jobs…)"
  echo "  • ClusterRoles/CRBs created by this chart (instance=${APP_NAME})"
  echo "  • Remote cluster SAs/CRBs: rhdh-dcs-reader, rhdh-cas-reader"
  echo "  • Git: application.yaml + values.yaml reset to placeholder state"
  echo "  • Proxy cluster catalog-info files removed from fusion-ai-discovery/clusters/"
  if [[ "$DELETE_OPERATORS" == "true" ]]; then
  echo ""
  echo -e "  ${RED}DELETE_OPERATORS=true — will also remove:${NC}"
  echo "  • RHDH Operator subscription/CSV in ${RHDH_OPERATOR_NS}"
  echo "  • PostgreSQL Operator subscription/CSV in ${PG_OPERATOR_NS}"
  echo "  • Namespaces: ${RHDH_OPERATOR_NS}, ${PG_OPERATOR_NS}"
  echo -e "  ${YELLOW}WARNING: these operators may be used by other workloads!${NC}"
  else
  echo ""
  echo -e "  ${GREEN}Operators and their namespaces are NOT touched${NC} (set DELETE_OPERATORS=true to include them)"
  fi
  echo ""
  echo -e "  ${YELLOW}Flags in effect:${NC}"
  echo "    FORCE              = ${FORCE}"
  echo "    DRY_RUN            = ${DRY_RUN}"
  echo "    DELETE_OPERATORS   = ${DELETE_OPERATORS}"
  echo "    SKIP_GIT_PUSH      = ${SKIP_GIT_PUSH}"
  echo "    SKIP_REMOTE_CLEANUP= ${SKIP_REMOTE_CLEANUP}"
  echo ""

  confirm "Are you absolutely sure you want to proceed with the full cleanup?"
}

# ── Phase C2: ArgoCD Application ─────────────────────────────────────────────
phase_c2_argocd() {
  step "Phase C2 — Remove ArgoCD Application"

  if ! oc get application.argoproj.io "${APP_NAME}" -n "${ARGOCD_NS}" &>/dev/null; then
    skip "ArgoCD Application '${APP_NAME}' not found in ${ARGOCD_NS} — nothing to delete"
    return
  fi

  # 1. Disable automated sync so ArgoCD stops reconciling while we delete
  info "Disabling automated sync on '${APP_NAME}' to prevent re-creation during teardown..."
  run oc patch application.argoproj.io "${APP_NAME}" \
    -n "${ARGOCD_NS}" --type=merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}'
  success "Automated sync disabled"

  # 2. Remove the resources-finalizer so deletion is not blocked by resource pruning
  info "Removing resources-finalizer from '${APP_NAME}'..."
  run oc patch application.argoproj.io "${APP_NAME}" \
    -n "${ARGOCD_NS}" --type=json \
    -p '[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
  success "Finalizer removed (or was already absent)"

  # 3. Delete the Application object itself
  info "Deleting ArgoCD Application '${APP_NAME}'..."
  run oc delete application.argoproj.io "${APP_NAME}" \
    -n "${ARGOCD_NS}" --wait=false 2>/dev/null || true

  if [[ "$DRY_RUN" != "true" ]]; then
    if wait_gone 60 oc get application.argoproj.io "${APP_NAME}" -n "${ARGOCD_NS}"; then
      success "ArgoCD Application '${APP_NAME}' deleted"
    else
      warn "ArgoCD Application still present after 60s — may be stuck; continuing"
    fi
  fi

  # 4. Remove any ArgoCD AppProject entries if a custom project was created
  info "Checking for custom AppProject referencing '${APP_NAME}'..."
  if oc get appproject.argoproj.io -n "${ARGOCD_NS}" --no-headers 2>/dev/null \
      | grep -q "${APP_NAME}"; then
    run oc delete appproject.argoproj.io "${APP_NAME}" \
      -n "${ARGOCD_NS}" 2>/dev/null || true
    success "AppProject '${APP_NAME}' deleted"
  else
    skip "No custom AppProject found"
  fi

  # 5. Clean up any ArgoCD repo secret for this repo (optional — warn only)
  info "Checking ArgoCD repository secrets..."
  REPO_SECRETS=$(oc get secret -n "${ARGOCD_NS}" \
    -l "argocd.argoproj.io/secret-type=repository" \
    --no-headers 2>/dev/null | awk '{print $1}' || true)
  if [[ -n "$REPO_SECRETS" ]]; then
    warn "Found ArgoCD repo secret(s): ${REPO_SECRETS}"
    warn "These are shared — remove manually if no other Applications use them:"
    warn "  oc delete secret <name> -n ${ARGOCD_NS}"
  fi

  success "Phase C2 complete"
}

# ── Phase C3: RHDH Namespace ──────────────────────────────────────────────────
phase_c3_rhdh_namespace() {
  step "Phase C3 — Remove all resources in ${RHDH_NS}"

  if ! oc get namespace "${RHDH_NS}" &>/dev/null; then
    skip "Namespace ${RHDH_NS} does not exist — skipping"
    return
  fi

  # 3a. Delete Backstage CR (operator-managed — must go first to prevent re-creation)
  info "Deleting Backstage custom resources..."
  if oc get crd backstages.rhdh.redhat.com &>/dev/null; then
    BACKSTAGE_CRS=$(oc get backstage -n "${RHDH_NS}" \
      -o name --no-headers 2>/dev/null || true)
    if [[ -n "$BACKSTAGE_CRS" ]]; then
      run oc delete backstage --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
      info "Waiting for Backstage CR deletion (up to 60s)..."
      if [[ "$DRY_RUN" != "true" ]]; then
        wait_gone 60 oc get backstage -n "${RHDH_NS}" --no-headers || \
          warn "Backstage CR still present after 60s — operator may be unresponsive"
      fi
      success "Backstage CRs deleted"
    else
      skip "No Backstage CR instances found"
    fi
  else
    skip "Backstage CRD not installed — skipping"
  fi

  # 3b. Delete PostgresCluster CR (operator-managed — terminates all PG pods + PVCs)
  info "Deleting PostgresCluster custom resources..."
  if oc get crd postgresclusters.postgres-operator.crunchydata.com &>/dev/null; then
    PG_CRS=$(oc get postgrescluster -n "${RHDH_NS}" \
      -o name --no-headers 2>/dev/null || true)
    if [[ -n "$PG_CRS" ]]; then
      run oc delete postgrescluster --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
      info "Waiting for PostgresCluster deletion (up to 90s)..."
      if [[ "$DRY_RUN" != "true" ]]; then
        wait_gone 90 oc get postgrescluster -n "${RHDH_NS}" --no-headers || \
          warn "PostgresCluster still present after 90s — may need manual finalizer removal"
      fi
      success "PostgresCluster CRs deleted"
    else
      skip "No PostgresCluster instances found"
    fi
  else
    skip "PostgresCluster CRD not installed — skipping"
  fi

  # 3c. Delete all PVCs (including dynamic-plugins-root and postgres data/backup volumes)
  info "Deleting all PVCs in ${RHDH_NS}..."
  PVC_LIST=$(oc get pvc -n "${RHDH_NS}" \
    --no-headers 2>/dev/null | awk '{print $1}' || true)
  if [[ -n "$PVC_LIST" ]]; then
    info "  PVCs found: $(echo "${PVC_LIST}" | tr '\n' ' ')"
    run oc delete pvc --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
    # Remove stuck finalizers
    if [[ "$DRY_RUN" != "true" ]]; then
      sleep 3
      for pvc in $PVC_LIST; do
        if oc get pvc "$pvc" -n "${RHDH_NS}" &>/dev/null; then
          warn "PVC ${pvc} stuck — patching out finalizers"
          oc patch pvc "$pvc" -n "${RHDH_NS}" \
            --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]' \
            2>/dev/null || true
        fi
      done
    fi
    success "All PVCs deleted"
  else
    skip "No PVCs found in ${RHDH_NS}"
  fi

  # 3d. Delete all named Secrets (fusion-cluster-tokens, github-auth-secret, rhdh-rhoai-connector-token, helm release secrets)
  info "Deleting Secrets in ${RHDH_NS}..."
  for secret_name in \
    fusion-cluster-tokens \
    github-auth-secret \
    rhdh-rhoai-connector-token; do
    if oc get secret "$secret_name" -n "${RHDH_NS}" &>/dev/null; then
      run oc delete secret "$secret_name" -n "${RHDH_NS}" 2>/dev/null || true
      success "Secret '${secret_name}' deleted"
    fi
  done
  # Sweep remaining Helm-managed and operator-managed secrets.
  # IMPORTANT: use --wait=false — system secrets (default-token-*, builder-token-*, etc.)
  # are continuously re-injected by OpenShift controllers; waiting for them to disappear
  # will block forever.  The namespace delete in step 3k cleans up whatever remains.
  run oc delete secret --all -n "${RHDH_NS}" \
    --wait=false 2>/dev/null || true
  success "All secrets deletion triggered (--wait=false)"

  # 3e. Delete application-owned ConfigMaps by name.
  # We deliberately avoid "oc delete configmap --all" because OpenShift continuously
  # re-injects several system ConfigMaps into every namespace:
  #   kube-root-ca.crt, openshift-service-ca.crt, odh-trusted-ca-bundle,
  #   odh-kserve-custom-ca-bundle
  # Deleting those with --wait (the default) blocks forever because the controller
  # immediately recreates them.  We delete only the app-owned ones by name, then
  # let the namespace delete (step 3k) sweep up anything left.
  info "Deleting ConfigMaps in ${RHDH_NS}..."
  APP_CONFIGMAPS=(
    app-config-fusion-blueprints
    app-config-fusion-services
    developer-hub-home-quick-access
    developerhub-app-config
    developerhub-postgres-backup
    fusion-ai-clusters
    fusion-ai-platform-entities
    fusion-ai-services-templates
    fusion-dynamic-plugins
    fusion-getting-started-quickstart
    fusion-templates
  )
  for cm in "${APP_CONFIGMAPS[@]}"; do
    run oc delete configmap "$cm" -n "${RHDH_NS}" \
      --ignore-not-found --wait=false 2>/dev/null || true
  done
  # Also sweep any remaining Helm-labelled ConfigMaps (non-blocking)
  run oc delete configmap \
    -l "app.kubernetes.io/managed-by=Helm" \
    -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  run oc delete configmap \
    -l "app.kubernetes.io/managed-by=argocd" \
    -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  success "Application ConfigMaps deleted (system CMs skipped — namespace delete handles them)"

  # 3f. Delete all Jobs (operator-check, namespace-labeler, createdb, etc.)
  info "Deleting Jobs in ${RHDH_NS}..."
  run oc delete job --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  success "Jobs deleted"

  # 3g. Delete Routes, Services, Deployments, StatefulSets
  # Use --wait=false throughout — OpenShift controllers (service-ca, etc.)
  # can re-inject resources into a live namespace; waiting for deletion causes
  # an indefinite hang.  The namespace delete in 3k sweeps everything left.
  info "Deleting Routes, Services, Deployments, StatefulSets in ${RHDH_NS}..."
  run oc delete route       --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  run oc delete service     --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  run oc delete deployment  --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  run oc delete statefulset --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  success "Routes, Services, Deployments, StatefulSets deletion triggered"

  # 3h. Delete RBAC within namespace
  info "Deleting Roles, RoleBindings, ServiceAccounts in ${RHDH_NS}..."
  run oc delete role           --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  run oc delete rolebinding    --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  run oc delete serviceaccount --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  success "Namespace RBAC deletion triggered"

  # 3i. Delete NetworkPolicies and ResourceQuotas
  info "Deleting NetworkPolicies and ResourceQuotas in ${RHDH_NS}..."
  run oc delete networkpolicy --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  run oc delete resourcequota --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  run oc delete limitrange    --all -n "${RHDH_NS}" --wait=false 2>/dev/null || true
  success "NetworkPolicies / Quotas deletion triggered"

  # 3j. Delete ClusterRoles and ClusterRoleBindings scoped ONLY to this app.
  # We use the instance label (app.kubernetes.io/instance=fusion-developer-hub)
  # rather than managed-by=Helm — that broader label would match every Helm
  # release on the cluster and delete unrelated cluster-scoped RBAC.
  info "Deleting ClusterRoles/ClusterRoleBindings for ${APP_NAME}..."
  run oc delete clusterrole \
    -l "app.kubernetes.io/instance=${APP_NAME}" 2>/dev/null || true
  run oc delete clusterrolebinding \
    -l "app.kubernetes.io/instance=${APP_NAME}" 2>/dev/null || true
  # Named resources created by the chart that may not carry the label
  for _name in \
    "${APP_NAME}-namespace-labeler" \
    "${APP_NAME}-argocd-rbac" \
    "rhdh-rhoai-connector"; do
    run oc delete clusterrolebinding "$_name" --ignore-not-found 2>/dev/null || true
    run oc delete clusterrole        "$_name" --ignore-not-found 2>/dev/null || true
  done
  success "ClusterRoles/ClusterRoleBindings deleted"

  # 3k. Delete the namespace itself
  info "Deleting namespace ${RHDH_NS}..."
  run oc delete namespace "${RHDH_NS}" --wait=false 2>/dev/null || true
  if [[ "$DRY_RUN" != "true" ]]; then
    info "Waiting for namespace deletion (up to 120s)..."
    if wait_gone 120 oc get namespace "${RHDH_NS}"; then
      success "Namespace ${RHDH_NS} deleted"
    else
      warn "Namespace stuck in Terminating — attempting finalizer patch"
      oc get namespace "${RHDH_NS}" -o json 2>/dev/null \
        | python3 -c "
import sys, json
ns = json.load(sys.stdin)
ns['spec']['finalizers'] = []
print(json.dumps(ns))
" | oc replace --raw "/api/v1/namespaces/${RHDH_NS}/finalize" -f - 2>/dev/null || true
      sleep 5
      if oc get namespace "${RHDH_NS}" &>/dev/null; then
        warn "Namespace ${RHDH_NS} still exists — manual removal may be needed"
      else
        success "Namespace ${RHDH_NS} removed after finalizer patch"
      fi
    fi
  fi

  success "Phase C3 complete"
}

# ── Phase C4: Operator cleanup (opt-in only) ─────────────────────────────────
phase_c4_operators() {
  step "Phase C4 — Operator subscription/CSV cleanup"

  if [[ "${DELETE_OPERATORS}" != "true" ]]; then
    skip "DELETE_OPERATORS=false — operators left untouched (they may be shared)."
    skip "Re-run with DELETE_OPERATORS=true to also remove RHDH and PostgreSQL operators."
    return
  fi

  warn "DELETE_OPERATORS=true — removing RHDH and PostgreSQL operators."
  warn "This will break any OTHER workload that depends on these operators."
  confirm "Confirm operator deletion?"

  # RHDH operator
  info "Removing RHDH Operator subscription..."
  if oc get subscription rhdh-operator -n "${RHDH_OPERATOR_NS}" &>/dev/null; then
    run oc delete subscription rhdh-operator \
      -n "${RHDH_OPERATOR_NS}" 2>/dev/null || true
    success "RHDH Operator subscription deleted"
  else
    skip "RHDH Operator subscription not found"
  fi

  info "Removing RHDH Operator CSV(s)..."
  RHDH_CSVS=$(oc get csv -n "${RHDH_OPERATOR_NS}" \
    --no-headers 2>/dev/null \
    | grep -i "rhdh-operator" | awk '{print $1}' || true)
  if [[ -n "$RHDH_CSVS" ]]; then
    for csv in $RHDH_CSVS; do
      run oc delete csv "$csv" -n "${RHDH_OPERATOR_NS}" 2>/dev/null || true
    done
    success "RHDH Operator CSV(s) deleted"
  else
    skip "No RHDH CSV found"
  fi

  # PostgreSQL operator
  info "Removing PostgreSQL Operator subscription..."
  for sub_name in postgresql pgo crunchy-postgres; do
    if oc get subscription "$sub_name" -n "${PG_OPERATOR_NS}" &>/dev/null; then
      run oc delete subscription "$sub_name" \
        -n "${PG_OPERATOR_NS}" 2>/dev/null || true
      success "PostgreSQL Operator subscription '${sub_name}' deleted"
      break
    fi
  done

  info "Removing PostgreSQL Operator CSV(s)..."
  PG_CSVS=$(oc get csv -n "${PG_OPERATOR_NS}" \
    --no-headers 2>/dev/null \
    | grep -i "postgres" | awk '{print $1}' || true)
  if [[ -n "$PG_CSVS" ]]; then
    for csv in $PG_CSVS; do
      run oc delete csv "$csv" -n "${PG_OPERATOR_NS}" 2>/dev/null || true
    done
    success "PostgreSQL Operator CSV(s) deleted"
  else
    skip "No PostgreSQL CSV found"
  fi

  # Remove OperatorGroups
  for ns in "${RHDH_OPERATOR_NS}" "${PG_OPERATOR_NS}"; do
    OGS=$(oc get operatorgroup -n "$ns" \
      --no-headers 2>/dev/null | awk '{print $1}' || true)
    for og in $OGS; do
      run oc delete operatorgroup "$og" -n "$ns" 2>/dev/null || true
    done
  done
  success "OperatorGroups cleaned"

  success "Phase C4 complete"
}

# ── Phase C5: Operator namespaces (opt-in only) ───────────────────────────────
phase_c5_operator_namespaces() {
  step "Phase C5 — Operator namespace deletion"

  if [[ "${DELETE_OPERATORS}" != "true" ]]; then
    skip "DELETE_OPERATORS=false — operator namespaces left untouched."
    return
  fi

  for ns in "${RHDH_OPERATOR_NS}" "${PG_OPERATOR_NS}"; do
    if oc get namespace "$ns" &>/dev/null; then
      info "Deleting namespace ${ns}..."
      run oc delete namespace "$ns" --wait=false 2>/dev/null || true
      if [[ "$DRY_RUN" != "true" ]]; then
        if wait_gone 90 oc get namespace "$ns"; then
          success "Namespace ${ns} deleted"
        else
          warn "Namespace ${ns} stuck in Terminating — check for stuck finalizers"
          warn "  oc get namespace ${ns} -o yaml | grep finalizers"
        fi
      fi
    else
      skip "Namespace ${ns} does not exist"
    fi
  done

  success "Phase C5 complete"
}

# ── Phase C6: Remote Fusion cluster cleanup ───────────────────────────────────
# Reads the cluster list from values.yaml, prompts login for each cluster,
# and removes the SA + CRB that 01-deploy-gitops-cluster.sh created.
phase_c6_remote_clusters() {
  step "Phase C6 — Remote Fusion cluster cleanup"

  if [[ "${SKIP_REMOTE_CLEANUP}" == "true" ]]; then
    skip "SKIP_REMOTE_CLEANUP=true — skipping remote SA teardown"
    return
  fi

  if [[ ! -f "$VALUES_YAML" ]]; then
    warn "values.yaml not found (${VALUES_YAML}) — skipping remote cleanup"
    return
  fi

  # Extract cluster names from values.yaml (only real entries — not placeholders)
  CLUSTER_NAMES=$(python3 - "$VALUES_YAML" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
# Match "- name: <word>" that does NOT contain < or > (i.e. not a placeholder)
for m in re.finditer(r'^\s+-\s+name:\s+([A-Za-z0-9_-]+)\s*$', content, re.MULTILINE):
    print(m.group(1))
PYEOF
  )

  if [[ -z "$CLUSTER_NAMES" ]]; then
    skip "No real cluster entries found in values.yaml — nothing to clean on remote clusters"
    return
  fi

  info "Cluster entries found in values.yaml: $(echo "${CLUSTER_NAMES}" | tr '\n' ' ')"

  for CLUSTER_ID in $CLUSTER_NAMES; do
    echo ""
    info "─── Cluster: ${CLUSTER_ID} ───"

    # Extract DCS/CAS namespaces for this cluster from values.yaml
    DCS_NS=$(python3 - "$VALUES_YAML" "$CLUSTER_ID" <<'PYEOF'
import sys, re
path, cid = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
# Find the cluster block and extract dcs namespace
in_cluster = False
for line in content.splitlines():
    if re.search(rf'^\s+-\s+name:\s+{re.escape(cid)}\s*$', line):
        in_cluster = True
    elif in_cluster and re.match(r'^\s+-\s+name:', line) and f'name: {cid}' not in line:
        break
    if in_cluster and re.search(r'^\s+namespace:\s+\S', line):
        print(line.split('namespace:')[1].strip())
        break
PYEOF
    )
    CAS_NS=$(python3 - "$VALUES_YAML" "$CLUSTER_ID" <<'PYEOF'
import sys, re
path, cid = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
in_cluster = False
found_dcs = False
for line in content.splitlines():
    if re.search(rf'^\s+-\s+name:\s+{re.escape(cid)}\s*$', line):
        in_cluster = True
    elif in_cluster and re.match(r'^\s+-\s+name:', line) and f'name: {cid}' not in line:
        break
    if in_cluster and re.search(r'^\s+namespace:\s+\S', line):
        if not found_dcs:
            found_dcs = True
        else:
            print(line.split('namespace:')[1].strip())
            break
PYEOF
    )

    DCS_NS="${DCS_NS:-ibm-data-cataloging}"
    CAS_NS="${CAS_NS:-ibm-cas}"

    OCP_API_URL=$(python3 - "$VALUES_YAML" "$CLUSTER_ID" <<'PYEOF'
import sys, re
path, cid = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
in_cluster = False
for line in content.splitlines():
    if re.search(rf'^\s+-\s+name:\s+{re.escape(cid)}\s*$', line):
        in_cluster = True
    elif in_cluster and re.match(r'^\s+-\s+name:', line) and f'name: {cid}' not in line:
        break
    if in_cluster and 'ocpApiUrl:' in line:
        print(line.split('ocpApiUrl:')[1].strip())
        break
PYEOF
    )

    info "  Cluster API : ${OCP_API_URL:-<not found in values.yaml>}"
    info "  DCS NS      : ${DCS_NS}"
    info "  CAS NS      : ${CAS_NS}"

    if [[ "$DRY_RUN" == "true" ]]; then
      echo -e "${YELLOW}[DRY-RUN]${NC} Would log in to remote cluster ${CLUSTER_ID} and remove:"
      echo "  SA  rhdh-dcs-reader / Secret rhdh-dcs-reader-token  in ${DCS_NS}"
      echo "  SA  rhdh-cas-reader / Secret rhdh-cas-reader-token  in ${CAS_NS}"
      echo "  CRB rhdh-dcs-reader"
      echo "  CRB rhdh-cas-reader"
      continue
    fi

    if [[ "$FORCE" != "true" ]]; then
      echo ""
      info "Log in to remote cluster ${CLUSTER_ID} now."
      info "Run: oc login --token=<token> --server=${OCP_API_URL:-<api-url>}"
      read -r -p "  Press Enter once logged in (or type 'skip' to skip this cluster): " reply
      [[ "$reply" == "skip" ]] && { skip "Skipping ${CLUSTER_ID}"; continue; }
    fi

    if ! oc whoami &>/dev/null; then
      warn "Not logged in to a cluster — skipping ${CLUSTER_ID}"
      continue
    fi
    CURRENT_SERVER=$(oc whoami --show-server 2>/dev/null || echo "")
    info "Logged in as: $(oc whoami)  server: ${CURRENT_SERVER}"

    # DCS SA / Secret / CRB
    info "  Removing DCS token secret rhdh-dcs-reader-token in ${DCS_NS}..."
    oc delete secret rhdh-dcs-reader-token \
      -n "${DCS_NS}" 2>/dev/null && \
      success "  Secret rhdh-dcs-reader-token deleted" || \
      skip "  Secret rhdh-dcs-reader-token not found"

    info "  Removing DCS ServiceAccount rhdh-dcs-reader in ${DCS_NS}..."
    oc delete serviceaccount rhdh-dcs-reader \
      -n "${DCS_NS}" 2>/dev/null && \
      success "  SA rhdh-dcs-reader deleted" || \
      skip "  SA rhdh-dcs-reader not found"

    info "  Removing DCS ClusterRoleBinding rhdh-dcs-reader..."
    oc delete clusterrolebinding rhdh-dcs-reader \
      2>/dev/null && \
      success "  CRB rhdh-dcs-reader deleted" || \
      skip "  CRB rhdh-dcs-reader not found"

    # CAS SA / Secret / CRB
    info "  Removing CAS token secret rhdh-cas-reader-token in ${CAS_NS}..."
    oc delete secret rhdh-cas-reader-token \
      -n "${CAS_NS}" 2>/dev/null && \
      success "  Secret rhdh-cas-reader-token deleted" || \
      skip "  Secret rhdh-cas-reader-token not found"

    info "  Removing CAS ServiceAccount rhdh-cas-reader in ${CAS_NS}..."
    oc delete serviceaccount rhdh-cas-reader \
      -n "${CAS_NS}" 2>/dev/null && \
      success "  SA rhdh-cas-reader deleted" || \
      skip "  SA rhdh-cas-reader not found"

    info "  Removing CAS ClusterRoleBinding rhdh-cas-reader..."
    oc delete clusterrolebinding rhdh-cas-reader \
      2>/dev/null && \
      success "  CRB rhdh-cas-reader deleted" || \
      skip "  CRB rhdh-cas-reader not found"

    success "Remote cluster ${CLUSTER_ID} cleaned"
  done

  # Remind operator to switch back to the RHDH cluster
  if [[ "$DRY_RUN" != "true" && "$FORCE" != "true" ]]; then
    echo ""
    info "Log back in to the RHDH cluster now before continuing."
    read -r -p "  Press Enter once you are logged in to the RHDH cluster..."
    oc whoami &>/dev/null || error "Not logged in to an OCP cluster."
  fi

  success "Phase C6 complete"
}

# ── Phase C7: Git file reset ──────────────────────────────────────────────────
phase_c7_git_reset() {
  step "Phase C7 — Reset Git files to placeholder state"

  # ── 7a. application.yaml ─────────────────────────────────────────────────────
  info "Resetting application.yaml to placeholder state..."
  if [[ -f "$APP_YAML" ]]; then
    cat > "$APP_YAML" <<'YAML'
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fusion-developer-hub
  # ArgoCD namespace: OpenShift GitOps default is openshift-gitops
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    environment: production
    app.kubernetes.io/managed-by: argocd

spec:
  project: default
  source:
    # REQUIRED: Replace with your Git repository URL
    repoURL: https://github.ibm.com/<org>/<repo>
    path: quickstarts/fusion-developerhub/deploy/helm
    # REQUIRED: Replace with your target branch
    targetRevision: <branch>
    helm:
      valueFiles:
        - values.yaml
        - environments/prod/values.yaml
      valuesObject:
        global:
          # REQUIRED: OCP wildcard domain
          # Run: oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}'
          wildcardDomain: <apps.your-cluster-domain>
        developerHub:
          storage:
            # REQUIRED: RWX StorageClass — leave empty to use cluster default
            storageClassName: ""
        argocd:
          enabled: true
          rbac:
            enabled: true

  destination:
    server: https://kubernetes.default.svc
    namespace: fusion-developer-hub

  revisionHistoryLimit: 10

  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - RespectIgnoreDifferences=true
      - Replace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  ignoreDifferences:
    - group: operators.coreos.com
      kind: Subscription
      jsonPointers:
        - /status
        - /spec/installPlanApproval
    - group: operators.coreos.com
      kind: InstallPlan
      jsonPointers:
        - /status
    - group: operators.coreos.com
      kind: ClusterServiceVersion
      jsonPointers:
        - /status
        - /metadata/annotations
    - group: rhdh.redhat.com
      kind: Backstage
      jsonPointers:
        - /status
    - group: postgres-operator.crunchydata.com
      kind: PostgresCluster
      jsonPointers:
        - /status

  info:
    - name: 'Add a CAS/DCS Cluster'
      value: |
        Run: ./01-deploy-gitops-cluster.sh
        Or edit environments/prod/values.yaml:
          developerHub.fusionServices.clusters:
            - name: <cluster-id>
              ocpApiUrl: https://api.<cluster-domain>:6443
YAML
    success "application.yaml reset to placeholders"
  else
    warn "application.yaml not found at ${APP_YAML} — skipping"
  fi

  # ── 7b. values.yaml ──────────────────────────────────────────────────────────
  info "Resetting values.yaml cluster entries, storageClassNames and wildcardDomain..."
  if [[ -f "$VALUES_YAML" ]]; then
    python3 - "$VALUES_YAML" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# 1. Reset wildcardDomain to placeholder
content = re.sub(
    r'(wildcardDomain:\s*).*',
    r'\1<apps.your-cluster-domain>',
    content
)

# 2. Reset ALL storageClassName values to empty string (default)
content = re.sub(
    r'(storageClassName:\s*)["\']?[A-Za-z0-9._/-]+["\']?',
    r'\1""',
    content
)

# 3. Remove all real cluster entries under fusionServices.clusters
# Strategy: locate the "    clusters:" key, then walk line-by-line removing
# only list items (lines starting with 6+ spaces) that belong to it.
# Stop as soon as we hit a line with ≤ 4 spaces of indent (a sibling or parent
# key at the same level as "clusters:") — that line belongs to a different block
# and must NOT be touched.
lines = content.splitlines(keepends=True)
out = []
in_clusters = False
skip_item   = False   # True while consuming lines of one cluster entry

i = 0
while i < len(lines):
    line = lines[i]

    # Detect the "    clusters:" key (4-space indent — child of fusionServices)
    if re.match(r'^    clusters:\s*$', line):
        in_clusters = True
        out.append(line)
        i += 1
        continue

    if in_clusters:
        # A line with ≤ 4 spaces indent is a sibling/parent — clusters block ended
        if re.match(r'^(\S|  \S|    \S)', line):
            in_clusters = False
            skip_item   = False
            out.append(line)
            i += 1
            continue

        # New cluster list item: "      - name: <real-word>" at 6-space indent
        # If name contains < or > it is a placeholder comment — keep it.
        m_item = re.match(r'^      - name:\s+([A-Za-z0-9_-]+)\s*$', line)
        if m_item:
            skip_item = True   # start skipping this entry's lines
            i += 1
            continue

        # A "      - " item that is NOT "- name:" ends the previous skipped entry
        # (e.g. a sentinel comment line "      # Add additional clusters below.")
        if re.match(r'^      [#-]', line):
            skip_item = False
            out.append(line)
            i += 1
            continue

        # Continuation line belonging to the current cluster entry — skip it
        if skip_item and re.match(r'^       ', line):
            i += 1
            continue

        # Any other line inside the clusters block (blank lines, comments)
        skip_item = False
        out.append(line)
        i += 1
        continue

    out.append(line)
    i += 1

content = ''.join(out)

# 4. Ensure the clusters: key has the sentinel placeholder comment so the file
# remains valid even when no entries are present.
# Replace "    clusters:\n" with the same line + placeholder comment when the
# comment is missing (idempotent).
content = re.sub(
    r'^(    clusters:[ \t]*\n)(?![ \t]*# Add additional clusters)',
    r'\1      # Add additional clusters below.\n',
    content,
    count=1,
    flags=re.MULTILINE
)

with open(path, 'w') as f:
    f.write(content)

print("values.yaml reset: wildcardDomain=<placeholder>, storageClassNames=\"\", clusters cleared")
PYEOF
    success "values.yaml reset to placeholder state"
  else
    warn "values.yaml not found at ${VALUES_YAML} — skipping"
  fi

  # ── 7c. Remove proxy-cluster catalog-info files ───────────────────────────────
  info "Removing proxy-cluster catalog-info files from fusion-ai-discovery/clusters/..."
  if [[ -d "$CLUSTERS_DIR" ]]; then
    # Remove every sub-directory that is NOT the cluster-template skeleton
    while IFS= read -r -d '' cluster_dir; do
      dir_name="$(basename "$cluster_dir")"
      if [[ "$dir_name" != "cluster-template" ]]; then
        info "  Removing clusters/${dir_name}/"
        run rm -rf "$cluster_dir"
        success "  Removed: clusters/${dir_name}/"
      fi
    done < <(find "$CLUSTERS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
  else
    skip "clusters/ directory not found at ${CLUSTERS_DIR}"
  fi

  # ── 7d. Commit and push ───────────────────────────────────────────────────────
  if [[ "${SKIP_GIT_PUSH}" == "true" ]]; then
    warn "SKIP_GIT_PUSH=true — local resets done but NOT committed/pushed"
    warn "Run manually: git add -A && git commit -m 'cleanup: reset to placeholder state' && git push"
    return
  fi

  cd "${REPO_ROOT}"

  local changed_files=()
  [[ -f "$APP_YAML"    ]] && git diff --name-only -- \
    "quickstarts/fusion-developerhub/deploy/gitops/environments/prod/application.yaml" \
    | grep -q . && changed_files+=("quickstarts/fusion-developerhub/deploy/gitops/environments/prod/application.yaml")
  [[ -f "$VALUES_YAML" ]] && git diff --name-only -- \
    "quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml" \
    | grep -q . && changed_files+=("quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml")

  # Also capture deleted cluster files
  DELETED=$(git ls-files --deleted \
    "quickstarts/fusion-developerhub/fusion-ai-discovery/clusters/" 2>/dev/null || true)
  [[ -n "$DELETED" ]] && changed_files+=($DELETED)

  if [[ ${#changed_files[@]} -eq 0 ]]; then
    info "No Git changes detected — files already at placeholder state"
    return
  fi

  info "Staging files for commit..."
  run git add \
    "quickstarts/fusion-developerhub/deploy/gitops/environments/prod/application.yaml" \
    "quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml" \
    "quickstarts/fusion-developerhub/fusion-ai-discovery/clusters/" 2>/dev/null || true

  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  run git commit -m "chore(cleanup): reset fusion-developer-hub to placeholder state

- application.yaml: repoURL, targetRevision, wildcardDomain, storageClassName → placeholders
- values.yaml: wildcardDomain → placeholder, all storageClassNames → \"\",
  fusionServices.clusters cleared of all real entries
- fusion-ai-discovery/clusters/: all proxy-cluster catalog-info files removed
  (cluster-template skeleton preserved)

Cleanup performed by 99-cleanup-gitops-cluster.sh"

  run git push origin "${CURRENT_BRANCH}"
  success "Cleanup state committed and pushed to ${CURRENT_BRANCH}"

  success "Phase C7 complete"
}

# ── Phase C8: Stale-entry audit ───────────────────────────────────────────────
phase_c8_audit() {
  step "Phase C8 — Stale-entry audit"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would audit residual resources across all touched namespaces"
    return
  fi

  local issues=0

  # ArgoCD Application
  if oc get application.argoproj.io "${APP_NAME}" -n "${ARGOCD_NS}" &>/dev/null; then
    warn "STALE: ArgoCD Application '${APP_NAME}' still exists in ${ARGOCD_NS}"
    (( issues++ )) || true
  else
    success "ArgoCD Application gone"
  fi

  # fusion-developer-hub namespace
  if oc get namespace "${RHDH_NS}" &>/dev/null; then
    NS_STATUS=$(oc get namespace "${RHDH_NS}" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$NS_STATUS" == "Terminating" ]]; then
      warn "Namespace ${RHDH_NS} still Terminating — this is normal, will complete shortly"
    else
      warn "STALE: Namespace ${RHDH_NS} still exists (status=${NS_STATUS})"
      (( issues++ )) || true
    fi
  else
    success "Namespace ${RHDH_NS} gone"
  fi

  # Operator namespaces — only audit if DELETE_OPERATORS was requested
  if [[ "${DELETE_OPERATORS}" == "true" ]]; then
    for ns in "${RHDH_OPERATOR_NS}" "${PG_OPERATOR_NS}"; do
      if oc get namespace "$ns" &>/dev/null; then
        NS_STATUS=$(oc get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [[ "$NS_STATUS" == "Terminating" ]]; then
          warn "Namespace ${ns} still Terminating — will complete shortly"
        else
          warn "STALE: Namespace ${ns} still exists (status=${NS_STATUS})"
          (( issues++ )) || true
        fi
      else
        success "Namespace ${ns} gone"
      fi
    done
  fi

  # PVCs in RHDH NS (may linger if namespace is Terminating — acceptable)
  PVCS=$(oc get pvc -n "${RHDH_NS}" --no-headers 2>/dev/null | wc -l || echo 0)
  if [[ "$PVCS" -gt 0 ]]; then
    warn "STALE: ${PVCS} PVC(s) still present in ${RHDH_NS}"
    oc get pvc -n "${RHDH_NS}" 2>/dev/null | sed 's/^/    /'
    (( issues++ )) || true
  else
    success "No PVCs remaining in ${RHDH_NS}"
  fi

  # Cluster-scoped RBAC
  for crb in rhdh-dcs-reader rhdh-cas-reader "${APP_NAME}-namespace-labeler"; do
    if oc get clusterrolebinding "$crb" &>/dev/null; then
      warn "STALE: ClusterRoleBinding '${crb}' still exists"
      (( issues++ )) || true
    else
      success "CRB ${crb} gone"
    fi
  done

  # values.yaml cluster entries
  if [[ -f "$VALUES_YAML" ]]; then
    REMAINING_CLUSTERS=$(python3 - "$VALUES_YAML" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
entries = re.findall(r'^\s+-\s+name:\s+([A-Za-z0-9_-]+)\s*$', content, re.MULTILINE)
print('\n'.join(entries))
PYEOF
    )
    if [[ -n "$REMAINING_CLUSTERS" ]]; then
      warn "STALE: values.yaml still contains cluster entries:"
      echo "$REMAINING_CLUSTERS" | sed 's/^/    /'
      (( issues++ )) || true
    else
      success "values.yaml clusters[] is empty"
    fi

    # storageClassName check
    SC_ENTRIES=$(grep -n "storageClassName:" "$VALUES_YAML" 2>/dev/null \
      | grep -v '""' | grep -v "^.*#" || true)
    if [[ -n "$SC_ENTRIES" ]]; then
      warn "STALE: Non-empty storageClassName entries remain in values.yaml:"
      echo "$SC_ENTRIES" | sed 's/^/    /'
      (( issues++ )) || true
    else
      success "All storageClassNames reset to empty string"
    fi

    # wildcardDomain check
    WD=$(grep "wildcardDomain:" "$VALUES_YAML" 2>/dev/null | head -1 || true)
    if echo "$WD" | grep -qv "<apps.your-cluster-domain>"; then
      warn "STALE: wildcardDomain in values.yaml may not be fully reset: ${WD}"
    else
      success "wildcardDomain reset to placeholder"
    fi
  fi

  # Proxy-cluster catalog-info files
  LEFTOVER_CLUSTERS=$(find "${CLUSTERS_DIR}" -mindepth 2 -name "catalog-info.yaml" \
    ! -path "*/cluster-template/*" 2>/dev/null || true)
  if [[ -n "$LEFTOVER_CLUSTERS" ]]; then
    warn "STALE: Proxy-cluster catalog-info files still on disk:"
    echo "$LEFTOVER_CLUSTERS" | sed 's/^/    /'
    (( issues++ )) || true
  else
    success "No proxy-cluster catalog-info files remaining"
  fi

  echo ""
  if [[ $issues -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║              Cleanup Audit PASSED — Zero stale entries       ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  else
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║   Cleanup Audit: ${issues} issue(s) found — see warnings above     ║${NC}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    warn "Re-run the relevant phase or resolve manually, then re-run Phase C8 to confirm."
  fi

  success "Phase C8 complete"
}

# ── Final summary ─────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║    IBM Fusion Developer Hub — Cleanup Complete               ║${NC}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "  Cleaned (fusion-developer-hub only):"
  echo "    ✓ ArgoCD Application '${APP_NAME}' removed from ${ARGOCD_NS}"
  echo "    ✓ Namespace ${RHDH_NS} deleted (Backstage CR, PostgresCluster CR,"
  echo "      all PVCs, Secrets, ConfigMaps, Jobs, Routes, Services, RBAC)"
  echo "    ✓ ClusterRoles/CRBs scoped to instance=${APP_NAME}"
  echo "    ✓ Remote cluster SAs/CRBs removed (rhdh-dcs-reader, rhdh-cas-reader)"
  echo "    ✓ application.yaml reset to placeholder state"
  echo "    ✓ values.yaml: wildcardDomain=<placeholder>, storageClassNames=\"\","
  echo "      clusters=[] (all hardcoded entries removed)"
  echo "    ✓ Proxy-cluster catalog-info files removed from fusion-ai-discovery/clusters/"
  if [[ "${DELETE_OPERATORS}" == "true" ]]; then
  echo "    ✓ RHDH + PostgreSQL operator subscriptions/CSVs removed"
  echo "    ✓ Namespaces ${RHDH_OPERATOR_NS} and ${PG_OPERATOR_NS} deleted"
  else
  echo ""
  echo -e "  ${YELLOW}Operators untouched${NC} (shared — use DELETE_OPERATORS=true to remove them)"
  fi
  echo ""
  echo "  To redeploy:"
  echo "    ./01-deploy-gitops-cluster.sh"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}${RED}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║     IBM Fusion Developer Hub — Full Cleanup Script          ║"
  echo "║                   99-cleanup-gitops-cluster.sh              ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  phase_c1_preflight
  phase_c2_argocd
  phase_c3_rhdh_namespace
  phase_c4_operators
  phase_c5_operator_namespaces
  phase_c6_remote_clusters
  phase_c7_git_reset
  phase_c8_audit
  print_summary
}

main "$@"
