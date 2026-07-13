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

# shellcheck source=lib/logging.sh
source "$ROOT_DIR/lib/logging.sh"
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
	# ── SHARED: Prerequisites ──────────────────────────────────────────────
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
	logger info "Detected env type: ${env_type}."

	# ── SHARED: Version Discovery ──────────────────────────────────────────
	fusion_installed="$(get_fusion_version)"
	fusion_ver="${fusion_installed:-$FUSION_VERSION}"
	logger info "Fusion version in use: ${fusion_ver} (installed: ${fusion_installed:-none})"

	odf_installed="$(get_odf_version)"
	odf_ver="${odf_installed:-$ODF_VERSION}"
	logger info "ODF version in use: ${odf_ver} (installed: ${odf_installed:-none})"

	cnsa_installed="$(get_cnsa_version)"
	# CNSA_VERSION is in product format (6.0.1.0); transform to CSV format (60.1.0) for comparison
	cnsa_ver="${cnsa_installed:-$(cnsa_product_to_csv "$CNSA_VERSION")}"
	logger info "CNSA version in use: ${cnsa_ver} (installed: ${cnsa_installed:-none})"

	cas_installed="$(get_cas_version)"
	# CAS_VERSION may have a leading 'v'; strip it for consistency with get_cas_version output
	cas_ver="${cas_installed:-${CAS_VERSION#v}}"
	logger info "CAS version in use: ${cas_ver} (installed: ${cas_installed:-none})"

	CNSA_GTE_6010=$(version_gte "${cnsa_ver}" "60.1.0")
	CAS_GTE_115=$(version_gte "${cas_ver}" "1.1.5")

	# ── FUSION: Discover or use target version ─────────────────────────────
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

	# ── DATA FOUNDATION: Discover or use target version ────────────────────
	if [[ -z "$(is_fsi_deployed "$DF_SERVICE_NAME")" ]]; then
		deploy_fsi "$DF_SERVICE_NAME" "templates/fusion/data_foundation.yaml"
	else
		logger info "FDF is already deployed."
	fi

	wait_for_fsi "$DF_SERVICE_NAME" "templates/fusion/data_foundation.yaml"

	if [[ -z "$(is_fdf_configured)" ]]; then
		logger info "FDF not configured or not Ready. Configuring now..."
		configure_fdf
	else
		logger success "FDF is already configured."
	fi

	patch_ceph_csi_drivers

	create_scale_rbd_sc

	# ── CNSA: Discover or use target version ──────────────────────────────
	if [[ "${CNSA_GTE_6010}" == false ]]; then
		# < 6.0.1.0: Scale is FSI-managed, manual PVC + daemonset + RBD SC
		if is_scale_deployed; then
			logger success "IBM Storage Scale is already deployed."
		else
			logger info "IBM Storage Scale not detected. Deploying..."
			deploy_scale_service
		fi

		ensure_project "$LOCAL_STORAGE_PROJECT"
		create_pvc_local_disks
		create_expose_rbd_daemonset
	fi

	# ── SHARED: Scale cluster ──────────────────────────────────────────────
	if ! is_scale_cluster_created; then
		SCALE_CLUSTER_NAME="${SCALE_CLUSTER_NAME:-$(get_cluster_base_domain)}"
		create_scale_cluster
	fi

	verify_scale_cluster

	# ── Filesystem Creation: version-gated ──────────────────────────────────
	if [[ "${CAS_GTE_115}" == false ]] || [[ "${CNSA_GTE_6010}" == false ]]; then
		if ! is_fs_created; then
			logger info "Configuring CNSA with $FILESYSTEM_NAME filesystem and $FILESYSTEM_CAPACITY size..."
			create_fs "${CNSA_GTE_6010}"
		fi

		verify_fs
		patch_scale_csi_driver

		if [[ "${CNSA_GTE_6010}" == false ]]; then
			validate_local_disks_usage
		fi
	fi

	if [[ "${CAS_GTE_115}" == false ]]; then
		configure_afm
		verify_afm_config
		scale_set_config "syncReadWFConfig" "yes"
		scale_set_config "afmPtrashOpt" "3"
		logger success "Scale AFM config set"
	fi

	if [[ "${CAS_GTE_115}" == true ]]; then
		# HACK: Workaround for missing cas-operator RBAC for labeling nodes
		ensure_node_labeling_rbac
	fi

	# ── SHARED: CAS deploy ─────────────────────────────────────────────────
	if [[ -z "$(is_fsi_deployed "$CAS_SERVICE_NAME")" ]]; then
		patch_cas_fsd
		deploy_fsi "${CAS_SERVICE_NAME}" "templates/fusion/content_aware_storage.yaml"
	else
		logger info "${CAS_SERVICE_NAME} is already deployed."
	fi

	wait_for_casinstall "${CAS_NAMESPACE}" "${CAS_SERVICE_NAME}"

	logger info "Patching CasInstall"
	patch_cas_install "${CAS_NAMESPACE}" "${CAS_SERVICE_NAME}" "${CAS_GTE_115}" "${CNSA_GTE_6010}"

	# ── Post-CAS-install: version-gated ───────────────────────────────────
	if [[ "${CAS_GTE_115}" == true ]]; then
		patch_scale_csi_driver
		wait_for_fsi "${CAS_SERVICE_NAME}" "templates/fusion/content_aware_storage.yaml" "${CAS_SERVICE_TIMEOUT}"
		verify_cas_install
	else
		wait_for_fsi "${CAS_SERVICE_NAME}" "templates/fusion/content_aware_storage.yaml" "${CAS_SERVICE_TIMEOUT}"
		delete_scale_rbd_sc
		configure_scale_watch "${CAS_NAMESPACE}" "${FILESYSTEM_NAME}"
		logger success "Scale watch configured"
	fi

	logger success "Local Data Caching has been successfully configured for CAS! 🎉"
}

main "$@"
