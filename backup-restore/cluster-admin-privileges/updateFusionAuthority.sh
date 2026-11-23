#!/bin/bash

##############################################################################
#Script Name	: updateFusionAuthority.sh
#Description	: Utility to reduce/restore Fusion authority in cluster
#Args       	:
#Author       	:
#Email         	:
##############################################################################

##############################################################################

# This utility will decrease or escalate permissions for fusion created roles
# in cluster based on arguments provided

# To reduce permissions, use
# ./updateFusionAuthority.sh reduce-authority

# To escalate permissions, use
# ./updateFusionAuthority.sh restore-authority
##############################################################################

CHECK_PASS='  ✅'
CHECK_FAIL='  ❌'
CHECK_UNKNOW='  ⏳'
PADDING_1='   '
PADDING_2='      '
ACTION=''
PREPRE_OPERATOR="isf-prereq-operator-controller-manager"
APP_OPERATOR=isf-application-operator-controller-manager
PLAT_OPERATOR=isf-platform-operator-controller-manager
BACKUP_AND_RESTORE_NAMESPACE=''

function print_header() {
    echo "======================================================================================"
    echo "Started authority change IBM Fusion cluster at $(date +'%F %z %r')"
    echo "======================================================================================"
}

function print_footer() {
    echo ""
    echo "========================================================================================"
    echo "Completed authority change IBM Fusion cluster at $(date +'%F %z %r')"
    echo "========================================================================================"
}

function print() {
        case "$1" in
                "info")
                        echo "INFO: $2";;
                "error")
                        echo "ERROR: $2";;
                "warn")
                        echo "WARN: $2";;
                "debug")
                        echo "DEBUG: $2";;
		"*")
			echo "$2";;
	esac
}


function verify_api_access() {
	print info "Verify Red Hat OpenShift API access."
	oc get clusterversion >/dev/null
	if [ $? -ne 0 ]; then
        print error "${CHECK_FAIL} Red Hat OpenShift API is inaccessible. Rest of the process can not be executed. Please login to OCP api before executing script"
		exit 1
    else
        print info "${CHECK_PASS} Red Hat OpenShift API is accessible."
	fi
}

function verify_yq_version() {
	print info "Verify the version of yq, YAML processor command-line."
	yq --version | grep 'version v4.' &> /dev/null
  if [ "$?" -ne 0 ]; then
    print error "${CHECK_FAIL} The required version of the yq was not found, v4.x+ required. See https://github.com/mikefarah/yq/ for details. Please add the correct version to the path before executing script."
    exit 1
  else
    print info "${CHECK_PASS} The required version of the yq was found."
  fi
}

function verify_fusion_version() {
	print info "Verify IBM Storage Fusion version is >= 2.14.0."
	local current_version
	current_version=$(oc get spectrumfusion -A -o custom-columns=NS:status.isfVersion --no-headers 2>/dev/null | tr -d '[:space:]')
	if [ -z "${current_version}" ]; then
		print error "${CHECK_FAIL} Unable to retrieve IBM Storage Fusion version. Ensure a SpectrumFusion instance exists and the API is accessible."
		exit 1
	fi

	local required="2.14.0"
	# Compare versions by splitting on '.' and comparing each segment numerically
	local IFS='.'
	read -ra cur  <<< "${current_version}"
	read -ra req  <<< "${required}"

	local is_sufficient=true
	for i in 0 1 2; do
		local c=${cur[$i]:-0}
		local r=${req[$i]:-0}
		if [ "$c" -gt "$r" ]; then
			break
		elif [ "$c" -lt "$r" ]; then
			is_sufficient=false
			break
		fi
	done

	if [ "${is_sufficient}" = false ]; then
		print error "${CHECK_FAIL} IBM Storage Fusion version ${current_version} is below the required minimum 2.14.0. This script cannot be executed on this cluster."
		exit 1
	fi

	print info "${CHECK_PASS} IBM Storage Fusion version ${current_version} meets the minimum requirement (>= 2.14.0)."
}

function get_cluster_role() {
	print info "Retrieve cluster roles"  >&2

	TEMP_ROLE_FILE=$(pwd)/tmp_role_file.log
	rm -f ${TEMP_ROLE_FILE} > /dev/null >&2
	declare -a clusterRole
	while read -r proc; do echo $proc >> ${TEMP_ROLE_FILE}; done <<< "$(oc get clusterrolebinding -A |grep -v NAME|grep isf-operator|awk '{print $1}')"
		while IFS= read -r line; do
			binding=$(oc get clusterrolebinding "$line" -o json|jq '.subjects'| jq -c '.[]|select(.name=="'$1'")')
			if [[ "$binding" == *$1* ]]; then
				role=$(oc get clusterrolebinding $line -o json|jq '.roleRef.name')
				clusterRole=$role
				print info "added $1 clusterrole=$role" >&2
			fi
		done < ${TEMP_ROLE_FILE}

	print info "${CHECK_PASS} Retrieved cluster role of $1" >&2
	echo $clusterRole
}

