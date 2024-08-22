#!/bin/bash
# Run this script to update default datamover pod resource limit on spoke cluster.

LOG=/tmp/applypatch-281_$$_log.txt
exec &> >(tee -a $LOG)
echo "Logging output in $LOG"

# Check for Backup & Restore namespace
BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2> /dev/null)
ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)

if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

if [ -n "$BR_NS" ]; then
    echo "This is Hub. No need to apply the script."
    exit 0
    
else
    echo "This is spoke. "
    echo "Saving original guardian-configmap yaml."

    BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace)
    
    if oc get configmap -n "$BR_NS" guardian-configmap -o yaml > guardian-configmap-original.yaml; then
        echo "Original guardian-configmap saved successfully."
    else
        echo "ERROR: Failed to save original guardian-configmap. Exiting."
        exit 1
    fi
    
    echo "Updating default datamover pod resource settings..."
    
    if oc set data -n "$BR_NS" cm/guardian-configmap datamoverJobpodMemoryLimit='15000Mi' \
                      datamoverJobpodMemoryRequest='4000Mi' \
                      datamoverJobpodMemoryRequestRes='4000Mi'; then
        echo "Resource settings updated finished."
    else
        echo "ERROR: Failed to update memory settings. Exiting."
        exit 1
    fi
fi
