#!/bin/bash
##
# start_Copyright_Notice
# Licensed Materials - Property of IBM
#
# IBM Spectrum Fusion 5639-SPS
# (C) Copyright IBM Corp. 2023 All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice
# ===============
# Authors: 
# Daniel.Danner@ibm.com
# xchai@us.ibm.com
# ganshug@gmail.com
# ===============
#set -x 

# Goal:
# This script is used to validate DHCP and DNS have been setup as required by HCI network requirements.
# 1. Verify both DNS forward lookup and reverse lookup for nodes, bootstrap VM and API VIP.
# 2. Verify DNS forward lookup for Ingress VIP.
# 3. Verify DHCP reservation for nodes and bootstrap VM.
# 4. Verify DHCP is set to send FQDN for nodes.
# 5. Verify both VIPs to be in same CIDR as Baremetal machine CIDR.
# 6. Verify none of the IPs are live/in use before starting installation.
# 7. Verify  lookup and reverse look have 1:1 results, no duplicates or more than one record returned.
# 
# Prerequisites:
# 1. Use this script before plugging in IBM Storage Fusion HCI node to data centre network and powering.
# Since dhcp client requests are simulated to verify IP and hostname assignment, 
# HCI nodes will have mac duplicate so it is imperative to not have nodes plugged in.
#
# 2. This expects an input file in a specific format with details of mac, IPs, VIPs, hostname, cluster name and basedomain. Here is a sample
# 
# CIDR,10.3.0.16/25
# NIC,enp3s0
# DNS1,10.3.0.1
# DNS2,10.3.0.2
# NTP,10.3.0.1
# CLUSTERNAME,cluster-name
# BASEDOMAIN=basedomain
# APIVIP,api,10.3.0.8
# INGRESSVIP,foo.apps,10.3.0.9
# KVM,bootstrap,10.3.0.10,00:16:3e:6a:41:16
# RU2,control-1-ru2,10.3.0.11,08:c0:eb:ff:4a:46
# RU3,control-1-ru3,10.3.0.12,08:c0:eb:ff:43:86
# RU4,control-1-ru4,10.3.0.13,08:c0:eb:ff:43:8a
# RU5,compute-1-ru5,10.3.0.14,08:c0:eb:ff:3d:3e
# RU6,compute-1-ru6,10.3.0.15,08:c0:eb:ff:3d:5a
# RU7,compute-1-ru7,10.3.0.16,08:c0:eb:ff:43:7e
#
# 3. DHCP and DNS records must already be in place to use this script.

# Regular Colors
ENDCOLOR="\e[0m"
Black='\033[0;30m'        # Black
RED='\033[0;31m'          # Red
GREEN='\033[0;32m'        # Green
YELLOW='\033[0;33m'       # Yellow
BLUE='\033[0;34m'         # Blue
PURPLE='\033[0;35m'       # Purple
CYAN='\033[0;36m'         # Cyan
WHITE='\033[0;37m'        # White

## Initialize variables
file=""
VERIFYDHCP="n"

## Print utility usage help
usage(){
	echo -e "${BLUE}Usage: $(basename \"${BASH_SOURCE[0]}\") -in myhcinetwork.txt [-dhcp [y|n]]${ENDCOLOR}\n"
	echo -e "${BLUE}For validating network, execute following:${ENDCOLOR}\n"
	echo -e "${GREEN}  ./verify_network.sh -in myhcinetwork.txt -dhcp n${ENDCOLOR}\n"
	echo -e "${BLUE}Available options:${ENDCOLOR}\n"
	echo -e "${BLUE} -in: myhcinetwork.txt: Required parameter that specifies location to file with DHCP/DNS details for rack to be deployed.${ENDCOLOR}\n"
	echo -e "${BLUE} -dhcp: [Y(y)|N(n)]: Optional parameter to specify if DHCP verification should not be done by utility.${ENDCOLOR}\n"
	echo -e "${BLUE}Example:${ENDCOLOR}\n"
	echo -e "${BLUE}./verify_network.sh myhcinetwork.txt -dhcp y${ENDCOLOR}\n"
    exit 1
}

