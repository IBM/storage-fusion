#!/usr/bin/env bash
set -eu

# GUARD CLAUSE: Prevent sourcing this file multiple times
if [[ -n "${LOADED_FUSION_UTILS_SH:-}" ]]; then
    return 0
fi
export LOADED_FUSION_UTILS_SH=1

#========================================
# IBM Spectrum Fusion Utility Functions
#========================================
# Purpose: IBM Spectrum Fusion operator and service management
#
# Functions:
#   1. get_environment_type()
#   2. get_fusion_namespace()
#   3. deploy_fusion()
#   4. ensure_spectrum_fusion()
#   5. apply_spectrum_fusion()
#   6. is_fsi_deployed()
#   7. deploy_fsi()
#   8. deploy_scale_service()
#   9. is_scale_deployed()
#========================================

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

	if [[ "$operator_package_catalog" != "" ]]; then
		logger success "Package $FUSION_PACKAGE_NAME is available."
		CATALOG_NAMESPACE="$(echo "$operator_package_catalog" | cut -d '/' -f 1)"
		export CATALOG_NAMESPACE
		FUSION_CATALOG_NAME="$(echo "$operator_package_catalog" | cut -d '/' -f 2)"
		export FUSION_CATALOG_NAME
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
	oc get "$SPECTRUM_FUSION_CRD" "$SPECTRUM_FUSION" -n "$FUSION_NAMESPACE" >/dev/null 2>&1
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
    accept: true" | oc create -n "${FUSION_NAMESPACE}" -f - >/dev/null 2>&1
	logger success "Spectrum Fusion CR applied successfully."
}

#----------------------------------------
# Function: Check if Fusion service is deployed successfully
#----------------------------------------
is_fsi_deployed() {
	local SERVICE_NAME="${1}"
	logger info "Checking if $SERVICE_NAME is deployed successfully..."

	if oc get "$FUSION_SERVICE_INSTANCE_CR" "$SERVICE_NAME" -n "$FUSION_NAMESPACE" \
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
}

#----------------------------------------
# Function: Wait for Fusion service
#----------------------------------------
wait_for_fsi() {
	export SERVICE_NAME="${1}"
	export SERVICE_TEMPLATE="${2}"

	local timeout="${3:-$((FUSION_SERVICE_RETRY_COUNT * RETRY_INTERVAL))}"

	wait_for_condition \
		"Waiting for $SERVICE_NAME installation to complete" \
		"${timeout}" \
		"oc get '$FUSION_SERVICE_INSTANCE_CR' '$SERVICE_NAME' -n '$FUSION_NAMESPACE' -o jsonpath='{.status.installStatus.status}' 2>/dev/null | grep -q 'Completed'"
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
			install_status=$(oc get "$FUSION_SERVICE_INSTANCE_CR" "$SCALE_SERVICE_NAME" \
				-n "$FUSION_NAMESPACE" \
				-o jsonpath='{.status.installStatus.status}' 2>/dev/null)

			progress=$(oc get "$FUSION_SERVICE_INSTANCE_CR" "$SCALE_SERVICE_NAME" \
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
# Function: Check if IBM Storage Scale is deployed
#----------------------------------------
is_scale_deployed() {
	local env_type
	env_type=$(get_environment_type)

	local status

	if [[ "$env_type" == "$HCI_ENVIRONMENT" ]]; then
		status=$(oc get "$FUSION_SERVICE_INSTANCE_CR" "$SCALE_SERVICE_NAME" \
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

