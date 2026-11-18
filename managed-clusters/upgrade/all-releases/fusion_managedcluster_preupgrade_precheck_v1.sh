#!/usr/bin/env bash
# start_Copyright_Notice
# Licensed Materials - Property of IBM
#
# IBM Fusion HCI 5639-SPS
# (C) Copyright IBM Corp. 2025, 2026 All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

# fusion_managedcluster_preupgrade_precheck_v1.sh
# READ-ONLY pre-upgrade readiness and health inspection tool for an IBM Fusion HCI hub
# and its ManagedClusters (spokes) running Fusion Addons (fusion-base, fusion-fdf,
# fusion-backup, fusion-gdp-rm). Hub-side checks apply to every ManagedCluster.
# Spoke access is automatic only for Hosted Control Plane (HCP) clusters; any other
# ManagedCluster needs its kubeconfig supplied with -s / SPOKE_KUBECONFIGS.
#
# Key Features:
#   1. Hub-side cluster & Data Foundation (Ceph) health verification.
#   2. Automatic discovery of all ManagedClusters. For HCP clusters, admin-kubeconfig
#      secrets are extracted automatically from HostedControlPlane namespaces; for other
#      clusters, spoke kubeconfigs must be supplied explicitly.
#   3. Comprehensive detection of stuck deletions (deletionTimestamp present) on:
#      - Hub StorageConsumers, Ceph clients, and subvolume groups
#      - Hub ManagedClusterAddOns and cascaded ManifestWorks
#      - Spoke SpectrumFusion, FSIs, StorageClients, Connections, and namespaces
#      - Stuck cleanup jobs and pods in Terminating state
#   4. ManagedCluster label vs StorageConsumer consistency audit (TS023322996 RCA check):
#      - Robust label key presence check (handles empty and boolean label values)
#      - Flags clusters where ManagedCluster was recreated or pruned without labels
#      - Verifies GitOps (ArgoCD / Flux) prune / selfHeal configuration
#   5. End-to-end Addon-to-Fusion-Operator workflow verification on each spoke cluster:
#      - Fusion Operator, CSVs, Deployments, Pods, and SpectrumFusion CR
#      - StorageClient & CSI heartbeat status-reporter checks
#      - Backup/Restore Connection CR and RemoteMount daemons
#   6. Full snapshot collection and upgrade readiness verdict (SAFE vs NOT SAFE).
#
#   7. Supplemental checks:
#      HostedCluster health (HCP only), ICSP/IDMS duplicate mirror sources,
#      NodePool readiness (HCP only),
#      Hub controller pod restarts, spoke Ready node quorum, in-flight backup/restore,
#      terminating AddOn namespaces/pods, terminating Storage AddOn PVCs, and the
#      OCP/Fusion/Data Foundation version matrix.
#
# Safety:
#   This script is strictly READ-ONLY. It only runs get/logs/describe/whoami commands.
#   It never creates, applies, patches, deletes, labels, or scales any resources.
#
# Compatibility:
#   Compatible with Bash 3.2+ (macOS / Linux) and POSIX shell environments.
#
# Usage:
#   ./fusion_managedcluster_preupgrade_precheck_v1.sh [OPTIONS]
#
# Environment variables:
#   HUB_KUBECONFIG      Path to hub cluster kubeconfig (defaults to KUBECONFIG or ~/.kube/config)
#   SPOKE_KUBECONFIGS   Optional space-separated list of explicit spoke kubeconfigs
#   NS_FUSION           Fusion namespace on Hub and Spoke (default: ibm-spectrum-fusion-ns)
#   NS_STORAGE          Storage namespace on Hub and Spoke (default: openshift-storage)
#   TARGET_CLUSTER      Optional single ManagedCluster name to inspect (default: all ManagedClusters)
#   SKIP_REDACTION      Set to 'true' to skip redacting tokens and secrets (default: false)
#   MIN_SPOKE_READY_NODES          Minimum Ready/schedulable nodes per spoke (default: 3)
#   CONTROLLER_RESTART_THRESHOLD   Max container restarts for Hub controllers (default: 50)

set -u

# --- Default Configuration ---
NS_FUSION="${NS_FUSION:-ibm-spectrum-fusion-ns}"
NS_STORAGE="${NS_STORAGE:-openshift-storage}"
NS_BACKUP="${NS_BACKUP:-ibm-backup-restore}"
HUB_KUBECONFIG="${HUB_KUBECONFIG:-${KUBECONFIG:-$HOME/.kube/config}}"
SPOKE_KUBECONFIGS="${SPOKE_KUBECONFIGS:-}"
TARGET_CLUSTER="${TARGET_CLUSTER:-}"
SKIP_REDACTION="${SKIP_REDACTION:-false}"
MIN_SPOKE_READY_NODES="${MIN_SPOKE_READY_NODES:-3}"
CONTROLLER_RESTART_THRESHOLD="${CONTROLLER_RESTART_THRESHOLD:-50}"
CLI_TOOL=""

# Formatting & Colors
if [ -t 1 ]; then
  C_RESET='\033[0m'
  C_RED='\033[91m'
  C_GREEN='\033[92m'
  C_YELLOW='\033[93m'
  C_BLUE='\033[94m'
  C_CYAN='\033[96m'
  C_BOLD='\033[1m'
else
  C_RESET=''
  C_RED=''
  C_GREEN=''
  C_YELLOW=''
  C_BLUE=''
  C_CYAN=''
  C_BOLD=''
fi

# Counters
stops=0
warns=0
passes=0

# CLI argument parsing
show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -k, --hub-kubeconfig <path>   Path to Hub cluster kubeconfig (default: \$HUB_KUBECONFIG or \$KUBECONFIG)
  -c, --cluster <name>          Inspect specific ManagedCluster name only
  -s, --spoke-kubeconfigs <files> Space-separated spoke kubeconfig file(s), quoted as one argument.
                                Required for non-HCP ManagedClusters (HCP kubeconfigs are fetched
                                automatically). Each path must contain the cluster name.
  --ns-fusion <namespace>       Fusion namespace (default: ibm-spectrum-fusion-ns)
  --ns-storage <namespace>      Storage namespace (default: openshift-storage)
  --skip-redaction, --no-redact Skip redacting tokens, keys, and onboarding tickets (default: redact)
  -h, --help                    Display this help message

Examples:
  # Check all ManagedClusters (HCP spoke kubeconfigs are extracted from Hub secrets automatically):
  HUB_KUBECONFIG=/root/hub-kubeconfig $(basename "$0")

  # Check a specific cluster:
  $(basename "$0") -k /root/hub-kubeconfig -c hcp-spoke1

  # Check non-HCP ManagedClusters by supplying their kubeconfigs:
  $(basename "$0") -k /root/hub-kubeconfig -s "/root/edge-site1.kubeconfig /root/edge-site2.kubeconfig"

Exit Codes:
  0: System is clean and SAFE TO UPGRADE (or warnings only, review advised)
  1: Usage or prerequisite error
  2: Critical STOP detected - NOT SAFE TO UPGRADE
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -k|--hub-kubeconfig) HUB_KUBECONFIG="$2"; shift 2 ;;
    -c|--cluster) TARGET_CLUSTER="$2"; shift 2 ;;
    -s|--spoke-kubeconfigs) SPOKE_KUBECONFIGS="$2"; shift 2 ;;
    --ns-fusion) NS_FUSION="$2"; shift 2 ;;
    --ns-storage) NS_STORAGE="$2"; shift 2 ;;
    --skip-redaction|--no-redact) SKIP_REDACTION=true; shift ;;
    -h|--help) show_help ;;
    *) echo "Unknown option: $1" >&2; show_help ;;
  esac
done

# Check CLI tool (prefer oc, fallback to kubectl)
if command -v oc >/dev/null 2>&1; then
  CLI_TOOL="oc"
elif command -v kubectl >/dev/null 2>&1; then
  CLI_TOOL="kubectl"
else
  echo -e "${C_RED}ERROR: Neither 'oc' nor 'kubectl' command found in PATH.${C_RESET}" >&2
  exit 1
fi

if [ -z "$HUB_KUBECONFIG" ] || [ ! -r "$HUB_KUBECONFIG" ]; then
  echo -e "${C_RED}ERROR: Hub kubeconfig not found or not readable at '${HUB_KUBECONFIG}'.${C_RESET}" >&2
  echo "Please set HUB_KUBECONFIG or pass -k /path/to/kubeconfig" >&2
  exit 1
fi

# Prepare Output Directory & Artifacts
out_dir="precheck-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out_dir/snapshot" "$out_dir/spoke_kubeconfigs" "$out_dir/clusters" || exit 1
summary="$out_dir/SUMMARY.txt"
report_file="$out_dir/WORKFLOW_STATUS_REPORT.txt"
matrix_file="$out_dir/matrix_rows.txt"
touch "$matrix_file"

