#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.9.1 release.
HOTFIX_NUMBER=2
EXPECTED_VERSION=2.10.1

patch_usage() {
    echo "Usage: $0 < -hci | -sds | -help > [ -dryrun ]"
    echo "Options:"
    echo "  -hci     Apply patch on HCI"
    echo "  -sds     Apply patch on SDS"
    echo "  -help    Display usage"
    echo "  -dryrun  Run without applying fixes"
}

PATCH=
while [[ $# -gt 0 ]]; do
    case "$1" in
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

[ -z "$PATCH" ] && echo "-sds|-hci are required" && patch_usage && exit 1

if (mkdir -p /tmp/br-post-install-patch-2.10.1); then
    DIR=/tmp/br-post-install-patch-2.10.1
else
    DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-2.10.1_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-2.10.1.sh script to $LOG"

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

set_deployment_image() {
    name=$1
    container=$2
    image=$3
    if (oc -n "$BR_NS" get deployment/"${name}" -o yaml >$DIR/"${name}".save.yaml); then
        echo "Patching deployment/${name} image..."
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" set image deployment/"${name}" "${container}"="${image}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" set image deployment/"${name}" "${container}"="${image}" --dry-run=client -o yaml >$DIR/"${name}".patch.yaml
        oc -n "$BR_NS" rollout status --timeout=65s deployment/"${name}"
    else
        echo "ERROR: Failed to save original deployment/${name}. Skipped updates."
    fi
}

set_velero_image() {
    image=$1
    if (oc -n "$BR_NS" get dpa velero -o yaml >$DIR/velero.save.yaml); then
        echo "Patching deployment/velero image..."
        patch="[{\"op\": \"replace\", \"path\": \"/spec/unsupportedOverrides/veleroImageFqin\", \"value\":\"${image}\"}]"
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" patch dataprotectionapplication.oadp.openshift.io velero --type='json' -p="${patch}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" patch dataprotectionapplication.oadp.openshift.io velero --type='json' -p="${patch}" --dry-run=client -o yaml >$DIR/velero.patch.yaml
        echo "Velero Deployement is restarting with replacement image"
        oc wait --namespace "$BR_NS" deployment.apps/velero --for=jsonpath='{.status.readyReplicas}'=1
    fi
}

patch_kafka_cr() {
    echo "Patching Kafka..."
    if ! oc get kafka guardian-kafka-cluster -o jsonpath='{.spec.kafka.listeners}' | grep -q external; then
        # Patch is not needed 
        return 0
    fi
    patch="{\"spec\":{\"kafka\":{\"listeners\":[{\"authentication\":{\"type\":\"tls\"},\"name\":\"tls\",\"port\":9093,\"tls\":true,\"type\":\"internal\"}]}}}"
        if [ -z "$DRY_RUN" ]; then
            oc -n "$BR_NS" patch kafka guardian-kafka-cluster --type='merge' -p="${patch}"
            echo "Waiting for the Kafka cluster to restart (10 min max)"
            oc wait --for=condition=Ready kafka/guardian-kafka-cluster --timeout=600s
        if [ $? -ne 0 ]; then
            echo "Error: Kafka is not ready after configuration patch."
            exit 1
        else
            echo "Kafka is ready. Restarting services that use Kafka."

        fi
    fi
    [ -n "$DRY_RUN" ] && oc -n "$BR_NS" patch kafka guardian-kafka-cluster --type='merge' -p="${patch}" --dry-run=client -o yaml >$DIR/kafka.patch.yaml
}

# restart_deployments restarts all the deployments that are provided and waits for them to reach the Available state.
# Arguments:
#   $1: Namespace of deployments
#   ${@:2}: List of deployments
restart_deployments() {
    DEPLOYMENT_NAMESPACE=${1}
    DEPLOYMENTS="${@:2}"

    if [ -n "$DRY_RUN" ]; then
        return 0
    fi

    echo "Restarting deployments $DEPLOYMENTS"
    for item in $(echo "$DEPLOYMENTS"); do
        oc -n "$DEPLOYMENT_NAMESPACE" rollout restart deployment "$item"
    done
    for item in $(echo "$DEPLOYMENTS"); do
        oc -n "$DEPLOYMENT_NAMESPACE" wait --for=condition=Available "deployment/$item" --timeout=600s
    done
    echo "Services restarted"
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

oc whoami > /dev/null || ( 
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
    BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
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

transactionmanager_img=cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:62c62ec0cd03945bcbc408faa62338e65476617c427373fd609e4809605127a3
set_deployment_image transaction-manager transaction-manager ${transactionmanager_img}
set_deployment_image dbr-controller dbr-controller ${transactionmanager_img}

velero_img=cp.icr.io/cp/bnr/fbr-velero@sha256:910ffee32ec4121df8fc2002278f971cd6b0d923db04d530f31cf5739e08e24c
set_velero_image ${velero_img}

patch_kafka_cr
restart_deployments "$BR_NS" applicationsvc job-manager backup-service backup-location-deployment backuppolicy-deployment dbr-controller guardian-dp-operator-controller-manager transaction-manager guardian-dm-controller-manager
restart_deployments "$ISF_NS" isf-application-operator-controller-manager

hotfix="hotfix-${EXPECTED_VERSION}.${HOTFIX_NUMBER}"
update_hotfix_configmap ${hotfix}

echo "Please verify that the pods for the following deployment have successfully restarted:"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "velero"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "node-agent"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "transaction-manager"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "dbr-controller"
