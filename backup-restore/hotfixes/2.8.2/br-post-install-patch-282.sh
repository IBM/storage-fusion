#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.8.2 release.
# Refer to https://www.ibm.com/support/pages/node/7178519 for additional information.
# Version 01-23-2025

mkdir -p /tmp/br-post-install-patch-282
if [ "$?" -eq 0 ]
then DIR=/tmp/br-post-install-patch-282
else DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-282_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-282.sh script to $LOG"

ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)

if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
if [ -n "$BR_NS" ]
 then
 HUB=true
else
   BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
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
if [[ $VERSION != 2.8.2* ]]
 then
    echo "ERROR: This patch applies to B&R version 2.8.2 only. You have $VERSION"
    exit 1
fi

if [ -n "$HUB" ]
  then
    echo "Apply patches to hub..."

   if (oc get deployment -n $BR_NS job-manager -o yaml > $DIR/job-manager-deployment.save.yaml)
      then
        echo "Patching job-manager-deployment image..."
        oc patch deployment job-manager -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"job-manager-container","image":"cp.icr.io/cp/fbr/guardian-job-manager@sha256:5a99629999105bdc83862f4bf37842b8004dfb3db9eea20b07ab7e39e95c8edc"}]}}}}'
    else
        echo "ERROR: Failed to save original job-manager-deployment. Skipped updates."
    fi

    if (oc get deployment -n $BR_NS backup-location-deployment -o yaml > $DIR/backup-location-deployment.save.yaml)
      then
        echo "Patching backup-location-deployment image..."
        oc patch deployment backup-location-deployment -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backup-location-container","image":"cp.icr.io/cp/fbr/guardian-backup-location@sha256:c737450b02a9f415a4c4eea6cc6a67ce0723a8bf5c08ce41469c847c5b598e16"}]}}}}'
    else
        echo "ERROR: Failed to save original backup-location-deployment. Skipped updates."
    fi

    if (oc get deployment -n $BR_NS backuppolicy-deployment -o yaml > $DIR/backuppolicy-deployment.save.yaml)
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
        oc patch deployment backuppolicy-deployment -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backuppolicy-container","image":"cp.icr.io/cp/fbr/guardian-backup-policy@sha256:32a4ffba0dd2da241bd128ab694fd6fc34a7087aab053a29658e3e0f69ef11aa"}]}}}}'
    else
        echo "ERROR: Failed to save original backuppolicy-deployment. Skipped updates."
    fi

    if (oc get deployment -n $BR_NS backup-service -o yaml > $DIR/backup-service-deployment.save.yaml)
      then
        echo "Patching backup-service image..."
        oc patch deployment backup-service -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backup-service","image":"cp.icr.io/cp/fbr/guardian-backup-service@sha256:742367383260fa25fdf1a7cf94a78267361519720869bb6cceac7476b5d5fab3"}]}}}}'
    else
        echo "ERROR: Failed to save original backup-service deployment. Skipped updates."
    fi

    if (oc get recipes.spp-data-protection.isf.ibm.com fusion-control-plane -n $ISF_NS -o yaml > $DIR/fusion-control-plane-recipe.save.yaml)
      then
        echo "Patching fusion-control-plane recipe..."
        oc patch recipes.spp-data-protection.isf.ibm.com fusion-control-plane -n $ISF_NS --type=merge -p '{"spec":{"hooks":[{"name":"fbr-hooks","nameSelector":"transaction-manager.*","namespace":"${FBR_NAMESPACE}","onError":"fail","ops":[{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/ctl-plane.pyc\",\"backup\",\"uid=${BACKUP_ID}\"]","container":"transaction-manager","name":"export-backup-inventory"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/ctl-plane.pyc\",\"restore\",\"uid=${BACKUP_ID}\"]","container":"transaction-manager","name":"restore-backup-inventory"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/ctl-plane.pyc\",\"deleteCRs\"]","container":"transaction-manager","name":"deleteCRs"}],"selectResource":"pod","singlePodOnly":true,"timeout":28800,"type":"exec"},{"name":"isf-dp-operator-hook","nameSelector":"transaction-manager.*","namespace":"${FBR_NAMESPACE}","onError":"fail","ops":[{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/patch-isd-dp-cm.pyc\",\"${PARENT_NAMESPACE}\",\"isf-data-protection-config\",\"DisableWebhook\"]","container":"transaction-manager","name":"disable-webhook"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/patch-isd-dp-cm.pyc\",\"${PARENT_NAMESPACE}\",\"isf-data-protection-config\",\"Recover\"]","container":"transaction-manager","name":"quiesce-isf-dp-controller"},{"command":"[\"/usr/src/app/code/.venv/bin/python3\",\"/usr/src/app/code/patch-isd-dp-cm.pyc\",\"${PARENT_NAMESPACE}\",\"isf-data-protection-config\",\"Normal\"]","container":"transaction-manager","name":"unquiesce-isf-dp-controller"}],"selectResource":"pod","singlePodOnly":true,"type":"exec"}]}}'
    else
        echo "ERROR: Failed to save original fusion-control-plane recipe. Skipped updates."
    fi
