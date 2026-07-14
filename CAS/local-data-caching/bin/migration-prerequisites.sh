#!/usr/bin/env bash
# start_Copyright_Notice
# Licensed Materials - Property of IBM

# IBM Spectrum Fusion 5900-AOY
# (C) Copyright IBM Corp. 2022 All Rights Reserved.

# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

#========================================
# Migration Prerequisites Validation Script
#========================================
# Purpose: Validate environment meets all prerequisites before migration
#
# This script runs as the first step of the migration Job to ensure:
#   1. Fusion is installed at a supported version
#   2. Data Foundation is installed at a supported version
#   3. CAS is installed at a supported version
#   4. Script-deployed local cache filesystem exists
#   5. S3 datasource(s) using cache-fs exist
#   6. Store validation state for idempotent execution
#========================================

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source required libraries
# shellcheck source=lib/constants.sh
source "${PROJECT_ROOT}/lib/constants.sh"
# shellcheck source=lib/logging.sh
source "${PROJECT_ROOT}/lib/logging.sh"
# shellcheck source=lib/utils.sh
source "${PROJECT_ROOT}/lib/utils.sh"
# shellcheck source=config/config.env
source "${PROJECT_ROOT}/config/config.env"
# shellcheck source=modules/ocp_cluster_utils.sh
source "${PROJECT_ROOT}/modules/ocp_cluster_utils.sh"
# shellcheck source=modules/fusion_utils.sh
source "${PROJECT_ROOT}/modules/fusion_utils.sh"
# shellcheck source=modules/df_utils.sh
source "${PROJECT_ROOT}/modules/df_utils.sh"
# shellcheck source=modules/scale_utils.sh
source "${PROJECT_ROOT}/modules/scale_utils.sh"
# shellcheck source=modules/cas_utils.sh
source "${PROJECT_ROOT}/modules/cas_utils.sh"
# shellcheck source=modules/olm_utils.sh
source "${PROJECT_ROOT}/modules/olm_utils.sh"

#========================================
# Version Comparison Utilities
#========================================

#----------------------------------------
# Function: Compare semantic versions
# Returns: 0 if version1 >= version2, 1 otherwise
#----------------------------------------
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Remove 'v' prefix if present
    version1="${version1#v}"
    version2="${version2#v}"
    
    # Split versions into arrays
    IFS='.' read -ra ver1 <<< "${version1}"
    IFS='.' read -ra ver2 <<< "${version2}"
    
    # Compare each component
    for i in {0..2}; do
        local v1="${ver1[$i]:-0}"
        local v2="${ver2[$i]:-0}"
        
        # Remove non-numeric suffixes (e.g., "1.2.3-beta" -> "1.2.3")
        v1="${v1%%[^0-9]*}"
        v2="${v2%%[^0-9]*}"
        
        if (( v1 > v2 )); then
            return 0
        elif (( v1 < v2 )); then
            return 1
        fi
    done
    
    return 0  # Versions are equal
}

#========================================
# Validation Functions
#========================================

#----------------------------------------
# Function: Validate Fusion installation and version
#----------------------------------------
validate_fusion() {
    logger info "Validating IBM Spectrum Fusion installation..."
    
    local env_type
    env_type=$(get_environment_type)
    echo "FUSION_ENVIRONMENT_TYPE: ${env_type}"
    
    local fusion_ns
    if [[ "${env_type}" == "${HCI_ENVIRONMENT}" ]]; then
        fusion_ns="${HCI_FUSION_NAMESPACE}"
    else
        fusion_ns="${FUSION_NAMESPACE}"
    fi
    echo "FUSION_NAMESPACE: ${fusion_ns}"

    # Check if Fusion operator is installed
    if ! oc get csv -n "${fusion_ns}" 2>/dev/null | grep "${FUSION_PACKAGE_NAME}"; then
        logger error "Fusion operator not found in namespace ${fusion_ns}"
        echo "FUSION_INSTALLED: false"
        FUSION_VERSION_FOUND="N/A"
        return 1
    fi
    
    # Get Fusion version
    FUSION_VERSION_FOUND=$(oc get csv -n "${fusion_ns}" -o jsonpath='{.items[?(@.spec.displayName=="IBM Storage Fusion")].spec.version}' 2>/dev/null | head -n1)
    
    if [[ -z "${FUSION_VERSION_FOUND}" ]]; then
        logger error "Unable to determine Fusion version"
        echo "FUSION_INSTALLED: false"
        FUSION_VERSION_FOUND="Unknown"
        return 1
    fi
    
    echo "FUSION_VERSION: ${FUSION_VERSION_FOUND}"
    logger info "Detected Fusion version: ${FUSION_VERSION_FOUND}"
    
    # Validate version meets minimum requirement
    if ! version_compare "${FUSION_VERSION_FOUND}" "${FUSION_VERSION}"; then
        logger error "Fusion version ${FUSION_VERSION_FOUND} is below minimum required version ${FUSION_VERSION}"
        echo "FUSION_VERSION_VALID: false"
        return 1
    fi
    
    echo "FUSION_INSTALLED: true"
    echo "FUSION_VERSION_VALID: true"
    logger success "Fusion validation passed: version ${FUSION_VERSION_FOUND} >= ${FUSION_VERSION}"
    
    return 0
}

