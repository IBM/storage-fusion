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

echo "================================================================="
echo "Cleanup Fusion odf"
echo "This will only uninstall Fusion Datafoundation service"
echo "This will not uninstall other services or Fusion itself"
echo "================================================================="

FUSION_NS="ibm-spectrum-fusion-ns"
if [[ $# -gt 0 ]]; then
	FUSION_NS=$1
fi
echo using fusion namespace "$FUSION_NS"

printf "\n------check Fusion SDS or HCI------\n"
result=$(oc get deployment isf-cns-operator-controller-manager -o jsonpath='{.metadata.annotations.environment}' -n "$FUSION_NS")
is_hci=0
if [[ $result == "HCI" ]]; then
	echo "this is hci"
	is_hci=1
else
	echo "this is sds"
fi

printf "\n------scale isf-cns deployment to 0 replica------\n"
oc scale deployment --replicas=0 isf-cns-operator-controller-manager -n "$FUSION_NS"

printf "\n------delete odf fusionserviceinstance ------\n"
oc delete fusionserviceinstance odfmanager -n "$FUSION_NS"

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
	exit 1
fi

# printf "\n------scale isf-prereq deployment to 0 replica------\n"
# oc scale deployment --replicas=0 isf-prereq-operator-controller-manager -n "$FUSION_NS"

printf "\n------delete storageclass ibm-spectrum-fusion-mgmt-sc------\n"
oc delete sc ibm-spectrum-fusion-mgmt-sc

# printf "\n------scale isf-prereq deployment to 1 replica------\n"
# oc scale deployment --replicas=1 isf-prereq-operator-controller-manager -n "$FUSION_NS"

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
