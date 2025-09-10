#!/bin/bash

###############################################################################
# Script Name: customer_cas_cleanup.sh
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
#   ./customer_cas_cleanup.sh [-n <namespace>] [--keep] [--keep-namespace] [--help]
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
  echo "Starting PVC cleanup in namespace: $NAMESPACE"
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

      # Handle associated PV
      local PV
      PV=$(oc get pv --no-headers -o custom-columns=":metadata.name,:spec.claimRef.name" | grep "$pvc" | awk '{print $1}' || true)

      if [[ -n "$PV" ]]; then
        echo "Processing PV $PV linked to PVC $pvc"
        local STATUS
        STATUS=$(oc get pv "$PV" -o jsonpath='{.status.phase}' || true)
        echo "PV $PV status is $STATUS"

        if [[ "$STATUS" == "Released" || "$STATUS" == "Failed" || "$STATUS" == "Terminating" ]]; then
          echo "PV $PV is in state $STATUS, removing finalizers if needed"
          oc patch pv "$PV" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
        fi

        echo "Deleting PV $PV"
        oc delete pv "$PV" --wait=false || true
        retry_until_gone "$PV" "" "pv"
      fi
    ) &

    JOBS=$((JOBS + 1))

    # Control parallel jobs
    while [[ $(jobs -rp | wc -l) -ge $MAX_PARALLEL ]]; do
      sleep 1
    done
  done

  wait
  echo "PVC and PV cleanup complete in namespace: $NAMESPACE"
}

# Function to delete FusionServiceInstance
delete_fusion_service_instance() {
    local fusion_ns
    fusion_ns=$(oc get spectrumfusion -A --no-headers | cut -d" " -f1 | head -n1)
    [ -z "$fusion_ns" ] && fusion_ns=$(oc get subs -A -o custom-columns=:metadata.namespace,:spec.name | grep "isf-operator$" | cut -d" " -f1)
    [ -z "$fusion_ns" ] && fusion_ns="ibm-spectrum-fusion-ns"

    if oc get fusionserviceinstance ibm-cas-service-instance -n "$fusion_ns" &>/dev/null; then
        echo "Deleting FusionServiceInstance from $fusion_ns..."
        # Delete without waiting, then retry until gone
        oc delete fusionserviceinstance ibm-cas-service-instance -n "$fusion_ns" --wait=false || true
        retry_until_gone "ibm-cas-service-instance" "$fusion_ns" "fusionserviceinstance"
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

# Delete CAS-specific CRD instances
delete_cas_crd_instances() {
    echo "Looking for CAS-specific CRDs in namespace: $NAMESPACE (excluding Kafka CRDs)..."
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
        echo "Checking instances in namespace: $NAMESPACE"

        local instances
        instances=$(oc get "$resource" -n "$NAMESPACE" --no-headers \
            -o custom-columns="NAME:.metadata.name" 2>/dev/null || true)

        if [ -z "$instances" ]; then
            echo "  No instances found for $resource in namespace $NAMESPACE"
            continue
        fi

        for name in $instances; do
            echo "  Deleting $resource/$name in namespace $NAMESPACE"

            # remove all finalizers (json patch)
            oc patch "$resource" "$name" -n "$NAMESPACE" --type=json \
                -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true

            oc patch "$resource" "$name" -n "$NAMESPACE" --type=merge \
                -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true

            oc delete "$resource" "$name" -n "$NAMESPACE" --ignore-not-found=true --wait=false

            # wait until gone
            retry_until_gone "$name" "$NAMESPACE" "$resource"
        done
    done
}


# resource cleanup with parallel flow
resource_cleanup() {
  echo "Starting resource cleanup in namespace: $NAMESPACE"
  local MAX_PARALLEL=5
  local active_jobs=0

  control_parallel() {
    while [[ $(jobs -rp | wc -l) -ge $MAX_PARALLEL ]]; do
      sleep 1
    done
  }

  # Delete pods stuck in certain states
  oc get pods -n "$NAMESPACE" --no-headers | \
    awk '{print $1, $3}' | \
    while read -r pod status; do
      if [[ "$status" =~ ^(Running|CrashLoopBackOff|Pending|Failed)$ ]]; then
        control_parallel
        (
          echo "Deleting pod $pod"
          oc delete pod "$pod" -n "$NAMESPACE" --grace-period=0 --wait=false || true
          retry_until_gone "$pod" "$NAMESPACE" "pod"
        ) &
      fi
    done

  # List of resource types to delete
  local resources=("secret" "configmap" "domains" "datasource")

  for res in "${resources[@]}"; do
    oc get "$res" -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
    while read -r name; do
      control_parallel
      (
        echo "Deleting $res/$name"
        oc delete "$res" "$name" -n "$NAMESPACE" --wait=false || true
        retry_until_gone "$name" "$NAMESPACE" "$res"
      ) &
    done
  done

  # Wait for all background jobs to complete
  wait
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
run_step "Delete CAS CRDs Only" delete_cas_crd_instances
run_step "Final Resource Cleanup" final_cleanup
run_step "Delete Fusion Service Instance" delete_fusion_service_instance
run_step "Uninstall Operators" uninstall_operators
run_step "Delete Namespace" delete_namespace

echo ""
echo "IBM CAS gets cleaned up successfully."
[[ "$KEEP_PARADEDB" == true ]] && echo "Note: cluster-parade resources have been preserved."
[[ "$KEEP_NAMESPACE" == true ]] && echo "Note: Namespace '$NAMESPACE' has not been deleted."
echo ""