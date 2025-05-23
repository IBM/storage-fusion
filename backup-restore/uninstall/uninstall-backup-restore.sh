#!/bin/bash 
# TO uninstall "Backup & Restore" and "Backup & Restore Agent". Not for uninstalling "Backup & Restore (Legacy)"
# Uninstall hub before uninstalling any of the spokes.
# Make sure you are logged into the correct cluster.

LOG=/tmp/$(basename $0)_log.txt
rm -f "$LOG"
exec &> >(tee -a $LOG)

echo "ARGUMENTS:" "$@"

USAGE="Usage: $0 [-u] [-d] [-b <Bakup and Restore Name Space>]
       -u to uninstall a spoke installation before uninstalling hub 
       -f to delete CRs in Fusion namespace
       -d to create DeleteBackupRequest to delete backups. Use this only if you plan to uninstall Fusion
          -d is effective only when -f is used as well
          Deleting backups is extremely slow process. May take hours or days depeding on varions factors."

err_exit()
{
        echo "ERROR:" "$@" >&2
        exit 1
}

check_cmd ()
{
   (type "$1" > /dev/null) || err_exit "$1  command not found"
}

check_cmd oc
check_cmd jq

oc whoami > /dev/null || err_exit "Not logged in a cluster"

NAMESPACE=$(oc get catsrc -A -o custom-columns=:metadata.namespace --no-headers --field-selector metadata.name=ibm-fusion-backup-restore-catalog)
[ -z "$NAMESPACE" ] && NAMESPACE=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace)
[ -z "$NAMESPACE" ] && NAMESPACE=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace)
[ -z "$NAMESPACE" ] && NAMESPACE=ibm-backup-restore
FORCE=false
SKIP=true
SKIP_ISF_CRS=true

while getopts "dfub:" OPT
do
  case ${OPT} in
    b )
      NAMESPACE="${OPTARG}"
      ;;
    f )
      SKIP_ISF_CRS=false
      ;;
    d )
      SKIP=false
      ;;
    u )
      FORCE=true
      ;;
    \? )
      err_exit "$USAGE"
      ;;
    : )
      err_exit "$USAGE"
      ;;
  esac
done

CNT_NS=$(echo $NAMESPACE | wc -w)
if  [ $CNT_NS -gt 1 ]
 then
        echo "ERROR:" "$CNT_NS candidate namespaces ' $NAMESPACE '. Use '-b' option" >&2
        err_exit "$USAGE"
fi
if [ "$SKIP_ISF_CRS" == "true" ] && [ "$SKIP" == "false" ]
 then
     print_heading "Ignored -d as -f is not present. -d is application only if -f is used"
    SKIP=true
fi

SERVER=$(oc whoami --show-server)
CONSOLE_URL=$(oc whoami --show-console)
echo "CLUSTER: $SERVER"
echo "         $CONSOLE_URL"

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

ISF_NS=$(oc get spectrumfusion -A --no-headers | cut -d" " -f1)
[ -z "$ISF_NS" ] && ISF_NS=$(oc get subs  -o custom-columns=:metadata.namespace,:spec.name -A | grep "isf-operator$"  | cut -d" " -f1)
[ -z "$ISF_NS" ] &&  ISF_NS=ibm-spectrum-fusion-ns
export ISF_NS
export NAMESPACE

echo "Fusion Namespace: $ISF_NS"
echo "Backup & Restore Namespace: $NAMESPACE"
echo "Fusion Installplans:"
oc -n "${ISF_NS}" get ip
echo "Fusion CSVs:"
oc -n "${ISF_NS}" get csv

add_lables()
{
   oc -n "$1" label $2 $3 uninstalling=true --overwrite 2>/dev/null
   oc -n "$1" label $2 $3 uninstall-date="$(date -u +%F-%H-%M-%S-%Z)" --overwrite 2>/dev/null
   oc -n "$1" label $2 $3 uninstall-user="$USER" --overwrite 2>/dev/null
   oc -n "$1" label $2 $3 uninstall-host="$(hostname -f)" --overwrite 2>/dev/null
}

add_lables "$NAMESPACE" dataprotectionagent --all
add_lables "$NAMESPACE" dataprotectionserver --all
add_lables "$ISF_NS" fusionserviceinstances 'ibm-backup-restore-service-instance ibm-backup-restore-agent-service-instance'
add_lables "$NAMESPACE" namespace "$NAMESPACE"

CONNECTION=$(oc -n "$NAMESPACE" get cm guardian-configmap -o custom-columns="CONN:data.connectionName" --no-headers)
if [ -n "$CONNECTION" ]
  then
     HUB_STATUS=$(oc -n $"NAMESPACE" get dataprotectionagent -o custom-columns=H:status.hubStatus --no-headers)
     if [ "$HUB_STATUS" == "Found" ] && [ "$FORCE" != "true" ]
      then
         err_exit 'Hub exist, uninstall hub first or use -u option to force uninstall spoke'
     fi
