#!/usr/bin/env bash

# GUARD CLAUSE: Prevent sourcing this file multiple times
if [[ -n "${LOADED_CAS_UTILS_SH:-}" ]]; then
    return 0
fi
export LOADED_CAS_UTILS_SH=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=modules/df_utils.sh
source "${PROJECT_ROOT}/modules/df_utils.sh"
# shellcheck source=modules/scale_utils.sh
source "${PROJECT_ROOT}/modules/scale_utils.sh"

#----------------------------------------
# Function: Patch the CAS FusionServiceDefinition with the CAS version
#----------------------------------------
patch_cas_fsd() {
  if ! oc patch fusionservicedefinition ibm-cas-service \
  -n ibm-spectrum-fusion-ns \
  -p='[{"op": "replace", "path": "/spec/onboarding/serviceOperatorSubscription/catalogSourceDetails/imageTag", "value": "'"$CAS_VERSION"'"}]' \
  --type='json' >/dev/null 2>&1; then
		logger error "Failed to set CAS version in FusionServiceDefinition."
		return 1
	fi
}

#----------------------------------------
# Function: Apply RBAC allowing cas-operator to label nodes
#----------------------------------------
ensure_node_labeling_rbac(){
  oc apply -f - <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ibm-isf-cas-operator-label-nodes
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "update", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ibm-isf-cas-operator-label-nodes
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ibm-isf-cas-operator-label-nodes
subjects:
- kind: ServiceAccount
  name: ibm-isf-cas-operator-controller-manager
  namespace: ${CAS_NAMESPACE}
EOF
}

#----------------------------------------
# Function: Returns true if CAS installation is completed
# (stage=CAS-INSTALLATION-COMPLETED and progress=100)
#----------------------------------------
cas_installed() {
  local casinstall_json
  casinstall_json=$(oc get casinstall "${CAS_SERVICE_NAME}" -n "${CAS_NAMESPACE}" -o json 2>/dev/null || true)

  local installation_stage
  local progress_percentage
  installation_stage=$(jq -r '.status.installationStage // empty' <<< "${casinstall_json}")
  progress_percentage=$(jq -r '.status.installStatus.progressPercentage // empty' <<< "${casinstall_json}")

  [[ "${installation_stage}" == "CAS-INSTALLATION-COMPLETED" && "${progress_percentage}" == "100" ]]
}

#----------------------------------------
# Function: Returns JSON patch for CasInstall cache and annotation settings
#----------------------------------------
patch_cas_install_cache() {
  local patch

  patch=$(jq -n \
    --arg sc "${LOCAL_DISK_PVC_STORAGE_CLASS}" \
    --arg sz "${FILESYSTEM_CAPACITY}" \
    '{
      "metadata": {"annotations": {"ignore-filesystem-health-timeout": "true"}},
      "spec": {"cache": {"storageClass": $sc, "size": $sz}}
    }')

  # W002: When CAS 1.1.5 has been installed and no Filesystem is found, set the
  # installation status backwards to force reconciliation from that point.
  if cas_installed && ! is_fs_created; then
    patch=$(jq '.status = {"installationStage": "CAS-CORE", "installStatus": {"progressPercentage": 85}}' <<< "${patch}")
  fi

  echo "${patch}"
}

