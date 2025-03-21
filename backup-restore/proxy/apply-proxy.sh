#!/bin/bash
# Run this script on hub and spoke clusters to apply cluster-wide proxy settings.

usage() {
  echo "Usage: $0 <proxy-url>"
}

check_cmd ()
{
   (type $1 > /dev/null) || echo "$1 command not found, install $1 command to apply patch"
}

check_cmd oc
oc whoami > /dev/null || err_exit "Not logged in to your cluster"

if [ "$#" -ne 1 ]; then
    usage
    exit 0
fi
PROXY_URL=$1

mkdir -p /tmp/br-apply-proxy
if [ "$?" -eq 0 ]
then DIR=/tmp/br-apply-proxy
else DIR=/tmp
fi
LOG=$DIR/apply-proxy_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of apply-proxy.sh script to $LOG"

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
if [ -n "$BR_NS" ]; then
    HUB=true
else
    BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
fi

if [ -z "$BR_NS" ]; then 
    echo "ERROR: No B&R installation found. Exiting."
    exit 1
fi

if [ -n "$HUB" ]; then
    if (oc get deployment -n $BR_NS backup-location-deployment -o yaml > $DIR/backup-location-deployment.save.yaml); then
        echo "Applying proxy settings to backup-location-deployment..."
        oc set env deployment backup-location-deployment -n $BR_NS http_proxy=$PROXY_URL
        oc set env deployment backup-location-deployment -n $BR_NS https_proxy=$PROXY_URL
    else
        echo "ERROR: Failed to save original backup-location-deployment. Skipped updates."
    fi
fi    

if (oc get dpa velero -n $BR_NS -o yaml > $DIR/dpa-velero.save.yaml); then
    echo "Applying proxy settings to DataProtectionApplication velero resource..."
    oc patch dpa velero -n $BR_NS --type=json -p "[{\"op\": \"add\", \"path\": \"/spec/configuration/nodeAgent/podConfig/env\", \"value\":[{\"name\":\"http_proxy\",\"value\":\"$PROXY_URL\"},{\"name\":\"https_proxy\",\"value\":\"$PROXY_URL\"}]}]"
    oc patch dpa velero -n $BR_NS --type=json -p "[{\"op\": \"add\", \"path\": \"/spec/configuration/velero/podConfig/env\", \"value\":[{\"name\":\"http_proxy\",\"value\":\"$PROXY_URL\"},{\"name\":\"https_proxy\",\"value\":\"$PROXY_URL\"}]}]"
else
    echo "ERROR: Failed to save original DataProtectionApplication velero resource. Skipped updates."
fi

if (oc get cm guardian-configmap -n $BR_NS -o yaml > $DIR/guardian-configmap.save.yaml); then
    echo "Applying proxy settings to datamover..."
    oc patch cm guardian-configmap -n $BR_NS --type=json -p "[{\"op\": \"add\", \"path\": \"/data/datamoverJobEnvVars\", \"value\": \"http_proxy=$PROXY_URL;https_proxy=$PROXY_URL\"}]"
else
    echo "ERROR: Failed to save original guardian-configmap. Skipped updates."
fi

