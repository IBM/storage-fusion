#!/bin/bash
# Run this script before installing Backup & Restore.
# If you already tried installing Backup & Restore and it has failed due to OADP not installing correctly:
#   1. Run this script.
#   2. Uninstall/clean using https://github.com/IBM/storage-fusion/blob/master/backup-restore/uninstall/uninstall-backup-restore.sh
# After running this script, Backup & restore should install fine.
# **** Do not forget to run last step to patch spectrum Fusion after installing Backup & restore ****
LOG=/tmp/br-pre-install-patch281_$$_log.txt
exec &> >(tee -a $LOG)
echo "Logging output in $LOG"

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2> /dev/null)
ISF_CR=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.name --no-headers)
ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)

if [ -z "$ISF_CR" ]
  then
        echo "ERROR: No Successful Fusion installation found. Exiting" 
        exit 1
fi

[ -n "$BR_NS" ] && HUB=true
if [ -n "$HUB" ]
 then
   echo " This is hub"
 else
   BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace 2> /dev/null)
   if [ -n "$BR_NS" ]
     then
        echo "This is spoke" 
     else
        echo "No Successful Backup & Restore installation found." 
   fi
fi

if [ -n "$BR_NS" ]
 then
   DPA_STATUS="$(oc -n "$BR_NS" get dataprotectionagents -o custom-columns=:status.installStatus.status --no-headers)"
   if [ "Completed" == "$DPA_STATUS" ]
     then
       echo "Agent install is already complete, no pre install patch needed"
       exit 0
   fi
fi

echo "Patching spectrumfusion $ISF_CR CR"
oc -n "$ISF_NS" patch -p '{"spec":{"configuration":{"services":{"skipOnBoardingServices":true}}}}' --type=merge spectrumfusion "$ISF_CR"


echo "Patching fusionservicedefinitions CRs"
oc -n "$ISF_NS" patch --type json --patch='[ { "op": "remove", "path": "/spec/upgradeConfiguration" } ]' fusionservicedefinition ibm-backup-restore-service
oc -n "$ISF_NS" patch --type json --patch='[ { "op": "remove", "path": "/spec/upgradeConfiguration" } ]' fusionservicedefinition ibm-backup-restore-agent-service

echo "Restarting isf-prereq-operator"
oc -n "$ISF_NS" rollout restart deployment isf-prereq-operator-controller-manager
oc -n "$ISF_NS" rollout status deployment isf-prereq-operator-controller-manager
echo ""
echo ' **** IMPORTANT: Execute following (Only) after Backup & Restore installation is complete ****'
echo oc -n $ISF_NS patch --type json --patch=\'[ { "op": "remove", "path": "/spec/configuration/services/skipOnBoardingServices" } ]\' spectrumfusion "$ISF_CR"

echo ""
echo '===> Install Backup Restore now and come back here when it is done'
while [ "Completed" != "$(oc -n "$BR_NS" get dataprotectionagents -o custom-columns=:status.installStatus.status --no-headers 2> /dev/null)" ]
 do
   sleep 2
done
echo Running oc -n $ISF_NS patch --type json --patch=\'[ { "op": "remove", "path": "/spec/configuration/services/skipOnBoardingServices" } ]\' spectrumfusion "$ISF_CR"
oc -n $ISF_NS patch --type json --patch='[ { "op": "remove", "path": "/spec/configuration/services/skipOnBoardingServices" } ]' spectrumfusion "$ISF_CR"
