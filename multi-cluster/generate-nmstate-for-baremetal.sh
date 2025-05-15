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
        mtu=$(oc -n ibm-spectrum-fusion-ns get secret userconfig-secret -o json | jq '.data."userconfig_secret.json"'|cut -d '"' -f 2|base64 -d|jq '.mtuCount')
        return mtu
}

function is_vlan_over_bond(){
    print info "Verify presence of CSI configmap if it is a 2.6.1 MetroDR setup before going for 2.7.1 upgrade"
    isfversion=$(oc get csv -n $FUSIONNS | grep isf-operator | awk '{print $1}' | grep "2.6.1" | wc -l)
    is_metrodr_setup
    is_metrodr_setup_op=$?
    if [ "$is_metrodr_setup_op" -eq 1 ] && [ "$isfversion" -eq 1 ]; then
        # 2.6.1 metrodr setup
        # check for CSI configmap
            check=$(oc get configmap -n "$SCALECSINS" ibm-spectrum-scale-csi-config -o json | jq '.data."VAR_DRIVER_DISCOVER_CG_FILESET"' | grep "DISABLED")
            if [ $? -eq 0 ]; then
		        print info "${CHECK_PASS} CSI Configmap with required values present on 2.6.1 metrodr setup"
            else
                print error "${CHECK_FAIL} CSI Configmap with required values not present on 2.6.1 MetroDR setup. \nPlease refer to the workaround to create CSI Configmap present in this doc : https://www.ibm.com/docs/en/sfhs/2.7.x?topic=system-prerequisites-prechecks and retry again."
	        fi
    else
        # MetroDR setup is not present, skip CSI configmap verification
        print info "Skipping CSI configmap verification as it is not a metroDR 2.6.1 setup"
    fi
}

