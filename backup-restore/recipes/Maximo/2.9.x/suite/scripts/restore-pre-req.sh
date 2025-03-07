#!/bin/bash

# Including MongoDB CRs in Transaction Manager clusterrole
echo -e "\n=== Including MongoDB CRs in Transaction Manager clusterrole ==="
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["mongodbcommunity.mongodb.com"],"resources":["mongodbcommunity"]}]' | oc apply -f -

# Including SLS CRs in Transaction Manager clusterrole
echo -e "\n=== Including SLS CRs in Transaction Manager clusterrole ==="
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["sls.ibm.com"],"resources":["licenseservices"]}]' | oc apply -f -

# Including Core CRs in Transaction Manager clusterrole
echo -e "\n=== Including Core CRs in Transaction Manager clusterrole ==="
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["core.mas.ibm.com"],"resources":["suites"]}]' | oc apply -f -

