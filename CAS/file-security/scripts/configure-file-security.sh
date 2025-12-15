#!/bin/bash

###############################################################################
# Script Name: configure-file-security.sh
# Purpose: To enable or disable file level security in CAS.
#
# Description:
#   This script modifies the cas-config configmap to enable file level
#   security and restarts the query search and document processors 
#   deployments.
#
# Prerequisites:
#   - You must be logged into the OpenShift cluster using `oc login`
#
# Usage:
#   ./configure-file-secuity.sh [<namespace>] [<file-security>] 
#
#   <namespace> (required): The namespace where CAS is installed.
#
#   <file-security> (required): Set to true to enable file level security
#   and false to disable file level secuity
# 
# Example:
#  ./configure-file-secuity.sh ibm-cas true
###############################################################################

set -euo pipefail

NAMESPACE="$1"
FILE_SECURITY="$2"

echo "========================================================================"
echo "Fusion Content-aware Storage (CAS) Configure File Level Security Script"
echo "Target Namespace: $NAMESPACE"
echo "========================================================================"

# Function to check if namespace exists
check_name_space(){
if ! oc get ns "$NAMESPACE" &>/dev/null; then
  echo "Namespace '$NAMESPACE' does not exist."
  exit 1
fi
}

# Fucntion to validate file security as 'true' or 'false'
validate_file_security(){
    if [ "$FILE_SECURITY" = "true" ]; then
        :
    elif [ "$FILE_SECURITY" = "false" ]; then
        :
    else
        echo "Error: Argument must be 'true' or 'false'"
        exit 1
    fi
}

# Function to set FENABLE_FILE_LEVEL_SECURITY in cas-config configmap
set_file_security(){
    enable_flag=($(oc get configmap cas-config -n $NAMESPACE -o jsonpath='{.data.ENABLE_FILE_LEVEL_SECURITY}' || true))
    if [ "$enable_flag" = "$FILE_SECURITY" ]; then
        echo "ENABLE_FILE_LEVEL_SECURITY is already set to $FILE_SECURITY"
        exit 0
    else
        oc patch configmap cas-config -n $NAMESPACE --type merge -p "{\"data\":{\"ENABLE_FILE_LEVEL_SECURITY\":\"$FILE_SECURITY\"}}" >/dev/null || true
        echo "ENABLE_FILE_LEVEL_SECURITY is now set to $FILE_SECURITY"
    fi
}

# Function to patch query search deployment with ENABLE_FILE_LEVEL_SECURITY
patch_query_search_deployment(){
    echo "Patching query-search deployment"
    enable_flag=($(oc get configmap cas-config -n $NAMESPACE -o jsonpath='{.data.ENABLE_FILE_LEVEL_SECURITY}' || true))
    oc set env deployment/query-search ENABLE_FILE_LEVEL_SECURITY=$enable_flag -n $NAMESPACE >/dev/null || true; 
    echo "Restarting query-search deployment"
    while true; do
        if  oc rollout status deployment/query-search -n $NAMESPACE >/dev/null 2>&1; then # wait for deployment to be ready
            break
        else
            sleep 2
        fi
    done         
    echo "Query-search deployment is available"
}

# Function to patch document processor deployments with ENABLE_FILE_LEVEL_SECURITY f
patch_document_processor_deployments(){
    echo "Patching Document Processor Deployments"
    enable_flag=($(oc get configmap cas-config -n $NAMESPACE -o jsonpath='{.data.ENABLE_FILE_LEVEL_SECURITY}' || true))
    docproc_list=($(oc get documentprocessors -n $NAMESPACE -o custom-columns=NAME:.metadata.name --no-headers))
    for docproc in "${docproc_list[@]}";
        do
            echo "Deleting $docproc deploymnet"
            oc delete deployment $docproc -n $NAMESPACE > /dev/null
            oc label documentprocessor -n $NAMESPACE $docproc FS-SECURITY=$enable_flag --overwrite >/dev/null  || true #Modify documentprocessor CR to create deployment
            oc label documentprocessor -n $NAMESPACE $docproc FS-SECURITY- >/dev/null || true # Remove label
            echo "Restarting $docproc deployment"
            while true; do
                if oc rollout status deployment/$docproc -n $NAMESPACE >/dev/null 2>&1; then # wait for deployment to be ready
                    break
                else
                    sleep 2
                fi
            done           
            echo "$docproc deploymnet available"
            initContainer="$(oc get deployment "$docproc" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.initContainers[*].name}' || true)" # Check for aclchecker container
            if [[ "$initContainer" == "cast-runtime-aclchecker" ]]; then
                echo "$docproc deployment is running with file level security"
            else
                echo "$docproc deployment is running without file level security"
            fi
    done
}
check_name_space
validate_file_security
set_file_security
patch_query_search_deployment
patch_document_processor_deployments
echo "File Level Security Script has completed successfully."