## Process command line arguments
function processArguments {
    while [ $# -gt 0 ]; do
        arg=$1
        shift
        case $arg in
		-in)
		    file=$1
		    shift ;;
		-dhcp)
		    VERIFYDHCP=$1
		    shift ;;
		-*)
            echo -e "${YELLOW}Warning: Ignoring unrecognized option ${arg} ${ENDCOLOR} \n\n"
            # Discard option value
            shift ;;
        *)
		    echo -e "${YELLOW}Warning: Ignoring unrecognized argument ${arg} ${ENDCOLOR} \n\n"
        esac
    done
}

## Check last command return code
function check() {
	if [ "$1" -ne 0 ] ; then
		if [[ -z "$3" ]];then
			echo -e "${RED}Error above ^^^^^^^^^^^^^^^^^^^^^^ ${ENDCOLOR} \n\n\n"
		else
			echo -e "${RED}Error: ${3}${ENDCOLOR} \n\n"
		fi
		if [[ "$2" == "y" ]];then
			exit 1
		fi
	fi
}

## Function to compare two variables
function comp {
	if [ "$1" == "$2" ] ; then
		echo -e "${GREEN}Expected $1 matched $2 ${ENDCOLOR}"
	else
		echo -e "${RED}ERROR: Expected $1 but got $2 ${ENDCOLOR}"
	fi
}

## Funtion to verify if VIPs for API and Ingress belong to same CIDR as OCP machine CIDR as required by OCP IPI installation
function verifycidr {
	local file=$1
	local apivip=$(cat $file |awk -F "," '/APIVIP/{print $3}')	
	local ingressvip=$(cat $file |awk -F "," '/INGRESSVIP/{print $3}')	
	local cidr=$(cat $file |awk -F "," '/CIDR/{print $2}')
	local network=$(echo $cidr | cut -d/ -f1)
	local mask=$(echo $cidr | cut -d/ -f2)
	local network_dec=$(echo $network | awk -F. '{printf("%d\n", ($1 * 256 + $2) * 256 + $3)}')
	local api_ip_dec=$(echo $apivip | awk -F. '{printf("%d\n", ($1 * 256 + $2) * 256 + $3)}')
	local ingress_ip_dec=$(echo $ingressvip | awk -F. '{printf("%d\n", ($1 * 256 + $2) * 256 + $3)}')
  	local mask_dec=$((0xffffffff << (32 - $mask)))
	local error=0
	# Check if API VIP is in machine CIDR
	if [[ $((api_ip_dec & mask_dec)) -ne $((network_dec & mask_dec)) ]]; then
		echo -e "${RED}ERROR: API VIP: $apivip is not within machine CIDR: $cidr.${ENDCOLOR}\n"
		error=1
	fi

	# Check if Ingress VIP is in machine CIDR
	if [[ $((ingress_ip_dec & mask_dec)) -ne $((network_dec & mask_dec)) ]]; then
		echo -e "${RED}ERROR: Ingress VIP: $ingressvip is not within machine CIDR: $cidr.${ENDCOLOR}\n"
		error=1
	fi
	check "$error" "y"
}

