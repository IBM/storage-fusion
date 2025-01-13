#!/bin/bash

oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["apps.mas.ibm.com"],"resources":["manageapps"]},{"verbs":["get","list"],"apiGroups":["apps.mas.ibm.com"],"resources":["manageworkspaces"]}]' | oc apply -f -
