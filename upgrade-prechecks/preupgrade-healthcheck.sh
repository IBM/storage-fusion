#!/bin/bash 

##############################################################################
#Script Name	: preupgrade_healthcheck.sh                                             
#Description	: Utility to run healthcheck for IBM Storage Fusion HCI system                                                      
#Args       	:                                                                                           
#Author       	:Anshu Garg     
#Email         	:ganshug@gmail.com                                           
##############################################################################

##############################################################################
# This utility will run a healthcheck on IBM Storage Fusion HCI system
# Execute it from a bash shell where you have logged into HCI OpenShift API
# It checks:
# API accessibility
# machine config pool
# nodes status
# cluster operators
# catalog sources
# Fusion operators
# services health
##############################################################################

CHECK_PASS='  ✅'
CHECK_FAIL='  ❌'
CHECK_UNKNOW='  ⏳'
PADDING_1='   '
PADDING_2='      '
REPORT=$(pwd)/preupgrade_healthcheck_report.log
TEMP_MMHEALTH_FILE=$(pwd)/tmp_health.log

#exec >>(tee ${REPORT}) 2>&1

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
    echo "			$1"
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

# Verify Red Hat OpenShift cluster operators health
function verify_clusteroperators_status () {
	print info "Verify Red Hat OpenShift cluster operators health."
	notavailablecocount=$(oc get co)
        unhealthy=0
        rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
        while read -r proc; do echo $proc >> ${TEMP_MMHEALTH_FILE}; done <<< "$(oc get co|grep -v NAME)"
        while IFS= read -r line
        do
                comp=$(echo $line|awk '{print $1}')
                available=$(echo $line|awk '{print $3}')	# Possible values True|False
                progressing=$(echo $line|awk '{print $4}')	# Possible values True|False
                degraded=$(echo $line|awk '{print $5}')		# Possible values True|False
                if [[ "${available}" == False || "${progressing}" == True || "${degraded}" == True ]]
		then
                        print error "${CHECK_FAIL} ${failed} Cluster operator $comp is not healthy or/and ready."
			print error "${CHECK_FAIL} $line"
                        unhealthy=1
                fi
        done <<< $(cat "${TEMP_MMHEALTH_FILE}")
        if [ $unhealthy  -eq 0 ]; then
                print info "${CHECK_PASS} All Red Hat OpenShift cluster operators are healthy."
        fi
        rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
}

# Verify Red Hat OpenShift nodes status
function verify_nodes_status() {
	print info "Verify Red Hat OpenShift nodes status."
	notreadynodescount=$(oc get nodes|egrep -i 'NotReady|Scheduling'|wc -l)
	if [ "${notreadynodescount}" -ne 0 ]; then
		print error "${CHECK_FAIL} Following nodes are not Ready."
		oc get nodes|egrep -i 'NotReady|Scheduling'
		print error "${CHECK_FAIL} All Red Hat OpenShift nodes are not Ready."
	else
		print info "${CHECK_PASS} All Red Hat OpenShift nodes are Ready."
        fi

}

