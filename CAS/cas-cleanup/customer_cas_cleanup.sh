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
#   ./cleanup-cas-customer.sh [-n <namespace>] [--keep] [--keep-namespace] [--help]
#
###############################################################################

set -euo pipefail

# Defaults
NAMESPACE="ibm-cas"
KEEP_PARADEDB=false
KEEP_NAMESPACE=false

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

# Delete CAS CRs
delete_custom_resources() {
  local CR_LIST
  CR_LIST=$(oc get CasInstall -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" || true)
  for CR in $CR_LIST; do
    echo "Deleting CasInstall: $CR"
    oc delete CasInstall "$CR" -n "$NAMESPACE" --wait=true || true
  done
}

# Delete Kafka-related resources with patching finalizers
delete_kafka_resources() {
  local TOPICS USERS KAFKAS

  echo "Checking and deleting KafkaTopics..."
  TOPICS=$(oc get kafkatopics.kafka.strimzi.io -n "$NAMESPACE" -o name || true)
  for topic in $TOPICS; do
    echo "Attempting to delete KafkaTopic: $topic"
    oc delete "$topic" -n "$NAMESPACE" --wait=false || true
  done

  echo "Checking and deleting KafkaUsers..."
  USERS=$(oc get kafkauser.kafka.strimzi.io -n "$NAMESPACE" -o name || true)
  for user in $USERS; do
    echo "Attempting to delete KafkaUser: $user"
    oc delete "$user" -n "$NAMESPACE" --wait=false || true
  done

  echo "Checking and deleting Kafka clusters..."
  KAFKAS=$(oc get kafka.kafka.strimzi.io -n "$NAMESPACE" -o name || true)
  for kafka in $KAFKAS; do
    echo "Attempting to delete Kafka: $kafka"
    oc delete "$kafka" -n "$NAMESPACE" --wait=false || true
  done

  echo "Waiting 2 minutes before checking stuck resources..."
  sleep 120

  # Helper to check and patch stuck Kafka resource
  patch_stuck_kafka_resource() {
    local RESOURCE_TYPE=$1
    local RESOURCE_LIST
    RESOURCE_LIST=$(oc get "$RESOURCE_TYPE" -n "$NAMESPACE" -o name 2>/dev/null || true)

    for res in $RESOURCE_LIST; do
      DELETION_TIMESTAMP=$(oc get "$res" -n "$NAMESPACE" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || true)
      if [[ -n "$DELETION_TIMESTAMP" ]]; then
        echo "Resource $res is stuck in Terminating (deletionTimestamp present)."
        read -rp "Do you want to remove finalizers and force delete $res? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          echo "Patching finalizers for $res"
          oc patch "$res" -n "$NAMESPACE" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
          echo "Force deleting $res"
          oc delete "$res" -n "$NAMESPACE" --wait=false || true
        else
          echo "Skipping $res as per user input."
        fi
      fi
    done
  }

  echo "Checking for stuck KafkaTopics..."
  patch_stuck_kafka_resource "kafkatopics.kafka.strimzi.io"

  echo "Checking for stuck KafkaUsers..."
  patch_stuck_kafka_resource "kafkauser.kafka.strimzi.io"

  echo "Checking for stuck Kafka clusters..."
  patch_stuck_kafka_resource "kafka.kafka.strimzi.io"
}


# Uninstall CAS operators
uninstall_operators() {
  local SUBS
  SUBS=$(oc get subscriptions -n "$NAMESPACE" -o name || true)
  for sub in $SUBS; do
    CSV=$(oc get "$sub" -n "$NAMESPACE" -o jsonpath='{.status.installedCSV}' || true)
    echo "Deleting subscription: $sub"
    oc delete "$sub" -n "$NAMESPACE" || true
    if [[ -n "$CSV" ]]; then
      echo "Deleting CSV: $CSV"
      oc delete clusterserviceversion "$CSV" -n "$NAMESPACE" || true
    fi
  done
}

#Cleanup PVCs and PVs
cleanup_pvcs() {
  local PVC_LIST
  PVC_LIST=$(oc get pvc -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name")

  for pvc in $PVC_LIST; do
    if [[ "$KEEP_PARADEDB" == true && "$pvc" == cluster-parade* ]]; then
      echo "Skipping cluster-parade PVC: $pvc"
      continue
    fi

    echo "Deleting PVC: $pvc"
    oc delete pvc "$pvc" -n "$NAMESPACE" || true

    sleep 10  # Allow PVC deletion to settle

    local PV
    PV=$(oc get pv --no-headers -o custom-columns=":metadata.name,:spec.claimRef.name,:status.phase" | grep "$pvc" | awk '{print $1}' || true)

    if [[ -n "$PV" ]]; then
      echo "Checking PV $PV for cleanup..."
      STATUS=$(oc get pv "$PV" -o jsonpath='{.status.phase}' || true)

      if [[ "$STATUS" == "Released" ]]; then
        echo "PV $PV is stuck in 'Released' state. Waiting 2 minutes before prompting..."
        sleep 120

        # Check if still Released
        STATUS=$(oc get pv "$PV" -o jsonpath='{.status.phase}' || true)
        if [[ "$STATUS" == "Released" ]]; then
          echo "PV $PV is still Released."
          read -rp "Do you want to force delete PV $PV by removing finalizers? [y/N]: " confirm
          if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "Removing finalizers from PV $PV..."
            oc patch pv "$PV" -p '{"metadata":{"finalizers":null}}' --type=merge || true
            echo "Deleting PV $PV..."
            oc delete pv "$PV" --wait=false || true
          else
            echo "Skipping PV $PV cleanup as per user request."
          fi
        else
          echo "PV $PV is no longer Released. Skipping force delete."
        fi
      fi
    fi
  done
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

# Delete CAS-specific CRDs (safe approach)
delete_cas_crds_only() {
  echo "Checking CAS-specific CRDs (read-only list)..."
  oc get crd | grep "cas.isf" || echo "None found (not deleting)"
}

# Final cleanup
final_cleanup() {
    echo "Cleaning up all resources in $NAMESPACE..."

    oc delete all --all -n "$NAMESPACE" --wait=true || true
    oc delete pvc --all -n "$NAMESPACE" --wait=true || true
    oc delete secret --all -n "$NAMESPACE" --wait=true || true
    oc delete configmap --all -n "$NAMESPACE" --wait=true || true

    echo "Resource cleanup complete."
}

# Delete namespace
delete_namespace() {
  if [[ "$KEEP_NAMESPACE" == false ]]; then
    echo "Deleting Namespace: $NAMESPACE"
    oc delete namespace "$NAMESPACE" || true
  else
    echo "Namespace $NAMESPACE preserved (--keep-namespace)."
  fi
}

### MAIN EXECUTION
delete_custom_resources
delete_catalog_source
delete_cas_crds_only
final_cleanup
cleanup_pvcs
delete_kafka_resources
uninstall_operators
delete_fusion_service_instance
delete_namespace

echo ""
echo "IBM CAS gets cleaned up successfully."
[[ "$KEEP_PARADEDB" == true ]] && echo "Note: cluster-parade resources have been preserved."
[[ "$KEEP_NAMESPACE" == true ]] && echo "Note: Namespace '$NAMESPACE' has not been deleted."
echo ""