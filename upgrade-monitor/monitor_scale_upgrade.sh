#!/bin/bash 

##############################################################################
#Script Name	: monitor_scale_upgrade.sh
#Description	: Utility to monitor Storage Scale upgrade for IBM Storage Fusion HCI system                                                      
#Args       	:                                                                                           
#Author       	:Anshu Garg, Anvesh Thangallapalli     
#Email         	:ganshug@gmail.com, thangallapallianvesh625@gmail.com                                          
##############################################################################

##############################################################################
# This utility will monitor Storage Scale upgrade on IBM Storage Fusion HCI system
# Execute it from a bash shell where you have logged into HCI OpenShift API
# Ensure jq is installed on that system
##############################################################################

CHECK_PASS='  ✅'
CHECK_FAIL='  ❌'
CHECK_UNKNOW='  ⏳'
CHECK_INPROGRESS=' 🕦'
CHECK_TERMINATING=' 🚫'
PADDING_1='   '
PADDING_2='      '
REPORT=$(pwd)/monitor_scale_upgrade.log
TEMP_MMHEALTH_FILE=$(pwd)/tmp-monitoring.log

SCALENS="ibm-spectrum-scale"
DAEMONNAME="ibm-spectrum-scale"

function print_header() {
    echo "======================================================================================"
    echo "Started healthcheck for IBM Storage Fusion HCI cluster at $(date +'%F %z %r')"
    echo "======================================================================================"
}

function print_footer() {
    echo ""
    echo "========================================================================================"
    echo "Healthcheck for IBM Storage Fusion HCI cluster completed at $(date +'%F %z %r')"
    echo "========================================================================================"
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
	oc get clusterversion
	if [ $? -ne 0 ]; then
        	print error "${CHECK_FAIL} Red Hat OpenShift API is inaccessible."	
        else
        	print info "${CHECK_PASS} Red Hat OpenShift API is accessible."	
	fi
}

# Get Scale configuration in terms of nodes and pods
# Sample output: Nodes/Pods
#        "name": "storage",
#        "nodeCount": "6",
#        "nodes": "compute-1-ru5.rackm05.rtp.raleigh.ibm.com, compute-1-ru6.rackm05.rtp.raleigh.ibm.com, compute-1-ru7.rackm05.rtp.raleigh.ibm.com, control-1-ru2.rackm05.rtp.raleigh.ibm.com, control-1-ru3.rackm05.rtp.raleigh.ibm.com, control-1-ru4.rackm05....",
#        "podCount": "6",
#        "pods": "compute-1-ru5, compute-1-ru6, compute-1-ru7, control-1-ru2, control-1-ru3, control-1-ru4",
#        "runningCount": "5"
function scale_config () {
	nodeCount=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq '.status.roles[0].nodeCount')
	nodes=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq '.status.roles[0].nodes')
	podCount=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq '.status.roles[0].podCount')
	pods=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq '.status.roles[0].pods')
	echo "${CHECK_PASS} Cluster has $nodeCount storage nodes: $nodes"
	print_subsection
	echo "${CHECK_PASS} Cluster has $podCount core pods: $pods"
}

# Monitor upgrade progress via Scale daemon
# Sample output: Node/Pod status
#    "statusDetails": {
#      "nodesRebooting": "control-1-ru2.rackm05.rtp.raleigh.ibm.com",
#      "nodesUnreachable": "",
#      "nodesWaitingForReboot": "compute-1-ru5.rackm05.rtp.raleigh.ibm.com, control-1-ru3.rackm05.rtp.raleigh.ibm.com",
#      "podsStarting": "",
#      "podsTerminating": "control-1-ru2",
#      "podsUnknown": "",
#      "podsWaitingForDelete": "compute-1-ru5, control-1-ru3",
#      "quorumPods": "control-1-ru2, control-1-ru3, control-1-ru4"
#    },

# Sample output: initial and tareget version
#    "versions": [
#      {
#        "count": "3",
#        "version": "5.1.7.0"
#      },
#      {
#        "count": "3",
#        "version": "5.1.9.0"
#      }
#    ]

