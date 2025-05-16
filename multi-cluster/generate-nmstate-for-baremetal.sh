#!/bin/bash

##############################################################################
#Script Name	: generate-nmstate-for-baremetal.sh
#Description	: Utility generates NMState specification for bare metal nodes.
#Args       	:
#Author       :Anshu Garg
#Email        :ganshug@gmail.com
##############################################################################

##############################################################################
# This utility will query HCI nodes inventory and generate NMState spec based
# on current network configuration of switches and nodes.
# Execute it from a bash shell where you have logged into HCI OpenShift API.
# Ensure jq is installed on that system.
#
# Execute as:
# ./generate-nmstate-for-baremetal.sh
#
# Result:
# Script will generate NMState for all compute nodes that are not part of 
# base HCI OCP cluster, in current directory.
##############################################################################
FUSIONNS="ibm-spectrum-fusion-ns"
APPLIANCEINFOCM="appliance-info"
BASERACKUSERCONFSECRET="userconfig-secret"

function help () {
cat << EOF
  ./generate-nmstate-for-baremetal.sh

  Result:
  Script will generate NMState for all compute nodes that are not part of 
  base HCI OCP cluster, in current directory.  
EOF
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

# Verify we are able to access OCP API and can execute oc commands
function verify_api_access() {
	print info "Verify Red Hat OpenShift API access."
	oc get clusterversion >/dev/null
	if [ $? -ne 0 ]; then
        	print error "${CHECK_FAIL} Red Hat OpenShift API is inaccessible. Rest of the check can not be executed. Please login to OCP api before executing script."
		exit 1
        else
        	print info "${CHECK_PASS} Red Hat OpenShift API is accessible."
	fi
}

# Utility to query MTU value
function get_mtu () {
        mtu=$(oc -n $FUSIONNS get secret $BASERACKUSERCONFSECRET -o json | jq '.data."userconfig_secret.json"'|cut -d '"' -f 2|base64 -d|jq '.mtuCount')
        return $mtu
}

# Get rackinfocm name from appliance info
function get_rackinfocm_from_applianceinfocm () {
    # Get appliance info cm value
    local data=$(oc -n $FUSIONNS get cm $APPLIANCEINFOCM  -o json |jq '.data[]')
    local baserackinfocmname=$(echo $data|sed 's/\\"/"/g'| sed 's/^"//;s/"$//'|jq -r 'select(.rackType == "base") | .rackInfoCM')
    echo ${baserackinfocmname}
}

# Find is vlan over bond0 is used for br-ex or bond0
function is_vlan_over_bond0 () {
    # Get base rack's rackinfo cm name
    local rackinfocmname=$(get_rackinfocm_from_applianceinfocm)
    local baserackinfodata=$(oc -n $FUSIONNS get cm $baserackinfocmname -o json|jq '.data[]')
    local vlanoverbond0=$(echo $baserackinfodata|sed 's/\\n//g'|sed 's/\\"/"/g'| sed 's/^"//;s/"$//'|jq ".rackInfo.vlanForBaremetalPrimaryInterface")
    if [ -z "$vlanoverbond0" ]; then
    	return false
    else
        return true
   fi
}

# Gets list of nodes from base rack config map
function get_base_ks_nodes(){
    data=$(oc -n $FUSIONNS get cm $APPLIANCEINFOCM  -o json |jq '.data[]')
    basekscmname=$(echo $data|sed 's/\\"/"/g'| sed 's/^"//;s/"$//'|jq -r 'select(.rackType == "base") | .kickstartCM')
    baseksdata=$(oc -n $FUSIONNS get cm $basekscmname -o json|jq '.data."kickstart.json"')
    baseksnodes=$(echo $baseksdata|sed 's/\\"/"/g'|sed 's/\\n//g'|sed 's/^"//;s/"$//'|jq ".computeNodeIntegratedManagementModules")

}

# It iterates over all nodes of a given kickstart and generates nmstate for all nodes with desired IP management spec (DHCP|Static)
function generate_nmstate() {
    # Loop through the compute nodes and generate nmstate.yaml files
    for node in $(jq -r '.computeNodeIntegratedManagementModules[].name' $json_file); do
 	nmstate_file="nmstate-$node.yaml"

  	# Extract the MAC addresses and interfaces for the compute node
  	mac_addresses=$(jq -r --arg node "$node" '.computeNodeIntegratedManagementModules[] | select(.name == $node) | .networkInterfaces[] | select(.interfaceType == "baremetal") | .macAddress' $json_file)
  	interfaceLeg1_values=$(jq -r --arg node "$node" '.computeNodeIntegratedManagementModules[] | select(.name == $node) | .networkInterfaces[] | select(.interfaceType == "baremetal") | .interfaceLeg1' $json_file)
  	interfaceLeg2_values=$(jq -r --arg node "$node" '.computeNodeIntegratedManagementModules[] | select(.name == $node) | .networkInterfaces[] | select(.interfaceType == "baremetal") | .interfaceLeg2' $json_file)
  	second_mac_address=$(echo "$mac_addresses" | tr ' ' ',')

  	# Create the nmstate.yaml file
  	cat <<EOF > "$nmstate_file"
	apiVersion: agent-install.openshift.io/v1beta1
	kind: NMStateConfig
	metadata:
  	  labels:
            infraenvs.agent-install.openshift.io: gpu1
          name: compute-$node
          namespace: gpu1
        spec:
          config:
            interfaces:
            - ipv4:
                dhcp: true
                enabled: true
            - ipv6:
                enabled: false
            link-aggregation:
              mode: 802.3ad
              options:
                lacp_rate: "1"
                miimon: "140"
                xmit_hash_policy: "1"
              ports:
              - name: $(echo "$interfaceLeg1_values" | tr ' ' ',')
              - name: $(echo "$interfaceLeg2_values" | tr ' ' ',')
          interfaces:
          - macAddress: $(echo "$mac_addresses" | tr ' ' ',')
            name: $(echo "$interfaceLeg1_values" | tr ' ' ',')
          - macAddress: $second_mac_address
            name: $(echo "$interfaceLeg2_values" | tr ' ' ',')
	EOF
    done
}
