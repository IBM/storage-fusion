#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.9.1 release.
HOTFIX_NUMBER=4
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

# Updates guardian-dp-operator and idp-agent-operator CSVs
update_operator_csv() {
    name="$1"
    deployment_name="$2"
    image="$3"
    csv_ns="$BR_NS"

    if (oc get csv -n "$csv_ns" "$name" -o yaml > "$DIR/${name}.save.yaml"); then
        echo "Scaling down deployment: $deployment_name ..."
        [ -z "$DRY_RUN" ] && oc scale deployment -n "$csv_ns" "$deployment_name" --replicas=0

        echo "Patching clusterserviceversion/$name (deployment: $deployment_name, image: $image) ..."
        dep_index=$(oc get csv -n "$csv_ns" "$name" -o json | jq "[.spec.install.spec.deployments[].name] | index(\"$deployment_name\")")

        if [[ "$dep_index" == "null" ]]; then
            echo "ERROR: Deployment '$deployment_name' not found in CSV $name"
            return 1
        fi
        patches=()
        container_index=0
        for cname in $(oc get csv -n "$csv_ns" "$name" -o json \
            | jq -r ".spec.install.spec.deployments[$dep_index].spec.template.spec.containers[].name"); do
            if [[ "$cname" == "manager" ]]; then
                patches+=("{\"op\":\"replace\",\"path\":\"/spec/install/spec/deployments/${dep_index}/spec/template/spec/containers/${container_index}/image\",\"value\":\"${image}\"}")
            fi
            ((container_index++))
        done

        patch_json="[$(IFS=,; echo "${patches[*]}")]"
        [ -z "$DRY_RUN" ] &&  oc patch csv -n "$csv_ns" "$name" --type='json' -p "$patch_json"
        [ -n "$DRY_RUN" ] && oc patch csv -n "$csv_ns" "$name" --type='json' -p "$patch_json" --dry-run=client -o yaml > "$DIR/${name}.patch.yaml"

        echo "Scaling up deployment: $deployment_name ..."
        [ -z "$DRY_RUN" ] && oc scale deployment -n "$csv_ns" "$deployment_name" --replicas=1

    else
        echo "ERROR: Failed to save original clusterserviceversion/$name. Skipped updates."
    fi
}

patch_kafka_cr() {
    echo "Patching Kafka..."
    if ! oc get kafka guardian-kafka-cluster -n "$BR_NS" -o jsonpath='{.spec.kafka.listeners}' | grep -q external; then
        # Patch is not needed 
        return 0
    fi
    patch="{\"spec\":{\"kafka\":{\"listeners\":[{\"authentication\":{\"type\":\"tls\"},\"name\":\"tls\",\"port\":9093,\"tls\":true,\"type\":\"internal\"}]}}}"
    if [ -z "$DRY_RUN" ]; then
        oc -n "$BR_NS" patch kafka guardian-kafka-cluster --type='merge' -p="${patch}"
        echo "Waiting for the Kafka cluster to restart (10 min max)"
        oc wait --for=condition=Ready kafka/guardian-kafka-cluster -n "$BR_NS" --timeout=600s
        if [ $? -ne 0 ]; then
            echo "Error: Kafka is not ready after configuration patch."
            exit 1
        else
            echo "Kafka is ready. Restarting services that use Kafka."

        fi
    else
        oc -n "$BR_NS" patch kafka guardian-kafka-cluster --type='merge' -p="${patch}" --dry-run=client -o yaml >$DIR/kafka.patch.yaml
    fi
}

update_kafka_topic_message_size() {
    echo "Patching Kafka inventory, restore and delete-backup topics..."

    patch='[{"op": "add", "path": "/spec/config/max.message.bytes", "value": "5242880"}]'
    if [ -z "$DRY_RUN" ]; then
        oc -n "$BR_NS" patch KafkaTopic inventory --type='json' -p="${patch}"
        oc -n "$BR_NS" patch KafkaTopic restore --type='json' -p="${patch}"
        oc -n "$BR_NS" patch KafkaTopic delete-backup --type='json' -p="${patch}"
        echo "Patched Kafka topics"
    else
        oc -n "$BR_NS" patch KafkaTopic inventory --type='json' -p="${patch}" --dry-run=client -o yaml >$DIR/inventory-topic.patch.yaml
        oc -n "$BR_NS" patch KafkaTopic restore --type='json' -p="${patch}" --dry-run=client -o yaml >$DIR/restore-topic.patch.yaml
    fi
}

