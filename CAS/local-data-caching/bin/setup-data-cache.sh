#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Exporting secrets and constants
set -a
source "$ROOT_DIR/lib/constants.sh"
source "$ROOT_DIR/config/config.env"
set +a

source "$ROOT_DIR/lib/utils.sh"

# Parse arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	--filesystem-name)
		FILESYSTEM_NAME="$2"
		shift 2
		;;
	--filesystem-capacity)
		FILESYSTEM_CAPACITY="$2"
		shift 2
		;;
	--help | -h)
		help
		exit 0
		;;
	*)
		echo "Unknown option: $1"
		echo "Use --help to see usage."
		exit 1
		;;
	esac
done

# Source libraries and modules
source "$ROOT_DIR/modules/ocp_cluster_utils.sh"
source "$ROOT_DIR/modules/olm_utils.sh"
source "$ROOT_DIR/modules/dataservices_utils.sh"
source "$ROOT_DIR/modules/cas_utils.sh"

# Main function
main() {
	logger info "Checking prerequisites..."

	check_ocp_connection
	is_supported_ocp_version
	check_cluster_admin
	validate_nodes

	if ! oc get packagemanifests "$LSO_PACKAGE" &>/dev/null; then
		logger error "${LSO_PACKAGE} must be available prior to configuring Fusion Data Caching."
	fi

	env_type="$(get_environment_type)"

	logger info "Detected env type: ${env_type}." # Checking HCI vs SDS

	# Install fusion if not already installed
	if [[ "${env_type}" == "${SDS_ENVIRONMENT}" ]]; then
		if [[ -z "$(is_operator_installed "$FUSION_PACKAGE_NAME")" ]]; then
			deploy_fusion "${env_type}"
		else
			logger success "Fusion operator is already installed."
		fi
	fi

	# Apply spectrum fusion CR if not present
	if ! ensure_spectrum_fusion; then
		logger info "Spectrum Fusion CR not found. Applying..."
		apply_spectrum_fusion
	else
		logger success "Spectrum Fusion CR already present in namespace '$FUSION_NAMESPACE'."
	fi

	# Install FDF if not already installed
	if [[ -z "$(is_fsi_deployed "$DF_SERVICE_NAME")" ]]; then
		deploy_fsi "$DF_SERVICE_NAME" "templates/fusion/data_foundation.yaml"
	else
		logger success "FDF is already deployed."
	fi

	# Configure FDF if not already configured
	if [[ -z "$(is_fdf_configured)" ]]; then
		logger info "FDF not configured or not Ready. Configuring now..."
		configure_fdf
	else
		logger success "FDF is already configured."
	fi

	# Deploy IBM Storage Scale if not already installed
	if is_scale_deployed; then
		logger success "IBM Storage Scale is already deployed."
	else
		logger info "IBM Storage Scale not detected. Deploying..."
		deploy_scale_service
	fi

	logger info "Configuring CNSA with $FILESYSTEM_NAME filesystem and $FILESYSTEM_CAPACITY size in $LOCAL_STORAGE_PROJECT..."

	ensure_project $LOCAL_STORAGE_PROJECT

	create_pvc_local_disks
	create_expose_rbd_daemonset

	# Create scale cluster if not exist
	if ! is_scale_cluster_created; then
		create_scale_cluster
	fi

	verify_scale_cluster

	get_device_ids_for_local_disks

	patch_device_regex_in_scale_cluster

	ensure_local_disks

	create_fs
	verify_fs

	validate_local_disks_usage

	## Set up AFM
	configure_afm
	verify_afm_config

	scale_set_config "syncReadWFConfig" "yes"
	scale_set_config "afmPtrashOpt" "3"
	logger success "Scale AFM config set"

	## Install CAS if not already installed
	if [[ -z "$(is_fsi_deployed "$CAS_SERVICE_NAME")" ]]; then
		deploy_fsi "${CAS_SERVICE_NAME}" "templates/fusion/content_aware_storage.yaml"
	else
		logger success "${CAS_SERVICE_NAME} is already deployed."
	fi

	## Create Scale Watch configuration for CAS
	configure_scale_watch "${CAS_NAMESPACE}" "${FILESYSTEM_NAME}"
	logger success "Scale watch configured"

	logger success "CAS Data Caching has been successfully installed! 🎉"
}

main "$@"
