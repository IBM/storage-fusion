#!/usr/bin/env bash
# start_Copyright_Notice
# Licensed Materials - Property of IBM

# IBM Spectrum Fusion 5900-AOY
# (C) Copyright IBM Corp. 2022 All Rights Reserved.

# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

###############################################################
### Global Envrionment Variables

set -u

TIMEOUT=600

# Colorful constants
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
NORMAL='\033[0m'

# Message labels
INFO="$(echo -e $GREEN"I"$NORMAL)"
WARNING="$(echo -e $YELLOW"W"$NORMAL)"
ERROR="$(echo -e $RED"E"$NORMAL)"

# OCP cluster configuration
OCP_SERVER=
OCP_USER=
OCP_PASSWORD=

# Fusion/CNS NameSpace
FUSION_NAMESPACE=

# Fusion's SNC filesystem array
SNC_FS=()
PV_List=()

###############################################################

info() {
	printf "$(date +"%T") [$INFO] %s\n" "$1"
}

warn() {
	printf "$(date +"%T") [$WARNING] %s\n" "$1"
}

error() {
	printf "$(date +"%T") [$ERROR] %s\n" "$1"
}

check_oc() {
	result=$(which oc)
	if [[ $? -eq 1 ]]; then
		error "There is no oc command"
		exit
	else
		info "Find oc command"
	fi
}

check_connection() {
	result=$(oc get node)
	if [[ $? -eq 1 ]]; then
		error "Connect to ocp error"
		exit
	else
		info "OCP connection is good"
	fi
}

show_ocp_server() {
	addr=$(oc whoami --show-server)
	info "OCP API url is $addr"
}

check_version() {
	VERSION=$(oc version | grep Server | awk '{print $3}')
	if [[ $VERSION =~ 4.10 ]]; then
		info "OCP version is $VERSION, meets requirement"
	else
		error "OCP version is $VERSION, require 4.10"
	fi
}

check_platform() {
	cluster=$(oc get infrastructure cluster -o yaml)
	echo "$cluster" | grep "VSphere" >/dev/null
	if [[ $? -eq 0 ]]; then
		info "this is supported platform: VSphere"
		return
	fi
	echo "$cluster" | grep "rosa" >/dev/null
	if [[ $? -eq 0 ]]; then
		info "this is supported platform: rosa"
		return
	fi
	error "this is not vsphere or rosa, not supported"
}

check_mc() {
	oc get mc 00-worker-ibm-spectrum-scale-kernel-devel &>/dev/null
	if [[ $? -eq 0 ]]; then
		info "scale MachineConfig is found"
	else
		error "there is no scale MachineConfig"
	fi

	oc get ContainerRuntimeConfig 01-worker-ibm-spectrum-scale-increase-pid-limit &>/dev/null
	if [[ $? -eq 0 ]]; then
		info "scale ContainerRuntimeConfig is found"
	else
		error "there is no scale ContainerRuntimeConfig"
	fi
}

check_mcp() {
	mcp_status=$(oc get mcp | grep worker | awk '{print $3}')
	if [[ $mcp_status != "True" ]]; then
		warn "mcp worker status updated is not True"
	else
		info "mcp worker status updated is True"
	fi
}

check_nodes() {
	worker_num=$(oc get node | grep -c worker)
	worker_l_num=$(oc get node --show-labels | grep worker | grep topology.kubernetes.io/region | grep -c topology.kubernetes.io/zone)
	storage_num=$(oc get node --show-labels | grep worker | grep -c "${SCALE_ROLE_LABEL}=${SCALE_ROLE_STORAGE}")

	info "worker node number: $worker_num"
	if [[ worker_num -lt 3 ]]; then
		error "worker node number is less than 3, not supported"
	fi

	info "worker node number with topology labels: $worker_l_num"
	worker_num=$(oc get node | grep -c worker)
	if [[ worker_l_num -ne $worker_num ]]; then
		warn "worker nodes do not all have topology labels"
	fi

	info "storage node number: $storage_num"
	if [[ $storage_num -gt 0 && $((storage_num % 3)) -eq 0 ]]; then
		info "storage node number meets requirement"
	else
		error "storage node number does not meet requirement"
	fi
}