fi

IGNORE_DBR_STATES="DeleteBackupRequestFailed|Cancelled|Completed|FailedValidation|Processed|Redundant|CancelPending"
if [ "$SKIP" != true ]
 then
    print_heading "Remove any existing backups"
    BACKUPS=$(oc get -n "${ISF_NS}" backups.data-protection.isf.ibm.com -l dp.isf.ibm.com/provider-name=isf-backup-restore --no-headers -o custom-columns=N:metadata.name 2> /dev/null)
    for BACKUP in ${BACKUPS[@]}; do
        export BACKUP

        YAML=$(cat <<EOF
apiVersion: data-protection.isf.ibm.com/v1alpha1
kind: DeleteBackupRequest
metadata:
  annotations:
    dp.isf.ibm.com/provider-name: isf-backup-restore
  name: delete-backup-$BACKUP
  namespace: $ISF_NS
spec:
  backup: $BACKUP
EOF
        )
        echo "$YAML" | oc apply -f -
    done

    UNFINISHED=$(oc -n "$ISF_NS" get fdbr -o custom-columns=NAME:metadata.name,STATUS:status.phase --no-headers | grep -ivE "$IGNORE_DBR_STATES" )

    while [ -n "$UNFINISHED" ]
     do
      echo "Some requests still not finished"
      oc -n "$ISF_NS" get fdbr -o custom-columns=NAME:metadata.name,STATUS:status.phase --no-headers | grep -ivE "$IGNORE_DBR_STATES"
      sleep 5
      UNFINISHED=$(oc -n "$ISF_NS" get fdbr -o custom-columns=NAME:metadata.name,STATUS:status.phase --no-headers | grep -ivE "$IGNORE_DBR_STATES" )
    done
fi

oc -n "$ISF_NS" patch --type json configmap isf-data-protection-config -p '[{"op": "replace", "path": "/data/Mode", "value": "DisableWebhook"}]'

if [ "$SKIP_ISF_CRS" == "true" ]
  then
     print_heading "Skipping deletion of Fusion CRs"
  else
     print_heading "Remove any DeleteBackupRequest CRs"
     DR=$(oc -n "$ISF_NS" get fdbr -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns=N:metadata.name --no-headers)
     [ -n "$DR" ] && oc -n "$ISF_NS" delete fdbr  $DR --timeout=60s
     DR=$(oc -n "$ISF_NS" get fdbr -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns=N:metadata.name --no-headers)
     [ -n "$DR" ] && oc -n "${ISF_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' fdbr $DR

     print_heading "Remove any existing policyAssigments CRs"
     PA=$(oc -n "$ISF_NS" get policyassignments.data-protection.isf.ibm.com -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns=N:metadata.name --no-headers)
     [ -n "$PA" ] && oc -n "$ISF_NS" delete policyassignments.data-protection.isf.ibm.com  $PA --timeout=60s
     PA=$(oc -n "$ISF_NS" get policyassignments.data-protection.isf.ibm.com -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns=N:metadata.name --no-headers)
     [ -n "$PA" ] && oc -n "${ISF_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' fpa $PA

     print_heading "Remove any existing backuppolicies CRs"
     BP=$(oc -n "$ISF_NS" get backuppolicies.data-protection.isf.ibm.com -o custom-columns="NAME:metadata.name,PROVIDER:spec.provider" --no-headers | grep 'isf-backup-restore$' | cut -f1 -d " ")
     [ -n "$BP" ] && oc -n "$ISF_NS" delete backuppolicies.data-protection.isf.ibm.com  $BP --timeout=60s
     BP=$(oc -n "$ISF_NS" get backuppolicies.data-protection.isf.ibm.com -o custom-columns="NAME:metadata.name,PROVIDER:spec.provider" --no-headers | grep 'isf-backup-restore$' | cut -f1 -d " ")
     [ -n "$BP" ] && oc -n "${ISF_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' fbp $BP


     print_heading "Remove any existing backup CRs"
     BS=$(oc -n "$ISF_NS" get backups.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns="NAME:metadata.name" --no-headers)
     if [ -n "$BS" ]
       then 
              oc -n "$ISF_NS" annotate --overwrite backups.data-protection.isf.ibm.com $BS fusion-config dp.isf.ibm.com/cleanup-status=complete
              oc -n "$ISF_NS" delete backups.data-protection.isf.ibm.com  $BS --timeout=60s
              BS=$(oc -n "$ISF_NS" get backups.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns="NAME:metadata.name" --no-headers)
              [ -n "$BS" ] && oc -n "${ISF_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' fbackup $BS
     fi

     print_heading "Remove any existing restore CRs"
     RS=$(oc -n "$ISF_NS" get restore.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns="NAME:metadata.name" --no-headers)
     [ -n "$RS" ] && oc -n "$ISF_NS" delete restore.data-protection.isf.ibm.com  $RS --timeout=60s
     RS=$(oc -n "$ISF_NS" get restore.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns="NAME:metadata.name" --no-headers)
     [ -n "$RS" ] && oc -n "${ISF_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' frestore $RS

     print_heading "Remove any existing backuplocations CRs"
     BSL=$(oc -n "$ISF_NS" get backupstoragelocation.data-protection.isf.ibm.com -o custom-columns="NAME:metadata.name,PROVIDER:spec.provider" --no-headers | grep 'isf-backup-restore$' | cut -f1 -d " ")
     [ -n "$BSL" ] && oc -n "$ISF_NS" delete --timeout=60s backupstoragelocation.data-protection.isf.ibm.com $BSL
     BSL=$(oc -n "$ISF_NS" get backupstoragelocation.data-protection.isf.ibm.com -o custom-columns="NAME:metadata.name,PROVIDER:spec.provider" --no-headers | grep 'isf-backup-restore$' | cut -f1 -d " " | grep -v "isf-dp-inplace-snapshot")
     [ -n "$BSL" ] && oc -n "${ISF_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' fbsl $BSL
     print_heading "Remove any BSL secrets"
     BSL_SECRET=$(oc -n "$ISF_NS" get secret -l dp.isf.ibm.com/ownedBy=fbsl,dp.isf.ibm.com/provider-name=isf-backup-restore  -o custom-columns="NAME:metadata.name" --no-headers)
     [ -n "$BSL_SECRET" ] && oc -n "$ISF_NS" delete --timeout=60s secret $BSL_SECRET
     BSL_SECRET=$(oc -n "$ISF_NS" get secret -l dp.isf.ibm.com/ownedBy=fbsl,dp.isf.ibm.com/provider-name=isf-backup-restore  -o custom-columns="NAME:metadata.name" --no-headers)
     [ -n "$BSL_SECRET" ] && oc -n "${ISF_NS}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' secret $BSL_SECRET
