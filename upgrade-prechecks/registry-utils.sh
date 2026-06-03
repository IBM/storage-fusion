#!/bin/bash

##############################################################################
# Registry Utility Functions for Pre-upgrade Health Check
#
# This file contains modular functions for testing registry connectivity
# and authentication across all cluster nodes.
#
# Functions:
# - is_offline_installation()
# - get_mirror_registries_from_idms()
# - get_mirror_registries_from_itms()
# - get_all_mirror_registries()
# - get_cluster_proxy_config()
# - extract_registry_from_image()
# - test_registry_connectivity()
# - test_registry_auth()
# - get_installed_operators()
# - catalog_source_exists()
# - get_catalog_source_image()
# - verify_operators_catalog_sources()
# - get_registries_from_operators()
# - check_dynamic_registries()
##############################################################################

# Detect if this is an offline/disconnected installation
# Returns 0 (true) if offline, 1 (false) if online
function is_offline_installation() {
	print info "Detecting installation type (online/offline)..."
	
	# Method 1: Check Fusion HCI platformconfig ConfigMap
	local base_rack_name=$(oc get configmap -n ibm-spectrum-fusion-ns -o json 2>/dev/null | \
		jq -r '.items[] | select(.metadata.name | startswith("platformconfig-")) | .metadata.name' | \
		head -1 | sed 's/platformconfig-//')
	
	if [[ -n "$base_rack_name" ]]; then
		local platform_config=$(oc get configmap "platformconfig-$base_rack_name" -n ibm-spectrum-fusion-ns -o json 2>/dev/null)
		if [[ -n "$platform_config" ]]; then
			local is_private=$(echo "$platform_config" | jq -r '.data.isPrivateRegistry // empty')
			if [[ "$is_private" == "true" ]]; then
				print info "Detected OFFLINE installation (isPrivateRegistry=true in platformconfig-$base_rack_name)"
				return 0
			fi
		fi
	fi
	
	# Method 2: Check Fusion HCI userconfig Secret
	if [[ -n "$base_rack_name" ]]; then
		local userconfig=$(oc get secret "userconfig-$base_rack_name" -n ibm-spectrum-fusion-ns -o json 2>/dev/null)
		if [[ -n "$userconfig" ]]; then
			local userconfig_data=$(echo "$userconfig" | jq -r '.data.userconfig // empty' | base64 -d 2>/dev/null)
			if [[ -n "$userconfig_data" ]]; then
				local is_private=$(echo "$userconfig_data" | jq -r '.isPrivateRegistry // empty')
				if [[ "$is_private" == "true" ]]; then
					print info "Detected OFFLINE installation (isPrivateRegistry=true in userconfig-$base_rack_name)"
					return 0
				fi
			fi
		fi
	fi
	
	# Method 3: Check for ImageDigestMirrorSet or ImageTagMirrorSet
	local idms_count=$(oc get imagedigestmirrorset -o json 2>/dev/null | jq '.items | length')
	local itms_count=$(oc get imagetagmirrorset -o json 2>/dev/null | jq '.items | length')
	
	if [[ "$idms_count" -gt 0 ]] || [[ "$itms_count" -gt 0 ]]; then
		print info "Detected OFFLINE installation (found $idms_count IDMS and $itms_count ITMS)"
		return 0
	fi
	
	print info "Detected ONLINE installation (no private registry indicators found)"
	return 1
}

