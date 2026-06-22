#!/usr/bin/env bash
set -eu

# GUARD CLAUSE: Prevent sourcing this file multiple times
if [[ -n "${LOADED_SCALE_UTILS_SH:-}" ]]; then
    return 0
fi
export LOADED_SCALE_UTILS_SH=1

#========================================
# IBM Spectrum Scale Utility Functions
#========================================
# Purpose: IBM Spectrum Scale cluster and filesystem operations
#
# Functions:
#   RBD Device Discovery (moved from df_utils.sh):
#     1. get_rbd_pod()
#     2. get_rbd_devices()
#     3. get_pool_and_img_from_pv()
#     4. get_device_id()
#     5. get_device_ids_for_local_disks()
#
#   Scale Cluster Operations:
#     6. is_scale_cluster_created()
#     7. create_scale_cluster()
#     8. verify_scale_cluster()
#     9. patch_device_regex_in_scale_cluster()
#
#   LocalDisk Management:
#    10. create_local_disks()
#    11. ensure_local_disks()
#    12. validate_local_disks_usage()
#
#   FileSystem Operations:
#    13. create_fs()
#    14. verify_fs()
#
#   Scale Core Operations:
#    15. get_scale_core_pod()
#    16. scale_core_exec()
#
#   AFM Configuration:
#    17. configure_afm()
#    18. verify_afm_config()
#
#   Configuration:
#    19. scale_set_config()
#========================================

#========================================
# RBD Device Discovery Functions
#========================================
# These functions were moved from df_utils.sh because they are
# exclusively used by Scale operations for device discovery.
#========================================

