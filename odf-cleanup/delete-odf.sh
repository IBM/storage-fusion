#!/usr/bin/env bash
# start_Copyright_Notice
# Licensed Materials - Property of IBM

# IBM Spectrum Fusion 5900-AOY
# (C) Copyright IBM Corp. 2022 All Rights Reserved.

# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

set -u

# shellcheck source=/dev/null
source "common.sh"

echo
echo "================================================================="
echo "Cleanup odf"
echo "================================================================="

result=$(oc get ns openshift-storage --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ $result -eq 0 ]]; then
    info "There is no openshift-storage namespace"
    #exit
fi

# delete ODF's storage cluster, UI Storage->Data Foundation -> Storage Systems
printf "\n------annotate storagecluster------\n"
## annotate storagecluster
## for internal storage, clustername=ocs-storagecluster
## for external storage, clustername=ocs-external-storagecluster
result=$(oc get storagecluster -n openshift-storage --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [[ $result -eq 0 ]]; then
    info "There is no storage cluster"
    #exit
else
    storageclustername=$(oc get storagecluster -n openshift-storage -o name)
    oc annotate "$storageclustername" -n openshift-storage  uninstall.ocs.openshift.io/mode="forced" --overwrite 
    info "Storage cluster has been patched as uninstall.ocs.openshift.io/mode=\"forced\" successfully"
fi

printf "\n------identify the PVCs and OBCs provisioned using OpenShift Data Foundation------\n"
RBD_PROVISIONER="rbd.csi.ceph.com"
CEPHFS_PROVISIONER="cephfs.csi.ceph.com"
NOOBAA_PROVISIONER="noobaa.io/obc"
RGW_PROVISIONER="ceph.rook.io/bucket"
NOOBAA_DB_PVC="noobaa-db"
NOOBAA_BACKINGSTORE_PVC="noobaa-default-backing-store-noobaa-pvc"
# Find all the OCS StorageClasses
OCS_STORAGECLASSES=$(oc get storageclasses | grep -e "$RBD_PROVISIONER" -e "$CEPHFS_PROVISIONER" -e "$NOOBAA_PROVISIONER" -e "$RGW_PROVISIONER" | awk '{print $1}')
# List PVCs in each of the StorageClasses

# Remove all the pvc's
for SC in $OCS_STORAGECLASSES
do
    # Get PVCs with the specified storage class
    PVC_LIST=$(oc get pvc --all-namespaces -o=jsonpath='{range .items[?(@.spec.storageClassName=="'$SC'")]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}')

    if [ -n "$PVC_LIST" ]
    then    
        # Loop through the PVCs and delete them
        while IFS= read -r pvc; do
            namespace=$(echo "$pvc" | cut -d ':' -f 1)
            pvc_name=$(echo "$pvc" | cut -d ':' -f 2)
            echo "Deleting PVC $pvc_name in namespace $namespace"
            oc delete pvc "$pvc_name" -n "$namespace"
        done <<< "$PVC_LIST"
    fi
done

result=$(oc get ns openshift-storage-client --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ $result -eq 0 ]]; then
    info "There is no openshift-storage-client namespace"
else
    printf "\n------delete storageclassclaim------\n"
    oc delete storageclassclaim --all --wait=true --timeout=5m

    if [[ $? -ge 1 ]]; then
        warn "storageclassclaim couldn't be deleted within 5 minutes"
        info "remove storageclassclaim finalizers"
        oc get storageclassclaim -o name | xargs -I {} kubectl patch {} --type merge -p '{"metadata":{"finalizers": []}}'
        warn "please verify if storageclassclaims are deleted later"
    else
        info "storageclassclaims have been deleted successfully"
    fi

    printf "\n------delete storageclient------\n"
    oc delete storageclient storageclient -n openshift-storage-client

    printf "\n------remove csiaddonsnode finalizer------\n"
    oc get csiaddonsnode -n openshift-storage-client -o name | xargs -I {} kubectl patch {} -n openshift-storage-client --type merge -p '{"metadata":{"finalizers": []}}'

    printf "\n------delete openshift-storage-client namespace------\n"
    oc delete ns openshift-storage-client
fi

result=$(oc get ns openshift-storage --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ $result -eq 0 ]]; then
    info "There is no openshift-storage namespace"
