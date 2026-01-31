#!/usr/bin/env bash
set -eu

#----------------------------------------
# Function: Check cluster connectivity
#----------------------------------------
check_ocp_connection() {
	if ! oc whoami &>/dev/null; then
		logger error "Connection failed: Unable to connect to OpenShift API. Please log in with 'oc login' and try again."
		return 1
	fi
}

#----------------------------------------
# Function: Get current OCP version
#----------------------------------------
get_ocp_version() {
	local version
	version=$(oc get clusterversion --no-headers | awk '{print $2}')
	if [[ -z "$version" ]]; then
		logger error "Operation failed: Unable to retrieve OpenShift cluster version."
		return 1
	fi
	echo "$version"
}

#----------------------------------------
# Function: Check if OCP version is supported (>= target)
#----------------------------------------
is_supported_ocp_version() {
	local current_version
	current_version=$(get_ocp_version)

	if [[ "$(printf '%s\n%s\n' "$current_version" "$OCP_TOLERATED_VERSION" | sort -V | head -n1)" == "$current_version" ]] &&
		[[ "$current_version" != "$OCP_TOLERATED_VERSION" ]]; then
		logger error "Version mismatch: OpenShift version $current_version is not supported. Minimum tolerated: $OCP_TOLERATED_VERSION."
		return 1
	fi

	if [[ "$(printf '%s\n%s\n' "$current_version" "$OCP_TARGET_VERSION" | sort -V | head -n1)" == "$current_version" ]] &&
		[[ "$current_version" != "$OCP_TARGET_VERSION" ]]; then
		logger warn "Running on a lower supported OpenShift version ($current_version < $OCP_TARGET_VERSION)."
		return 0
	fi

	return 0
}

#----------------------------------------
# Function: Check if user is a cluster admin
#----------------------------------------
check_cluster_admin() {
	if ! oc auth can-i '*' '*' --all-namespaces &>/dev/null; then
		logger error "Permission denied: User does not have cluster-admin privileges."
		return 1
	fi
}

#----------------------------------------
# Function: Get nodes
#----------------------------------------
get_nodes() {
	oc get nodes --no-headers -o custom-columns=NAME:.metadata.name
}

#----------------------------------------
# Function: Count nodes
#----------------------------------------
count_nodes() {
	local nodes=$(get_nodes)
	echo "$nodes" | wc -l | tr -d ' '
}

#----------------------------------------
# Function: Validate nodes
#----------------------------------------
validate_nodes() {
	local count
	count=$(count_nodes)

	if ((count < EXPECTED_NODE_COUNT)); then
		logger error "Validation failed: Found only ${count} nodes, expected ${EXPECTED_NODE_COUNT}. Please verify your cluster setup."
		return 1
	fi
}

#----------------------------------------
# Function: Check if a ConfigMap exists in a namespace
#----------------------------------------
is_cm_exist() {
	local cm_name="$1"
	local namespace="$2"

	if oc get configmap "$cm_name" -n "$namespace" &>/dev/null; then
		return 0
	else
		return 1
	fi
}

#----------------------------------------
# Function: Ensure namespace exists
#----------------------------------------
ensure_namespace() {
	local namespace="$1"
	if ! oc get ns "$namespace" &>/dev/null; then
		logger info "Namespace '$namespace' not found. Creating..."
		if oc create ns "$namespace" >/dev/null 2>&1; then
			logger success "Namespace '$namespace' created successfully."
		else
			logger error "Operation failed: Unable to create namespace '$namespace'."
			return 1
		fi
	else
		logger success "Namespace '$namespace' already exists."
	fi
}

#----------------------------------------
# Function: Ensure project exist
#----------------------------------------
ensure_project() {
	local project="$1"
	if oc get project "$project" &>/dev/null; then
		logger info "Project '$project' already exists."
	else
		if oc new-project "$project" &>/dev/null; then
			logger success "Project '$project' created successfully."
		else
			logger error "Failed to create project '$project'."
		fi
	fi
}

#----------------------------------------
# Function: Label nodes
#----------------------------------------
label_nodes() {
	local label="$1"
	local nodes="$2"

	logger info "Labeling nodes with '$label'..."

	for node in $nodes; do
		if oc label node "$node" "$label" --overwrite >/dev/null 2>&1; then
			logger success "Labeled node '$node' with '$label'."
		else
			logger warn "Failed to label node '$node'."
		fi
	done
}

#----------------------------------------
# Function: Get cluster base domain
#----------------------------------------
get_cluster_base_domain() {
	oc get dns cluster -o jsonpath='{.spec.baseDomain}{"\n"}' 2>/dev/null
}

#----------------------------------------
# Function: Get node name for a given pod
#----------------------------------------
get_node_for_pod() {
	local namespace="$1"
	local pod="$2"
	[[ -z "$pod" ]] && return 1
	oc get pod "$pod" -n "$namespace" -o jsonpath='{.spec.nodeName}' 2>/dev/null
}

#----------------------------------------
# Function: Get PV name from PVC
#----------------------------------------
get_pv_from_pvc() {
	local pvc="$1"
	oc get pvc "$pvc" -n $LOCAL_STORAGE_PROJECT -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo ""
}
