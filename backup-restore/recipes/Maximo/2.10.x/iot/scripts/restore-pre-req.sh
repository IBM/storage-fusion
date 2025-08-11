#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

RULES=(
  '{"apiGroups":["iot.ibm.com"],"resources":["iots","iotworkspaces"],"verbs":["get","list"]}'
)

for rule_json in "${RULES[@]}"; do
  apiGroup=$(echo "$rule_json" | jq -r '.apiGroups[0]')
  resources=$(echo "$rule_json" | jq -c '.resources')
  verbs=$(echo "$rule_json" | jq -c '.verbs')

  exists=$(oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
    --arg apiGroup "$apiGroup" \
    --argjson resources "$resources" \
    --argjson verbs "$verbs" \
    '.rules[] | select(
      .apiGroups == [$apiGroup] and
      (.resources | all(. as $r | $resources | index($r))) and
      (.verbs | index("get")) and
      (.verbs | index("list"))
    )' > /dev/null && echo yes || echo no)

  if [[ "$exists" == "no" ]]; then
    echo "Adding rule for resources $resources in apiGroup $apiGroup to $CLUSTERROLE..."
    oc patch clusterrole "$CLUSTERROLE" --type=json -p="[
      {
        \"op\": \"add\",
        \"path\": \"/rules/-\",
        \"value\": $rule_json
      }
    ]"
  else
    echo "Rule for resources $resources in apiGroup $apiGroup already exists. Skipping."
  fi
done
