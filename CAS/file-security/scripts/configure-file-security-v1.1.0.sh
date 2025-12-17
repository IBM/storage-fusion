#!/bin/bash

###############################################################################
# Script Name: configure-file-security.sh
# Purpose: To enable or disable file level security and ACL cache in CAS.
#
# Usage:
#   ./configure-file-security.sh \
#       --namespace <namespace> \
#       --file-security <on|off> \
#       --acl_cache <on|off>
#
# Example:
#   ./configure-file-security.sh --namespace ibm-cas --file-security on --acl-cache off
###############################################################################

set -euo pipefail

############################################
# Parse Flags
############################################

NAMESPACE=""
FILE_SECURITY=""
ACL_CACHE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --file-security)
      FILE_SECURITY="$2"
      shift 2
      ;;
    --acl-cache)
      ACL_CACHE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

############################################
# Validate Required Flags
############################################
if [[ -z "$NAMESPACE" ]]; then
  echo "Error: --namespace is required"
  exit 1
fi

if [[ -z "$FILE_SECURITY" ]]; then
  echo "Error: --file-security is required"
  exit 1
fi

if [[ -z "$ACL_CACHE" ]]; then
  echo "Error: --acl_cache is required"
  exit 1
fi

echo "========================================================================"
echo "Fusion Content-aware Storage (CAS) Configure File Level Security Script"
echo "Namespace:      $NAMESPACE"
echo "File Security:  $FILE_SECURITY"
echo "ACL Cache:      $ACL_CACHE"
echo "========================================================================"


############################################
# Validate 'on'/'off'
############################################
validate_flag() {
  local value="$1"
  local name="$2"

  if [[ "$value" != "on" && "$value" != "off" ]]; then
      echo "Error: $name must be 'on' or 'off'"
      exit 1
  fi
}

validate_flag "$FILE_SECURITY" "file-security"
validate_flag "$ACL_CACHE" "acl_cache"

############################################
# Validate namespace exists
############################################
check_name_space() {
  if ! oc get ns "$NAMESPACE" &>/dev/null; then
    echo "Error: Namespace '$NAMESPACE' does not exist."
    exit 1
  fi
}
check_name_space

############################################
# Patch configmap values
############################################
set_configmap_values() {

    local fs_flag="$([ "$FILE_SECURITY" = "on" ] && echo "true" || echo "false")"
    local acl_flag="$([ "$ACL_CACHE" = "on" ] && echo "true" || echo "false")"

    oc patch configmap cas-config -n "$NAMESPACE" --type merge \
        -p "{\"data\":{\"ENABLE_FILE_LEVEL_SECURITY\":\"$fs_flag\",\"USE_ACL_CACHE\":\"$acl_flag\"}}" >/dev/null

    echo "ENABLE_FILE_LEVEL_SECURITY set to: $fs_flag"
    echo "USE_ACL_CACHE set to: $acl_flag"
}

############################################
# Patch query-search deployment
############################################
patch_query_search_deployment() {
    echo "Patching query-search deployment"

    fs_flag=$(oc get configmap cas-config -n "$NAMESPACE" -o jsonpath='{.data.ENABLE_FILE_LEVEL_SECURITY}')
    acl_flag=$(oc get configmap cas-config -n "$NAMESPACE" -o jsonpath='{.data.USE_ACL_CACHE}')

    oc set env deployment/query-search \
        ENABLE_FILE_LEVEL_SECURITY="$fs_flag" \
        USE_ACL_CACHE="$acl_flag" \
        -n "$NAMESPACE" >/dev/null || true

    oc rollout restart deployment/query-search -n "$NAMESPACE" >/dev/null

    echo "Waiting for query-search..."
    oc rollout status deployment/query-search -n "$NAMESPACE" >/dev/null
    echo "query-search updated."
}

############################################
# Patch document processors
############################################
patch_document_processor_deployments() {

    echo "Patching Document Processor Deployments"
    fs_flag=$(oc get configmap cas-config -n "$NAMESPACE" -o jsonpath='{.data.ENABLE_FILE_LEVEL_SECURITY}')

    docproc_list=($(oc get documentprocessors -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name --no-headers))

    for docproc in "${docproc_list[@]}"; do
        echo "Deleting $docproc deployment"
        oc delete deployment "$docproc" -n "$NAMESPACE" >/dev/null

        oc label documentprocessor -n "$NAMESPACE" "$docproc" FS-SECURITY="$fs_flag" --overwrite >/dev/null
        oc label documentprocessor -n "$NAMESPACE" "$docproc" FS-SECURITY- >/dev/null

        echo "Waiting for $docproc rollout..."
        oc rollout status deployment/"$docproc" -n "$NAMESPACE" >/dev/null

        initContainer="$(oc get deployment "$docproc" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.initContainers[*].name}' || true)"

        if [[ "$initContainer" == *"cast-runtime-aclchecker"* ]]; then
            echo "$docproc running with ACL checker enabled"
        else
            echo "$docproc running without ACL checker"
        fi
    done
}

############################################
# Main
############################################

set_configmap_values
patch_query_search_deployment
patch_document_processor_deployments

echo "File Security + ACL Cache configuration completed successfully."
