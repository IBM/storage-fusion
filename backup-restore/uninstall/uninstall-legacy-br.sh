#!/bin/bash 
# Performs a full uninstallation for legacy Fusion Backup & Restore from the cli. Not for uninstalling new "Backup & Restore"
# Make sure you are logged into the correct cluster.

#USAGE="Usage: $0  " 

LOG=/tmp/$(basename $0)_log.txt
exec &> >(tee -a $LOG)

export NAMESPACES=("ibm-spectrum-protect-plus-ns" "baas")

err_exit()
{
  echo "ERROR: " "$@" >&2
  exit 1
}

check_cmd ()
{
  (type $1 > /dev/null) || err_exit "$1  command not found"
}

check_cmd oc
check_cmd jq

oc whoami > /dev/null || err_exit "Not logged in to a cluster"

START_TIME=$(date +%s)

print_heading()
{
   CURRENT_TIME=$(date +%s)
   ELAPSED_TIME=$(( $CURRENT_TIME - $START_TIME ))
   ELAPSED_MIN=$((  $ELAPSED_TIME / 60 ))
   ELAPSED_SEC=$((  $ELAPSED_TIME % 60 ))
  echo -e "===================================================================================================="
  echo "$(date) $ELAPSED_MIN:$ELAPSED_SEC $@"
  echo -e "===================================================================================================="
}

if ! oc get crd spectrumfusions.prereq.isf.ibm.com ; then
  err_exit "No spectrumfusion CRD found. "
fi 

FUSION_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)
export FUSION_NS

[ -z "$FUSION_NS" ] &&  err_exit "No Fusion namespace found. Exiting."

echo "Fusion Installplans:"
oc -n "${FUSION_NS}" get ip
echo "Fusion CSVs:"
oc -n "${FUSION_NS}" get csv

print_heading "Remove Backup & Restore (Legacy) from Fusion"

SF_CR=$(oc get spectrumfusion.prereq.isf.ibm.com -n "${FUSION_NS}" --no-headers -o name)
oc patch -n "${FUSION_NS}" "$SF_CR" --type json -p '[{"op": "replace", "path": "/spec/DataProtection/Enable", "value": false}]'

oc scale --replicas=0 deployment/isf-prereq-operator-controller-manager -n "${FUSION_NS}"

oc -n "$FUSION_NS" patch --type json configmap isf-data-protection-config -p '[{"op": "replace", "path": "/data/Mode", "value": "DisableWebhook"}]'

print_heading "Remove any existing Backup & Restore (Legacy) Restore CRs"
RS=$(oc -n "${FUSION_NS}" get restore.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns="NAME:metadata.name" --no-headers)
[ -n "$RS" ] && oc -n "${FUSION_NS}" delete  --timeout=60s restore.data-protection.isf.ibm.com  $RS
RS=$(oc -n "${FUSION_NS}" get restore.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns="NAME:metadata.name" --no-headers)
[ -n "$RS" ] && oc -n "${FUSION_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' restore.data-protection.isf.ibm.com $RS

print_heading "Add any existing Backup & Restore (Legacy) backup to DeleteBackupRequest"
BACKUPS=$(oc get -n "${FUSION_NS}" backups.data-protection.isf.ibm.com -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns="NAME:metadata.name" --no-headers 2> /dev/null)
for BACKUP in ${BACKUPS[@]}; do
  yaml=$(cat <<EOF
apiVersion: data-protection.isf.ibm.com/v1alpha1
kind: DeleteBackupRequest
metadata:
  annotations:
    dp.isf.ibm.com/provider-name: isf-ibmspp
  name: delete-backup-${BACKUP}
  namespace: ${FUSION_NS}
spec:
  backup: ${BACKUP}
EOF
)
  echo "$yaml" | oc apply -f -
done

retry=0
while [ "$retry" -lt 5 ]; do
  STATUS=$(oc get -n "${FUSION_NS}" deletebackuprequest.data-protection.isf.ibm.com -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers | egrep -iv "DeleteBackupRequestFailed|Cancelled|Completed|Processed|FailedValidation")
  if [ -z "$STATUS" ]; then
    echo "deletebackuprequests have finished "
    break
  else
    echo "Some deletebackuprequests are not yet finished:"
    echo "$STATUS"
    retry=$((retry + 1))
    sleep 10
  fi
done

print_heading "Remove other existing Backup & Restore (Legacy) backup CRs"
BS=$(oc -n "${FUSION_NS}" get backups.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns="NAME:metadata.name" --no-headers)
if [ -n "$BS" ]
then 
  oc -n "${FUSION_NS}" annotate --overwrite backups.data-protection.isf.ibm.com $BS fusion-config dp.isf.ibm.com/cleanup-status=complete 2> /dev/null
  oc -n "${FUSION_NS}" delete  --timeout=60s backups.data-protection.isf.ibm.com  $BS
  BS=$(oc -n "${FUSION_NS}" get backups.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns="NAME:metadata.name" --no-headers)
  [ -n "$BS" ] && oc -n "${FUSION_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' backups.data-protection.isf.ibm.com $BS