# Verify no ongoing updates on nodes as part of mco
function verify_mcp() {
	print info "Verify machine config pools are updated."
	#NAME     CONFIG   UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT
	inprogress=0
	degraded=0
	notready=0
	notupdated=0
	winprogress=0
	wdegraded=0
	wnotready=0
	wnotupdated=0
	computemcp=$(oc get mcp worker|grep -v READYMACHINECOUNT)
	controlmcp=$(oc get mcp master|grep -v READYMACHINECOUNT)
	computecount=$(oc get nodes |grep compute|wc -l)
	controlcount=$(oc get nodes |grep control|wc -l)
	degcompute=$(echo $computemcp|awk '{print $5}')
	readycompute=$(echo $computemcp|awk '{print $7}')
	updatedcompute=$(echo $computemcp|awk '{print $8}')
	inprogresscompute=$(echo $computemcp|awk '{print $4}')
	degcontrol=$(echo $controlmcp|awk '{print $5}')
	inprogresscontrol=$(echo $controlmcp|awk '{print $4}')
	readycontrol=$(echo $controlmcp|awk '{print $7}')
	updatedcontrol=$(echo $controlmcp|awk '{print $8}')
	if [[ $degcompute -ne 0 ]]; then
		print error "${CHECK_FAIL}  $degcompute compute nodes are degraded."
		wdegraded=1
	fi
	if [[ $inprogresscompute -ne 0 ]]; then
		print error "${CHECK_UNKNOW}  $inprogresscompute compute nodes are updating."
		winprogress=1
	fi
	if [[ $readycompute -ne $computecount ]]; then
		print error "${CHECK_FAIL}  $readycompute compute nodes are not ready."
		wnotready=1
	fi
	if [[ $updatedcompute -ne $computecount ]]; then
		print error "${CHECK_FAIL}  $updatedcompute compute nodes are not updated."
		wnotupdated=1
	fi
	if [[ $wnotupdated -eq 1 || $wnotready -eq 1 || $winprogress -eq 1 || $wdegraded -eq 1 ]]; then
		print error "${CHECK_FAIL} $(oc get nodes|grep compute)"
	fi	

	print_subsection	
	# Check control mcp
	if [[ $degcontrol -ne 0 ]]; then
		print error "${CHECK_FAIL}  $degcontrol control nodes are degraded."
		degraded=1
	fi
	if [[ $inprogresscontrol -ne 0 ]]; then
		print error "${CHECK_UNKNOW}  $inprogresscontrol control nodes are updating."
		inprogress=1
	fi
	if [[ $readycontrol -ne $controlcount ]]; then
		print error "${CHECK_FAIL}  $readycontrol control nodes are not ready."
		notready=1
	fi
	if [[ $updatedcontrol -ne $controlcount ]]; then
		print error "${CHECK_FAIL}  $updatedcontrol control nodes are not updated."
		notupdated=1
	fi
	if [[ $notupdated -eq 1 || $notready -eq 1 || $inprogress -eq 1 || $degraded -eq 1 ]]; then
		print error "${CHECK_FAIL} $(oc get nodes|grep control)"
	fi	
	if [[ $notready -eq 0 && $inprogress -eq 0 && $degraded -eq 0 && $notupdated -eq 0 && $wnotupdated -eq 0 && $wnotready -eq 0 && $winprogress -eq 0 && $wdegraded -eq 0 ]]; then
		print info "${CHECK_PASS} All machine configuration pools are upto date."
	fi
}

# Verify catalogsources
# Failed catalog impact any and every operator install in cluster so all catalaog sources including customer's own catalogsources must be healthy
function verify_catsrc() {
	print info "Verify catalog sources health in cluster."
        unhealthy=0
	# oc get catsrc -A
	#NAMESPACE               NAME                                	 	
	rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
        while read -r proc; do echo $proc >> ${TEMP_MMHEALTH_FILE}; done <<< "$(oc get catsrc -A |grep -v NAME)"
        while IFS= read -r line
        do
                name=$(echo $line|awk '{print $2}')
                ns=$(echo $line|awk '{print $1}')
                state=$(oc get catsrc $name -n $ns -o yaml|grep lastObservedState |grep -v "f:"|awk '{print $2}')
                if [[ "$state" != "READY" ]]; then
                        print error "${CHECK_FAIL} catalog source ${name} in namespace $ns is not ready."
                        unhealthy=1
                fi
        done <<< $(cat "${TEMP_MMHEALTH_FILE}")
	if [[ ${unhealthy} -eq 0 ]]; then
		print info "${CHECK_PASS} All catalog sources are ready."
	fi
}

