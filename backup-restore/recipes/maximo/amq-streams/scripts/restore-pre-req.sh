#!/bin/bash


oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["kafka.strimzi.io"],"resources":["kafkas", "kafkausers"]}]' | oc apply -f -