function change_prereq_operator_authority() {
	print info "Changing Prereq Operator authority"

	local all_resource_rbac_verbs=$2
	local rbac_verbs=$3

	if ! oc get deployment ${PREPRE_OPERATOR} > /dev/null 2>&1; then
		print error "${CHECK_FAIL} Invalid deployment: deployment ${PREPRE_OPERATOR} not found" >&2
		exit 2
	fi

	## Change Prereq Operator Authority in IBM Storage Fusion Operator CSV
	ISF_CSV_NAME=$(oc get --selector="operators.coreos.com/isf-operator.$1" csv --no-headers -o custom-columns=":metadata.name") > /dev/null 2>&1
	if [ -z ${ISF_CSV_NAME+x} ]; then
		print error "${CHECK_FAIL} Failed to find isf-operator CSV. Skipping isf-operator CSV update" >&2
	else
		print info "Changing Prereq Operator authority in IBM Storage Fusion Operator CSV"
		
    oc get csv ${ISF_CSV_NAME} -o yaml |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${PREPRE_OPERATOR}'").rules) |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "*").verbs = '"${all_resource_rbac_verbs}"')' |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${PREPRE_OPERATOR}'").rules) |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterroles").verbs = '"${rbac_verbs}"')' |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${PREPRE_OPERATOR}'").rules) |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterrolebindings").verbs = '"${rbac_verbs}"')' > $(pwd)/isf_csv_change_prereq_patch_$$.yaml

		if oc patch csv ${ISF_CSV_NAME} --type merge --patch-file $(pwd)/isf_csv_change_prereq_patch_$$.yaml; then
			print info "${CHECK_PASS} Changed Prereq Operator authority in IBM Storage Fusion Operator CSV" >&2
		else
			print error "${CHECK_FAIL} Failed to change Prereq operator authority in IBM Storage Fusion Operator CSV" >&2
    		exit 1
		fi
	fi

	## Reduce Prereq Operator Authority in ClusterRole
	clusterRole=$(get_cluster_role ${PREPRE_OPERATOR})
	print info "clusterrole $clusterRole" 2>&1

	print info "Changing Prereq Operator authority in ClusterRole"
	cr=$(echo "$clusterRole" | tr -d '"' 2>&1)
	oc get ClusterRole $cr -o yaml |\
	yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "*").verbs = '"${all_resource_rbac_verbs}"')' |\
	yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterroles").verbs = '"${rbac_verbs}"')' |\
	yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterrolebindings").verbs = '"${rbac_verbs}"')' > $(pwd)/isf_cr_change_prereq_patch_$$.yaml

	if oc apply -f $(pwd)/isf_cr_change_prereq_patch_$$.yaml; then
		print info "${CHECK_PASS} Changed Prereq Operator authority in ClusterRole"
	else
		print error "${CHECK_FAIL} Failed to change Prereq operator authority in ClusterRole" >&2
    	exit 1
	fi

	print info "${CHECK_PASS} Changed Prereq Operator authority"
}

function change_application_operator_authority() {
	print info "Changing Application Operator authority"

	local all_resource_rbac_verbs=$2
	local rbac_verbs=$3

  # check for deployment
	if ! oc get deployment ${APP_OPERATOR} > /dev/null 2>&1; then
		print error "${CHECK_FAIL} Invalid deployment: deployment ${APP_OPERATOR} not found" >&2
		exit 2
	fi

  # Update Application Operator Authority in CSV
	ISF_CSV_NAME=$(oc get --selector="operators.coreos.com/isf-operator.$1" csv --no-headers -o custom-columns=":metadata.name") > /dev/null 2>&1
	if [ -z ${ISF_CSV_NAME+x} ]; then
		print error "${CHECK_FAIL} Failed to find isf-operator CSV. Skipping isf-operator CSV update" >&2
	else
		print info "Changing Application Operator authority in IBM Storage Fusion Operator CSV"

		oc get csv ${ISF_CSV_NAME} -o yaml |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${APP_OPERATOR}'").rules) |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "*").verbs = '"${all_resource_rbac_verbs}"')' |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${APP_OPERATOR}'").rules) |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterroles").verbs = '"${rbac_verbs}"')' |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${APP_OPERATOR}'").rules) |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterrolebindings").verbs = '"${rbac_verbs}"')' > $(pwd)/isf_csv_change_application_patch_$$.yaml 

    # Apply CSV patch only if APP_OPERATOR clusterPermissions rules are present
    local PATCH_LEN=$(yq eval '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName=="'${APP_OPERATOR}'")).rules | length' $(pwd)/isf_csv_change_application_patch_$$.yaml)
		if [ "$PATCH_LEN" -gt 0 ]; then
      if oc patch csv ${ISF_CSV_NAME} --type merge --patch-file $(pwd)/isf_csv_change_application_patch_$$.yaml; then
        print info "${CHECK_PASS} Changed Application Operator authority in IBM Storage Fusion Operator CSV" >&2
      else
        print error "${CHECK_FAIL} Failed to change Application operator authority in IBM Storage Fusion Operator CSV" >&2
        exit 1
      fi
    else
      print info "ClusterPermissions not found, skipping Application Operators CSV patch" >&2
    fi  
	fi

	# Finding cluster role for Application Operator
	clusterRole=$(get_cluster_role ${APP_OPERATOR})
	print info "clusterrole $clusterRole" 2>&1

  # Updating write access verbs from cluster role
	print info "Changing Application Operator authority in ClusterRole"
	cr=$(echo "$clusterRole" | tr -d '"' 2>&1)
	oc get ClusterRole $cr -o yaml |\
	yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "*").verbs = '"${all_resource_rbac_verbs}"')' |\
	yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterroles").verbs = '"${rbac_verbs}"')' |\
	yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterrolebindings").verbs = '"${rbac_verbs}"')' > $(pwd)/isf_cr_change_app_patch_$$.yaml

  # Applying the changes
	if oc apply -f $(pwd)/isf_cr_change_app_patch_$$.yaml; then
		print info "${CHECK_PASS} Changed Application Operator authority in ClusterRole"
	else
		print error "${CHECK_FAIL} Failed to change Application operator authority in ClusterRole" >&2
    	exit 1
	fi

	print info "${CHECK_PASS} Changed Application Operator authority"
}

