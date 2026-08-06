#!/bin/bash
source maximo_env.sh

CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing ${CLUSTERROLE} "kafka.strimzi.io" "kafkas"
add_rule_if_missing ${CLUSTERROLE} "kafka.strimzi.io" "kafkausers"

