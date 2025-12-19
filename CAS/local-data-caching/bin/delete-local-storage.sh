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

echo
echo "================================================================="
echo "Cleanup local storage"
echo "================================================================="

printf "\n------delete localvolumesets------\n"
oc delete localvolumesets.local.storage.openshift.io --all -n openshift-local-storage

printf "\n------delete local storage pv and storageclass------\n"
sc_list=$(oc get sc | grep "kubernetes.io/no-provisioner" | awk '{print $1}')
for i in $sc_list; do
	oc get pv | grep "$i" | awk '{print $1}' | xargs oc delete pv
	oc delete sc "$i"
done

printf "\n------delete the symlinks created by the LocalVolumeSet------\n"
for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do
	oc debug node/"$i" -- chroot /host rm -rfv /mnt/local-storage/
done

printf "\n------delete openshift-local-storage namespace------\n"
result=$(oc get ns openshift-local-storage --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ $result -eq 0 ]]; then
	info "There is no ns openshift-local-storage"
else
	oc delete ns openshift-local-storage --wait=true --timeout=5m
fi

echo "================================================================="
echo "Cleanup local storage completed in $(date +"%F %Z")"
echo "================================================================="
