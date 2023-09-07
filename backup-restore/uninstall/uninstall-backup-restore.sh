#!/bin/bash 
# TO uninstall "Backup & Restore" and "Backup & Restore Agent". Not for uninstalling "Backup & Restore (Legacy)"
# Uninstall hub before uninstalling any of the spokes.
# Make sure you are logged into the correct cluster.

USAGE="Usage: $0 [-u] [-d] [-b <Bakup and Restore Name Space>]
       -u to unistall a spoke installation before uninstalling hub 
       -d to creat DeleteBackupRequest to delete backups. Use this if you plan to uninstall Fusion"

NAMESPACE=ibm-backup-restore
FORCE=false
SKIP=true

err_exit()
{
        echo "ERROR:" "$@" >&2
        exit 1
}

while getopts "dub:" OPT
do
  case ${OPT} in
    b )
      NAMESPACE="${OPTARG}"
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

check_cmd ()
{
   (type "$1" > /dev/null) || err_exit "$1  command not found"
}

check_cmd oc
check_cmd jq

oc whoami > /dev/null || err_exit "Not logged in a cluster"


print_heading()
{
  echo
  echo -e "===================================================================================================="
  echo -e "$(date)" "$@"
  echo -e "===================================================================================================="
}


# Track time to set future expectations
UNINSTALL_STARTED="$(date +%s)"

ISF_NS=$(oc get spectrumfusion -A --no-headers | cut -d" " -f1)
[ -z "$ISF_NS" ] &&  ISF_NS=ibm-spectrum-fusion-ns
export ISF_NS

CONNECTION=$(oc -n "$NAMESPACE" get cm guardian-configmap -o custom-columns="CONN:data.connectionName" --no-headers)
if [ -n "$CONNECTION" ]
  then
     HUB_STATUS=$(oc -n $"NAMESPACE" get dataprotectionagent -o custom-columns=H:status.hubStatus --no-headers)
     if [ "$HUB_STATUS" == "Found" ] && [ "$FORCE" != "true" ]
      then
         err_exit 'Hub exist, uninstall hub first or use -u option to force uninstall spoke'
     fi
fi

if [ "$SKIP" != true ]
 then
    print_heading "Remove any existing backups"
    BACKUPS=$(oc get -n "${ISF_NS}" backups.data-protection.isf.ibm.com -l dp.isf.ibm.com/provider-name=isf-backup-restore | awk '{print $1}' 2> /dev/null)
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

    UNFINISHED=$(oc -n "$ISF_NS" get  deletebackuprequest.data-protection.isf.ibm.com -o custom-columns=NAME:metadata.name,STATUS:status.phase --no-headers | grep -ivE "DeleteBackupRequestFailed|Cancelled|Completed|FailedValidation" )

    while [ -n "$UNFINISHED" ]
     do
      echo "Some requests still not finished"
      oc -n "$ISF_NS" get deletebackuprequest.data-protection.isf.ibm.com -o custom-columns=NAME:metadata.name,STATUS:status.phase --no-headers | grep -ivE "DeleteBackupRequestFailed|Cancelled|Completed|FailedValidation"
      sleep 5
      UNFINISHED=$(oc -n "$ISF_NS" get deletebackuprequest.data-protection.isf.ibm.com -o custom-columns=NAME:metadata.name,STATUS:status.phase --no-headers | grep -ivE "DeleteBackupRequestFailed|Cancelled|Completed|FailedValidation" )
    done
fi

PA=$(oc -n "$ISF_NS" get policyassignments.data-protection.isf.ibm.com --no-headers | grep "isf-backup-restore" | cut -f1 -d" ")
[ -n "$PA" ] && oc -n "$ISF_NS" delete policyassignments.data-protection.isf.ibm.com  $PA

print_heading "Remove any existing backuppolicies CRs"
BP=$(oc -n "$ISF_NS" get backuppolicies.data-protection.isf.ibm.com -o custom-columns="NAME:metadata.name,PROVIDER:spec.provider" --no-headers | grep 'isf-backup-restore$' | cut -f1 -d " ")
[ -n "$BP" ] && oc -n "$ISF_NS" delete backuppolicies.data-protection.isf.ibm.com  $BP


print_heading "Remove any existing backup CRs"
BS=$(oc -n "$ISF_NS" get backups.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns="NAME:metadata.name" --no-headers)
if [ -n "$BS" ]
  then 
         oc -n "$ISF_NS" annotate --overwrite backups.data-protection.isf.ibm.com $BS fusion-config dp.isf.ibm.com/cleanup-status=complete
         oc -n "$ISF_NS" delete backups.data-protection.isf.ibm.com  $BS
fi

