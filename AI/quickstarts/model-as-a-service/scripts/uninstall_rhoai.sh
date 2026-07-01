#!/bin/bash

set -euo pipefail

# Helper function to delete resources with finalizer handling
delete_resource_with_finalizers() {
  local resource_type=$1
  local resource_name=$2
  local namespace=$3
  local timeout=${4:-30}
  
  if [ -n "$namespace" ]; then
    local ns_flag="-n $namespace"
  else
    local ns_flag="-A"
  fi
  
  if oc get $resource_type $resource_name $ns_flag &> /dev/null; then
    echo "Deleting $resource_type/$resource_name..."
    oc delete $resource_type $resource_name $ns_flag --timeout=${timeout}s 2>/dev/null || true
    
    # Wait a bit and check if still exists
    sleep 5
    
    if oc get $resource_type $resource_name $ns_flag &> /dev/null; then
      echo "Removing finalizers from $resource_type/$resource_name..."
      if [ -n "$namespace" ]; then
        oc patch $resource_type $resource_name -n $namespace -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      else
        # For cluster-scoped resources
        oc patch $resource_type $resource_name -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      fi
      sleep 2
    fi
  fi
}

# Helper function to delete all resources of a type with finalizer handling
delete_all_resources_with_finalizers() {
  local resource_type=$1
  local namespace=${2:-""}
  
  if [ -n "$namespace" ]; then
    local ns_flag="-n $namespace"
  else
    local ns_flag="--all-namespaces"
  fi
  
  echo "Deleting all $resource_type resources..."
  oc delete $resource_type --all $ns_flag --timeout=30s 2>/dev/null || true
  
  # Wait and remove finalizers from any stuck resources
  sleep 5
  local stuck_resources=$(oc get $resource_type $ns_flag -o name 2>/dev/null || true)
  
  if [ -n "$stuck_resources" ]; then
    echo "Removing finalizers from stuck $resource_type resources..."
    for resource in $stuck_resources; do
      if [ -n "$namespace" ]; then
        oc patch $resource -n $namespace -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      else
        # Get namespace for each resource
        local res_ns=$(oc get $resource -o jsonpath='{.metadata.namespace}' 2>/dev/null || echo "")
        if [ -n "$res_ns" ]; then
          oc patch $resource -n $res_ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        else
          oc patch $resource -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        fi
      fi
    done
  fi
}

echo "==========================================="
echo " OpenShift AI / ODH Complete Cleanup"
echo "==========================================="
echo ""
echo "This script follows the official Red Hat OpenShift AI uninstallation procedure:"
echo "1. Uninstall RHOAI operator"
echo "2. Delete MAAS platform resources"
echo "3. Delete RHOAI custom resources"
echo "4. Uninstall dependent operators"
echo "5. Clean up CRDs and remaining resources"
echo ""

echo "==========================================="
echo " Phase 1: Uninstall RHOAI Operator"
echo "==========================================="
echo ""
echo "Following official Red Hat OpenShift AI uninstallation procedure..."
echo ""

echo "Preflight Check: Verifying redhat-ods-operator namespace exists..."
if ! oc get namespace redhat-ods-operator &> /dev/null; then
  echo ""
  echo "ERROR: redhat-ods-operator namespace does not exist!"
  echo ""
  echo "The RHOAI operator namespace must exist to perform proper cleanup."
  echo "This could mean:"
  echo "  1. RHOAI was never installed"
  echo "  2. RHOAI operator was already uninstalled"
  echo "  3. The namespace was manually deleted"
  echo ""
  echo "Skipping Phase 1 (RHOAI Operator uninstallation)..."
  echo "Proceeding to Phase 4 (Dependent Operators cleanup)..."
  echo ""
else
  echo "✓ redhat-ods-operator namespace exists, proceeding with cleanup..."
  echo ""