fi

print_heading "Remove any existing Backup & Restore (Legacy) Policy Assignment CRs"
PA=$(oc -n "${FUSION_NS}" get fpa  -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns=N:metadata.name --no-headers)
[ -n "$PA" ] && oc -n "${FUSION_NS}" delete  --timeout=60s fpa $PA
PA=$(oc -n "${FUSION_NS}" get fpa  -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns=N:metadata.name --no-headers)
[ -n "$PA" ] && oc -n "${FUSION_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' fpa $PA

print_heading "Remove any existing Backup & Restore (Legacy) Backup Policies CRs"
FBP=$(oc  -n "${FUSION_NS}" get fbp -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns=N:metadata.name --no-headers)
[ -n "$FBP" ] && oc -n "${FUSION_NS}" delete  --timeout=60s fbp $FBP
FBP=$(oc  -n "${FUSION_NS}" get fbp -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns=N:metadata.name --no-headers)
[ -n "$FBP" ] && oc -n "${FUSION_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' fbp $FBP

print_heading "Remove any existing Backup & Restore (Legacy) Backup Storage Location CRs "
BSL=$(oc -n "${FUSION_NS}" get fbsl -l  dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns=N:metadata.name --no-headers)
[ -n "$BSL" ] && oc -n "${FUSION_NS}" delete  --timeout=60s fbsl $BSL
BSL=$(oc -n "${FUSION_NS}" get fbsl -l  dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns=N:metadata.name --no-headers| grep -v "in-place-snapshot")
[ -n "$BSL" ] && oc -n "${FUSION_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' fbsl $BSL

print_heading "Remove any existing Backup & Restore (Legacy)  DeleteBackupRequest CRs "
DR=$(oc -n "$FUSION_NS" get fdbr -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns=N:metadata.name --no-headers)
[ -n "$DR" ] && oc -n "$FUSION_NS" delete fdbr  $DR --timeout=60s
DR=$(oc -n "$FUSION_NS" get fdbr -l dp.isf.ibm.com/provider-name=isf-ibmspp -o custom-columns=N:metadata.name --no-headers)
[ -n "$DR" ] && oc -n "${FUSION_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' fdbr $DR

print_heading "Remove sppmanager CR"
oc delete sppmanager sppmanager -n "${FUSION_NS}"

oc -n "$FUSION_NS" patch --type json configmap isf-data-protection-config -p '[{"op": "replace", "path": "/data/Mode", "value": "Normal"}]'

print_heading "Remove subscriptions in namespace ibm-spectrum-protect-plus-ns and baas" 
for NAMESPACE in ${NAMESPACES[@]}
do
  SUBSCRIPTION_NAMES=$(oc -n "${NAMESPACE}" get subs --no-headers | cut -d" " -f1)
  if [ -n "$SUBSCRIPTION_NAMES" ]; then
    print_heading "Remove any Backup & Restore (Legacy) subscriptions, csvs for dependent operators in namespace ${NAMESPACE}"
    # Delete the subscription and instance
    for SUBSCRIPTION_NAME in ${SUBSCRIPTION_NAMES[@]}
    do
      csvName=$(oc get subscription "${SUBSCRIPTION_NAME}" -n "${NAMESPACE}" -o yaml | grep currentCSV | awk -F' ' '{print $2}')
      oc delete subscription "${SUBSCRIPTION_NAME}" -n "${NAMESPACE}"
      oc delete clusterserviceversion ${csvName} -n "${NAMESPACE}"
    done
  else
    csvName=$(oc -n "${NAMESPACE}" get csv -o name)
    oc delete ${csvName} -n "${NAMESPACE}"
  fi

  # delete the operatorgroup created during install
  print_heading "Delete any existing operatorgroups in namespace ${NAMESPACE}"
  oc delete operatorgroup -n "${NAMESPACE}" --all

  print_heading "Remove namespace ${NAMESPACE}"
  if ! oc get namespace "${NAMESPACE}" ; then
    echo "Namespace ${NAMESPACE} was not found"
  else
    echo "oc delete namespace ${NAMESPACE}"
    oc delete namespace "${NAMESPACE}"
  fi
done

print_heading "Remove Backup & Restore (Legacy) catalogsource "
oc delete CatalogSource ibm-sppc-operator -n openshift-marketplace 2> /dev/null

