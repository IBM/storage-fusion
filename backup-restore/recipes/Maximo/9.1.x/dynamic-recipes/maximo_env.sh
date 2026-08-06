#!/bin/bash

# Variables are grouped by application, modify this script based on applications to backup and restore

# MAS Core / MAS Manage / MongoDb
export MAS_INSTANCE_ID=${MAS_INSTANCE_ID:-arft}

#MAS Core
export REPORTING_OPERATOR_NAMESPACE=${REPORTING_OPERATOR_NAMESPACE:-redhat-marketplace}
export REPORTING_OPERATOR=${REPORTING_OPERATOR:-dro}

# MAS Manage
export MAS_WORKSPACE_ID=${MAS_WORKSPACE_ID:-dev}

# MongoDb
export MONGODB_NAMESPACE=${MONGODB_NAMESPACE:-mongoce}

# DB2
export DB2_NAMESPACE=${DB2_NAMESPACE:-db2u}

# AMQ Streams
# MAS Core also requires this variable, if no kafka resource to backup, leave default value
export KAFKA_NAMESPACE=${KAFKA_NAMESPACE:-amq-streams}

# SLS
export SLS_NAMESPACE=${SLS_NAMESPACE:-ibm-sls}

# Visual Inspection
export VISUALINSPECTION_NAMESPACE=${VISUALINSPECTION_NAMESPACE:-"mas-${MAS_INSTANCE_ID}-visualinspection"}

# Spectrum fusion namespace
export ISF_NAMESPACE=${ISF_NAMESPACE:-"ibm-spectrum-fusion-ns"}

# AI Service
export AI_INSTANCE_ID=${AI_INSTANCE_ID:-arftai}
export AISERVICE_NAMESPACE=${AISERVICE_NAMESPACE:-"aiservice-${AI_INSTANCE_ID}"}
export AISERVICE_TENANT_NAMESPACE=${AISERVICE_TENANT_NAMESPACE:-"aiservice-${AI_INSTANCE_ID}-user"}
export MINIO_NAMESPACE=${MINIO_NAMESPACE:-minio}
export ODH_NAMESPACE=${ODH_NAMESPACE:-opendatahub}

add_rule_if_missing() {
  local clusterrole="$1"
  local apigroup="$2"
  local resource="$3"
  local verbs='["get", "list", "watch"]'

  echo "Checking permission for resource '$resource'..."

  oc get clusterrole "$clusterrole" -o json | jq -e \
    --arg apigroup "$apigroup" \
    --arg resource "$resource" \
    --argjson verbs "$verbs" \
    '
    .rules[] | select(
      .apiGroups == [$apigroup] and
      (.resources | index($resource)) and
      (.verbs | index("get") and index("list") and index("watch"))
    )
    ' > /dev/null

  if [[ $? -ne 0 ]]; then
    echo "Adding rule for resource '$resource'..."
    oc patch clusterrole "$clusterrole" --type=json -p="[
      {
        "op": "add",
        "path": "/rules/-",
        "value": {
          "apiGroups": ["$apigroup"],
          "resources": ["$resource"],
          "verbs": ["get", "list", "watch"]
        }
      }
    ]"
  else
    echo "Rule for resource '$resource' already exists. Skipping."
  fi
}

add_ns_if_missing_from_fapp() {
  local APP_NAMESPACE="$1"
  local CORE_NAMESPACE="mas-${MAS_INSTANCE_ID}-core"
  echo -e "\n=== Checking if ${APP_NAMESPACE} is added to ${CORE_NAMESPACE} Fusion App CR ==="
  app_ns="$(oc get fapp -n ${ISF_NAMESPACE} ${CORE_NAMESPACE} -ojson | jq --arg APP_NAMESPACE "${APP_NAMESPACE}" '.spec.includedNamespaces[] | select(. == $APP_NAMESPACE)')"
  if [[ -z "${app_ns}" ]]; then
    echo "${APP_NAMESPACE} not included, adding to Fusion App CR..."
    oc patch -n ${ISF_NAMESPACE} fapp ${CORE_NAMESPACE} --type=json -p='[{"op": "add", "path": "/spec/includedNamespaces/-", "value": "'${APP_NAMESPACE}'"}]'
  else
    echo "${APP_NAMESPACE} already added."
  fi
}
