#!/bin/bash
# Script to mirror IBM Spectrum Fusion HCI images before install, if going for IBM Spectrum Fusion HCI enterprise installation.
# Author: sivas.srr@in.ibm.com, anshugarg@in.ibm.com, divjain5@in.ibm.com, THANGALLAPALLI.ANVESH@ibm.com

# start_Copyright_Notice
# Licensed Materials - Property of IBM
#
# IBM Storage Fusion 5639-SPS
# (C) Copyright IBM Corp. 2021 All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

# usage - This function used for user guidance what are the flags they have to pass while running the script
usage(){
cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") <args>
For validation of images presence in enterprise registry, execute as following:
 ./mirror-isf-images.sh -rh "ENTERPRISE_REGISTRY_HOST" -p "ENTERPRISE_REGISTRY_PORT" -tp "TARGET_PATH" -ps "absolute path to config.json directory" -il "IMAGE_LIST_JSON" [-sds "y|n"]
Available options:
-il : Mandatory absolute path to image list json to be validated in registry
-ps :  ./mirror-bkp-restore-images.sh -rh "ENTERPRISE_REGISTRY_HOST" -il "IMAGE_LIST_JSON" -tp "TARGET_PATH" -p "ENTERPRISE_REGISTRY_PORT" -ps "absolute path to config.json".
-tp : Optional taget registry path for mirroring images when it is not default for HCI release.
-p : Optional enterprise registry port.
-sds: Optional parameter to indicate mirroring to be done for SDS. If not specified, default is HCI.
-rh: Mandatory enterprise registry host - ensure credentials for enterprise registry host is present in auth file.
Example:
./mirror-isf-images.sh -ps "/root/mirror" -rh "test-jfrog-artifactory.com" -tp "hci-260" -p "443" -il isf-260-images.json -sds n
EOF
    exit 1
}

# As of now commented the below code - will reenable later
# source ./mirror-hci-images.sh

########################## FUNCTIONS ##########################
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
			echo "INFO: $2";;
	esac
}

function processArguments {
    while [ $# -gt 0 ]; do
	echo "SRS $1 output:" $1
	echo "SRS $0 output:" $2
        arg=$1
        shift
        case $arg in
        	-il)
            	IMAGE_LIST_JSON=$1
               shift ;;
        	-ps)
            	PULLSECRET=$1
            	shift ;;
        	-rh)
            	ENTERPRISE_REGISTRY_HOST=$1
            	shift ;;
		      -p)
		          ENTERPRISE_REGISTRY_PORT=$1
		          shift ;;
        	-tp)
        	   	TARGET_PATH=$1
        	   	shift ;;
    		  -sds)
	    	    	SDS=$1
		          shift ;;
           -*)
               print warn "Ignoring unrecognized option $arg" >&2
               # Discard option value
               shift ;;
           *)
		          print warn "Ignoring unrecognized argument $arg" >&2;;
        esac
    done
}