# Get mirror registries from ImageDigestMirrorSet (cluster-level, runs once)
function get_mirror_registries_from_idms() {
	local idms_data=$(oc get imagedigestmirrorset -o json 2>/dev/null)
	if [[ -z "$idms_data" ]]; then
		return
	fi
	
	# Extract all mirror URLs from all IDMS
	local mirrors=$(echo "$idms_data" | jq -r '
		.items[].spec.imageDigestMirrors[]?.mirrors[]? // empty
	' | sort -u)
	
	# Extract registry from each mirror URL
	echo "$mirrors" | while read -r mirror; do
		if [[ -n "$mirror" ]]; then
			extract_registry_from_image "$mirror"
		fi
	done | sort -u
}

# Get mirror registries from ImageTagMirrorSet (cluster-level, runs once)
function get_mirror_registries_from_itms() {
	local itms_data=$(oc get imagetagmirrorset -o json 2>/dev/null)
	if [[ -z "$itms_data" ]]; then
		return
	fi
	
	# Extract all mirror URLs from all ITMS
	local mirrors=$(echo "$itms_data" | jq -r '
		.items[].spec.imageTagMirrors[]?.mirrors[]? // empty
	' | sort -u)
	
	# Extract registry from each mirror URL
	echo "$mirrors" | while read -r mirror; do
		if [[ -n "$mirror" ]]; then
			extract_registry_from_image "$mirror"
		fi
	done | sort -u
}

# Get all unique mirror registries from IDMS and ITMS (cluster-level, runs once)
# This consolidates all mirror registries before per-node validation
function get_all_mirror_registries() {
	# Send logging to stderr to avoid mixing with output
	print info "Extracting mirror registries from ImageDigestMirrorSet and ImageTagMirrorSet..." >&2
	
	local temp_file=$(mktemp)
	
	# Get IDMS mirrors
	print info "  Checking ImageDigestMirrorSet resources..." >&2
	get_mirror_registries_from_idms >> "$temp_file"
	
	# Get ITMS mirrors
	print info "  Checking ImageTagMirrorSet resources..." >&2
	get_mirror_registries_from_itms >> "$temp_file"
	
	# Return unique registries (only registries go to stdout)
	if [[ -f "$temp_file" ]]; then
		local unique_registries=$(sort -u "$temp_file")
		rm -f "$temp_file"
		
		if [[ -n "$unique_registries" ]]; then
			local count=$(echo "$unique_registries" | wc -l | tr -d ' ')
			print info "  Consolidated $count unique mirror registry(ies)" >&2
			# Output only the registries to stdout
			echo "$unique_registries"
		fi
	fi
}

# Get cluster-wide proxy configuration
function get_cluster_proxy_config() {
	local proxy_config=$(oc get proxy cluster -o json 2>/dev/null)
	if [[ $? -eq 0 ]]; then
		HTTP_PROXY=$(echo "$proxy_config" | jq -r '.spec.httpProxy // empty')
		HTTPS_PROXY=$(echo "$proxy_config" | jq -r '.spec.httpsProxy // empty')
		NO_PROXY=$(echo "$proxy_config" | jq -r '.spec.noProxy // empty')
		
		if [[ -n "$HTTPS_PROXY" ]]; then
			print info "Cluster-wide proxy detected: $HTTPS_PROXY"
			PROXY_VARS="HTTP_PROXY=$HTTP_PROXY HTTPS_PROXY=$HTTPS_PROXY NO_PROXY=$NO_PROXY"
			return 0
		fi
	fi
	PROXY_VARS=""
	return 1
}

# Extract registry URL from image reference (including port if present)
# Examples:
#   quay.io/openshift-release-dev/ocp-release:4.12 -> quay.io
#   registry.example.com:8443/namespace/image:tag -> registry.example.com:8443
#   registry.example.com:8443/namespace/image@sha256:abc -> registry.example.com:8443
function extract_registry_from_image() {
	local image="$1"
	
	# Extract registry (everything before first /)
	local registry=$(echo "$image" | cut -d'/' -f1)
	
	# Check if it contains a dot or port (to distinguish from namespace)
	if [[ "$registry" == *"."* ]] || [[ "$registry" == *":"* ]]; then
		echo "$registry"
	else
		# Default to docker.io if no registry specified
		echo "docker.io"
	fi
}

# Test registry connectivity with proxy support from all nodes
function test_registry_connectivity() {
	local registry="$1"
	local registry_url="https://$registry"
	
	# Build curl command with proxy if configured
	# -k: Skip SSL certificate verification (common for private registries with self-signed certs)
	# Properly quote the URL to prevent shell interpretation issues with ports
	local curl_cmd="curl -k -s -o /dev/null -w '%{http_code}' --connect-timeout 10 '$registry_url'"
	if [[ -n "$PROXY_VARS" ]]; then
		curl_cmd="$PROXY_VARS $curl_cmd"
	fi
	
	# Get all ready nodes (control and worker)
	print info "Getting list of cluster nodes..."
	local nodes=$(oc get nodes --no-headers | grep -v "NotReady" | awk '{print $1}')
	local node_count=$(echo "$nodes" | wc -l)
	print info "Testing connectivity from $node_count node(s)..."
	
	local total_nodes=0
	local failed_nodes=0
	local failed_node_list=""
	
	for node in $nodes; do
		total_nodes=$((total_nodes + 1))
		print info "  Testing from node $node ($total_nodes/$node_count)..."
		local http_code=$(oc debug nodes/$node -- chroot /host bash -c "$curl_cmd" 2>/dev/null | tail -1)
		
		# Accept 200, 301, 302, 401, 403, 404 as success (registry is accessible)
		# 404 is normal for registries that don't serve content at root path
		# 401/403 means registry is accessible but requires authentication
		# 301/302 means registry is accessible and redirecting
		if [[ "$http_code" =~ ^(200|301|302|401|403|404)$ ]]; then
			print info "  ${CHECK_PASS} Node $node can reach $registry (HTTP $http_code)"
		else
			failed_nodes=$((failed_nodes + 1))
			failed_node_list="$failed_node_list\n    - $node (HTTP $http_code)"
			print error "  ${CHECK_FAIL} Node $node cannot reach $registry (HTTP $http_code)"
		fi
	done
	
	# Summary for this registry
	if [[ $failed_nodes -eq 0 ]]; then
		print info "${CHECK_PASS} Registry $registry is accessible from all $total_nodes nodes."
		return 0
	else
		print error "${CHECK_FAIL} Registry $registry is NOT accessible from $failed_nodes out of $total_nodes nodes:$failed_node_list"
		return 1
	fi
}

# Test registry authentication by pulling catalog image
function test_registry_auth() {
	local image="$1"
	local registry=$(extract_registry_from_image "$image")
	
	getReadyControlNode
	
	# Build podman pull command with proxy if configured
	local pull_cmd="podman pull --authfile /var/lib/kubelet/config.json $image"
	if [[ -n "$PROXY_VARS" ]]; then
		pull_cmd="$PROXY_VARS $pull_cmd"
	fi
	
	oc debug nodes/$CONTROLNODE -- chroot /host bash -c "$pull_cmd" 2>&1 | grep -q "Writing manifest"
	if [[ $? -eq 0 ]]; then
		print info "${CHECK_PASS} Successfully pulled image from $registry."
		return 0
	else
		print error "${CHECK_FAIL} Failed to pull image from $registry. Check authentication."
		return 1
	fi
}

# Get all installed operators (from Subscriptions)
function get_installed_operators() {
	oc get subscriptions -A -o json 2>/dev/null | \
		jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)|\(.spec.source)|\(.spec.sourceNamespace)"'
}

# Check if CatalogSource exists
function catalog_source_exists() {
	local catalog_name="$1"
	local catalog_namespace="$2"
	oc get catalogsource "$catalog_name" -n "$catalog_namespace" &>/dev/null
	return $?
}

# Get CatalogSource image
function get_catalog_source_image() {
	local catalog_name="$1"
	local catalog_namespace="$2"
	oc get catalogsource "$catalog_name" -n "$catalog_namespace" -o json 2>/dev/null | \
		jq -r '.spec.image // empty'
}

# Verify operators have valid CatalogSources
function verify_operators_catalog_sources() {
	print info "Verifying operators have valid CatalogSources..."
	
	local operators_data=$(get_installed_operators)
	if [[ -z "$operators_data" ]]; then
		print info "${CHECK_PASS} No operators found in cluster."
		return 0
	fi
	
	local total_operators=0
	local missing_catalogs=0
	declare -a missing_catalog_list
	
	while IFS='|' read -r namespace operator_name catalog_name catalog_namespace; do
		if [[ -z "$operator_name" ]]; then
			continue
		fi
		
		total_operators=$((total_operators + 1))
		
		if ! catalog_source_exists "$catalog_name" "$catalog_namespace"; then
			missing_catalogs=$((missing_catalogs + 1))
			missing_catalog_list+=("${CHECK_FAIL} Operator '$operator_name' in namespace '$namespace' references missing CatalogSource '$catalog_name' in namespace '$catalog_namespace'")
		fi
	done <<< "$operators_data"
	
	if [[ $missing_catalogs -gt 0 ]]; then
		print error "${CHECK_FAIL} $missing_catalogs operators have missing CatalogSources:"
		for msg in "${missing_catalog_list[@]}"; do
			print error "$msg"
		done
		return 1
	else
		print info "${CHECK_PASS} All $total_operators operators have valid CatalogSources."
		return 0
	fi
}

# Get unique registries from operators' CatalogSources
function get_registries_from_operators() {
	local operators_data=$(get_installed_operators)
	if [[ -z "$operators_data" ]]; then
		return 1
	fi
	
	local operator_count=$(echo "$operators_data" | grep -v '^$' | wc -l)
	print info "Processing $operator_count operator subscription(s)..." >&2
	
	local temp_file=$(mktemp)
	local processed=0
	
	while IFS='|' read -r namespace operator_name catalog_name catalog_namespace; do
		if [[ -z "$operator_name" ]]; then
			continue
		fi
		
		processed=$((processed + 1))
		print info "  [$processed/$operator_count] Checking operator: $operator_name in $namespace..." >&2
		
		# Check if catalog exists
		if catalog_source_exists "$catalog_name" "$catalog_namespace"; then
			local image=$(get_catalog_source_image "$catalog_name" "$catalog_namespace")
			if [[ -n "$image" ]]; then
				# Store unique catalog:image pairs (check if already added)
				local key="$catalog_name|$catalog_namespace"
				if ! grep -q "^$key|" "$temp_file" 2>/dev/null; then
					echo "$key|$image" >> "$temp_file"
					print info "    Found CatalogSource: $catalog_name with image: $image" >&2
				fi
			fi
		fi
	done <<< "$operators_data"
	
	# Output unique catalog:image pairs
	if [[ -f "$temp_file" ]]; then
		while IFS='|' read -r catalog_name catalog_namespace image; do
			echo "$image|$catalog_namespace|$catalog_name"
		done < "$temp_file"
		rm -f "$temp_file"
	fi
}

# Dynamic registry connectivity check based on operators
# Phase 1: Cluster-level detection and consolidation (runs once)
# Phase 2: Per-node validation (runs for each node)
function check_dynamic_registries() {
	print info "=========================================="
	print info "PHASE 1: Cluster-Level Registry Discovery"
	print info "=========================================="
	
	# Detect proxy configuration (cluster-level, runs once)
	get_cluster_proxy_config
	
	# Detect if this is offline/online installation (cluster-level, runs once)
	local is_offline=false
	if is_offline_installation; then
		is_offline=true
	fi
	
	# Consolidate registries to test (cluster-level, runs once)
	local registries_to_test=""
	local registry_count=0
	
	if [[ "$is_offline" == "true" ]]; then
		print info ""
		print info "OFFLINE installation detected - extracting mirror registries from IDMS/ITMS..."
		print info ""
		
		# Get all mirror registries (cluster-level consolidation)
		registries_to_test=$(get_all_mirror_registries)
		
		if [[ -z "$registries_to_test" ]]; then
			print error "${CHECK_FAIL} No mirror registries found in IDMS/ITMS for offline installation."
			print info "This may indicate a configuration issue with ImageDigestMirrorSet or ImageTagMirrorSet."
			return 1
		fi
		
		registry_count=$(echo "$registries_to_test" | wc -l | tr -d ' ')
		print info ""
		print info "Consolidated $registry_count unique mirror registry(ies) for validation"
		print info ""
		
	else
		print info ""
		print info "ONLINE installation detected - extracting registries from CatalogSources..."
		print info ""
		
		# Get registries from operators' catalog sources (cluster-level consolidation)
		print info "Collecting CatalogSource information from all operators..."
		local catalog_data=$(get_registries_from_operators)
		if [[ -z "$catalog_data" ]]; then
			print error "${CHECK_FAIL} No valid CatalogSources found for installed operators."
			return 1
		fi
		
		# Consolidate unique registries from catalog sources
		local temp_registries=$(mktemp)
		while IFS='|' read -r image namespace catalog_name; do
			if [[ -n "$image" ]]; then
				extract_registry_from_image "$image" >> "$temp_registries"
			fi
		done <<< "$catalog_data"
		
		registries_to_test=$(sort -u "$temp_registries")
		rm -f "$temp_registries"
		
		if [[ -z "$registries_to_test" ]]; then
			print error "${CHECK_FAIL} No registries could be extracted from CatalogSources."
			return 1
		fi
		
		registry_count=$(echo "$registries_to_test" | wc -l | tr -d ' ')
		print info ""
		print info "Consolidated $registry_count unique registry(ies) from CatalogSources for validation"
		print info ""
	fi
	
	# ========================================
	# PHASE 2: Per-Node Registry Validation
	# ========================================
	print info "=========================================="
	print info "PHASE 2: Per-Node Registry Validation"
	print info "=========================================="
	print info ""
	print info "Testing connectivity and authentication from all cluster nodes..."
	print info ""
	
	local failed_registries=0
	local passed_registries=0
	local tested_count=0
	local failed_registry_list=""
	local passed_registry_list=""
	
	# Test each consolidated registry from all nodes
	while read -r registry; do
		if [[ -z "$registry" ]]; then
			continue
		fi
		
		tested_count=$((tested_count + 1))
		
		print_subsection
		print info "[$tested_count of $registry_count] Testing registry: $registry"
		print info ""
		
		# Test connectivity from all nodes (per-node validation)
		if test_registry_connectivity "$registry"; then
			passed_registries=$((passed_registries + 1))
			passed_registry_list="${passed_registry_list}  ${CHECK_PASS} $registry\n"
			
			# For online installations, also test authentication
			if [[ "$is_offline" == "false" ]]; then
				# Find a catalog image using this registry for auth testing
				local test_image=$(echo "$catalog_data" | grep "^[^|]*$registry" | head -1 | cut -d'|' -f1)
				if [[ -n "$test_image" ]]; then
					print info "Testing authentication for image: $test_image"
					test_registry_auth "$test_image"
				fi
			fi
		else
			failed_registries=$((failed_registries + 1))
			failed_registry_list="${failed_registry_list}  ${CHECK_FAIL} $registry\n"
		fi
	done <<< "$registries_to_test"
	
	# Final summary
	print_subsection
	print info "=========================================="
	print info "Registry Validation Summary"
	print info "=========================================="
	if [[ "$is_offline" == "true" ]]; then
		print info "Installation Type: OFFLINE (disconnected)"
		print info "Registries Tested: Mirror registries from IDMS/ITMS"
	else
		print info "Installation Type: ONLINE (connected)"
		print info "Registries Tested: CatalogSource registries"
	fi
	print info ""
	print info "Total Registries Validated: $tested_count"
	print info "Passed Registries: $passed_registries"
	print info "Failed Registries: $failed_registries"
	print info ""
	
	if [[ $passed_registries -gt 0 ]]; then
		print info "Passed Registries:"
		echo -e "$passed_registry_list"
	fi
	
	if [[ $failed_registries -gt 0 ]]; then
		print error "Failed Registries:"
		echo -e "$failed_registry_list"
	fi
	print info "=========================================="
	
	if [[ $failed_registries -gt 0 ]]; then
		return 1
	fi
	return 0
}
