#!/bin/bash
# Run this script to update default datamover pod resource limit on spoke cluster.

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