fi

print_heading "Delete any existing guardiancopybackups CRs"
oc delete guardiancopybackups -n "${NAMESPACE}" --all --timeout=60s
print_heading "Delete any existing guardiancopyrestores CRs"
oc delete guardiancopyrestores -n "${NAMESPACE}" --all --timeout=60s
print_heading "Delete any existing guardianmongoes CRs"
oc delete guardianmongoes -n "${NAMESPACE}" --all --timeout=60s
print_heading "Delete any existing kafkatopics CRs"
oc delete  kafkatopics.kafka.strimzi.io -n "${NAMESPACE}" --all --timeout=60s
# remove velero backuprepositories so that velero doesn't think repositories still exist on reinstall
print_heading "Removing Velero CRs"
oc delete backuprepositories.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete backups.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete backupstoragelocations.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete datadownloads.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete datauploads.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete deletebackuprequests.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete downloadrequests.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete podvolumebackups.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete podvolumerestores.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete restores.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete schedules.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete serverstatusrequests.velero.io -n "${NAMESPACE}" --all --timeout=60s
oc delete volumesnapshotlocations.velero.io -n "${NAMESPACE}" --all --timeout=60s

KT=$(oc -n "${NAMESPACE}" get kafkatopics.kafka.strimzi.io -o custom-columns="NAME:metadata.name" --no-headers)
[ -n "$KT" ] && oc -n "${NAMESPACE}" patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' kafkatopics.kafka.strimzi.io $KT
oc delete  kafkatopics.kafka.strimzi.io -n "${NAMESPACE}" --all --timeout=60s

remove_fsi ()
{
   print_heading "Remove any existing fusionserviceinstances"
   for FBRI in $(oc -n "$ISF_NS" get fusionserviceinstance --no-headers | awk '{print $1}')
   do
           echo "Checking $FBRI"
           TEMP=$(oc -n "$ISF_NS" get fusionserviceinstance "$FBRI" -o json |jq -rc '[(.spec.parameters[]|"\n",.name,.value)]|@csv' | tr -d '"' | grep ",namespace," | cut -d"," -f3)
           if [ "$TEMP" == "$NAMESPACE" ]
            then 
               print_heading "Update fusionservicedefinition and Remove fusionserviceinstance $FBRI" 
               FSD=$(oc -n "$ISF_NS" get fusionserviceinstance "$FBRI" -o json | jq -rc '.spec.serviceDefinition')
               oc -n "$ISF_NS" patch --type json fusionservicedefinition $FSD -p '[{"op": "replace", "path": "/spec/onboarding/serviceOperatorSubscription/triggerCatSrcCreate", "value": false}]'
               echo "oc delete -n $ISF_NS fusionserviceinstance $FBRI"
               oc delete -n "$ISF_NS" fusionserviceinstance "$FBRI" --timeout=60s
           fi
   done
}

