#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.8.1 release.

LOG=/tmp/br-post-install-patch281_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch281.sh script to $LOG"

# Check for Backup & Restore namespace
#BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2> /dev/null)
ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)

if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace)
if [ -n "$BR_NS" ]
 then
 HUB=true
else
   BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace)
fi

if [ -z "$BR_NS" ] 
 then
    echo "ERROR: No B&R installation found. Exiting."
    exit 1
fi
AGENTCSV=$(oc -n "$BR_NS" get csv -o name | grep ibm-dataprotectionagent)
VERSION=$(oc -n "$BR_NS" get "$AGENTCSV" -o custom-columns=:spec.version --no-headers)
if [ -z "$VERSION" ] 
 then
    echo "ERROR: Could not get B&R version. Exiting"
    exit 1
fi
if [[ $VERSION != 2.8.1* ]]
 then
    echo "ERROR: This patch appiles to B&R version 2.8.1 only. You have $VERSION"
    exit 1
fi

if (oc -n "$BR_NS" get csv ibm-dataprotectionagent.v2.8.1 -o yaml > ibm-dataprotectionagent.v2.8.1-csv-original.yaml)
   then
      echo "Saved original configuration and images to ibm-dataprotectionagent.v2.8.1-csv-original.yaml. Use it to revert changes made by this patch."
      oc -n "$BR_NS" annotate --overwrite=true clusterserviceversion ibm-dataprotectionagent.v2.8.1 operatorframework.io/properties='{"properties":[{"type":"olm.gvk","value":{"group":"dataprotectionagent.idp.ibm.com","kind":"DataProtectionAgent","version":"v1"}},{"type":"olm.package","value":{"packageName":"ibm-dataprotectionagent","version":"2.8.1"}},{"type":"olm.package.required","value":{"packageName":"guardian-dm-operator","versionRange":"\u003e=2.8.0-1"}},{"type":"olm.package.required","value":{"packageName":"redhat-oadp-operator","versionRange":"\u003e=1.1.0 \u003c1.5.0"}},{"type":"olm.package.required","value":{"packageName":"guardian-dm-operator","versionRange":"\u003e=2.8.0-1"}},{"type":"olm.package.required","value":{"packageName":"redhat-oadp-operator","versionRange":"\u003e=1.1.0 \u003c1.5.0"}}]}'
  else
    echo "ERROR: Failed to save original ibm-dataprotectionagent.v2.8.1 csv. Skipped Patch."
fi

if (oc -n "$BR_NS" get csv ibm-backup-restore guardian-dm-operator.v2.8.1 -o yaml > ibm-backup-restore guardian-dm-operator.v2.8.1-original.yaml)
   then
      echo "Saved original configuration and images to guardian-dm-operator.v2.8.1-original.yaml. Use it to revert changes made by this patch."
   else
      echo "ERROR: Failed to save original guardian-dm-operator.v2.8.1 csv. Skipped Patch."
fi
    
if (oc get configmap -n "$BR_NS" guardian-configmap -o yaml > guardian-configmap-original.yaml)
 then
    oc set data -n "$BR_NS" cm/guardian-configmap datamoverJobpodMemoryLimit='15000Mi' \
                  datamoverJobpodMemoryRequest='4000Mi' \
                  datamoverJobpodMemoryRequestRes='4000Mi'
else
    echo "ERROR: Failed to save original guardian-configmap. skipped updates"
fi

if (oc get configmap -n "$BR_NS" guardian-dm-image-config -o yaml > guardian-dm-image-config-original.yaml)
 then
    echo "Scaling down guardian-dm-controller-manager deployment..."
    oc scale deployment guardian-dm-controller-manager -n "$BR_NS" --replicas=0
    oc set data -n "$BR_NS" cm/guardian-dm-image-config DM_IMAGE=cp.icr.io/cpopen/guardian-datamover@sha256:c875806495327dc719337584c608ba6bb5a0902ee1e89990a6f1b47666655bad
    oc patch csv -n $BR_NS guardian-dm-operator.v2.8.1 --type='json' -p='[{"op":"replace", "path":"/spec/install/spec/deployments/0/spec/template/spec/containers/1/image", "value":"cp.icr.io/cpopen/guardian-dm-operator@sha256:a879a312b153e4eeb7eb334a39f753e4e7c331bce8e176d5e1d20159e32a55a3"}]'
    echo "Scaling up guardian-dm-controller-manager deployment..."
    oc scale deployment guardian-dm-controller-manager -n "$BR_NS" --replicas=1
else
    echo "ERROR: Failed to save original configmap guardian-dm-image-config. skipped updates"
fi

echo "Patching dbr-controller deployment..."
echo "Scaling down dbr-controller deployment..."
oc scale deployment dbr-controller -n "$BR_NS" --replicas=0
oc patch deployment/dbr-controller -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"dbr-controller","image":"cp.icr.io/cp/fbr/guardian-transaction-manager@sha256:be77eecb921b2e905e8ea5e0f6ca9b5b6bec76dc4b6cdde223e54e6c42840e97"}]}}}}'
oc set resources deployment dbr-controller  -n "$BR_NS" --limits memory=3Gi
echo "Scaling up dbr-controller deployment..."
oc scale deployment dbr-controller -n "$BR_NS" --replicas=1
echo "Patching transaction-manager deployment..."
oc patch deployment/transaction-manager -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"transaction-manager","image":"cp.icr.io/cp/fbr/guardian-transaction-manager@sha256:be77eecb921b2e905e8ea5e0f6ca9b5b6bec76dc4b6cdde223e54e6c42840e97"}]}}}}'

