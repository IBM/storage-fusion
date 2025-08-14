#!/bin/bash

CLUSTERROLE="transaction-manager-ibm-backup-restore"

# Check if rule for licenseservices exists
oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["sls.ibm.com"] and
    (.resources | contains(["licenseservices"])) and
    (.verbs | contains(["get"]) and contains(["list"]))
  )' > /dev/null

if [[ $? -ne 0 ]]; then
  echo "Adding licenseservices rule to ClusterRole '$CLUSTERROLE'..."
  oc patch clusterrole "$CLUSTERROLE" --type=json -p='[
    {
      "op": "add",
      "path": "/rules/-",
      "value": {
        "apiGroups": ["sls.ibm.com"],
        "resources": ["licenseservices"],
        "verbs": ["get", "list"]
      }
    }
  ]'
else
  echo "Rule for licenseservices already exists. Skipping."
fi
