#!/bin/bash
# Run this script on hub and spoke clusters to apply cluster-wide proxy settings.

mkdir -p /tmp/br-apply-proxy
if [ "$?" -eq 0 ]
then DIR=/tmp/br-apply-proxy
else DIR=/tmp
fi
LOG=$DIR/apply-proxy_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of apply-proxy.sh script to $LOG"

usage() {
    echo "Usage: $0 <proxy-url>"
}

err_exit()
{
    echo "$@" >&2
    exit 1
}

check_cmd ()
{
   (type $1 > /dev/null) || err_exit "$1 command not found, install $1 command to apply patch"
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi
PROXY_URL=$1

check_cmd oc
oc whoami > /dev/null || err_exit "Not logged in to your cluster"

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

AGENTCSV=$(oc -n "$BR_NS" get csv -o name | grep ibm-dataprotectionagent)
VERSION=$(oc -n "$BR_NS" get "$AGENTCSV" -o custom-columns=:spec.version --no-headers)
if [ -z "$VERSION" ] ; then
    echo "ERROR: Could not get B&R version."
    exit 1
elif [[ $VERSION == 2.7.* || $VERSION == 2.8.* ]]; then
    echo "This script works for B&R version 2.9 and above, you have $VERSION."
    exit 1
fi

if [ -n "$HUB" ]; then
    if (oc get deployment -n $BR_NS backup-location-deployment -o yaml > $DIR/backup-location-deployment.save.yaml); then
        echo "Applying proxy settings to backup-location-deployment..."
        oc set env deployment backup-location-deployment -n $BR_NS http_proxy="$PROXY_URL" https_proxy="$PROXY_URL"
    else
        echo "ERROR: Failed to save original backup-location-deployment. Skipped updates."
    fi
fi    

if (oc get deployment transaction-manager -n $BR_NS -o yaml > $DIR/transaction-manager-deployment.save.yaml); then
    echo "Applying proxy settings to transaction-manager..."
  oc set env deployment transaction-manager -n $BR_NS http_proxy="$PROXY_URL" https_proxy="$PROXY_URL"
else
    echo "ERROR: Failed to save original transaction-manager deployment. Skipped updates."
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

