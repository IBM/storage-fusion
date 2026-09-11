#!/bin/bash

# This script applies the recovery data collected by collectFsRecoveryData.sh
# to a recovery cluster. It extracts the tar.gz archive and applies the
# resources (StorageClass, VolumeGroupReplicationClass, Filesystem,
# LocalDisk, FilesystemRecoveryData) for the specified filesystems.
#
# The ramendr.openshift.io/storageid label is rewritten during apply:
# the primary cluster ID prefix is replaced with XXX so that the ramen
# relocation controller can later substitute the secondary cluster's ID.
#
# The CNSA operator on the recovery site will recognize the dr-primary labels
# and ignore those CRs, allowing RamenDR to manage the replication.

set -euo pipefail

# Configuration
NAMESPACE="ibm-spectrum-scale"
TEMP_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# Function to cleanup on exit
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log_info "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

usage() {
    cat << EOF
Usage: $0 --tar <tar-file> --fs <filesystem-name>[,<filesystem-name>,...]

Apply filesystem recovery data to a recovery cluster.

Arguments:
  --tar   Path to the tar.gz file created by collectFsRecoveryData.sh (required)
  --fs    Comma-separated list of Filesystem names to apply (required)

Examples:
  $0 --tar fs-recovery-data-20260325-081049.tar.gz --fs fs1
  $0 --tar fs-recovery-data-20260325-081049.tar.gz --fs fs1,fs2

This script will:
1. Extract the tar.gz archive
2. Apply resources for each selected filesystem to the recovery cluster
3. Verify resources are created successfully

The recovery cluster's CNSA operator will recognize dr-primary labels
and ignore the CRs, allowing RamenDR to manage replication.
EOF
    exit 1
}

# Parse arguments
TAR_FILE=""
FS_FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tar)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                log_error "--tar requires a value"
                usage
            fi
            TAR_FILE="$2"
            shift 2
            ;;
        --tar=*)
            TAR_FILE="${1#--tar=}"
            shift
            ;;
        --fs)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                log_error "--fs requires a value"
                usage
            fi
            FS_FILTER="$2"
            shift 2
            ;;
        --fs=*)
            FS_FILTER="${1#--fs=}"
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            usage
            ;;
    esac
done

# Strip any accidental spaces from values (e.g. --fs "lg1, lg2")
TAR_FILE="${TAR_FILE// /}"
FS_FILTER="${FS_FILTER// /}"

if [ -z "$TAR_FILE" ]; then
    log_error "--tar argument is required"
    usage
fi

if [ -z "$FS_FILTER" ]; then
    log_error "--fs argument is required"
    usage
fi

# Check prerequisites
log_info "Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq is required but not installed. Aborting."; exit 1; }
command -v tar >/dev/null 2>&1 || { log_error "tar is required but not installed. Aborting."; exit 1; }

# Validate tar file exists
if [ ! -f "$TAR_FILE" ]; then
    log_error "Tar file not found: $TAR_FILE"
    exit 1
fi

# Check if namespace exists on recovery cluster
log_info "Checking if namespace '$NAMESPACE' exists on recovery cluster..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "Namespace '$NAMESPACE' does not exist on recovery cluster."
    log_error "Please create the namespace first: kubectl create namespace $NAMESPACE"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
log_info "Created temporary directory: $TEMP_DIR"

# Extract tar file
log_step "Extracting tar file: $TAR_FILE"
tar -xzf "$TAR_FILE" -C "$TEMP_DIR"

# Build the list of JSON files to process for the specified filesystems
IFS=',' read -ra FS_NAMES <<< "$FS_FILTER"
log_info "Applying filesystems: ${FS_FILTER}"
JSON_FILES=""
for FS_NAME in "${FS_NAMES[@]}"; do
    MATCH=$(find "$TEMP_DIR" -name "${FS_NAME}.json" -type f)
    if [ -z "$MATCH" ]; then
        log_warn "No JSON file found for filesystem '$FS_NAME' in archive, skipping."
    else
        JSON_FILES="${JSON_FILES}${MATCH}"$'\n'
    fi
done
JSON_FILES=$(echo "$JSON_FILES" | sed '/^$/d')

if [ -z "$JSON_FILES" ]; then
    log_error "No JSON files to process. Aborting."
    exit 1
fi

FILE_COUNT=$(echo "$JSON_FILES" | wc -l | tr -d ' ')
log_info "Found $FILE_COUNT JSON file(s) to process"

# Process each JSON file (one per filesystem)
FILE_INDEX=0
TOTAL_RESOURCES=0
APPLIED_RESOURCES=0
FAILED_RESOURCES=0

