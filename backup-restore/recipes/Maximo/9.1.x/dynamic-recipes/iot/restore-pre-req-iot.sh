#!/bin/bash
source maximo_env.sh

CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing ${CLUSTERROLE} "iot.ibm.com" "iotworkspaces"
add_rule_if_missing ${CLUSTERROLE} "iot.ibm.com" "iots"
