#!/bin/bash
source maximo_env.sh

CLUSTERROLE="transaction-manager-ibm-backup-restore"
add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "visualinspectionapps"
add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "visualinspectionappworkspaces"