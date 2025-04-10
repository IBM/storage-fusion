#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.9.1 release.
# Refer to https://www.ibm.com/support/pages/node/7230021 for additional information.
# Version 04-10-2025

patch_usage() {
  echo "Usage: $0 (-hci |-sds | -help)"
  echo "Options:"
  echo "  -hci   Apply patch on HCI"
  echo "  -sds   Apply patch on SDS"
  echo "  -help  Display usage"
}

PATCH=
if [[ "$#" -ne 1 ]]; then
    patch_usage
    exit 0
elif [[ "$1" == "-hci" ]]; then
    PATCH="HCI"
elif [[ "$1" == "-sds" ]]; then
    PATCH="SDS"
elif [[ "$1" == "-help" ]]; then
    patch_usage
    exit 0
else 
    echo "Unknown option: $1"
    patch_usage
    exit 1
fi
EXPECTED_VERSION=2.9.1

mkdir -p /tmp/br-post-install-patch-291
if [ "$?" -eq 0 ]
then DIR=/tmp/br-post-install-patch-291
else DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-291_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-291.sh script to $LOG"

check_cmd ()
{
   (type $1 > /dev/null) || echo "$1 command not found, install jq command to apply patch"
}
check_cmd oc
check_cmd jq
oc whoami > /dev/null || err_exit "Not logged in to your cluster"

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
    echo "ERROR: Could not get B&R version. Skipped updates"
    exit 0
elif [[ $VERSION != $EXPECTED_VERSION* ]]; then
    echo "This patch applies to B&R version $EXPECTED_VERSION only, you have $VERSION. Skipped updates"
    exit 0
fi

if (oc get deployment -n $BR_NS transaction-manager -o yaml > $DIR/transaction-manager-deployment.save.yaml)
then
    echo "Patching deployment/transaction-manager image..."
    oc set image deployment/transaction-manager --namespace $BR_NS transaction-manager=cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:b407e1c6585cc38938d52b750dddef57a97846edc4752b37da55014d1b9ef732
    oc rollout status --namespace $BR_NS --timeout=65s deployment/transaction-manager
else
    echo "ERROR: Failed to save original transaction-manager deployment. Skipped updates."
fi

echo "Please verify that these pods have successfully restarted after hotfix update in their corresponding namespace:"
printf "  %-25s: %s\n" "$BR_NS" "transaction-manager"
