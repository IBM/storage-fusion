#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

# Check if the rule for db2uclusters already exists
oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["db2u.databases.ibm.com"] and
    (.resources | contains(["db2uclusters"])) and
    (.verbs | contains(["get"]) and contains(["list"]))
  )' > /dev/null

if [[ $? -ne 0 ]]; then
  echo "Adding db2uclusters rule to ClusterRole '$CLUSTERROLE'..."
  oc patch clusterrole "$CLUSTERROLE" --type=json -p='[
    {
      "op": "add",
      "path": "/rules/-",
      "value": {
        "apiGroups": ["db2u.databases.ibm.com"],
        "resources": ["db2uclusters"],
        "verbs": ["get", "list"]
      }
    }
  ]'
else
  echo "Rule for db2uclusters already exists. Skipping."
fi
