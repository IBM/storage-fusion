#!/usr/bin/env bash
set -eu

# GUARD CLAUSE: Prevent sourcing this file multiple times
if [[ -n "${LOADED_DF_UTILS_SH:-}" ]]; then
    return 0
fi
export LOADED_DF_UTILS_SH=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/../lib/utils.sh"

# shellcheck source=config/config.env
source "$ROOT_DIR/config/config.env"

#========================================
# OpenShift Data Foundation Utility Functions
#========================================
# Purpose: OpenShift Data Foundation (ODF) / Ceph operations
#
# Functions:
#   1. is_fdf_configured()
#   2. configure_fdf()
#   3. patch_rbd_csi_driver()
#   4. create_pvc_local_disks()
#   5. create_expose_rbd_daemonset()
#   6. convert_hdd_to_ssd()
#========================================

#----------------------------------------
# Function: Check if FDF is already configured
#----------------------------------------
is_fdf_configured() {
	local status
	status=$(oc get "$STORAGE_CLUSTER" "$OCS_CLUSTER_NAME" -n "$OCS_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)

	if [[ "$status" == "Ready" ]]; then
		echo "ready"
	fi
}

#----------------------------------------
# Function: Generate LocalVolumeSet Manifest
#----------------------------------------
gen_local_volume_set() {
	local localvolumeset_yaml
	localvolumeset_yaml=$(cat <<EOF
apiVersion: local.storage.openshift.io/v1alpha1
kind: LocalVolumeSet
metadata:
  name: ${OCS_BACKING_STORAGECLASS}
  namespace: openshift-local-storage
spec:
  nodeSelector:
    nodeSelectorTerms:
      - matchExpressions: []
  storageClassName: ${OCS_BACKING_STORAGECLASS}
  volumeMode: Block
  deviceInclusionSpec:
    deviceTypes:
      - disk
      - part
EOF
)

	# Add deviceMechanicalProperties only if ODF_ALLOW_ROTATIONAL is not set
	if [[ "${ODF_ALLOW_ROTATIONAL}" != "true" ]]; then
		localvolumeset_yaml=$(echo "$localvolumeset_yaml" | yq eval '.spec.deviceInclusionSpec.deviceMechanicalProperties = ["NonRotational"]' -)
	fi

	match_expressions="$(match_expressions_list "${STORAGE_NODE_MATCH}")"
	echo "$localvolumeset_yaml" | yq eval ".spec.nodeSelector.nodeSelectorTerms[0].matchExpressions = ${match_expressions}" - || {
		logger error "Failed to generate LocalVolumeSet"
		return 1
	}
}

#----------------------------------------
# Function: Configure FDF
#----------------------------------------
configure_fdf() {
	convert_hdd_to_ssd

	logger info "Configuring FDF..."

	localvolumeset_yaml="$(gen_local_volume_set)" || return 1
	echo "$localvolumeset_yaml" | oc apply -f - || {
		logger error "Failed to apply LocalVolumeSet"
		return 1
	}

	local retry_count=0
	while true; do
		local no_of_disks
		no_of_disks=$(oc get localvolumeset "${OCS_BACKING_STORAGECLASS}" -n openshift-local-storage \
			-o jsonpath='{.status.totalProvisionedDeviceCount}' 2>/dev/null)
		if [[ "$no_of_disks" -gt 2 ]]; then
			logger success "LocalVolumeSet ${OCS_BACKING_STORAGECLASS} provisioned $no_of_disks PVs."
			export NO_OF_OSDS="$no_of_disks"
			break
		fi

		((++retry_count))
		if [[ $retry_count -ge $STORAGE_CLUSTER_RETRY_COUNT ]]; then
			logger error "Timeout: LocalVolumeSet not Available after $((STORAGE_CLUSTER_RETRY_COUNT)) seconds."
			return 1
		fi

		sleep 1
	done


	label_nodes "$CLUSTER_OCS_OPENSHIFT_IO/$OCS_NAMESPACE=" "$(get_nodes)"

	envsubst <templates/storagecluster.yaml | oc apply -f - || {
		logger error "Failed to apply StorageCluster"
		return 1
	}

	logger success "FDF configuration applied successfully."

	local retry_count=0
	while true; do
		if oc get "$STORAGE_CLUSTER" "$OCS_CLUSTER_NAME" -n "$OCS_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Ready"; then
			logger success "StorageCluster is Ready."
			break
		fi

		((++retry_count))
		if [[ $retry_count -ge $STORAGE_CLUSTER_RETRY_COUNT ]]; then
			logger error "Timeout: StorageCluster did not reach Ready phase after $((STORAGE_CLUSTER_RETRY_COUNT * RETRY_INTERVAL)) seconds."
			return 1
		fi

		logger info "StorageCluster not Ready yet... retrying in ${RETRY_INTERVAL}s ($retry_count/$STORAGE_CLUSTER_RETRY_COUNT)"
		sleep "$RETRY_INTERVAL"
	done
}

#----------------------------------------
# Function: Patch Ceph CSI drivers (RBD and CephFS)
#----------------------------------------
patch_ceph_csi_drivers() {
	drivers=("rbd" "cephfs")
	for driver in "${drivers[@]}"; do
		if oc get -n "$OCS_NAMESPACE" "driver.csi.ceph.io/openshift-storage.${driver}.csi.ceph.com" &>/dev/null; then
			patch_ceph_csi_driver "$driver"
		fi
	done
}

#----------------------------------------
# Function: Patch individual Ceph CSI driver
#----------------------------------------
patch_ceph_csi_driver() {
	driver="$1"
	oc patch -n "$OCS_NAMESPACE" \
		"driver.csi.ceph.io/openshift-storage.${driver}.csi.ceph.com" \
		--type=merge \
		--patch-file <(cat <<EOF
spec:
  nodePlugin:
    kubeletDirPath: ${KUBELET_ROOT_DIR_PATH}
    tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
        operator: Exists
      - effect: NoSchedule
        key: node.ocs.openshift.io/storage
        operator: Equal
        value: "true"
EOF
)
}

#----------------------------------------
# Function: Create backing StorageClass for LocalDisks
#----------------------------------------
create_scale_rbd_sc() {
	local base_storage_class
	base_storage_class="$(oc get storageclass "${LOCAL_DISK_PVC_STORAGE_CLASS_SOURCE}" -oyaml 2> /dev/null)"
	cat <<EOF | oc apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    description: Provides Ceph RBD volumes with 'abort_on_full'
    reclaimspace.csiaddons.openshift.io/schedule: '@weekly'
  name: ${LOCAL_DISK_PVC_STORAGE_CLASS}
parameters:
  $(get_param_value "${base_storage_class}" "clusterID")
  $(get_param_value "${base_storage_class}" "csi.storage.k8s.io/controller-expand-secret-name")
  $(get_param_value "${base_storage_class}" "csi.storage.k8s.io/controller-expand-secret-namespace")
  $(get_param_value "${base_storage_class}" "csi.storage.k8s.io/fstype")
  $(get_param_value "${base_storage_class}" "csi.storage.k8s.io/node-stage-secret-name")
  $(get_param_value "${base_storage_class}" "csi.storage.k8s.io/node-stage-secret-namespace")
  $(get_param_value "${base_storage_class}" "csi.storage.k8s.io/provisioner-secret-name")
  $(get_param_value "${base_storage_class}" "csi.storage.k8s.io/provisioner-secret-namespace")
  $(get_param_value "${base_storage_class}" "pool")
  $(get_param_value "${base_storage_class}" "imageFormat")
  imageFeatures: layering,deep-flatten
  mapOptions: abort_on_full
$(get_param_value "${base_storage_class}" "provisioner")
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
}

#----------------------------------------
# Function: Delete backing StorageClass for LocalDisks
#----------------------------------------
delete_scale_rbd_sc() {
	oc delete storageclass "${LOCAL_DISK_PVC_STORAGE_CLASS}" --ignore-not-found >/dev/null 2>&1
}

#----------------------------------------
# Function: Create PVCs for local disks
#----------------------------------------
create_pvc_local_disks() {
	local i=1
	local pvc_names
	while (( i <= NO_OF_RBD_PVCS )); do
		local pvc_name="local-disk${i}"
		cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: ${LOCAL_STORAGE_PROJECT}
spec:
  accessModes:
    - ${LOCAL_DISK_PVC_ACCESS_MODE}
  resources:
    requests:
      storage: ${FILESYSTEM_CAPACITY}
  storageClassName: ${LOCAL_DISK_PVC_STORAGE_CLASS}
  volumeMode: ${LOCAL_DISK_PVC_VOLUME_MODE}
EOF
		pvc_names+="${pvc_name} "
		((++i))
	done

	local interval=10 # 10 seconds
	while true; do
		local unbound_pvcs=""
		local i=1

		for pvc_name in ${pvc_names}; do
			local pvc_phase
			pvc_phase="$(oc get pvc -n "${LOCAL_STORAGE_PROJECT}" "${pvc_name}" -ojsonpath='{.status.phase}')"
			if [[ "${pvc_phase}"  != "Bound" ]]; then
				unbound_pvcs+="${pvc_name} "
			fi
		done

		if [[ "${unbound_pvcs}" == "" ]]; then
			logger success "LocalDisk RBD PVCs provisioned successfully."
			break
		else
			logger info "Waiting on RBD PVCs to bind: ${unbound_pvcs}..."
		fi

		sleep ${interval}
	done
}

#----------------------------------------
# Function: Create DaemonSet to expose Ceph RBD PVCs as block devices
#----------------------------------------
create_expose_rbd_daemonset() {
	if envsubst <templates/daemonset_expose_rbd.yaml | oc apply -f - >/dev/null 2>&1; then
		logger success "DaemonSet applied successfully in namespace $LOCAL_STORAGE_PROJECT."
	else
		logger error "Failed to create DaemonSet to expose Ceph RBD PVCs."
		return 1
	fi

	local retry_count=0
	while true; do
		local desired ready
		desired=$(oc get daemonset "$EXPOSE_RBD_DS_NAME" -n "$LOCAL_STORAGE_PROJECT" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
		ready=$(oc get daemonset "$EXPOSE_RBD_DS_NAME" -n "$LOCAL_STORAGE_PROJECT" -o jsonpath='{.status.numberReady}' 2>/dev/null)

		if [[ -n "$desired" && "$desired" -eq "$ready" ]]; then
			logger success "All DaemonSet pods are Ready ($ready/$desired)."
			break
		fi

		((++retry_count))
		if [[ $retry_count -ge $STORAGE_CLUSTER_RETRY_COUNT ]]; then
			logger error "Timeout: DaemonSet pods did not become Ready after $((STORAGE_CLUSTER_RETRY_COUNT * RETRY_INTERVAL)) seconds."
			return 1
		fi
		sleep "$RETRY_INTERVAL"
	done
}

#----------------------------------------
# Function: Convert HDDs to SSDs (if env var set)
#----------------------------------------
convert_hdd_to_ssd() {
	[[ -z "${CONVERT_HDD_TO_SSD:-}" ]] && return 0
	logger warn "Setting all block devices as non-rotational..."
	for n in $(get_nodes); do
		oc debug "no/$n" -- chroot /host bash -c '
			for f in /sys/block/*/queue/rotational; do
				[[ $(cat "$f") == 1 ]] && echo 0 > "$f"
			done
		' >/dev/null 2>&1
	done
}