SKIP_MINIO="true"
if [[ -z "$SKIP_MINIO" ]];
  then
    echo "Saving old guardian-minio image to old-minio-image.txt"
    oc get statefulset guardian-minio -n $BR_NS -o jsonpath="{.spec.template.spec.containers[0].image}" >> old-minio-image.txt  
    echo "Updating statefulset/guardian-minio image to quay.io/minio/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3"
    oc set image statefulset/guardian-minio -n $BR_NS minio=quay.io/minio/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3
fi

if [ -n "$HUB" ]
  then
    echo "Apply patches to hub..."

    if (oc get deployment -n $BR_NS backuppolicy-deployment -o yaml > backuppolicy-deployment.save.yaml)
      then
        echo "Creating backup-policy service account..."
        oc create sa backup-policy -n $BR_NS

        echo "Creating backup-policy-role cluster role..."
        oc create clusterrole backup-policy-role --verb=get --resource=configmaps

        echo "Creating backup-policy-rolebinding cluster role binding..."
        oc adm policy add-cluster-role-to-user backup-policy-role -z backup-policy  -n $BR_NS --rolebinding-name=backup-policy-rolebinding

        echo "Patching backuppolicy-deployment service account..."
        oc patch deployment backuppolicy-deployment -n $BR_NS -p '{"spec":{"template":{"spec":{"serviceAccountName":"backup-policy"}}}}'

        echo "Patching backuppolicy-deployment image..."
        oc patch deployment backuppolicy-deployment -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backuppolicy-container","image":"cp.icr.io/cp/fbr/guardian-backup-policy@sha256:f7bcf21292258b1e2299a58bccc53886548fd05d5ab714756f4e364195085a5b"}]}}}}'
    else
        echo "ERROR: Failed to save original backuppolicy-deployment. Skipped updates."
    fi

    if (oc get deployment -n $BR_NS backup-location-deployment -o yaml > backup-location-deployment.save.yaml)
      then
        echo "Patching backup-location-deployment image..."
        oc patch deployment backup-location-deployment -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backup-location-container","image":"cp.icr.io/cp/fbr/guardian-backup-location@sha256:9e9ff3fb6d3c56b1932ee553b374b093adbf037a55a70ae83b359f262029e23e"}]}}}}'
    else
        echo "ERROR: Failed to save original backup-location-deployment. Skipped updates."
    fi

    if (oc get deployment -n $BR_NS backup-service -o yaml > backup-service-deployment.save.yaml)
      then
        echo "Patching backup-service image..."
        oc patch deployment backup-service -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backup-service","image":"cp.icr.io/cp/fbr/guardian-backup-service@sha256:1bf6b6b093499c14c27fd819637b992999beb0eb5e9cc9dc6feac154b8c7dbda"}]}}}}'
    else
        echo "ERROR: Failed to save original backup-service deployment. Skipped updates."
    fi

    if (oc get recipes.spp-data-protection.isf.ibm.com fusion-control-plane -n $ISF_NS -o yaml > fusion-control-plane-recipe.save.yaml)
      then
        echo "Patching fusion-control-plane recipe..."
        oc patch recipes.spp-data-protection.isf.ibm.com fusion-control-plane -n $ISF_NS --type=merge -p '{"spec":{"hooks":[{"name":"fbr-hooks","nameSelector":"transaction-manager.*","namespace":"${FBR_NAMESPACE}","onError":"fail","ops":[{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/ctl-plane.pyc\",\"backup\",\"uid=${BACKUP_ID}\"]","container":"transaction-manager","name":"export-backup-inventory"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/ctl-plane.pyc\",\"restore\",\"uid=${BACKUP_ID}\"]","container":"transaction-manager","name":"restore-backup-inventory"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/ctl-plane.pyc\",\"deleteCRs\"]","container":"transaction-manager","name":"deleteCRs"}],"selectResource":"pod","singlePodOnly":true,"timeout":28800,"type":"exec"},{"name":"isf-dp-operator-hook","nameSelector":"transaction-manager.*","namespace":"${FBR_NAMESPACE}","onError":"fail","ops":[{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/patch-isd-dp-cm.pyc\",\"${PARENT_NAMESPACE}\",\"isf-data-protection-config\",\"DisableWebhook\"]","container":"transaction-manager","name":"disable-webhook"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/patch-isd-dp-cm.pyc\",\"${PARENT_NAMESPACE}\",\"isf-data-protection-config\",\"Recover\"]","container":"transaction-manager","name":"quiesce-isf-dp-controller"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/patch-isd-dp-cm.pyc\",\"${PARENT_NAMESPACE}\",\"isf-data-protection-config\",\"Normal\"]","container":"transaction-manager","name":"unquiesce-isf-dp-controller"}],"selectResource":"pod","singlePodOnly":true,"type":"exec"}]}}'
    else
        echo "ERROR: Failed to save original fusion-control-plane recipe. Skipped updates."
    fi
fi

echo "Please verify that these pods in $BR_NS namespace have successfully restarted after hotfix update:"
echo "     guardian-dm-controller-manager"
echo "     dbr-controller"
echo "     transaction-manager"
if [ -n "$HUB" ]
  then
    echo "     backup-location-deployment"
    echo "     backuppolicy-deployment"
    echo "     backup-service deployment"
fi



