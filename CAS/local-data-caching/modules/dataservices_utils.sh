#!/usr/bin/env bash
set -eu

#----------------------------------------
# Function: Determine environment type (HCI or SDS)
#----------------------------------------
get_environment_type() {
	if is_cm_exist "$APPLIANCE_INFO" "$HCI_FUSION_NAMESPACE"; then
		echo "$HCI_ENVIRONMENT"
	else
		echo "$SDS_ENVIRONMENT"
	fi
}

#----------------------------------------
# Function: Get fusion namespace from environment HCI vs SDS
#----------------------------------------
get_fusion_namespace() {
	local env_type
	env_type=$(get_environment_type)

	if [[ "$env_type" == "$HCI_ENVIRONMENT" ]]; then
		echo "-n $HCI_FUSION_NAMESPACE"
	else
		echo "-A"
	fi
}

#----------------------------------------
# Function: Deploy Fusion operator
#----------------------------------------
deploy_fusion() {
	local environment_type="$1"

	verify_catalog_sources || return 1

	logger info "Starting Fusion operator deployment..."

	if [[ "$environment_type" == "$HCI_ENVIRONMENT" ]]; then
		export FUSION_CATALOG_NAME="$HCI_CATALOG"
		export FUSION_CATALOG_SOURCE_IMAGE="$IBM_OPEN_REGISTRY/$IBM_OPEN_REGISTRY_NS/$HCI_CATALOG:$FUSION_VERSION-$HCI_CATALOG_SUFFIX"
	else
		export FUSION_CATALOG_NAME="$SOFTWARE_CATALOG"
		export FUSION_CATALOG_SOURCE_IMAGE="$IBM_OPEN_REGISTRY/$IBM_OPEN_REGISTRY_NS/$SOFTWARE_CATALOG:$FUSION_VERSION"
	fi

	operator_package_catalog="$(get_operator_package_catalog "$FUSION_PACKAGE_NAME")"

	if [[ "x$operator_package_catalog" != "x" ]]; then
		logger success "Package $FUSION_PACKAGE_NAME is available."
		export CATALOG_NAMESPACE="$(echo "$operator_package_catalog" | cut -d '/' -f 1)"
		export FUSION_CATALOG_NAME="$(echo "$operator_package_catalog" | cut -d '/' -f 2)"
	fi

	ensure_operator_package "$FUSION_PACKAGE_NAME" "$FUSION_CATALOG_NAME" "templates/fusion/catalog_source.yaml"
	ensure_namespace "$FUSION_NAMESPACE"
	ensure_operator_group "$FUSION_NAMESPACE" "templates/fusion/operator_group.yaml"
	apply_subscription "templates/fusion/subscription.yaml"
	wait_for_csv_success "$FUSION_NAMESPACE" "$FUSION_PACKAGE_NAME"

	logger success "Fusion operator deployment completed successfully."
}

#----------------------------------------
# Function: Ensure Spectrum Fusion CR exists
#----------------------------------------
ensure_spectrum_fusion() {
	oc get $SPECTRUM_FUSION_CRD $SPECTRUM_FUSION -n "$FUSION_NAMESPACE" >/dev/null 2>&1
}

#----------------------------------------
# Function: Apply Spectrum Fusion CR
#----------------------------------------
apply_spectrum_fusion() {
	echo "apiVersion: prereq.isf.ibm.com/v1
kind: ${SPECTRUM_FUSION_CRD}
metadata:
  name: ${SPECTRUM_FUSION}
  namespace: ${FUSION_NAMESPACE}
spec:
  license:
    accept: true" | oc create -n ${FUSION_NAMESPACE} -f - >/dev/null 2>&1
	logger success "Spectrum Fusion CR applied successfully."
}