## Function to verify DNS lookup and reverse lookup records for 
## each node, VIP, bootstrap one by one (try both DNS servers if more than one DNS servers are available on network)
function verifydns {
	local file=$1
	local dnsServers=$2
	local cidr=$(cat $file |awk -F "," '/CIDR/{print $2}')
	local clustername=$(cat $file |awk -F "," '/CLUSTERNAME/{print $2}')
	local basedomain=$(cat $file |awk -F "," '/BASEDOMAIN/{print $2}')
	for dns in ${dnsServers}
	do
		echo -e "${BLUE}#######################${ENDCOLOR} \n"
		echo -e "${BLUE}# Verify DNS lookup against DNS server ${dns}${ENDCOLOR} \n"
		echo -e "${BLUE}#######################${ENDCLOLOR}\n"

		while IFS="," read -r ru hostname ip mac; do 
			RES=''
			echo "Resolving hostname ${hostname}. Expecting ip ${ip}."  
			RES=$(host -4 -W 2  $hostname.$clustername.$basedomain $dns |awk '/has address/{print $4}' )
			comp $ip $RES
			# Count number of ips returned by lookup, it should be 1 and only 1
			RES=$(host -4 -W 2  $hostname.$clustername.$basedomain $dns |awk '/has address/{print $4}'|wc -l)
			comp "1" $RES
			RES=''
		done < <(cat $file |egrep 'RU|VIP|KVM')
		echo -e "\n \n"

		echo -e "${BLUE}#######################${ENDCOLOR} \n"
		echo -e "${BLUE}# Verify DNS reverse lookup against DNS server ${dns}${ENDCOLOR} \n"
		echo -e "${BLUE}#######################${ENDCLOLOR}"

		while IFS="," read -r ru hostname ip mac; do
			RES=''
			echo "Resolving ip ${ip}. Expecting hostname ${hostname}.${clustername}.${basedomain}." 
			RES=$(host -4 -W 2 $ip $dns |awk '/domain name pointer/{print $5}' | sed 's/.$//' )
			comp $hostname.$clustername.$basedomain $RES
			# Count number of hosts returned by reverse lookup, it should be 1 and only 1
			RES=$(host -4 -W 2 $ip $dns |awk '/domain name pointer/{print $5}' | sed 's/.$//'| wc -l)
			comp "1" $RES
			RES=''
		done < <(cat $file |egrep 'RU|APIVIP|KVM')
		echo -e "\n \n"
	done
	
	echo -e "${BLUE}#######################${ENDCOLOR} \n"
        echo -e "${BLUE}# Verify DNS lookup without specifying any DNS server, incase there are mutliple DNS servers on network with entry for one node ${ENDCOLOR} \n"
	echo -e "${BLUE}#######################${ENDCLOLOR}\n"
	
	while IFS="," read -r ru hostname ip mac; do
        	RES=''
                echo "Resolving hostname ${hostname}. Expecting ip ${ip}."
                RES=$(host -4 -W 2  $hostname.$clustername.$basedomain|awk '/has address/{print $4}' )
                comp $ip $RES
                # Count number of ips returned by lookup, it should be 1 and only 1
                RES=$(host -4 -W 2  $hostname.$clustername.$basedomain|awk '/has address/{print $4}'|wc -l)
                comp "1" $RES
                RES=''
        done < <(cat $file |egrep 'RU|VIP|KVM')
        echo -e "\n \n"	
}

## Function to verify DHCP reservation for each node and bootstrap one by one 
function verifydhcp {
	echo -e "${BLUE}#######################"
	echo -e "${BLUE}# Verify DHCP setup"
    	echo -e "${BLUE}#######################${ENDCOLOR}"

    	#############################################
	local file=$1
    	local NIC=$(cat $file |awk -F "," '/NIC/{print $2}') 
	local clustername=$(cat $file |awk -F "," '/CLUSTERNAME/{print $2}')
        local basedomain=$(cat $file |awk -F "," '/BASEDOMAIN/{print $2}')
    	#############################################
    	# This NIC must be connected to the data centre network to test DHCP
 	
	while IFS="," read -r ru hostname ip mac; do 
		## kill any dhcp client requests
    		killall dhclient  1>/dev/null  2>/dev/null
		echo -e "DHCP test for hostname ${BLUE}${hostname}.${clustername}.${basedomain} with mac ${mac}. Expecting ip ${ip} ${ENDCOLOR}." 
		
		## Add a new network interface with mac that is being tested for correct DHCP reservation
		ip link add link ${NIC} address $mac ${NIC}.$ru  type macvlan
		ip link set ${NIC}.$ru up
		
		## Send dhcp request, that is, send request to get IP/hostname from DHCP
		dhclient ${NIC}.$ru 
		sleep 2
		
		## Get IP assigned to new interface from DHCP
		dhcpip=`ip -4  addr show ${NIC}.$ru |  grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" |head -1`
		comp $ip $dhcpip
		
		## After validation, remove interface else whe node is added to network, it will create mac duplicacy
		ip link delete ${NIC}.$ru
		echo -e "\n"
		echo "Link deletion completed. Waiting for 5 seconds before starting test for next nic." 
		sleep 5
	done < <(cat $file |egrep 'RU|KVM')
	killall dhclient  2>/dev/null
}