fi

if (oc get deployment -n $BR_NS transaction-manager -o yaml > $DIR/transaction-manager-deployment.save.yaml)
  then
    echo "Patching transaction-manager image..."
    oc patch deployment/transaction-manager -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"transaction-manager","image":"cp.icr.io/cp/fbr/guardian-transaction-manager@sha256:0ae46fc2f6e744f79f81005579f4dcb7c9981b201f239433bf1e132f9c89c8cd"}]}}}}'
else
    echo "ERROR: Failed to save original transaction-manager deployment. Skipped updates."
fi


echo "Saving old guardian-minio image to old-minio-image.txt"
oc get statefulset guardian-minio -n $BR_NS -o jsonpath="{.spec.template.spec.containers[0].image}" > $DIR/old-minio-image.txt
echo "Updating statefulset/guardian-minio image to quay.io/minio/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3"
oc set image statefulset/guardian-minio -n $BR_NS minio=quay.io/minio/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3
oc delete pod guardian-minio-0 -n $BR_NS

if (oc -n "$BR_NS" get csv guardian-dm-operator.v2.8.2 -o yaml > $DIR/guardian-dm-operator.v2.8.2-original.yaml)
   then
      echo "Saved original configuration of guardian-dm-operator to $DIR/guardian-dm-operator.v2.8.2-original.yaml."
   else
      echo "ERROR: Failed to save original guardian-dm-operator.v2.8.2 csv. Skipped Patch."
fi

if (oc get configmap -n "$BR_NS" guardian-dm-image-config -o yaml > $DIR/guardian-dm-image-config-original.yaml)
 then
    echo "Scaling down guardian-dm-controller-manager deployment..."
    oc scale deployment guardian-dm-controller-manager -n "$BR_NS" --replicas=0
    oc set data -n "$BR_NS" cm/guardian-dm-image-config DM_IMAGE=icr.io/cpopen/guardian-datamover@sha256:8617945fbbcf13c8ec15eccf85a18ed3aecd7432cff8380a06bc9ce3ab5d406b
    oc patch csv -n $BR_NS guardian-dm-operator.v2.8.2 --type='json' -p='[{"op":"replace", "path":"/spec/install/spec/deployments/0/spec/template/spec/containers/1/image", "value":"icr.io/cpopen/guardian-dm-operator@sha256:ef5095ae54a7140e51b17f02b0b591fc0736e28cca66d9f69199df997b74eb98"}]'
    echo "Scaling up guardian-dm-controller-manager deployment..."
    oc scale deployment guardian-dm-controller-manager -n "$BR_NS" --replicas=1
else
    echo "ERROR: Failed to save original configmap guardian-dm-image-config. skipped updates"
fi

echo "Please verify that these pods in $BR_NS namespace have successfully restarted after hotfix update:"
echo "     guardian-minio"
echo "     transaction-manager"
if [ -n "$HUB" ]
  then
    echo "     backup-location-deployment"
    echo "     backuppolicy-deployment"
    echo "     backup-service"
    echo "     guardian-dm-controller-manager"
    echo "     job-manager"
    echo "                                   "
    echo "Previous version of this script incorrectly patched job-manager by adding a second container named ‘job-manager’ instead of updating image of container named ‘job-manager-container'"
    echo " Check number of containers in job-manager pod: oc get pod -n ibm-backup-restore | grep job-manager"
    echo "      job-manager-557fdf847f-cpqpw   2/2     Running"
    echo "If it has two containers, edit job-manager deployment and remove this sub-section under spec.template.spec.containers"
    echo "- name: job-manager" 
    echo "  image: '...'"
    echo "  resources: {}"
    echo "  terminationMessagePath: '...'"
    echo "  imagePullPolicy: '...' " 
   
fi