#----------------------------------------
# Function: Validate Data Foundation installation and version
#----------------------------------------
validate_data_foundation() {
    logger info "Validating OpenShift Data Foundation installation..."
    
    logger info "${OCS_NAMESPACE}"
    # Check if ODF namespace exists
    if ! oc get namespace "${OCS_NAMESPACE}" &>/dev/null; then
        logger error "ODF namespace ${OCS_NAMESPACE} not found"
        echo "DF_INSTALLED: false"
        DF_VERSION_FOUND="N/A"
        DF_STATUS_FOUND="N/A"
        return 1
    fi
    
    # Check if StorageCluster exists
    if ! oc get "${STORAGE_CLUSTER}" "${OCS_CLUSTER_NAME}" -n "${OCS_NAMESPACE}" &>/dev/null; then
        logger error "StorageCluster ${OCS_CLUSTER_NAME} not found in namespace ${OCS_NAMESPACE}"
        echo "DF_INSTALLED: false"
        DF_VERSION_FOUND="N/A"
        DF_STATUS_FOUND="N/A"
        return 1
    fi
    
    # Check StorageCluster status
    local df_status
    df_status=$(oc get "${STORAGE_CLUSTER}" "${OCS_CLUSTER_NAME}" -n "${OCS_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null)
    DF_STATUS_FOUND="${df_status}"
    
    if [[ "${df_status}" != "Ready" ]]; then
        logger error "StorageCluster status is '${df_status}', expected 'Ready'"
        echo "DF_STATUS: ${df_status}"
        echo "DF_READY: false"
        return 1
    fi
    
    # Get ODF version from CSV
    local df_version
    df_version=$(oc get csv -n "${OCS_NAMESPACE}" -o json | jq -r '.items[] | select(.spec.displayName | contains("Data Foundation")) | .spec.version' | head -n1)
    
    if [[ -z "${df_version}" ]]; then
        # Try alternative display name
        df_version=$(oc get csv -n "${OCS_NAMESPACE}" -o jsonpath='{.items[?(@.spec.displayName=="OpenShift Container Storage")].spec.version}' 2>/dev/null | head -n1)
    fi
    
    if [[ -z "${df_version}" ]]; then
        logger warn "Unable to determine Data Foundation version, proceeding with caution"
        echo "DF_VERSION: unknown"
        echo "DF_VERSION_VALID: unknown"
        DF_VERSION_FOUND="Unknown"
    else
        DF_VERSION_FOUND="${df_version}"
        echo "DF_VERSION: ${df_version}"
        logger info "Detected Data Foundation version: ${df_version}"
        
        # Validate version meets minimum requirement
        local min_df_version="${DATA_FOUNDATION_MIN_VERSION:-4.20.0}"
        if ! version_compare "${df_version}" "${min_df_version}"; then
            logger error "Data Foundation version ${df_version} is below minimum required version ${min_df_version}"
            echo "DF_VERSION_VALID: false"
            return 1
        fi
        
        echo "DF_VERSION_VALID: true"
        logger success "Data Foundation version validation passed: ${df_version} >= ${min_df_version}"
    fi
    
    echo "DF_INSTALLED: true"
    echo "DF_STATUS: ${df_status}"
    echo "DF_READY: true"
    logger success "Data Foundation validation passed"
    
    return 0
}

#----------------------------------------
# Function: Validate CAS installation and version
#----------------------------------------
validate_cas() {
    logger info "Validating Content Aware Storage (CAS) installation..."
    
    # Check if CAS namespace exists
    if ! oc get namespace "${CAS_NAMESPACE}"; then
        logger error "CAS namespace ${CAS_NAMESPACE} not found"
        echo "CAS_INSTALLED: false"
        CAS_VERSION_FOUND="N/A"
        CAS_STATUS_FOUND="N/A"
        return 1
    fi
    
    # Check if CAS service instance exists
    local cas_instance
    cas_instance=$(oc get FusionServiceInstance -n "${FUSION_NAMESPACE}" --no-headers | awk '{print $1}' | grep ibm-cas-service-instance)
    
    if [[ -z "${cas_instance}" ]]; then
        logger error "CAS service instance not found in namespace ${FUSION_NAMESPACE}"
        echo "CAS_INSTALLED: false"
        CAS_VERSION_FOUND="N/A"
        CAS_STATUS_FOUND="N/A"
        return 1
    fi
    
    echo "CAS_INSTANCE_NAME: ${cas_instance}"
    
    # Check CAS installation status
    local cas_status
    cas_status=$(oc get FusionServiceInstance "${cas_instance}" -n "${FUSION_NAMESPACE}" \
        -o jsonpath='{.status.installStatus.status}' 2>/dev/null)
    CAS_STATUS_FOUND="${cas_status}"
    
    if [[ "${cas_status}" != "Completed" ]]; then
        logger error "CAS installation status is '${cas_status}', expected 'Completed'"
        echo "CAS_STATUS: ${cas_status}"
        echo "CAS_READY: false"
        return 1
    fi
    
    # Get CAS version
    local cas_version
    cas_version=$(oc get FusionServiceInstance "${cas_instance}" -n "${FUSION_NAMESPACE}" \
        -o jsonpath='{.status.currentVersion}')
    logger info "${cas_version}"
    if [[ -z "${cas_version}" ]]; then
        logger warn "Unable to determine CAS version, proceeding with caution"
        echo "CAS_VERSION: unknown"
        echo "CAS_VERSION_VALID: unknown"
        CAS_VERSION_FOUND="Unknown"
    else
        CAS_VERSION_FOUND="${cas_version}"
        echo "CAS_VERSION: ${cas_version}"
        logger info "Detected CAS version: ${cas_version}"
        
        # Validate version meets minimum requirement
        local min_cas_version="${CAS_MIN_VERSION:-1.1.3}"
        if ! version_compare "${cas_version}" "${min_cas_version}"; then
            logger error "CAS version ${cas_version} is below minimum required version ${min_cas_version}"
            echo "CAS_VERSION_VALID: false"
            return 1
        fi
        
        echo "CAS_VERSION_VALID: true"
        logger success "CAS version validation passed: ${cas_version} >= ${min_cas_version}"
    fi
    
    echo "CAS_INSTALLED: true"
    echo "CAS_STATUS: ${cas_status}"
    echo "CAS_READY: true"
    logger success "CAS validation passed"
    
    return 0
}

#----------------------------------------
# Function: Validate local cache filesystem exists
#----------------------------------------
validate_cache_filesystem() {
    logger info "Validating local cache filesystem..."
    
    # Check if Scale namespace exists
    if ! oc get namespace "${SCALE_NAMESPACE}"; then
        logger error "Scale namespace ${SCALE_NAMESPACE} not found"
        echo "CACHE_FS_EXISTS: false"
        FS_NAME_FOUND="N/A"
        FS_CAPACITY_FOUND="N/A"
        return 1
    fi
    
    # Check if filesystem exists
    local fs_name="${FILESYSTEM_NAME}"
    FS_NAME_FOUND="${fs_name}"
    
    if ! oc get filesystem "${fs_name}" -n "${SCALE_NAMESPACE}" &>/dev/null; then
        logger error "Cache filesystem '${fs_name}' not found in namespace ${SCALE_NAMESPACE}"
        echo "CACHE_FS_EXISTS: false"
        echo "CACHE_FS_NAME: ${fs_name}"
        FS_CAPACITY_FOUND="N/A"
        return 1
    fi
    
    # Check filesystem status
    local fs_success fs_healthy fs_success_reason fs_healthy_reason
    fs_success=$(oc get filesystem "${fs_name}" -n "${SCALE_NAMESPACE}" \
        -o jsonpath='{.status.conditions[?(@.type=="Success")].status}')
    fs_success_reason=$(oc get filesystem "${fs_name}" -n "${SCALE_NAMESPACE}" \
        -o jsonpath='{.status.conditions[?(@.type=="Success")].reason}')
    fs_healthy=$(oc get filesystem "${fs_name}" -n "${SCALE_NAMESPACE}" \
        -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}')
    fs_healthy_reason=$(oc get filesystem "${fs_name}" -n "${SCALE_NAMESPACE}" \
        -o jsonpath='{.status.conditions[?(@.type=="Healthy")].reason}')
    
    if [[ "${fs_success}" != "True" ]]; then
        if [[ "${fs_success_reason}" != "NotSupported" ]]; then
            logger error "Cache filesystem '${fs_name}' is not healthy (Success=${fs_success}, Healthy=${fs_healthy})"
            echo "CACHE_FS_EXISTS: true"
            echo "CACHE_FS_NAME: ${fs_name}"
            echo "CACHE_FS_SUCCESS: false"
            echo "CACHE_FS_SUCCESS_REASON: ${fs_success_reason}"
            return 1
        fi
    fi

    if [[ "${fs_healthy}" != "True" ]]; then
        if [[ "${fs_healthy_reason}" != "NotSupported" ]]; then
            logger error "Cache filesystem '${fs_name}' is not healthy (Success=${fs_success}, Healthy=${fs_healthy})"
            echo "CACHE_FS_EXISTS: true"
            echo "CACHE_FS_NAME: ${fs_name}"
            echo "CACHE_FS_HEALTHY: false"
            echo "CACHE_FS_HEALTHY_REASON: ${fs_healthy_reason}"
            return 1
        fi
    fi
    
    # Get filesystem capacity
    local fs_capacity
    fs_capacity=$(oc get filesystem "${fs_name}" -n "${SCALE_NAMESPACE}" \
        -o jsonpath='{.spec.localDiskCapacity}')
    FS_CAPACITY_FOUND="${fs_capacity:-N/A}"
    
    echo "CACHE_FS_EXISTS: true"
    echo "CACHE_FS_NAME: ${fs_name}"
    echo "CACHE_FS_SUCCESS: true"
    echo "CACHE_FS_SUCCESS_REASON: ${fs_success_reason}"
    echo "CACHE_FS_HEALTHY: true"
    echo "CACHE_FS_HEALTHY_REASON: ${fs_healthy_reason}"
    echo "CACHE_FS_CAPACITY: ${fs_capacity}"
    
    logger success "Cache filesystem validation passed: '${fs_name}' is healthy with capacity ${fs_capacity}"
    
    return 0
}

#----------------------------------------
# Function: Validate S3 datasources using cache filesystem
#----------------------------------------
validate_s3_datasources() {
    logger info "Validating S3 datasources using cache filesystem..."
    
    local fs_name="${FILESYSTEM_NAME}"
    local datasource_count=0
    local valid_datasources=""
    
    # Get all datasources in CAS namespace
    local datasources
    datasources=$(oc get datasources -n "${CAS_NAMESPACE}" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null)
    
    if [[ -z "${datasources}" ]]; then
        logger warn "No datasources found in namespace ${CAS_NAMESPACE}"
        S3_COUNT_FOUND="0"
        echo "S3_DATASOURCES_COUNT: 0"
        echo "S3_DATASOURCES_VALID: false"
        return 2
    fi
    
    # Check each datasource for S3 type and cache-fs usage.
    # S3 datasources have spec.s3 populated; the filesystem name is spec.s3.fileSystemName.
    for ds in ${datasources}; do
        local ds_cache_fs
        ds_cache_fs=$(oc get datasource "${ds}" -n "${CAS_NAMESPACE}" \
            -o jsonpath='{.spec.s3.fileSystemName}')
        
        if [[ "${ds_cache_fs}" == "${fs_name}" ]]; then
            ((datasource_count++))
            valid_datasources="${valid_datasources}${ds} "
            logger info "Found valid S3 datasource: ${ds} using cache filesystem ${fs_name}"
        fi
    done
    
    S3_COUNT_FOUND="${datasource_count}"
    
    if [[ ${datasource_count} -eq 0 ]]; then
        logger error "No S3 datasources found using cache filesystem '${fs_name}'"
        echo "S3_DATASOURCES_COUNT: 0"
        echo "S3_DATASOURCES_VALID: false"
        return 1
    fi
    
    echo "S3_DATASOURCES_COUNT: ${datasource_count}"
    echo "S3_DATASOURCES_LIST: ${valid_datasources% }"
    echo "S3_DATASOURCES_VALID: true"
    
    logger success "S3 datasource validation passed: Found ${datasource_count} datasource(s) using cache filesystem"
    
    return 0
}

#========================================
# Main Validation Orchestration
#========================================

# Global variables to store validation results
FUSION_VERSION_FOUND=""
DF_VERSION_FOUND=""
DF_STATUS_FOUND=""
CAS_VERSION_FOUND=""
CAS_STATUS_FOUND=""
FS_NAME_FOUND=""
FS_CAPACITY_FOUND=""
S3_COUNT_FOUND=""

#----------------------------------------
# Function: Print validation summary table
#----------------------------------------
print_validation_summary() {
    local fusion_status="$1"
    local df_status="$2"
    local cas_status="$3"
    local fs_status="$4"
    local s3_status="$5"
    local overall_status="$6"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           MIGRATION PREREQUISITES VALIDATION SUMMARY                               ║"
    echo "╠════════════════════════════════════════════════════════════════════════════════════════════════════╣"
    echo "║ Component                                     Status                      Details                  ║"
    echo "╠════════════════════════════════════════════════════════════════════════════════════════════════════╣"
    printf "║ %-45s %-27s %-25s ║\n" "IBM Spectrum Fusion" "${fusion_status}" "v${FUSION_VERSION_FOUND}"
    printf "║ %-45s %-27s %-25s ║\n" "OpenShift Data Foundation" "${df_status}" "v${DF_VERSION_FOUND} (${DF_STATUS_FOUND})"
    printf "║ %-45s %-27s %-25s ║\n" "Content Aware Storage (CAS)" "${cas_status}" "v${CAS_VERSION_FOUND} (${CAS_STATUS_FOUND})"
    printf "║ %-45s %-27s %-25s ║\n" "Local Cache Filesystem" "${fs_status}" "${FS_NAME_FOUND} (${FS_CAPACITY_FOUND:-N/A})"
    printf "║ %-45s %-27s %-25s ║\n" "S3 Datasources" "${s3_status}" "${S3_COUNT_FOUND} datasource(s)"
    echo "╠════════════════════════════════════════════════════════════════════════════════════════════════════╣"
    printf "║ %-45s %-27s %-25s ║\n" "OVERALL VALIDATION" "${overall_status}" ""
    echo "╚════════════════════════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
}

#----------------------------------------
# Function: Run all validations
#----------------------------------------
run_all_validations() {
    local overall_status=0
    local failed_checks=""
    
    # Track individual check results for summary
    local fusion_result="✅ PASSED"
    local df_result="✅ PASSED"
    local cas_result="✅ PASSED"
    local fs_result="✅ PASSED"
    local s3_result_text="✅ PASSED"
    
    logger info "Starting migration prerequisites validation..."
    logger info "================================================"
    
    # Run each validation
    if ! validate_fusion; then
        overall_status=1
        failed_checks="${failed_checks}Fusion "
        fusion_result="❌ FAILED"
    fi
    
    if ! validate_data_foundation; then
        overall_status=1
        failed_checks="${failed_checks}Data Foundation "
        df_result="❌ FAILED"
    fi
    
    if ! validate_cas; then
        overall_status=1
        failed_checks="${failed_checks}CAS "
        cas_result="❌ FAILED"
    fi
    
    if ! validate_cache_filesystem; then
        overall_status=1
        failed_checks="${failed_checks}Cache Filesystem "
        fs_result="❌ FAILED"
    fi
    
    local s3_exit_code=0
    validate_s3_datasources || s3_exit_code=$?
    
    # S3 datasources might return WARNING (2), only fail on FAILED (1)
    if [[ ${s3_exit_code} -eq 1 ]]; then
        overall_status=1
        failed_checks="${failed_checks}S3 Datasources "
        s3_result_text="❌ FAILED"
    elif [[ ${s3_exit_code} -eq 2 ]]; then
        s3_result_text="❓ WARNING"
    fi
    
    logger info "================================================"
    
    # Print summary table
    local overall_result
    if [[ ${overall_status} -eq 0 ]]; then
        overall_result="✅ PASSED"
    else
        overall_result="❌ FAILED"
    fi
    
    print_validation_summary "${fusion_result}" "${df_result}" "${cas_result}" "${fs_result}" "${s3_result_text}" "${overall_result}"
    
    # Display final validation status
    if [[ ${overall_status} -eq 0 ]]; then
        echo "VALIDATION_STATUS: PASSED"
        echo "VALIDATION_COMPLETED_AT: $(date +"%Y-%m-%d %H:%M:%S")"
        logger success "All migration prerequisites validation checks PASSED"
        return 0
    else
        echo "VALIDATION_STATUS: FAILED"
        echo "VALIDATION_FAILED_CHECKS: ${failed_checks% }"
        echo "VALIDATION_COMPLETED_AT: $(date +"%Y-%m-%d %H:%M:%S")"
        logger error "Migration prerequisites validation FAILED"
        logger error "Failed checks: ${failed_checks% }"
        return 1
    fi
}

#========================================
# Main Entry Point
#========================================

main() {
    logger info "Migration Prerequisites Validation Script"
    
    # Run all validations
    run_all_validations
    rc=$?
    exit ${rc}
}

# Execute main function
main "$@"
