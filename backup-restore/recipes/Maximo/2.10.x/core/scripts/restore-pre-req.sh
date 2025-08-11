#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

# Check if rule for suites exists
oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["core.mas.ibm.com"] and
    (.resources | contains(["suites"])) and
    (.verbs | contains(["get"]) and contains(["list"]))
  )' > /dev/null

if [[ $? -ne 0 ]]; then
  echo "Adding suites rule to ClusterRole '$CLUSTERROLE'..."
  oc patch clusterrole "$CLUSTERROLE" --type=json -p='[
    {
      "op": "add",
      "path": "/rules/-",
      "value": {
        "apiGroups": ["core.mas.ibm.com"],
        "resources": ["suites"],
        "verbs": ["get", "list"]
      }
    }
  ]'
else
  echo "Rule for suites already exists. Skipping."
fi