function change_platform_operator_authority() {
	print info "Changing Platform Operator authority"

	local all_resource_rbac_verbs=$2
	local rbac_verbs=$3

  # check for deployment
	if ! oc get deployment ${PLAT_OPERATOR} > /dev/null 2>&1; then
		print error "${CHECK_FAIL} Invalid deployment: deployment ${PLAT_OPERATOR} not found" >&2
		exit 2
	fi

  # Update Platform Operator Authority in CSV
	ISF_CSV_NAME=$(oc get --selector="operators.coreos.com/isf-operator.$1" csv --no-headers -o custom-columns=":metadata.name") > /dev/null 2>&1
	if [ -z ${ISF_CSV_NAME+x} ]; then
		print error "${CHECK_FAIL} Failed to find isf-operator CSV. Skipping isf-operator CSV update" >&2
	else
		print info "Changing Platform Operator authority in IBM Storage Fusion Operator CSV"

		oc get csv ${ISF_CSV_NAME} -o yaml |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${PLAT_OPERATOR}'").rules) |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "*").verbs = '"${all_resource_rbac_verbs}"')' |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${PLAT_OPERATOR}'").rules) |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterroles").verbs = '"${rbac_verbs}"')' |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${PLAT_OPERATOR}'").rules) |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterrolebindings").verbs = '"${rbac_verbs}"')' > $(pwd)/isf_csv_change_platform_patch_$$.yaml 

    # Apply CSV patch only if PLAT_OPERATOR clusterPermissions rules are present
    local PATCH_LEN=$(yq eval '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName=="'${PLAT_OPERATOR}'")).rules | length' $(pwd)/isf_csv_change_platform_patch_$$.yaml)
		if [ "$PATCH_LEN" -gt 0 ]; then
      if oc patch csv ${ISF_CSV_NAME} --type merge --patch-file $(pwd)/isf_csv_change_platform_patch_$$.yaml; then
        print info "${CHECK_PASS} Changed Platform Operator authority in IBM Storage Fusion Operator CSV" >&2
      else
        print error "${CHECK_FAIL} Failed to change Platform operator authority in IBM Storage Fusion Operator CSV" >&2
        exit 1
      fi
    else
      print info "ClusterPermissions not found, skipping Platform Operators CSV patch" >&2
    fi  
	fi

	# Finding cluster role for Platform Operator
	clusterRole=$(get_cluster_role ${PLAT_OPERATOR})
	print info "clusterrole $clusterRole" 2>&1

  # Updating write access verbs from cluster role
	print info "Changing Platform Operator authority in ClusterRole"
	cr=$(echo "$clusterRole" | tr -d '"' 2>&1)
	oc get ClusterRole $cr -o yaml |\
	yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "*").verbs = '"${all_resource_rbac_verbs}"')' |\
	yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterroles").verbs = '"${rbac_verbs}"')' |\
	yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io" and .resources[0] == "clusterrolebindings").verbs = '"${rbac_verbs}"')' > $(pwd)/isf_cr_change_platform_patch_$$.yaml

  # Applying the changes
	if oc apply -f $(pwd)/isf_cr_change_platform_patch_$$.yaml; then
		print info "${CHECK_PASS} Changed Platform Operator authority in ClusterRole"
	else
		print error "${CHECK_FAIL} Failed to change Platform operator authority in ClusterRole" >&2
    	exit 1
	fi

	print info "${CHECK_PASS} Changed Platform Operator authority"
}