check_pullsecret() {
	secret=$(oc get secret pull-secret -n openshift-config --template='{{index .data ".dockerconfigjson" | base64decode}}')
	echo "$secret" | grep icr.io >/dev/null
	if [[ $? -eq 0 ]]; then
		info "pull secret is found for icr.io"
	else
		warn "pull secret is not set for icr.io"
	fi

	echo "$secret" | grep artifactory.swg-devops.com >/dev/null
	if [[ $? -eq 0 ]]; then
		info "pull secret is found for artifactory.swg-devops.com"
	else
		warn "pull secret is not set for artifactory.swg-devops.com"
	fi
}

check_isf_cns_operator() {
	result=$(oc get deploy -A | grep -c isf-cns-operator-controller-manager)
	if [[ $result -gt 1 ]]; then
		error "isf-cns-operator deployment is found to have multiple instances"
		return
	elif [[ $result -eq 0 ]]; then
		error "isf-cns-operator deployment is not found"
		return
	fi

	result=$(oc get pod -A | grep isf-cns-operator-controller-manager | awk '{print $4}')
	if [[ "${result}" == "Running" ]]; then
		info "isf-cns controller manager status is ${result}"
	else
		error "isf-cns controller manager status is ${result}"
	fi
}

check_scale_ns() {
	scale_ns_num=$(oc get ns | grep -c ibm-spectrum-scale)
	if [[ scale_ns_num -eq 4 ]]; then
		info "scale namespaces are created"
	else
		error "scale namespace number is $scale_ns_num, less than expected"
	fi
}

check_scale_ns_deleted() {
	scale_ns_num=$(oc get ns | grep -c ibm-spectrum-scale)
	if [[ scale_ns_num -eq 0 ]]; then
		info "scale namespaces not exist"
	else
		error "still have $scale_ns_num scale namespaces, the env is not clean."
	fi
}

check_scale_operator() {
	result=$(oc get pod -n ibm-spectrum-scale-operator --no-headers | grep ibm-spectrum-scale-controller-manager | awk '{print $3}')
	if [[ $result == "" ]]; then
		error "can not find ibm-spectrum-scale-controller-manager pod"
	elif [[ "${result}" == "Running" ]]; then
		info "scale controller manager status is ${result}"
	else
		error "scale controller manager status is ${result}"
	fi
}

check_scale_csi() {
	result=$(oc get pod -n ibm-spectrum-scale-csi --no-headers)
	if [[ $result == "" ]]; then
		error "can not find scale csi pods"
		return
	fi
	pod_num=$(echo "$result" | grep -c csi)
	running_num=$(echo "$result" | awk '{print $3}' | grep -c Running)
	if [[ pod_num -eq running_num ]]; then
		info "csi pods are all in Running status"
	else
		error "csi pods are not all in Running status"
	fi
}

check_scale_core() {
	result=$(oc get pod -n ibm-spectrum-scale -l app.kubernetes.io/name=core --no-headers)
	if [[ $result == "" ]]; then
		error "can not find scale core pod"
		return
	fi
	result1=$(echo "$result" | wc -l | tr -d ' ')
	info "scale core pod number: $result1"
	result2=$(oc get node | grep -c worker)
	result3=$(echo "$result" | grep -c Running)
	info "scale core pod number in Running status: $result3"
	if [[ $result1 -ne $result2 ]]; then
		error "scale core pod number is fewer than expected"
	fi
	if [[ $result1 -ne $result3 ]]; then
		error "scale core pods are not all in Running status"
	fi
}

check_sncnode() {
	result=$(oc get sncnode ibm-spectrum-fusion-sncnode --no-headers)
	if [[ $result == "" ]]; then
		error "can not find sncnode CR"
		return
	fi
	sncnode_status=$(echo "$result" | awk '{print $2}')
	if [[ $sncnode_status != "completed" ]]; then
		error "sncnode CR status is not completed"
	else
		info "sncnode CR status is completed"
	fi
}

