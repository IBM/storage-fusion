#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.12.3 release.
patch_usage() {
    echo "Patches the Fusion Backup & Restore install to ${EXPECTED_VERSION} hotfix ${HOTFIX_NUMBER}"

    echo "This command should be run on each hub and spoke of a Fusion Backup & Restore install"

    echo "Usage: $0 < -hci | -sds | -help > [ -dryrun ] [-logdir <path>]"
    echo "Options:"
    echo "  -hci     Apply patch on HCI"
    echo "  -sds     Apply patch on SDS"
    echo "  -help    Display usage"
    echo "  -dryrun  Run without applying fixes. Proposed patches will be written to logdir."
    echo "  -logdir  Directory to log output, patches, and saved YAMLs. Defaults to /tmp"
}

HOTFIX_NUMBER=1
EXPECTED_VERSION=2.12.3
IMAGE_SOURCE="br-2.12.3patch-offline-mirror.sh"

PATCH=
DRY_RUN=
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
        DRY_RUN="--dry-run=client"
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

[ -z "$DIR" ] && DIR=/tmp
if ! mkdir -p "${DIR}"; then
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

    echo -e "Checking for required version of oc 4.14+"
    OC_VERSION=$(oc version --client -o json | jq -r '.clientVersion.gitVersion')
    MAJOR=$(echo "${OC_VERSION}" | sed 's/v//' | cut -d. -f1)
    MINOR=$(echo "${OC_VERSION}" | sed 's/v//' | cut -d. -f2)
    if [ "${MAJOR}" -lt 4 ]; then
        echo "Detected oc client version ${OC_VERSION}. Minimum 4.14"
        exit 1
    fi
    if [ "${MINOR}" -lt 14 ]; then
        echo "Detected oc client version ${OC_VERSION}. Minimum 4.14"
        exit 1
    fi
}

check_for_required_dependencies
if ! oc whoami > /dev/null; then
   echo "Not logged in to your cluster"
   exit 1
fi

if [ ! -f "$IMAGE_SOURCE" ]; then
    echo "Container image sourcefile ${IMAGE_SOURCE} is missing. The hotfix"
    echo "requires the container image source file to execute. This file can"
    echo "be found on the hotfix repository."
    # file not found is errno 2
    exit 2
fi

source "${IMAGE_SOURCE}"

ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)
if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

if BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null) && [ -n "$BR_NS" ]
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

update_hotfix_configmap() {
    hotfix=$1
    applied_on=$(date '+%Y-%m-%dT%TZ')
    if (oc -n "$BR_NS" get configmap bnr-hotfixes -o yaml 1>$DIR/bnr-hotfixes.save.yaml 2>&1); then
        patch="[{\"op\": \"add\", \"path\": \"/data/${hotfix}-applied-on\", \"value\": \"${applied_on}\"}]"
        oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} patch configmap bnr-hotfixes --type=json -p "${patch}" -o yaml >$DIR/bnr-hotfixes.patch.yaml
    else
        oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} create configmap bnr-hotfixes --from-literal="${hotfix}"-applied-on="${applied_on}" -o yaml >$DIR/bnr-hotfixes.patch.yaml
    fi
}

AGENT_CSV=$(oc -n "$BR_NS" get csv -o name | grep ibm-dataprotectionagent)
oc patch -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} "$AGENT_CSV" --type=json \
  -p '[
    {
      "op": "replace",
      "path": "/metadata/annotations/operatorframework.io~1properties",
      "value": "{\"properties\":[{\"type\":\"olm.gvk\",\"value\":{\"group\":\"dataprotectionagent.idp.ibm.com\",\"kind\":\"DataProtectionAgent\",\"version\":\"v1\"}},{\"type\":\"olm.package\",\"value\":{\"packageName\":\"ibm-dataprotectionagent\",\"version\":\"2.12.3\"}},{\"type\":\"olm.package.required\",\"value\":{\"packageName\":\"guardian-dm-operator\",\"versionRange\":\"\u003e=2.12.3-1\"}},{\"type\":\"olm.package.required\",\"value\":{\"packageName\":\"guardian-dp-operator\",\"versionRange\":\"\u003e=2.12.3-1\"}},{\"type\":\"olm.package.required\",\"value\":{\"packageName\":\"redhat-oadp-operator\",\"versionRange\":\"\u003e=1.4.1 \u003c1.7.0 !1.4.11\"}}]}"
    }
  ]'

OADP_SUB=$(oc -n "$BR_NS" get subs -o name | grep oadp)
OADP_CSV=$(oc -n "$BR_NS" get csv -o name | grep oadp)
OADP_VER=$(oc -n "$BR_NS" get "$OADP_CSV" -o custom-columns=:spec.version --no-headers)
OADP_DEPLOYMENT="openshift-adp-controller-manager"
if [ "$OADP_VER" == "1.4.11" ]; then
   oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} delete "$OADP_CSV"
   oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} delete deployment "$OADP_DEPLOYMENT"
   oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} patch "$OADP_SUB" --type=merge -p '{"spec":{"startingCSV":null}}'

   NEW_OADP_CSV=$(oc -n "$BR_NS" get csv -l "operators.coreos.com/redhat-oadp-operator.$BR_NS" -o name)
   while [ -z "$NEW_OADP_CSV" ] ; do
      echo "Waiting for new OADP to be installed..."
      sleep 5
      NEW_OADP_CSV=$(oc -n "$BR_NS" get csv -l "operators.coreos.com/redhat-oadp-operator.$BR_NS" -o name)
   done
   echo "$NEW_OADP_CSV is created"

   until oc get deployment "${OADP_DEPLOYMENT}" -n "${BR_NS}" &> /dev/null; do
      echo "Waiting for deployment ${OADP_DEPLOYMENT} to be created..."
      sleep 5
   done

   echo "Deployment $OADP_DEPLOYMENT created! Now waiting for it to become fully available..."
   oc -n "$BR_NS" rollout status deployment/"${OADP_DEPLOYMENT}" --timeout=5m
   oc -n "$BR_NS" get deployment "${OADP_DEPLOYMENT}"
fi
hotfix="hotfix-${EXPECTED_VERSION}.${HOTFIX_NUMBER}"

update_hotfix_configmap ${hotfix}