else
    printf "\n------delete storageconsumer------\n"
    ## delete storageconsumer
    result=$(oc get storageconsumer -n openshift-storage --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ $result -eq 0 ]]; then
        info "There is no storageconsumer"
    else
        oc delete -n openshift-storage storageconsumer --all --wait=true
        if [[ $? -ge 1 ]]; then
            error "error to delete storageconsumer"
            exit 1
        else
            info "storageconsumer has been deleted successfully"
        fi
    fi

    printf "\n------delete storagesystem------\n"
    ## delete storagesystem
    result=$(oc get storagesystem -n openshift-storage --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ $result -eq 0 ]]; then
        info "There is no storage system"
    else
        # wait for 5 mins for storage cluster deletion
        # oc wait --for=delete storagesystem ocs-storagecluster-storagesystem -n openshift-storage --timeout=300s

        oc delete -n openshift-storage storagesystem --all --wait=true
        if [[ $? -ge 1 ]]; then
            error "Storage system couldn't be deleted"
            exit 1
        else
            info "Storage system has been deleted successfully"
        fi
    fi

    printf "\n------check cleanup pods------\n"
    ocpversion=$(oc get clusterversion --no-headers| awk '{print $2}')
    ocpversion_major=$(echo "$ocpversion"|cut -d "." -f1)
    ocpversion_minor=$(echo "$ocpversion"|cut -d "." -f2)
    if [[ ocpversion_major -ne 4 ]]; then 
        echo "ocp version is $ocpversion, not expected!"
        exit 1
    fi
    if [[ ocpversion_minor -ge 14 ]]; then 
        echo "ocp version is $ocpversion"
        echo "skip check cleanup pods"
    else
        echo "ocp version is $ocpversion" 
        echo "sleep 60s to wait for cleanup pods to finish their job"
        sleep 60

        result=$(oc get pods -n openshift-storage | grep -c cluster-cleanup-job)
        if [[ $result -eq 0 ]]; then
            info "No cleanup pods were found, better to wait and retry again."
            echo 
        else
            completed_result=$(oc get pods -n openshift-storage | grep cluster-cleanup-job | grep -c Completed)
            if [[ $completed_result -eq $result ]]; then
                info "cleanup jobs are all done"
            else
                error "not all cleanup jobs are completed, please wait and retry again."
                exit 1
            fi
        fi
    fi

    printf "\n------delete openshift-storage namespace------\n"
    oc project default
    oc delete ns openshift-storage --wait=true --timeout=5m
    if [[ $? -ge 1 ]]; then
        warn "openshift-storage namespace couldn't be deleted within 5 minutes"
        info "trying to delete all pods in openshift-storage namespace forcefully"
        oc delete pods --force --all -n openshift-storage
        warn "please verify if openshift-storage namespace is deleted later"
    else
        info "openshift-storage namespace has been deleted successfully"
    fi

fi

printf "\n------clean up /var/lib/rook dir on each node------\n"
for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/"$i" -- chroot /host  rm -rf /var/lib/rook; done

#for i in $(oc get node -l node-role.kubernetes.io/worker= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/"$i" -- chroot /host  ls -l /var/lib/rook; done

# Chech whether encryption is enabled, if yes, need to override those disks
printf '\n------check Encryption disks------\n'
info "Start checking whether there are encrypted disks..."
result=$(for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/"$i" -- chroot /host dmsetup ls; done)
encryptedflag="dmcrypt"

if [[ $result == *$encryptedflag* ]]; then
    echo "Encryption is enabled and disks are encrypted."
    echo "Those disks are:"
    echo "$result"
    echo ""
    echo "Try to clean up encrypted disks. "
    for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); 
    do 
        echo "working on node $i, press ctrl+c only ONCE if this clean up disk process takes too long"
        oc debug node/"$i" -- chroot /host dmsetup ls| awk '{print $1}' | xargs -I {}  oc debug node/"$i" -- chroot /host cryptsetup luksClose --debug --verbose {}; 
    done
    info "Clean up encrypted disks done"
    # info $(echo $result | grep -E 'Starting|dmcrypt')
else
    info "Encryption is not enabled or already cleaned up"
fi


# printf "\n------delete localvolumeset------\n"
# result=$(oc get localvolumeset -n openshift-local-storage --no-headers 2>/dev/null | wc -l | tr -d ' ')
# if [[ $result -eq 0 ]]; then
#     info "There is no localvolumeset detected"
# else
#     info "localvolumeset detected, start to remove local storage"
#     CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)
#     "$CURRENT_DIR"/delete-local-storage.sh
# fi

printf "\n------check pv in released state------\n"
oc get pv|grep -i released

printf "\n------check openshift-storage namespace------\n"
oc get ns | grep openshift-storage

printf "\n------unlabel/untaint nodes------\n"
oc label nodes  --all cluster.ocs.openshift.io/openshift-storage- &>/dev/null 
oc label nodes  --all topology.rook.io/rack- &>/dev/null
oc adm taint nodes --all node.ocs.openshift.io/storage- &>/dev/null

echo "================================================================="
echo "Cleanup ODF completed in $(date +"%F %Z")"
echo "================================================================="