function reduce_prereq_operator_authority() {
	print info "Reducing Prereq Operator authority"
	local all_resource_rbac_verbs='["get","list", "watch"]'
	local rbac_verbs='["get","list", "watch"]'
	change_prereq_operator_authority $1 "${all_resource_rbac_verbs}" "${rbac_verbs}"
	print info "${CHECK_PASS} Reduced Prereq Operator authority"
}

function restore_prereq_operator_authority() {
	print info "Restoring Prereq Operator authority"
	local all_resource_rbac_verbs='["*"]'
	local rbac_verbs='["create", "delete", "get", "list", "patch", "update", "watch"]'
	change_prereq_operator_authority $1 "${all_resource_rbac_verbs}" "${rbac_verbs}"
	print info "${CHECK_PASS} Restored Prereq Operator authority"
}

function reduce_application_operator_authority() {
	print info "Reducing Application Operator authority"
	local all_resource_rbac_verbs='["get","list", "watch"]'
	local rbac_verbs='["get","list", "watch"]'
	change_application_operator_authority $1 "${all_resource_rbac_verbs}" "${rbac_verbs}"
	print info "${CHECK_PASS} Reduced Application Operator authority"
}

function restore_application_operator_authority() {
	print info "Restoring Application Operator authority"
	local all_resource_rbac_verbs='["*"]'
	local rbac_verbs='["create", "get", "list", "update", "watch"]'
	change_application_operator_authority $1 "${all_resource_rbac_verbs}" "${rbac_verbs}"
	print info "${CHECK_PASS} Restored Application Operator authority"
}

function reduce_serviceability_authority() {
  print info "Reducing Serviceability Operators authority"
  
  local SERVICE_OPERATOR=isf-serviceability-operator-controller-manager
  local SERVICE_OPERATOR_ADMIN=isf-serviceability-operator-controller-manager-admin

 # check if the serviceability deployments are present
  if ! oc get deployment $SERVICE_OPERATOR > /dev/null 2>&1; then
    print error "${CHECK_FAIL} Serviceability deployment ($SERVICE_OPERATOR) not found in '$1'"
    exit 1
  fi

  ISF_CSV_NAME=$(oc get --selector="operators.coreos.com/isf-operator.$1" csv --no-headers -o custom-columns=":metadata.name") > /dev/null 2>&1
	if [ -z ${ISF_CSV_NAME+x} ]; then
		print error "${CHECK_FAIL} Failed to find isf-operator CSV. Skipping isf-operator CSV update" >&2
	else
		print info "Changing Serviceabilitiy authority in IBM Storage Fusion Operator CSV"

    # 1. Reduce Serviceability admin in CSV
		oc get csv ${ISF_CSV_NAME} -o yaml |\
    yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName=="'${SERVICE_OPERATOR_ADMIN}'") ).rules = ((.spec.install.spec.clusterPermissions[] | select(.serviceAccountName=="'${SERVICE_OPERATOR}'") ).rules)' > $(pwd)/isf_csv_change_serviceability_admin_patch_$$.yaml

    # Apply CSV patch only if SERVICE_OPERATOR_ADMIN clusterPermissions rules are present
    local PATCH_LEN=$(yq eval '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName=="'${SERVICE_OPERATOR_ADMIN}'")).rules | length' $(pwd)/isf_csv_change_serviceability_admin_patch_$$.yaml)
    if [ "$PATCH_LEN" -gt 0 ]; then
      if oc patch csv ${ISF_CSV_NAME} --type merge --patch-file $(pwd)/isf_csv_change_serviceability_admin_patch_$$.yaml; then
        print info "${CHECK_PASS} Changed Serviceability Operator authority in IBM Storage Fusion Operator CSV" >&2
      else
        print error "${CHECK_FAIL} Failed to change Serviceability operator authority in IBM Storage Fusion Operator CSV" >&2
        exit 1
      fi
    else
      print info "ClusterPermissions not found, skipping Serviceability Operators CSV patch" >&2
    fi  

    # 2. Reduce Servicability admin ClusterRole
    patch_file=$(pwd)/isf_cr_change_serviceability_patch_$$.yaml
    clusterRole=$(get_cluster_role ${SERVICE_OPERATOR})
    cr=$(echo "$clusterRole" | tr -d '"' 2>&1)
    oc get ClusterRole $cr  -o yaml | yq '{"rules": .rules}' > $patch_file

    clusterRole=$(get_cluster_role ${SERVICE_OPERATOR_ADMIN})
    cr=$(echo "$clusterRole" | tr -d '"' 2>&1)
    oc get clusterrole $cr -o yaml | yq '.rules = load("'"$patch_file"'").rules' > $(pwd)/isf_cr_change_serviceability_admin_patch_$$.yaml
    if oc apply -f $(pwd)/isf_cr_change_serviceability_admin_patch_$$.yaml; then
        print info "${CHECK_PASS} Reduced verbs for ClusterRole - $cr"
    else
        print error "${CHECK_FAIL} Failed to reduce verbs ClusterRole - $cr" >&2
        exit 1
    fi
	fi

  # SCC change
  oc adm policy add-scc-to-user anyuid system:serviceaccount:$1:isf-serviceability-operator-controller-manager &> /dev/null

  # End
  print info "${CHECK_PASS} Reduced Serviceability Operators authority"
}

