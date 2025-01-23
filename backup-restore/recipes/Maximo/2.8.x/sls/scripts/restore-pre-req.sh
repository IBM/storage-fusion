#!/bin/bash

oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["sls.ibm.com"],"resources":["licenseservices"]}]' | oc apply -f -
