#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.9.0 release.
# Refer to https://www.ibm.com/support/pages/node/7181447 for additional information.
# Version 02-27-2025

patch_usage() {
  echo "Usage: $0 (-hci |-sds | -help)"
  echo "Options:"
  echo "  -hci   Apply patch on HCI"
  echo "  -sds   Apply patch on SDS"
  echo "  -help  Display usage"
}

# Returns:
# 0 if configmap node-agent-config exists
# 1 if configmap node-agent-config does not exist
testNodeAgentConfigMap() {
    oc get configmap node-agent-config --namespace $1 2>/dev/null | grep -q "^node-agent-config"
    echo $?
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

mkdir -p /tmp/br-post-install-patch-290
if [ "$?" -eq 0 ]
then DIR=/tmp/br-post-install-patch-290
else DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-290_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-290.sh script to $LOG"

check_cmd ()
{
   (type $1 > /dev/null) || echo "$1 command not found, install jq command to apply patch"
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

check_cmd oc
check_cmd jq
oc whoami > /dev/null || (echo "Not logged in to your cluster" ; exit 1)

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

if [ -n "$HUB" ]
    then
      if (oc get recipes.spp-data-protection.isf.ibm.com fusion-control-plane -n $ISF_NS -o yaml > $DIR/fusion-control-plane-recipe.save.yaml)
      then
        echo "Patching fusion-control-plane recipe on hub ..."
        oc patch recipes.spp-data-protection.isf.ibm.com fusion-control-plane -n $ISF_NS --type=merge -p '"spec": {"workflows": [{"failOn": "essential-error","name": "backup","sequence": [{"group": "bsl-secrets"},{"group": "connection-secrets"},{"group": "fusion-dp-crs"},{"group": "fusion-opt-crs"},{"group": "cluster-crs"},{"hook": "fbr-hooks/export-backup-inventory"},{"group": "add-mongo-inventory"}]},{"failOn": "essential-error","name": "restore","sequence": [{"hook": "isf-dp-operator-hook/disable-webhook"},{"hook": "fbr-hooks/deleteCRs"},{"hook": "isf-dp-operator-hook/quiesce-isf-dp-controller"},{"group": "bsl-secrets"},{"group": "connection-secrets"},{"group": "restore-fusion-opt-crs"},{"group": "restore-fusion-dp-crs"},{"group": "cluster-crs"},{"hook": "fbr-hooks/restore-backup-inventory"},{"hook": "isf-dp-operator-hook/unquiesce-isf-dp-controller"}]}]}'
    else
        echo "ERROR: Failed to save original fusion-control-plane recipe. Skipped updates."
    fi
fi

FSIROLETOADD=$(cat <<EOF
- apiGroups:
  - service.isf.ibm.com
  resources:
  - fusionserviceinstances
  verbs:
  - get
  - list
  - watch
EOF
)
echo "Patching isf-data-protection-operator-controller-manager clusterrole..."
CLUSTERROLE=`oc get clusterrolebinding -o wide | grep "${ISF_NS}/isf-data-protection-operator-controller-manager" | grep isf-operator.v2.9.0 | awk '{print $2}'`
oc get ${CLUSTERROLE} -o yaml > $DIR/clusterrole-isf-data-protection.save.yaml
echo -e "$(cat $DIR/clusterrole-isf-data-protection.save.yaml)\n${FSIROLETOADD}" | oc apply -f -
   
if (oc get csv -n $ISF_NS isf-operator.v2.9.0 -o yaml > $DIR/isf-operator.v2.9.0.save.yaml)
  then
    echo "Scaling down isf-data-protection-operator-controller-manager deployment..."
    oc scale deployment -n $ISF_NS isf-data-protection-operator-controller-manager --replicas=0
    index=$(oc get csv -n $ISF_NS isf-operator.v2.9.0 -o json | jq '[.spec.install.spec.deployments[].name] | index("isf-data-protection-operator-controller-manager")')
    if [[ "$PATCH" == "HCI" ]]; then
        echo "Patching HCI clusterserviceversion/isf-operator.v2.9.0..."
        oc patch csv -n ${ISF_NS} isf-operator.v2.9.0 --type='json' -p="[{\"op\":\"replace\", \"path\":\"/spec/install/spec/deployments/$index/spec/template/spec/containers/0/image\", \"value\":\"cp.icr.io/cp/fusion-hci/isf-data-protection-operator@sha256:d6f1081340eed3b18e714acd86e4cc406b9c43ba92705cad76c7688c6d325581\"}]"
    elif [[ "$PATCH" == "SDS" ]]; then
        echo "Patching SDS clusterserviceversion/isf-operator.v2.9.0..."
        oc patch csv -n ${ISF_NS} isf-operator.v2.9.0  --type='json' -p="[{\"op\":\"replace\", \"path\":\"/spec/install/spec/deployments/$index/spec/template/spec/containers/0/image\", \"value\":\"cp.icr.io/cp/fusion-sds/isf-data-protection-operator@sha256:8d0d7ef3064271b948a4b9a3b05177ae959613a0b353062a286edb972112cfc4\"}]"
    fi

    echo "Scaling up isf-data-protection-operator-controller-manager deployment..."
    oc scale deployment -n $ISF_NS isf-data-protection-operator-controller-manager --replicas=1
else
    echo "ERROR: Failed to save original clusterserviceversion/isf-operator.v2.9.0. Skipped updates."
fi

AGENTCSV=$(oc -n "$BR_NS" get csv -o name | grep ibm-dataprotectionagent)
VERSION=$(oc -n "$BR_NS" get "$AGENTCSV" -o custom-columns=:spec.version --no-headers)
if [ -z "$VERSION" ] 
  then
    echo "ERROR: Could not get B&R version. Skipped updates"
elif [[ $VERSION != 2.9.0* ]]; then
    echo "This patch applies to B&R version 2.9.0 only, you have $VERSION. Skipped updates"
fi

if [[ "$VERSION" == 2.9.0* ]]; then
    if (oc get deployment -n $BR_NS transaction-manager -o yaml > $DIR/transaction-manager-deployment.save.yaml)
    then
        echo "Patching deployment/transaction-manager image..."
        oc set image deployment/transaction-manager -n $BR_NS transaction-manager=cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:124346800f9988b6c20d7fed5fae4c3a2728df8348cd96120b1eac1e71e641f0
    else
        echo "ERROR: Failed to save original transaction-manager deployment. Skipped updates."
    fi

    if (oc get deployment -n $BR_NS dbr-controller -o yaml > $DIR/dbr-controller-deployment.save.yaml)
    then
        echo "Patching deployment/dbr-controller image..."
        oc set image deployment/dbr-controller -n $BR_NS dbr-controller=cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:124346800f9988b6c20d7fed5fae4c3a2728df8348cd96120b1eac1e71e641f0
    else
        echo "ERROR: Failed to save original dbr-controller deployment. Skipped updates."
    fi

    if (oc -n "$BR_NS" get csv guardian-dm-operator.v2.9.0 -o yaml > $DIR/guardian-dm-operator.v2.9.0-original.yaml)
    then
      echo "Saved original configuration of guardian-dm-operator to $DIR/guardian-dm-operator.v2.9.0-original.yaml."
    else
      echo "ERROR: Failed to save original guardian-dm-operator.v2.9.0 csv. Skipped Patch."
    fi

    if (oc get configmap -n "$BR_NS" guardian-dm-image-config -o yaml > $DIR/guardian-dm-image-config-original.yaml)
    then
      echo "Scaling down guardian-dm-controller-manager deployment..."
      oc scale deployment guardian-dm-controller-manager -n "$BR_NS" --replicas=0
      oc set data -n "$BR_NS" cm/guardian-dm-image-config DM_IMAGE=icr.io/cpopen/guardian-datamover@sha256:4555ad7c0b4f95535a89cb9c6cd021f05d41a87aa1276d90e1e3a0b7b8d36799
      oc patch csv -n $BR_NS guardian-dm-operator.v2.9.0 --type='json' -p='[{"op":"replace", "path":"/spec/install/spec/deployments/0/spec/template/spec/containers/1/image", "value":"icr.io/cpopen/guardian-dm-operator@sha256:736babab4ab22bf3d2bdf6ea54100031a3e800cea9bf2226a6c1a80a69206ea6"}]'
      echo "Scaling up guardian-dm-controller-manager deployment..."
      oc scale deployment guardian-dm-controller-manager -n "$BR_NS" --replicas=1
    else
      echo "ERROR: Failed to save original configmap guardian-dm-image-config. skipped updates"
    fi

    # ensure configmap node-agent-config exists
    NODEAGENTCONFIGFOUND=$(testNodeAgentConfigMap "$BR_NS")
    # if node-agent-config is not found, create it with default values
    if [ $NODEAGENTCONFIGFOUND -eq 1 ]; then
      echo "ConfigMap node-agent-config not found, creating it."
      oc create configmap node-agent-config --namespace "$BR_NS"
      oc set data --namespace "$BR_NS" configmap/node-agent-config node-agent-config\.json='{"loadConcurrency":{"globalConfig":5},"podResources":{"cpuRequest":"2","cpuLimit":"4","memoryRequest":"4Gi","memoryLimit":"16Gi","ephemeralStorageRequest":"5Gi","ephemeralStorageLimit":"5Gi"}}'
    fi 
    
    # force a reconcile by the the dataprotection agent to any custom settings in the DataProtectionAgent
    # the reconcile only occurs when a field in the datamoverPodResources is updated, edit a field and then put back as is
    # if field isn't changed, then no reconcile occurs
    CPULIMIT=$(oc get dataprotectionagent dpagent --namespace "$BR_NS" -o jsonpath="{.spec.datamoverConfiguration.datamoverPodConfig.podResources.cpuLimit}")
    let CPULIMIT=$CPULIMIT+1
    oc patch dataprotectionagent dpagent --namespace "$BR_NS" --type='json' -p='[{"op": "replace", "path": "/spec/datamoverConfiguration/datamoverPodConfig/podResources/cpuLimit", "value":"'${CPULIMIT}'"}]'
    let CPULIMIT=$CPULIMIT-1
    oc patch dataprotectionagent dpagent --namespace "$BR_NS" --type='json' -p='[{"op": "replace", "path": "/spec/datamoverConfiguration/datamoverPodConfig/podResources/cpuLimit", "value":"'${CPULIMIT}'"}]'
    # node-agent pod must restart to pickup the change
    oc delete pod -l name=node-agent --namespace "$BR_NS"

    # replace the velero image
    if (oc --namespace "$BR_NS" get dpa velero -o yaml > $DIR/velero-original.yaml)
      then
        echo "Saved original OADP DataProtectionApplication configuration to $DIR/velero-original.yaml"
        oc patch dataprotectionapplication.oadp.openshift.io velero --namespace "$BR_NS" --type='json' -p='[{"op": "replace", "path": "/spec/unsupportedOverrides/veleroImageFqin", "value":"cp.icr.io/cp/bnr/fbr-velero@sha256:99c8ccf942196d813dae94edcd18ff05c4c76bdee2ddd2cbbe2da3fa2810dd49"}]'
        echo "Velero Deployement is restarting with replacement image"
        oc wait --namespace "$BR_NS" deployment.apps/velero --for=jsonpath='{.status.readyReplicas}'=1
    fi

    if [ -n "$HUB" ]
    then
      echo "Apply patches to hub..."
      if (oc get deployment -n $BR_NS job-manager -o yaml > $DIR/job-manager-deployment.save.yaml)
      then
        echo "Patching job-manager-deployment image..."
        oc patch deployment job-manager -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"job-manager-container","image":"cp.icr.io/cp/bnr/guardian-job-manager@sha256:7f31cb89d2279a3a54d85a23a4fd65c1745316c1d72c40ce8df32096469de47c"}]}}}}'
      else
        echo "ERROR: Failed to save original job-manager-deployment. Skipped updates."
      fi

      if (oc get deployment -n $BR_NS backup-service -o yaml > $DIR/backup-service-deployment.save.yaml)
      then
        echo "Patching backup-service-deployment image..."
        oc patch deployment backup-service -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"backup-service","image":"cp.icr.io/cp/bnr/guardian-backup-service@sha256:b310c5128b6b655e884a9629da7361c80625dd76378cea52eb6b351b3a70c139"}]}}}}'
      else
        echo "ERROR: Failed to save original backup-service-deployment. Skipped updates."
      fi
      patch_kafka_cr
      restart_deployments "$BR_NS" applicationsvc job-manager backup-service backup-location-deployment backuppolicy-deployment dbr-controller guardian-dp-operator-controller-manager transaction-manager guardian-dm-controller-manager
      restart_deployments "$ISF_NS" isf-application-operator-controller-manager
    fi
fi

echo "Please verify that these pods have successfully restarted after hotfix update in their corresponding namespace:"
printf "  %-25s: %s\n" "$ISF_NS" "isf-data-protection-operator-controller-manager"
if [[ "$VERSION" == 2.9.0* ]]; then
    printf "  %-25s: %s\n" "$BR_NS" "transaction-manager"
    printf "  %-25s: %s\n" "$BR_NS" "dbr-controller"
    printf "  %-25s: %s\n" "$BR_NS" "guardian-dm-controller-manager"
    printf "  %-25s: %s\n" "$BR_NS" "job-manager if HUB cluster"
fi
