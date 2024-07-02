#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <namespace> <labels> <image_keyword> 
    arguments: <namespace> is manadatory,  <labels> and <image_keyword> are optional
    i.e. 
         ./update_labels.sh uat                            # list the labels of the pvc's and deplyment's whose deployment has image mysql

         ./update_labels.sh uat redis                      # list the labels of the pvc's and deplyment's whose deployment has image redis

         ./update_labels.sh uat mysql fusion-label=mysql   # list the labels of the pvc's and deplyment's whose deployment has image mysql 
                                                           # and add the labels to the pvc and deployment if label is not there whose deployment has image mysql

         ./update_labels.sh uat redis fusion-label=redis   # list the labels of the pvc's and deplyment's whose deployment has image redis 
                                                           # and add the labels to the pvc and deployment if label is not there whose deployment has image redis
    "
    exit 1
fi


NAMESPACE="$1"
IMAGE_KEYWORD="${2:-mysql}"
LABEL="$3"
if echo "$LABEL" | grep -q -q '^[^=]*=[^=]*$'; then
    LABEL_KEY=$(echo "$LABEL" | cut -d '=' -f1)
    LABEL_VALUE=$(echo "$LABEL" | cut -d '=' -f2-)
fi

CLUSTER_INFO=$(oc cluster-info)

echo Namespace : $NAMESPACE
echo IMAGE_KEYWORD : $IMAGE_KEYWORD
echo LABEL : $LABEL
echo Cluster Info : $CLUSTER_INFO

# check if a deployment uses mysql or other db image
function is_db_deployment() {
    local RESOURCE_TYPE=$1
    local RESOURCE_NAME=$2
    local IMAGE=$(oc get $RESOURCE_TYPE $RESOURCE_NAME -n $NAMESPACE -o=jsonpath="{.spec.template.spec.containers[*].image}")
    

    if [[ $IMAGE == *$IMAGE_KEYWORD* ]]; then
        return 0  
    else
        return 1 
    fi
}

# get PVC labels or "NA" if no labels found
function get_pvc_labels() {
    local PVC=$1
    local PVC_LABELS=$(oc get pvc $PVC -n $NAMESPACE --no-headers -o=jsonpath='{.metadata.labels}')
    if [[ -z "$PVC_LABELS" ]]; then
        echo "NA"
    else
        echo "$PVC_LABELS"
    fi
}

# get PVC labels or "NA" if no labels found
function get_deployment_labels() {
    local DEPLOYMENT=$1
    local DEPLOYMENT_LABELS=$(oc get deployment $DEPLOYMENT -n $NAMESPACE --no-headers -o=jsonpath='{.metadata.labels}')
    if [[ -z "$DEPLOYMENT_LABELS" ]]; then
        echo "NA"
    else
        echo "$DEPLOYMENT_LABELS"
    fi
}

PVC_LIST=()
DEPLOYMENT_LIST=()

# get all deployments in the namespace
DEPLOYMENTS=$(oc get deployments -n $NAMESPACE --no-headers | awk '{print $1}')


for DEPLOYMENT in $DEPLOYMENTS
do  
    if is_db_deployment "deployment" $DEPLOYMENT; then
        PVC=$(oc get deployment $DEPLOYMENT -n $NAMESPACE -o=jsonpath="{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}")
        DEPLOYMENT_LIST+=("$DEPLOYMENT")
        if [[ -n "$PVC" ]]; then
            PVC_LIST+=("$PVC")
        fi
    fi
done

echo
# add labels to pvc and deployment
if [[ -z "$LABEL_KEY" && -z "$LABEL_VALUE" ]]; then
    echo "No label provided"
else
    for PVC in "${PVC_LIST[@]}"
    do  
        echo Trying to add label: $LABEL to pvc $PVC 
        oc label --overwrite=true pvc $PVC "$LABEL" -n $NAMESPACE
        echo
    done
    for DEPLOY in "${DEPLOYMENT_LIST[@]}"
    do  
        echo Trying to add label: $LABEL to deploymnet $DEPLOY 
        oc label --overwrite=true deployment $DEPLOY "$LABEL" -n $NAMESPACE
        echo
    done
fi

echo
# print PVCs and their labels
for PVC in "${PVC_LIST[@]}"
do
    PVC_LABELS=$(get_pvc_labels $PVC)
    echo "PVC: $PVC" 
    echo " Labels: $PVC_LABELS"
    echo
done


echo
# print deployment and their labels
for DEPLOYMENT in "${DEPLOYMENT_LIST[@]}"
do
    DEPLOYMENT_LABELS=$(get_deployment_labels $DEPLOYMENT)
    echo "Deployment: $DEPLOYMENT" 
    echo " Labels: $DEPLOYMENT_LABELS"
    echo
done
