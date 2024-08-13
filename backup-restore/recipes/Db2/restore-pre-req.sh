#!/bin/bash

oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["db2u.databases.ibm.com"],"resources":["db2uengines", "db2uinstances", "db2uclusters"]}]' | oc apply -f -