# Read image list
function read_image_list {
	if [[ -z "$OPERATOR_VERSION" ]]; then VERSION=$(cat ${IMAGE_LIST_JSON} | jq -r '.version'); fi
	echo "VERSION: " $VERSION
	isf_hci_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf.mgmt | @sh') | tr -d '"' | tr -d \')
	isf_kube_proxy_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf."kube-proxy" | @sh') | tr -d '"' | tr -d \')
	isf_hci_submariner_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf."submariner" | @sh') | tr -d '"' | tr -d \')
    isf_hci_gcr_proxy_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf."gcr-kube-proxy" | @sh') | tr -d '"' | tr -d \')
	isf_sds_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf."sds-mgmt" | @sh') | tr -d '"' | tr -d \')
}
function mirror_isf_images () {
    if [ ${SDS} == "y" -o ${SDS} == "Y" -o ${SDS} == "yes" -o ${SDS} == "Yes" -o ${SDS} == "YES" ]; then
        #Start mirroring ISF-SDS images
        for img in ${isf_sds_images[@]}; do
            if [[  "${img}" == *"isf-operator-software-catalog"* ||  "${img}" == *"isf-operator-software-bundle"* ]]; then
                SOURCE_REGISTRY=$IBM_OPEN_REGISTRY
            	SDS_SOURCE_PATH=$IBMOPENPATH
             else
                        SOURCE_REGISTRY=$IBM_REGISTRY
            fi
            print debug "skopeo copy --authfile $PULLSECRET --all docker://${SOURCE_REGISTRY}/${SDS_SOURCE_PATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${img}  2>&1 > ${MIRROR_LOG}"
            skopeo copy --authfile $PULLSECRET --all docker://${SOURCE_REGISTRY}/${SDS_SOURCE_PATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${img}  2>&1 >> ${MIRROR_LOG}
            if [[ $? -ne 0 ]] ; then print error "Failed to copy ${img} from ${SOURCE_REGISTRY}/${SDS_SOURCE_PATH} to ${LOCAL_REGISTRY}/${MIRROR_PATH}"; failedtocopy=1; fi
        done

	for img in ${isf_kube_proxy_images[@]}; do
            print debug "skopeo copy --authfile $PULLSECRET --all docker://${REDHAT_REGISTRY}/${OPENSHIFT4}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${OPENSHIFT4}-${img}  2>&1 > ${MIRROR_LOG}"
            skopeo copy --authfile $PULLSECRET --all docker://${REDHAT_REGISTRY}/${OPENSHIFT4}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${OPENSHIFT4}-${img}  2>&1 >> ${MIRROR_LOG}
            if [[ $? -ne 0 ]]; then print error "Failed to copy ${img} from ${REDHAT_REGISTRY}/${OPENSHIFT4} to ${LOCAL_REGISTRY}/${MIRROR_PATH}"; failedtocopy=1; fi
            print debug "skopeo copy --authfile $PULLSECRET --all docker://${REDHAT_REGISTRY}/${OPENSHIFT4}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${OPENSHIFT4}/${img}  2>&1 > ${MIRROR_LOG}"
            skopeo copy --authfile $PULLSECRET --all docker://${REDHAT_REGISTRY}/${OPENSHIFT4}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${OPENSHIFT4}/${img}  2>&1 >> ${MIRROR_LOG}
            if [[ $? -ne 0 ]] ; then print error "Failed to copy ${img} from ${REDHAT_REGISTRY}/${OPENSHIFT4} to ${LOCAL_REGISTRY}/${MIRROR_PATH}"; failedtocopy=1; fi
        done
    else
        #Start mirroring ISF images
	for img in ${isf_hci_images[@]}; do
		if [[  "${img}" == *"isf-operator-catalog"* ||  "${img}" == *"isf-operator-bundle"* ]]; then
	    	SOURCE_REGISTRY=$IBM_OPEN_REGISTRY
			ISF_SOURCE_PATH=$IBMOPENPATH
		else
			SOURCE_REGISTRY=$IBM_REGISTRY
	    	fi

		print debug "skopeo copy --authfile $PULLSECRET --all docker://${SOURCE_REGISTRY}/${ISF_SOURCE_PATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${img}  2>&1 > ${MIRROR_LOG}"
		skopeo copy --authfile $PULLSECRET --all docker://${SOURCE_REGISTRY}/${ISF_SOURCE_PATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${img}  2>&1 >> ${MIRROR_LOG}
		if [[ $? -ne 0 ]] ; then print error "Failed to copy ${img} from ${SOURCE_REGISTRY}/${ISF_SOURCE_PATH} to ${LOCAL_REGISTRY}/${MIRROR_PATH}"; failedtocopy=1; fi
	done

        # Mirror SUBMARINER images
    	for img in ${isf_hci_submariner_images[@]}; do
            	print debug "skopeo copy --authfile $PULLSECRET --all docker://${QUAY}/${SUBMARINER}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${SUBMARINER}/${img}  2>&1 > ${MIRROR_LOG}"
                skopeo copy --authfile $PULLSECRET --all docker://${QUAY}/${SUBMARINER}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${SUBMARINER}/${img}  2>&1 >> ${MIRROR_LOG}
            	if [[ $? -ne 0 ]] ; then print error "Failed to copy ${img} from ${QUAY}/${SUBMARINER}/${img} to ${LOCAL_REGISTRY}/${MIRROR_PATH}/${SUBMARINER}"; failedtocopy=1; fi
        done

        # Mirror gcr kube rbac proxy images for DR
    	for img in ${isf_hci_gcr_proxy_images[@]}; do
            	print debug "skopeo copy --authfile $PULLSECRET --all docker://${GCR}/${KUBEBUILDER}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${KUBEBUILDER}/${img}  2>&1 > ${MIRROR_LOG}"
                skopeo copy --authfile $PULLSECRET --all docker://${GCR}/${KUBEBUILDER}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${KUBEBUILDER}/${img}  2>&1 >> ${MIRROR_LOG}
            	if [[ $? -ne 0 ]] ; then print error "Failed to copy ${img} from ${GCR}/${KUBEBUILDER}/${img} to ${LOCAL_REGISTRY}/${MIRROR_PATH}/${KUBEBUILDER}"; failedtocopy=1; fi
        done

        #Create target path for kube-proxy image where source is registry docker://registry.redhat.io/openshift4/ose-kube-rbac-proxy
    	IFS='/' read -r NAMESPACE PREFIX <<< "${MIRROR_PATH}"
    	if [[ "$PREFIX" != "" ]]; then IMAGE_NS=${NAMESPACE}; REPO_PREFIX=$(echo "${PREFIX}"| sed -r 's/\//-/g')-; else IMAGE_NS=${NAMESPACE}; REPO_PREFIX=""; fi
        for img in ${isf_kube_proxy_images[@]}; do
		print debug "skopeo copy --authfile $PULLSECRET --all docker://${REDHAT_REGISTRY}/${OPENSHIFT4}/${img} docker://${LOCAL_REGISTRY}/${IMAGE_NS}/${REPO_PREFIX}${OPENSHIFT4}-${img}  2>&1 > ${MIRROR_LOG}"
        	skopeo copy --authfile $PULLSECRET --all docker://${REDHAT_REGISTRY}/${OPENSHIFT4}/${img} docker://${LOCAL_REGISTRY}/${IMAGE_NS}/${REPO_PREFIX}${OPENSHIFT4}-${img}  2>&1 >> ${MIRROR_LOG}
        	if [[ $? -ne 0 ]] ; then print error "Failed to copy ${img} from ${REDHAT_REGISTRY}/${OPENSHIFT4} to ${LOCAL_REGISTRY}/${IMAGE_NS}"; failedtocopy=1; fi
        done

    	for img in ${isf_hci_gcr_proxy_images[@]}; do
            	print debug "skopeo copy --authfile $PULLSECRET --all docker://${GCR}/${KUBEBUILDER}/${img} docker://${LOCAL_REGISTRY}/${IMAGE_NS}/${REPO_PREFIX}${KUBEBUILDER}-${img}  2>&1 > ${MIRROR_LOG}"
                skopeo copy --authfile $PULLSECRET --all docker://${GCR}/${KUBEBUILDER}/${img} docker://${LOCAL_REGISTRY}/${IMAGE_NS}/${REPO_PREFIX}${KUBEBUILDER}-${img}  2>&1 >> ${MIRROR_LOG}
            	if [[ $? -ne 0 ]] ; then print error "Failed to copy ${img} from ${GCR}/${KUBEBUILDER}/${img} to ${LOCAL_REGISTRY}/${IMAGE_NS}"; failedtocopy=1; fi
        done

    fi

    if [[ $failedtocopy -eq 1  ]] ; then
    	print error "Some are having issues to copy, please check nohup.out / output of execution"
	    exit 1 # Exit with an error in image copy
    else
	    print info "Successfully mirrored ISF images."
    fi
}
########################## GLOBAL VALUES ##########################
# Set default values
IBM_REGISTRY_USER=cp
IBM_REGISTRY=cp.icr.io
IBM_OPEN_REGISTRY=icr.io
LOCAL_OCP_REPOSITORY=ocp4/openshift4

