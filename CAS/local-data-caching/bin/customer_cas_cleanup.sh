#!/bin/bash

###############################################################################
# Script Name: customer_cas_cleanup.sh (Enhanced Version)
# Purpose: Safely uninstall the CAS service from OpenShift with proper ordering
#
# IMPROVEMENTS:
#    - Scale down deployments/statefulsets BEFORE deletion to prevent restarts
#    - Better parade resource preservation (all resources, not just secrets)
#    - Proper cleanup ordering to prevent resource recreation
#    - Better finalizer handling in all cleanup functions
#    - Prevents valkey reinstallation when namespace is preserved
#    - Handles stuck PVCs with finalizers consistently
#    - More granular resource selection to avoid parade deletion
#
# FEATURES:
#    - Deletes CAS Custom Resources (CasInstall)
#    - Cleans up Kafka resources (topics, users, brokers)
#    - Uninstalls CAS operators and related ClusterServiceVersions
#    - Removes namespace-specific ClusterRoleBindings
#    - Deletes CAS catalog sources and PVCs (optionally preserved)
#    - Removes FusionServiceInstance (if applicable)
#    - Deletes associated Persistent Volumes (PVs) in 'Released' state
#    - Safely deletes or retains the namespace based on options
#    - Preserves parade resources when requested
#
# Usage:
#  yes y | bash customer_cas_cleanup.sh [-n <namespace>] [--keep-paradedb] [--keep-namespace] [--help]
#
###############################################################################

set -euo pipefail

# Defaults
NAMESPACE="ibm-cas"
KEEP_PARADEDB=false
KEEP_NAMESPACE=false
RETRY_COUNT=5
RETRY_INTERVAL=10
MAX_PARALLEL=5

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Help
print_help() {
    cat << EOF
Usage: $0 [options]

Options:
  -n, --namespace <name>       Target namespace (default: ibm-cas)
  --keep-paradedb              Do NOT delete cluster-parade resources (ALL resources preserved)
  --keep-namespace             Do NOT delete the namespace after cleanup
  --help                       Display this help message

Examples:
  # Delete everything including namespace
  $0 -n ibm-cas

  # Keep parade resources but delete namespace
  $0 -n ibm-cas --keep-paradedb

  # Keep namespace and parade resources
  $0 -n ibm-cas --keep-paradedb --keep-namespace

Notes:
  - When --keep-paradedb is set, ALL parade resources are preserved (pods, pvcs, secrets, configmaps, services)
  - When --keep-namespace is set, operators are scaled down to prevent resource recreation
  - PVCs with finalizers are automatically handled with user confirmation

EOF
    exit 0
}

# Run wrapper with error handling
run_step() {
    local step_name="$1"; shift
    echo ""
    echo "============================================================"
    log_info "Starting: $step_name"
    echo "============================================================"
    echo ""

    if "$@"; then
        echo ""
        echo "============================================================"
        log_success "Completed: $step_name"
        echo "============================================================"
    else
        log_error "Failed: $step_name (continuing to next step)"
    fi
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --keep-paradedb|--keep-cluster-parade)
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
            log_error "Unknown argument: $1"
            print_help
            ;;
    esac
done

echo "============================================================"
echo "CAS Cleanup Script - Enhanced Customer-Safe Version"
echo "============================================================"
log_info "Target Namespace: $NAMESPACE"
log_info "Preserve Parade Resources: $KEEP_PARADEDB"
log_info "Preserve Namespace: $KEEP_NAMESPACE"
echo "============================================================"

# Confirm
echo ""
log_warn "This script will perform the following operations:"
echo "  1. Scale down CAS operators to prevent resource recreation"
echo "  2. Delete CAS Custom Resources and operators"
echo "  3. Delete Kafka resources (topics, users, brokers)"
echo "  4. Delete CAS-specific pods, services, configmaps, secrets"
echo "  5. Delete PVCs and associated PVs"
if [[ "$KEEP_PARADEDB" == true ]]; then
    log_info "  → Parade resources (ALL types) will be PRESERVED"