function restore_serviceability_authority() {
	print info "Restoring Serviceability Operator authority"

  # remove SCC policy
  oc adm policy remove-scc-from-user anyuid system:serviceaccount:$1:isf-serviceability-operator-controller-manager &> /dev/null

  local SERVICE_OPERATOR=isf-serviceability-operator-controller-manager
  local SERVICE_OPERATOR_ADMIN=isf-serviceability-operator-controller-manager-admin

 # check if the serviceability deployments are present
  if ! oc get deployment $SERVICE_OPERATOR > /dev/null 2>&1; then
    print error "${CHECK_FAIL} Serviceability deployment ($SERVICE_OPERATOR) not found in '$1'"
    exit 1
  fi

  ISF_CSV_NAME=$(oc get --selector="operators.coreos.com/isf-operator.$1" csv --no-headers -o custom-columns=":metadata.name") > /dev/null 2>&1
  if [ -z ${ISF_CSV_NAME+x} ]; then
    print error "${CHECK_FAIL} Failed to find isf-operator CSV. Skipping isf-operator CSV update" >&2
  else
    print info "Changing Serviceabilitiy authority in IBM Storage Fusion Operator CSV"

    # 1. Restore Serviceability admin in CSV
    oc get csv ${ISF_CSV_NAME} -o yaml \
      | yq '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName == "'${SERVICE_OPERATOR_ADMIN}'").rules) = [
          {"apiGroups": ["*"], "resources": ["*"], "verbs": ["*"]},
          {"nonResourceURLs": ["*"], "verbs": ["*"]}
        ]' > $(pwd)/isf_csv_change_serviceability_admin_patch_$$.yaml

    # Apply CSV patch only if SERVICE_OPERATOR_ADMIN clusterPermissions rules are present
    local PATCH_LEN=$(yq eval '(.spec.install.spec.clusterPermissions[] | select(.serviceAccountName=="'${SERVICE_OPERATOR_ADMIN}'")).rules | length' $(pwd)/isf_csv_change_serviceability_admin_patch_$$.yaml)
		if [ "$PATCH_LEN" -gt 0 ]; then
      if oc patch csv ${ISF_CSV_NAME} --type merge --patch-file $(pwd)/isf_csv_change_serviceability_admin_patch_$$.yaml; then
        print info "${CHECK_PASS} Changed Serviciability Operator authority in IBM Storage Fusion Operator CSV" >&2
      else
        print error "${CHECK_FAIL} Failed to change Serviciability operator authority in IBM Storage Fusion Operator CSV" >&2
        exit 1
      fi
    else
      print info "ClusterPermissions not found, skipping Serviciability Operator CSV patch" >&2
    fi  

    # 2. Restore Servicability admin ClusterRole
    clusterRole=$(get_cluster_role ${SERVICE_OPERATOR_ADMIN})
    cr=$(echo "$clusterRole" | tr -d '"' 2>&1)
    oc get clusterrole $cr -o yaml \
      | yq '(.rules) = [
          {"apiGroups": ["*"], "resources": ["*"], "verbs": ["*"]},
          {"nonResourceURLs": ["*"], "verbs": ["*"]}
        ]' > $(pwd)/isf_cr_change_serviceability_admin_patch_$$.yaml

    if oc apply -f $(pwd)/isf_cr_change_serviceability_admin_patch_$$.yaml; then
        print info "${CHECK_PASS} Restored verbs for ClusterRole - $cr"
    else
        print error "${CHECK_FAIL} Failed to restore verbs ClusterRole - $cr" >&2
        exit 1
    fi
  fi

	print info "${CHECK_PASS} Restored Serviceability Operator authority"
}

function reduce_platform_operator_authority() {
	print info "Reducing Platform Operator authority"
	local all_resource_rbac_verbs='["get","list", "watch"]'
	local rbac_verbs='["get","list", "watch"]'
	change_platform_operator_authority $1 "${all_resource_rbac_verbs}" "${rbac_verbs}"
	print info "${CHECK_PASS} Reduced Platform Operator authority"
}

