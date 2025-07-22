#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.9.1 release.
# Refer to https://www.ibm.com/support/pages/node/7230021 for additional information.
# Version 05-16-2025

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
EXPECTED_VERSION=2.10.1

mkdir -p /tmp/br-post-install-patch-2101
if [ "$?" -eq 0 ]
then DIR=/tmp/br-post-install-patch-2101
else DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-2101_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-2101.sh script to $LOG"

#check_cmd:
# Returns:
#   0 on finding the command
#   1 if the command does not exist
check_cmd ()
{
   type $1 > /dev/null
   echo $?
}

REQUIREDCOMMANDS=("oc" "jq")
echo -e "Checking for required commands: ${REQUIREDCOMMANDS[*]}"
for COMMAND in "${REQUIREDCOMMANDS[@]}"; do
    IS_COMMAND=$(check_cmd $COMMAND)
    if [ $IS_COMMAND -ne 0 ]; then
        echo "ERROR: $COMMAND command not found, install $COMMAND command to apply patch"
        exit $IS_COMMAND
    fi
done

oc whoami > /dev/null || ( echo "Not logged in to your cluster" ; exit 1)

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


if (oc --namespace "$BR_NS" get dpa velero -o yaml > $DIR/velero-original.yaml)
then
    echo "Saved original OADP DataProtectionApplication configuration to $DIR/velero-original.yaml"
    oc patch dataprotectionapplication.oadp.openshift.io velero --namespace "$BR_NS" --type='json' -p='[{"op": "replace", "path": "/spec/unsupportedOverrides/veleroImageFqin", "value":"cp.icr.io/cp/bnr/fbr-velero@sha256:910ffee32ec4121df8fc2002278f971cd6b0d923db04d530f31cf5739e08e24c"}]'
    echo "Velero Deployement is restarting with replacement image"
    oc wait --namespace "$BR_NS" deployment.apps/velero --for=jsonpath='{.status.readyReplicas}'=1
fi

echo "Please verify that these pods have successfully restarted after hotfix update in their corresponding namespace:"
printf "  %-25s: %s\n" "$BR_NS" "velero"
printf "  %-25s: %s\n" "$BR_NS" "node-agent"