# Verify status of Scale daemon pods
function verify_scale_daemon_pods_status() {
        print info "Verify IBM Storage Scale daemon pods status."
	fail=0
        running=$(oc get daemons ibm-spectrum-scale -n ibm-spectrum-scale -ojson | jq -r '.status.podsStatus'|grep running| awk '{print $2}'|cut -d '"' -f 2)
        terminating=$(oc get daemons ibm-spectrum-scale -n ibm-spectrum-scale -ojson | jq -r '.status.podsStatus'|grep terminating| awk '{print $2}'|cut -d '"' -f 2)
        starting=$(oc get daemons ibm-spectrum-scale -n ibm-spectrum-scale -ojson | jq -r '.status.podsStatus'|grep starting| awk '{print $2}'|cut -d '"' -f 2)
        waitingForDelete=$(oc get daemons ibm-spectrum-scale -n ibm-spectrum-scale -ojson | jq -r '.status.podsStatus'|grep waitingForDelete| awk '{print $2}'|cut -d '"' -f 2)
        unknown=$(oc get daemons ibm-spectrum-scale -n ibm-spectrum-scale -ojson | jq -r '.status.podsStatus'|grep unknown| awk '{print $2}'|cut -d '"' -f 2)
        if [ "${terminating}" -ne 0 ]; then
                print error "${CHECK_FAIL} ${terminating} daemons are in terminating state."
		fail=1
        fi
        if [ "${starting}" -ne 0 ]; then
                print error "${CHECK_UNKNOW} ${starting} daemons are in starting state."
		fail=1
        fi
        if [ "${waitingForDelete}" -ne 0 ]; then
                print error "${CHECK_FAIL} ${waitingForDelete} daemons are in waitingForDelete state."
		fail=1
        fi
        if [ "${unknown}" -ne 0 ]; then
                print error "${CHECK_FAIL} ${unknown} daemons are in unknown state."
		fail=1
        fi
	if [ $fail -eq 0 ]; then
                print info "${CHECK_PASS} All of IBM Storage Scale daemon pods are healthy."
        fi
}

# Get Scale health summary
function verify_mmhealth_summary() {
	print info "Verify IBM Storage Scale health"
	unhealthy=0
	rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
	nodename=$(oc get nodes |grep 'control'|grep 'Ready'|head -1|awk '{print $1}'|cut -d"." -f 1)
	while read -r proc; do echo $proc >> ${TEMP_MMHEALTH_FILE}; done <<< "$(oc -n ibm-spectrum-scale rsh $nodename mmhealth cluster show|egrep 'NODE|GPFS|NETWORK|FILESYSTEM|DISK|FILESYSMGR|GUI|NATIVE_RAID|PERFMON|THRESHOLD')"
	while IFS= read -r line 
	do 
		comp=$(echo $line|awk '{print $1}')
		failed=$(echo $line|awk '{print $3}')
		degraded=$(echo $line|awk '{print $4}')
		if [ ${failed} -ne 0 ]; then
			print error "${CHECK_FAIL} ${failed} failed $comp found."
			unhealthy=1
		fi
		if [ ${degraded} -ne 0 ]; then
                        print error "${CHECK_FAIL} ${degraded} degraded $comp found."
			unhealthy=1
		fi
	done <<< $(cat "${TEMP_MMHEALTH_FILE}")	
	if [ $unhealthy  -eq 0 ]; then
		print info "${CHECK_PASS} All of IBM Storage Scale components are healthy."
	else
		print error "${CHECK_FAIL} health summary:"
		oc -n ibm-spectrum-scale rsh $nodename mmhealth cluster show
	fi
	rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
}