update_kafka_connection() {
    echo "Setting Kafka message size properties in kafka-connection ConfigMap..."
    patch='[{"op": "add", "path": "/data/max.request.size", "value": "5242880"}]'
    if [ -z "$DRY_RUN" ]; then
        oc -n "$BR_NS" patch configmap kafka-connection --type='json' -p="${patch}"
    else
        oc -n "$BR_NS" patch configmap kafka-connection --type='json' -p="${patch}" --dry-run=client -o yaml >$DIR/kafka-connection.patch.yaml
    fi
}

update_tm_env() {
    echo "Setting Kafka message size property in as TM env variable..."
    message_size='MAX_REQUEST_SIZE=5242880'
    if [ -z "$DRY_RUN" ]; then
        oc set env -n "$BR_NS" deployment/transaction-manager "${message_size}"
        oc set env -n "$BR_NS" deployment/dbr-controller "${message_size}"
    else
        oc set env -n "$BR_NS" deployment/transaction-manager "${message_size}" --dry-run=client -o yaml >$DIR/tm_env.patch.yaml
        oc set env -n "$BR_NS" deployment/transaction-manager "${message_size}" --dry-run=client -o yaml >$DIR/dbr_env.patch.yaml
    fi
}

# restart_deployments restarts all the deployments that are provided and waits for them to reach the Available state.
# Arguments:
#   $1: Namespace of deployments
#   ${@:2}: List of deployments
restart_deployments() {
    DEPLOYMENT_NAMESPACE=${1}
    DEPLOYMENTS=("${@:2}")
    VALID_DEPLOYMENTS=()

    if [ -n "$DRY_RUN" ]; then
     return
    fi

    for deployment in "${DEPLOYMENTS[@]}"; do
        if oc -n "$DEPLOYMENT_NAMESPACE" get deployment "${deployment}" &> /dev/null; then
            VALID_DEPLOYMENTS+=("$deployment")
        fi
    done
    echo "Restarting deployments ${VALID_DEPLOYMENTS[@]}"
    for deployment in ${VALID_DEPLOYMENTS[@]}; do
        oc -n "$DEPLOYMENT_NAMESPACE" rollout restart deployment "$deployment"
    done
    for deployment in ${VALID_DEPLOYMENTS[@]}; do
        oc -n "$DEPLOYMENT_NAMESPACE" rollout status deployment "$deployment"
    done
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

update_tm_env
transactionmanager_img=cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:45a3ff23c17fc0078bd67f26ba494724dd9f9d0c9b73c92adf444e6d152b2136
set_deployment_image transaction-manager transaction-manager ${transactionmanager_img}
set_deployment_image dbr-controller dbr-controller ${transactionmanager_img}

velero_img=cp.icr.io/cp/bnr/fbr-velero@sha256:b34f53ef2a02a883734f24dba9411baf6cfeef38983183862fa0ea773a7fc405
set_velero_image ${velero_img}

if [ -n "$HUB" ]; then
    guardiandpoperator_img=icr.io/cpopen/guardian-dp-operator@sha256:e7dce0d4817e545e5d40f90b116e85bd5ce9098f979284f12ad63cbc56f52d8c
    update_operator_csv guardian-dp-operator.v2.10.1 guardian-dp-operator-controller-manager "${guardiandpoperator_img}"

    guardianidpagentoperator_img=icr.io/cpopen/idp-agent-operator@sha256:b2ab67807e79a064b14d7c79c902c5ec5949c0b6dc2ac4c990dcfb201f00ee0a
    update_operator_csv ibm-dataprotectionagent.v2.10.1 ibm-dataprotectionagent-controller-manager "${guardianidpagentoperator_img}"
    
    jobmanager_img=cp.icr.io/cp/bnr/guardian-job-manager@sha256:b9fe3eb8e5562c35c8f353a1283328a39eefeccaca81b0b9608f9eb14631ae6c
    set_deployment_image job-manager job-manager-container ${jobmanager_img}

    patch_kafka_cr
    update_kafka_topic_message_size
    update_kafka_connection
    restart_deployments "$BR_NS" applicationsvc job-manager backup-service backup-location-deployment backuppolicy-deployment dbr-controller guardian-dp-operator-controller-manager transaction-manager guardian-dm-controller-manager
    restart_deployments "$ISF_NS" isf-application-operator-controller-manager
fi

hotfix="hotfix-${EXPECTED_VERSION}.${HOTFIX_NUMBER}"
update_hotfix_configmap ${hotfix}

echo "Please verify that the pods for the following deployment have successfully restarted:"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "velero"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "node-agent"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "transaction-manager"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "guardian-dp-operator-controller-manager"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "ibm-dataprotectionagent-controller-manager"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "dbr-controller"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "guardian-kafka-cluster-kafka"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "job-manager"
