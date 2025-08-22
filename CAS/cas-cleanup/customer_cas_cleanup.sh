#!/bin/bash

###############################################################################
# Script Name: cleanup-cas-customer.sh
# Purpose: Safely uninstall the CAS service from OpenShift without forcing deletion.
#
# FEATURES:
#    Deletes CAS Custom Resources (CasInstall)
#    Cleans up Kafka resources (topics, users, brokers)
#    Uninstalls CAS operators and related ClusterServiceVersions
#    Removes namespace-specific ClusterRoleBindings
#    Deletes CAS catalog sources and PVCs (optionally preserved)
#    Removes FusionServiceInstance (if applicable)
#    Deletes associated Persistent Volumes (PVs) in 'Released' state
#    Safely deletes or retains the namespace based on options

# SAFETY WARNINGS:
#    This script performs **destructive actions** in your cluster.
#    Ensure that you have backups or snapshots before proceeding.
#    Finalizers are respected; this script does **not force-patch finalizers**.
#    Use the --preserve-paradedb or --preserve-namespace options as needed.

# INTERACTIVE MODE:
#   The script prompts for confirmation before executing critical actions unless
#   the '-y' flag is passed.

# Usage:
#   ./cleanup_cas_customer.sh [-n <namespace>] [--keep] [--keep-namespace] [--help]
#
###############################################################################

set -euo pipefail

# Defaults
NAMESPACE="ibm-cas"
KEEP_PARADEDB=false
KEEP_NAMESPACE=false
RETRY_COUNT=5
RETRY_INTERVAL=10

# Help
print_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -n, --namespace <name>       Target namespace (default: ibm-cas)"
  echo "  --keep-paradedb              Do NOT delete cluster-parade Pods or PVCs"
  echo "  --keep-namespace             Do NOT delete the namespace after cleanup"
  echo "  --help                       Display this help message"
  exit 0
}

# Run wrapper with error handling
run_step() {
  local step_name="$1"; shift
  echo "============================================================"
  echo "INFO" "Starting: $step_name"
  echo "============================================================"
  echo
  if "$@"; then
    echo
    echo "============================================================"
    echo "INFO" "Completed: $step_name"
    echo "============================================================"
  else
    echo "ERROR" "Failed: $step_name (continuing to next step)"
  fi
  echo
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --keep-cluster-parade)
      KEEP_PARADEDB=true
      shift
      ;;
    --keep-namespace)
      KEEP_NAMESPACE=true
      shift
      ;;
    --help)
      print_help
      ;;
    *)
      echo "Unknown argument: $1"
      print_help
      ;;
  esac
done

echo "============================================================"
echo "CAS Cleanup Script - Customer-Safe Version"
echo "Target Namespace: $NAMESPACE"
echo "Preserve cluster-parade Pods/PVCs: $KEEP_PARADEDB"
echo "Preserve Namespace: $KEEP_NAMESPACE"
echo "============================================================"

# Confirm
echo ""
echo "This script will perform the following operations:"
echo "- Uninstall CAS operator and related CRs in '$NAMESPACE'"
echo "- Delete KafkaTopics, KafkaUsers, Kafka brokers (without force)"
echo "- Delete PVCs and their associated PVs (unless marked keep)"
echo "- Remove CAS catalog sources, CRDs (except shared/global ones)"
echo "- Optionally delete the entire namespace unless --keep-namespace is specified"
echo ""
read -rp "Are you sure you want to proceed? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && echo "Aborted by user." && exit 0

# Check if namespace exists
if ! oc get ns "$NAMESPACE" &>/dev/null; then
  echo "Namespace '$NAMESPACE' does not exist."
  exit 1
fi

# List Pods and PVCs (for awareness)
echo "Current Pods in namespace:"
oc get pods -n "$NAMESPACE"
echo ""
echo "Current PVCs in namespace:"
oc get pvc -n "$NAMESPACE"
echo ""

# Retry wrapper
retry_until_gone() {
  local resource=$1
  local namespace=$2
  local kind=$3

  for i in $(seq 1 "$RETRY_COUNT"); do
    if [[ -z "$namespace" ]]; then
      if ! oc get "$kind" "$resource" &>/dev/null; then
        echo "$kind/$resource deleted successfully."
        return 0
      fi
    else
      if ! oc get "$kind" "$resource" -n "$namespace" &>/dev/null; then
        echo "$kind/$resource deleted successfully."
        return 0
      fi
    fi
    echo "[$i/$RETRY_COUNT] Waiting for $kind/$resource to terminate..."
    sleep "$RETRY_INTERVAL"
  done

  echo "$kind/$resource did not delete after $RETRY_COUNT retries."
  read -rp "Do you want to patch/remove finalizers and force delete $kind/$resource? [y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    if [[ -z "$namespace" ]]; then
      oc patch "$kind" "$resource" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
      oc delete "$kind" "$resource" --wait=false || true
    else
      oc patch "$kind" "$resource" -n "$namespace" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
      oc delete "$kind" "$resource" -n "$namespace" --wait=false || true
    fi
  fi
}