# Get Scale detailed status
function verify_mmhealth_details() {
        print info "Verify IBM Storage Scale health"
        unhealthy=0
        rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
        while read -r proc; do echo $proc >> ${TEMP_MMHEALTH_FILE}; done <<< "$(oc rsh control-1-ru2 mmhealth node show -N all)"
        while IFS= read -r line
        do
                comp=$(echo $line|awk '{print $1}')
                failed=$(echo $line|awk '{print $3}')
                degraded=$(echo $line|awk '{print $4}')
                if [ ${failed} -ne 0 ]; then
                        print error "${CHECK_FAIL} ${failed} failed $comp found."
                        unhealthy=1
                fi
                if [ ${degraded} -ne 0 ]; then
                        print error "${CHECK_FAIL} ${degraded} degraded $comp found."
                        unhealthy=1
                fi
        done <<< $(cat "${TEMP_MMHEALTH_FILE}")
        if [ $unhealthy  -eq 0 ]; then
                print info "${CHECK_PASS} All of IBM Storage Scale components are healthy."
        else
                print error "${CHECK_FAIL} health summary:"
                oc rsh control-1-ru2 mmhealth cluster show
        fi
        rm -f ${TEMP_MMHEALTH_FILE} >> /dev/null
}

# Get Fusion operator health
function verify_fusion_health() {
	print info "Verify IBM Storage Fusion health."
	csvhealth=$(oc get csv -n ibm-spectrum-fusion-ns|grep isf-operator|grep Succeeded)
	if [ $? -ne 0 ]; then
		print error "${CHECK_FAIL} IBM Storage Fusion operator is not healthy."
		print error "${CHECK_FAIL} $(oc get csv -n ibm-spectrum-fusion-ns|grep isf-operator)"
	fi
}

# Get data protection operators health
function verify_br_health() {
	print info "Verify IBM Storage Fusion Data protection health."

	# check operators health
	unhealthy=0
	notsuccesscount=$(oc get csv -n ibm-backup-restore|egrep -v 'Succ|NAME'|wc -l)
	if [ ${notsuccesscount} -ne 0 ]; then
		print error "${CHECK_FAIL} ${notsuccesscount} operators for data protection are degraded."
	        unhealthy=1
		print error "${CHECK_FAIL} Here are failed operators. Use \"oc describe csv <csv name> -n ibm-backup-restore\" to get more details about failure."
		oc get csv -n ibm-backup-restore|egrep -v 'Succ|NAME'
        else 
		print info "${CHECK_PASS} All operators for data protection are healthy."
	fi

	print_subsection
	# check pods health
	unhealthy=0
	notsuccesscount=$(oc get po -n ibm-backup-restore|egrep -v 'Running|Completed|NAME'|wc -l)
	if [ ${notsuccesscount} -ne 0 ]; then
		print error "${CHECK_FAIL} ${notsuccesscount} pods for data protection are not running."
	        unhealthy=1
		print error "${CHECK_FAIL} Here are failed pods:"
		oc get pods -n ibm-backup-restore|egrep -v 'Running|Completed|NAME'
        else 
		print info "${CHECK_PASS} All pods for data protection are healthy."
	fi

	print_subsection
        # check pvc health
	unhealthy=0
        notsuccesscount=$(oc get pvc -n ibm-backup-restore|egrep -v 'Bound|NAME'|wc -l)
        if [ ${notsuccesscount} -ne 0 ]; then
                print error "${CHECK_FAIL} ${notsuccesscount} PVCs for data protection are not bound."
                unhealthy=1
                print error "${CHECK_FAIL} List of unbound PVCs:"
                oc get pvc -n ibm-backup-restore|egrep -v 'Bound|NAME'
        else
                print info "${CHECK_PASS} All PVCs for data protection are bound."
        fi

}

rm -f ${REPORT} > /dev/null
print_header
verify_api_access
print_section "Cluster operators"
verify_clusteroperators_status
print_section "Nodes"
verify_nodes_status
print_section "Machine configuration pools"
verify_mcp
print_section "Catalog sources"
verify_catsrc 
print_section "Fusion software"
verify_fusion_health
print_section "Scale daemon pods"
verify_scale_daemon_pods_status
print_section "Backup & Restore"
verify_br_health
print_section "Scale cluster"
verify_mmhealth_summary
print_section 
#verify_mmhealth_details
print_footer