echo "Step 1: Preparing ConfigMap for RHOAI operator deletion..."
if oc get namespace redhat-ods-operator &> /dev/null; then
  # Delete existing ConfigMap if present (to ensure clean state)
  if oc get configmap delete-self-managed-odh -n redhat-ods-operator &> /dev/null; then
    echo "Deleting existing ConfigMap..."
    oc delete configmap delete-self-managed-odh -n redhat-ods-operator --ignore-not-found=true
    sleep 2
  fi
  
  # Create fresh ConfigMap
  echo "Creating ConfigMap delete-self-managed-odh..."
  oc create configmap delete-self-managed-odh -n redhat-ods-operator
  echo "ConfigMap created successfully"
else
  echo "Namespace redhat-ods-operator does not exist, skipping ConfigMap creation"
fi

echo ""
echo "Step 2: Setting addon-managed-odh-delete label on ConfigMap..."
if oc get configmap delete-self-managed-odh -n redhat-ods-operator &> /dev/null; then
  oc label configmap/delete-self-managed-odh api.openshift.com/addon-managed-odh-delete=true -n redhat-ods-operator --overwrite
  echo "✓ Label set successfully"
else
  echo "ConfigMap not found, skipping label"
fi

echo ""
echo "Step 3: Waiting for RHOAI operator to delete redhat-ods-applications project..."
PROJECT_NAME=redhat-ods-applications

if oc get project $PROJECT_NAME &> /dev/null; then
  while oc get project $PROJECT_NAME &> /dev/null; do
    echo "The $PROJECT_NAME project still exists"
    sleep 1
  done
  echo "The $PROJECT_NAME project no longer exists"
else
  echo "The $PROJECT_NAME project does not exist"
fi

echo ""
echo "Step 4: Deleting redhat-ods-operator namespace..."
if oc get namespace redhat-ods-operator &> /dev/null; then
  oc delete namespace redhat-ods-operator --ignore-not-found=true
  echo "Namespace deletion initiated"
else
  echo "Namespace redhat-ods-operator does not exist"
fi

echo ""
echo "Step 5: Confirming rhods-operator subscription no longer exists..."
if oc get subscriptions --all-namespaces | grep -i rhods-operator &> /dev/null; then
  echo "WARNING: rhods-operator subscription still exists"
  oc get subscriptions --all-namespaces | grep rhods-operator
else
  echo "✓ rhods-operator subscription does not exist"
fi

echo ""
echo "Step 6: Verifying RHOAI projects are deleted..."
echo "Checking for remaining RHOAI-related projects:"
REMAINING_PROJECTS=$(oc get namespaces | grep -E 'redhat-ods-applications|redhat-ods-monitoring|redhat-ods-operator|rhods-notebooks' || true)
if [ -z "$REMAINING_PROJECTS" ]; then
  echo "✓ No RHOAI projects found"
else
  echo "WARNING: Found remaining RHOAI projects:"
  echo "$REMAINING_PROJECTS"
fi

fi  # End of redhat-ods-operator namespace check

echo ""
echo "==========================================="
echo " Phase 2: Delete MAAS Platform Resources"
echo "==========================================="

echo ""
echo "Step 7: Deleting Kuadrant instance..."
delete_resource_with_finalizers "kuadrant" "kuadrant" "kuadrant-system"
delete_all_resources_with_finalizers "kuadrant"

echo ""
echo "Step 7a: Deleting all Kuadrant CRD instances..."
# Get all CRDs with .kuadrant.io group
KUADRANT_CRDS=$(oc get crd -o name | grep '\.kuadrant\.io$' | sed 's|customresourcedefinition.apiextensions.k8s.io/||' || true)

if [ -n "$KUADRANT_CRDS" ]; then
  echo "Found Kuadrant CRDs: $KUADRANT_CRDS"
  
  for crd in $KUADRANT_CRDS; do
    echo "Processing CRD: $crd"
    
    # Delete all instances of this CRD across all namespaces
    echo "  Deleting all instances of $crd..."
    oc delete $crd --all --all-namespaces --timeout=30s 2>/dev/null || true
    
    # Wait and check for stuck resources
    sleep 3
    
    # Remove finalizers from any stuck instances
    STUCK_INSTANCES=$(oc get $crd --all-namespaces -o name 2>/dev/null || true)
    if [ -n "$STUCK_INSTANCES" ]; then
      echo "  Removing finalizers from stuck $crd instances..."
      for instance in $STUCK_INSTANCES; do
        INSTANCE_NS=$(oc get $instance -o jsonpath='{.metadata.namespace}' 2>/dev/null || echo "")
        if [ -n "$INSTANCE_NS" ]; then
          oc patch $instance -n $INSTANCE_NS -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        else
          oc patch $instance -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        fi
      done
      sleep 2
    fi
  done
  
  echo "All Kuadrant CRD instances deleted"
