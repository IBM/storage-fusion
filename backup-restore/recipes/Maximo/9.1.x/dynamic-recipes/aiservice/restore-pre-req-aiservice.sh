#!/bin/bash
source maximo_env.sh

CLUSTERROLE="transaction-manager-ibm-backup-restore"
add_rule_if_missing ${CLUSTERROLE} "aiservice.ibm.com" "aiserviceapps"
add_rule_if_missing ${CLUSTERROLE} "aiservice.ibm.com" "aiservicetenants"
add_rule_if_missing ${CLUSTERROLE} "serving.kserve.io" "inferenceservices"

AISERVICE_SA=ibm-aiservice-operator
echo -e "\nChecking if ${AISERVICE_SA} has access to configmaps in ${SLS_NAMESPACE} namespace"
CAN_ACCESS_SLS=$(oc auth can-i get configmaps --as=system:serviceaccount:${AISERVICE_NAMESPACE}:${AISERVICE_SA} -n ${SLS_NAMESPACE})
if [[ "$CAN_ACCESS_SLS" == "no" ]]; then
    suffix=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 38 | head -n 1)
    clusterrole_name=ibm-aiservice-${suffix}
    echo -e "\nCreating cluster role ${clusterrole_name}"
    oc create clusterrole ${clusterrole_name} --verb=get,list --resource=configmaps,secrets

    echo -e "\nAdding ServiceAccount ${AISERVICE_SA} to ClusterRole ${clusterrole_name}"
    oc adm policy add-cluster-role-to-user ${clusterrole_name} system:serviceaccount:${AISERVICE_NAMESPACE}:${AISERVICE_SA}

    echo -e "\nVerify ServiceAccount ${AISERVICE_SA} has access to configmaps in ${SLS_NAMESPACE} namespace"
    oc auth can-i get configmaps --as=system:serviceaccount:${AISERVICE_NAMESPACE}:${AISERVICE_SA} -n ${SLS_NAMESPACE}
else
   echo -e "\nService account ${AISERVICE_SA} already has access to SLS namespace"
fi
