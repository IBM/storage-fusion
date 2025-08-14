#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

# Check if the specific rule already exists
oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["kafka.strimzi.io"] and
    (.resources | contains(["kafkas"]) and contains(["kafkausers"])) and
    (.verbs | contains(["get"]) and contains(["list"]) and contains(["watch"]))
  )' > /dev/null

if [[ $? -ne 0 ]]; then
  echo "Adding new rule to ClusterRole '$CLUSTERROLE'..."
  oc patch clusterrole "$CLUSTERROLE" --type=json -p='[
    {
      "op": "add",
      "path": "/rules/-",
      "value": {
        "apiGroups": ["kafka.strimzi.io"],
        "resources": ["kafkas", "kafkausers"],
        "verbs": ["get", "list", "watch"]
      }
    }
  ]'
else
  echo "Rule already exists. Skipping."
fi
