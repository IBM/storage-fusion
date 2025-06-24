#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.10.0 release.
HOTFIX_NUMBER=1

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
EXPECTED_VERSION=2.10.0

if (mkdir -p /tmp/br-post-install-patch-2.10.0); then
    DIR=/tmp/br-post-install-patch-2.10.0
else
    DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-2.10.0_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-2.10.0.sh script to $LOG"

#check_cmd:
# Returns:
#   0 on finding the command
#   1 if the command does not exist
check_cmd() {
    type "$1" >/dev/null
    echo $?
}

update_hotfix_configmap() {
    hotfix="hotfix-"${EXPECTED_VERSION}.${HOTFIX_NUMBER}
    applied_on=$(date '+%Y-%m-%dT%T')
    if (oc -n "$BR_NS" get configmap bnr-hotfixes 1>/dev/null 2>&1); then
        oc -n "$BR_NS" patch configmap bnr-hotfixes --type=json -p "[{\"op\": \"add\", \"path\": \"/data/${hotfix}-applied-on\", \"value\": \"${applied_on}\"}]"
    else
        oc -n "$BR_NS" create configmap bnr-hotfixes --from-literal=${hotfix}-applied-on="${applied_on}"
    fi
}

REQUIREDCOMMANDS=("oc" "jq")
echo -e "Checking for required commands: ${REQUIREDCOMMANDS[*]}"
for COMMAND in "${REQUIREDCOMMANDS[@]}"; do
    IS_COMMAND=$(check_cmd "$COMMAND")
    if [ "$IS_COMMAND" -ne 0 ]; then
        echo "ERROR: $COMMAND command not found, install $COMMAND command to apply patch"
        exit "$IS_COMMAND"
    fi
done

oc whoami >/dev/null || (
    echo "Not logged in to your cluster"
    exit 1
)

ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)
if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
if [ -n "$BR_NS" ]; then
    HUB=true
else
    BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace 2 >/dev/null)
fi

if [ -z "$BR_NS" ]; then
    echo "ERROR: No B&R installation found. Exiting."
    exit 1
fi

AGENTCSV=$(oc -n "$BR_NS" get csv -o name | grep ibm-dataprotectionagent)
VERSION=$(oc -n "$BR_NS" get "$AGENTCSV" -o custom-columns=:spec.version --no-headers)
if [ -z "$VERSION" ]; then
    echo "ERROR: Could not get B&R version. Skipped updates"
    exit 0
elif [[ $VERSION != $EXPECTED_VERSION* ]]; then
    echo "This patch applies to B&R version $EXPECTED_VERSION only, you have $VERSION. Skipped updates"
    exit 0
fi

if [ -n "$HUB" ]; then
    echo "Apply patches to hub..."

    if (oc get deployment -n "$BR_NS" backup-location-deployment -o yaml >$DIR/backup-location-deployment.save.yaml); then
        echo "Patching deployment/backup-location-deployment image..."
        oc set image deployment/backup-location-deployment -n "$BR_NS" backup-location-container=IMAGE-guardian-backup-location
        oc rollout status --namespace "$BR_NS" --timeout=65s deployment/backup-location-deployment
    else
        echo "ERROR: Failed to save original backup-location-deployment. Skipped updates."
    fi

    if (oc get deployment -n "$BR_NS" guardian-dp-operator-controller-manager -o yaml >$DIR/guardian-dp-operator-controller-manager.save.yaml); then
        echo "Patching deployment/guardian-dp-operator-controller-manager image..."
        oc set image deployment/guardian-dp-operator-controller-manager --namespace "$BR_NS" manager=IMAGE-guardian-dp-operator
        oc rollout status --namespace "$BR_NS" --timeout=65s deployment/guardian-dp-operator-controller-manager
    else
        echo "ERROR: Failed to save original guardian-dp-operator-controller-manager. Skipped updates."
    fi
fi

if (oc get deployment -n "$BR_NS" transaction-manager -o yaml >$DIR/transaction-manager-deployment.save.yaml); then
    echo "Patching deployment/transaction-manager image..."
    oc set image deployment/transaction-manager --namespace "$BR_NS" transaction-manager=IMAGE-guardian-transaction-manager
    oc rollout status --namespace "$BR_NS" --timeout=65s deployment/transaction-manager
else
    echo "ERROR: Failed to save original transaction-manager deployment. Skipped updates."
fi

if (oc --namespace "$BR_NS" get dpa velero -o yaml >$DIR/velero.save.yaml); then
    echo "Patching deployment/velero image..."
    oc patch dataprotectionapplication.oadp.openshift.io velero --namespace "$BR_NS" --type='json' -p='[{"op": "replace", "path": "/spec/unsupportedOverrides/veleroImageFqin", "value":"IMAGE-velero"}]'
    echo "Velero Deployement is restarting with replacement image"
    oc wait --namespace "$BR_NS" deployment.apps/velero --for=jsonpath='{.status.readyReplicas}'=1
fi

update_hotfix_configmap

echo "Please verify that the pods for the following deployment have successfully restarted:"
if [ -n "$HUB" ]; then
    printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "backup-location-deployment"
    printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "guardian-dp-operator-controller-manager"
fi

printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "transaction-manager"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "velero"