else
  echo "No Kuadrant CRDs found"
fi

echo ""
echo "Step 7b: Deleting Kuadrant CRDs..."
if [ -n "$KUADRANT_CRDS" ]; then
  for crd in $KUADRANT_CRDS; do
    echo "  Deleting CRD: $crd"
    # Start deletion in background with short timeout
    oc delete crd $crd --timeout=5s 2>/dev/null &
    DELETE_PID=$!
    
    # Wait a moment for deletion to start
    sleep 2
    
    # Force remove finalizers immediately if CRD still exists
    if oc get crd $crd &> /dev/null; then
      echo "  Forcing finalizer removal from CRD: $crd"
      oc patch crd $crd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      sleep 1
    fi
    
    # Wait for background delete to complete (if still running)
    wait $DELETE_PID 2>/dev/null || true
    
    # Final check and force delete if needed
    if oc get crd $crd &> /dev/null; then
      echo "  Force deleting CRD: $crd"
      oc delete crd $crd --force --grace-period=0 2>/dev/null || true
    fi
  done
  echo "All Kuadrant CRDs deleted"
fi

echo ""
echo "Step 8: Deleting LeaderWorkerSet operator instance..."
delete_resource_with_finalizers "leaderworkersetoperator" "cluster" "openshift-lws-operator"
delete_all_resources_with_finalizers "leaderworkersetoperator"

echo ""
echo "==========================================="
echo " Phase 3: Delete RHOAI Custom Resources"
echo "==========================================="

echo ""
echo "Step 9: Deleting DataScienceCluster resources..."
delete_all_resources_with_finalizers "datasciencecluster"

echo ""
echo "Step 10: Deleting DSCInitialization resources..."
delete_all_resources_with_finalizers "dscinitialization"

echo ""
echo "Step 11: Deleting Model Registry resources..."
delete_all_resources_with_finalizers "modelregistries.modelregistry.opendatahub.io"

echo ""
echo "Step 12: Deleting KServe resources..."
delete_all_resources_with_finalizers "inferenceservices.serving.kserve.io"
delete_all_resources_with_finalizers "servingruntimes.serving.kserve.io"
delete_all_resources_with_finalizers "inferencegraphs.serving.kserve.io"
delete_all_resources_with_finalizers "trainedmodels.serving.kserve.io"
delete_all_resources_with_finalizers "llminferenceservices.serving.kserve.io"
delete_all_resources_with_finalizers "llminferenceserviceconfigs.serving.kserve.io"
delete_all_resources_with_finalizers "clusterstoragecontainers.serving.kserve.io"

echo ""
echo "Step 13: Deleting Ray resources..."
delete_all_resources_with_finalizers "rayclusters.ray.io"
delete_all_resources_with_finalizers "rayjobs.ray.io"
delete_all_resources_with_finalizers "rayservices.ray.io"

echo ""
echo "Step 14: Deleting TrustyAI resources..."
delete_all_resources_with_finalizers "trustyaiservices.trustyai.opendatahub.io"
delete_all_resources_with_finalizers "lmevaljobs.trustyai.opendatahub.io"
delete_all_resources_with_finalizers "nemoguardrails.trustyai.opendatahub.io"
delete_all_resources_with_finalizers "guardrailsorchestrators.trustyai.opendatahub.io"

echo ""
echo "==========================================="
echo " Phase 4: Uninstall Dependent Operators"
echo "==========================================="

