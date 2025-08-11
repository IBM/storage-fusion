#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

check_and_add_rule() {
  local apiGroup=$1
  local resources=$2  # JSON array string e.g. '["manageapps"]'

  # Check if all resources exist in a rule with the given apiGroup and verbs get,list
  if ! oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
    --argjson resources "$resources" \
    --arg apiGroup "$apiGroup" \
    '.rules[] | select(
      .apiGroups == [$apiGroup] and
      (.resources | all(. as $r | $resources | index($r))) and
      (.verbs | index("get")) and
      (.verbs | index("list"))
    )' > /dev/null; then

    echo "Adding rule for resources $resources in apiGroup $apiGroup to $CLUSTERROLE..."
    oc patch clusterrole "$CLUSTERROLE" --type=json -p="[
      {
        \"op\": \"add\",
        \"path\": \"/rules/-\",
        \"value\": {
          \"apiGroups\": [\"$apiGroup\"],
          \"resources\": $resources,
          \"verbs\": [\"get\", \"list\"]
        }
      }
    ]"
  else
    echo "Rule for resources $resources in apiGroup $apiGroup already exists. Skipping."
  fi
}

check_and_add_rule  "apps.mas.ibm.com" '["manageapps", "manageworkspaces"]'
