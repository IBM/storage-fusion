#!/usr/bin/env bash
# Script only cleans the ODF

set -u

echo "================================================================="
echo "Cleanup Fusion odf"
echo "This will only uninstall Fusion Datafoundation service"
echo "This will not uninstall other services or Fusion itself"
echo "================================================================="

# Prompt the user to confirm if ODF label is removed
read -p "Confirm if label isf.ibm.com/fusion-fdf is removed from the HCP cluster (y/n): " response

# Check the response
if [ "$response" == "n" ]; then
    echo "Please remove the label isf.ibm.com/fusion-fdf for the current HCP cluster before proceeding.........."
    exit 1
elif [ "$response" != "y" ] && [ "$response" != "n" ]; then
    echo "Invalid input. Please enter 'y' or 'n'."
    exit 1
fi

FUSION_NS="ibm-spectrum-fusion-ns"
if [[ $# -gt 0 ]]; then
    FUSION_NS=$1
fi
echo using fusion namespace "$FUSION_NS"

printf "\n------check Fusion SDS or HCI------\n"
result=$(oc get deployment isf-cns-operator-controller-manager -o jsonpath='{.metadata.annotations.environment}'  -n "$FUSION_NS")
is_hci=0
if [[ $result == "HCI" ]]; then
    echo "this is hci"
    is_hci=1
    exit 1
else
    echo -e "this is sds\n"
fi

# Check for PVC's or any workload consuming ODF before cleaning the ODF
# Define an array of storage classes
storage_classes=("ocs-storagecluster-ceph-rbd" "ibm-spectrum-fusion-mgmt-sc" "ocs-storagecluster-cephfs")

# array to store the list of volume snapshots found for given pvc
volume_snapshots=()
pvcs_bound_to_pods=()

# Iterate over each storage class
for storage_class in "${storage_classes[@]}"; do
    echo "Fetching PVCs with storage class '$storage_class'"
    # Store the command output in a variable
    pvc_lists=$(oc get pvc --all-namespaces -o=json | jq -c --arg storage_class "$storage_class" '.items[] | select(.status.phase == "Bound" and .spec.storageClassName == $storage_class) | {pvc_name: .metadata.name, namespace: .metadata.namespace}')

    # Check if the variable is not empty
    if [ -n "$pvc_lists" ]; then
        echo "PVCs found consuming storage class "$storage_class""
        echo -e "$pvc_lists\n"

        # Iterate over each line in the command output
        echo "Fetching snapshots and pods consuming storage class "$storage_class""
        while IFS= read -r line; do
            # Extract PVC name and namespace from each line
            pvc_name=$(echo "$line" | jq -r '.pvc_name')
            namespace=$(echo "$line" | jq -r '.namespace')

            # Fetch PVC snapshots in the namespace
            volume_snapshot=$(oc get volumesnapshot --namespace "$namespace" -o=json | jq -c --arg pvc_name "$pvc_name" '.items[] | select(.spec.source.persistentVolumeClaimName == $pvc_name) | {snapshot_name: .metadata.name, source_pvc: .spec.source.persistentVolumeClaimName, namespace: .metadata.namespace}')
            if [ -n "$volume_snapshot" ]
            then
                echo "Found Snapshot for PVC '$pvc_name' snapshot $volume_snapshot"
                volume_snapshots+=($volume_snapshot)
            fi

            attached_pod=$(oc get pods --namespace "$namespace" -o=json | jq -c --arg pvc_name "$pvc_name" '.items[] | select(.spec.volumes[].persistentVolumeClaim.claimName == $pvc_name) | {name: .metadata.name, namespace: .metadata.namespace, claimName: .spec.volumes[] | select(.persistentVolumeClaim.claimName == $pvc_name) | .persistentVolumeClaim.claimName}' 2>/dev/null)
            if [ -n "$attached_pod" ]
            then
                echo "Found pod $attached_pod"
                pvcs_bound_to_pods+=($attached_pod)
            fi
        done <<< "$pvc_lists"
    else
        echo "No PVCs found with storage class '$storage_class'."
    fi
done

if [ ${#volume_snapshots[@]} -ne 0 ] ; then
    printf "\nRemove the below Snapshots of the PVC's created before cleaning up the odf\n"
    echo -e "${volume_snapshots[@]}\n"
fi

if [ ${#pvcs_bound_to_pods[@]} -ne 0 ] ; then
    printf "\nRemove the below workloads before cleaning up the odf\n" 
    echo -e "${pvcs_bound_to_pods[@]}\n"
fi

if [[ ${#volume_snapshots[@]} -gt 0 || ${#pvcs_bound_to_pods[@]} -gt 0 ]]; then
    printf "Remove the above workload/snapshot\n"
    exit 1
fi

printf "\n------scale isf-cns deployment to 0 replica------\n"
oc scale deployment --replicas=0 isf-cns-operator-controller-manager -n "$FUSION_NS"

printf "\n------delete odfmanager------\n"
oc delete odfmanager odfmanager

printf "\n------delete odfcluster------\n"
oc delete odfcluster odfcluster -n "$FUSION_NS"

if [[ is_hci -eq 1 ]]; then
    printf "\n------scale isf-bkprstr deployment to 0 replica------\n"
    oc scale deployment --replicas=0 isf-bkprstr-operator-controller-manager -n "$FUSION_NS"

    printf "\n------scale logcollector deployment to 0 replica------\n"
    oc scale deployment --replicas=0 logcollector -n "$FUSION_NS"

    printf "\n------delete Fusion internal used PVC isf-bkprstr-claim logcollector------\n"
    oc delete pvc isf-bkprstr-claim logcollector -n "$FUSION_NS"
fi

CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)
"$CURRENT_DIR"/delete-odf.sh

result=$?
if [[ $result -ne 0 ]]; then
    echo ""
    echo "================================================================="
    echo "Delete ODF failed"
    echo "Please check failure and retry"
    echo "================================================================="
    exit
fi

# printf "\n------scale isf-prereq deployment to 0 replica------\n"
# oc scale deployment --replicas=0 isf-prereq-operator-controller-manager -n "$FUSION_NS"

printf "\n------delete storageclass ibm-spectrum-fusion-mgmt-sc------\n"
oc delete sc ibm-spectrum-fusion-mgmt-sc

# printf "\n------scale isf-prereq deployment to 1 replica------\n"
# oc scale deployment --replicas=1 isf-prereq-operator-controller-manager -n "$FUSION_NS"

printf "\n------delete odf fusionserviceinstance ------\n"
oc delete fusionserviceinstance odfmanager -n "$FUSION_NS"

printf "\n------delete fdf catalogsource ------\n"
oc delete catalogsource isf-data-foundation-catalog -n openshift-marketplace

printf "\n------scale isf-cns deployment back to 1 replica------\n"
oc scale deployment --replicas=1 isf-cns-operator-controller-manager -n "$FUSION_NS"

if [[ is_hci -eq 1 ]]; then
    printf "\n------recreate the PVC isf-bkprstr-claim and logcollector------\n"
    oc apply -f - <<EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:  
    name: isf-bkprstr-claim
    namespace: ibm-spectrum-fusion-ns 
spec:
    accessModes:
        - ReadWriteMany
    resources:
        requests:
            storage: 25Gi  
    storageClassName: ibm-spectrum-fusion-mgmt-sc
    volumeMode: Filesystem
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:  
    name: logcollector 
    namespace: ibm-spectrum-fusion-ns 
spec:
    accessModes:
        - ReadWriteMany
    resources:
        requests:
            storage: 25Gi  
    storageClassName: ibm-spectrum-fusion-mgmt-sc
    volumeMode: Filesystem
EOF

    printf "\n------scale isf-bkprstr deployment to 1 replica------\n"
    oc scale deployment --replicas=1 isf-bkprstr-operator-controller-manager -n ibm-spectrum-fusion-ns

    printf "\n------scale logcollector deployment to 2 replica------\n"
    oc scale deployment --replicas=2 logcollector -n ibm-spectrum-fusion-ns
fi

echo "================================================================="
echo "Cleanup Fusion with ODF completed in $(date +"%F %Z")"
echo "================================================================="
