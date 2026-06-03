#!/bin/bash

##############################################################################
# Network Utility Functions for Pre-upgrade Health Check
# 
# This file contains modular functions for testing DNS and DHCP reachability
# across all cluster nodes.
#
# Functions:
# - get_base_rack_info()
# - is_dhcp_cluster()
# - get_ntp_server()
# - get_node_dns_servers()
# - get_node_dhcp_server()
# - verify_dns_reachability()
# - verify_dhcp_reachability()
# - verify_ntp_reachability()
# - verify_nodes_dns_dhcp()
##############################################################################

# Get base rack information from appliance-info configmap
function get_base_rack_info() {
	# Get the appliance-info configmap
	local appliance_info=$(oc get configmap appliance-info -n ${FUSIONNS} -o json 2>/dev/null)
	if [[ -z "$appliance_info" ]]; then
		print info "appliance-info configmap not found."
		return 1
	fi
	
	# Get all keys (rack serials) from the data section
	local rack_serials=$(echo "$appliance_info" | jq -r '.data | keys[]')
	
	# Find the base rack (rackType: "base")
	for rack_serial in $rack_serials; do
		local rack_data=$(echo "$appliance_info" | jq -r ".data.\"$rack_serial\"")
		local rack_type=$(echo "$rack_data" | jq -r '.rackType // empty')
		
		if [[ "$rack_type" == "base" ]]; then
			# Export rack information
			export BASE_RACK_SERIAL="$rack_serial"
			export PLATFORMCONFIG_CM=$(echo "$rack_data" | jq -r '.platformconfigCM // empty')
			export USERCONFIG_SECRET=$(echo "$rack_data" | jq -r '.userconfigSecret // empty')
			print info "Base rack found: $BASE_RACK_SERIAL"
			print info "Platform config CM: $PLATFORMCONFIG_CM"
			print info "User config secret: $USERCONFIG_SECRET"
			return 0
		fi
	done
	
	print info "No base rack found in appliance-info configmap."
	return 1
}

# Determine if cluster uses DHCP or static IP
function is_dhcp_cluster() {
	if ! get_base_rack_info; then
		print info "Could not determine base rack. Assuming static IP configuration."
		return 1
	fi
	
	# Try platformconfig configmap first
	if [[ -n "$PLATFORMCONFIG_CM" ]]; then
		local platform_config=$(oc get configmap "$PLATFORMCONFIG_CM" -n ${FUSIONNS} -o json 2>/dev/null)
		if [[ -n "$platform_config" ]]; then
			# The data is stored as a JSON string in a key like "platformconfig-f68l021.json"
			local config_key=$(echo "$platform_config" | jq -r '.data | keys[0]')
			local config_json=$(echo "$platform_config" | jq -r ".data.\"$config_key\"")
			local dhcp_enabled=$(echo "$config_json" | jq -r '.dhcp // false')
			
			print info "Found $PLATFORMCONFIG_CM, dhcp: $dhcp_enabled"
			if [[ "$dhcp_enabled" == "true" ]]; then
				return 0
			fi
		fi
	fi
	
	# Try userconfig secret as fallback
	if [[ -n "$USERCONFIG_SECRET" ]]; then
		local user_config=$(oc get secret "$USERCONFIG_SECRET" -n ${FUSIONNS} -o json 2>/dev/null)
		if [[ -n "$user_config" ]]; then
			# The data is base64 encoded JSON
			local config_key=$(echo "$user_config" | jq -r '.data | keys[0]')
			local config_json=$(echo "$user_config" | jq -r ".data.\"$config_key\"" | base64 -d 2>/dev/null)
			local dhcp_enabled=$(echo "$config_json" | jq -r '.dhcp // false')
			
			print info "Found $USERCONFIG_SECRET, dhcp: $dhcp_enabled"
			if [[ "$dhcp_enabled" == "true" ]]; then
				return 0
			fi
		fi
	fi
	
	return 1
}

# Get NTP server from platform config
function get_ntp_server() {
	if [[ -z "$PLATFORMCONFIG_CM" ]]; then
		get_base_rack_info >/dev/null 2>&1
	fi
	
	# Try platformconfig configmap first
	if [[ -n "$PLATFORMCONFIG_CM" ]]; then
		local platform_config=$(oc get configmap "$PLATFORMCONFIG_CM" -n ${FUSIONNS} -o json 2>/dev/null)
		if [[ -n "$platform_config" ]]; then
			local config_key=$(echo "$platform_config" | jq -r '.data | keys[0]')
			local config_json=$(echo "$platform_config" | jq -r ".data.\"$config_key\"")
			local ntp=$(echo "$config_json" | jq -r '.ntp // empty')
			
			if [[ -n "$ntp" ]]; then
				echo "$ntp"
				return 0
			fi
		fi
	fi
	
	# Try userconfig secret as fallback
	if [[ -n "$USERCONFIG_SECRET" ]]; then
		local user_config=$(oc get secret "$USERCONFIG_SECRET" -n ${FUSIONNS} -o json 2>/dev/null)
		if [[ -n "$user_config" ]]; then
			local config_key=$(echo "$user_config" | jq -r '.data | keys[0]')
			local config_json=$(echo "$user_config" | jq -r ".data.\"$config_key\"" | base64 -d 2>/dev/null)
			local ntp=$(echo "$config_json" | jq -r '.ntp // empty')
			
			if [[ -n "$ntp" ]]; then
				echo "$ntp"
				return 0
			fi
		fi
	fi
	
	return 1
}

