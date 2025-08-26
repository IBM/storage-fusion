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
EXPECTED_VERSION=2.9.1

mkdir -p /tmp/br-post-install-patch-291
if [ "$?" -eq 0 ]
then DIR=/tmp/br-post-install-patch-291
else DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-291_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-291.sh script to $LOG"

#check_cmd:
# Returns:
#   0 on finding the command
#   1 if the command does not exist
check_cmd ()
{
   type $1 > /dev/null
   echo $?
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
    else
        oc -n "$BR_NS" patch kafka guardian-kafka-cluster --type='merge' -p="${patch}" --dry-run=client -o yaml >$DIR/kafka.patch.yaml
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
    echo "Restarting deployments $VALID_DEPLOYMENTS"
    for deployment in $VALID_DEPLOYMENTS; do
        oc -n "$DEPLOYMENT_NAMESPACE" rollout restart deployment "$deployment"
    done
    for deployment in $VALID_DEPLOYMENTS; do
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

if (oc get deployment -n $BR_NS transaction-manager -o yaml > $DIR/transaction-manager-deployment.save.yaml)
then
    echo "Patching deployment/transaction-manager image..."
    oc set image deployment/transaction-manager --namespace $BR_NS transaction-manager=cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:d64c38811669c178aec9aa8b60f439de376e3a47ccb67d7f1e170e1834bb2172
    oc rollout status --namespace $BR_NS --timeout=65s deployment/transaction-manager
else
    echo "ERROR: Failed to save original transaction-manager deployment. Skipped updates."
fi

if (oc get deployment -n $BR_NS dbr-controller -o yaml > $DIR/dbr-controller-deployment.save.yaml)
then
    echo "Patching deployment/dbr-controller image..."
    oc set image deployment/dbr-controller --namespace $BR_NS dbr-controller=cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:c935e0c4a2d9b29c86bacc9322bbd6330a7a30fcb8ccfce2d068abf082d2805e
    oc rollout status --namespace $BR_NS --timeout=65s deployment/dbr-controller
else
    echo "ERROR: Failed to save original dbr-controller deployment. Skipped updates."
fi

if (oc get deployment -n $BR_NS ibm-dataprotectionserver-controller-manager -o yaml > $DIR/ibm-dataprotectionserver-controller-manager-deployment.save.yaml)
then
    echo "Patching deployment/ibm-dataprotectionserver-controller-manager image..."
    oc set image deployment/ibm-dataprotectionserver-controller-manager --namespace $BR_NS manager=icr.io/cpopen/idp-server-operator@sha256:ec54933ec22c0b1175a1d017240401032caff5de0bdf99e7b5acea3a03686470
    oc rollout status --namespace $BR_NS --timeout=65s deployment/ibm-dataprotectionserver-controller-manager
else
    echo "ERROR: Failed to save original ibm-dataprotectionserver-controller-manager deployment. Skipped updates."
fi


if (oc --namespace "$BR_NS" get dpa velero -o yaml > $DIR/velero-original.yaml)
then
    echo "Saved original OADP DataProtectionApplication configuration to $DIR/velero-original.yaml"
    oc patch dataprotectionapplication.oadp.openshift.io velero --namespace "$BR_NS" --type='json' -p='[{"op": "replace", "path": "/spec/unsupportedOverrides/veleroImageFqin", "value":"cp.icr.io/cp/bnr/fbr-velero@sha256:877df338898d3164ddc389b1a4079f56b5cbd5f88cfa31ef4e17da1e5b70868f"}]'
    echo "Velero Deployement is restarting with replacement image"
    oc wait --namespace "$BR_NS" deployment.apps/velero --for=jsonpath='{.status.readyReplicas}'=1
fi

TMROLETOADD=$(cat <<EOF
- apiGroups:
  - ""
  resources:
  - persistentvolumes
  verbs:
  - get
  - patch
EOF
)
echo "Patching transaction-manager-$BR_NS clusterrole..."
TMCLUSTERROLE=transaction-manager-$BR_NS
oc get clusterrole ${TMCLUSTERROLE} -o yaml > $DIR/clusterrole-$TMCLUSTERROLE.yaml
echo -e "$(cat $DIR/clusterrole-$TMCLUSTERROLE.yaml)\n${TMROLETOADD}" | oc apply -f -

if [ -n "$HUB" ]; then
    patch_kafka_cr
    restart_deployments "$BR_NS" applicationsvc job-manager backup-service backup-location-deployment backuppolicy-deployment dbr-controller guardian-dp-operator-controller-manager transaction-manager guardian-dm-controller-manager
    restart_deployments "$ISF_NS" isf-application-operator-controller-manager
fi

echo "Please verify that these pods have successfully restarted after hotfix update in their corresponding namespace:"
printf "  %-25s: %s\n" "$BR_NS" "transaction-manager"
printf "  %-25s: %s\n" "$BR_NS" "dbr-controller"
printf "  %-25s: %s\n" "$BR_NS" "ibm-dataprotectionserver-controller-manager"

echo "Please verify that ClusterRole ${TMCLUSTERROLE} has 'get' and 'patch' permissions for persistentvolumes"