print_heading "Remove any existing restore CRs"
RS=$(oc -n "$ISF_NS" get restore.data-protection.isf.ibm.com  -l dp.isf.ibm.com/provider-name=isf-backup-restore -o custom-columns="NAME:metadata.name" --no-headers)
[ -n "$RS" ] && oc -n "$ISF_NS" delete restore.data-protection.isf.ibm.com  $RS

print_heading "Remove any existing backuplocations CRs"
BSL=$(oc -n "$ISF_NS" get backupstoragelocation.data-protection.isf.ibm.com -o custom-columns="NAME:metadata.name,PROVIDER:spec.provider" --no-headers | grep 'isf-backup-restore$' | cut -f1 -d " ")
[ -n "$BSL" ] && oc -n "$ISF_NS" delete --timeout=60s backupstoragelocation.data-protection.isf.ibm.com $BSL

print_heading "Delete any existing guardiancopybackups CRs"
oc delete guardiancopybackups -n "${NAMESPACE}" --all
print_heading "Delete any existing guardiancopyrestores CRs"
oc delete guardiancopyrestores -n "${NAMESPACE}" --all
print_heading "Delete any existing guardianmongoes CRs"
oc delete guardianmongoes -n "${NAMESPACE}" --all

## err_exit "REMOVE THIS"

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
               oc delete -n "$ISF_NS" fusionserviceinstance "$FBRI"
           fi
   done
}

remove_fsi

# Subscriptions for dependent operators
SUBSCRIPTION_NAMES=$(oc -n "${NAMESPACE}" get subs --no-headers | cut -d" " -f1)

print_heading "Remove any subscriptions, csvs and operatorgroups for dependent operators in namespace ${NAMESPACE}"
# Delete the subscription and instance
for SUBSCRIPTION_NAME in ${SUBSCRIPTION_NAMES[@]}
do
    csvName=$(oc get subscription "${SUBSCRIPTION_NAME}" -n "${NAMESPACE}" -o yaml | grep currentCSV | awk -F' ' '{print $2}')
    echo "===== Deleting subscription $SUBSCRIPTION_NAME"
    oc delete subscription "${SUBSCRIPTION_NAME}" -n "${NAMESPACE}"
    echo "===== Deleting csv ${csvName}"
    oc delete clusterserviceversion ${csvName} -n "${NAMESPACE}"
done

# delete the operatorgroup created during install
print_heading "Delete any existing operatorgroups"
oc delete operatorgroup -n "${NAMESPACE}" --all

print_heading "Delete Redis"
oc delete redis redis -n "${NAMESPACE}" --timeout=60s
if oc get redis redis -n "${NAMESPACE}" >/dev/null 2>&1; then
   oc patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' redis redis -n "${NAMESPACE}"
   oc delete redis redis -n "${NAMESPACE}"
fi

if oc get redis redis -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Redis instance still exists. You may need to deleted it manually."
fi

print_heading "Namespace removal started at $(date)"
echo

if ! oc get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Namespace ${NAMESPACE} was not found"
  else
    echo "oc delete namespace ${NAMESPACE}"
    oc delete namespace "${NAMESPACE}"
fi
oc delete validatingwebhookconfigurations -l olm.owner.namespace="${NAMESPACE}" --ignore-not-found
oc delete mutatingwebhookconfigurations -l olm.owner.namespace="${NAMESPACE}" --ignore-not-found

remove_fsi

INSTS=$(oc get dataprotectionserver -A -o name 2> /dev/null)
INSTA=$(oc get dataprotectionagent  -A -o name 2> /dev/null)
[ -n "$INSTA" ] && INSTS="$INSTS $INSTA"
if [ -z "$INSTS" ] 
 then
     echo "==== Deleting cluster role bindings and crds"
     ROLES=$(oc get clusterrole --ignore-not-found | grep -iE "guardian|ibm-backup-restore|dataprotectionagent|dataprotectionserver" | cut -d" " -f1)
     [ -n "$ROLES" ] && oc delete clusterrole $ROLES
     BINDINGS=$(oc get clusterrolebinding --ignore-not-found | grep -iE "guardian|ibm-backup-restore|dataprotectionagent|dataprotectionserver" | cut -d" " -f1)
     [ -n "$BINDINGS" ] && oc delete clusterrolebinding $BINDINGS
     CRDS=$(oc get crd -o name | grep -E 'guardian.*ibm.com|dataprotection.*.ibm.com')
     [ -n "$CRDS" ]  && oc delete $CRDS
 else
   echo "==== Other copies of Backup & Restore exist in following namespaces"
   oc get dataprotectionagent,dataprotectionserver -A --no-headers| cut -d" " -f1
fi
UNINSTALL_ENDED="$(date +%s)"

print_heading "Overall uninstall time:  $[ ${UNINSTALL_ENDED} - ${UNINSTALL_STARTED} ] seconds"

echo "Done"
