#!/bin/bash

# Collect recovery data for one or more Filesystem CRs from ibm-spectrum-scale namespace.
# Takes one or more filesystem names via --fs fs1[,fs2,...].
# For each filesystem, dumps the CR content (excluding k8s runtime metadata, including labels)
# plus all associated resources keyed by ramendr.openshift.io/groupreplicationid:
# StorageClass, VolumeGroupReplicationClass (cluster-scoped), LocalDisk, FilesystemRecoveryData (namespaced, ibm-spectrum-scale)
# Each filesystem produces a separate <fsname>.json file inside a single tar.gz archive.
#
# Preflight label checks (script aborts the filesystem if any fail):
#   Filesystem                  : ramendr.openshift.io/groupreplicationid
#                                 ramendr.openshift.io/storageid
#                                 scale.spectrum.ibm.com/dr-primary
#   StorageClass                : ramendr.openshift.io/groupreplicationid
#                                 ramendr.openshift.io/storageid
#                                 (no dr-primary — not set by the Scale operator on SC)
#   VolumeGroupReplicationClass : ramendr.openshift.io/groupreplicationid
#                                 ramendr.openshift.io/storageid
#                                 (no dr-primary — not set by the Scale operator on VGRC)
#   LocalDisk                   : ramendr.openshift.io/groupreplicationid
#                                 ramendr.openshift.io/storageid
#                                 scale.spectrum.ibm.com/dr-primary
#   FilesystemRecoveryData      : ramendr.openshift.io/groupreplicationid
#                                 ramendr.openshift.io/storageid
#                                 scale.spectrum.ibm.com/dr-primary

set -euo pipefail

# Configuration
NAMESPACE="ibm-spectrum-scale"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LABEL_KEY="ramendr.openshift.io/groupreplicationid"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 --fs <filesystem-name>[,<filesystem-name>,...]

Collect recovery data for one or more Filesystem CRs.

Arguments:
  --fs    Comma-separated list of Filesystem CR names to collect

Examples:
  $0 --fs fs1
  $0 --fs fs1,fs2

Each filesystem produces a separate <fsname>.json file inside a single tar.gz archive.
EOF
    exit 1
}

# Function to clean up K8s runtime metadata from JSON
clean_metadata() {
    local json="$1"
    echo "$json" | jq 'del(.metadata.resourceVersion,
                           .metadata.uid,
                           .metadata.selfLink,
                           .metadata.generation,
                           .metadata.creationTimestamp,
                           .metadata.managedFields,
                           .metadata.ownerReferences,
                           .status)'
}

# Validate that all required RamenDR labels are present on a resource.
# Each resource kind has a different required label set based on what the
# Scale operator actually sets:
#   - groupreplicationid + storageid : all collected kinds
#   - dr-primary                     : filesystem, localdisk, filesystemrecoverydata only
#                                      (NOT set on storageclass or volumegroupreplicationclass)
#
# Usage: validate_labels <json> <kind> <resource-description>
#   kind: filesystem | storageclass | volumegroupreplicationclass |
#         localdisk  | filesystemrecoverydata
# Returns 0 if all required labels are present, number of missing labels otherwise.
# Note: scale.spectrum.ibm.com/dr-state is not checked here — it is not
# required on any of the collected resource kinds.
validate_labels() {
    local json="$1"
    local kind="$2"
    local desc="$3"
    local missing=0

    local -a required_labels=("ramendr.openshift.io/groupreplicationid"
                               "ramendr.openshift.io/storageid")
    case "$kind" in
        filesystem|localdisk|filesystemrecoverydata)
            required_labels+=("scale.spectrum.ibm.com/dr-primary")
            ;;
        storageclass|volumegroupreplicationclass)
            # dr-primary is not set by the Scale operator on these kinds
            ;;
    esac

    for lbl in "${required_labels[@]}"; do
        val=$(echo "$json" | jq -r ".metadata.labels[\"$lbl\"] // empty")
        if [ -z "$val" ]; then
            log_warn "    $desc is missing required label '$lbl'"
            missing=$((missing + 1))
        fi
    done
    return $missing
}

# Parse arguments
FS_LIST=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fs)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                log_error "--fs requires a value"
                usage
            fi
            FS_LIST="$2"
            shift 2
            ;;
        --fs=*)
            FS_LIST="${1#--fs=}"
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            usage
            ;;
    esac
done

# Strip any accidental spaces from the value (e.g. --fs="lg1, lg2")
FS_LIST="${FS_LIST// /}"

if [ -z "$FS_LIST" ]; then
    log_error "--fs argument is required"
    usage
fi

# Split comma-separated FS names into an array
IFS=',' read -ra FS_NAMES <<< "$FS_LIST"