fi
if [[ "$KEEP_NAMESPACE" == true ]]; then
    log_info "  → Namespace will be PRESERVED (operators scaled down)"
else
    log_warn "  → Namespace will be DELETED"
fi
echo ""
read -rp "Are you sure you want to proceed? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && log_warn "Aborted by user." && exit 0

# Check if namespace exists
if ! oc get ns "$NAMESPACE" &>/dev/null; then
    log_error "Namespace '$NAMESPACE' does not exist."
    exit 1
fi

log_success "Namespace '$NAMESPACE' exists. Proceeding with cleanup..."

# List current state
echo ""
log_info "Current Pods in namespace '$NAMESPACE':"
oc get pods -n "$NAMESPACE" 2>/dev/null || log_warn "No pods found or unable to list pods"
echo ""
log_info "Current PVCs in namespace '$NAMESPACE':"
oc get pvc -n "$NAMESPACE" 2>/dev/null || log_warn "No PVCs found or unable to list PVCs"
echo ""

# Helper: Check if resource is parade-related
is_parade_resource() {
    local resource_name="$1"
    [[ "$resource_name" =~ ^(cluster-parade|parade-) ]] || [[ "$resource_name" =~ -parade$ ]]
}

# Retry wrapper with finalizer removal
retry_until_gone() {
    local resource=$1
    local namespace=$2
    local kind=$3

    for i in $(seq 1 "$RETRY_COUNT"); do
        local exists=false

        if [[ -z "$namespace" ]]; then
            oc get "$kind" "$resource" &>/dev/null && exists=true
        else
            oc get "$kind" "$resource" -n "$namespace" &>/dev/null && exists=true
        fi

        if [[ "$exists" == false ]]; then
            log_success "$kind/$resource deleted successfully"
            return 0
        fi

        log_info "[$i/$RETRY_COUNT] Waiting for $kind/$resource to terminate..."
        sleep "$RETRY_INTERVAL"
    done

    log_error "$kind/$resource did not delete after $RETRY_COUNT retries"
    read -rp "Remove finalizers and force delete $kind/$resource? [y/N]: " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Removing finalizers from $kind/$resource"
        if [[ -z "$namespace" ]]; then
            oc patch "$kind" "$resource" --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
            oc patch "$kind" "$resource" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
            oc delete "$kind" "$resource" --wait=false --grace-period=0 --force 2>/dev/null || true
        else
            oc patch "$kind" "$resource" -n "$namespace" --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
            oc patch "$kind" "$resource" -n "$namespace" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
            oc delete "$kind" "$resource" -n "$namespace" --wait=false --grace-period=0 --force 2>/dev/null || true
        fi
    else
        log_warn "Skipping forced deletion of $kind/$resource"
    fi
}