#----------------------------------------
# Function: Returns JSON patch for CasInstall CPU docling/vllm flags
#----------------------------------------
patch_cas_install_cpu_flags() {
  local namespace="${1}"

  # Use RELATED_IMAGE_CAS_DOCLING_CPU if set, otherwise retrieve from cas-operator deployment
  local docling_image="${RELATED_IMAGE_CAS_DOCLING_CPU:-}"
  if [[ -z "${docling_image}" ]]; then
    # The docling CUDA image can also be used in CPU mode
    docling_image=$(oc get deployment ibm-isf-cas-operator-controller-manager -n "${namespace}" \
      -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RELATED_IMAGE_CAS_DOCLING_CUDA")].value}' 2>/dev/null)
    if [[ -z "${docling_image}" ]]; then
      logger error "Failed to retrieve RELATED_IMAGE_CAS_DOCLING_CUDA from cas-operator deployment in namespace '${namespace}'."
      return 1
    fi
  fi

  # Use RELATED_IMAGE_CAS_VLLM_CPU if set, otherwise retrieve from cas-operator deployment
  local vllm_image="${RELATED_IMAGE_CAS_VLLM_CPU:-}"
  if [[ -z "${vllm_image}" ]]; then
    vllm_image=$(oc get deployment ibm-isf-cas-operator-controller-manager -n "${namespace}" \
      -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RELATED_IMAGE_CAS_VLLM_CPU")].value}' 2>/dev/null)
    if [[ -z "${vllm_image}" ]]; then
      logger error "Failed to retrieve RELATED_IMAGE_CAS_VLLM_CPU from cas-operator deployment in namespace '${namespace}'."
      return 1
    fi
  fi

  jq -n \
    --arg docling "RELATED_IMAGE_CAS_DOCLING_CPU=${docling_image}" \
    --arg vllm "RELATED_IMAGE_CAS_VLLM_CPU=${vllm_image}" \
    '{"spec": {"flags": [$docling, "DOCLING_GPU_TYPE=cpu", $vllm, "VLLM_GPU_TYPE=cpu"]}}'
}

#----------------------------------------
# Function: Returns JSON patch to enable docling multimodal in CasInstall
#----------------------------------------
patch_cas_install_docling() {
  jq -n '{"spec": {"documentProcessingEngine": {"docling_multimodal": {"enabled": true}}}}'
}

#----------------------------------------
# Function: Patch CasInstall immediately after creation
#----------------------------------------
patch_cas_install() {
  local namespace="${1}"
  local name="${2}"
  local cas_gte_115="${3}"
  local cnsa_gte_6010="${4}"

  local patch="{}"

  if [[ "${CAS_ENABLE_DOCLING}" == "true" ]]; then
    local docling_patch
    docling_patch="$(patch_cas_install_docling)"
    patch="$(jq -s '.[0] * .[1]' <(echo "${patch}") <(echo "${docling_patch}"))"
  fi

  if [[ "${cas_gte_115}" == true ]] && [[ "${cnsa_gte_6010}" == true ]]; then
    local cache_patch
    cache_patch="$(patch_cas_install_cache)"
    patch="$(jq -s '.[0] * .[1]' <(echo "${patch}") <(echo "${cache_patch}"))"
  fi

  if [[ "${CAS_RHAI_USE_CPU}" == "true" ]]; then
    logger info "Patching CasInstall to use CPU for RHAI"
    local cpu_patch
    cpu_patch="$(patch_cas_install_cpu_flags "${namespace}")" || return 1
    patch="$(jq -s '.[0] * .[1]' <(echo "${patch}") <(echo "${cpu_patch}"))"
  fi

  if ! oc patch casinstall "${name}" -n "${namespace}" --type=merge -p "${patch}" >/dev/null 2>&1; then
    logger error "Failed to patch CasInstall '${name}' in namespace '${namespace}'."
    return 1
  fi
}

#----------------------------------------
# Function: Wait for CasInstall CR to exist
#----------------------------------------
wait_for_casinstall() {
  local namespace="${1}"
  local name="${2}"

  wait_for_condition \
    "Waiting for CasInstall CR '${name}' in namespace '${namespace}'" \
    "${CAS_INSTALL_TIMEOUT}" \
    "oc get casinstall '${name}' -n '${namespace}'"
}

#----------------------------------------
# Function: Verify CAS installation from FSI succeeds
#----------------------------------------
verify_cas_install() {
  wait_for_condition \
    "Waiting for CAS installation to complete" \
    "${CAS_SERVICE_TIMEOUT}" \
    "[[ \$(oc get casinstall '${CAS_SERVICE_NAME}' -n '${CAS_NAMESPACE}' -o jsonpath='{.status.installationStage}' 2>/dev/null) == 'CAS-INSTALLATION-COMPLETED' ]] && [[ \$(oc get casinstall '${CAS_SERVICE_NAME}' -n '${CAS_NAMESPACE}' -o jsonpath='{.status.installStatus.progressPercentage}' 2>/dev/null) == '100' ]]"
}

#----------------------------------------
# Function: Configure Scale watch for CAS Kafka instance
#----------------------------------------
configure_scale_watch() {
  NAMESPACE="${1}"
  FS_NAME="${2}"

  TEMP_DIR=$(mktemp -d)
  cd "${TEMP_DIR}" || {
    logger error "Failed to change directory to ${TEMP_DIR}"
    return 1
  }

  config_dir="/mnt/${FS_NAME}/${NAMESPACE}"
  config_file="${NAMESPACE}.watch.config"

  oc extract -n "${NAMESPACE}" secret/kafka-cluster-ca-cert --keys=ca.crt --to=-> cluster_ca.crt
  oc extract -n "${NAMESPACE}" secret/cas-user --keys=user.crt --to=-> user.crt
  oc extract -n "${NAMESPACE}" secret/cas-user --keys=user.key --to=-> user.key
  openssl x509 -in user.crt -out user.pem -outform PEM

  cas_pw="$(oc extract -n "${NAMESPACE}" secret/cas-user --keys=user.password --to=-)"

  cat <<EOF >"${config_file}"
SINK_AUTH_TYPE:CERT
CA_CERT_LOCATION:${config_dir}/cluster_ca.crt
CLIENT_KEY_FILE_LOCATION:${config_dir}/user.key
CLIENT_PEM_CERT_LOCATION:${config_dir}/user.pem
CLIENT_KEY_FILE_PASSWORD:$cas_pw
EOF

  scale_core_pod="$(get_scale_core_pod)"
  logger info "Configuring Scale watch through Pod: ${scale_core_pod}"
  scale_core_exec "sudo mkdir -p ${config_dir} && sudo chmod 755 ${config_dir}"
  oc rsync -n "${SCALE_NAMESPACE}" ./ "${scale_core_pod}:${config_dir}/" -c gpfs

  rm -rf "${TEMP_DIR}"

  op_cm="$(oc get configmap -n "${NAMESPACE}" operator-config -oyaml --ignore-not-found 2> /dev/null)"

  if [[ -n "${op_cm}" ]]; then
	  oc patch -n "${NAMESPACE}" configmap operator-config \
		  --type=merge \
		  -p '{"data": {"KAFKA_AUTHEN_LOCAL": "'"${config_dir}/${config_file}"'"}}'
  else
    cat <<EOF | oc apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: operator-config
  labels:
    app.kubernetes.io/name: cas.isf.ibm.com
    app.kubernetes.io/component: kafka-op-config
data:
  KAFKA_AUTHEN_LOCAL: ${config_dir}/${config_file}
EOF
  fi

  logger success "Scale watch configured"
}

#----------------------------------------
# Function: Get installed CAS version from CSV
#----------------------------------------
get_cas_version() {
	local ver
	ver=$(oc get csv -A --no-headers \
		-o custom-columns=NAME:.metadata.name,VERSION:.spec.version 2>/dev/null \
		| grep "ibm-isf-cas-operator" | awk '{print $2}' | head -n1)
	echo "${ver#v}"
}

#----------------------------------------
# Function: Validate CAS namespace exists
#----------------------------------------
validate_cas_namespace() {
	local cas_namespace="${1}"
	
	logger info "Validating CAS namespace..."
	
	if ! oc get namespace "${cas_namespace}" &>/dev/null; then
		logger error "CAS namespace not found: ${cas_namespace}"
		logger error "This is the target namespace where the migration job will run"
		return 1
	fi
	
	logger success "CAS namespace validated: ${cas_namespace}"
	return 0
}

#----------------------------------------
# Function: Get migration state for a phase
#----------------------------------------
get_migration_state() {
	local namespace="${1}"
	local phase="${2}"
	
	# Check for running jobs
	local active_jobs
	active_jobs=$(oc get jobs -n "${namespace}" \
		-l "app=${MIGRATION_APP_LABEL},migration-phase=${phase}" \
		-o jsonpath='{.items[?(@.status.active>0)].metadata.name}' 2>/dev/null || echo "")
	
	if [[ -n "${active_jobs}" ]]; then
		echo "running"
		return 0
	fi
	
	# Check for succeeded jobs
	local succeeded_jobs
	succeeded_jobs=$(oc get jobs -n "${namespace}" \
		-l "app=${MIGRATION_APP_LABEL},migration-phase=${phase}" \
		-o jsonpath='{.items[?(@.status.succeeded>0)].metadata.name}' 2>/dev/null || echo "")
	
	if [[ -n "${succeeded_jobs}" ]]; then
		echo "completed"
		return 0
	fi
	
	# Check for failed jobs
	local failed_jobs
	failed_jobs=$(oc get jobs -n "${namespace}" \
		-l "app=${MIGRATION_APP_LABEL},migration-phase=${phase}" \
		-o jsonpath='{.items[?(@.status.failed>0)].metadata.name}' 2>/dev/null || echo "")
	
	if [[ -n "${failed_jobs}" ]]; then
		echo "failed"
		return 0
	fi
	
	echo "pending"
	return 0
}

#----------------------------------------
# Function: Check migration state and handle accordingly
#----------------------------------------
check_migration_state() {
	local namespace="${1}"
	local phase="${2}"
	
	logger info "Checking migration state for ${phase}-migration..."
	
	local current_state
	current_state=$(get_migration_state "${namespace}" "${phase}")
	
	case "${current_state}" in
		running)
			local running_job
			running_job=$(oc get jobs -n "${namespace}" \
				-l "app=${MIGRATION_APP_LABEL},migration-phase=${phase}" \
				-o jsonpath='{.items[?(@.status.active>0)].metadata.name}' 2>/dev/null)
			
			logger error "${phase}-migration already running: ${running_job}"
			logger error "Check status: oc get job ${running_job} -n ${namespace}"
			return 1
			;;
		
		completed)
			local completed_job
			completed_job=$(oc get jobs -n "${namespace}" \
				-l "app=${MIGRATION_APP_LABEL},migration-phase=${phase}" \
				-o jsonpath='{.items[?(@.status.succeeded>0)].metadata.name}' 2>/dev/null | head -n1)
			
			logger warn "${phase}-migration already completed: ${completed_job}"
			read -p "Re-run migration? (yes/no): " -r
			if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
				logger info "Cancelled by user"
				return 1
			fi
			;;
		
		failed)
			local failed_job
			failed_job=$(oc get jobs -n "${namespace}" \
				-l "app=${MIGRATION_APP_LABEL},migration-phase=${phase}" \
				-o jsonpath='{.items[?(@.status.failed>0)].metadata.name}' 2>/dev/null | head -n1)
			
			logger warn "Previous ${phase}-migration failed: ${failed_job}"
			logger warn "Review logs: oc logs job/${failed_job} -n ${namespace}"
			read -p "Retry migration? (yes/no): " -r
			if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
				logger info "Cancelled by user"
				return 1
			fi
			;;
		
		pending)
			logger info "No previous ${phase}-migration found"
			;;
	esac
	
	logger success "State check passed (current: ${current_state})"
	return 0
}