OUTPUT_DIR="fs-recovery-data-${TIMESTAMP}"
OUTPUT_TAR="fs-recovery-data-${TIMESTAMP}.tar.gz"

# Check prerequisites
log_info "Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq is required but not installed. Aborting."; exit 1; }

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "Namespace '$NAMESPACE' does not exist. Aborting."
    exit 1
fi

# Check that all required CRDs are registered in the cluster.
# Instance names are NOT listed here — at this stage the filesystem-specific
# groupreplicationid is not yet known, so any instance names would be
# unrelated to the requested filesystem and misleading.
log_info "Checking required CRDs..."
MISSING_CRDS=0
MISSING_CRD_NAMES=()
for CRD in storageclass volumegroupreplicationclass localdisk filesystemrecoverydata; do
    if ! kubectl explain "$CRD" >/dev/null 2>&1; then
        log_error "  Required resource type '$CRD' is not available in the cluster."
        MISSING_CRD_NAMES+=("$CRD")
        MISSING_CRDS=$((MISSING_CRDS + 1))
    else
        log_info "  Found: $CRD"
    fi
done
if [ "$MISSING_CRDS" -gt 0 ]; then
    log_error "$MISSING_CRDS required CRD(s) are missing: ${MISSING_CRD_NAMES[*]}. Aborting."
    exit 1
fi

# Create output directory
log_info "Creating output directory: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