function check_upgrade_scheduled_nodes () {
    nodes=$1

    echo $nodes
    nodes=$nodes | tr -d '"'
    echo $nodes
    nodes=$(sed -e 's/^"//' -e 's/"$//' <<<"$nodes")
    echo $nodes
    IFS=', ' read -r -a nodesArr <<< "$nodes"
    for element in "${nodesArr[@]}"
    do
        echo $CHECK_UNKNOW $"$element" node is waiting \for reboot
    done
    echo Length of array ${#nodesArr[@]}
}

function monitor_scale_progress () {
	oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails'
	daemon_output=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.quorumPods')
    echo Daemon: ${daemon_output[@]}
    echo Daemon2: control-1-ru2, control-1-ru3, control-1-ru4
    for element in "${daemon_output[@]}"
        do
            echo element: "$element"
        done
    oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.versions'
	# check_upgrade_scheduled_nodes $daemon_output 
    check_upgrade_scheduled_nodes "${daemon_output[@]}"
	# check_upgrade_scheduled_nodes "control-1-ru2, control-1-ru3, control-1-ru4"
	# QP=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.quorumPods')
    # print_section "QP"
    # echo $QP
    # echo ${QP:0:5}
    # echo $QP | tr -d '"'
    # QPR=$QP | tr -d '"'

    # # Remove quotations
    # output=$(sed -e 's/^"//' -e 's/"$//' <<<"$QP")
    # echo output: $output
    # IFS=', ' read -r -a out_array <<< "$output"
    # # echo $array
    # for element in "${out_array[@]}"
    # do
    #     echo "$element"
    # done
    # echo Length of array ${#out_array[@]}
    # echo $QP
}

function monitor_scale_progress_table () {
    echo "Fetching details..."
    s_no=0
    s_no2=0
    cv=$(oc get clusterversion)
    daemon=$(oc get daemon $DAEMONNAME -n $SCALENS -o json)
    scale_version=`oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.versions[0].version'`
    rolecount=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq -r '.status.roles | length')
    node_rebooting_details=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.nodesRebooting')
    node_unreachable_details=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.nodesUnreachable')
    node_waiting_for_reboot_details=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.nodesWaitingForReboot')
    pods_starting_details=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.podsStarting')
    pods_terminating_details=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.podsTerminating')
    pods_unknown_details=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.podsUnknown')
    pods_waiting_for_delete_details=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.podsWaitingForDelete')
    quorum_pods_details=$(oc get daemon $DAEMONNAME -n $SCALENS -o json | jq  '.status.statusDetails.quorumPods')
    echo "$cv" >> table.txt
    echo "SCALE_VERSION: $scale_version" >> table.txt
    cat table.txt
    rm table.txt
    echo ""
    for ((j=0; j<rolecount; j++))
    do
        s_no=0
        nodeCount=$(jq -r --argjson j "$j" '.status.roles[$j].nodeCount' <<< "$daemon" | awk '{print int($1)}')
        role=$(jq -r --argjson j "$j" '.status.roles[$j] | .name' <<< "$daemon")
        node_names=($(oc get nodes --selector="scale.spectrum.ibm.com/role=$role" --output=jsonpath='{.items[*].metadata.name}' | tr -d '\n'))
        podCount=$(jq -r --argjson j "$j" '.status.roles[$j].podCount' <<< "$daemon" | awk '{print int($1)}')
        echo "S_NO $(tr '[:lower:]' '[:upper:]' <<< "$role")_NODE IS_REBOOTING IS_REACHABLE IS_WAITING_FOR_REBOOT" >> table2.txt
        for ((i=0; i<nodeCount; i++))
        do
            s_no=$(($s_no+1))
            storage_node="${node_names[i]}"
            if echo "$node_rebooting_details" | grep -q "$storage_node"
            then
                node_rebooting="${CHECK_INPROGRESS}"
            else
                node_rebooting="-"
            fi
            if echo "$node_unreachable_details" | grep -q "$storage_node"
            then
                node_unreachable="${CHECK_PASS}"
            else
                node_unreachable="${CHECK_FAIL}"
            fi
            if echo "$node_waiting_for_reboot_details" | grep -q "$storage_node"
            then
                node_waiting_for_reboot="${CHECK_UNKNOW}"
            else
                node_waiting_for_reboot="-"
            fi
            echo "$s_no $storage_node $node_rebooting $node_unreachable $node_waiting_for_reboot" >> table2.txt
        done
        cat table2.txt | column -t
        echo ""
        rm table2.txt
        s_no2=0
        echo "S_NO $(tr '[:lower:]' '[:upper:]' <<< "$role")_POD IS_STARTING IS_TERMINATING IS_UNKNOWN IS_WAITING_FOR_DELETE IS_QUORUM_PODS" >> table3.txt
        for ((i=0; i<podCount; i++))
        do
            s_no2=$(($s_no2+1))
            core_pod=$(jq -r --argjson key "$i" --argjson j "$j" '.status.roles[$j].pods | split(",") | .[$key]' <<< "$daemon" | sed 's/^[[:space:]]*//')
            if echo "$pods_starting_details" | grep -q "$core_pod"
            then
                pods_starting="${CHECK_INPROGRESS}"
            else
                pods_starting="-"
            fi
            if echo "$pods_terminating_details" | grep -q "$core_pod"
            then
                pods_terminating="${CHECK_TERMINATING}"
            else
                pods_terminating="-"
            fi
            if echo "$pods_unknown_details" | grep -q "$core_pod"
            then
                pods_unknown="?"
            else
                pods_unknown="-"
            fi
            if echo "$pods_waiting_for_delete_details" | grep -q "$core_pod"
            then
                pods_waiting_for_delete="${CHECK_UNKNOW}"
            else
                pods_waiting_for_delete="-"
            fi
            if echo "$quorum_pods_details" | grep -q "$core_pod"
            then
                quorum_pods="${CHECK_PASS}"
            else
                quorum_pods="-"
            fi
            echo "$s_no2 $core_pod $pods_starting $pods_terminating $pods_unknown $pods_waiting_for_delete $quorum_pods" >> table3.txt
        done
        cat table3.txt | column -t
        echo "-----------------------------------------------------------------------------------------------------"
        rm table3.txt
    done    
}

function pods_blocking_drains() {
oc -n openshift-machine-config-operator logs machine-config-controller-7997756fc7-8s58l  machine-config-controller -f  | grep "error when evicting pods"
}

# rm -f ${REPORT} > /dev/null
# print_header
# print_section "API access"
# verify_api_access
# print_section "Scale configuration"
# scale_config
# print_section "Begin Storage Scale upgrade status"
# monitor_scale_progress
# print_footer
monitor_scale_progress_table
# pods_blocking_drains