## None of the IPs should be use and pingable before HCI install is completed
function verifyipsnotinuse {	
	local file=$1
	local clustername=$(cat $file |awk -F "," '/CLUSTERNAME/{print $2}')
        local basedomain=$(cat $file |awk -F "," '/BASEDOMAIN/{print $2}')
	while IFS="," read -r ru hostname ip mac; do 
		# ping test - IPs should not live on the network as rack is not installed yet
		echo -e "${BLUE}Info: ping ${hostname}.${clustername}.${basedomain} and $ip${ENDCOLOR}"
		ping -c 3 $ip
		# When ping is successful, it is an error for this check so return code zero is error in this case
		# In that case force an error code 1 to be sent to check method to enable failure path
		if [[ $? -eq 0 ]];then
			check "1" "n" "$ip is pingable before HCI installation. IP can not be used. Check DHCP/DNS configuration for IP: $ip"
		fi
	done < <(cat $file |egrep 'RU|VIP|KVM' )
	echo -e "\n \n"
}

#########Start main here ######
## Process options
processArguments "$@"

echo -e "${BLUE}Info: Input file provided is $file. ${ENDCOLOR} \n"

## Validate input network file
if [[ ! -f $file || ! -s $file ]]; then
	echo -e "${RED}Error: either input file does not exist or is empty. ${ENDCOLOR} \n\n"
	exit 1
fi
echo -e "${BLUE}Info: Verify dhcp is set to: $VERIFYDHCP. ${ENDCOLOR} \n"

## Get DNS servers from input file
dns1=`cat $file |grep DNS1|awk -F',' '{print $2}'`
dns2=`cat $file |grep DNS2|awk -F',' '{print $2}'`
dnsServers=(${dns1} ${dns2})

#Validate input file for dns server(s) details
if [[ -z "$dnsServers" ]];then
	echo -e "${RED}Error: DNS server is not specified in input file. ${ENDCOLOR} \n\n"
	exit 1
fi
echo -e "${BLUE}Info: DNS server in input file: $dnsServers. ${ENDCOLOR} \n"

## Get NTP server details from input file
ntp=`cat $file | grep -i NTP | awk -F',' '{print $2}'`
if [[ -z "$ntp" ]];then
	echo -e "${RED}Error: NTP server is not specified in input file. ${ENDCOLOR} \n\n"
        exit 1
fi
echo -e "${BLUE}Info: NTP server in input file: $ntp. ${ENDCOLOR} \n"

## Get NIC server details from input file
nic=`cat $file | grep -i NIC | awk -F',' '{print $2}'`
if [[ -z "$nic" ]];then
	echo -e "${RED}Error: Network interface is not specified in input file. ${ENDCOLOR} \n\n"
        exit 1
fi
echo -e "${BLUE}Info: Network interface in input file: $nic. ${ENDCOLOR} \n"

## Get API details from input file
cat $file | grep -q APIVIP
check $? "y" "Missing or wrong entry for API endpoint."

## Get APP details from input file
cat $file | grep -q INGRESSVIP
check $? "y" "Missing or wrong entry for Ingress endpoint."

## Get bootstrap VM details from input file
cat $file | grep -q KVM
check $? "y" "Missing or wrong entry for bootstrap vm."

## Get machine CIDR details from input file
cat $file | grep -q CIDR 
check $? "y" "Missing or wrong entry for machine CIDR."

## Get Nodes details from input file
eval nodecount=`cat $file | grep  RU | wc -l`
if [[ ${nodecount} < 6 ]];then
	echo -e "${RED}Error: Atleast 6 nodes information must be provided for HCI network setup verification. ${ENDCOLOR} \n\n"
	exit 1
fi

# Perform DNS validation for each node, VIP, bootstrap one by one (try both DNS servers if more than one DNS servers are available on network)
verifydns $file $dnsServers

## Perform DHCP validation for each node and bootstrap
## DHCP is verified only when expliclty specified as argument to this utility
if [ "$VERIFYDHCP" == "y" ] ; then
	verifydhcp $file
fi

# Verify both VIPs are in same machine CIDR as OCP nodes
verifycidr $file

# ping test - IPs should not live on the network as rack is not installed yet
verifyipsnotinuse $file