function restore_platform_operator_authority() {
	print info "Restoring Platform Operator authority"
	local all_resource_rbac_verbs='["*"]'
	local rbac_verbs='["create", "get", "list", "update", "watch"]'
	change_platform_operator_authority $1 "${all_resource_rbac_verbs}" "${rbac_verbs}"
	print info "${CHECK_PASS} Restored Platform Operator authority"
}


function change_data_mover_operator_authority() {
  local rbac_verbs=$1
  local scc_verbs=$2

  ## Confirm Backup & Restore namespace was found
  if [ -z "${BACKUP_AND_RESTORE_NAMESPACE}" ]; then
   print error "${CHECK_FAIL} Failed to find the Backup & Restore namespace" >&2
   exit 10
  fi

  ## Confirm Backup & Restore namespace is valid
  if ! oc -n ${BACKUP_AND_RESTORE_NAMESPACE} get deployment guardian-dm-controller-manager > /dev/null 2>&1; then
    print error "${CHECK_FAIL} Invalid namespace: Backup & Restore not found" >&2
    exit 11
  fi

  local csv_name
  csv_name=$(oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get --selector="operators.coreos.com/guardian-dm-operator.${BACKUP_AND_RESTORE_NAMESPACE}" csv --no-headers -o custom-columns=":metadata.name") > /dev/null 2>&1
  if [ -z "${csv_name}" ]; then
    print error "${CHECK_FAIL} Failed to find Data Mover operator CSV: --selector=operators.coreos.com/guardian-dm-operator.${BACKUP_AND_RESTORE_NAMESPACE}" >&2
    exit 12
  else
    oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get csv ${csv_name} -o yaml |\
    yq '(.spec.install.spec.clusterPermissions) as $i ireduce({}; setpath($i | path; $i))' |\
    yq '.spec.install.spec.clusterPermissions[0].rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io").verbs = '"${rbac_verbs}"')' |\
    yq '.spec.install.spec.clusterPermissions[0].rules |= map(select(.resources[0] == "securitycontextconstraints").verbs = '"${scc_verbs}"')' > /tmp/dm_csv_patch_$$.yaml
    if oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" patch csv "${csv_name}" --type merge --patch-file /tmp/dm_csv_patch_$$.yaml; then
      print info "${CHECK_PASS} Changed Data Mover operator authority in CSV"
      #rm /tmp/dm_csv_patch_$$.yaml
    else
      print error "${CHECK_FAIL} Failed to change Data Mover operator authority in CSV" >&2
      #rm /tmp/dm_csv_patch_$$.yaml
      exit 13
    fi
  fi

  local cluster_role_name
  cluster_role_name=$(oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get --selector="operators.coreos.com/guardian-dm-operator.${BACKUP_AND_RESTORE_NAMESPACE}" ClusterRole --no-headers -o custom-columns=":metadata.name")
  if [ -z "${cluster_role_name}" ]; then
    print error "${CHECK_FAIL} Failed to find Data Mover cluster role ${cluster_role_name}: --selector=operators.coreos.com/guardian-dm-operator.${BACKUP_AND_RESTORE_NAMESPACE}" >&2
    exit 14
  else
    if oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get ClusterRole "${cluster_role_name}" -o yaml |\
      yq '.rules |= map(select(.apiGroups[0] == "rbac.authorization.k8s.io").verbs = '"${rbac_verbs}"')' |\
      yq '.rules |= map(select(.resources[0] == "securitycontextconstraints").verbs = '"${scc_verbs}"')' |\
      oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" apply -f -; then
      print info "${CHECK_PASS} Changed Data Mover operator authority in cluster role"
    else
      print error "${CHECK_FAIL} Failed to change Data Mover operator authority in cluster role" >&2
      exit 15
    fi
  fi
}

