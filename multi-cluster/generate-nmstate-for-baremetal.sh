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
NMSTATESDIR="nmstates"

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
    echo ${baseksnodes}
}

# It iterates over all nodes of a given kickstart and generates nmstate for all nodes with desired IP management spec (DHCP|Static)
function generate_nmstate() {
 echo "hi"
}

#### main
rm -rf ${NMSTATESDIR} > /dev/null
mkdir ${NMSTATESDIR}
cd ${NMSTATESDIR}
if [ $# -eq 0 ]; then
        echo $(get_base_ks_nodes)
else
	help
fi
