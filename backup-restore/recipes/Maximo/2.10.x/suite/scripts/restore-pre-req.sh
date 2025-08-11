#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

check_and_add_rule() {
  local apiGroup=$1
  local resource=$2

  echo -e "\n=== Processing CRs for apiGroup: $apiGroup, resource: $resource ==="

  oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
    --arg apiGroup "$apiGroup" \
    --arg resource "$resource" \
    '.rules[] | select(
      (.apiGroups | index($apiGroup)) and
      (.resources | index($resource)) and
      (.verbs | index("get")) and
      (.verbs | index("list"))
    )' > /dev/null

  if [[ $? -ne 0 ]]; then
    echo "Adding rule for $resource in $apiGroup to ClusterRole '$CLUSTERROLE'..."
    oc patch clusterrole "$CLUSTERROLE" --type=json -p="[
      {
        "op": "add",
        "path": "/rules/-",
        "value": {
          "apiGroups": ["$apiGroup"],
          "resources": ["$resource"],
          "verbs": ["get", "list"]
        }
      }
    ]"
  else
    echo "Rule for $resource in $apiGroup already exists. Skipping."
  fi
}

check_and_add_rule "mongodbcommunity.mongodb.com" "mongodbcommunity"
check_and_add_rule "sls.ibm.com" "licenseservices"
check_and_add_rule "core.mas.ibm.com" "suites"