function change_bnr_install_operator_authority() {
  local clusterroles_verbs=$1
  local clusterrolebindings_verbs=$2
  local scc_verbs=$3
  local installer_type=$4

  ## Confirm Backup & Restore namespace was found
  if [ -z "${BACKUP_AND_RESTORE_NAMESPACE}" ]; then
   print error "${CHECK_FAIL} Failed to find the Backup & Restore namespace" >&2
   exit 10
  fi

  ## Confirm Backup & Restore namespace is valid
  if ! oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get deployment guardian-dm-controller-manager > /dev/null 2>&1; then
    print error "${CHECK_FAIL} Invalid namespace: Backup & Restore not found" >&2
    exit 11
  fi

  local csv_name
  csv_name=$(oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get --selector="operators.coreos.com/ibm-dataprotection${installer_type}.${BACKUP_AND_RESTORE_NAMESPACE}" csv --no-headers -o custom-columns=":metadata.name") > /dev/null 2>&1
  if [ -z "${csv_name}" ]; then
    print error "${CHECK_FAIL} Failed to find ${installer_type} install operator CSV." >&2
    exit 16
  else
    oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get csv ${csv_name} -o yaml |\
    yq '(.spec.install.spec.clusterPermissions) as $i ireduce({}; setpath($i | path; $i))' |\
    yq '.spec.install.spec.clusterPermissions[0].rules |= map(select(.resources[0] == "clusterroles").verbs = '"${clusterroles_verbs}"')' |\
    yq '.spec.install.spec.clusterPermissions[0].rules |= map(select(.resources[0] == "clusterrolebindings").verbs = '"${clusterrolebindings_verbs}"')' |\
    yq '.spec.install.spec.clusterPermissions[0].rules |= map(select(.resources[0] == "securitycontextconstraints").verbs = '"${scc_verbs}"')' > /tmp/install_csv_cluster_patch_$$.yaml
    if oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" patch csv "${csv_name}" --type merge --patch-file /tmp/install_csv_cluster_patch_$$.yaml; then
      print info "${CHECK_PASS} Changed cluster permissions for the ${installer_type} install authority in CSV"
    else
      print error "${CHECK_FAIL} Failed to change cluster permissions for the ${installer_type} install operator authority in CSV" >&2
      exit 17
    fi
    oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get csv ${csv_name} -o yaml |\
    yq '(.spec.install.spec.permissions) as $i ireduce({}; setpath($i | path; $i))' |\
    yq '.spec.install.spec.permissions[0].rules |= map(select(.resources[0] == "clusterroles").verbs = '"${clusterroles_verbs}"')' |\
    yq '.spec.install.spec.permissions[0].rules |= map(select(.resources[0] == "clusterrolebindings").verbs = '"${clusterrolebindings_verbs}"')' |\
    yq '.spec.install.spec.permissions[0].rules |= map(select(.resources[0] == "securitycontextconstraints").verbs = '"${scc_verbs}"')' > /tmp/install_csv_ns_patch_$$.yaml
    if oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" patch csv "${csv_name}" --type merge --patch-file /tmp/install_csv_ns_patch_$$.yaml; then
      print info "${CHECK_PASS} Changed permissions for the ${installer_type} install authority in CSV"
    else
      print error "${CHECK_FAIL} Failed to change permissions for the ${installer_type} install operator authority in CSV" >&2
      exit 17
    fi
  fi

  local cluster_role_name
  cluster_role_name=$(oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get --selector="operators.coreos.com/ibm-dataprotection${installer_type}.${BACKUP_AND_RESTORE_NAMESPACE}" ClusterRole --no-headers -o custom-columns=":metadata.name")
  if [ -z "${cluster_role_name}" ]; then
    print error "${CHECK_FAIL} Failed to find Data Mover cluster role." >&2
    exit 18
  else
    if oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get ClusterRole "${cluster_role_name}" -o yaml |\
      yq '.rules |= map(select(.resources[0] == "clusterroles").verbs = '"${clusterroles_verbs}"')' |\
      yq '.rules |= map(select(.resources[0] == "clusterrolebindings").verbs = '"${clusterrolebindings_verbs}"')' |\
      yq '.rules |= map(select(.resources[0] == "securitycontextconstraints").verbs = '"${scc_verbs}"')' |\
      oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" apply -f -; then
      print info "${CHECK_PASS} Changed the ${installer_type} install operator authority in cluster role"
    else
      print error "${CHECK_FAIL} Failed to change the ${installer_type} install operator authority in cluster role" >&2
      exit 19
    fi
  fi

  local role_name
  role_name=$(oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get --selector="operators.coreos.com/ibm-dataprotection${installer_type}.${BACKUP_AND_RESTORE_NAMESPACE}" Role --no-headers -o custom-columns=":metadata.name")
  if [ -z "${role_name}" ]; then
    print error "${CHECK_FAIL} Failed to find Data Mover cluster role." >&2
    exit 18
  else
    if oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" get Role "${role_name}" -o yaml |\
      yq '.rules |= map(select(.resources[0] == "clusterroles").verbs = '"${clusterroles_verbs}"')' |\
      yq '.rules |= map(select(.resources[0] == "clusterrolebindings").verbs = '"${clusterrolebindings_verbs}"')' |\
      yq '.rules |= map(select(.resources[0] == "securitycontextconstraints").verbs = '"${scc_verbs}"')' |\
      oc -n "${BACKUP_AND_RESTORE_NAMESPACE}" apply -f -; then
      print info "${CHECK_PASS} Changed the ${installer_type} install operator authority in role"
    else
      print error "${CHECK_FAIL} Failed to change the ${installer_type} install operator authority in role" >&2
      exit 19
    fi
  fi
}

function reduce_data_mover_operator_authority() {
  print info "Reducing Data Mover Operator authority"
  local rbac_verbs='["get","list", "watch"]'
  local scc_verbs='["get","list", "watch"]'
  change_data_mover_operator_authority "${rbac_verbs}" "${scc_verbs}"
}

