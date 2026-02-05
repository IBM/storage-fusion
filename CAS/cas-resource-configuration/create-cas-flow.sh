#!/usr/bin/env bash
###############################################################################
# CAS Bootstrap Script
# - Logs into OpenShift
# - Creates DataSource (Scale or AWS)
# - Creates Domain
# - Creates DocumentProcessor (NVIDIA or Docling)
###############################################################################

set -Eeuo pipefail

#######################################
# Global variables
#######################################
SCRIPT_NAME=$(basename "$0")
CONFIG_FILE=${1:-cas-config.env}
LOG_FILE="/tmp/${SCRIPT_NAME}.log"
NAMESPACE_DEFAULT="ibm-cas"

#######################################
# Logging helpers
#######################################
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
  log "ERROR: $*"
  exit 1
}

trap 'error "Script failed at line $LINENO"' ERR

#######################################
# Load configuration
#######################################
[[ -f "$CONFIG_FILE" ]] || error "Config file not found: $CONFIG_FILE"
log "Loading configuration from $CONFIG_FILE"
source "$CONFIG_FILE"

#######################################
# Required validation
#######################################
require() {
  [[ -z "${!1:-}" ]] && error "Missing required variable: $1"
}

for v in OC_SERVER OC_TOKEN DATASOURCE_NAME DOMAIN_NAME DOC_PROCESSOR_NAME; do
  require "$v"
done

NAMESPACE="${NAMESPACE:-$NAMESPACE_DEFAULT}"
DATASOURCE_TYPE="${DATASOURCE_TYPE:-scale}"
DOC_PROCESSOR_TYPE="${DOC_PROCESSOR_TYPE:-nvidia}"

#######################################
# Datasource validation
#######################################
if [[ "$DATASOURCE_TYPE" == "scale" ]]; then
  require SCALE_FILESYSTEM_NAME
  require SCALE_PATH
elif [[ "$DATASOURCE_TYPE" == "aws" ]]; then
  require AWS_BUCKET
  require AWS_ENDPOINT
  require AWS_SECRET_NAME
  require AWS_FILESYSTEM_NAME
else
  error "Unsupported DATASOURCE_TYPE: $DATASOURCE_TYPE"
fi

#######################################
# Document processor validation
#######################################
if [[ "$DOC_PROCESSOR_TYPE" != "nvidia" && "$DOC_PROCESSOR_TYPE" != "docling" ]]; then
  error "Unsupported DOC_PROCESSOR_TYPE: $DOC_PROCESSOR_TYPE"
fi

#######################################
# OpenShift login
#######################################
log "Logging into OpenShift cluster"
oc login "$OC_SERVER" \
  --token="$OC_TOKEN" \
  --insecure-skip-tls-verify=true >/dev/null

log "Switching to namespace: $NAMESPACE"
oc get ns "$NAMESPACE" >/dev/null 2>&1 || error "Namespace $NAMESPACE not found"
oc project "$NAMESPACE" >/dev/null

#######################################
# Create DataSource
#######################################
log "Creating DataSource: $DATASOURCE_NAME"

if [[ "$DATASOURCE_TYPE" == "scale" ]]; then
cat <<EOF | oc apply -f -
apiVersion: cas.isf.ibm.com/v1beta1
kind: DataSource
metadata:
  name: ${DATASOURCE_NAME}
  namespace: ${NAMESPACE}
spec:
  scale:
    fileSystemName: ${SCALE_FILESYSTEM_NAME}
    path: ${SCALE_PATH}
EOF
fi

if [[ "$DATASOURCE_TYPE" == "aws" ]]; then
cat <<EOF | oc apply -f -
apiVersion: cas.isf.ibm.com/v1beta1
kind: DataSource
metadata:
  name: ${DATASOURCE_NAME}
  namespace: ${NAMESPACE}
spec:
  s3:
    bucket: ${AWS_BUCKET}
    endpoint: ${AWS_ENDPOINT}
    provider: aws
    fileSystemName: ${AWS_FILESYSTEM_NAME}
    credentials:
      secretName: ${AWS_SECRET_NAME}
      accessKeyRef:
        key: accessKey
      secretKeyRef:
        key: secretKey
EOF
fi

#######################################
# Create Domain
#######################################
log "Creating Domain: $DOMAIN_NAME"

cat <<EOF | oc apply -f -
apiVersion: cas.isf.ibm.com/v1beta1
kind: Domain
metadata:
  name: ${DOMAIN_NAME}
  namespace: ${NAMESPACE}
spec:
  dataSources:
  - ${DATASOURCE_NAME}
  collections:
  - name: "${DOMAIN_NAME}"
EOF

#######################################
# Create Document Processor
#######################################
log "Creating DocumentProcessor: $DOC_PROCESSOR_NAME"

DP_TYPE="nvidia_multimodal"
[[ "$DOC_PROCESSOR_TYPE" == "docling" ]] && DP_TYPE="docling_multimodal"

cat <<EOF | oc apply -f -
apiVersion: cas.isf.ibm.com/v1beta1
kind: DocumentProcessor
metadata:
  name: ${DOC_PROCESSOR_NAME}
  namespace: ${NAMESPACE}
spec:
  type: ${DP_TYPE}
  domains:
  - ${DOMAIN_NAME}
EOF

#######################################
# Post validation
#######################################
log "Validating CAS resources"

oc get datasource "${DATASOURCE_NAME}" -n "${NAMESPACE}"
oc get domain "${DOMAIN_NAME}" -n "${NAMESPACE}"
oc get documentprocessor "${DOC_PROCESSOR_NAME}" -n "${NAMESPACE}"

log "SUCCESS: CAS bootstrap completed"
log "Documents should begin ingestion automatically"
