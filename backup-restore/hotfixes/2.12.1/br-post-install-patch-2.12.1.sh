#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.12.1 release.
HOTFIX_NUMBER=1
EXPECTED_VERSION=2.12.1

patch_usage() {
    echo "Patches the Fusion Backup & Restore install to ${EXPECTED_VERSION} hotfix ${HOTFIX_NUMBER}".

    echo "This command should be run on each hub and spoke of a Fusion Backup & Restore"
    echo "install."

    echo "Usage: $0 < -hci | -sds | -help > [ -dryrun ] [-logdir <path>]"
    echo "Options:"
    echo "  -hci     Apply patch on HCI"
    echo "  -sds     Apply patch on SDS"
    echo "  -help    Display usage"
    echo "  -dryrun  Run without applying fixes. Proposed patches will be written to logdir."
    echo "  -logdir  Directory to log output, patches, and saved YAMLs. Defaults to /tmp/br-post-install-patch-${EXPECTED_VERSION}"
}
set -e

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
    applied_on=$(date '+%Y-%m-%dT%TZ')
    if (oc -n "$BR_NS" get configmap bnr-hotfixes -o yaml 1>$DIR/bnr-hotfixes.save.yaml 2>&1); then
        patch="[{\"op\": \"add\", \"path\": \"/data/${hotfix}-applied-on\", \"value\": \"${applied_on}\"}]"
        oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} patch configmap bnr-hotfixes --type=json -p "${patch}" -o yaml >$DIR/bnr-hotfixes.patch.yaml
    else
        oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} create configmap bnr-hotfixes --from-literal="${hotfix}"-applied-on="${applied_on}" -o yaml >$DIR/bnr-hotfixes.patch.yaml
    fi
}

get_oadp_version() {
    oc get csv  -l operators.coreos.com/redhat-oadp-operator.${BR_NS} -n "$BR_NS" -o json | jq .items[0].spec.version
}

set_deployment_image() {
    name=$1
    container=$2
    image=$3
    echo "${name} ${container} ${image}"
    if (oc -n "$BR_NS" get deployment/"${name}" -o yaml >$DIR/"${name}".save.yaml); then
        echo "Patching deployment/${name} image..."
        oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} set image deployment/"${name}" "${container}"="${image}" -o yaml >$DIR/"${name}".patch.yaml
        oc -n "$BR_NS" rollout status --timeout=65s deployment/"${name}"
    else
        echo "ERROR: Failed to save original deployment/${name}. Skipped updates."
    fi
}

set_velero_image() {
    OADP_VERSION=$(get_oadp_version)
    if [[ $OADP_VERSION == *"1.4"* ]]; then
        image=$1
    else
        # image=$2
        # current hotfix 1 only patches OADP-1.4
        return 0
    fi

    echo "Patching OADP $OADP_VERSION"

    if (oc -n "$BR_NS" get dpa velero -o yaml >$DIR/velero.save.yaml); then
        echo "Patching deployment/velero image..."
        patch="[{\"op\": \"replace\", \"path\": \"/spec/unsupportedOverrides/veleroImageFqin\", \"value\":\"${image}\"}, {\"op\": \"replace\", \"path\": \"/metadata/annotations/veleroforoadp14\", \"value\": \"${oadp_velero_14}\"},{\"op\": \"replace\", \"path\": \"/metadata/annotations/veleroforoadp15\", \"value\": \"${oadp_velero_15}\"}]"
        oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} patch dataprotectionapplication.oadp.openshift.io velero --type='json' -p="${patch}" -o yaml >$DIR/velero.patch.yaml
        echo "Velero Deployement is restarting with replacement image"
        oc wait --namespace "$BR_NS" deployment.apps/velero --for=jsonpath='{.status.readyReplicas}'=1
    fi
}

# mirror spoke values to ConfigMap guardian-configmap (#69600)
# most of the time this can be resolved by forcing reconciles due to state-1 incorrect behavior
resolve_hub_connection() {
    # hub (bool) Whether the current cluster is a hub or spoke, this does not execute on hubs
    HUB=$1

    if [[ "${HUB}" == "true" ]]; then
        return 0
    fi

    if (oc -n "${BR_NS}" get "configmap/guardian-configmap" -o yaml >$DIR/guardian-configmap.save.yaml); then
        echo "Triggering reconcile of agent operator and mirroring cross-cluster communication configmap values"
        AGENT_NAME=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.name 2>/dev/null)
        # twice to deal with the state-1 issue
        oc --namespace "${BR_NS}" ${DRY_RUN:+"${DRY_RUN}"} label "dataprotectionagent/${AGENT_NAME}" forceupdate="true"
        oc --namespace "${BR_NS}" ${DRY_RUN:+"${DRY_RUN}"} label "dataprotectionagent/${AGENT_NAME}" forceupdate-
        oc --namespace "${BR_NS}" ${DRY_RUN:+"${DRY_RUN}"} label "dataprotectionagent/${AGENT_NAME}" forceupdate="true"
        oc --namespace "${BR_NS}" ${DRY_RUN:+"${DRY_RUN}"} label "dataprotectionagent/${AGENT_NAME}" forceupdate-

        # and mirror the required values to configmap guardian-configmap
        CONNECTION_NAME=$(oc get --namespace "${BR_NS}" "dataprotectionagent/${AGENT_NAME}" -o jsonpath='{.spec.connectionName}')
        HUB_ENDPOINT_URL=$(oc get --namespace "${BR_NS}" "dataprotectionagent/${AGENT_NAME}" -o jsonpath='{.spec.hubEndPointURL}')
        HUB_CLUSTER_NAME=$(oc get --namespace "${BR_NS}" "dataprotectionagent/${AGENT_NAME}" -o jsonpath='{.spec.hubClusterName}')
        KAFKA_ENDPOINT=$(oc get --namespace "${BR_NS}" "dataprotectionagent/${AGENT_NAME}" -o jsonpath='{.spec.transactionManager.kafkaService}')
        KAFKA_PORT=$(oc get --namespace "${BR_NS}" "dataprotectionagent/${AGENT_NAME}" -o jsonpath='{.spec.transactionManager.kafkaPort}')
        oc --namespace "${BR_NS}" ${DRY_RUN:+"${DRY_RUN}"} set data "configmap/guardian-configmap" connectionName="${CONNECTION_NAME}" hubEndPointURL="${HUB_ENDPOINT_URL}" hubClusterName="${HUB_CLUSTER_NAME}" kafka-service="${KAFKA_ENDPOINT}" kafka-port="${KAFKA_PORT}" -o yaml >$DIR/guardian-configmap.patch.yaml
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

    echo -e "Checking for required version of oc 4.10+"
    OC_VERSION=$(oc version --client -o json | jq -r '.clientVersion.gitVersion')
    MAJOR=$(echo "${OC_VERSION}" | sed 's/v//' | cut -d. -f1)
    MINOR=$(echo "${OC_VERSION}" | sed 's/v//' | cut -d. -f2)
    if [ "${MAJOR}" -lt 4 ]; then
        echo "Detected oc client version ${OC_VERSION}. Minimum 4.10"
        exit 1
    fi
    if [ "${MINOR}" -lt 10 ]; then
        echo "Detected oc client version ${OC_VERSION}. Minimum 4.10"
        exit 1
    fi
}

check_for_required_dependencies

oc whoami > /dev/null || ( echo "Not logged in to your cluster" ; exit 1)

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

# make hub/cluster spoke connection settings to reconcile and resolve to the configmap
resolve_hub_connection $HUB