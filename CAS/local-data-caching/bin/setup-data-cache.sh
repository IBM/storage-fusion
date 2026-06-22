#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Exporting secrets and constants
set -a
# shellcheck source=lib/constants.sh
source "$ROOT_DIR/lib/constants.sh"
# shellcheck source=config/config.env
source "$ROOT_DIR/config/config.env"
set +a

# shellcheck source=lib/utils.sh
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
# shellcheck source=modules/ocp_cluster_utils.sh
source "$ROOT_DIR/modules/ocp_cluster_utils.sh"
# shellcheck source=modules/olm_utils.sh
source "$ROOT_DIR/modules/olm_utils.sh"
# shellcheck source=modules/fusion_utils.sh
source "$ROOT_DIR/modules/fusion_utils.sh"
# shellcheck source=modules/df_utils.sh
source "$ROOT_DIR/modules/df_utils.sh"
# shellcheck source=modules/scale_utils.sh
source "$ROOT_DIR/modules/scale_utils.sh"
# shellcheck source=modules/cas_utils.sh
source "$ROOT_DIR/modules/cas_utils.sh"

# Main function
main() {
	logger info "Checking prerequisites..."

	check_ocp_connection

	OCP_VERSION=$(get_ocp_version)
	export OCP_VERSION
	is_supported_ocp_version "${OCP_VERSION}"
	check_cluster_admin
	validate_nodes

	if ! oc get packagemanifests "$LSO_PACKAGE" &>/dev/null; then
		logger error "${LSO_PACKAGE} must be available prior to configuring Fusion Data Caching."
	fi

	env_type="$(get_environment_type)"

	logger info "Detected env type: ${env_type}." # Checking HCI vs SDS

	# # Install fusion if not already installed
	if [[ "${env_type}" == "${SDS_ENVIRONMENT}" ]]; then
		if [[ -z "$(is_operator_installed "$FUSION_PACKAGE_NAME")" ]]; then
			deploy_fusion "${env_type}"
		else
			logger success "Fusion operator is already installed."
		fi
	fi

	# # Apply spectrum fusion CR if not present
	if ! ensure_spectrum_fusion; then
		logger info "Spectrum Fusion CR not found. Applying..."
		apply_spectrum_fusion
	else
		logger success "Spectrum Fusion CR already present in namespace '$FUSION_NAMESPACE'."
	fi

	# # Install FDF if not already installed
	if [[ -z "$(is_fsi_deployed "$DF_SERVICE_NAME")" ]]; then
		deploy_fsi "$DF_SERVICE_NAME" "templates/fusion/data_foundation.yaml"
	else
		logger info "FDF is already deployed."
	fi

	wait_for_fsi "$DF_SERVICE_NAME" "templates/fusion/data_foundation.yaml"

	# Configure FDF if not already configured
	if [[ -z "$(is_fdf_configured)" ]]; then
		logger info "FDF not configured or not Ready. Configuring now..."
		configure_fdf
	else
		logger success "FDF is already configured."
	fi

	patch_ceph_csi_drivers

	create_scale_rbd_sc

	# Create scale cluster if not exist
	if ! is_scale_cluster_created; then
		SCALE_CLUSTER_NAME="${SCALE_CLUSTER_NAME:-$(get_cluster_base_domain)}"
		create_scale_cluster
	fi

	verify_scale_cluster

	create_scale_rbd_sc

	# HACK: Workaround for missing cas-operator RBAC for labeling nodes
	ensure_node_labeling_rbac

	# Install CAS if not already installed
	if [[ -z "$(is_fsi_deployed "$CAS_SERVICE_NAME")" ]]; then
		patch_cas_fsd
		deploy_fsi "${CAS_SERVICE_NAME}" "templates/fusion/content_aware_storage.yaml"
	else
		logger info "${CAS_SERVICE_NAME} is already deployed."
	fi

	wait_for_casinstall "${CAS_NAMESPACE}" "${CAS_SERVICE_NAME}"

	logger info "Patching CasInstall"
	patch_cas_install "${CAS_NAMESPACE}" "${CAS_SERVICE_NAME}"

	patch_scale_csi_driver

	wait_for_fsi "${CAS_SERVICE_NAME}" "templates/fusion/content_aware_storage.yaml" "${CAS_SERVICE_TIMEOUT}"

	delete_scale_rbd_sc

	logger success "Local Data Caching has been successfully configured for CAS! 🎉"
}

main "$@"