function restore_data_mover_operator_authority() {
  print info "Restoring Data Mover Operator authority"
  local rbac_verbs='["create", "delete", "deletecollection", "get", "list", "patch", "update", "watch"]'
  local scc_verbs='["create", "delete", "deletecollection", "get", "list", "patch", "update", "watch", "use"]'
  change_data_mover_operator_authority "${rbac_verbs}" "${scc_verbs}"
}

function reduce_server_install_operator_authority() {
  print info "Reducing Server Install Operator authority"
  local clusterroles_verbs='["get","list", "watch"]'
  local clusterrolebindings_verbs='["get","list", "watch"]'
  local scc_verbs='["get","list", "watch"]'
  local installer_type='server'
  change_bnr_install_operator_authority "${clusterroles_verbs}" "${clusterrolebindings_verbs}" "${scc_verbs}" "${installer_type}"
}

function restore_server_install_operator_authority() {
  print info "Restoring Server Install Operator authority"
  local clusterroles_verbs='["create", "delete", "get", "list", "patch", "update", "watch"]'
  local clusterrolebindings_verbs='["create", "delete", "get", "list", "patch", "update", "watch"]'
  local scc_verbs='["create", "delete", "get", "list", "update", "watch"]'
  local installer_type='server'
  change_bnr_install_operator_authority "${clusterroles_verbs}" "${clusterrolebindings_verbs}" "${scc_verbs}" "${installer_type}"
}

function reduce_agent_install_operator_authority() {
  print info "Reducing Agent Install Operator authority"
  local clusterroles_verbs='["get","list", "watch"]'
  local clusterrolebindings_verbs='["get","list", "watch"]'
  local scc_verbs='["get","list", "watch"]'
  local installer_type='agent'
  change_bnr_install_operator_authority "${clusterroles_verbs}" "${clusterrolebindings_verbs}" "${scc_verbs}" "${installer_type}"
}

function restore_agent_install_operator_authority() {
  print info "Restoring Agent Install Operator authority"
  local clusterroles_verbs='["create", "delete", "get", "list", "patch", "update", "watch"]'
  local clusterrolebindings_verbs='["create", "delete", "get", "list", "patch", "update", "watch"]'
  local scc_verbs='["create", "delete", "get", "list", "patch", "update", "watch", "use"]'
  local installer_type='agent'
  change_bnr_install_operator_authority "${clusterroles_verbs}" "${clusterrolebindings_verbs}" "${scc_verbs}" "${installer_type}"
}

function set_backup_and_restore_namespace() {
  BACKUP_AND_RESTORE_NAMESPACE=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace)
  [ -z "$BACKUP_AND_RESTORE_NAMESPACE" ] && BACKUP_AND_RESTORE_NAMESPACE=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace)
  [ -z "$BACKUP_AND_RESTORE_NAMESPACE" ] && BACKUP_AND_RESTORE_NAMESPACE=ibm-backup-restore
}

##################### starts main here #####################

print_header

verify_api_access

verify_yq_version

verify_fusion_version

while test $# -gt 0
do
    case "$1" in
        reduce-authority) ACTION="reduce-authority"
            ;;
        restore-authority) ACTION="restore-authority"
            ;;
        *) echo "Unknown argument $1"
            ;;
    esac
    shift
done

if [ -z ${ACTION} ]; then
	print error "${CHECK_FAIL} Provide one of the option: reduce-authority, restore-authority, or authorize-restore"
	exit 1
fi

## Set Fusion namespace
NAMESPACE=$(oc get csv -A |grep -v NAME|grep isf-operator|awk '{print $1}')
if ! oc project "$NAMESPACE" > /dev/null 2>&1; then
	print error "${CHECK_FAIL} Invalid namespace: Namespace does not exist" >&2
	exit 5
fi

## Set Backup & Restore namespace
set_backup_and_restore_namespace

if [ "$ACTION" == "reduce-authority" ]; then
	reduce_prereq_operator_authority "${NAMESPACE}"
	reduce_serviceability_authority "${NAMESPACE}"
	reduce_application_operator_authority "${NAMESPACE}"
  reduce_platform_operator_authority "${NAMESPACE}"
	reduce_data_mover_operator_authority
	reduce_server_install_operator_authority
	reduce_agent_install_operator_authority
	# Add other reduction methods for other operators here
elif [ "$ACTION" == "restore-authority" ]; then
	restore_prereq_operator_authority "${NAMESPACE}"
	restore_serviceability_authority "${NAMESPACE}"
	restore_application_operator_authority "${NAMESPACE}"
  restore_platform_operator_authority "${NAMESPACE}"
	restore_data_mover_operator_authority
	restore_server_install_operator_authority
	restore_agent_install_operator_authority
fi

print_footer