while IFS= read -r json_file; do
    FILE_INDEX=$((FILE_INDEX + 1))

    # The JSON filename is the filesystem name
    FS_NAME=$(basename "$json_file" .json)
    log_step "Processing filesystem [$FILE_INDEX/$FILE_COUNT]: $FS_NAME"

    # Count resources in this file
    RESOURCE_COUNT=$(jq '. | length' "$json_file")
    log_info "  File contains $RESOURCE_COUNT resource(s)"
    TOTAL_RESOURCES=$((TOTAL_RESOURCES + RESOURCE_COUNT))

    # Apply each resource in the JSON array
    RESOURCE_INDEX=0
    while [ $RESOURCE_INDEX -lt $RESOURCE_COUNT ]; do
        RESOURCE=$(jq ".[$RESOURCE_INDEX]" "$json_file")
        KIND=$(printf '%s\n' "$RESOURCE" | jq -r '.kind')
        NAME=$(printf '%s\n' "$RESOURCE" | jq -r '.metadata.name')

        log_info "  Applying $KIND/$NAME  [filesystem: $FS_NAME]"

        # Rewrite the storageid label: replace the primary cluster ID prefix with XXX.
        # The ramen relocation controller will substitute the secondary cluster's ID later.
        STORAGE_ID=$(printf '%s\n' "$RESOURCE" | jq -r '.metadata.labels["ramendr.openshift.io/storageid"] // ""')
        if [ -n "$STORAGE_ID" ] && [ "$STORAGE_ID" != "null" ]; then
            FILESYSTEM_ID="${STORAGE_ID#*-}"
            NEW_STORAGE_ID="XXX-${FILESYSTEM_ID}"
            log_info "    Rewriting storageid: $STORAGE_ID -> $NEW_STORAGE_ID"
            RESOURCE=$(printf '%s\n' "$RESOURCE" | jq --arg new_id "$NEW_STORAGE_ID" \
                '.metadata.labels["ramendr.openshift.io/storageid"] = $new_id')
        fi

        if printf '%s\n' "$RESOURCE" | kubectl apply --server-side --force-conflicts -f - 2>&1; then
            log_info "    Successfully applied $KIND/$NAME"
            APPLIED_RESOURCES=$((APPLIED_RESOURCES + 1))
        else
            log_error "    Failed to apply $KIND/$NAME"
            FAILED_RESOURCES=$((FAILED_RESOURCES + 1))
        fi

        RESOURCE_INDEX=$((RESOURCE_INDEX + 1))
    done

    log_info "  Completed filesystem: $FS_NAME"
done <<< "$JSON_FILES"

# Summary
echo ""
log_step "=== Summary ==="
log_info "Total resources processed: $TOTAL_RESOURCES"
log_info "Successfully applied: $APPLIED_RESOURCES"
if [ $FAILED_RESOURCES -gt 0 ]; then
    log_warn "Failed to apply: $FAILED_RESOURCES"
else
    log_info "Failed to apply: $FAILED_RESOURCES"
fi

# Verification
echo ""
log_step "=== Verification ==="
log_info "Verifying resources on recovery cluster..."

SC_COUNT=$(kubectl get storageclass -l ramendr.openshift.io/groupreplicationid 2>/dev/null | grep -v NAME | wc -l | tr -d ' ' || echo "0")
log_info "StorageClasses with DR labels: $SC_COUNT"

VGRC_COUNT=$(kubectl get volumegroupreplicationclass -l ramendr.openshift.io/groupreplicationid 2>/dev/null | grep -v NAME | wc -l | tr -d ' ' || echo "0")
log_info "VolumeGroupReplicationClasses with DR labels: $VGRC_COUNT"

FS_COUNT=$(kubectl get filesystems -n "$NAMESPACE" -l ramendr.openshift.io/groupreplicationid 2>/dev/null | grep -v NAME | wc -l | tr -d ' ' || echo "0")
log_info "Filesystems with DR labels: $FS_COUNT"

LD_COUNT=$(kubectl get localdisk -n "$NAMESPACE" -l ramendr.openshift.io/groupreplicationid 2>/dev/null | grep -v NAME | wc -l | tr -d ' ' || echo "0")
log_info "LocalDisks with DR labels: $LD_COUNT"

FRD_COUNT=$(kubectl get filesystemrecoverydata -n "$NAMESPACE" -l ramendr.openshift.io/groupreplicationid 2>/dev/null | grep -v NAME | wc -l | tr -d ' ' || echo "0")
log_info "FilesystemRecoveryData with DR labels: $FRD_COUNT"

echo ""
if [ $FAILED_RESOURCES -eq 0 ]; then
    log_info "All resources applied successfully to recovery cluster!"
    log_info "The CNSA operator will recognize dr-primary labels and ignore these CRs."
    log_info "Proceed with discovery in RamenDR"
else
    log_warn "Some resources failed to apply. Please review the errors above."
    exit 1
fi

exit 0
