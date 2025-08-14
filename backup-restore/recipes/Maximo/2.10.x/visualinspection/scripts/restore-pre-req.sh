#!/bin/bash

#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing() {
  local apigroup="$1"
  local resource="$2"
  local verbs='["get", "list", "watch"]'

  echo "Checking permission for resource '$resource'..."

  oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
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
    oc patch clusterrole "$CLUSTERROLE" --type=json -p="[
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

add_rule_if_missing "apps.mas.ibm.com" "visualinspectionapps"
add_rule_if_missing "apps.mas.ibm.com" "visualinspectionappworkspaces"