#!/bin/bash

oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["apps.mas.ibm.com"],"resources":["optimizerapps"]},{"verbs":["get","list"],"apiGroups":["apps.mas.ibm.com"],"resources":["optimizerworkspaces"]}]' | oc apply -f -