ARCHITECTURE=x86_64
QUAY=quay.io

IBMPATH=cp
ISF_SUBPATH=isf
SDS_SUBPATH=isf-sds
IBMOPENPATH=cpopen
VERSION=$(cat ${IMAGE_LIST_JSON} | jq -r '.version')
ISF_OPERATOR_PATH=isf-operator
SPPSERVER=sppserver
SPPAGENT=sppc
STRIMZI=strimzi
OADP=oadp
RHSCL=rhscl
RHEL8=rhel8
OPENSHIFT4=openshift4
OPERATORHUBIO=operatorhubio
MIRROR_LOG="$(pwd)/mirror_out.log"
OPM_EXPORT_OUT="$(pwd)/temp_export.out"
SUBMARINER="submariner"
REDHAT_REGISTRY=registry.redhat.io
KUBEBUILDER="kubebuilder"
GCR="gcr.io"
##################################################
##################################################

# Start main
# Process command arguments
echo "SRS: all arguments"
processArguments "$@"

[[  -z "$IMAGE_LIST_JSON" ]] && usage
[[  -z "$ENTERPRISE_REGISTRY_HOST" ]] && usage

if [[ -z "$TARGET_PATH" ]] ; then
    print info "Target path within target registry was not specified so default is being used."
	MIRROR_PATH=$(cat ${IMAGE_LIST_JSON} | jq -r '."isf-target-path"')
