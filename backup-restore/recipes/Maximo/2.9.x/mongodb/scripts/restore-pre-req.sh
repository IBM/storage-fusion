#!/bin/bash

oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["mongodbcommunity.mongodb.com"],"resources":["mongodbcommunity"]}]' | oc apply -f -