FBR_NS=$(oc get dataprotectionservers -A -o custom-columns=NS:metadata.namespace --no-headers)
[ -z "$FBR_NS" ] && FBR_NS=$(oc get dataprotectionagent -A -o custom-columns=NS:metadata.namespace --no-headers)
export FBR_NS
if [ -n "$FBR_NS" ] ; then
  print_heading "Fusion Backup & Restore installed. Double check if OADP and AMQ subscription has the correct source."
  if [[ $(oc -n "${FBR_NS}" get $(oc get subs -n "${FBR_NS}" -o name | grep "oadp" )  -o json|jq -r .spec.source) == "ibm-sppc-operator" ]] ; then
    OADP_CAT=$(oc -n openshift-marketplace get packagemanifests redhat-oadp-operator -o custom-columns=CS:status.catalogSource --no-headers)
    OADP_SUBS=$(oc get subs -n "${FBR_NS}" -o name |grep "oadp")
    oc patch ${OADP_SUBS} -n "${FBR_NS}" --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/source\", \"value\": \"${OADP_CAT}\"}]"
  fi
  if [[ $(oc -n "${FBR_NS}" get $(oc get subs -n "${FBR_NS}" -o name | grep "amq" ) -o json|jq -r .spec.source) == "ibm-sppc-operator" ]] ; then
    AMQ_CAT=$(oc -n openshift-marketplace get packagemanifests amq-streams -o custom-columns=CS:status.catalogSource --no-headers)
    AMQ_SUBS=$(oc get subs -n "${FBR_NS}" -o name |grep "amq")
    oc patch ${AMQ_SUBS} -n "${FBR_NS}" --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/source\", \"value\": \"${AMQ_CAT}\"}]"
  fi
fi

FSD_NS=$(oc get SpectrumDiscover -A -o custom-columns=NS:metadata.namespace --no-headers)
export FSD_NS
if [ -n "$FSD_NS" ] ; then
  print_heading "Data Cataloging installed. Double check if AMQ subscription has the correct source."
  if [[ $(oc -n "${FSD_NS}" get $(oc get subs -n "${FSD_NS}" -o name | grep "amq" ) -o json|jq -r .spec.source) == "ibm-sppc-operator" ]] ; then
    AMQ_CAT=$(oc -n openshift-marketplace get packagemanifests amq-streams -o custom-columns=CS:status.catalogSource --no-headers)
    AMQ_SUBS=$(oc get subs -n "${FSD_NS}" -o name |grep "amq")
    oc patch ${AMQ_SUBS} -n "${FSD_NS}" --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/source\", \"value\": \"${AMQ_CAT}\"}]"
  fi
fi

print_heading "Deleting cluster role bindings and crds"
ROLES=$(oc get clusterrole --ignore-not-found | egrep -i "ibmsppcs.sppc.ibm.com|ibmsppc-operator-metrics-reader|baas-spp-agent|spp-operator" | cut -d" " -f1)
[ -n "$ROLES" ] && oc delete clusterrole $ROLES
BINDINGS=$(oc get clusterrolebinding --ignore-not-found | egrep -i "spp-operator|baas-spp-agent" | cut -d" " -f1)
[ -n "$BINDINGS" ] && oc delete clusterrolebinding $BINDINGS
CRDS=$(oc get crd -o name | egrep -i "ibmsppcs.sppc.ibm.com|ibmspps.ocp.spp.ibm.com")
[ -n "$CRDS" ]  && oc delete $CRDS

oc scale --replicas=1 deployment/isf-prereq-operator-controller-manager -n "${FUSION_NS}"
#make sure prereq pod is running
print_heading "Waiting for prereq pod to be ready"
oc wait --for=condition=available deploy/isf-prereq-operator-controller-manager -n "${FUSION_NS}" --timeout=300s
PREREQ_POD=$(oc -n "${FUSION_NS}" get pods -o name | grep isf-prereq-operator-controller-manager)
while [ -z "$PREREQ_POD" ]
 do
   sleep 2
   PREREQ_POD=$(oc -n "${FUSION_NS}" get pods -o name | grep isf-prereq-operator-controller-manager)
done
oc -n "${FUSION_NS}" wait --for=condition=ready "$PREREQ_POD" --timeout=300s

SF_CR_FILE=/tmp/sf_${START_TIME}_$$.yaml
oc -n "${FUSION_NS}" get "$SF_CR" -o yaml | awk '{ if ($0 == "status:") {exit} else {print $0}}' | grep -Ev '^  uid:|^  resourceVersion:|^  generation:|^  creationTimestamp:' > $SF_CR_FILE
if [ -r "$SF_CR_FILE" ] && [ -s "$SF_CR_FILE" ]
 then
   echo "Recreating $SF_CR"
   oc -n "${FUSION_NS}" delete "$SF_CR"
   oc apply -f "$SF_CR_FILE"
 else
   echo "Error: Could not clear status in $SF_CR. $SF_CR_FILE is not accessible or empty."
fi

echo "Fusion Installplans:"
oc -n "${FUSION_NS}" get ip
echo "Fusion CSVs:"
oc -n "${FUSION_NS}" get csv

print_heading "Backup and Restore (Legacy) uninstalled"