#----------------------------------------
# Function: Get RBD nodeplugin pod name (with fallback)
#----------------------------------------
get_rbd_pod() {
	local pod
	local node="$1"

	logger info "Identifying pod for RBD nodeplugin pod on node ${node}"
	# Try newer label first
	pod=$(oc get pod -n "$OCS_NAMESPACE" -l "$RBD_POD_NEW_LABEL" \
		--field-selector "spec.nodeName=$node" \
		-o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
	logger info "Using the latest RBD CSI labels, pod ${pod} was identified as running on node ${node}"

	# Fallback for older label
	if [[ -z "$pod" ]]; then
		pod=$(oc get pod -n "$OCS_NAMESPACE" -l "$RBD_POD_OLD_LABEL" \
			--field-selector "spec.nodeName=$node" \
			-o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
		logger info "Using the old RBD CSI labels, pod ${pod} was identified as running on node ${node}"
	fi

	if [[ -z "$pod" ]]; then
		logger error "No RBD nodeplugin pod found on Scale core pod node ${scale_node} in $OCS_NAMESPACE namespace (checked both labels)."
		return 1
	fi

	echo "$pod"
}

#----------------------------------------
# Function: Get Ceph RBD devices list (from one nodeplugin pod running on the same node as the Scale core pod)
#----------------------------------------
get_rbd_devices() {
	local pod node
	#
	# Step 1: Grab the Scale pod and the identify the node it is running on
	#
	scale_pod="$(get_scale_core_pod)" || return 1
	scale_node=$(get_node_for_pod "$SCALE_NAMESPACE" "$scale_pod")
	logger info "Detected Scale pod as $scale_pod running on $scale_node"
	#
	# Step 2: Grab the corresponding CSI plugin pod on the same node
	# the Scale core pod is running using the extra argument of get_rbd_pod ${node}. 
	#
	odf_pod=$(get_rbd_pod "${scale_node}") || return 1
	odf_node=$(get_node_for_pod "$OCS_NAMESPACE" "$odf_pod")
	logger info "Detected ODF pod as $odf_pod running on $odf_node"

	logger info "Using RBD nodeplugin pod $odf_pod running on node $odf_node to extract RBD device list. Scale node was ${scale_node}."

	oc exec -n "$OCS_NAMESPACE" "$odf_pod" -c "$RBD_CONTAINER" -- rbd device list 2>/dev/null || echo ""
}

#----------------------------------------
# Function: Get pool and image name from PV
#----------------------------------------
get_pool_and_img_from_pv() {
	local pv="$1"
	local pool img
	pool=$(oc get pv "$pv" -o jsonpath='{.spec.csi.volumeAttributes.pool}' 2>/dev/null || echo "")
	img=$(oc get pv "$pv" -o jsonpath='{.spec.csi.volumeAttributes.imageName}' 2>/dev/null || echo "")
	echo "$pool $img"
}

#----------------------------------------
# Function: Get device ID for given pool and image
#----------------------------------------
get_device_id() {
	local devices="$1"
	local pool="$2"
	local img="$3"

	echo "$devices" | grep -E "${pool}"'[[:space:]]+.*'"${img}" | awk '{print $NF}' || echo ""
}

#----------------------------------------
# Function: Get device IDs for local disks
#----------------------------------------
get_device_ids_for_local_disks() {
	local devices
	devices=$(get_rbd_devices)
	DEVICE_IDS=()

	for pvc in local-disk1 local-disk2 local-disk3; do
		local pv pool img dev
		pv=$(get_pv_from_pvc "$pvc")
		read -r pool img <<<"$(get_pool_and_img_from_pv "$pv")"
		dev=$(get_device_id "$devices" "$pool" "$img")

		if [[ -n "$dev" ]]; then
			DEVICE_IDS+=("$dev")
		else
			logger warn "No device found for PVC: $pvc"
		fi
	done

	if [[ ${#DEVICE_IDS[@]} -eq 0 ]]; then
		logger error "No RBD device IDs found for any local-disk PVCs"
		return 1
	fi
}

#========================================
# Scale Cluster Operations
#========================================

#----------------------------------------
# Function: Check if Scale cluster exists
#----------------------------------------
is_scale_cluster_created() {
	oc get "$SCALE_CUSTOM_RESOURCE" "$SCALE_NAMESPACE" &>/dev/null
}

#----------------------------------------
# Function: Patch Scale CSI driver with kubelet root directory
#----------------------------------------
patch_scale_csi_driver() {
	SECONDS=0
	while ! oc get csiscaleoperator ibm-spectrum-scale-csi -n "${SCALE_NAMESPACE}" &>/dev/null; do
		logger info "Waiting for CSIScaleOperator CR... (${SECONDS}s elapsed)"
		(( SECONDS += 5 ))
		sleep 5
	done

	logger info "Patching CSIScaleOperator CR..."

	oc apply -f - <<EOF
apiVersion: csi.ibm.com/v1
kind: CSIScaleOperator
metadata:
  name: ibm-spectrum-scale-csi
  namespace: ${SCALE_NAMESPACE}
spec:
  kubeletRootDirPath: ${KUBELET_ROOT_DIR_PATH}
EOF
}

#----------------------------------------
# Function: Create Spectrum Scale cluster
#----------------------------------------
create_scale_cluster() {
	logger info "Creating Spectrum Scale cluster..."

	if envsubst <templates/spectrum_scale_cluster.yaml | oc apply -f - >/dev/null 2>&1; then
		logger success "Spectrum Scale cluster creation initiated"
	else
		logger error "Failed to apply Spectrum Scale cluster manifest."
		return 1
	fi
}

#----------------------------------------
# Function: Verify Scale cluster status
#----------------------------------------
verify_scale_cluster() {
	local timeout=300 # 5 minutes
	local interval=30 # 30 seconds
	local elapsed=0

	logger info "Waiting for Scale Daemon..."

	while ((elapsed < timeout)); do
		local status reason daemon_status
		daemon_status=$(oc get daemon -n "$SCALE_NAMESPACE" ibm-spectrum-scale \
			-o jsonpath='{.status.conditions[?(@.type=="Healthy")].status} {.status.conditions[?(@.type=="Healthy")].reason}' \
			--ignore-not-found=true 2>/dev/null)
		read -r status reason <<< "$daemon_status"
		if [[ "$status" == "True" ]] || [[ "$status" == "Tips" ]] || [[ "$reason" == "Degraded" ]]; then
			logger success "Scale Daemon is operational"
			oc delete sc "$SCALE_STORAGE_CLASS" --ignore-not-found=true
			return 0
		else
			sleep "$interval"
			((elapsed += interval))
		fi
	done

	logger error "Timeout: Scale Daemon did not come up within ${timeout}s."
	return 1
}

#----------------------------------------
# Function: Patch device regex in Scale cluster CR
#----------------------------------------
patch_device_regex_in_scale_cluster() {
	local first="${DEVICE_IDS[0]}"
	local prefix="${first%%[0-9]*}"
	local pattern="${prefix}*"

	oc patch "$SCALE_CUSTOM_RESOURCE" "$SCALE_NAMESPACE" \
		--type=merge \
		-p "{\"spec\":{\"daemon\":{\"nsdDevicesConfig\":{\"localDevicePaths\":[{\"devicePath\":\"${pattern}\",\"deviceType\":\"generic\"}]}}}}"

	logger success "Patched $SCALE_NAMESPACE with device pattern: ${pattern}"
}

#========================================
# LocalDisk Management
#========================================

#----------------------------------------
# Function: Create LocalDisk CRs
#----------------------------------------
create_local_disks() {
	local pod node i=0
	pod="$(get_scale_core_pod)" || return 1
	node=$(get_node_for_pod "$SCALE_NAMESPACE" "$pod")
	logger info "Identified Scale core pod ${pod} running on node ${node} to verify device IDs"

	logger info "Creating LocalDisk CRs on node '$node'..."

	for dev in "${DEVICE_IDS[@]}"; do
		cat <<EOF | oc apply -f -
apiVersion: scale.spectrum.ibm.com/v1beta1
kind: LocalDisk
metadata:
  name: disk${i}
  namespace: ${SCALE_NAMESPACE}
spec:
  node: ${node}
  device: ${dev}
EOF
		((++i))
	done
}

#----------------------------------------
# Function: Ensure all LocalDisks are READY=True and TYPE=shared
#----------------------------------------
ensure_local_disks() {
	local timeout=1200 # 20 minutes
	local interval=30  # 30 seconds
	local elapsed=0

	logger info "Waiting for all LocalDisks to become READY=True and TYPE=shared..."

	while ((elapsed < timeout)); do
		local disks
		disks=$(oc get localdisks -n "$SCALE_NAMESPACE" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null)

		if [[ -z "$disks" ]]; then
			logger info "No LocalDisks found."
			create_local_disks
		else
			local not_ready not_shared
			not_ready=""
			not_shared=""

			for disk in $disks; do
				local ready type
				ready=$(oc get localdisk "$disk" -n "$SCALE_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
				type=$(oc get localdisk "$disk" -n "$SCALE_NAMESPACE" -o jsonpath='{.status.type}' 2>/dev/null)

				[[ "$ready" != "True" ]] && not_ready+="$disk "
				[[ "$type" != "shared" ]] && not_shared+="$disk "
			done

			if [[ -z "$not_ready" && -z "$not_shared" ]]; then
				logger success "All LocalDisks are READY=True and TYPE=shared."
				return 0
			fi

			[[ -n "$not_ready" ]] && logger info "Waiting for these disks to become READY=True: $not_ready"
			[[ -n "$not_shared" ]] && logger info "Waiting for these disks to have TYPE=shared: $not_shared"
		fi

		sleep "$interval"
		((elapsed += interval))
	done

	logger error "Timeout: Not all LocalDisks became READY=True and TYPE=shared within ${timeout}s."
	return 1
}

#----------------------------------------
# Function: Validate LocalDisk usage and health
#----------------------------------------
validate_local_disks_usage() {
	logger info "Validating LocalDisk usage and health..."

	local timeout=$((5 * 60))
	local interval=30
	local elapsed=0

	while ((elapsed < timeout)); do
		# Extract disk name, Used=True, Healthy=True statuses
		local disk_status
		disk_status=$(oc get localdisks -n "$SCALE_NAMESPACE" \
			-o jsonpath='{range .items[*]}{.metadata.name} {.status.conditions[?(@.type=="Used")].status} {.status.conditions[?(@.type=="Healthy")].status}{"\n"}{end}' 2>/dev/null)

		# Filter disks that are NOT both Used=True and Healthy=True
		local not_ready
		not_ready=$(echo "$disk_status" | awk '$2!="True" || $3!="True" {print $1}')

		if [[ -z "$not_ready" ]]; then
			logger success "All LocalDisks are used and healty."
			return 0
		fi

		logger info "Waiting for LocalDisks to be used and healthy... (${elapsed}s elapsed)"
		sleep $interval
		((elapsed += interval))
	done

	logger error "Timeout waiting for LocalDisks to reach USED=True and HEALTHY=Healthy."
	return 1
}

#========================================
# FileSystem Operations
#========================================

#----------------------------------------
# Function: Check if FileSystem exists
#----------------------------------------
is_fs_created() {
	oc get -n "$SCALE_NAMESPACE" filesystem "$FILESYSTEM_NAME" &>/dev/null || return 1
}

#----------------------------------------
# Function: Create Spectrum Scale FileSystem
#----------------------------------------
create_fs() {
	if ! envsubst <templates/filesystem.yaml | oc apply -f - >/dev/null 2>&1; then
		logger error "Failed to create Spectrum Scale FileSystem '${FILESYSTEM_NAME}'."
		return 1
	fi
}

#----------------------------------------
# Function: Verify FileSystem status
#----------------------------------------
verify_fs() {
	logger info "Verifying Spectrum Scale FileSystem status..."

	local timeout=900 # 15 minutes
	local interval=30
	local elapsed=0

	while ((elapsed < timeout)); do
		# Extract Success and Healthy condition statuses
		local fs_status fs_name success health
		fs_status=$(oc get filesystem -n "$SCALE_NAMESPACE" \
			-o jsonpath='{range .items[*]}{.metadata.name} {.status.conditions[?(@.type=="Success")].status} {.status.conditions[?(@.type=="Healthy")].reason}{"\n"}{end}' \
			2>/dev/null)
		read -r fs_name success health <<< "$fs_status"

		if [[ "$success" == "True" ]]; then
			if [[ "$health" == "Healthy" ]]; then
				logger success "Filesystem '$fs_name' created successfully."
				return 0
			elif [[ "$health" == "Degraded" ]]; then
				logger warn "Filesystem '$fs_name' created but health is degraded. Proceeding with installation."
				return 0
			fi
		fi

		logger info "Waiting for Filesystem '$fs_name' to be ready... (${elapsed}s elapsed)"
		sleep "$interval"
		((elapsed += interval))
	done

	logger error "Timeout waiting for Filesystem."
	return 1
}

#========================================
# Scale Core Operations
#========================================

#----------------------------------------
# Function: Get first scale-core Pod
#----------------------------------------
get_scale_core_pod() {
	scale_core_pod="$(oc get no -l "${SCALE_DAEMON_LABEL}" --no-headers -o custom-columns=NAME:.metadata.name | head -n 1)"
	logger info "Using scale-core Pod: ${scale_core_pod}"
	echo "${scale_core_pod}"
}

#----------------------------------------
# Function: Run command inside a scale-core Pod
#----------------------------------------
scale_core_exec() {
	POD="$(get_scale_core_pod)"
	CMD="${*}"
	logger info "Running on $POD: $CMD"
	oc exec -n "${SCALE_NAMESPACE}" -i -c gpfs "${POD}" -- bash -s <<<"${CMD}"
}

#========================================
# AFM Configuration
#========================================

#----------------------------------------
# Function: Configure AFM
#----------------------------------------
configure_afm() {
	logger info "Checking for AFM Gateway label..."
	afm_node="$(oc get no -l "${SCALE_ROLE_LABEL}=${SCALE_ROLE_AFM}" --no-headers -o custom-columns=NAME:.metadata.name)"
	if [[ "${afm_node}x" == "x" ]]; then
		afm_node=$(get_nodes | tr '\n' ' ' | awk '{print $1}')
		label_nodes "${SCALE_ROLE_LABEL}=${SCALE_ROLE_AFM}" "${afm_node}"
	fi
	logger success "AFM Gateway label set on ${afm_node}"
}

#----------------------------------------
# Function: Verify AFM configuration
#----------------------------------------
verify_afm_config() {
	afm_daemon="$(oc get daemons.scale.spectrum.ibm.com -n "${SCALE_NAMESPACE}" ibm-spectrum-scale -o=go-template='{{range .status.roles}}{{if eq .name "afm"}}{{.pods}}{{end}}{{end}}')"
	if [[ "${afm_daemon}x" != "x" ]]; then
		logger success "Verified AFM Gateway role configured on ${afm_daemon}"
	else
		logger error "AFM Gateway role not configured"
	fi
}

#========================================
# Configuration
#========================================

#----------------------------------------
# Function: Set Scale config options
#----------------------------------------
scale_set_config() {
	OPT="${1}"
	VALUE="${2}"

	logger info "Setting Scale config: ${OPT}=${VALUE}"
	lsconfig="$(scale_core_exec mmlsconfig)"
	found_value="$(echo "$lsconfig" | grep "${OPT}" | awk '{print $2}')"
	logger info "  Current value: ${found_value:-<none>}"
	if [[ "${found_value}" != "${VALUE}" ]]; then
		scale_core_exec "mmchconfig ${OPT}=${VALUE} --force -i"
	fi
}
