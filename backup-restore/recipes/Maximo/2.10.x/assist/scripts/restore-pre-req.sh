#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

# Define rules with combined resources per apiGroup
RULES=(
  '{"apiGroups":["apps.mas.ibm.com"],"resources":["assistapps","assistworkspaces"],"verbs":["get","list"]}'
)

for rule_json in "${RULES[@]}"; do
  apiGroups=$(echo "$rule_json" | jq -r '.apiGroups[0]')
  resources=$(echo "$rule_json" | jq -c '.resources')
  verbs=$(echo "$rule_json" | jq -c '.verbs')

  # Check if a rule with all these resources and apiGroup exists
  exists=$(oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
    --arg apiGroups "$apiGroups" \
    --argjson resources "$resources" \
    --argjson verbs "$verbs" \
    '.rules[] | select(
      .apiGroups == [$apiGroups] and
      (.resources | all(. as $r | $resources | index($r))) and
      (.verbs | index("get")) and
      (.verbs | index("list"))
    )' >/dev/null && echo yes || echo no)

  if [[ "$exists" == "no" ]]; then
    echo "Adding rule for resources $resources in apiGroup $apiGroups to $CLUSTERROLE..."
    oc patch clusterrole "$CLUSTERROLE" --type=json -p="[
      {
        "op": "add",
        "path": "/rules/-",
        "value": $rule_json
      }
    ]"
  else
    echo "Rule for resources $resources in apiGroup $apiGroups already exists. Skipping."
  fi
done
