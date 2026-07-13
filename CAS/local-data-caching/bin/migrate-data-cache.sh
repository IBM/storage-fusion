#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
set -a
# shellcheck source=lib/constants.sh
source "$ROOT_DIR/lib/constants.sh"
# shellcheck source=config/config.env
source "$ROOT_DIR/config/config.env"
set +a

# Load utilities
# shellcheck source=lib/logging.sh
source "$ROOT_DIR/lib/logging.sh"
# shellcheck source=lib/utils.sh
source "$ROOT_DIR/lib/utils.sh"
# shellcheck source=modules/ocp_cluster_utils.sh
source "$ROOT_DIR/modules/ocp_cluster_utils.sh"
# shellcheck source=modules/cas_utils.sh
source "$ROOT_DIR/modules/cas_utils.sh"

# Set defaults for launcher-specific options (core config comes from sourced files)
JOB_TIMEOUT="${JOB_TIMEOUT:-1800}"
SKIP_VALIDATION="${SKIP_VALIDATION:-false}"
DRY_RUN="${DRY_RUN:-false}"
DRY_RUN_JOB="${DRY_RUN_JOB:-false}"
DELETE_PREVIOUS_JOBS="${DELETE_PREVIOUS_JOBS:-false}"
PRESERVE_JOB_RESOURCES="${PRESERVE_JOB_RESOURCES:-true}"
JOB_NAME="${JOB_NAME:-cas-fs-migration-$(date +%Y%m%d-%H%M%S)}"
MIGRATION_PHASE="${MIGRATION_PHASE:-}"
MIGRATION_PVC_NAME="${MIGRATION_PVC_NAME:-${CAS_SERVICE_NAME}-migration-pvc}"

# Migration script tracking (computed at initialization)
MIGRATION_SCRIPT_FILE="${MIGRATION_SCRIPT_FILE:-${ROOT_DIR}/jobs/migration.sh}"
MIGRATION_SCRIPT_HASH=$(compute_script_hash "${MIGRATION_SCRIPT_FILE}" 2>/dev/null || echo "")
MIGRATION_CM_NAME="cas-migration-scripts-${MIGRATION_SCRIPT_HASH}"

cleanup_resources() {
	local namespace="${CAS_NAMESPACE}"

	logger info "Cleanup: all migration resources"

	if [[ "${PRESERVE_JOB_RESOURCES}" == "true" ]]; then
		logger info "Preserving resources for debugging"
		logger info "To delete all migration Jobs: oc delete jobs -n ${namespace} -l app=${MIGRATION_APP_LABEL}"
		logger info "To cleanup: PRESERVE_JOB_RESOURCES=false ./migrate-data-cache.sh --migration-phase cleanup"
		return 0
	fi

	# Delete all Jobs with MIGRATION_APP_LABEL
	logger info "Deleting all migration Jobs..."
	oc delete jobs -n "${namespace}" \
		-l "app=${MIGRATION_APP_LABEL}" \
		--ignore-not-found=true

	# Delete ConfigMaps created by this script
	logger info "Deleting migration ConfigMaps..."
	oc delete configmap -n "${namespace}" \
		-l "app=${MIGRATION_APP_LABEL}" \
		--ignore-not-found=true 2>/dev/null || true

	# Delete NetworkPolicy
	logger info "Deleting migration NetworkPolicy..."
	oc delete networkpolicy -n "${namespace}" \
		-l "app=${MIGRATION_APP_LABEL}" \
		--ignore-not-found=true 2>/dev/null || true

	# Delete migration PVC
	logger info "Deleting migration PVC: ${MIGRATION_PVC_NAME}"
	oc delete pvc "${MIGRATION_PVC_NAME}" -n "${namespace}" \
		--ignore-not-found=true

	# Delete RBAC resources (SA, Role, RoleBinding, ClusterRole, ClusterRoleBinding)
	logger info "Deleting migration RBAC resources..."
	export CAS_NAMESPACE="${namespace}"
	export MIGRATION_APP_LABEL
	envsubst < "${ROOT_DIR}/templates/migration/cas_migration_rbac.yaml" \
		| oc delete -f - --ignore-not-found=true 2>/dev/null || true

	logger success "Cleanup complete"
	return 0
}

# Trap handler for cleanup on exit
cleanup_on_exit() {
	local exit_code=$?
	if [[ -n "${JOB_NAME:-}" ]] && [[ -n "${CAS_NAMESPACE:-}" ]]; then
		# Preserve resources by default for debugging
		cleanup_resources "${JOB_NAME}" "${CAS_NAMESPACE}" "true"
	fi
	exit "${exit_code}"
}

