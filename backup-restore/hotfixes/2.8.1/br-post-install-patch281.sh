#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.8.1 release.

LOG=/tmp/br-post-install-patch281_$$_log.txt
exec &> >(tee -a $LOG)
echo "Logging output in $LOG"

# Check for Backup & Restore namespace
#BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2> /dev/null)
ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)

if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace)

if (oc -n "$BR_NS" get csv ibm-dataprotectionagent.v2.8.1 -o yaml > ibm-dataprotectionagent.v2.8.1-csv-original.yaml)
   then
      echo "Saved original configuration and images to ibm-dataprotectionagent.v2.8.1-csv-original.yaml. Use it to revert changes made by this patch."
      oc -n "$BR_NS" annotate --overwrite=true clusterserviceversion ibm-dataprotectionagent.v2.8.1 operatorframework.io/properties='{"properties":[{"type":"olm.gvk","value":{"group":"dataprotectionagent.idp.ibm.com","kind":"DataProtectionAgent","version":"v1"}},{"type":"olm.package","value":{"packageName":"ibm-dataprotectionagent","version":"2.8.1"}},{"type":"olm.package.required","value":{"packageName":"guardian-dm-operator","versionRange":"\u003e=2.8.0-1"}},{"type":"olm.package.required","value":{"packageName":"redhat-oadp-operator","versionRange":"\u003e=1.1.0 \u003c1.5.0"}},{"type":"olm.package.required","value":{"packageName":"guardian-dm-operator","versionRange":"\u003e=2.8.0-1"}},{"type":"olm.package.required","value":{"packageName":"redhat-oadp-operator","versionRange":"\u003e=1.1.0 \u003c1.5.0"}}]}'
  else
    echo "ERROR: Failed to save original ibm-dataprotectionagent.v2.8.1 csv. Skipped Patch."
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
    oc set data -n "$BR_NS" cm/guardian-dm-image-config DM_IMAGE=cp.icr.io/cp/fbr/guardian-datamover@sha256:b051b665b42ce81ab543558b8f7c2ddf36dfc7a95df887ef8583da2912849c5e
    echo "Scaling up guardian-dm-controller-manager deployment..."
    oc scale deployment guardian-dm-controller-manager -n "$BR_NS" --replicas=1
else
    echo "ERROR: Failed to save original configmap guardian-dm-image-config. skipped updates"
fi

echo "Patching dbr-controller deployment..."
echo "Scaling down dbr-controller deployment..."
oc scale deployment dbr-controller -n "$BR_NS" --replicas=0
oc patch deployment/dbr-controller -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"dbr-controller","image":"cp.icr.io/cp/fbr/guardian-transaction-manager@sha256:656433641ceda21ee45469500b2b7040983c48d1e3ee50f809be5ab6f3ab527d"}]}}}}'
oc set resources deployment dbr-controller  -n "$BR_NS" --limits memory=3Gi
echo "Scaling up dbr-controller deployment..."
oc scale deployment dbr-controller -n "$BR_NS" --replicas=1
echo "Patching transaction-manager deployment..."
oc patch deployment/transaction-manager -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"transaction-manager","image":"cp.icr.io/cp/fbr/guardian-transaction-manager@sha256:656433641ceda21ee45469500b2b7040983c48d1e3ee50f809be5ab6f3ab527d"}]}}}}'

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
    oc patch deployment backup-location-deployment -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backup-location-container","image":"cp.icr.io/cp/fbr/guardian-backup-location@sha256:b0e2cb55082192780bd6ad02fe19c71d478b213817c64689562869256110af3b"}]}}}}'
else
    echo "ERROR: Failed to save original backup-location-deployment. Skipped updates."
fi
echo "Please verify that these pods in $BR_NS namespace have successfully restarted after hotfix update:"
echo "     guardian-dm-controller-manager"
echo "     dbr-controller"
echo "     transaction-manager"
echo "     backup-location-deployment"
echo "     backuppolicy-deployment"