check_ld() {
	result=$(oc get ld -n ibm-spectrum-scale --no-headers)
	if [[ $result == "" ]]; then
		error "can not find scale local disks"
		return
	fi
	ld_num=$(echo "$result" | grep -c pvc)
	ready_num=$(echo "$result" | awk '{print $4}' | grep -c True)
	if [[ ld_num -ne ready_num ]]; then
		error "local disks are not all in ready state"
		return
	fi

	used_num=$(echo "$result" | awk '{print $5}' | grep -c True)
	if [[ ld_num -ne used_num ]]; then
		error "local disks are not all in used state"
		return
	fi

	avail_num=$(echo "$result" | awk '{print $6}' | grep -c True)
	if [[ ld_num -ne avail_num ]]; then
		error "local disks are not all in available state"
		return
	fi

	info "local disks status is good"
}

check_fs() {
	result=$(oc get fs -n ibm-spectrum-scale --no-headers | awk '{print $2}')
	if [[ $result == "" ]]; then
		error "can not find scale filesystem"
		return
	fi
	if [[ $result != "True" ]]; then
		error "scale filesystem is not ready"
	else
		info "scale filesystem is ready"
	fi
}

login_ocp() {
	if [[ $OCP_SERVER == "" ]]; then
		info "No cluster URL is specified, check the default credential connections"
		name=$(oc whoami 2>/dev/null)
		if [[ $? -eq 0 ]]; then
			info "Logged into OCP cluster with local credential, need double confirm"
			cluster_api=$(oc whoami --show-server 2>/dev/null)
			read -p "$(date +"%T") [$WARNING] Execute scripts in OCP cluster: $cluster_api, confirm? [Y/y]: " choice
			if [[ $choice != "Y" && $choice != "y" ]]; then
				info "Exited..."
				exit 1
			fi
			return
		else
			error "Login OCP cluster $OCP_SERVER error, please verify the cluster URL, username, and password"
			exit 1
		fi
	fi

	result=$(oc login $OCP_SERVER --username $OCP_USER --password $OCP_PASSWORD --insecure-skip-tls-verify=true)
	if [[ $? -eq 1 ]]; then
		error "Login OCP cluster failed, please verify the cluster URL, username, and password"
		exit 1
	else
		info "Login OCP cluster $OCP_SERVER successfully"
	fi
}