# Cleanup trap for sensitive temporary spoke kubeconfigs
cleanup() {
  if [ -d "$out_dir/spoke_kubeconfigs" ]; then
    rm -f "$out_dir/spoke_kubeconfigs"/*.kubeconfig 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Logging Functions
pass() {
  passes=$((passes+1))
  printf "${C_GREEN}[PASS]${C_RESET} %s\n" "$*"
  printf "PASS  %s\n" "$*" >> "$summary"
}

warn() {
  warns=$((warns+1))
  printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*"
  printf "WARN  %s\n" "$*" >> "$summary"
}

stop() {
  stops=$((stops+1))
  printf "${C_RED}${C_BOLD}[STOP]${C_RESET} %s\n" "$*"
  printf "STOP  %s\n" "$*" >> "$summary"
}

note() {
  printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$*"
  printf "INFO  %s\n" "$*" >> "$summary"
}

section() {
  local title="$*"
  echo ""
  echo -e "${C_CYAN}${C_BOLD}========================================================================${C_RESET}"
  echo -e "${C_CYAN}${C_BOLD}  $title${C_RESET}"
  echo -e "${C_CYAN}${C_BOLD}========================================================================${C_RESET}"
  printf "\n========================================================================\n  %s\n========================================================================\n" "$title" >> "$summary"
}

hub() { "$CLI_TOOL" --kubeconfig "$HUB_KUBECONFIG" "$@"; }

save() {
  local f=$1
  shift
  {
    printf '# Timestamp: %s\n# Command: %s\n\n' "$(date -u +%FT%TZ)" "$*"
    "$@" 2>&1
  } >"$out_dir/$f"
}

# ------------------------------------------------------------------------------
# Supplemental check helpers (hub-side, per-spoke and per-addon)
# ------------------------------------------------------------------------------

# True (rc 0) if $1 is a member of the space-separated list $2
in_list() {
  local item=$1 x
  for x in $2; do [ "$x" = "$item" ] && return 0; done
  return 1
}

# Supported OCP/ODF versions per Fusion major.minor. Usage: matrix_lookup <fusion_mm> hub|spoke|odf
matrix_lookup() {
  case "$1:$2" in
    2.8:hub|2.8:spoke|2.8:odf)   echo "4.14" ;;
    2.9:hub)                     echo "4.15 4.16" ;;
    2.9:spoke)                   echo "4.14 4.15 4.16" ;;
    2.9:odf)                     echo "4.15 4.16" ;;
    2.14:hub)                    echo "4.16 4.17" ;;
    2.14:spoke)                  echo "4.15 4.16 4.17" ;;
    2.14:odf)                    echo "4.16 4.17" ;;
    3.0:hub|5.1:hub)             echo "4.18 4.20" ;;
    3.0:spoke|5.1:spoke)         echo "4.16 4.17 4.18 4.20" ;;
    3.0:odf|5.1:odf)             echo "4.18 4.20" ;;
    *) echo "" ;;
  esac
}

# Check 2: duplicate registry mirror sources across IDMS and ICSP. Usage: audit_mirror_sources <label> <kubeconfig>
audit_mirror_sources() {
  local label=$1 kc=$2 idms icsp dups
  idms=$("$CLI_TOOL" --kubeconfig "$kc" get imagedigestmirrorsets.config.openshift.io \
    -o jsonpath='{range .items[*].spec.imageDigestMirrors[*]}{.source}{"\n"}{end}' 2>/dev/null | grep . || true)
  icsp=$("$CLI_TOOL" --kubeconfig "$kc" get imagecontentsourcepolicies.operator.openshift.io \
    -o jsonpath='{range .items[*].spec.repositoryDigestMirrors[*]}{.source}{"\n"}{end}' 2>/dev/null | grep . || true)
  if [ -z "$idms" ] && [ -z "$icsp" ]; then
    note "$label: No IDMS/ICSP mirror sources defined"
    return 0
  fi
  dups=$(printf '%s\n%s\n' "$idms" "$icsp" | grep . | sort | uniq -c | awk '$1 > 1 {print $2 " (x" $1 ")"}')
  if [ -n "$dups" ]; then
    warn "$label: Duplicate/conflicting IDMS/ICSP mirror source(s): $(echo "$dups" | tr '\n' ' ')"
  else
    pass "$label: All IDMS/ICSP mirror sources are unique"
  fi
}

# Check 1: HostedCluster health (Hub). Usage: audit_hostedcluster <namespace> <name>
hc_cond() { hub get hostedcluster.hypershift.openshift.io "$2" -n "$1" -o jsonpath="{.status.conditions[?(@.type==\"$3\")].status}" 2>/dev/null; }
audit_hostedcluster() {
  local ns=$1 name=$2 s bad=0 paused_spec paused_ann
  s=$(hc_cond "$ns" "$name" Available)
  if [ "$s" != "True" ]; then stop "HostedCluster $ns/$name: Available=${s:-<missing>} (expected True)"; bad=1; fi
  s=$(hc_cond "$ns" "$name" Degraded)
  if [ "$s" = "True" ]; then stop "HostedCluster $ns/$name: Degraded=True"; bad=1; fi
  s=$(hc_cond "$ns" "$name" ReconciliationActive)
  if [ "$s" = "False" ]; then stop "HostedCluster $ns/$name: ReconciliationActive=False (reconciliation is not active)"; bad=1
  elif [ -z "$s" ]; then warn "HostedCluster $ns/$name: ReconciliationActive condition is missing"; fi
  s=$(hc_cond "$ns" "$name" ValidHostedControlPlaneConfiguration)
  if [ "$s" = "False" ]; then stop "HostedCluster $ns/$name: ValidHostedControlPlaneConfiguration=False"; bad=1; fi
  s=$(hc_cond "$ns" "$name" ClusterVersionSucceeding)
  if [ "$s" = "False" ]; then stop "HostedCluster $ns/$name: ClusterVersionSucceeding=False"; bad=1; fi
  paused_spec=$(hub get hostedcluster.hypershift.openshift.io "$name" -n "$ns" -o jsonpath='{.spec.paused}{.spec.pausedUntil}' 2>/dev/null || true)
  paused_ann=$(hub get hostedcluster.hypershift.openshift.io "$name" -n "$ns" -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/paused}' 2>/dev/null || true)
  if [ "$paused_spec" = "true" ] || { [ -n "$paused_spec" ] && [ "$paused_spec" != "false" ]; } || [ -n "$paused_ann" ]; then
    stop "HostedCluster $ns/$name is paused (spec='${paused_spec}', annotation='${paused_ann}')"; bad=1
  fi
  [ "$bad" -eq 0 ] && pass "HostedCluster $ns/$name: Available, not Degraded, reconciling and not paused"
  return 0
}

# Check 3: NodePool readiness (Hub). Usage: audit_nodepool <namespace> <name> <desired> <ready> <unready>
# ready/unready are the sums of .status.nodesInfo.nodeVersions[].readyNodeCount / unreadyNodeCount.
np_cond() { hub get nodepool.hypershift.openshift.io "$2" -n "$1" -o jsonpath="{.status.conditions[?(@.type==\"$3\")].status}" 2>/dev/null; }
audit_nodepool() {
  local ns=$1 name=$2 desired=$3 ready=${4:-0} unready=${5:-0} s t bad=0
  s=$(np_cond "$ns" "$name" Ready)
  if [ "$s" != "True" ]; then stop "NodePool $ns/$name: Ready=${s:-<missing>} (expected True)"; bad=1; fi
  for t in UpdatingConfig UpdatingVersion; do
    s=$(np_cond "$ns" "$name" "$t")
    if [ "$s" = "True" ]; then stop "NodePool $ns/$name: $t=True (update in progress)"; bad=1; fi
  done
  for t in ValidReleaseImage ValidMachineConfig; do
    s=$(np_cond "$ns" "$name" "$t")
    if [ "$s" = "False" ]; then stop "NodePool $ns/$name: $t=False"; bad=1; fi
  done
  for t in AllMachinesReady AllNodesHealthy; do
    s=$(np_cond "$ns" "$name" "$t")
    if [ "$s" = "False" ]; then warn "NodePool $ns/$name: $t=False"; fi
  done
  case "$desired" in
    ''|*[!0-9]*) ;;
    *) if [ "${ready:-0}" -lt "$desired" ]; then stop "NodePool $ns/$name: readyNodeCount ${ready:-0} < desired replicas $desired (unreadyNodeCount ${unready:-0})"; bad=1; fi ;;
  esac
  if [ "${unready:-0}" -gt 0 ] 2>/dev/null; then warn "NodePool $ns/$name: unreadyNodeCount=$unready"; fi
  [ "$bad" -eq 0 ] && pass "NodePool $ns/$name: Ready, not updating, ready nodes ${ready:-0}/${desired:-auto}"
  return 0
}

# Check 4: Hub controller deployments & pod restart counts
audit_hub_controllers() {
  local d want ready bad=0 pod phase cs c rest restarts reason
  for d in isf-prereq-operator isf-platform-operator fusionmanager-controller isf-hcp-manager; do
    if ! hub get deploy "$d" -n "$NS_FUSION" >/dev/null 2>&1; then
      note "Hub controller deployment $d not present in $NS_FUSION (skipped)"
      continue
    fi
    want=$(hub get deploy "$d" -n "$NS_FUSION" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    ready=$(hub get deploy "$d" -n "$NS_FUSION" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [ "${ready:-0}" = "0" ]; then
      stop "Hub controller deployment $d has 0 ready replicas (desired ${want:-0})"; bad=1
    elif [ "${ready:-0}" != "${want:-0}" ]; then
      warn "Hub controller deployment $d has ${ready:-0}/${want:-0} ready replicas"
    fi
  done
  while IFS='|' read -r pod phase cs; do
    [ -z "$pod" ] && continue
    if [ "$phase" != "Running" ]; then
      stop "Hub controller pod $pod is in phase '$phase' (expected Running)"; bad=1
    fi
    for c in $(echo "$cs" | tr ',' ' '); do
      rest=${c#*:}; restarts=${rest%%:*}; reason=${rest#*:}
      case "$restarts" in ''|*[!0-9]*) continue ;; esac
      if [ "$restarts" -gt "$CONTROLLER_RESTART_THRESHOLD" ]; then
        stop "Hub controller pod $pod container ${c%%:*} restart count ($restarts) exceeds threshold ($CONTROLLER_RESTART_THRESHOLD)"; bad=1
      fi
      case "$reason" in CrashLoopBackOff|Error) stop "Hub controller pod $pod container ${c%%:*} is in $reason"; bad=1 ;; esac
    done
  done < <(hub get pods -n "$NS_FUSION" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"|"}{range .status.containerStatuses[*]}{.name}{":"}{.restartCount}{":"}{.state.waiting.reason}{","}{end}{"\n"}{end}' 2>/dev/null |
    grep -E '^(isf-prereq-operator|isf-platform-operator|fusionmanager-controller|isf-hcp-manager)' || true)
  [ "$bad" -eq 0 ] && pass "Hub controllers (prereq/platform/fusionmanager/hcp-manager) are Running with restarts <= $CONTROLLER_RESTART_THRESHOLD"
  return 0
}

# Check 6 (per spoke, per addon CRD): in-flight Backup/Restore operations. Requires spoke().
# Usage: audit_inflight_ops <cluster> <crd> <label>
audit_inflight_ops() {
  local mc=$1 crd=$2 label=$3 inflight
  spoke get crd "$crd" >/dev/null 2>&1 || return 0
  inflight=$(spoke get "$crd" -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null |
    awk '$2=="InProgress"||$2=="Pending"||$2=="Running"||$2=="New"||$2=="Canceling" {print $1"("$2")"}' | tr '\n' ' ')
  if [ -n "$inflight" ]; then
    warn "Spoke $mc: In-flight/incomplete $label operation(s): $inflight"
  else
    pass "Spoke $mc: No in-flight $label operations"
  fi
}

# Check 8 (per spoke, per storage addon): Terminating PVCs on addon StorageClasses. Requires spoke().
# Usage: audit_terminating_pvcs <cluster> <label> <provisioner-ERE>
audit_terminating_pvcs() {
  local mc=$1 label=$2 prov=$3 scs bad
  scs=$(spoke get sc -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.provisioner}{"\n"}{end}' 2>/dev/null |
    awk -v re="$prov" '$2 ~ re {print $1}')
  [ -z "$scs" ] && return 0
  # awk -v must not contain newlines (BSD/macOS awk errors out), so pass the names space-separated.
  # StorageClass names cannot contain spaces.
  bad=$(spoke get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"|"}{.spec.storageClassName}{"|"}{.metadata.deletionTimestamp}{"|"}{.status.phase}{"\n"}{end}' 2>/dev/null |
    awk -F'|' -v scs="$(echo "$scs" | tr '\n' ' ')" 'BEGIN{n=split(scs,a," "); for(i=1;i<=n;i++) m[a[i]]=1} ($2 in m) && ($3!="" || $4=="Terminating") {print $1" [SC: "$2"]"}' | tr '\n' ' ')
  if [ -n "$bad" ]; then
    stop "Spoke $mc: Terminating PVC(s) on $label StorageClass(es): $bad"
    spoke_extra_blockers=$((spoke_extra_blockers+1))
  else
    pass "Spoke $mc: No Terminating PVCs on $label StorageClasses ($(echo "$scs" | tr '\n' ' '))"
  fi
}

note "Pre-upgrade check initiated at $(date -u +%FT%TZ)"
note "Output directory: $out_dir (SUMMARY: $summary)"

# ==============================================================================
# SECTION 1: HUB CONNECTIVITY & CLUSTER VERSIONS
# ==============================================================================
section "1. HUB ACCESS AND OPERATOR VERSIONS"

if ! hub whoami --show-server >"$out_dir/hub_server.txt" 2>&1; then
  stop "Cannot reach the Hub API server with HUB_KUBECONFIG ($HUB_KUBECONFIG)"
  exit 2
fi
hub_server=$(cat "$out_dir/hub_server.txt")
note "Hub API Server: $hub_server"

save hub_clusterversion.txt hub get clusterversion
save hub_fusion_csv.txt hub get csv -n "$NS_FUSION"
save hub_storage_csv.txt hub get csv -n "$NS_STORAGE"
save hub_nodes.txt hub get nodes -o wide

save hub_subscriptions.txt hub get subscription.operators.coreos.com -n "$NS_FUSION" \
  -o custom-columns=NAME:.metadata.name,CHANNEL:.spec.channel,SOURCE:.spec.source,APPROVAL:.spec.installPlanApproval,INSTALLED:.status.installedCSV

if hub get subscription.operators.coreos.com -n "$NS_FUSION" \
     -o jsonpath='{range .items[*]}{.spec.installPlanApproval}{"\n"}{end}' 2>/dev/null | grep -qi automatic; then
  warn "A Fusion subscription on Hub has installPlanApproval=Automatic. Switch to Manual before upgrading so you control InstallPlan approval."
else
  pass "All Fusion subscriptions on Hub use Manual approval"
fi

# --- Supplemental Check 9 (Hub): OCP / Fusion / Data Foundation version matrix ---
HUB_OCP_VER=$(hub get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || true)
HUB_OCP_MM=$(echo "$HUB_OCP_VER" | awk -F. '{print $1"."$2}')
HUB_OCP_MINOR=$(echo "$HUB_OCP_VER" | awk -F. '{print $2}')
hub_fusion_csv_rows=$(hub get csv -n "$NS_FUSION" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.version}{"\n"}{end}' 2>/dev/null || true)
hub_odf_csv_rows=$(hub get csv -n "$NS_STORAGE" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.version}{"\n"}{end}' 2>/dev/null || true)
HUB_FUSION_VER=$(echo "$hub_fusion_csv_rows" | awk '$1 ~ /^(isf-operator|spectrum-fusion)/ {print $2; exit}')
HUB_FUSION_MM=$(echo "$HUB_FUSION_VER" | awk -F. 'NF>=2 {print $1"."$2}')
HUB_ODF_VER=$(echo "$hub_odf_csv_rows" | awk '$1 ~ /^odf-operator/ {print $2; exit}')
HUB_ODF_MM=$(echo "$HUB_ODF_VER" | awk -F. 'NF>=2 {print $1"."$2}')
note "Hub versions: OCP=${HUB_OCP_VER:-unknown} Fusion=${HUB_FUSION_VER:-unknown} DataFoundation=${HUB_ODF_VER:-unknown}"

if [ -z "$HUB_FUSION_MM" ]; then
  note "Hub Fusion operator version could not be determined; release-matrix comparison skipped"
elif [ -z "$(matrix_lookup "$HUB_FUSION_MM" hub)" ]; then
  note "Fusion $HUB_FUSION_MM is not in the built-in version matrix; release-matrix comparison skipped"
else
  if in_list "$HUB_OCP_MM" "$(matrix_lookup "$HUB_FUSION_MM" hub)"; then
    pass "Hub OCP $HUB_OCP_MM is supported for Fusion $HUB_FUSION_MM"
  else
    warn "Hub OCP ${HUB_OCP_MM:-unknown} is not in the supported list for Fusion $HUB_FUSION_MM ($(matrix_lookup "$HUB_FUSION_MM" hub))"
  fi
  if [ -n "$HUB_ODF_MM" ]; then
    if in_list "$HUB_ODF_MM" "$(matrix_lookup "$HUB_FUSION_MM" odf)"; then
      pass "Hub Data Foundation $HUB_ODF_MM is supported for Fusion $HUB_FUSION_MM"
    else
      warn "Hub Data Foundation $HUB_ODF_MM is not in the supported list for Fusion $HUB_FUSION_MM ($(matrix_lookup "$HUB_FUSION_MM" odf))"
    fi
  fi
fi

for csv_ns in "$NS_FUSION" "$NS_STORAGE"; do
  bad_csvs=$(hub get csv -n "$csv_ns" -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{": "}{.status.phase}{"\n"}{end}' 2>/dev/null | grep .) || true
  if [ -n "$bad_csvs" ]; then
    stop "Hub ClusterServiceVersion(s) in $csv_ns not Succeeded: $(echo "$bad_csvs" | tr '\n' ' ')"
  else
    pass "All Hub CSVs in $csv_ns are Succeeded"
  fi
done

# --- Supplemental Check 2 (Hub): ICSP / IDMS mirror source collisions ---
audit_mirror_sources "Hub" "$HUB_KUBECONFIG"

# ==============================================================================
# SECTION 2: HUB FUSION CONTROLLERS & WORKLOADS
# ==============================================================================
section "2. HUB FUSION CONTROLLER HEALTH & SERVICES"

save hub_fusion_deployments.txt hub get deploy -n "$NS_FUSION"
save hub_fusion_pods.txt hub get pods -n "$NS_FUSION" -o wide

if hub get pods -n "$NS_FUSION" --no-headers 2>/dev/null | grep -Ev ' Running | Completed ' | grep -q .; then
  warn "Pods in $NS_FUSION on Hub are not all in Running/Completed state (see $out_dir/hub_fusion_pods.txt)"
else
  pass "All pods in $NS_FUSION on Hub are Running/Completed"
fi

if hub get deploy fusionmanager-controller -n "$NS_FUSION" >/dev/null 2>&1; then
  want=$(hub get deploy fusionmanager-controller -n "$NS_FUSION" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  ready=$(hub get deploy fusionmanager-controller -n "$NS_FUSION" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  image=$(hub get deploy fusionmanager-controller -n "$NS_FUSION" -o jsonpath='{.spec.template.spec.containers[*].image}' 2>/dev/null)
  note "fusionmanager-controller: replicas=${want:-?} ready=${ready:-0} image=${image}"
  if [ "${want:-0}" = "0" ]; then
    warn "fusionmanager-controller is scaled to 0 replicas"
  elif [ "${ready:-0}" != "$want" ]; then
    warn "fusionmanager-controller ready replicas ${ready:-0} of $want"
  else
    pass "fusionmanager-controller has $ready/$want ready replicas"
  fi
  save hub_fusionmanager_controller.log hub logs -n "$NS_FUSION" deployment/fusionmanager-controller --tail=2000
else
  warn "Deployment fusionmanager-controller not found in $NS_FUSION on Hub"
fi

# --- Supplemental Check 4 (Hub): Prereq / Platform / FusionManager / HCP-manager controller health ---
audit_hub_controllers

# Validate label-validation-webhook and fusion-addon-webhook-server ready endpoints
save hub_label_webhook.txt hub get validatingwebhookconfiguration label-validation-webhook -o yaml
if hub get validatingwebhookconfiguration label-validation-webhook >/dev/null 2>&1; then
  fp=$(hub get validatingwebhookconfiguration label-validation-webhook -o jsonpath='{.webhooks[*].failurePolicy}' 2>/dev/null)
  note "label-validation-webhook exists, failurePolicy=${fp:-?}"
  eps=$(hub get endpoints fusion-addon-webhook-server -n "$NS_FUSION" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
  if [ -z "$eps" ]; then
    warn "Service fusion-addon-webhook-server in $NS_FUSION has no ready endpoints: Fusion label changes are not validated (failurePolicy=${fp:-?})."
  else
    pass "fusion-addon-webhook-server has ready endpoints"
  fi
else
  warn "ValidatingWebhookConfiguration label-validation-webhook not found: Fusion label changes are not validated"
fi

# Validate FusionServiceDefinitions in -n ibm-spectrum-fusion-ns
save hub_fsd.txt hub get fusionservicedefinitions -n "$NS_FUSION"
if hub get crd fusionservicedefinitions.service.isf.ibm.com >/dev/null 2>&1; then
  hub_fsds=$(hub get fusionservicedefinitions -n "$NS_FUSION" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep . || true)
  if [ -z "$hub_fsds" ]; then
    warn "No FusionServiceDefinitions found in $NS_FUSION on Hub (see hub_fsd.txt)"
  else
    pass "FusionServiceDefinitions present in $NS_FUSION on Hub: $(echo "$hub_fsds" | tr '\n' ' ')"
  fi
else
  warn "CRD fusionservicedefinitions.service.isf.ibm.com not found on Hub"
fi

# Validate FusionServiceInstances in -n ibm-spectrum-fusion-ns (ensure in Completed)
save hub_fsi.txt hub get fusionserviceinstances -n "$NS_FUSION" -o wide
if hub get crd fusionserviceinstances.service.isf.ibm.com >/dev/null 2>&1; then
  hub_fsis=$(hub get fusionserviceinstances -n "$NS_FUSION" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.installStatus.status}{" "}{.status.status}{"\n"}{end}' 2>/dev/null | grep . || true)
  if [ -z "$hub_fsis" ]; then
    warn "No FusionServiceInstances found in $NS_FUSION on Hub (see hub_fsi.txt)"
  else
    hub_fsi_bad=""
    while read -r fsi_name fsi_inst_status fsi_status; do
      [ -z "$fsi_name" ] && continue
      st="${fsi_inst_status}"
      [ -z "$st" ] && st="${fsi_status}"
      if [ "$st" != "Completed" ]; then
        hub_fsi_bad="${hub_fsi_bad} ${fsi_name}(${st:-Unknown})"
      fi
    done <<< "$hub_fsis"
    if [ -n "$hub_fsi_bad" ]; then
      warn "Hub FusionServiceInstances not in Completed status:$hub_fsi_bad"
    else
      pass "All Hub FusionServiceInstances in $NS_FUSION are in Completed status"
    fi
  fi
else
  warn "CRD fusionserviceinstances.service.isf.ibm.com not found on Hub"
fi

# Snapshot fusion-addon-config ConfigMap
if hub get configmap fusion-addon-config -n "$NS_FUSION" >/dev/null 2>&1; then
  save snapshot/fusion-addon-config.yaml hub get configmap fusion-addon-config -n "$NS_FUSION" -o yaml
  pass "Snapshotted fusion-addon-config ConfigMap from $NS_FUSION on Hub"
else
  warn "ConfigMap fusion-addon-config not found in $NS_FUSION on Hub"
fi

# Provider LoadBalancer Ingress check
lb_ip=$(hub get svc -A --field-selector metadata.name=ocs-provider-server-load-balancer \
  -o jsonpath='{range .items[*]}{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}' 2>/dev/null | grep . | head -1 || true)
if [ -n "$lb_ip" ]; then
  pass "ocs-provider-server-load-balancer has ingress address ($lb_ip)"
fi

# ==============================================================================
# SECTION 3: HUB DATA FOUNDATION / CEPH STORAGE HEALTH
# ==============================================================================
section "3. HUB DATA FOUNDATION (FDF/CEPH) HEALTH"

save hub_storagecluster.txt hub get storagecluster -n "$NS_STORAGE"
save hub_cephcluster.txt hub get cephcluster -n "$NS_STORAGE" \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,HEALTH:.status.ceph.health
save hub_openshift_storage_pods.txt hub get pods -n "$NS_STORAGE" -o wide

if hub get cephcluster -n "$NS_STORAGE" -o jsonpath='{range .items[*]}{.status.ceph.health}{"\n"}{end}' 2>/dev/null | grep -q HEALTH_OK; then
  pass "Hub CephCluster reports HEALTH_OK"
else
  stop "Hub CephCluster is not HEALTH_OK (see $out_dir/hub_cephcluster.txt). Do not upgrade while storage is degraded!"
fi

# ==============================================================================
# SECTION 4: HUB STUCK DELETIONS & TERMINATING OBJECTS CHECK
# ==============================================================================
section "4. HUB STUCK DELETIONS & TERMINATING CONSUMER OBJECTS"

for r in storageconsumers.ocs.openshift.io cephclients.ceph.rook.io \
         cephblockpoolradosnamespaces.ceph.rook.io cephfilesystemsubvolumegroups.ceph.rook.io; do
  terminating_objs=$(hub get "$r" -n "$NS_STORAGE" -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep .) || true
  n=$(echo -n "$terminating_objs" | grep -c . || true)
  if [ "$n" -gt 0 ]; then
    stop "$n object(s) of $r in $NS_STORAGE have deletionTimestamp and are stuck in Terminating ($terminating_objs). Resolve before upgrade!"
  else
    pass "No Terminating objects found for $r in $NS_STORAGE"
  fi
done

# Snapshot consumer objects for audit
save snapshot/storageconsumers.yaml hub get storageconsumers.ocs.openshift.io -n "$NS_STORAGE" -o yaml --show-managed-fields
save snapshot/cephclients.yaml hub get cephclients.ceph.rook.io -n "$NS_STORAGE" -o yaml
save snapshot/radosnamespaces.yaml hub get cephblockpoolradosnamespaces.ceph.rook.io -n "$NS_STORAGE" -o yaml
save snapshot/subvolumegroups.yaml hub get cephfilesystemsubvolumegroups.ceph.rook.io -n "$NS_STORAGE" -o yaml

for cm in $(hub get storageconsumers.ocs.openshift.io -n "$NS_STORAGE" \
     -o jsonpath='{range .items[*]}{.spec.resourceNameMappingConfigMap.name}{"\n"}{end}' 2>/dev/null | grep .); do
  save "snapshot/configmap_${cm}.yaml" hub get configmap "$cm" -n "$NS_STORAGE" -o yaml
done

save hub_storageconsumers.txt hub get storageconsumers.ocs.openshift.io -n "$NS_STORAGE" \
  -o custom-columns='NAME:.metadata.name,UID:.metadata.uid,CREATED:.metadata.creationTimestamp,ENABLED:.spec.enable,MAPPING_CM:.spec.resourceNameMappingConfigMap.name,CLUSTER:.metadata.labels.isf\.ibm\.com/cluster-name'

# ==============================================================================
# SECTION 5: MANAGEDCLUSTER LABELS VS STORAGECONSUMER AUDIT (TS023322996 RCA)
# ==============================================================================
section "5. MANAGEDCLUSTER LABELS & STORAGECONSUMER CONSISTENCY AUDIT"

save hub_managedclusters.txt hub get managedcluster -o wide

mc_list=$(hub get managedcluster -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -v '^local-cluster$' || true)

if [ -z "$mc_list" ]; then
  note "No ManagedClusters other than local-cluster found on Hub."
fi

while IFS= read -r mc; do
  [ -z "$mc" ] && continue
  if [ -n "$TARGET_CLUSTER" ] && [ "$mc" != "$TARGET_CLUSTER" ]; then
    continue
  fi
  save "snapshot/managedcluster_${mc}.yaml" hub get managedcluster "$mc" -o yaml --show-managed-fields
  
  # Fetch full JSON for robust label checking
  mc_json=$(hub get managedcluster "$mc" -o json 2>/dev/null || true)
  
  has_base=false
  has_fdf=false
  has_backup=false
  has_rm=false

  # Check label key presence in .metadata.labels
  if echo "$mc_json" | grep -q '"isf.ibm.com/fusion-base"'; then
    has_base=true
  fi
  if echo "$mc_json" | grep -q '"isf.ibm.com/fusion-fdf"'; then
    has_fdf=true
  fi
  if echo "$mc_json" | grep -q '"isf.ibm.com/fusion-backup"'; then
    has_backup=true
  fi
  if echo "$mc_json" | grep -q '"isf.ibm.com/fusion-gdp-rm"'; then
    has_rm=true
  fi

  created=$(hub get managedcluster "$mc" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
  cfgs=$(hub get managedcluster "$mc" -o jsonpath='{range .spec.managedClusterClientConfigs[*]}{.url}{"\n"}{end}' 2>/dev/null | grep -c . || true)

  # Check consumer matched by label isf.ibm.com/cluster-name
  cons=$(hub get storageconsumers.ocs.openshift.io -n "$NS_STORAGE" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.isf\.ibm\.com/cluster-name}{"\n"}{end}' 2>/dev/null |
    awk -v c="$mc" '$2==c {print $1}' || true)
  
  # Fallback consumer check by name prefix/suffix if label missing
  if [ -z "$cons" ]; then
    cons=$(hub get storageconsumers.ocs.openshift.io -n "$NS_STORAGE" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null |
      grep -E "^${mc}$|^${mc}-storageconsumer$" || true)
  fi

  cons_created=""
  if [ -n "$cons" ]; then
    cons_first=$(echo "$cons" | head -n 1)
    cons_created=$(hub get storageconsumers.ocs.openshift.io "$cons_first" -n "$NS_STORAGE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)
  fi

  base_desc="absent"
  [ "$has_base" = true ] && base_desc="present"
  fdf_desc="absent"
  [ "$has_fdf" = true ] && fdf_desc="present"

  note "ManagedCluster $mc: created=$created base='$base_desc' fdf='$fdf_desc' clientConfigs=$cfgs consumer='${cons:-none}'"

  if [ "$has_base" = false ] && [ "$has_fdf" = false ]; then
    if [ -n "$cons" ]; then
      stop "ManagedCluster $mc has a StorageConsumer ($cons) but NEITHER isf.ibm.com/fusion-base NOR fusion-fdf labels. (Incident TS023322996 state: cluster was recreated/pruned without addon labels). NOT SAFE TO UPGRADE!"
    else
      note "ManagedCluster $mc has no isf.ibm.com/fusion-* labels and no StorageConsumer matched by label."
    fi
  elif [ "$has_base" = false ] || [ "$has_fdf" = false ]; then
    warn "ManagedCluster $mc has only one of fusion-base / fusion-fdf (base='$base_desc', fdf='$fdf_desc'). Expected both for clusters consuming FDF."
  else
    pass "ManagedCluster $mc carries required fusion-base and fusion-fdf labels"
  fi

  # Cluster recreation indicator
  if [ -n "$cons_created" ] && [ -n "$created" ] && [[ "$created" > "$cons_created" ]]; then
    stop "ManagedCluster $mc ($created) is NEWER than its StorageConsumer ($cons_created). ManagedCluster was deleted and recreated after onboarding! Check GitOps/ArgoCD prune settings."
  fi

  # ManagedFields / GitOps check
  mgrs=$(hub get managedcluster "$mc" -o jsonpath='{range .metadata.managedFields[*]}{.manager}{"\n"}{end}' 2>/dev/null | sort -u | tr '\n' ' ')
  if echo "$mgrs" | grep -Eiq 'argocd|argo|flux|gitops'; then
    warn "ManagedCluster $mc is managed by a GitOps engine ($mgrs). Ensure automated prune is disabled during upgrade window."
  fi
done <<< "$mc_list"

# Check for orphaned StorageConsumers on Hub (only those tied to TARGET_CLUSTER when set;
# mc_list stays unfiltered so existence is checked against all ManagedClusters)
while read -r cname ccluster; do
  [ -z "$cname" ] && continue
  case "$cname" in *internal*) continue ;; esac
  if [ -n "$TARGET_CLUSTER" ] && [ "$ccluster" != "$TARGET_CLUSTER" ]; then
    continue
  fi
  if [ -z "$ccluster" ]; then
    warn "StorageConsumer $cname has no isf.ibm.com/cluster-name label: cannot match to ManagedCluster automatically."
  elif ! echo "$mc_list" | grep -qx "$ccluster"; then
    stop "StorageConsumer $cname references cluster '$ccluster' but no matching ManagedCluster exists on Hub."
  fi
done < <(hub get storageconsumers.ocs.openshift.io -n "$NS_STORAGE" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.isf\.ibm\.com/cluster-name}{"\n"}{end}' 2>/dev/null || true)

# ==============================================================================
# SECTION 6: GITOPS AUTOMATION & ACM POLICY CHECKS
# ==============================================================================
section "6. GITOPS AUTOMATED PRUNE & ACM POLICIES"

if hub get crd applications.argoproj.io >/dev/null 2>&1; then
  save hub_argocd_applications.txt hub get applications.argoproj.io -A \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PRUNE:.spec.syncPolicy.automated.prune,SELFHEAL:.spec.syncPolicy.automated.selfHeal,DEST:.spec.destination.name,PATH:.spec.source.path'
  if hub get applications.argoproj.io -A -o jsonpath='{range .items[*]}{.spec.syncPolicy.automated.prune}{"\n"}{end}' 2>/dev/null | grep -q true; then
    warn "ArgoCD Applications with automated.prune=true exist on Hub. Verify they do not prune ManagedClusters or Fusion labels during upgrade."
  else
    pass "No ArgoCD Application has automated prune=true"
  fi
fi

if hub get crd policies.policy.open-cluster-management.io >/dev/null 2>&1; then
  save hub_acm_policies.txt hub get policies.policy.open-cluster-management.io -A
fi

# ==============================================================================
# SECTION 7: HUB-SIDE MANAGEDCLUSTERADDON & MANIFESTWORK STATUS
# ==============================================================================
section "7. HUB-SIDE ADDON OBJECTS & MANIFESTWORK HEALTH"

# Check all ManagedClusterAddons and ManifestWorks for deletion timestamps and degraded states
while IFS= read -r mc; do
  [ -z "$mc" ] && continue
  if [ -n "$TARGET_CLUSTER" ] && [ "$mc" != "$TARGET_CLUSTER" ]; then
    continue
  fi

  save "clusters/${mc}_hub_addons.txt" hub get managedclusteraddons -n "$mc"
  save "clusters/${mc}_hub_manifestworks.txt" hub get manifestworks -n "$mc"

  # 1. ManagedClusterAddOn deletion timestamp check
  deleting_addons=$(hub get managedclusteraddons -n "$mc" -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep .) || true
  if [ -n "$deleting_addons" ]; then
    stop "Cluster $mc has ManagedClusterAddOn object(s) stuck in DELETION state: $deleting_addons"
  else
    pass "Cluster $mc: No ManagedClusterAddOns in deletion state"
  fi

  # 2. ManagedClusterAddOn health conditions
  for addon in $(hub get managedclusteraddons -n "$mc" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    available_cond=$(hub get managedclusteraddon "$addon" -n "$mc" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
    degraded_cond=$(hub get managedclusteraddon "$addon" -n "$mc" -o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}' 2>/dev/null)
    
    if [ "$available_cond" = "False" ] || [ "$degraded_cond" = "True" ]; then
      stop "Cluster $mc: AddOn '$addon' is DEGRADED or UNAVAILABLE (Available=$available_cond, Degraded=$degraded_cond)"
    else
      pass "Cluster $mc: AddOn '$addon' is Healthy (Available=$available_cond, Degraded=${degraded_cond:-False})"
    fi
  done

  # 3. ManifestWork deletion timestamp and applied status check
  deleting_works=$(hub get manifestworks -n "$mc" -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep .) || true
  if [ -n "$deleting_works" ]; then
    stop "Cluster $mc has ManifestWork(s) stuck in DELETION state: $deleting_works"
  else
    pass "Cluster $mc: No ManifestWorks in deletion state"
  fi

  for mw in $(hub get manifestworks -n "$mc" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    applied_cond=$(hub get manifestwork "$mw" -n "$mc" -o jsonpath='{.status.conditions[?(@.type=="Applied")].status}' 2>/dev/null)
    degraded_cond=$(hub get manifestwork "$mw" -n "$mc" -o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}' 2>/dev/null)
    if [ "$applied_cond" = "False" ] || [ "$degraded_cond" = "True" ]; then
      stop "Cluster $mc: ManifestWork '$mw' failed to apply or is Degraded (Applied=$applied_cond, Degraded=$degraded_cond)"
    fi
  done
done <<< "$mc_list"

# ==============================================================================
# SECTION 7A: HUB-SIDE HOSTEDCLUSTER & NODEPOOL HEALTH (HCP clusters only)
# ==============================================================================
section "7A. HUB-SIDE HOSTEDCLUSTER & NODEPOOL HEALTH (HCP CLUSTERS ONLY)"

if hub get crd hostedclusters.hypershift.openshift.io >/dev/null 2>&1; then
  save hub_hostedclusters.txt hub get hostedclusters.hypershift.openshift.io -A \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PROGRESSING:.status.conditions[?(@.type=="Progressing")].status,AVAILABLE:.status.conditions[?(@.type=="Available")].status,DEGRADED:.status.conditions[?(@.type=="Degraded")].status,RECONCILING:.status.conditions[?(@.type=="ReconciliationActive")].status'
  while IFS='|' read -r hc_ns hc_name; do
    [ -z "$hc_name" ] && continue
    if [ -n "$TARGET_CLUSTER" ] && [ "$hc_name" != "$TARGET_CLUSTER" ]; then
      continue
    fi
    audit_hostedcluster "$hc_ns" "$hc_name"
  done < <(hub get hostedclusters.hypershift.openshift.io -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
else
  note "CRD hostedclusters.hypershift.openshift.io not found on Hub; HostedCluster checks skipped"
fi

if hub get crd nodepools.hypershift.openshift.io >/dev/null 2>&1; then
  save hub_nodepools.txt hub get nodepools.hypershift.openshift.io -A \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLUSTER:.spec.clusterName,DESIRED:.spec.replicas,READY_NODES:.status.nodesInfo.nodeVersions[*].readyNodeCount,UNREADY_NODES:.status.nodesInfo.nodeVersions[*].unreadyNodeCount,READY_COND:.status.conditions[?(@.type=="Ready")].status,UPDATING_CFG:.status.conditions[?(@.type=="UpdatingConfig")].status,UPDATING_VER:.status.conditions[?(@.type=="UpdatingVersion")].status'
  while IFS='|' read -r np_ns np_name np_cluster np_desired np_ready_counts np_unready_counts; do
    [ -z "$np_name" ] && continue
    if [ -n "$TARGET_CLUSTER" ] && [ "$np_cluster" != "$TARGET_CLUSTER" ]; then
      continue
    fi
    # nodeVersions is a list (one entry per node version); sum the per-version counts.
    np_ready=$(echo "$np_ready_counts" | awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s}')
    np_unready=$(echo "$np_unready_counts" | awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s}')
    audit_nodepool "$np_ns" "$np_name" "$np_desired" "$np_ready" "$np_unready"
  done < <(hub get nodepools.hypershift.openshift.io -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.spec.clusterName}{"|"}{.spec.replicas}{"|"}{range .status.nodesInfo.nodeVersions[*]}{.readyNodeCount}{" "}{end}{"|"}{range .status.nodesInfo.nodeVersions[*]}{.unreadyNodeCount}{" "}{end}{"\n"}{end}' 2>/dev/null || true)
else
  note "CRD nodepools.hypershift.openshift.io not found on Hub; NodePool checks skipped"
fi

# ==============================================================================
# SECTION 8: SPOKE DISCOVERY & SPOKE WORKFLOW INSPECTION
# ==============================================================================
section "8. SPOKE DISCOVERY & FUSION OPERATOR WORKFLOW HEALTH"

# Map file for HCP cluster -> namespace
hcp_map_file="$out_dir/hcp_namespaces.txt"
touch "$hcp_map_file"

# Check if Hypershift CRD exists on Hub
if hub get crd hostedcontrolplanes.hypershift.openshift.io >/dev/null 2>&1; then
  hub get hostedcontrolplanes.hypershift.openshift.io -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null >> "$hcp_map_file" || true
fi

# Fallback: check HostedClusters
if hub get crd hostedclusters.hypershift.openshift.io >/dev/null 2>&1; then
  hub get hostedclusters.hypershift.openshift.io -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null >> "$hcp_map_file" || true
fi

# Process each ManagedCluster
while IFS= read -r mc; do
  [ -z "$mc" ] && continue
  if [ -n "$TARGET_CLUSTER" ] && [ "$mc" != "$TARGET_CLUSTER" ]; then
    continue
  fi

  echo ""
  note ">>> Inspecting Spoke Cluster: $mc <<<"
  spoke_extra_blockers=0

  spoke_kc=""
  hcp_ns=$(awk -v c="$mc" '$2==c {print $1; exit}' "$hcp_map_file" 2>/dev/null || true)

  # If not found via HostedControlPlane lookup, try cluster name as namespace or clusters namespace
  if [ -z "$hcp_ns" ]; then
    if hub get secret admin-kubeconfig -n "$mc" >/dev/null 2>&1; then
      hcp_ns="$mc"
    elif hub get secret "${mc}-admin-kubeconfig" -n "clusters" >/dev/null 2>&1; then
      hcp_ns="clusters"
    fi
  fi

  # Check manual SPOKE_KUBECONFIGS list first if provided
  if [ -n "$SPOKE_KUBECONFIGS" ]; then
    for manual_kc in $SPOKE_KUBECONFIGS; do
      if [[ "$manual_kc" == *"$mc"* ]] && [ -r "$manual_kc" ]; then
        spoke_kc="$manual_kc"
        note "Using explicitly provided kubeconfig for $mc: $spoke_kc"
        break
      fi
    done
  fi

  # Automated secret extraction if spoke_kc is not set
  if [ -z "$spoke_kc" ]; then
    if [ -n "$hcp_ns" ]; then
      target_secret="admin-kubeconfig"
      if ! hub get secret "$target_secret" -n "$hcp_ns" >/dev/null 2>&1; then
        if hub get secret "${mc}-admin-kubeconfig" -n "$hcp_ns" >/dev/null 2>&1; then
          target_secret="${mc}-admin-kubeconfig"
        fi
      fi

      if hub get secret "$target_secret" -n "$hcp_ns" >/dev/null 2>&1; then
        extracted_kc="$out_dir/spoke_kubeconfigs/${mc}.kubeconfig"
        # Extract kubeconfig data (handles base64 or direct kubeconfig field)
        kc_data=$(hub get secret "$target_secret" -n "$hcp_ns" -o jsonpath='{.data.kubeconfig}' 2>/dev/null | base64 -d 2>/dev/null || true)
        if [ -z "$kc_data" ]; then
          kc_data=$(hub get secret "$target_secret" -n "$hcp_ns" -o jsonpath='{.data.admin-kubeconfig}' 2>/dev/null | base64 -d 2>/dev/null || true)
        fi

        if [ -n "$kc_data" ]; then
          echo "$kc_data" > "$extracted_kc"
          chmod 600 "$extracted_kc"
          spoke_kc="$extracted_kc"
          note "Extracted admin-kubeconfig for $mc from secret '$target_secret' in namespace '$hcp_ns'"
        else
          warn "Secret '$target_secret' in namespace '$hcp_ns' did not contain valid kubeconfig data"
        fi
      else
        warn "Could not locate admin-kubeconfig secret in namespace '$hcp_ns' for cluster $mc"
      fi
    else
      warn "Could not identify HostedControlPlane namespace for ManagedCluster $mc (not an HCP cluster?). Supply its kubeconfig with -s to enable spoke checks."
    fi
  fi

  if [ -z "$spoke_kc" ] || [ ! -r "$spoke_kc" ]; then
    warn "Cannot connect to spoke cluster $mc (No kubeconfig available). Spoke-side workflow checks skipped for $mc."
    printf "%-20s | %-12s | %-16s | %-16s | %-10s\n" "$mc" "NO_KUBECONFIG" "SKIPPED" "N/A" "NOT_READY" >> "$matrix_file"
    continue
  fi

  # Helper for Spoke CLI
  spoke() { "$CLI_TOOL" --kubeconfig "$spoke_kc" "$@"; }

  # Test connectivity
  if ! spoke whoami --show-server >"$out_dir/clusters/${mc}_server.txt" 2>&1; then
    stop "Cannot reach spoke cluster $mc API server with extracted admin-kubeconfig"
    printf "%-20s | %-12s | %-16s | %-16s | %-10s\n" "$mc" "FAILED_CONNECT" "N/A" "N/A" "NOT_READY" >> "$matrix_file"
    continue
  fi

  spoke_server=$(cat "$out_dir/clusters/${mc}_server.txt")
  if [ "$spoke_server" = "$hub_server" ]; then
    stop "Spoke kubeconfig for $mc points at the Hub API endpoint ($spoke_server)"
    printf "%-20s | %-12s | %-16s | %-16s | %-10s\n" "$mc" "TARGETS_HUB" "N/A" "N/A" "NOT_READY" >> "$matrix_file"
    continue
  fi
  pass "Connected to spoke cluster $mc ($spoke_server)"

  # Collect Spoke Nodes & basic info
  save "clusters/${mc}_nodes.txt" spoke get nodes -o wide
  spoke_node_count=$(spoke get nodes --no-headers 2>/dev/null | grep -c . || true)
  note "Spoke $mc has $spoke_node_count worker node(s)"

  # --------------------------------------------------------------------------
  # 8.0 Spoke General Checks (node quorum, OCP version, mirror sources)
  # --------------------------------------------------------------------------
  # Check 5: Minimum Ready & schedulable worker nodes
  active_nodes=$(spoke get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.unschedulable}{"|"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null |
    awk -F'|' '$3=="True" && $2!="true"' | grep -c . || true)
  if [ "${active_nodes:-0}" -lt "$MIN_SPOKE_READY_NODES" ]; then
    stop "Spoke $mc has only ${active_nodes:-0} active/Ready schedulable node(s) (minimum $MIN_SPOKE_READY_NODES required)"
    spoke_extra_blockers=$((spoke_extra_blockers+1))
  else
    pass "Spoke $mc has $active_nodes active/Ready schedulable node(s) (minimum $MIN_SPOKE_READY_NODES)"
  fi

  # Check 9: Spoke OCP version skew against Hub and release matrix
  spoke_ocp_ver=$(spoke get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || true)
  if [ -z "$spoke_ocp_ver" ]; then
    warn "Spoke $mc: Could not determine OCP version (ClusterVersion unavailable)"
  else
    spoke_ocp_mm=$(echo "$spoke_ocp_ver" | awk -F. '{print $1"."$2}')
    spoke_ocp_minor=$(echo "$spoke_ocp_ver" | awk -F. '{print $2}')
    note "Spoke $mc OCP version: $spoke_ocp_ver (Hub: ${HUB_OCP_VER:-unknown})"
    case "${HUB_OCP_MINOR:-}" in
      ''|*[!0-9]*) ;;
      *)
        case "$spoke_ocp_minor" in
          ''|*[!0-9]*) warn "Spoke $mc: Cannot parse OCP minor version from '$spoke_ocp_ver'" ;;
          *)
            ocp_skew=$((HUB_OCP_MINOR - spoke_ocp_minor))
            if [ "$ocp_skew" -lt 0 ] || [ "$ocp_skew" -gt 2 ]; then
              stop "Spoke $mc: OCP $spoke_ocp_ver skew ($ocp_skew minor) vs Hub $HUB_OCP_VER is outside supported range (0 to 2 minor versions behind Hub)"
              spoke_extra_blockers=$((spoke_extra_blockers+1))
            else
              pass "Spoke $mc: OCP $spoke_ocp_ver skew ($ocp_skew minor) vs Hub $HUB_OCP_VER is within supported limits"
            fi
            ;;
        esac
        ;;
    esac
    if [ -n "${HUB_FUSION_MM:-}" ]; then
      spoke_ocp_supported=$(matrix_lookup "$HUB_FUSION_MM" spoke)
      if [ -n "$spoke_ocp_supported" ] && ! in_list "$spoke_ocp_mm" "$spoke_ocp_supported"; then
        warn "Spoke $mc: OCP $spoke_ocp_mm is not in the supported Spoke OCP list for Fusion $HUB_FUSION_MM ($spoke_ocp_supported)"
      fi
    fi
  fi

  # Check 2: ICSP / IDMS mirror source collisions on the spoke
  audit_mirror_sources "Spoke $mc" "$spoke_kc"

  # --------------------------------------------------------------------------
  # 8.1 Spoke Stuck Deletions & Cleanup Jobs
  # --------------------------------------------------------------------------
  stuck_deletions_count=0

  # Check terminating namespaces/pods in all AddOn namespaces (Check 7)
  for ns in "$NS_FUSION" "$NS_STORAGE" "$NS_BACKUP" "ibm-spectrum-scale" "ibm-spectrum-scale-csi" "open-cluster-management-agent-addon"; do
    if spoke get ns "$ns" >/dev/null 2>&1; then
      ns_deleting=$(spoke get ns "$ns" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || true)
      if [ -n "$ns_deleting" ]; then
        stop "Spoke $mc: Namespace $ns has deletionTimestamp ($ns_deleting) and is stuck in Terminating"
        stuck_deletions_count=$((stuck_deletions_count+1))
      fi

      terminating_pods=$(spoke get pods -n "$ns" --no-headers 2>/dev/null | grep -i 'Terminating' || true)
      if [ -n "$terminating_pods" ]; then
        stop "Spoke $mc has Terminating pod(s) in namespace $ns:\n$terminating_pods"
        stuck_deletions_count=$((stuck_deletions_count+1))
      fi

      # Check for resources stuck with deletionTimestamp
      deleting_crs=$(spoke get all,fusionserviceinstances,spectrumfusions,storageclients,connections -n "$ns" \
        -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.kind}{"/"}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep .) || true
      if [ -n "$deleting_crs" ]; then
        stop "Spoke $mc has resource(s) in $ns stuck in DELETION state:\n$deleting_crs"
        stuck_deletions_count=$((stuck_deletions_count+1))
      fi

      # Check cleanup jobs
      failed_jobs=$(spoke get jobs -n "$ns" -o jsonpath='{range .items[?(@.status.failed>0)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep .) || true
      if [ -n "$failed_jobs" ]; then
        warn "Spoke $mc has failed Job(s) in namespace $ns: $failed_jobs"
      fi
    fi
  done

  if [ "$stuck_deletions_count" -eq 0 ]; then
    pass "Spoke $mc: No resources or pods stuck in deletion state"
  fi

  # Determine labels for this ManagedCluster on Hub
  mc_labels=$(hub get managedcluster "$mc" -o jsonpath='{.metadata.labels}' 2>/dev/null || true)
  spoke_has_base=false; echo "$mc_labels" | grep -q '"isf.ibm.com/fusion-base"' && spoke_has_base=true
  spoke_has_fdf=false; echo "$mc_labels" | grep -q '"isf.ibm.com/fusion-fdf"' && spoke_has_fdf=true
  spoke_has_backup=false; echo "$mc_labels" | grep -q '"isf.ibm.com/fusion-backup"' && spoke_has_backup=true
  spoke_has_rm=false; echo "$mc_labels" | grep -q '"isf.ibm.com/fusion-gdp-rm"' && spoke_has_rm=true

  fusion_op_healthy=true

  # --------------------------------------------------------------------------
  # 8.2 Spoke Fusion AddOn (fusion-base) Health & Consistency
  # --------------------------------------------------------------------------
  # Discover Spoke-side base resources
  has_spoke_sf=false
  if spoke get spectrumfusion -n "$NS_FUSION" >/dev/null 2>&1; then
    has_spoke_sf=true
  fi
  has_spoke_fa=false
  if spoke get deploy fusion-agent -n open-cluster-management-agent-addon >/dev/null 2>&1; then
    has_spoke_fa=true
  fi
  spoke_fusion_csvs=$(spoke get csv -n "$NS_FUSION" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E '^isf-operator|^spectrum-fusion' || true)

  # Direction 2 Consistency: Spoke Base Resources -> Missing Hub Label
  if [ "$spoke_has_base" = false ]; then
    spoke_base_res=""
    [ "$has_spoke_sf" = true ] && spoke_base_res="SpectrumFusion CR"
    [ "$has_spoke_fa" = true ] && spoke_base_res="${spoke_base_res:+$spoke_base_res, }fusion-agent deployment"
    [ -n "$spoke_fusion_csvs" ] && spoke_base_res="${spoke_base_res:+$spoke_base_res, }Fusion CSV ($spoke_fusion_csvs)"

    if [ -n "$spoke_base_res" ]; then
      stop "Spoke $mc has Fusion Base resources deployed ($spoke_base_res) but ManagedCluster on Hub is MISSING label 'isf.ibm.com/fusion-base'. (Direction 2 Desync: Spoke resources exist without Hub label). NOT SAFE TO UPGRADE!"
      fusion_op_healthy=false
    fi
  fi

  # Direction 1 & Health: Validate FusionServiceDefinitions in -n ibm-spectrum-fusion-ns
  save "clusters/${mc}_fsd.txt" spoke get fusionservicedefinitions -n "$NS_FUSION"
  if spoke get crd fusionservicedefinitions.service.isf.ibm.com >/dev/null 2>&1; then
    spoke_fsds=$(spoke get fusionservicedefinitions -n "$NS_FUSION" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep . || true)
    if [ -n "$spoke_fsds" ]; then
      pass "Spoke $mc: FusionServiceDefinitions present in $NS_FUSION: $(echo "$spoke_fsds" | tr '\n' ' ')"
    elif [ "$spoke_has_base" = true ]; then
      warn "Spoke $mc: No FusionServiceDefinitions found in $NS_FUSION (see clusters/${mc}_fsd.txt)"
    fi
  elif [ "$spoke_has_base" = true ]; then
    warn "Spoke $mc: CRD fusionservicedefinitions.service.isf.ibm.com not found"
  fi

  # Validate fusion-agent in -n open-cluster-management-agent-addon
  save "clusters/${mc}_agent_fusion.txt" spoke get deploy fusion-agent -n open-cluster-management-agent-addon -o wide
  if [ "$has_spoke_fa" = true ]; then
    fa_want=$(spoke get deploy fusion-agent -n open-cluster-management-agent-addon -o jsonpath='{.spec.replicas}' 2>/dev/null)
    fa_ready=$(spoke get deploy fusion-agent -n open-cluster-management-agent-addon -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [ "${fa_want:-0}" -gt 0 ] && [ "${fa_ready:-0}" = "$fa_want" ]; then
      pass "Spoke $mc: fusion-agent deployment is Healthy in open-cluster-management-agent-addon (${fa_ready}/${fa_want} ready)"
    else
      stop "Spoke $mc: fusion-agent deployment has ${fa_ready:-0}/${fa_want:-0} ready replicas in open-cluster-management-agent-addon"
      fusion_op_healthy=false
    fi
  elif [ "$spoke_has_base" = true ]; then
    warn "Spoke $mc carries fusion-base label but Deployment fusion-agent was not found in open-cluster-management-agent-addon"
  fi

  # Validate SpectrumFusion CR, CSVs, and Pods in $NS_FUSION
  save "clusters/${mc}_fusion_pods.txt" spoke get pods -n "$NS_FUSION" -o wide
  save "clusters/${mc}_fusion_csv.txt" spoke get csv -n "$NS_FUSION"
  save "clusters/${mc}_spectrumfusion.txt" spoke get spectrumfusion -n "$NS_FUSION" -o yaml

  if [ "$has_spoke_sf" = true ]; then
    sf_deleting=$(spoke get spectrumfusion -n "$NS_FUSION" -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep .) || true
    if [ -n "$sf_deleting" ]; then
      stop "Spoke $mc: SpectrumFusion CR is in DELETION state: $sf_deleting"
      fusion_op_healthy=false
    else
      sf_status=$(spoke get spectrumfusion -n "$NS_FUSION" -o jsonpath='{.items[0].status.status}' 2>/dev/null || true)
      sf_avail=$(spoke get spectrumfusion -n "$NS_FUSION" -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
      sf_degraded=$(spoke get spectrumfusion -n "$NS_FUSION" -o jsonpath='{.items[0].status.conditions[?(@.type=="Degraded")].status}' 2>/dev/null || true)

      if [ "$sf_avail" = "False" ] || [ "$sf_degraded" = "True" ]; then
        stop "Spoke $mc: SpectrumFusion CR status is Degraded or Unavailable (Available=$sf_avail, Degraded=$sf_degraded, Status=$sf_status)"
        fusion_op_healthy=false
      else
        pass "Spoke $mc: SpectrumFusion CR is Healthy (Available=${sf_avail:-True}, Degraded=${sf_degraded:-False}, Status=${sf_status:-Completed})"
      fi
    fi
  elif [ "$spoke_has_base" = true ]; then
    warn "Spoke $mc carries fusion-base label but no SpectrumFusion CR found in $NS_FUSION"
  fi

  if spoke get pods -n "$NS_FUSION" --no-headers 2>/dev/null | grep -Ev ' Running | Completed ' | grep -q .; then
    warn "Spoke $mc: Some pods in $NS_FUSION are not Running/Completed (see $out_dir/clusters/${mc}_fusion_pods.txt)"
  else
    pass "Spoke $mc: All pods in $NS_FUSION are Running/Completed"
  fi

  failed_csvs=$(spoke get csv -n "$NS_FUSION" -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{": "}{.status.phase}{"\n"}{end}' 2>/dev/null | grep .) || true
  if [ -n "$failed_csvs" ]; then
    stop "Spoke $mc: ClusterServiceVersion(s) in $NS_FUSION not in Succeeded phase:\n$failed_csvs"
    fusion_op_healthy=false
  else
    pass "Spoke $mc: All CSVs in $NS_FUSION are Succeeded"
  fi

  # --------------------------------------------------------------------------
  # 8.3 Spoke ODF AddOn (fusion-fdf) Health & Consistency
  # --------------------------------------------------------------------------
  # Discover Spoke-side ODF resources
  odf_fsis=""
  if spoke get crd fusionserviceinstances.service.isf.ibm.com >/dev/null 2>&1; then
    odf_fsis=$(spoke get fusionserviceinstances -n "$NS_FUSION" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.installStatus.status}{" "}{.status.status}{"\n"}{end}' 2>/dev/null | grep -E 'odfmanager|data-foundation' || true)
  fi
  has_spoke_odf_agent=false
  if spoke get deploy odf-agent -n open-cluster-management-agent-addon >/dev/null 2>&1; then
    has_spoke_odf_agent=true
  fi
  spoke_sc_list=$(spoke get storageclients.ocs.openshift.io -A -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep . || true)
  spoke_odf_sc=$(spoke get sc -o jsonpath='{range .items[?(@.provisioner=~".*rbd.csi.ceph.com|.*cephfs.csi.ceph.com")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep . || true)

  # Direction 2 Consistency: Spoke ODF Resources -> Missing Hub Label
  if [ "$spoke_has_fdf" = false ]; then
    spoke_odf_res=""
    [ -n "$odf_fsis" ] && spoke_odf_res="ODF FSI ($(echo "$odf_fsis" | awk '{print $1}' | tr '\n' ' '))"
    [ "$has_spoke_odf_agent" = true ] && spoke_odf_res="${spoke_odf_res:+$spoke_odf_res, }odf-agent deployment"
    [ -n "$spoke_sc_list" ] && spoke_odf_res="${spoke_odf_res:+$spoke_odf_res, }StorageClient ($spoke_sc_list)"
    [ -n "$spoke_odf_sc" ] && spoke_odf_res="${spoke_odf_res:+$spoke_odf_res, }Ceph StorageClasses ($spoke_odf_sc)"

    if [ -n "$spoke_odf_res" ]; then
      stop "Spoke $mc has ODF/FDF resources deployed ($spoke_odf_res) but ManagedCluster on Hub is MISSING label 'isf.ibm.com/fusion-fdf'. (Direction 2 Desync: Spoke resources exist without Hub label - TS023322996 incident state). NOT SAFE TO UPGRADE!"
      fusion_op_healthy=false
    fi
  fi

  # Validate ODF FusionServiceInstance in -n ibm-spectrum-fusion-ns (ensure in Completed)
  if [ -n "$odf_fsis" ]; then
    while read -r fsi_name fsi_inst_st fsi_st; do
      [ -z "$fsi_name" ] && continue
      st="${fsi_inst_st}"
      [ -z "$st" ] && st="${fsi_st}"
      if [ "$st" = "Completed" ]; then
        pass "Spoke $mc: ODF FusionServiceInstance '$fsi_name' is Completed"
      else
        stop "Spoke $mc: ODF FusionServiceInstance '$fsi_name' is in '${st:-Unknown}' status (expected Completed)"
        fusion_op_healthy=false
      fi
    done <<< "$odf_fsis"
  elif [ "$spoke_has_fdf" = true ]; then
    warn "Spoke $mc carries fusion-fdf label but no ODF FusionServiceInstance found in $NS_FUSION"
  fi

  # Validate odf-agent in -n open-cluster-management-agent-addon
  save "clusters/${mc}_agent_odf.txt" spoke get deploy odf-agent -n open-cluster-management-agent-addon -o wide
  if [ "$has_spoke_odf_agent" = true ]; then
    odf_want=$(spoke get deploy odf-agent -n open-cluster-management-agent-addon -o jsonpath='{.spec.replicas}' 2>/dev/null)
    odf_ready=$(spoke get deploy odf-agent -n open-cluster-management-agent-addon -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [ "${odf_want:-0}" -gt 0 ] && [ "${odf_ready:-0}" = "$odf_want" ]; then
      pass "Spoke $mc: odf-agent deployment is Healthy in open-cluster-management-agent-addon (${odf_ready}/${odf_want} ready)"
    else
      stop "Spoke $mc: odf-agent deployment has ${odf_ready:-0}/${odf_want:-0} ready replicas in open-cluster-management-agent-addon"
      fusion_op_healthy=false
    fi
  elif [ "$spoke_has_fdf" = true ]; then
    warn "Spoke $mc carries fusion-fdf label but Deployment odf-agent was not found in open-cluster-management-agent-addon"
  fi

  # Validate ODF CSV
  if spoke get ns "$NS_STORAGE" >/dev/null 2>&1; then
    save "clusters/${mc}_storage_csv.txt" spoke get csv -n "$NS_STORAGE"
    failed_odf_csvs=$(spoke get csv -n "$NS_STORAGE" -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{": "}{.status.phase}{"\n"}{end}' 2>/dev/null | grep .) || true
    if [ -n "$failed_odf_csvs" ]; then
      stop "Spoke $mc: ODF ClusterServiceVersion(s) in $NS_STORAGE not Succeeded:\n$failed_odf_csvs"
      fusion_op_healthy=false
    else
      pass "Spoke $mc: All CSVs in $NS_STORAGE are Succeeded"
    fi

    # Validate Pods in -n openshift-storage
    save "clusters/${mc}_storage_pods.txt" spoke get pods -n "$NS_STORAGE" -o wide
    if spoke get pods -n "$NS_STORAGE" --no-headers 2>/dev/null | grep -Ev ' Running | Completed ' | grep -q .; then
      warn "Spoke $mc: Some pods in $NS_STORAGE are not Running/Completed (see $out_dir/clusters/${mc}_storage_pods.txt)"
    else
      pass "Spoke $mc: All pods in $NS_STORAGE are Running/Completed"
    fi
  fi

  # StorageClient & Heartbeat status-reporter
  save "clusters/${mc}_storageclients.txt" spoke get storageclients.ocs.openshift.io -A -o yaml
  sc_deleting=$(spoke get storageclients.ocs.openshift.io -A -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep .) || true
  if [ -n "$sc_deleting" ]; then
    stop "Spoke $mc has StorageClient object(s) stuck in DELETION state: $sc_deleting"
  fi

  sc_phases=$(spoke get storageclients.ocs.openshift.io -A -o custom-columns=NAME:.metadata.name,PHASE:.status.phase --no-headers 2>/dev/null | grep .) || true
  if [ -n "$sc_phases" ]; then
    note "Spoke $mc StorageClient status:\n$sc_phases"
    if echo "$sc_phases" | grep -vqi 'Connected\|Ready'; then
      stop "Spoke $mc: StorageClient is not in Connected/Ready phase:\n$sc_phases"
    else
      pass "Spoke $mc: StorageClient is Connected"
    fi
  fi

  for p in $(spoke get pods -n "$NS_STORAGE" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | grep status-reporter); do
    if spoke logs -n "$NS_STORAGE" "$p" --tail=200 2>/dev/null | grep -qi 'no storageConsumer found'; then
      stop "Spoke $mc: status-reporter pod '$p' reports 'no storageConsumer found'. StorageConsumer missing on Hub!"
    fi
  done

  # Check 8 (ODF part): No Terminating PVCs on Data Foundation (Ceph) StorageClasses
  audit_terminating_pvcs "$mc" "Data Foundation (Ceph)" 'ceph[.]com|openshift-storage'

  # --------------------------------------------------------------------------
  # 8.4 Spoke Backup AddOn (fusion-backup) Health & Consistency
  # --------------------------------------------------------------------------
  # Discover Spoke-side Backup resources
  backup_fsis=""
  if spoke get crd fusionserviceinstances.service.isf.ibm.com >/dev/null 2>&1; then
    backup_fsis=$(spoke get fusionserviceinstances -n "$NS_FUSION" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.installStatus.status}{" "}{.status.status}{"\n"}{end}' 2>/dev/null | grep -E 'backup-restore|dataprotection' || true)
  fi
  has_spoke_ba=false
  if spoke get deploy backup-agent -n open-cluster-management-agent-addon >/dev/null 2>&1; then
    has_spoke_ba=true
  fi
  # Require at least one Connection object: `get` succeeds when the CRD is installed
  # but has no instances, which is not a deployed backup resource.
  has_spoke_conn=false
  if spoke get connections.application.isf.ibm.com -n "$NS_FUSION" \
       -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -q .; then
    has_spoke_conn=true
  fi
  spoke_backup_csvs=""
  if spoke get ns "$NS_BACKUP" >/dev/null 2>&1; then
    spoke_backup_csvs=$(spoke get csv -n "$NS_BACKUP" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep . || true)
  fi

  # Direction 2 Consistency: Spoke Backup Resources -> Missing Hub Label
  if [ "$spoke_has_backup" = false ]; then
    spoke_backup_res=""
    [ -n "$backup_fsis" ] && spoke_backup_res="Backup FSI ($(echo "$backup_fsis" | awk '{print $1}' | tr '\n' ' '))"
    [ "$has_spoke_ba" = true ] && spoke_backup_res="${spoke_backup_res:+$spoke_backup_res, }backup-agent deployment"
    [ "$has_spoke_conn" = true ] && spoke_backup_res="${spoke_backup_res:+$spoke_backup_res, }Backup Connection CR"
    [ -n "$spoke_backup_csvs" ] && spoke_backup_res="${spoke_backup_res:+$spoke_backup_res, }Backup CSV ($spoke_backup_csvs)"

    if [ -n "$spoke_backup_res" ]; then
      stop "Spoke $mc has Backup/Restore resources deployed ($spoke_backup_res) but ManagedCluster on Hub is MISSING label 'isf.ibm.com/fusion-backup'. (Direction 2 Desync: Spoke resources exist without Hub label). NOT SAFE TO UPGRADE!"
      fusion_op_healthy=false
    fi
  fi

  # Validate Backup/Restore Client FusionServiceInstance in -n ibm-spectrum-fusion-ns (ensure in Completed)
  if [ -n "$backup_fsis" ]; then
    while read -r fsi_name fsi_inst_st fsi_st; do
      [ -z "$fsi_name" ] && continue
      st="${fsi_inst_st}"
      [ -z "$st" ] && st="${fsi_st}"
      if [ "$st" = "Completed" ]; then
        pass "Spoke $mc: Backup/Restore FusionServiceInstance '$fsi_name' is Completed"
      else
        stop "Spoke $mc: Backup/Restore FusionServiceInstance '$fsi_name' is in '${st:-Unknown}' status (expected Completed)"
        fusion_op_healthy=false
      fi
    done <<< "$backup_fsis"
  elif [ "$spoke_has_backup" = true ]; then
    warn "Spoke $mc carries fusion-backup label but no Backup/Restore FusionServiceInstance found in $NS_FUSION"
  fi

  # Validate backup-agent in -n open-cluster-management-agent-addon
  save "clusters/${mc}_agent_backup.txt" spoke get deploy backup-agent -n open-cluster-management-agent-addon -o wide
  if [ "$has_spoke_ba" = true ]; then
    ba_want=$(spoke get deploy backup-agent -n open-cluster-management-agent-addon -o jsonpath='{.spec.replicas}' 2>/dev/null)
    ba_ready=$(spoke get deploy backup-agent -n open-cluster-management-agent-addon -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [ "${ba_want:-0}" -gt 0 ] && [ "${ba_ready:-0}" = "$ba_want" ]; then
      pass "Spoke $mc: backup-agent deployment is Healthy in open-cluster-management-agent-addon (${ba_ready}/${ba_want} ready)"
    else
      stop "Spoke $mc: backup-agent deployment has ${ba_ready:-0}/${ba_want:-0} ready replicas in open-cluster-management-agent-addon"
      fusion_op_healthy=false
    fi
  elif [ "$spoke_has_backup" = true ]; then
    warn "Spoke $mc carries fusion-backup label but Deployment backup-agent was not found in open-cluster-management-agent-addon"
  fi

  # Validate Backup-Restore CSV
  if spoke get ns "$NS_BACKUP" >/dev/null 2>&1; then
    save "clusters/${mc}_backup_csv.txt" spoke get csv -n "$NS_BACKUP"
    failed_backup_csvs=$(spoke get csv -n "$NS_BACKUP" -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{": "}{.status.phase}{"\n"}{end}' 2>/dev/null | grep .) || true
    if [ -n "$failed_backup_csvs" ]; then
      stop "Spoke $mc: Backup-Restore CSV(s) in $NS_BACKUP not Succeeded:\n$failed_backup_csvs"
      fusion_op_healthy=false
    else
      pass "Spoke $mc: All CSVs in $NS_BACKUP are Succeeded"
    fi

    # Validate Pods in -n ibm-backup-restore
    save "clusters/${mc}_backup_pods.txt" spoke get pods -n "$NS_BACKUP" -o wide
    if spoke get pods -n "$NS_BACKUP" --no-headers 2>/dev/null | grep -Ev ' Running | Completed ' | grep -q .; then
      warn "Spoke $mc: Some pods in $NS_BACKUP are not Running/Completed (see $out_dir/clusters/${mc}_backup_pods.txt)"
    else
      pass "Spoke $mc: All pods in $NS_BACKUP are Running/Completed"
    fi
  fi

  # Validate Connection CR for Backup
  if [ "$has_spoke_conn" = true ]; then
    conn_deleting=$(spoke get connections.application.isf.ibm.com -n "$NS_FUSION" -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep .) || true
    if [ -n "$conn_deleting" ]; then
      stop "Spoke $mc: Backup Connection CR is stuck in DELETION state: $conn_deleting"
    fi
    conn_status=$(spoke get connections.application.isf.ibm.com -n "$NS_FUSION" -o jsonpath='{.items[*].status.status}' 2>/dev/null || true)
    note "Spoke $mc Backup Connection status: ${conn_status:-unknown}"
  fi

  # Check 6: In-flight / incomplete Backup & Restore operations
  audit_inflight_ops "$mc" backups.data-protection.isf.ibm.com "Fusion Backup"
  audit_inflight_ops "$mc" restores.data-protection.isf.ibm.com "Fusion Restore"
  audit_inflight_ops "$mc" backups.velero.io "Velero/OADP Backup"

  # --------------------------------------------------------------------------
  # 8.5 Spoke GDP Remote Mount AddOn (fusion-gdp-rm) Health & Consistency
  # --------------------------------------------------------------------------
  # Discover Spoke-side GDP resources
  gdp_fsis=""
  if spoke get crd fusionserviceinstances.service.isf.ibm.com >/dev/null 2>&1; then
    gdp_fsis=$(spoke get fusionserviceinstances -n "$NS_FUSION" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.service\.isf\.ibm\.com/name}{" "}{.status.installStatus.status}{" "}{.status.status}{"\n"}{end}' 2>/dev/null | grep -E 'gdp-remote-mount|remotemount|scale' || true)
  fi
  has_spoke_rma=false
  if spoke get deploy remotemount-agent -n open-cluster-management-agent-addon >/dev/null 2>&1; then
    has_spoke_rma=true
  fi
  spoke_scale_sc=$(spoke get sc -o jsonpath='{range .items[?(@.provisioner=="spectrumscale.csi.ibm.com")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep . || true)
  gdp_csvs=$(spoke get csv -A -o jsonpath='{range .items[?(@.metadata.name=~"spectrum-scale.*|scale.*")]}{.metadata.namespace}{"/"}{.metadata.name}{": "}{.status.phase}{"\n"}{end}' 2>/dev/null | grep . || true)

  # Direction 2 Consistency: Spoke GDP Resources -> Missing Hub Label
  if [ "$spoke_has_rm" = false ]; then
    spoke_rm_res=""
    [ -n "$gdp_fsis" ] && spoke_rm_res="GDP FSI ($(echo "$gdp_fsis" | awk '{print $1}' | tr '\n' ' '))"
    [ "$has_spoke_rma" = true ] && spoke_rm_res="${spoke_rm_res:+$spoke_rm_res, }remotemount-agent deployment"
    [ -n "$spoke_scale_sc" ] && spoke_rm_res="${spoke_rm_res:+$spoke_rm_res, }Scale CSI StorageClasses ($spoke_scale_sc)"
    [ -n "$gdp_csvs" ] && spoke_rm_res="${spoke_rm_res:+$spoke_rm_res, }GDP CSVs"

    if [ -n "$spoke_rm_res" ]; then
      stop "Spoke $mc has GDP Remote Mount resources deployed ($spoke_rm_res) but ManagedCluster on Hub is MISSING label 'isf.ibm.com/fusion-gdp-rm'. (Direction 2 Desync: Spoke resources exist without Hub label). NOT SAFE TO UPGRADE!"
      fusion_op_healthy=false
    fi
  fi

  # Validate GDP FusionServiceInstance in -n ibm-spectrum-fusion-ns (ensure in Completed)
  if [ -n "$gdp_fsis" ]; then
    while read -r fsi_name fsi_ann fsi_inst_st fsi_st; do
      [ -z "$fsi_name" ] && continue
      st="${fsi_inst_st}"
      [ -z "$st" ] && st="${fsi_st}"
      if [ "$st" = "Completed" ]; then
        pass "Spoke $mc: GDP Remote Mount FusionServiceInstance '$fsi_name' is Completed"
      else
        stop "Spoke $mc: GDP Remote Mount FusionServiceInstance '$fsi_name' is in '${st:-Unknown}' status (expected Completed)"
        fusion_op_healthy=false
      fi
    done <<< "$gdp_fsis"
  elif [ "$spoke_has_rm" = true ]; then
    warn "Spoke $mc carries fusion-gdp-rm label but no GDP FusionServiceInstance found in $NS_FUSION"
  fi

  # Validate remotemount-agent in -n open-cluster-management-agent-addon
  save "clusters/${mc}_agent_remotemount.txt" spoke get deploy remotemount-agent -n open-cluster-management-agent-addon -o wide
  if [ "$has_spoke_rma" = true ]; then
    rm_want=$(spoke get deploy remotemount-agent -n open-cluster-management-agent-addon -o jsonpath='{.spec.replicas}' 2>/dev/null)
    rm_ready=$(spoke get deploy remotemount-agent -n open-cluster-management-agent-addon -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [ "${rm_want:-0}" -gt 0 ] && [ "${rm_ready:-0}" = "$rm_want" ]; then
      pass "Spoke $mc: remotemount-agent deployment is Healthy in open-cluster-management-agent-addon (${rm_ready}/${rm_want} ready)"
    else
      stop "Spoke $mc: remotemount-agent deployment has ${rm_ready:-0}/${rm_want:-0} ready replicas in open-cluster-management-agent-addon"
      fusion_op_healthy=false
    fi
  elif [ "$spoke_has_rm" = true ]; then
    warn "Spoke $mc carries fusion-gdp-rm label but Deployment remotemount-agent was not found in open-cluster-management-agent-addon"
  fi

  # Validate GDP CSV
  if [ -n "$gdp_csvs" ]; then
    failed_gdp_csvs=$(echo "$gdp_csvs" | grep -v 'Succeeded' || true)
    if [ -n "$failed_gdp_csvs" ]; then
      stop "Spoke $mc: GDP CSV(s) not in Succeeded phase:\n$failed_gdp_csvs"
      fusion_op_healthy=false
    else
      pass "Spoke $mc: All GDP CSVs are Succeeded"
    fi
  elif [ "$spoke_has_rm" = true ]; then
    warn "Spoke $mc carries fusion-gdp-rm label but no Scale/GDP CSVs found"
  fi

  # Check 8 (Scale part): No Terminating PVCs on Scale CSI StorageClasses
  audit_terminating_pvcs "$mc" "GDP Remote Mount (Scale CSI)" 'spectrumscale[.]csi[.]ibm[.]com'

  # Record matrix row
  op_summary="HEALTHY"
  [ "$fusion_op_healthy" = false ] && op_summary="DEGRADED"
  
  readiness="READY"
  if [ "$op_summary" != "HEALTHY" ] || [ "$stuck_deletions_count" -gt 0 ] || [ "$spoke_extra_blockers" -gt 0 ]; then
    readiness="NOT_READY"
  fi

  printf "%-20s | %-12s | %-16s | %-16s | %-10s\n" "$mc" "CONNECTED" "$op_summary" "$stuck_deletions_count" "$readiness" >> "$matrix_file"
done <<< "$mc_list"

# ==============================================================================
# SECTION 9: REDACTION PASS
# ==============================================================================
section "9. REDACTION PASS"

if [ "$SKIP_REDACTION" = true ] || [ "$SKIP_REDACTION" = "1" ]; then
  note "Redaction pass skipped per configuration (--skip-redaction)."
else
  # onboardingTicket is a credential (StorageClient spec, possibly copied elsewhere); also JWT-like tokens
  # and common secret keys. Applied to every saved file, including snapshots and the controller log.
  find "$out_dir" -type f ! -name SUMMARY.txt ! -name matrix_rows.txt -print0 | while IFS= read -r -d '' f; do
    sed -E \
      -e 's/(onboardingTicket"?:[[:space:]]*"?)[^",}[:space:]]+/\1<redacted>/g' \
      -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*/<redacted-jwt>/g' \
      -e 's/((password|token|apikey|api_key|secret)"?:[[:space:]]*"?)[^",}[:space:]]+/\1<redacted>/gI' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
  note "Redaction pass done (onboardingTicket, JWT-like strings, password/token/apikey/secret values). Review the directory before sharing."
fi

# ==============================================================================
# SECTION 10: SUMMARY REPORT & UPGRADE READINESS VERDICT
# ==============================================================================
section "10. WORKFLOW STATUS SUMMARY & VERDICT"

{
  echo "================================================================================"
  echo " IBM FUSION MANAGEDCLUSTER PRE-UPGRADE READINESS MATRIX"
  echo " Generated: $(date -u +%FT%TZ)"
  echo "================================================================================"
  printf "%-20s | %-12s | %-16s | %-16s | %-10s\n" "CLUSTER NAME" "SPOKE LINK" "FUSION OPERATOR" "STUCK DELETIONS" "READINESS"
  echo "--------------------------------------------------------------------------------"
  if [ -s "$matrix_file" ]; then
    cat "$matrix_file"
  else
    echo "No ManagedClusters checked."
  fi
  echo "================================================================================"
} | tee "$report_file"

echo ""
echo -e "${C_BOLD}Total Passed Checks  :${C_RESET} ${C_GREEN}$passes${C_RESET}"
echo -e "${C_BOLD}Total Warnings Found :${C_RESET} ${C_YELLOW}$warns${C_RESET}"
echo -e "${C_BOLD}Total STOP (Blockers):${C_RESET} ${C_RED}$stops${C_RESET}"
echo ""

if [ "$stops" -gt 0 ]; then
  echo -e "${C_RED}${C_BOLD}********************************************************************************${C_RESET}"
  echo -e "${C_RED}${C_BOLD} RESULT: NOT SAFE TO UPGRADE! ($stops critical blocker(s) detected)${C_RESET}"
  echo -e "${C_RED}${C_BOLD} Do NOT initiate upgrade. Review $summary and resolve all STOP issues.${C_RESET}"
  echo -e "${C_RED}${C_BOLD}********************************************************************************${C_RESET}"
  printf "\nRESULT: NOT SAFE TO UPGRADE (STOP=%d, WARN=%d). Review %s\n" "$stops" "$warns" "$summary" >> "$summary"
  exit 2
fi

if [ "$warns" -gt 0 ]; then
  echo -e "${C_YELLOW}${C_BOLD}********************************************************************************${C_RESET}"
  echo -e "${C_YELLOW}${C_BOLD} RESULT: SAFE TO UPGRADE WITH WARNINGS ($warns warning(s) found)${C_RESET}"
  echo -e "${C_YELLOW}${C_BOLD} Review $summary with your administrator or IBM Support before upgrading.${C_RESET}"
  echo -e "${C_YELLOW}${C_BOLD}********************************************************************************${C_RESET}"
  printf "\nRESULT: SAFE TO UPGRADE WITH WARNINGS (WARN=%d). Review %s\n" "$warns" "$summary" >> "$summary"
  exit 0
else
  echo -e "${C_GREEN}${C_BOLD}********************************************************************************${C_RESET}"
  echo -e "${C_GREEN}${C_BOLD} RESULT: SAFE TO UPGRADE (All checks passed cleanly)${C_RESET}"
  echo -e "${C_GREEN}${C_BOLD} All checked ManagedClusters, addons, and Fusion operators are in healthy states.${C_RESET}"
  echo -e "${C_GREEN}${C_BOLD}********************************************************************************${C_RESET}"
  printf "\nRESULT: SAFE TO UPGRADE (All checks passed cleanly).\n" >> "$summary"
  exit 0
fi
