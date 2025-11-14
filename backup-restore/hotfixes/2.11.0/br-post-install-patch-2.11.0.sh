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
HOTFIX_NUMBER=4
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

fix_redis() {
    if oc get StatefulSet redis-master -n $BR_NS -o yaml | grep "storage: 8Gi" >/dev/null 2>&1; then
        echo redis CR needs to be recreated
        IDP_SERVER_POD=$(oc get pods -n $BR_NS | awk '{print $1}' | grep -i ibm-dataprotectionserver-controller-manager)
        STORAGE_CLASS=$(oc get dataprotectionserver ibm-backup-restore-service-instance -n $BR_NS -o yaml | grep storageClass |  awk -F' ' '{print $2}')

        # Get the Redis CR yaml from idp-server pod
        if [ -f "guardian-redis-cr.yaml" ]; then
            rm "guardian-redis-cr.yaml"
        fi
        oc exec -c manager -n $BR_NS $IDP_SERVER_POD -- cat /k8s/redis/guardian-redis-cr.yaml >  ./guardian-redis-cr.yaml

        OLD_SIZE="size: 8Gi"
        NEW_SIZE="size: 256Mi"
        OLD_FBR_IMAGE="fbr-redis"
        NEW_FBR_IMAGE="fbr-valkey"
        OLD_FBR_TAG="tag: 7.0.4"
        NEW_FBR_TAG="tag: 7.2.5"
        OLD_SC="rook-ceph-block"

        # Replace old PVC size, valkey image and tag
        sed -i '' "s/${OLD_SIZE}/${NEW_SIZE}/g" "guardian-redis-cr.yaml"
        sed -i '' "s/${OLD_FBR_IMAGE}/${NEW_FBR_IMAGE}/g" "guardian-redis-cr.yaml"
        sed -i '' "s/\<${OLD_FBR_TAG}\>/${NEW_FBR_TAG}/g" "guardian-redis-cr.yaml"
        sed -i '' "s/${OLD_SC}/${STORAGE_CLASS}/g" "guardian-redis-cr.yaml"

        oc scale deployment -n $BR_NS redis-operator-controller-manager --replicas=0

        # Delete any redis-dockercfg* and redis-token* secrets that might have been constantly
        # generated when redis-controller was in error state
        oc get secrets -o name | grep redis-dockercfg | xargs oc delete
        oc get secrets -o name | grep redis-token | xargs oc delete

        # Create Redis CR
        oc delete redis redis -n $BR_NS --timeout=60s
        if oc get redis redis -n $BR_NS >/dev/null 2>&1; then
            oc patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' redis redis -n $BR_NS
            oc delete redis redis -n $BR_NS
        fi

        oc scale deployment -n $BR_NS redis-operator-controller-manager --replicas=1
        oc wait -n $BR_NS deployment/redis-operator-controller-manager --for=jsonpath='{.status.readyReplicas}'=1

        # Recreate Redis CR using updated yaml
        oc apply -n $BR_NS -f guardian-redis-cr.yaml
        echo Finished creating Redis CR
    fi
}

get_oadp_version() {
    oc get csv  -l operators.coreos.com/redhat-oadp-operator.${BR_NS} -o json | jq .items[0].spec.version
}

set_velero_image() {
    OADP_VERSION=$(get_oadp_version)
    echo "Patching OADP $OADP_VERSION"
    if [[ $OADP_VERSION == *"1.4"* ]]; then
        image=$1
    else
        image=$2
    fi

    if (oc -n "$BR_NS" get dpa velero -o yaml >$DIR/velero.save.yaml); then
        echo "Patching deployment/velero image..."
        patch="[{\"op\": \"replace\", \"path\": \"/spec/unsupportedOverrides/veleroImageFqin\", \"value\":\"${image}\"}]"
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" patch dataprotectionapplication.oadp.openshift.io velero --type='json' -p="${patch}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" patch dataprotectionapplication.oadp.openshift.io velero --type='json' -p="${patch}" --dry-run=client -o yaml >$DIR/velero.patch.yaml
        echo "Velero Deployement is restarting with replacement image"
        oc wait --namespace "$BR_NS" deployment.apps/velero --for=jsonpath='{.status.readyReplicas}'=1
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

if [ -n "$HUB" ]; then
    fix_redis
fi

if (oc get deployment -n $BR_NS transaction-manager -o yaml > $DIR/transaction-manager-deployment.save.yaml)
then
    echo "Patching deployment/transaction-manager image..."
    oc set image deployment/transaction-manager --namespace $BR_NS transaction-manager=cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:6465fadda4ca4402d098932d68563209ecfcc6ca7aa3e5accee02be98e4404dd
    oc rollout status --namespace $BR_NS --timeout=65s deployment/transaction-manager
else
    echo "ERROR: Failed to save original transaction-manager deployment. Skipped updates."
fi

# update oadp velero
oadp_velero_14=cp.icr.io/cp/bnr/fbr-velero@sha256:1fd0dc018672507b24148a0fe71e69f91ab31576c7fa070c599d7a446b5095aa
oadp_velero_15=cp.icr.io/cp/bnr/fbr-velero15@sha256:7a57d50f9c1b6a338edf310c5e69182ac98ec6338376b4ddc0474ff7e592f4f4
set_velero_image ${oadp_velero_14} ${oadp_velero_15}


hotfix="hotfix-${EXPECTED_VERSION}.${HOTFIX_NUMBER}"
update_hotfix_configmap ${hotfix}

echo "Please verify that these pods have successfully restarted after hotfix update in their corresponding namespace:"
printf "  %-25s: %s\n" "$BR_NS" "transaction-manager"
