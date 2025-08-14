#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

# Check if rule for mongodbcommunity exists
oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["mongodbcommunity.mongodb.com"] and
    (.resources | contains(["mongodbcommunity"])) and
    (.verbs | contains(["get"]) and contains(["list"]))
  )' > /dev/null

if [[ $? -ne 0 ]]; then
  echo "Adding mongodbcommunity rule to ClusterRole '$CLUSTERROLE'..."
  oc patch clusterrole "$CLUSTERROLE" --type=json -p='[
    {
      "op": "add",
      "path": "/rules/-",
      "value": {
        "apiGroups": ["mongodbcommunity.mongodb.com"],
        "resources": ["mongodbcommunity"],
        "verbs": ["get", "list"]
      }
    }
  ]'
else
  echo "Rule for mongodbcommunity already exists. Skipping."
fi