#----------------------------------------
# Function: Check if Fusion service is deployed successfully
#----------------------------------------
is_fsi_deployed() {
	local SERVICE_NAME="${1}"
	logger info "Checking if $SERVICE_NAME is deployed successfully..."

	if oc get $FUSION_SERVICE_INSTANCE_CR $SERVICE_NAME -n "$FUSION_NAMESPACE" \
		-o jsonpath='{.status.installStatus.status}' 2>/dev/null | grep -q "Completed"; then
		echo "true"
	else
		echo ""
	fi
}

#----------------------------------------
# Function: Deploy Fusion service
#----------------------------------------
deploy_fsi() {
	export SERVICE_NAME="${1}"
	export SERVICE_TEMPLATE="${2}"

	logger info "Deploying Fusion service: $SERVICE_NAME"

	if envsubst <"${SERVICE_TEMPLATE}" | oc apply -n "$FUSION_NAMESPACE" -f - >/dev/null; then
		logger success "$SERVICE_NAME created successfully."
	else
		logger error "Operation failed: Unable to create Fusion service $SERVICE_NAME."
		return 1
	fi

	local retry_count=0
	while true; do
		if oc get $FUSION_SERVICE_INSTANCE_CR $SERVICE_NAME -n $FUSION_NAMESPACE -o jsonpath='{.status.installStatus.status}' 2>/dev/null | grep -q "Completed"; then
			logger success "$SERVICE_NAME install is Completed."
			return 0
		fi

		((++retry_count))
		if [[ $retry_count -ge $FUSION_SERVICE_RETRY_COUNT ]]; then
			logger error "Timeout: $SERVICE_NAME installation did not reach Completed status after $((FUSION_SERVICE_RETRY_COUNT * RETRY_INTERVAL)) seconds."
			return 1
		fi

		logger info "$SERVICE_NAME installation not Completed yet... retrying in ${RETRY_INTERVAL}s ($retry_count/$FUSION_SERVICE_RETRY_COUNT)"
		sleep "$RETRY_INTERVAL"
	done
}

#----------------------------------------
# Function: Check if FDF is already configured
#----------------------------------------
is_fdf_configured() {
	local status
	status=$(oc get $STORAGE_CLUSTER $OCS_CLUSTER_NAME -n $OCS_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null)

	if [[ "$status" == "Ready" ]]; then
		echo "ready"
	fi
}

