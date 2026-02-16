#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.11.0 release.
HOTFIX_NUMBER=1
EXPECTED_VERSION=2.12.0

source br-2.12.0patch-offline-mirror.sh

patch_usage() {
    echo "Usage: $0 < -hci | -sds | -help > [ -dryrun ] [-logdir <path>]"
    echo "Options:"
    echo "  -hci     Apply patch on HCI"
    echo "  -sds     Apply patch on SDS"
    echo "  -help    Display usage"
    echo "  -dryrun  Run without applying fixes"
    echo "  -logdir  Directory to log output, patches, and saved YAMLs. Defaults to /tmp/br-post-install-patch-${EXPECTED_VERSION}"
}
set -e

PATCH=
while [[ $# -gt 0 ]]; do
    case "${1}" in
    -sds)
        PATCH="SDS"
        shift
        ;;
    -hci)
        PATCH="HCI"
        shift
        ;;
    -dryrun)
        DRY_RUN="true"
        shift
        ;;
    -logdir)
        shift
        DIR="${1}"
        shift
        ;;
    -help)
        patch_usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        patch_usage
        exit 1
        ;;
    esac
done

# use selected directory for saving logs, patches, and old values
# if not, use the default generated directory
# if not, use /tmp
if [ -z "$DIR" ]; then
  DIR=/tmp/br-post-install-patch-${EXPECTED_VERSION}
fi

mkdir -p ${DIR}
if [ "$?" -ne 0 ]; then
  DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-${EXPECTED_VERSION}_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-${EXPECTED_VERSION}.sh script to $LOG"

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

get_oadp_version() {
    oc get csv  -l operators.coreos.com/redhat-oadp-operator.${BR_NS} -n "$BR_NS" -o json | jq .items[0].spec.version
}

set_velero_image() {
    OADP_VERSION=$(get_oadp_version)
    if [[ $OADP_VERSION == *"1.4"* ]]; then
        image=$1
    else
        # image=$2
        # current hotfix 1 only patches OADP-1.4
        return
    fi

    echo "Patching OADP $OADP_VERSION"

    if (oc -n "$BR_NS" get dpa velero -o yaml >$DIR/velero.save.yaml); then
        echo "Patching deployment/velero image..."
        patch="[{\"op\": \"replace\", \"path\": \"/spec/unsupportedOverrides/veleroImageFqin\", \"value\":\"${image}\"}, {\"op\": \"replace\", \"path\": \"/metadata/annotations/veleroforoadp14\", \"value\": \"${oadp_velero_14}\"},{\"op\": \"replace\", \"path\": \"/metadata/annotations/veleroforoadp15\", \"value\": \"${oadp_velero_15}\"}]"
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" patch dataprotectionapplication.oadp.openshift.io velero --type='json' -p="${patch}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" patch dataprotectionapplication.oadp.openshift.io velero --type='json' -p="${patch}" --dry-run=client -o yaml >$DIR/velero.patch.yaml
        echo "Velero Deployement is restarting with replacement image"
        oc wait --namespace "$BR_NS" deployment.apps/velero --for=jsonpath='{.status.readyReplicas}'=1
    fi
}

check_for_required_dependencies() {
    REQUIREDCOMMANDS=("oc" "jq")
    echo -e "Checking for required commands: ${REQUIREDCOMMANDS[*]}"
    for COMMAND in "${REQUIREDCOMMANDS[@]}"; do
        IS_COMMAND=$(check_cmd $COMMAND)
        if [ $IS_COMMAND -ne 0 ]; then
            echo "ERROR: $COMMAND command not found, install $COMMAND command to apply patch"
            exit $IS_COMMAND
        fi
    done
}

check_for_required_dependencies

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

# update oadp velero
oadp_velero_14=$(build_icr_path ${OADP_VELERO_14})
oadp_velero_15=""
set_velero_image ${oadp_velero_14} ${oadp_velero_15}

hotfix="hotfix-${EXPECTED_VERSION}.${HOTFIX_NUMBER}"
update_hotfix_configmap ${hotfix}

echo "Please verify that the pods for the following deployment have successfully restarted for Openshift 4.18 and lower:"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "velero"

echo "Please verify that the pods for the following daemonsets have successfully restarted for Openshift 4.18 and lower:"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "node-agent"