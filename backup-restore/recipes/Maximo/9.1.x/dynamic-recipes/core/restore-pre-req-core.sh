#!/bin/bash
source maximo_env.sh

CLUSTERROLE="transaction-manager-ibm-backup-restore"
add_rule_if_missing ${CLUSTERROLE} "core.mas.ibm.com" "suites"
add_rule_if_missing ${CLUSTERROLE} "operators.coreos.com" "clusterserviceversions"
