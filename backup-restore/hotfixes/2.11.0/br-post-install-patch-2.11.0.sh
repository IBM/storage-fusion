#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.11.0 release.

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
HOTFIX_NUMBER=2
EXPECTED_VERSION=2.11.0

mkdir -p /tmp/br-post-install-patch-2.11.0
if [ "$?" -eq 0 ]
then DIR=/tmp/br-post-install-patch-2.11.0
else DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-2.11.0_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-2.11.0.sh script to $LOG"

#check_cmd:
# Returns:
#   0 on finding the command
#   1 if the command does not exist
check_cmd ()
{
   type $1 > /dev/null
   echo $?
}

update_hotfix_configmap() {
    hotfix=$1
    applied_on=$(date '+%Y-%m-%dT%T')
    if (oc -n "$BR_NS" get configmap bnr-hotfixes -o yaml 1>$DIR/bnr-hotfixes.save.yaml 2>&1); then
        patch="[{\"op\": \"add\", \"path\": \"/data/${hotfix}-applied-on\", \"value\": \"${applied_on}\"}]"
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" patch configmap bnr-hotfixes --type=json -p "${patch}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" patch configmap bnr-hotfixes --type=json -p "${patch}" --dry-run=client -o yaml >$DIR/bnr-hotfixes.patch.yaml
    else
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" create configmap bnr-hotfixes --from-literal="${hotfix}"-applied-on="${applied_on}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" create configmap bnr-hotfixes --from-literal="${hotfix}"-applied-on="${applied_on}" --dry-run=client -o yaml >$DIR/bnr-hotfixes.patch.yaml
    fi
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
    oc set image deployment/transaction-manager --namespace $BR_NS transaction-manager=cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:6465fadda4ca4402d098932d68563209ecfcc6ca7aa3e5accee02be98e4404dd
    oc rollout status --namespace $BR_NS --timeout=65s deployment/transaction-manager
else
    echo "ERROR: Failed to save original transaction-manager deployment. Skipped updates."
fi

hotfix="hotfix-${EXPECTED_VERSION}.${HOTFIX_NUMBER}"
update_hotfix_configmap ${hotfix}

echo "Please verify that these pods have successfully restarted after hotfix update in their corresponding namespace:"
printf "  %-25s: %s\n" "$BR_NS" "transaction-manager"