echo ""
echo "Step 15: Uninstalling Connectivity Link (Kuadrant) operator..."
oc delete subscription kuadrant-operator -n kuadrant-system --ignore-not-found=true || true
oc delete subscription rhcl-operator -n kuadrant-system --ignore-not-found=true || true
oc get csv -n kuadrant-system | grep -i kuadrant | awk '{print $1}' | xargs -r oc delete csv -n kuadrant-system || true

echo ""
echo "Step 16: Uninstalling Cert Manager operator..."
oc delete subscription openshift-cert-manager-operator -n cert-manager-operator --ignore-not-found=true || true
oc get csv -n cert-manager-operator | grep -i cert-manager | awk '{print $1}' | xargs -r oc delete csv -n cert-manager-operator || true

echo ""
echo "Step 17: Uninstalling Leader Worker Set operator..."
oc delete subscription leader-worker-set -n openshift-lws-operator --ignore-not-found=true || true
oc get csv -n openshift-lws-operator | grep -i leader-worker-set | awk '{print $1}' | xargs -r oc delete csv -n openshift-lws-operator || true


echo ""
echo "==========================================="
echo " Phase 5: Clean Up Remaining Resources"
echo "==========================================="

echo ""
echo "Step 18: Deleting operator namespaces..."
for ns in \
  opendatahub \
  redhat-ods-applications \
  redhat-ods-monitoring \
  redhat-ods-operator \
  rhoai-model-registries \
  odh-model-registries \
  modelmesh-serving \
  knative-serving \
  knative-eventing \
  kuadrant-system \
  cert-manager-operator \
  cert-manager \
  openshift-lws-operator
do
  echo "Deleting namespace: $ns"
  oc delete ns $ns --ignore-not-found=true || true
done

echo ""
echo "Waiting 30 seconds for namespace cleanup..."
sleep 30

echo ""
echo "Step 19: Removing stuck namespace finalizers if needed..."

for ns in $(oc get ns | egrep 'odh|rhoai|modelmesh|kserve|knative|opendatahub|kuadrant|cert-manager|lws' | awk '{print $1}')
do
  phase=$(oc get ns $ns -o jsonpath='{.status.phase}' 2>/dev/null || true)

  if [[ "$phase" == "Terminating" ]]; then
    echo "Removing finalizers from namespace: $ns"
    oc patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge || true
  fi
done

echo ""
echo "Step 20: Removing webhook configurations..."

oc get validatingwebhookconfigurations | \
egrep 'odh|rhoai|kserve|modelmesh|serving|ray|trustyai|kuadrant|cert-manager' | \
awk '{print $1}' | \
xargs -r oc delete validatingwebhookconfiguration || true

oc get mutatingwebhookconfigurations | \
egrep 'odh|rhoai|kserve|modelmesh|serving|ray|trustyai|kuadrant|cert-manager' | \
awk '{print $1}' | \
xargs -r oc delete mutatingwebhookconfiguration || true

echo ""
echo "Step 21: Removing CRDs..."

oc get crd | \
egrep 'opendatahub|datascience|kserve|modelmesh|serving.kserve|ray.io|trustyai|kuadrant|cert-manager|leaderworkerset' | \
awk '{print $1}' | \
xargs -r oc delete crd || true

echo ""
echo "==========================================="
echo " Cleanup Verification"
echo "==========================================="

echo ""
echo "Remaining namespaces:"
oc get ns | egrep 'odh|rhoai|modelmesh|kserve|knative|kuadrant|cert-manager|lws' || true

echo ""
echo "Remaining CRDs:"
oc get crd | egrep 'opendatahub|datascience|kserve|modelmesh|serving.kserve|ray.io|trustyai|kuadrant|cert-manager|leaderworkerset' || true

echo ""
echo "Remaining subscriptions:"
oc get subscriptions -A | egrep 'rhods|kuadrant|cert-manager|leader-worker' || true

echo ""
echo "Remaining pods:"
oc get pods -A | egrep 'odh|rhoai|opendatahub|modelmesh|kserve|serving|kuadrant|cert-manager|lws' || true

echo ""
echo "==========================================="
echo " Cleanup Completed"
echo "==========================================="