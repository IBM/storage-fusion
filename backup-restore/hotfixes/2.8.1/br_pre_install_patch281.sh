#!/bin/bash
# Run this script before installing Backup & Restore.
# If you already tried installing Backup & Restore and it has failed, uninstall it using
#   https://github.com/IBM/storage-fusion/blob/master/backup-restore/uninstall/uninstall-backup-restore.sh
# Then run this script.
# After running this script, Backup & restore should install fine.
# 
LOG=/tmp/br_pre_install_patch281_$$_log.txt
exec &> >(tee -a $LOG)

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace)
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
   BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace)
   if [ -n "$BR_NS" ]
     then
        echo "This is spoke" 
     else
        echo "No Successful Backup & Restore installation found." 
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
echo "IMPORTANT: Execute following (Only) after Backup & Restore installation is complete"
echo oc -n $ISF_NS patch --type json --patch=\'[ { "op": "remove", "path": "/spec/configuration/services/skipOnBoardingServices" } ]\' spectrumfusion "$ISF_CR"