FS_TOTAL=${#FS_NAMES[@]}
FS_INDEX=0
SKIPPED=0

for FS_NAME in "${FS_NAMES[@]}"; do
    FS_INDEX=$((FS_INDEX + 1))
    log_info "Processing Filesystem [$FS_INDEX/$FS_TOTAL]: $FS_NAME"

    # Fetch the named Filesystem CR
    fs_json=$(kubectl get filesystem "$FS_NAME" -n "$NAMESPACE" -o json 2>/dev/null) || {
        log_warn "  Filesystem CR '$FS_NAME' not found in namespace '$NAMESPACE', skipping."
        SKIPPED=$((SKIPPED + 1))
        continue
    }

    # Validate spec.local.replication: external
    REPLICATION=$(echo "$fs_json" | jq -r '.spec.local.replication // empty')
    if [ "$REPLICATION" != "external" ]; then
        log_warn "  Filesystem '$FS_NAME' does not have spec.local.replication: external (got: '${REPLICATION}'), skipping."
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Extract groupreplicationid
    GROUP_REP_ID=$(echo "$fs_json" | jq -r ".metadata.labels[\"$LABEL_KEY\"] // empty")
    if [ -z "$GROUP_REP_ID" ]; then
        log_warn "  Filesystem '$FS_NAME' does not have label '$LABEL_KEY', skipping."
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    log_info "  Group Replication ID: $GROUP_REP_ID"

    # Check that all required associated resources exist for this specific filesystem
    # (scoped by groupreplicationid) and that every instance carries all required
    # RamenDR labels before creating any output file.
    log_info "  Checking associated resources for groupreplicationid=$GROUP_REP_ID..."
    PREFLIGHT_MISSING=0
    PREFLIGHT_LABEL_FAILURES=0
    for RESOURCE_CHECK in "storageclass:cluster" "volumegroupreplicationclass:cluster" "localdisk:namespaced" "filesystemrecoverydata:namespaced"; do
        RES_TYPE="${RESOURCE_CHECK%%:*}"
        RES_SCOPE="${RESOURCE_CHECK##*:}"
        if [ "$RES_SCOPE" = "namespaced" ]; then
            RES_JSON=$(kubectl get "$RES_TYPE" -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
        else
            RES_JSON=$(kubectl get "$RES_TYPE" -o json 2>/dev/null || echo '{"items":[]}')
        fi
        RES_ITEMS=$(echo "$RES_JSON" | \
            jq -c ".items[] | select(.metadata.labels[\"$LABEL_KEY\"] == \"$GROUP_REP_ID\")")
        RES_COUNT=$(echo "$RES_ITEMS" | grep -c . || true)
        if [ "${RES_COUNT:-0}" -eq 0 ]; then
            log_error "  No $RES_TYPE found with label $LABEL_KEY=$GROUP_REP_ID for Filesystem '$FS_NAME'."
            PREFLIGHT_MISSING=$((PREFLIGHT_MISSING + 1))
        else
            log_info "    Found $RES_COUNT $RES_TYPE instance(s) for this filesystem."
            # Validate required RamenDR labels on every instance of this resource type
            while IFS= read -r item; do
                [ -z "$item" ] && continue
                ITEM_NAME=$(echo "$item" | jq -r '.metadata.name')
                if ! validate_labels "$item" "$RES_TYPE" "$RES_TYPE/$ITEM_NAME"; then
                    log_error "    $RES_TYPE/$ITEM_NAME is missing required labels. Fix labels before running this script."
                    PREFLIGHT_LABEL_FAILURES=$((PREFLIGHT_LABEL_FAILURES + 1))
                fi
            done <<< "$RES_ITEMS"
        fi
    done
    if [ "$PREFLIGHT_MISSING" -gt 0 ]; then
        log_error "  $PREFLIGHT_MISSING required resource type(s) missing for Filesystem '$FS_NAME'. Skipping."
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Validate all required RamenDR labels are present on the Filesystem CR
    if ! validate_labels "$fs_json" "filesystem" "Filesystem/$FS_NAME"; then
        PREFLIGHT_LABEL_FAILURES=$((PREFLIGHT_LABEL_FAILURES + 1))
    fi

    if [ "$PREFLIGHT_LABEL_FAILURES" -gt 0 ]; then
        log_error "  $PREFLIGHT_LABEL_FAILURES resource(s) have missing required RamenDR labels for Filesystem '$FS_NAME'. Skipping."
        log_error "  Fix the missing labels listed above before running this script."
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Each filesystem gets its own JSON file named after the FS
    OUTPUT_FILE="$OUTPUT_DIR/${FS_NAME}.json"

    # Initialize JSON array for all resources of this filesystem
    echo "[" > "$OUTPUT_FILE"

    # Write Filesystem CR
    log_info "  Writing Filesystem CR..."
    CLEANED_FS=$(clean_metadata "$fs_json")
    echo "$CLEANED_FS" | jq '.' >> "$OUTPUT_FILE"

    # Track how many associated resources are found for this filesystem,
    # and which resource types had zero matches (for diagnostic reporting).
    ASSOC_RESOURCES=0
    MISSING_RESOURCE_TYPES=()
    COLLECTED_SC=()
    COLLECTED_VGRC=()
    COLLECTED_LD=()
    COLLECTED_FRD=()

    # Collect StorageClass resources with matching groupreplicationid (cluster-scoped)
    log_info "  Collecting StorageClass resources..."
    SC_JSON=$(kubectl get storageclass -o json | \
        jq -c ".items[] | select(.metadata.labels[\"$LABEL_KEY\"] == \"$GROUP_REP_ID\")")

    if [ -n "$SC_JSON" ]; then
        while IFS= read -r sc; do
            [ -z "$sc" ] && continue
            SC_NAME=$(echo "$sc" | jq -r '.metadata.name')
            log_info "    Found StorageClass: $SC_NAME"
            echo "," >> "$OUTPUT_FILE"
            CLEANED_SC=$(clean_metadata "$sc")
            echo "$CLEANED_SC" | jq '.' >> "$OUTPUT_FILE"
            ASSOC_RESOURCES=$((ASSOC_RESOURCES + 1))
            COLLECTED_SC+=("$SC_NAME")
        done <<< "$SC_JSON"
    else
        log_warn "  No StorageClass found with label $LABEL_KEY=$GROUP_REP_ID"
        MISSING_RESOURCE_TYPES+=("StorageClass")
    fi

    # Collect VolumeGroupReplicationClass resources with matching groupreplicationid (cluster-scoped)
    log_info "  Collecting VolumeGroupReplicationClass resources..."
    VGRC_JSON=$(kubectl get volumegroupreplicationclass -o json 2>/dev/null | \
        jq -c ".items[] | select(.metadata.labels[\"$LABEL_KEY\"] == \"$GROUP_REP_ID\")" || echo "")

    if [ -n "$VGRC_JSON" ]; then
        while IFS= read -r vgrc; do
            [ -z "$vgrc" ] && continue
            VGRC_NAME=$(echo "$vgrc" | jq -r '.metadata.name')
            log_info "    Found VolumeGroupReplicationClass: $VGRC_NAME"
            echo "," >> "$OUTPUT_FILE"
            CLEANED_VGRC=$(clean_metadata "$vgrc")
            echo "$CLEANED_VGRC" | jq '.' >> "$OUTPUT_FILE"
            ASSOC_RESOURCES=$((ASSOC_RESOURCES + 1))
            COLLECTED_VGRC+=("$VGRC_NAME")
        done <<< "$VGRC_JSON"
    else
        log_warn "  No VolumeGroupReplicationClass found with label $LABEL_KEY=$GROUP_REP_ID"
        MISSING_RESOURCE_TYPES+=("VolumeGroupReplicationClass")
    fi

    # Collect LocalDisk resources with matching groupreplicationid (namespaced)
    log_info "  Collecting LocalDisk resources..."
    LD_JSON=$(kubectl get localdisk -n "$NAMESPACE" -o json 2>/dev/null | \
        jq -c ".items[] | select(.metadata.labels[\"$LABEL_KEY\"] == \"$GROUP_REP_ID\")" || echo "")

    if [ -n "$LD_JSON" ]; then
        while IFS= read -r ld; do
            [ -z "$ld" ] && continue
            LD_NAME=$(echo "$ld" | jq -r '.metadata.name')
            log_info "    Found LocalDisk: $LD_NAME"
            echo "," >> "$OUTPUT_FILE"
            CLEANED_LD=$(clean_metadata "$ld")
            echo "$CLEANED_LD" | jq '.' >> "$OUTPUT_FILE"
            ASSOC_RESOURCES=$((ASSOC_RESOURCES + 1))
            COLLECTED_LD+=("$LD_NAME")
        done <<< "$LD_JSON"
    else
        log_warn "  No LocalDisk found with label $LABEL_KEY=$GROUP_REP_ID"
        MISSING_RESOURCE_TYPES+=("LocalDisk")
    fi

    # Collect FilesystemRecoveryData resources with matching groupreplicationid (namespaced)
    log_info "  Collecting FilesystemRecoveryData resources..."
    FRD_JSON=$(kubectl get filesystemrecoverydata -n "$NAMESPACE" -o json 2>/dev/null | \
        jq -c ".items[] | select(.metadata.labels[\"$LABEL_KEY\"] == \"$GROUP_REP_ID\")" || echo "")

    if [ -n "$FRD_JSON" ]; then
        while IFS= read -r frd; do
            [ -z "$frd" ] && continue
            FRD_NAME=$(echo "$frd" | jq -r '.metadata.name')
            log_info "    Found FilesystemRecoveryData: $FRD_NAME"
            echo "," >> "$OUTPUT_FILE"
            CLEANED_FRD=$(clean_metadata "$frd")
            echo "$CLEANED_FRD" | jq '.' >> "$OUTPUT_FILE"
            ASSOC_RESOURCES=$((ASSOC_RESOURCES + 1))
            COLLECTED_FRD+=("$FRD_NAME")
        done <<< "$FRD_JSON"
    else
        log_warn "  No FilesystemRecoveryData found with label $LABEL_KEY=$GROUP_REP_ID"
        MISSING_RESOURCE_TYPES+=("FilesystemRecoveryData")
    fi

    # Abort this filesystem if no associated resources were found at all
    if [ "$ASSOC_RESOURCES" -eq 0 ]; then
        log_error "  No associated resources found for Filesystem '$FS_NAME' (groupreplicationid=$GROUP_REP_ID). Skipping — archive would be incomplete."
        log_error "  Missing resource types: ${MISSING_RESOURCE_TYPES[*]}"
        rm -f "$OUTPUT_FILE"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Warn if some (but not all) resource types are absent — archive may be incomplete
    if [ "${#MISSING_RESOURCE_TYPES[@]}" -gt 0 ]; then
        log_warn "  WARNING: Filesystem '$FS_NAME' archive may be incomplete."
        log_warn "  Missing resource type(s): ${MISSING_RESOURCE_TYPES[*]}"
    fi

    log_info "  Resources collected for Filesystem '$FS_NAME' ($ASSOC_RESOURCES total):"
    [ "${#COLLECTED_SC[@]}"   -gt 0 ] && log_info "    StorageClass:              ${COLLECTED_SC[*]}"
    [ "${#COLLECTED_VGRC[@]}" -gt 0 ] && log_info "    VolumeGroupReplicationClass: ${COLLECTED_VGRC[*]}"
    [ "${#COLLECTED_LD[@]}"   -gt 0 ] && log_info "    LocalDisk:                 ${COLLECTED_LD[*]}"
    [ "${#COLLECTED_FRD[@]}"  -gt 0 ] && log_info "    FilesystemRecoveryData:    ${COLLECTED_FRD[*]}"

    # Close JSON array and validate
    echo "]" >> "$OUTPUT_FILE"
    jq '.' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

    log_info "  Completed: $FS_NAME -> $OUTPUT_FILE"
done

PROCESSED=$((FS_TOTAL - SKIPPED))

if [ "$PROCESSED" -eq 0 ]; then
    log_error "No filesystems were processed successfully. Aborting."
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

# Pack all per-FS JSON files into a single archive
log_info "Creating archive: $OUTPUT_TAR"
tar -czf "$OUTPUT_TAR" -C "$(dirname "$OUTPUT_DIR")" "$(basename "$OUTPUT_DIR")"

# Clean up temporary directory
log_info "Cleaning up temporary directory..."
rm -rf "$OUTPUT_DIR"

log_info "Successfully created recovery data archive: $OUTPUT_TAR"
log_info "Archive location: $(pwd)/$OUTPUT_TAR"
log_info "Filesystems processed: $PROCESSED / $FS_TOTAL (skipped: $SKIPPED)"

exit 0