trap cleanup_on_exit EXIT INT TERM

show_help() {
	cat << EOF
Usage: migrate-data-cache.sh --migration-phase <phase> [OPTIONS]

Orchestrate CAS data cache migration by launching Kubernetes Jobs.

REQUIRED:
  --migration-phase <phase>    Migration phase: pre, post, full, or cleanup

OPTIONS:
  --filesystem-name <name>     Filesystem name (default: ${FILESYSTEM_NAME})
  --cas-namespace <ns>         CAS namespace (default: ${CAS_NAMESPACE})
  --scale-namespace <ns>       Scale namespace (default: ${SCALE_NAMESPACE})
  --migration-pvc-name <name>  Migration PVC name (default: ${CAS_SERVICE_NAME}-migration-pvc)
  --job-name <name>            Custom job name (default: auto-generated)
  --timeout <seconds>          Job timeout (default: ${JOB_TIMEOUT})
  --skip-validation            Skip prerequisite validation (dangerous!)
  --dry-run                    Echo create/apply commands instead of executing
  --dry-run-job                Job echoes commands instead of executing (for testing)
  --help, -h                   Show this help

ENVIRONMENT VARIABLES:
  DELETE_PREVIOUS_JOBS=true    Delete existing Jobs for the phase before running (allows re-run after failure)
  PRESERVE_JOB_RESOURCES=false Delete all migration resources on exit (default: true — preserve for debugging)

PHASES:
  pre      Back up DataSources and record migration state before upgrades
  post     Restore DataSources from backup after upgrades; removes all migration resources on success
  full     Execute pre and post phases in sequence; removes all migration resources on success
  cleanup  Delete all migration resources (Jobs, ConfigMaps, NetworkPolicy, PVC, RBAC) without running a Job

EXAMPLES:
  # Pre-migration backup
  ./migrate-data-cache.sh --migration-phase pre

  # Post-migration restore with custom timeout
  ./migrate-data-cache.sh --migration-phase post --timeout 3600

  # Re-run after a failed pre (delete the previous failed Job first)
  DELETE_PREVIOUS_JOBS=true ./migrate-data-cache.sh --migration-phase pre

  # Tear down all migration resources after a confirmed complete migration
  PRESERVE_JOB_RESOURCES=false ./migrate-data-cache.sh --migration-phase cleanup

PREREQUISITES:
  - OpenShift cluster connection (oc login)
  - Cluster admin privileges
  - Fusion 2.12.x, CAS 1.1.4
  - Script-deployed cache-fs
EOF
}

require_argument_value() {
	local option="$1"
	local value="${2:-}"

	if [[ -z "$value" || "$value" == --* ]]; then
		logger error "Option ${option} requires a value"
		exit 1
	fi
}

parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--migration-phase)
			require_argument_value "$1" "${2:-}"
			MIGRATION_PHASE="$2"
			shift 2
			;;
		--filesystem-name)
			require_argument_value "$1" "${2:-}"
			FILESYSTEM_NAME="$2"
			shift 2
			;;
		--cas-namespace)
			require_argument_value "$1" "${2:-}"
			CAS_NAMESPACE="$2"
			shift 2
			;;
		--scale-namespace)
			require_argument_value "$1" "${2:-}"
			SCALE_NAMESPACE="$2"
			shift 2
			;;
		--migration-pvc-name)
			require_argument_value "$1" "${2:-}"
			MIGRATION_PVC_NAME="$2"
			shift 2
			;;
		--job-name)
			require_argument_value "$1" "${2:-}"
			JOB_NAME="$2"
			shift 2
			;;
		--timeout)
			require_argument_value "$1" "${2:-}"
			JOB_TIMEOUT="$2"
			shift 2
			;;
		--skip-validation)
			SKIP_VALIDATION=true
			shift
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		--dry-run-job)
			DRY_RUN_JOB=true
			shift
			;;
		--help | -h)
			show_help
			exit 0
			;;
		*)
			logger error "Unknown option: $1"
			echo "Use --help to see usage."
			exit 1
			;;
		esac
	done

	if [[ -z "${MIGRATION_PHASE}" ]]; then
		logger error "--migration-phase is required"
		show_help
		exit 1
	fi

	if [[ ! "${MIGRATION_PHASE}" =~ ^(pre|post|full|cleanup)$ ]]; then
		logger error "Invalid phase: ${MIGRATION_PHASE}"
		logger error "Must be: pre, post, full, or cleanup"
		exit 1
	fi
}