remove_fsi

print_heading "Delete Redis"
oc delete redis redis -n "${NAMESPACE}" --timeout=60s
if oc get redis redis -n "${NAMESPACE}" >/dev/null 2>&1; then
   oc patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' redis redis -n "${NAMESPACE}"
   oc delete redis redis -n "${NAMESPACE}"
fi

if oc get redis redis -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Redis instance still exists. You may need to deleted it manually."
fi

# Subscriptions for dependent operators
SUBSCRIPTION_NAMES=$(oc -n "${NAMESPACE}" get subs --no-headers | cut -d" " -f1)

print_heading "Remove any subscriptions, csvs and operatorgroups for dependent operators in namespace ${NAMESPACE}"
# Delete the subscription and instance
for SUBSCRIPTION_NAME in ${SUBSCRIPTION_NAMES[@]}
do
    csvName=$(oc get subscription "${SUBSCRIPTION_NAME}" -n "${NAMESPACE}" -o yaml | grep currentCSV | awk -F' ' '{print $2}')
    echo "===== Deleting subscription $SUBSCRIPTION_NAME"
    oc delete subscription "${SUBSCRIPTION_NAME}" -n "${NAMESPACE}" --timeout=60s
    echo "===== Deleting csv ${csvName}"
    oc delete clusterserviceversion ${csvName} -n "${NAMESPACE}" --timeout=60s
done

# delete the operatorgroup created during install
print_heading "Delete any existing operatorgroups"
oc delete operatorgroup -n "${NAMESPACE}" --all --timeout=60s

print_heading "Namespace removal started at $(date)"
echo

if ! oc get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Namespace ${NAMESPACE} was not found"
  else
    echo "oc delete namespace ${NAMESPACE}"
    oc delete namespace "${NAMESPACE}"
fi
oc delete validatingwebhookconfigurations -l olm.owner.namespace="${NAMESPACE}" --ignore-not-found --timeout=60s
oc delete mutatingwebhookconfigurations -l olm.owner.namespace="${NAMESPACE}" --ignore-not-found --timeout=60s

remove_fsi

oc -n "$ISF_NS" patch --type json configmap isf-data-protection-config -p '[{"op": "replace", "path": "/data/Mode", "value": "Normal"}]'

INSTS=$(oc get dataprotectionserver -A -o name 2> /dev/null)
INSTA=$(oc get dataprotectionagent  -A -o name 2> /dev/null)
[ -n "$INSTA" ] && INSTS="$INSTS $INSTA"
if [ -z "$INSTS" ] 
 then
     echo "==== Deleting Fusion control plane recipe"
     oc -n "$ISF_NS" delete recipes.spp-data-protection.isf.ibm.com fusion-control-plane
     echo "==== Deleting cluster role bindings and crds"
     ROLES=$(oc get clusterrole --ignore-not-found | grep -iE "guardian|ibm-backup-restore|dataprotectionagent|dataprotectionserver|ibm-datamover" | cut -d" " -f1)
     [ -n "$ROLES" ] && oc delete clusterrole $ROLES --timeout=60s
     BINDINGS=$(oc get clusterrolebinding --ignore-not-found | grep -iE "guardian|ibm-backup-restore|dataprotectionagent|dataprotectionserver|ibm-datamover" | cut -d" " -f1)
     [ -n "$BINDINGS" ] && oc delete clusterrolebinding $BINDINGS --timeout=60s
     oc delete scc ibm-datamover --timeout=60s
     CRDS=$(oc get crd -o name | grep -E 'guardian.*ibm.com|dataprotectionserver.*.ibm.com|dataprotectionagent.*.ibm.com')
     [ -n "$CRDS" ]  && oc delete $CRDS --timeout=60s
 else
   echo "==== Other copies of Backup & Restore exist in following namespaces"
   oc get dataprotectionagent,dataprotectionserver -A --no-headers| cut -d" " -f1
fi
#Delete namespace again just in case it was recreated in the meantime
echo "oc delete namespace ${NAMESPACE}"
oc delete namespace "${NAMESPACE}"

echo "Fusion Installplans:"
oc -n "${ISF_NS}" get ip
echo "Fusion CSVs:"
oc -n "${ISF_NS}" get csv
print_heading "Backup and Restore uninstalled"