#----------------------------------------
# Function: Configure FDF
#----------------------------------------
configure_fdf() {
	convert_hdd_to_ssd

	logger info "Configuring FDF..."

	envsubst <templates/localvolumeset.yaml | oc apply -f - || {
		logger error "Failed to apply LocalVolumeSet"
		return 1
	}

	local retry_count=0
	while true; do
		local no_of_disks
		no_of_disks=$(oc get localvolumeset ${OCS_BACKING_STORAGECLASS} -n openshift-local-storage \
			-o jsonpath='{.status.totalProvisionedDeviceCount}' 2>/dev/null)
		if [[ "$no_of_disks" -gt 0 ]]; then
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
		if oc get $STORAGE_CLUSTER "$OCS_CLUSTER_NAME" -n $OCS_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Ready"; then
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
# Function: Enable GlobalDataPlatform service
#----------------------------------------
deploy_scale_service() {
	logger info "Deploying GlobalDataPlatform service..."

	local env_type
	env_type=$(get_environment_type)

	if [[ "$env_type" == "$HCI_ENVIRONMENT" ]]; then
		if ! envsubst <templates/fusion/gdp.yaml | oc apply -f -; then
			logger error "Failed to apply GDP FusionServiceInstance."
			return 1
		fi
	else
		if ! oc patch "$SPECTRUM_FUSION_CRD" "$SPECTRUM_FUSION" \
			-n "$FUSION_NAMESPACE" \
			--type merge \
			-p '{"spec": {"GlobalDataPlatform": {"Enable": true}}}' >/dev/null 2>&1; then
			logger error "Failed to enable GlobalDataPlatform on SpectrumFusion CR."
			return 1
		fi
	fi

	logger info "Waiting for GlobalDataPlatform installation to complete..."

	local install_status
	local progress

	while true; do

		if [[ "$env_type" == "$HCI_ENVIRONMENT" ]]; then
			install_status=$(oc get $FUSION_SERVICE_INSTANCE_CR "$SCALE_SERVICE_NAME" \
				-n "$FUSION_NAMESPACE" \
				-o jsonpath='{.status.installStatus.status}' 2>/dev/null)

			progress=$(oc get $FUSION_SERVICE_INSTANCE_CR "$SCALE_SERVICE_NAME" \
				-n "$FUSION_NAMESPACE" \
				-o jsonpath='{.status.installStatus.progressPercentage}' 2>/dev/null)

		else
			install_status=$(oc get "$SPECTRUM_FUSION_CRD" "$SPECTRUM_FUSION" \
				-n "$FUSION_NAMESPACE" \
				-o jsonpath='{.status.GlobalDataPlatformStatus.installStatus}' 2>/dev/null)

			progress=$(oc get "$SPECTRUM_FUSION_CRD" "$SPECTRUM_FUSION" \
				-n "$FUSION_NAMESPACE" \
				-o jsonpath='{.status.GlobalDataPlatformStatus.progressPercentage}' 2>/dev/null)
		fi

		if [[ "$install_status" == "Completed" ]]; then
			logger success "GlobalDataPlatform installation ${install_status} progress: ${progress:-N/A}%."
			return 0
		fi

		logger info "Waiting... Status: ${install_status:-N/A}, Progress: ${progress:-N/A}%"
		sleep "$GDP_RETRY_INTERVAL"
	done
}

#----------------------------------------
# Function: Create PVCs for local disks
#----------------------------------------
create_pvc_local_disks() {
	local base_storage_class="$(oc get storageclass ${LOCAL_DISK_PVC_STORAGE_CLASS} -oyaml 2> /dev/null)"
	local cnsa_backing_sc_name="${LOCAL_DISK_PVC_STORAGE_CLASS}-aof"
	cat <<EOF | oc apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    description: Provides Ceph RBD volumes with 'abort_on_full'
    reclaimspace.csiaddons.openshift.io/schedule: '@weekly'
  name: ${cnsa_backing_sc_name}
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
  storageClassName: ${cnsa_backing_sc_name}
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
			pvc_phase="$(oc get pvc -n ${LOCAL_STORAGE_PROJECT} ${pvc_name} -ojsonpath='{.status.phase}')"
			if [[ "${pvc_phase}"  != "Bound" ]]; then
				unbound_pvcs+="${pvc_name} "
			fi
		done

		if [[ "x${unbound_pvcs}" == "x" ]]; then
			logger success "LocalDisk RBD PVCs provisioned successfully."
			break
		else
			logger info "Waiting on RBD PVCs to bind: ${unbound_pvcs}..."
		fi

		sleep ${interval}
	done

	oc delete storageclass ${cnsa_backing_sc_name} --ignore-not-found >/dev/null 2>&1
}

#----------------------------------------
# Function: Create DaemonSet to expose Ceph RBD PVCs as block devices
#----------------------------------------
create_expose_rbd_daemonset() {
	local output
	if envsubst <templates/daemonset_expose_rbd.yaml | oc apply -f - >/dev/null 2>&1; then
		logger success "DaemonSet applied successfully in namespace $LOCAL_STORAGE_PROJECT."
	else
		logger error "Failed to create DaemonSet to expose Ceph RBD PVCs."
		return 1
	fi

	local retry_count=0
	while true; do
		local desired ready
		desired=$(oc get daemonset $EXPOSE_RBD_DS_NAME -n "$LOCAL_STORAGE_PROJECT" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
		ready=$(oc get daemonset $EXPOSE_RBD_DS_NAME -n "$LOCAL_STORAGE_PROJECT" -o jsonpath='{.status.numberReady}' 2>/dev/null)

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
# Function: Get RBD nodeplugin pod name (with fallback)
#----------------------------------------
get_rbd_pod() {
	local pod

	# Try newer label first
	pod=$(oc get pod -n $OCS_NAMESPACE -l $RBD_POD_NEW_LABEL \
		-o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

	# Fallback for older label
	if [[ -z "$pod" ]]; then
		pod=$(oc get pod -n $OCS_NAMESPACE -l $RBD_POD_OLD_LABEL \
			-o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
	fi

	if [[ -z "$pod" ]]; then
		logger error "No RBD nodeplugin pod found in $OCS_NAMESPACE namespace (checked both labels)."
		return 1
	fi

	echo "$pod"
}

#----------------------------------------
# Function: Get Ceph RBD devices list (from one nodeplugin pod)
#----------------------------------------
get_rbd_devices() {
	local pod node
	pod=$(get_rbd_pod) || return 1
	node=$(get_node_for_pod "$pod")

	logger info "Using RBD nodeplugin pod '$pod' running on node '$node'"

	oc exec -n $OCS_NAMESPACE "$pod" -c $RBD_CONTAINER -- rbd device list 2>/dev/null || echo ""
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

	echo "$devices" | grep -E "$pool[[:space:]]+.*$img" | awk '{print $NF}' || echo ""
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

is_scale_cluster_created() {
	oc get $SCALE_CUSTOM_RESOURCE $SCALE_NAMESPACE &>/dev/null
}

create_scale_cluster() {
	logger info "Creating Spectrum Scale cluster..."

	export CLUSTER_BASE_DOMAIN=$(get_cluster_base_domain)

	if envsubst <templates/spectrum_scale_cluster.yaml | oc apply -f - >/dev/null 2>&1; then
		logger success "Spectrum Scale cluster creation initiated"
	else
		logger error "Failed to apply Spectrum Scale cluster manifest."
		return 1
	fi
}

verify_scale_cluster() {
	local timeout=120 # 2 minutes
	local interval=30 # 30 seconds
	local elapsed=0

	logger info "Waiting for Scale cluster..."

	while ((elapsed < timeout)); do
		local status
		status=$(oc get $SCALE_CUSTOM_RESOURCE $SCALE_NAMESPACE \
			-o jsonpath='{.status.conditions[?(@.type=="Success")].status}' 2>/dev/null)
		if [[ "$status" == "True" ]]; then
			logger success "Scale cluster is operational"
			oc delete sc "$SCALE_STORAGE_CLASS" --ignore-not-found=true
			return 0
		else
			sleep "$interval"
			((elapsed += interval))
		fi
	done

	logger error "Timeout: Scale cluster did not come up within ${timeout}s."
	return 1
}

#----------------------------------------
# Function: Patch device regex in Scale cluster CR
#----------------------------------------
patch_device_regex_in_scale_cluster() {
	local first="${DEVICE_IDS[0]}"
	local prefix="${first%%[0-9]*}"
	local pattern="${prefix}*"

	oc patch $SCALE_CUSTOM_RESOURCE $SCALE_NAMESPACE \
		--type=merge \
		-p "{\"spec\":{\"daemon\":{\"nsdDevicesConfig\":{\"localDevicePaths\":[{\"devicePath\":\"${pattern}\",\"deviceType\":\"generic\"}]}}}}"

	logger success "Patched $SCALE_NAMESPACE with device pattern: ${pattern}"
}

#----------------------------------------
# Function: Create LocalDisk CRs
#----------------------------------------
create_local_disks() {
	local pod node i=0
	pod=$(get_rbd_pod) || return 1
	node=$(get_node_for_pod "$pod")

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
# Function: Check if IBM Storage Scale is deployed
#----------------------------------------
is_scale_deployed() {
	local env_type
	env_type=$(get_environment_type)

	local status

	if [[ "$env_type" == "$HCI_ENVIRONMENT" ]]; then
		status=$(oc get $FUSION_SERVICE_INSTANCE_CR "$SCALE_SERVICE_NAME" \
			-n "$FUSION_NAMESPACE" \
			-o jsonpath='{.status.installStatus.status}' 2>/dev/null)
	else
		local enabled
		enabled=$(oc get "$SPECTRUM_FUSION_CRD" -n "$FUSION_NAMESPACE" \
			-o jsonpath='{.items[0].status.GlobalDataPlatformStatus.ServiceEnabled}' 2> /dev/null)
		if [[ "${enabled}" == "false" ]]; then
			logger info "GlobalDataPlatform Service is not enabled."
			return 1
		fi
		status=$(oc get "$SPECTRUM_FUSION_CRD" -n "$FUSION_NAMESPACE" \
			-o jsonpath='{.items[0].status.GlobalDataPlatformStatus.installStatus}' 2>/dev/null)
	fi

	if [[ "$status" == "Completed" ]]; then
		logger success "IBM Storage Scale deployment status: Completed."
		return 0
	else
		logger info "IBM Storage Scale deployment status: ${status:-Unknown}."
		return 1
	fi
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

verify_fs() {
	logger info "Verifying Spectrum Scale FileSystem status..."

	local timeout=$((5 * 60))
	local interval=30
	local elapsed=0

	while ((elapsed < timeout)); do
		# Extract Success and Healthy condition statuses
		local fs_status
		fs_status=$(oc get filesystem -n "$SCALE_NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name} {.status.conditions[?(@.type=="Success")].status} {.status.conditions[?(@.type=="Healthy")].status}{"\n"}{end}' 2>/dev/null)

		if echo "$fs_status" | grep -q "True True"; then
			logger success "FileSystem is created successfully and it's healty."
			return 0
		fi

		logger info "Waiting for FileSystem to be ready... (${elapsed}s elapsed)"
		sleep "$interval"
		((elapsed += interval))
	done

	logger error "Timeout waiting for FileSystem to become success and healty."
	return 1
}

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

#----------------------------------------
# Function: Get first scale-core Pod
#----------------------------------------
get_scale_core_pod() {
	scale_core_pod="$(oc get daemons.scale.spectrum.ibm.com -n "${SCALE_NAMESPACE}" ibm-spectrum-scale --template={{.status.statusDetails.quorumPods}} | tr ',' ' ' | awk '{print $1}')"
	logger info "Using scale-core Pod: ${scale_core_pod}"
	echo "${scale_core_pod}"
}

#----------------------------------------
# Function: Run command inside a scale-core Pod
#----------------------------------------
scale_core_exec() {
	POD="$(get_scale_core_pod)"
	CMD="${@}"
	logger info "Running on $POD: $CMD"
	oc exec -n "${SCALE_NAMESPACE}" -i -c gpfs ${POD} -- bash -s <<<"${CMD}"
}

#----------------------------------------
# Function: Configure AFM
#----------------------------------------
configure_afm() {
	logger info "Checking for AFM Gateway label..."
	afm_node="$(oc get no -l scale.spectrum.ibm.com/role=afm --no-headers -o custom-columns=NAME:.metadata.name)"
	if [[ "${afm_node}x" == "x" ]]; then
		afm_node=$(get_nodes | tr '\n' ' ' | awk '{print $1}')
		label_nodes "scale.spectrum.ibm.com/role=afm" "${afm_node}"
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

#----------------------------------------
# Function: Convert HDDs to SSDs (if env var set)
#----------------------------------------
convert_hdd_to_ssd() {
	[[ -z "${CONVERT_HDD_TO_SSD:-}" ]] && return 0
	for n in $(get_nodes); do
		oc debug "$n" -- chroot /host bash -c '
			for f in /sys/block/*/queue/rotational; do
				[[ $(cat "$f") == 1 ]] && echo 0 > "$f"
			done
		' >/dev/null 2>&1
	done
}
