#!/bin/bash

##############################################################################
#Script Name	: discoverLLA.sh
#Description	: Utility to query Link Local Addresses (LLAs) of discovered 
#                 nodes of IBM Storage Fusion HCI system
#Args       	:
#Author       	:Anshu Garg
#Email         	:ganshug@gmail.com
##############################################################################

##############################################################################
# This utility will query link local address from newly discovered nodes
# Execute it from a bash shell where you have logged into HCI OpenShift API
# Ensure jq is installed on that system
# Execute chmod+x discoverLLA.sh to give execute permission to script
# It returns: List of LLAs (see sample below)
# "fe80::3a68:ddff:fe49:7e05"
# "fe80::3a68:ddff:fe49:7b6d"
# "fe80::a94:efff:fef1:3107"
# "fe80::a94:efff:fef1:309b"
# "fe80::a94:efff:fef3:1b31"
##############################################################################

CHECK_PASS='  ✅'
CHECK_FAIL='  ❌'
CHECK_UNKNOW='  ⏳'
PADDING_1='   '
PADDING_2='      '
TEMP_MMHEALTH_FILE=$(pwd)/lla.txt
FUSIONNS="ibm-spectrum-fusion-ns"


function print_header() {
    echo "======================================================================================"
    echo "Started collection of LLAs for IBM Storage Fusion HCI cluster at $(date +'%F %z %r')"
    echo "======================================================================================"
}

function print_section() {
    echo ""
    echo "======================================================================================"
    echo "			****** $1 ******"
    echo "======================================================================================"
    echo ""
}

function print_subsection() {
    echo ""
    echo "======================================================================================"
    echo ""
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
        	print error "${CHECK_FAIL} Red Hat OpenShift API is inaccessible. Please login to OCP api before executing script."
		exit 1
        else
        	print info "${CHECK_PASS} Red Hat OpenShift API is accessible."
	fi
}

# Get LLAs from nodes
function getllas() {
	count=$(oc -n ibm-spectrum-fusion-ns get ccf -oname|wc -l)
	if [[ $count -gt 0 ]]; then
		print info "Here is list of LLAs:"
		oc -n ibm-spectrum-fusion-ns get ccf -oname | xargs oc -n ibm-spectrum-fusion-ns -ojson  get|jq '.items[].spec.linkLocal' 
	else
		print info "No new nodes discovered."
	fi
}

rm -f ${REPORT} > /dev/null
print_header
print_section "API access"
verify_api_access
print_section "Get LLAs"
getllas