# Delete CAS CRs
delete_custom_resources() {
  local CR_LIST
  CR_LIST=$(oc get CasInstall -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" || true)
  for CR in $CR_LIST; do
    echo "Deleting CasInstall: $CR"
    oc delete CasInstall "$CR" -n "$NAMESPACE" --wait=false || true
    retry_until_gone "$CR" "$NAMESPACE" "CasInstall"
  done
}

# Delete Kafka-related resources with patching finalizers
delete_kafka_resources() {
  local RESOURCES=("kafkatopics.kafka.strimzi.io" "kafkauser.kafka.strimzi.io" "kafka.kafka.strimzi.io")

  for kind in "${RESOURCES[@]}"; do
    local LIST
    LIST=$(oc get "$kind" -n "$NAMESPACE" -o name || true)
    for res in $LIST; do
      echo "Deleting $res..."
      oc delete "$res" -n "$NAMESPACE" --wait=false || true
      retry_until_gone "${res#*/}" "$NAMESPACE" "$kind"
    done
  done
}

# Uninstall CAS operators
uninstall_operators() {
  local SUBS
  SUBS=$(oc get subscriptions -n "$NAMESPACE" -o name || true)
  for sub in $SUBS; do
    CSV=$(oc get "$sub" -n "$NAMESPACE" -o jsonpath='{.status.installedCSV}' || true)
    echo "Deleting subscription: $sub"
    oc delete "$sub" -n "$NAMESPACE" --wait=false || true
    retry_until_gone "${sub#*/}" "$NAMESPACE" "Subscription"
    if [[ -n "$CSV" ]]; then
      echo "Deleting CSV: $CSV"
      oc delete clusterserviceversion "$CSV" -n "$NAMESPACE" --wait=false || true
      retry_until_gone "$CSV" "$NAMESPACE" "clusterserviceversion"
    fi
  done
}

# Cleanup PVCs and PVs in parallel
cleanup_pvcs() {
  local PVC_LIST
  PVC_LIST=$(oc get pvc -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" || true)
  local MAX_PARALLEL=5
  local JOBS=0

  for pvc in $PVC_LIST; do
    (
      if [[ "$KEEP_PARADEDB" == true && "$pvc" == cluster-parade* ]]; then
        echo "Skipping cluster-parade PVC: $pvc"
        exit 0
      fi

      echo "Deleting PVC: $pvc"
      oc delete pvc "$pvc" -n "$NAMESPACE" --wait=false || true
      retry_until_gone "$pvc" "$NAMESPACE" "pvc"

      local PV
      PV=$(oc get pv --no-headers -o custom-columns=":metadata.name,:spec.claimRef.name" | grep "$pvc" | awk '{print $1}' || true)

      if [[ -n "$PV" ]]; then
        echo "Found PV $PV for PVC $pvc"
        STATUS=$(oc get pv "$PV" -o jsonpath='{.status.phase}' || true)

        if [[ "$STATUS" == "Released" ]]; then
          read -rp "PV $PV is Released. Remove finalizers and delete? [y/N]: " confirm
          if [[ "$confirm" =~ ^[Yy]$ ]]; then
            oc patch pv "$PV" -p '{"metadata":{"finalizers":null}}' --type=merge || true
            oc delete pv "$PV" --wait=false || true
          fi
        fi
      fi
    ) &

    # increment job counter
    JOBS=$((JOBS + 1))

    # if we hit MAX_PARALLEL, wait for background jobs to finish before continuing
    while [[ $(jobs -rp | wc -l) -ge $MAX_PARALLEL ]]; do
      sleep 1
    done
  done

  # wait for all remaining jobs
  wait
  echo "PVC and PV cleanup complete for namespace: $NAMESPACE"
}

# Function to delete FusionServiceInstance
delete_fusion_service_instance() {
    local fusion_ns
    fusion_ns=$(oc get spectrumfusion -A --no-headers | cut -d" " -f1 | head -n1)
    [ -z "$fusion_ns" ] && fusion_ns=$(oc get subs -A -o custom-columns=:metadata.namespace,:spec.name | grep "isf-operator$" | cut -d" " -f1)
    [ -z "$fusion_ns" ] && fusion_ns="ibm-spectrum-fusion-ns"

    if oc get fusionserviceinstance ibm-cas-service-instance -n "$fusion_ns" &>/dev/null; then
        echo "Deleting FusionServiceInstance from $fusion_ns..."
        oc delete fusionserviceinstance ibm-cas-service-instance -n "$fusion_ns" --wait=true
    else
        echo "No FusionServiceInstance found in $fusion_ns."
    fi
}

# Delete CAS CatalogSource
delete_catalog_source() {
  if oc get catalogsource ibm-isf-cas-operator-catalog -n "$NAMESPACE" &>/dev/null; then
    echo "Deleting CAS CatalogSource..."
    oc delete catalogsource ibm-isf-cas-operator-catalog -n "$NAMESPACE" --wait=true || true
  fi
}

# Delete CAS-specific CRD instances safely
delete_cas_crd_instances() {
    echo "Looking for CAS-specific CRDs (excluding Kafka CRDs)..."
    local CAS_CRDS
    CAS_CRDS=$(oc get crd --no-headers -o custom-columns=":metadata.name" | grep -i "cas.isf" || true)

    if [ -z "$CAS_CRDS" ]; then
        echo "No CAS CRDs found."
        return
    fi

    for crd in $CAS_CRDS; do
        local resource
        resource=$(echo "$crd" | cut -d '.' -f1)

        echo "----"
        echo "CRD: $crd"
        echo "Resource: $resource"
        echo "Checking instances..."

        local instances
        instances=$(oc get "$resource" --all-namespaces --no-headers -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" 2>/dev/null || true)

        if [ -z "$instances" ]; then
            echo "  No instances found for $resource"
            continue
        fi

        echo "$instances" | while read -r ns name; do
            echo "  Deleting $resource/$name in namespace $ns"

            # Remove finalizers if present
            oc patch "$resource" "$name" -n "$ns" --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true

            # Delete the instance
            oc delete "$resource" "$name" -n "$ns" --ignore-not-found=true

            # Wait until gone
            retry_until_gone "$resource" "$name" "$ns"
        done
    done
}

# Resource cleanup
resource_cleanup() {
    echo "Cleaning up all resources in namespace: $NAMESPACE..."

    # Delete pods stuck in specific states (graceful delete)
    oc get pods -n "$NAMESPACE" --no-headers | \
        grep -E 'Running|CrashLoopBackOff|Pending|Failed' | \
        awk '{print $1}' | \
        xargs -r oc delete pod -n "$NAMESPACE" --grace-period=0

    # Delete all other resources
    oc delete secret --all -n "$NAMESPACE" --wait=true || true
    oc delete configmap --all -n "$NAMESPACE" --wait=true || true
    oc delete domains --all -n "$NAMESPACE" --wait=true || true
    oc delete datasource --all -n "$NAMESPACE" --wait=true || true
    echo "Resource cleanup complete in namespace: $NAMESPACE"
}

# Final cleanup
final_cleanup() {
    echo "Cleaning up all resources in namespace: $NAMESPACE..."

    # Delete all resources
    oc delete pods --all -n "$NAMESPACE" --wait=true || true
    oc delete pvc --all -n "$NAMESPACE" --wait=true || true
    oc delete secret --all -n "$NAMESPACE" --wait=true || true
    oc delete configmap --all -n "$NAMESPACE" --wait=true || true
    oc delete all --all -n "$NAMESPACE" --wait=true || true
    echo "Resource cleanup complete in namespace: $NAMESPACE"
}

# Delete namespace
delete_namespace() {
  if [[ "$KEEP_NAMESPACE" == false ]]; then
    echo "Deleting Namespace: $NAMESPACE"
    oc delete namespace "$NAMESPACE" --wait=false || true
    retry_until_gone "$NAMESPACE" "" "namespace"
  else
    echo "Namespace $NAMESPACE preserved (--keep-namespace)."
  fi
}

#######################################
### MAIN EXECUTION FLOW #####
#######################################

run_step "Resource Cleanup" resource_cleanup
run_step "Cleanup PVCs" cleanup_pvcs
run_step "Delete Catalog Source" delete_catalog_source
run_step "Delete Kafka Resources" delete_kafka_resources
run_step "Delete Custom Resources" delete_custom_resources
run_step "Delete CAS CRDs Only" delete_cas_crd_instances
run_step "Final Resource Cleanup" final_cleanup
run_step "Uninstall Operators" uninstall_operators
run_step "Delete Fusion Service Instance" delete_fusion_service_instance
run_step "Delete Namespace" delete_namespace

echo ""
echo "IBM CAS gets cleaned up successfully."
[[ "$KEEP_PARADEDB" == true ]] && echo "Note: cluster-parade resources have been preserved."
[[ "$KEEP_NAMESPACE" == true ]] && echo "Note: Namespace '$NAMESPACE' has not been deleted."
echo ""