else
       	MIRROR_PATH=${TARGET_PATH}
fi

if [[  -z "$PULLSECRET" ]] ; then
   print info "Pull secret directory is not defined!, using default ~/.docker/config.json"
   PULLSECRET="/root/.docker"
fi

if [ ! -f "$PULLSECRET/config.json" ]; then
    print info "Pull secret not found in directory $PULLSECRET"
	exit 1
fi

if [[ -z "$ENTERPRISE_REGISTRY_PORT" ]] ; then
  print info "No registry port is provided."
  LOCAL_REGISTRY=$ENTERPRISE_REGISTRY_HOST
else
  LOCAL_REGISTRY=$ENTERPRISE_REGISTRY_HOST:$ENTERPRISE_REGISTRY_PORT
fi

if [[ -z "$SDS" ]]; then
        print info "sds option not provided, so mirroring for IBM Spectrum Fusion operator images."
        SDS='n'
fi

if [ ${SDS} == "y" -o ${SDS} == "Y" -o ${SDS} == "yes" -o ${SDS} == "Yes" -o ${SDS} == "YES" ]; then
    SDS_SOURCE_PATH=${IBMPATH}/${SDS_SUBPATH}
else
    ISF_SOURCE_PATH=${IBMPATH}/${ISF_SUBPATH}
fi

# Set regustry url
echo "========================================================="
echo "Inputs provided"
echo "========================================================="
echo Image list json file:	$IMAGE_LIST_JSON
echo Target registry path:	$LOCAL_REGISTRY/$MIRROR_PATH
echo Pull secret:		$PULLSECRET/config.json
if [ ${SDS} == "y" -o ${SDS} == "Y" -o ${SDS} == "yes" -o ${SDS} == "Yes" -o ${SDS} == "YES" ] ; then
echo SDS Mirroring:	        "True"
else
echo HCI Mirroring:             "True"
fi
echo "========================================================="

# Remove old mirror logs
rm -f ${MIRROR_LOG}
rm -f ${OPM_EXPORT_OUT}

# read image file and create image list of various components
read_image_list

print info "Logging to source and target registries"
# Find if docker or podman is being used
which podman 2>&1 > /dev/null
podmanrc=$?
which docker 2>&1 > /dev/null
dockerrc=$?
if [ ${podmanrc} -ne 0 -a ${dockerrc} -ne 0 ] ; then
	print error "Could not find either podman or docker on path. Please install docker or podman and add it to path."
	exit 1
elif [[ $dockerrc -eq 0 ]] ; then
	print info "Using docker as container tool."
	CTOOL=docker
elif [[ $podmanrc -eq 0 ]] ; then
  	print info "Using podman as container tool."
        CTOOL=podman
	PULLSECRET="$PULLSECRET/config.json"
fi

for LOGIN_SRC_REG in ${IBM_REGISTRY} ${LOCAL_REGISTRY} ${REDHAT_REGISTRY}
do
  if [[ $CTOOL == "docker" ]]; then
    print info "$CTOOL --config  ${PULLSECRET} login ${LOGIN_SRC_REG}"
    $CTOOL --config  ${PULLSECRET} login ${LOGIN_SRC_REG}
    if [[ $? -ne 0 ]] ; then print error "Login to ${LOGIN_SRC_REG} failed. Ensure you have correct credentials in ${PULLSECRET} and check connectivity to registry."; usage; exit 1; fi
  else
    print info "$CTOOL login ${LOGIN_SRC_REG} --authfile  ${PULLSECRET}"
    $CTOOL login ${LOGIN_SRC_REG} --authfile ${PULLSECRET}
    if [[ $? -ne 0 ]] ; then print error "Login to ${LOGIN_SRC_REG} failed. Ensure you have correct credentials in ${PULLSECRET} and check connectivity to registry."; usage; exit 1; fi
  fi
done

if [[ $CTOOL == "docker" ]]; then
# Reset the pull-secret value as it will be used for skopeo copy
PULLSECRET="$PULLSECRET/config.json"
fi

# Mirror ISF images to local registry
mirror_isf_images