# Get DNS servers from node
function get_node_dns_servers() {
	local node="$1"
	local dns_servers=$(oc debug nodes/${node} -- chroot /host cat /etc/resolv.conf 2>/dev/null | grep "^nameserver" | awk '{print $2}')
	echo "$dns_servers"
}

# Get DHCP server from node (if DHCP is used)
function get_node_dhcp_server() {
	local node="$1"
	# Try to get DHCP server from lease file
	local dhcp_server=$(oc debug nodes/${node} -- chroot /host bash -c "grep -h 'dhcp-server-identifier' /var/lib/dhclient/*.lease 2>/dev/null | tail -1 | awk '{print \$3}' | tr -d ';'" 2>/dev/null)
	echo "$dhcp_server"
}

# Verify DNS server reachability from node
function verify_dns_reachability() {
	local node="$1"
	local dns_server="$2"
	
	# Test DNS server reachability using ping
	oc debug nodes/${node} -- chroot /host ping -c 2 -W 2 ${dns_server} >/dev/null 2>&1
	return $?
}

# Verify DHCP server reachability from node
function verify_dhcp_reachability() {
	local node="$1"
	local dhcp_server="$2"
	
	# Test DHCP server reachability using ping
	oc debug nodes/${node} -- chroot /host ping -c 2 -W 2 ${dhcp_server} >/dev/null 2>&1
	return $?
}

# Verify NTP server reachability from node
function verify_ntp_reachability() {
	local node="$1"
	local ntp_server="$2"
	
	# Test NTP server reachability using ping
	oc debug nodes/${node} -- chroot /host ping -c 2 -W 2 ${ntp_server} >/dev/null 2>&1
	return $?
}

# Enhanced DNS and DHCP verification
function verify_nodes_dns_dhcp() {
	print info "Verifying DNS and DHCP reachability on all nodes..."
	
	# Determine if cluster uses DHCP
	local use_dhcp=0
	if is_dhcp_cluster; then
		use_dhcp=1
		print info "Cluster is configured with DHCP. Will check DNS, DHCP, and NTP reachability."
	else
		print info "Cluster is configured with static IPs. Will check DNS and NTP reachability only."
	fi
	
	# Get NTP server
	local ntp_server=$(get_ntp_server)
	if [[ -n "$ntp_server" ]]; then
		print info "NTP server configured: $ntp_server"
	else
		print info "NTP server not found in configuration."
	fi
	
	local overall_status=0
	local nodes=$(oc get nodes --no-headers | grep -v "NotReady" | awk '{print $1}')
	local node_count=$(echo "$nodes" | wc -l)
	local current=0
	
	for node in $nodes; do
		current=$((current + 1))
		print_subsection
		print info "[$current/$node_count] Checking node: $node"
		
		# Check DNS servers
		print info "  Getting DNS servers from $node..."
		local dns_servers=$(get_node_dns_servers "$node")
		
		if [[ -z "$dns_servers" ]]; then
			print error "  ${CHECK_FAIL} Could not retrieve DNS servers from $node"
			overall_status=1
			continue
		fi
		
		print info "  Found DNS server(s): $(echo $dns_servers | tr '\n' ' ')"
		
		# Test each DNS server
		for dns_server in $dns_servers; do
			print info "  Testing DNS server $dns_server reachability..."
			if verify_dns_reachability "$node" "$dns_server"; then
				print info "  ${CHECK_PASS} DNS server $dns_server is reachable from $node"
			else
				print error "  ${CHECK_FAIL} DNS server $dns_server is NOT reachable from $node"
				overall_status=1
			fi
		done
		
		# Test DNS resolution
		print info "  Testing DNS resolution..."
		oc debug nodes/${node} -- chroot /host nslookup $IBMENTITLEDREG >/dev/null 2>&1
		if [[ $? -eq 0 ]]; then
			print info "  ${CHECK_PASS} DNS resolution is working on $node"
		else
			print error "  ${CHECK_FAIL} DNS resolution is NOT working on $node"
			overall_status=1
		fi
		
		# Check DHCP if enabled
		if [[ $use_dhcp -eq 1 ]]; then
			print info "  Getting DHCP server from $node..."
			local dhcp_server=$(get_node_dhcp_server "$node")
			
			if [[ -z "$dhcp_server" ]]; then
				print warn "  ${CHECK_WARN} Could not retrieve DHCP server from $node (may be using static IP)"
			else
				print info "  Found DHCP server: $dhcp_server"
				print info "  Testing DHCP server reachability..."
				if verify_dhcp_reachability "$node" "$dhcp_server"; then
					print info "  ${CHECK_PASS} DHCP server $dhcp_server is reachable from $node"
				else
					print error "  ${CHECK_FAIL} DHCP server $dhcp_server is NOT reachable from $node"
					overall_status=1
				fi
			fi
		fi
		
		# Check NTP server if configured
		if [[ -n "$ntp_server" ]]; then
			print info "  Testing NTP server $ntp_server reachability..."
			if verify_ntp_reachability "$node" "$ntp_server"; then
				print info "  ${CHECK_PASS} NTP server $ntp_server is reachable from $node"
			else
				print error "  ${CHECK_FAIL} NTP server $ntp_server is NOT reachable from $node"
				overall_status=1
			fi
		fi
	done
	
	print_subsection
	if [[ $overall_status -eq 0 ]]; then
		print info "${CHECK_PASS} All DNS/DHCP/NTP reachability checks passed."
	else
		print error "${CHECK_FAIL} Some DNS/DHCP/NTP reachability checks failed. Review above for details."
	fi
	
	return $overall_status
}

# Made with Bob