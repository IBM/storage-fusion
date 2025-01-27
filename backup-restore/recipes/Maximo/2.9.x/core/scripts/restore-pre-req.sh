#!/bin/bash

oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["core.mas.ibm.com"],"resources":["suites"]}]' | oc apply -f -