get_snc_fs() {
	result=$(oc get fsf -n $FUSION_NAMESPACE --no-headers 2>/dev/null | awk '{print $1}')
	if [[ $result == "" ]]; then
		warn "Fusion doesn't have filesystem in $FUSION_NAMESPACE namespace"
	else
		SNC_FS=(${result// /})
		info "Fusion has ${#SNC_FS[*]} filesystem(s) ${SNC_FS[@]}"
		# echo ${#SNC_FS[*]}
	fi
}

delete_fs() {
	if [[ $# == 0 ]]; then
		error "delete_fs function usage ERROR, missing parameter SNC or SCALE"
		exit 1
	elif [[ $1 != "SNC" && $1 != "SCALE" ]]; then
		error "delete_fs function usage ERROR, parameter supports SNC or SCALE only"
		exit 1
	else
		local fs_count=${#SNC_FS[*]}
		# echo $fs_count

		if [[ $1 == "SNC" ]]; then
			ns=$FUSION_NAMESPACE
			fstype="fsf"
			labeltype="fusion.spectrum.ibm.com/allowDelete="
		elif [[ $1 == "SCALE" ]]; then
			ns="ibm-spectrum-scale"
			fstype="fs"
			labeltype="scale.spectrum.ibm.com/allowDelete="
		fi

		if [[ $fs_count -eq 0 ]]; then
			info "There is no filesystem need to be deleted"
		else
			for fs in ${SNC_FS[@]}; do
				# Check whether the delete label exist already, if no, label it first
				result=$(oc get $fstype $fs -n $ns --show-labels 2>/dev/null | grep $labeltype | awk '{print $1}')

				# Start to label the filesystem as deleted
				if [[ $? == 0 && $result == "" ]]; then
					result=$(oc label $fstype $fs $labeltype -n $ns 2>/dev/null)

					if [[ $? -gt 0 ]]; then
						error "Label filesystem $fs ERROR, please whether it exists in $ns namespace"
						return
					else
						info "Label filesystem $fs as deleted, start to delete it next"
					fi
				fi

				info "Delete filesystem $fs may take for a while, please be patient ..."
				# Start delete this filesystem, normally this is a quick action
				# In some trouble case, if filesystem couldn't be deleted within 120s, then delete it using finalizer

				result=$(oc delete $fstype $fs -n $ns 2>/dev/null)
				result=$(oc wait --for=delete $fstype $fs -n $ns --timeout=10s 2>/dev/null)

				# Use finalizer to delete the filesystem if timeout is encountered
				if [[ $? == 1 ]]; then
					## start to finalizer
					result=$(oc patch $fstype $fs -n $ns --type=merge -p '{"metadata": {"finalizers":null}}' 2>/dev/null)

					if [ $? -gt 0 ]; then
						error "Patch finalizer to $1 $fs ERROR, it might be deleted, or there are something wrong in the environment"
						return
					else
						info "Filesystem $fs has been deleted using finalizer"
					fi

				elif [[ $? -gt 1 ]]; then
					error "Filesystem $fs couldn't be deleted, please whether it exists in $ns namespace"
					return
				else
					info "Filesystem $fs has been deleted"
				fi

			done
		fi
		info "Delete $1 filesystem operation complete"
	fi
}

delete_localdisk() {

	oc delete ld --all -n ibm-spectrum-scale >/dev/null 2>&1 &

	waittime=0
	until [[ $waittime == 120 ]]; do
		result=$(oc wait --for=delete ld --all -n ibm-spectrum-scale --timeout=60s 2>/dev/null)

		if [[ $? -gt 0 ]]; then
			info "Local disks are under deleting, wait for 1 more minute ..."
		elif [[ $? == 0 ]]; then
			info "Delete local disks operation complete"
			return
		fi
		waittime=$((waittime + 60))

	done

	# local disk are not fully deleted within 10 minutes, start to delete them using finalizer
	result=$(oc get ld -n ibm-spectrum-scale --no-headers 2>/dev/null | awk '{print $1}' 2>/dev/null)
	if [[ $result == "" ]]; then
		info "Delete local disks operation complete"
		return
	else
		ld_list=(${result// /})

		info "Local disks are not cleaned up within expected 10 mins. There are ${#ld_list[*]} left, start to use finalizer approach to delete them"
		for ldisk in ${ld_list[@]}; do
			result=$(oc patch ld $ldisk -n ibm-spectrum-scale --type=merge -p '{"metadata": {"finalizers":null}}' 2>/dev/null)

			if [ $? -gt 0 ]; then
				error "Patch finalizer to local disk $ldisk ERROR, it might be deleted, or there are something wrong in the environment"
				return
			fi
			info "Local disk $ldisk has been deleted"
		done
	fi
	info "Delete local disks operation complete"
}

delete_fs_volume() {
	if [[ $# == 0 ]]; then
		error "delete_fs_volume function usage ERROR, missing parameter PVC or PV"
		exit 1
	elif [[ $1 != "PVC" && $1 != "PV" ]]; then
		error "delete_fs_volume function usage ERROR, parameter supports PVC or PV only"
		exit 1
	else
		# Delete all PVCs and PVs operation takes some time about a few minuteslaunch it in backend deamon
		if [[ $1 == "PVC" ]]; then
			# gain original PVC list, save it in PV_List for future PV deletion and verfication purpose
			result=$(oc get pvc -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core -o json -n ibm-spectrum-scale | jq -j '.items[] | "\(.spec.volumeName)\n"' 2>/dev/null)
			if [[ $? -gt 0 || $result == "" ]]; then
				info "All $1 have been deleted"
			else
				PV_List=(${result// /})
			fi

			oc delete pvc -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core -n ibm-spectrum-scale >/dev/null 2>&1 &
		elif [[ $1 == "PV" ]]; then
			oc delete pv -n ibm-spectrum-scale $(echo ${PV_List[*]}) >/dev/null 2>&1 &
		fi

		# Check the remaing pvc or pv, wait another 1 minutes if there are some left
		waittime=0
		sleepinterval=60

		until [[ $waittime == $TIMEOUT ]]; do
			if [[ $1 == "PVC" ]]; then
				result=$(oc get pvc -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core -n ibm-spectrum-scale --no-headers 2>/dev/null | awk '{print $1}' 2>/dev/null)
			elif [[ $1 == "PV" ]]; then
				result=$(oc get pv ${PV_List[*]} -n ibm-spectrum-scale --no-headers 2>/dev/null | awk '{print $1}' 2>/dev/null)
			fi

			if [[ $? -gt 0 ]]; then
				error "Get $1 ERROR, this script may have something wrong, please contact script owner"
				return
			elif [[ $result == "" ]]; then
				info "All $1 have been deleted"
				return
			else
				volumns=(${result// /})
				info "There are ${#volumns[*]} $1 need to be deleted, wait for 1 more minute ..."
			fi

			$(sleep ${sleepinterval})
			waittime=$((waittime + sleepinterval))
		done

		info "$1 are not cleaned up within expected 10 mins. There are ${#volumns[*]} left, start to use finalizer approach to delete them. The volumes in backend datastore may not be deleted, this needs to be checked manually"
		for vol in ${volumns[@]}; do
			if [[ $1 == "PVC" ]]; then
				result=$(oc patch pvc $vol -n ibm-spectrum-scale --type=merge -p '{"metadata": {"finalizers":null}}' 2>/dev/null)
			elif [[ $1 == "PV" ]]; then
				result=$(oc patch pv $vol -n ibm-spectrum-scale --type=merge -p '{"metadata": {"finalizers":null}}' 2>/dev/null)
			fi

			if [ $? -gt 0 ]; then
				error "Patch finalizer to $1 $vol ERROR, it might be deleted, or there are something wrong in the environment"
				return
			fi

			info "$1 $vol has been deleted"
		done

		info "Delete $1 operation complete"
	fi
}

delete_scale_csi_cr() {

	result=$(oc -n ibm-spectrum-scale-csi get csiscaleoperators/ibm-spectrum-scale-csi 2>/dev/null)
	if [[ $? -gt 0 || result == "" ]]; then
		info "Scale CSI ibm-spectrum-scale-csi has been deleted"
		return
	fi

	result=$(oc -n ibm-spectrum-scale-csi delete csiscaleoperators/ibm-spectrum-scale-csi 2>/dev/null)
	if [[ $? -gt 0 ]]; then
		error "Delete Scale CSI ibm-spectrum-scale-csi ERROR, please check if it exists"
		return
	fi
	info "Delete Scale CSI operation complete"
}

delete_snc_sc() {

	result=$(oc get sc --no-headers 2>/dev/null | grep spectrumscale.csi.ibm.com)
	if [[ $? -gt 0 || result == "" ]]; then
		info "No storage class needs to be deleted"
		return
	fi

	result=$(oc delete sc $(oc get sc --no-headers 2>/dev/null | grep spectrumscale.csi.ibm.com | awk '{print $1}') 2>/dev/null)
	if [[ $? -gt 0 ]]; then
		error "Delete Fusion's Storage Class ERROR, please check whether any exist"
		return
	fi
	info "Delete SNC Storage Class operation complete"
}

check_mmfs_deleted() {
	worker_num=$(oc get node | grep -c worker)
	deleted_num=$(oc get node | grep worker | awk '{print $1}' | xargs -I{} oc debug node/{} -q -T -- \
		chroot /host sh -c "ls /var/mmfs" | grep -c "No such file or directory")

	if [[ $deleted_num == $worker_num ]]; then
		info "scale old config folder not exist on all worker nodes"
	else
		error "not all worker nodes clean scale old config, the env is not clean."
	fi
}

check_scale_crd_deleted() {
	isf_crd_num=$(oc get crd | grep -e csiscaleoperators -e scale.spectrum.ibm.com | grep -c scale)

	if [[ isf_crd_num -eq 0 ]]; then
		info "no any scale crd exist"
	else
		error "still have $isf_crd_num fusion crd, the env is not clean."
	fi
}

check_isf_crd_deleted() {
	isf_crd_num=$(oc get crd | grep -c isf)

	if [[ isf_crd_num -eq 0 ]]; then
		info "no any fusion crd exist"
	else
		error "still have $isf_crd_num fusion crd, the env is not clean."
	fi
}