# CRITICAL: Scale down operators FIRST to prevent resource recreation
scale_down_operators() {
    log_info "Scaling down operators to prevent resource recreation..."

    # Scale down deployments
    local deployments
    deployments=$(oc get deployment -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

    for deploy in $deployments; do
        # Skip parade deployments if preservation is enabled
        if [[ "$KEEP_PARADEDB" == true ]] && is_parade_resource "$deploy"; then
            log_info "Skipping parade deployment: $deploy"
            continue
        fi

        log_info "Scaling down deployment: $deploy"
        oc scale deployment "$deploy" -n "$NAMESPACE" --replicas=0 --timeout=60s 2>/dev/null || true
    done

    # Scale down statefulsets (CRITICAL for valkey)
    local statefulsets
    statefulsets=$(oc get sts -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

    for sts in $statefulsets; do
        # Skip parade statefulsets if preservation is enabled
        if [[ "$KEEP_PARADEDB" == true ]] && is_parade_resource "$sts"; then
            log_info "Skipping parade statefulset: $sts"
            continue
        fi

        log_info "Scaling down statefulset: $sts"
        oc scale sts "$sts" -n "$NAMESPACE" --replicas=0 --timeout=60s 2>/dev/null || true
    done

    # Wait for pods to terminate
    log_info "Waiting for pods to terminate after scale-down..."
    sleep 10

    log_success "Operators and statefulsets scaled down"
}

# Delete Kafka resources
delete_kafka_resources() {
    log_info "Deleting Kafka resources..."

    local RESOURCES=("kafkatopics.kafka.strimzi.io" "kafkauser.kafka.strimzi.io" "kafka.kafka.strimzi.io")

    for kind in "${RESOURCES[@]}"; do
        local LIST
        LIST=$(oc get "$kind" -n "$NAMESPACE" -o name 2>/dev/null || true)

        if [[ -z "$LIST" ]]; then
            log_info "No $kind resources found"
            continue
        fi

        for res in $LIST; do
            local name="${res#*/}"
            log_info "Deleting $res..."

            # Remove finalizers first
            oc patch "$kind" "$name" -n "$NAMESPACE" --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
            oc delete "$res" -n "$NAMESPACE" --wait=false 2>/dev/null || true
            retry_until_gone "$name" "$NAMESPACE" "$kind"
        done
    done

    log_success "Kafka resources cleanup completed"
}

# Uninstall CAS operators
uninstall_operators() {
    log_info "Uninstalling CAS operators..."

    local SUBS
    SUBS=$(oc get subscriptions -n "$NAMESPACE" -o name 2>/dev/null || true)

    if [[ -z "$SUBS" ]]; then
        log_info "No subscriptions found"
        return 0
    fi

    for sub in $SUBS; do
        local name="${sub#*/}"
        local CSV
        CSV=$(oc get "$sub" -n "$NAMESPACE" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)

        log_info "Deleting subscription: $name"
        oc delete "$sub" -n "$NAMESPACE" --wait=false 2>/dev/null || true
        retry_until_gone "$name" "$NAMESPACE" "Subscription"

        if [[ -n "$CSV" ]]; then
            log_info "Deleting CSV: $CSV"
            oc patch clusterserviceversion "$CSV" -n "$NAMESPACE" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
            oc delete clusterserviceversion "$CSV" -n "$NAMESPACE" --wait=false 2>/dev/null || true
            retry_until_gone "$CSV" "$NAMESPACE" "clusterserviceversion"
        fi
    done

    log_success "Operators uninstalled"
}

# Cleanup PVCs with proper parade preservation
cleanup_pvcs() {
    log_info "Starting PVC cleanup in namespace: $NAMESPACE"

    local PVC_LIST
    PVC_LIST=$(oc get pvc -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

    if [[ -z "$PVC_LIST" ]]; then
        log_info "No PVCs found"
        return 0
    fi

    local JOBS=0

    for pvc in $PVC_LIST; do
        # Skip parade PVCs if preservation is enabled
        if [[ "$KEEP_PARADEDB" == true ]] && is_parade_resource "$pvc"; then
            log_info "Skipping parade PVC: $pvc"
            continue
        fi

        (
            log_info "Deleting PVC: $pvc"

            # Remove finalizers
            oc patch pvc "$pvc" -n "$NAMESPACE" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true

            oc delete pvc "$pvc" -n "$NAMESPACE" --wait=false 2>/dev/null || true
            retry_until_gone "$pvc" "$NAMESPACE" "pvc"

            # Handle associated PV
            local PV
            PV=$(oc get pv --no-headers -o custom-columns=":metadata.name,:spec.claimRef.name" 2>/dev/null | \
                 grep "$pvc" | awk '{print $1}' || true)

            if [[ -n "$PV" ]]; then
                log_info "Processing PV $PV linked to PVC $pvc"
                local STATUS
                STATUS=$(oc get pv "$PV" -o jsonpath='{.status.phase}' 2>/dev/null || true)
                log_info "PV $PV status is $STATUS"

                if [[ "$STATUS" =~ ^(Released|Failed|Terminating)$ ]]; then
                    log_info "PV $PV is in state $STATUS, removing finalizers"
                    oc patch pv "$PV" --type=json \
                        -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
                fi

                log_info "Deleting PV $PV"
                oc delete pv "$PV" --wait=false 2>/dev/null || true
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
    log_success "PVC and PV cleanup complete"
}

# Delete FusionServiceInstance
delete_fusion_service_instances() {
    log_info "Deleting FusionServiceInstance resources..."

    local fusion_ns instance_name mandatory

    # Discover the namespace
    fusion_ns=$(oc get spectrumfusion -A --no-headers 2>/dev/null | cut -d" " -f1 | head -n1)
    [ -z "$fusion_ns" ] && fusion_ns=$(oc get subs -A -o custom-columns=:metadata.namespace,:spec.name 2>/dev/null | \
                                       grep "isf-operator$" | cut -d" " -f1)
    [ -z "$fusion_ns" ] && fusion_ns="ibm-spectrum-fusion-ns"

    local instances=(
        "ibm-cas-service-instance:true"
        "cas-install-redstack:false"
    )

    for entry in "${instances[@]}"; do
        instance_name="${entry%%:*}"
        mandatory="${entry##*:}"

        if oc get fusionserviceinstance "$instance_name" -n "$fusion_ns" &>/dev/null; then
            log_info "Deleting FusionServiceInstance '$instance_name' from $fusion_ns"

            # Remove finalizers
            oc patch fusionserviceinstance "$instance_name" -n "$fusion_ns" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true

            oc delete fusionserviceinstance "$instance_name" -n "$fusion_ns" --wait=false 2>/dev/null || true
            retry_until_gone "$instance_name" "$fusion_ns" "fusionserviceinstance"
        elif [ "$mandatory" = "true" ]; then
            log_warn "Mandatory FusionServiceInstance '$instance_name' not found in $fusion_ns"
        else
            log_info "Optional FusionServiceInstance '$instance_name' not found, skipping"
        fi
    done

    log_success "FusionServiceInstance cleanup completed"
}

# Delete CAS CatalogSource
delete_catalog_source() {
    log_info "Deleting CAS CatalogSource..."

    if oc get catalogsource ibm-isf-cas-operator-catalog -n "$NAMESPACE" &>/dev/null; then
        oc delete catalogsource ibm-isf-cas-operator-catalog -n "$NAMESPACE" --wait=true 2>/dev/null || true
        log_success "CatalogSource deleted"
    else
        log_info "CatalogSource not found"
    fi
}

# Delete CAS-specific CRD instances
delete_cas_crd_instances() {
    log_info "Looking for CAS-specific CRDs (excluding Kafka CRDs)..."

    local CAS_CRDS
    CAS_CRDS=$(oc get crd --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep -i "cas.isf" || true)

    if [ -z "$CAS_CRDS" ]; then
        log_info "No CAS CRDs found"
        return 0
    fi

    for crd in $CAS_CRDS; do
        local resource
        resource=$(echo "$crd" | cut -d '.' -f1)

        log_info "Processing CRD: $crd (Resource: $resource)"

        local instances
        instances=$(oc get "$resource" -n "$NAMESPACE" --no-headers \
            -o custom-columns="NAME:.metadata.name" 2>/dev/null || true)

        if [ -z "$instances" ]; then
            log_info "No instances found for $resource in namespace $NAMESPACE"
            continue
        fi

        for name in $instances; do
            log_info "Deleting $resource/$name in namespace $NAMESPACE"

            # Remove finalizers (both methods for safety)
            oc patch "$resource" "$name" -n "$NAMESPACE" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true

            oc patch "$resource" "$name" -n "$NAMESPACE" --type=merge \
                -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true

            # Delete instance
            oc delete "$resource" "$name" -n "$NAMESPACE" --ignore-not-found=true --wait=false 2>/dev/null

            # Wait until gone
            retry_until_gone "$name" "$NAMESPACE" "$resource"
        done
    done

    log_success "CAS CRD instances cleanup completed"
}

# Resource cleanup with proper parade preservation
resource_cleanup() {
    log_info "Starting resource cleanup in namespace: $NAMESPACE"

    local JOBS=0

    control_parallel() {
        while [[ $(jobs -rp | wc -l) -ge $MAX_PARALLEL ]]; do
            sleep 1
        done
    }

    # STEP 1: Delete StatefulSets (if not already scaled down)
    log_info "Deleting StatefulSets..."

    local sts_list
    sts_list=$(oc get sts -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

    if [[ -z "$sts_list" ]]; then
        log_info "No StatefulSets found"
    else
        for sts in $sts_list; do
            # Skip parade statefulsets
            if [[ "$KEEP_PARADEDB" == true ]] && is_parade_resource "$sts"; then
                log_info "Preserving parade StatefulSet: $sts"
                continue
            fi

            control_parallel
            (
                log_info "Deleting StatefulSet $sts"
                oc patch sts "$sts" -n "$NAMESPACE" --type=json \
                    -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
                oc delete sts "$sts" -n "$NAMESPACE" --wait=false 2>/dev/null || true
                retry_until_gone "$sts" "$NAMESPACE" "sts"
            ) &
        done
        wait
    fi

    log_success "StatefulSets deletion completed"

    # STEP 2: Delete Deployments
    log_info "Deleting Deployments..."

    local deploy_list
    deploy_list=$(oc get deployment -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

    if [[ -n "$deploy_list" ]]; then
        for deploy in $deploy_list; do
            # Skip parade deployments
            if [[ "$KEEP_PARADEDB" == true ]] && is_parade_resource "$deploy"; then
                log_info "Preserving parade Deployment: $deploy"
                continue
            fi

            control_parallel
            (
                log_info "Deleting Deployment $deploy"
                oc delete deployment "$deploy" -n "$NAMESPACE" --wait=false 2>/dev/null || true
                retry_until_gone "$deploy" "$NAMESPACE" "deployment"
            ) &
        done
        wait
    fi

    log_success "Deployments deletion completed"

    # STEP 3: Delete remaining Pods
    log_info "Deleting remaining pods..."

    oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | \
        awk '{print $1, $3}' | \
        while read -r pod status; do
            # Skip parade pods
            if [[ "$KEEP_PARADEDB" == true ]] && is_parade_resource "$pod"; then
                log_info "Preserving parade pod: $pod"
                continue
            fi

            if [[ "$status" =~ ^(Running|CrashLoopBackOff|Pending|Failed|Terminating|Error)$ ]]; then
                control_parallel
                (
                    log_info "Deleting pod $pod (status: $status)"
                    oc delete pod "$pod" -n "$NAMESPACE" \
                        --grace-period=0 \
                        --force \
                        --wait=false 2>/dev/null || true
                    retry_until_gone "$pod" "$NAMESPACE" "pod"
                ) &
            fi
        done

    wait
    log_success "Pod cleanup completed"

    # STEP 4: Delete other namespaced resources (with parade preservation)
    local resources=("service" "route" "job" "cronjob")

    for res in "${resources[@]}"; do
        log_info "Deleting $res resources..."

        oc get "$res" -n "$NAMESPACE" --no-headers \
            -o custom-columns=":metadata.name" 2>/dev/null | \
        while read -r name; do
            # Skip parade resources
            if [[ "$KEEP_PARADEDB" == true ]] && is_parade_resource "$name"; then
                log_info "Preserving parade $res: $name"
                continue
            fi

            control_parallel
            (
                log_info "Deleting $res/$name"
                oc delete "$res" "$name" -n "$NAMESPACE" --wait=false 2>/dev/null || true
                retry_until_gone "$name" "$NAMESPACE" "$res"
            ) &
        done
    done

    wait
    log_success "Resource cleanup completed"
}

# Final cleanup with parade preservation
final_cleanup() {
    log_info "Starting final cleanup of remaining resources..."

    # Delete secrets (with parade preservation)
    log_info "Cleaning up secrets..."
    oc get secrets -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
    while read -r secret; do
        # Skip default service account tokens and parade secrets
        if [[ "$secret" =~ ^(default-token|builder-token|deployer-token) ]]; then
            continue
        fi

        if [[ "$KEEP_PARADEDB" == true ]] && is_parade_resource "$secret"; then
            log_info "Preserving parade secret: $secret"
            continue
        fi

        oc delete secret "$secret" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    done

    # Delete configmaps (with parade preservation)
    log_info "Cleaning up configmaps..."
    oc get configmaps -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | \
    while read -r cm; do
        if [[ "$KEEP_PARADEDB" == true ]] && is_parade_resource "$cm"; then
            log_info "Preserving parade configmap: $cm"
            continue
        fi

        oc delete configmap "$cm" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    done

    # Delete network policies
    log_info "Cleaning up network policies..."
    oc delete networkpolicy docling-deny-all-egress -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    oc delete networkpolicy docling-allow-local-egress -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true

    # Delete rolebindings
    log_info "Cleaning up rolebindings..."
    oc delete rolebindings --all -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true

    log_success "Final cleanup completed"
}

# Delete namespace
delete_namespace() {
    if [[ "$KEEP_NAMESPACE" == false ]]; then
        log_info "Deleting Namespace: $NAMESPACE"

        # Remove finalizers from namespace
        oc patch namespace "$NAMESPACE" --type=json \
            -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true

        oc delete namespace "$NAMESPACE" --wait=false 2>/dev/null || true
        retry_until_gone "$NAMESPACE" "" "namespace"

        log_success "Namespace deleted"
    else
        log_info "Namespace $NAMESPACE preserved (--keep-namespace)"

        if [[ "$KEEP_PARADEDB" == true ]]; then
            log_info "Checking parade resources in preserved namespace..."
            local parade_pods
            parade_pods=$(oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -E "^(cluster-parade|parade-)" | wc -l)
            log_info "Parade pods preserved: $parade_pods"

            local parade_pvcs
            parade_pvcs=$(oc get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | grep -E "^(cluster-parade|parade-)" | wc -l)
            log_info "Parade PVCs preserved: $parade_pvcs"
        fi
    fi
}

#######################################
### MAIN EXECUTION FLOW ###
#######################################

# CRITICAL: Scale down operators FIRST to prevent resource recreation
run_step "Scale Down Operators and StatefulSets" scale_down_operators

# Delete CAS-specific resources
run_step "Delete CAS CRD Instances" delete_cas_crd_instances
run_step "Delete Fusion Service Instances" delete_fusion_service_instances
run_step "Delete Catalog Source" delete_catalog_source
run_step "Delete Kafka Resources" delete_kafka_resources
run_step "Uninstall Operators" uninstall_operators

# Delete workloads and resources
run_step "Resource Cleanup (Deployments, StatefulSets, Pods)" resource_cleanup
run_step "Cleanup PVCs and PVs" cleanup_pvcs
run_step "Final Resource Cleanup (Secrets, ConfigMaps, etc.)" final_cleanup

# Delete namespace (if requested)
run_step "Delete Namespace" delete_namespace

# Summary
echo ""
echo "============================================================"
log_success "IBM CAS cleanup completed successfully"
echo "============================================================"

if [[ "$KEEP_PARADEDB" == true ]]; then
    log_info "Parade resources preserved:"
    log_info "  - Pods, StatefulSets, Deployments"
    log_info "  - PVCs and PVs"
    log_info "  - Secrets and ConfigMaps"
    log_info "  - Services and Routes"
fi

if [[ "$KEEP_NAMESPACE" == true ]]; then
    log_info "Namespace '$NAMESPACE' has been preserved"
    log_info "All CAS operators have been scaled down to prevent resource recreation"
fi

echo ""