delete_previous_migration_jobs() {
	local namespace="${1}"
	local phase="${2}"
	local jobs

	jobs=$(oc get jobs -n "${namespace}" \
		-l "app=${MIGRATION_APP_LABEL},migration-phase=${phase}" \
		-o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

	if [[ -z "${jobs}" ]]; then
		logger info "No previous ${phase}-migration Jobs found to delete"
		return 0
	fi

	logger warn "Deleting previous ${phase}-migration Jobs"
	while IFS= read -r job_name; do
		[[ -z "${job_name}" ]] && continue
		logger info "Deleting Job: ${job_name}"
		oc delete job "${job_name}" -n "${namespace}" --ignore-not-found=true >/dev/null
	done <<< "${jobs}"

	logger success "Previous ${phase}-migration Jobs deleted"
	return 0
}

run_validations() {
	logger info "Starting CLI launcher prerequisite validation..."
	
	# Skip if requested (dangerous!)
	if [[ "${SKIP_VALIDATION}" == "true" ]]; then
		logger warn "Skipping validation (--skip-validation flag)"
		return 0
	fi

	# Run CLI launcher validations in sequence
	check_ocp_connection || exit 1
	check_cluster_admin || exit 1
	validate_cas_namespace "${CAS_NAMESPACE}" || exit 1

	if [[ "${DELETE_PREVIOUS_JOBS}" == "true" ]]; then
		delete_previous_migration_jobs "${CAS_NAMESPACE}" "${MIGRATION_PHASE}" || exit 1
	fi

	check_migration_state "${CAS_NAMESPACE}" "${MIGRATION_PHASE}" || exit 1
	
	logger success "All CLI launcher validations passed"
	logger info "Additional validations (versions, cache-fs, Scale namespace) will be performed by the migration script"
	return 0
}

ensure_migration_pvc() {
	local pvc_name="${1}"
	local namespace="${2}"
	
	logger info "Checking for migration PVC: ${pvc_name}"
	
	# Check if PVC already exists
	if oc get pvc "${pvc_name}" -n "${namespace}" &>/dev/null; then
		logger info "PVC exists: ${pvc_name}"
		return 0
	fi
	
	logger info "Creating migration PVC: ${pvc_name}"
	
	if [[ "${DRY_RUN}" == "true" ]]; then
		logger info "[DRY-RUN] Would create PVC: ${pvc_name}"
		logger info "[DRY-RUN]   StorageClass: ocs-storagecluster-cephfs"
		logger info "[DRY-RUN]   Size: 1Gi"
		return 0
	fi

	# Create PVC
	if ! cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: ${namespace}
  labels:
    app: cas-data-cache-migration
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: ocs-storagecluster-cephfs
EOF
	then
		logger error "Failed to create PVC: ${pvc_name}"
		return 1
	fi
	
	logger success "PVC created: ${pvc_name}"
	logger info "  StorageClass: ocs-storagecluster-cephfs"
	logger info "  Size: 1Gi"
	
	# Wait for PVC to be bound
	logger info "Waiting for PVC to be bound..."
	local timeout=60
	local elapsed=0
	while [[ ${elapsed} -lt ${timeout} ]]; do
		local status
		status=$(oc get pvc "${pvc_name}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
		
		if [[ "${status}" == "Bound" ]]; then
			logger success "PVC bound successfully"
			return 0
		fi
		
		sleep 2
		elapsed=$((elapsed + 2))
	done
	
	logger error "PVC did not bind within ${timeout} seconds"
	return 1
}

reconcile_configmap() {
	local template_file="${1}"
	local namespace="${2}"
	
	# Validate migration script exists
	if [[ ! -f "${MIGRATION_SCRIPT_FILE}" ]]; then
		logger error "Migration script not found: ${MIGRATION_SCRIPT_FILE}"
		return 1
	fi
	
	# Validate hash was computed
	if [[ -z "${MIGRATION_SCRIPT_HASH}" ]]; then
		logger error "Failed to compute migration script hash"
		return 1
	fi
	
	# Check if ConfigMap already exists
	if oc get configmap "${MIGRATION_CM_NAME}" -n "${namespace}" &>/dev/null; then
		logger info "ConfigMap exists: ${MIGRATION_CM_NAME}"
		logger info "Reusing (no changes detected)"
		return 0
	fi
	
	# Create new ConfigMap
	logger info "Creating ConfigMap: ${MIGRATION_CM_NAME}"
	
	# Read and indent the migration script for YAML
	local migration_script
	migration_script=$(sed 's/^/    /' "${MIGRATION_SCRIPT_FILE}")
	
	# Export variables for envsubst
	export MIGRATION_CM_NAME
	export MIGRATION_SCRIPT="${migration_script}"
	
	if [[ "${DRY_RUN}" == "true" ]]; then
		# shellcheck disable=SC2016
		logger info '[DRY-RUN] envsubst < ${template_file} | oc apply -f -'
		logger info "[DRY-RUN] ConfigMap would be created: ${MIGRATION_CM_NAME}"
	else
		if ! envsubst < "${template_file}" | oc apply -f -; then
			logger error "Failed to create ConfigMap"
			return 1
		fi
		logger success "ConfigMap created: ${MIGRATION_CM_NAME}"
	fi
	
	return 0
}

generate_and_apply_job() {
	local job_name="${1}"
	local migration_phase="${2}"
	local configmap_name="${3}"
	local timestamp="${4}"
	
	logger info "Creating Job: ${job_name}"
	
	# Export variables for envsubst
	export JOB_NAME="${job_name}"
	export MIGRATION_PHASE="${migration_phase}"
	export MIGRATION_CM_NAME="${configmap_name}"
	export MIGRATION_PVC_NAME="${MIGRATION_PVC_NAME}"
	export FILESYSTEM_NAME="${FILESYSTEM_NAME}"
	export CAS_NAMESPACE="${CAS_NAMESPACE}"
	export SCALE_NAMESPACE="${SCALE_NAMESPACE}"
	export MIGRATION_TIMESTAMP="${timestamp}"
	export DRY_RUN_JOB="${DRY_RUN_JOB}"
	
	# Generate and apply
	if [[ "${DRY_RUN}" == "true" ]]; then
		# shellcheck disable=SC2016
		logger info '[DRY-RUN] envsubst < ${ROOT_DIR}/templates/migration/cas_migration_job.yaml | oc apply -f -'
		logger info "[DRY-RUN] Job would be created: ${job_name}"
		logger info "[DRY-RUN]   Phase: ${migration_phase}"
		logger info "[DRY-RUN]   ConfigMap: ${configmap_name}"
	else
		if ! envsubst < "${ROOT_DIR}/templates/migration/cas_migration_job.yaml" | oc apply -f -; then
			logger error "Failed to create Job"
			envsubst < "${ROOT_DIR}/templates/migration/cas_migration_job.yaml"
			return 1
		fi
		logger success "Job created: ${job_name}"
		logger info "  Phase: ${migration_phase}"
		logger info "  ConfigMap: ${configmap_name}"
	fi
	return 0
}

ensure_migration_networkpolicy() {
	local namespace="${1}"
	
	logger info "Ensuring migration NetworkPolicy exists..."
	
	# Check if NetworkPolicy already exists
	if oc get networkpolicy cas-migration-network-policy -n "${namespace}" &>/dev/null; then
		logger info "NetworkPolicy exists: cas-migration-network-policy"
		return 0
	fi
	
	logger info "Creating migration NetworkPolicy..."
	
	if [[ "${DRY_RUN}" == "true" ]]; then
		# shellcheck disable=SC2016
		logger info '[DRY-RUN] envsubst < ${ROOT_DIR}/templates/migration/cas_migration_networkpolicy.yaml | oc apply -f -'
		logger info "[DRY-RUN] NetworkPolicy would be created: cas-migration-network-policy"
		return 0
	fi
	
	# Export variables for envsubst
	export CAS_NAMESPACE="${namespace}"
	export MIGRATION_APP_LABEL
	
	if ! envsubst < "${ROOT_DIR}/templates/migration/cas_migration_networkpolicy.yaml" | oc apply -f -; then
		logger error "Failed to create NetworkPolicy"
		return 1
	fi
	
	logger success "NetworkPolicy created: cas-migration-network-policy"
	return 0
}

ensure_migration_rbac() {
	local namespace="${1}"

	logger info "Ensuring migration RBAC resources exist..."

	if [[ "${DRY_RUN}" == "true" ]]; then
		# shellcheck disable=SC2016
		logger info '[DRY-RUN] envsubst < ${ROOT_DIR}/templates/migration/cas_migration_rbac.yaml | oc apply -f -'
		logger info "[DRY-RUN] RBAC resources would be created: cas-migration-sa, cas-migration-anyuid-scc-use, cas-migration-role"
		return 0
	fi

	export CAS_NAMESPACE="${namespace}"
	export MIGRATION_APP_LABEL

	if ! envsubst < "${ROOT_DIR}/templates/migration/cas_migration_rbac.yaml" | oc apply -f -; then
		logger error "Failed to create migration RBAC resources"
		return 1
	fi

	logger success "Migration RBAC resources applied"
	return 0
}

set_cas_csv_olm_managed() {
	local value="${1}"   # "true" or "false"
	local namespace="${2}"

	local csv_name
	csv_name=$(oc get csv -n "${namespace}" --no-headers \
		-o custom-columns=NAME:.metadata.name 2>/dev/null \
		| grep ibm-isf-cas-operator | head -n1)

	if [[ -z "${csv_name}" ]]; then
		logger warn "CAS CSV not found in namespace '${namespace}' — skipping olm.managed label"
		return 0
	fi

	logger info "Setting CSV '${csv_name}' olm.managed=${value}"
	oc label csv "${csv_name}" -n "${namespace}" "olm.managed=${value}" --overwrite || {
		logger warn "Failed to set olm.managed=${value} on CSV '${csv_name}' — continuing"
	}
}

delete_cas_webhooks() {
	local svc="ibm-isf-cas-operator-controller-manager-service"

	logger info "Removing webhooks referencing '${svc}'..."

	local mwc_names
	mwc_names=$(oc get mutatingwebhookconfigurations -o json 2>/dev/null \
		| jq -r --arg svc "${svc}" \
		  '.items[] | select(.webhooks[]?.clientConfig.service.name == $svc) | .metadata.name')

	local vwc_names
	vwc_names=$(oc get validatingwebhookconfigurations -o json 2>/dev/null \
		| jq -r --arg svc "${svc}" \
		  '.items[] | select(.webhooks[]?.clientConfig.service.name == $svc) | .metadata.name')

	if [[ -z "${mwc_names}" && -z "${vwc_names}" ]]; then
		logger info "No webhooks referencing '${svc}' found"
		return 0
	fi

	echo "${mwc_names}" | grep -v '^$' | while read -r name; do
		logger info "  Deleting MutatingWebhookConfiguration: ${name}"
		oc delete mutatingwebhookconfiguration "${name}" --ignore-not-found || true
	done

	echo "${vwc_names}" | grep -v '^$' | while read -r name; do
		logger info "  Deleting ValidatingWebhookConfiguration: ${name}"
		oc delete validatingwebhookconfiguration "${name}" --ignore-not-found || true
	done

	logger success "CAS webhooks removed"
}

generate_and_apply_resources() {
	local job_name="${1}"
	local migration_phase="${2}"
	local timestamp
	timestamp=$(date +%Y%m%d-%H%M%S)
	
	logger info "Generating migration resources..."

	# Pre-migration only: prevent OLM from restarting the operator while it is
	# intentionally scaled to 0, and clear any stale webhooks that would block
	# API writes against CAS CRs when the operator has no endpoints.
	if [[ "${migration_phase}" == "pre" || "${migration_phase}" == "full" ]]; then
		set_cas_csv_olm_managed "false" "${CAS_NAMESPACE}"
		delete_cas_webhooks
	fi

	# Step 1: Ensure RBAC resources exist (SA + SCC binding + Role + RoleBinding)
	ensure_migration_rbac "${CAS_NAMESPACE}" || return 1

	# Step 2: Ensure PVC exists
	ensure_migration_pvc "${MIGRATION_PVC_NAME}" "${CAS_NAMESPACE}" || return 1
	
	# Step 3: Ensure NetworkPolicy exists
	ensure_migration_networkpolicy "${CAS_NAMESPACE}" || return 1
	
	# Step 4: ConfigMap (updates MIGRATION_CM_NAME global)
	reconcile_configmap \
		"${ROOT_DIR}/templates/migration/cas_migration_configmap.yaml" \
		"${CAS_NAMESPACE}" || return 1

	# Step 5: Job
	generate_and_apply_job \
		"${job_name}" \
		"${migration_phase}" \
		"${MIGRATION_CM_NAME}" \
		"${timestamp}" || return 1

	logger success "Resources created"
	logger info "  ServiceAccount: cas-migration-sa"
	logger info "  PVC: ${MIGRATION_PVC_NAME}"
	logger info "  NetworkPolicy: cas-migration-network-policy"
	logger info "  ConfigMap: ${MIGRATION_CM_NAME}"
	logger info "  Job: ${job_name}"
	return 0
}

report_job_diagnostics() {
	local job_name="${1}"
	local namespace="${2}"

	logger info "Job diagnostics for: ${job_name}"

	local pod_name
	pod_name=$(oc get pods -n "${namespace}" \
		-l "job-name=${job_name}" \
		-o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

	logger info "--- Job Status ---"
	oc get job "${job_name}" -n "${namespace}" -o wide 2>&1 || true

	if [[ -n "${pod_name}" ]]; then
		logger info "--- Pod Status ---"
		oc get pod "${pod_name}" -n "${namespace}" -o wide 2>&1 || true

		logger info "--- Pod Describe ---"
		oc describe pod "${pod_name}" -n "${namespace}" 2>&1 || true

		logger info "--- Related Events ---"
		oc get events -n "${namespace}" \
			--field-selector "involvedObject.name=${pod_name}" \
			--sort-by=.lastTimestamp 2>&1 || true

		local pod_phase
		pod_phase=$(oc get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

		if [[ "${pod_phase}" == "Failed" ]]; then
			logger info "--- Pod Logs ---"
			oc logs "pod/${pod_name}" -n "${namespace}" 2>&1 || true
		fi
	else
		logger warn "No pod found for job diagnostics"
	fi

	logger info "--- Suggested Commands ---"
	logger info "oc describe job ${job_name} -n ${namespace}"
	logger info "oc get pods -n ${namespace} -l job-name=${job_name} -o wide"
	if [[ -n "${pod_name}" ]]; then
		logger info "oc describe pod ${pod_name} -n ${namespace}"
		logger info "oc get events -n ${namespace} --field-selector involvedObject.name=${pod_name} --sort-by=.lastTimestamp"
		logger info "oc logs pod/${pod_name} -n ${namespace}"
	fi

	return 0
}

report_migration_status() {
	local job_name="${1}"
	local namespace="${2}"
	local exit_code="${3}"

	logger info "==================================="
	logger info "Migration Status Report"
	logger info "==================================="
	logger info "Job: ${job_name}"
	logger info "Namespace: ${namespace}"

	if [[ ${exit_code} -eq 0 ]]; then
		logger success "Migration completed successfully"
	else
		logger error "Migration failed (exit code: ${exit_code})"
		logger error "Check logs: oc logs job/${job_name} -n ${namespace}"
		report_job_diagnostics "${job_name}" "${namespace}"
	fi

	logger info "==================================="
	logger info ""
	logger info "NOTICE: Migration PVC '${MIGRATION_PVC_NAME}' was created in namespace '${namespace}'"
	logger info "        This PVC can be deleted after migration completes:"
	logger info "        oc delete pvc ${MIGRATION_PVC_NAME} -n ${namespace}"
	
	return "${exit_code}"
}


main() {
	parse_arguments "$@"

	run_validations

	generate_and_apply_resources "${JOB_NAME}" "${MIGRATION_PHASE}" || exit 1

	if [[ "${DRY_RUN}" == "true" ]]; then
		logger success "[DRY-RUN] Migration Job '${JOB_NAME}' would be created in namespace '${CAS_NAMESPACE}'"
		logger info "[DRY-RUN] To execute for real, run without --dry-run flag"
		return 0
	fi

	logger success "Migration Job '${JOB_NAME}' created in namespace '${CAS_NAMESPACE}'"

	local job_exit_code=0
	if ! wait_for_job_pod_ready "${JOB_NAME}" "${CAS_NAMESPACE}" 60; then
		job_exit_code=1
	else
		stream_job_logs "${JOB_NAME}" "${CAS_NAMESPACE}" &
		local log_pid=$!

		if ! wait_for_job_completion "${JOB_NAME}" "${CAS_NAMESPACE}" "${JOB_TIMEOUT}"; then
			job_exit_code=1
		fi

		# Wait for log streaming to finish
		wait "${log_pid}" 2>/dev/null || true
	fi

	# Post-migration success: restore OLM management of the CAS operator
	if [[ ${job_exit_code} -eq 0 && ( "${MIGRATION_PHASE}" == "post" || "${MIGRATION_PHASE}" == "full" ) ]]; then
		set_cas_csv_olm_managed "true" "${CAS_NAMESPACE}"
	fi

	report_migration_status "${JOB_NAME}" "${CAS_NAMESPACE}" "${job_exit_code}"

	return "${job_exit_code}"
}

main "$@"
