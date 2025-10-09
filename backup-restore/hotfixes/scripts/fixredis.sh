#!/bin/bash 

# Make sure you are logged into the correct cluster.
oc whoami > /dev/null || err_exit "Not logged in a cluster"


BNR_NS=$(oc get catsrc -A -o custom-columns=:metadata.namespace --no-headers --field-selector metadata.name=ibm-fusion-backup-restore-catalog)

IDP_SERVER_POD=$(oc get pods -n $BNR_NS | awk '{print $1}' | grep -i ibm-dataprotectionserver-controller-manager)

STORAGE_CLASS=$(oc get dataprotectionserver ibm-backup-restore-service-instance -n $BNR_NS -o yaml | grep storageClass |  awk -F' ' '{print $2}')

# Get the Redis CR yaml from idp-server pod
if [ -f "guardian-redis-cr.yaml" ]; then
      rm "guardian-redis-cr.yaml"
    fi
oc exec -c manager -n $BNR_NS $IDP_SERVER_POD -- cat /k8s/redis/guardian-redis-cr.yaml >  ./guardian-redis-cr.yaml

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


oc scale deployment -n $BNR_NS redis-operator-controller-manager --replicas=0

# Delete any redis-dockercfg* and redis-token* secrets that might have been constantly
# generated when redis-controller was in error state
oc get secrets -o name | grep redis-dockercfg | xargs oc delete
oc get secrets -o name | grep redis-token | xargs oc delete

# Create Redis CR
oc delete redis redis -n $BNR_NS --timeout=60s
if oc get redis redis -n $BNR_NS >/dev/null 2>&1; then
   oc patch --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' redis redis -n $BNR_NS
   oc delete redis redis -n $BNR_NS
fi

oc scale deployment -n $BNR_NS redis-operator-controller-manager --replicas=1
oc wait -n $BNR_NS deployment/redis-operator-controller-manager --for=jsonpath='{.status.readyReplicas}'=1

# Recreate Redis CR using updated yaml
oc apply -n $BNR_NS -f guardian-redis-cr.yaml
echo Finished creating Redis CR
