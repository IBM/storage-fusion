#!/bin/bash

# Script to mirror IBM Spectrum Scale images before install, if going for IBM Spectrum Fusion enterprise installation.
# Author: sivas.srr@in.ibm.com, anshugarg@in.ibm.com, divjain5@in.ibm.com, THANGALLAPALLI.ANVESH@ibm.com

##
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
For mirroring IBM Spectrum Scale images presence in enterprise registry, execute as following:
 ./mirror-scale-images.sh -rh "ENTERPRISE_REGISTRY_HOST" -il "IMAGE_LIST_JSON" -tp "TARGET_PATH" -p "ENTERPRISE_REGISTRY_PORT" -ps "absolute path to config.json directory" [-sds y|n]
Available options:
-il : Mandatory absolute path to image list json to be validated in registry
-ps :  ./mirror-bkp-restore-images.sh -rh "ENTERPRISE_REGISTRY_HOST" -il "IMAGE_LIST_JSON" -tp "TARGET_PATH" -p "ENTERPRISE_REGISTRY_PORT" -ps "absolute path to config.json".
-rh : Mandatory enterprise registry hostname - ensure credentials for enterprise registry host is present in auth file.
-tp : Optional taget registry path for mirroring images when it is not default for HCI release.
-p : Optional enterprise registry port. If no port is specified it is set and used as 443.
-sds: Optional parameter to indicate mirroring to be done for SDS. If not specified, default is HCI.
Example:
./mirror-scale-images.sh -ps "/root/mirror" -rh "test-jfrog-artifactory.com" -tp "hci-260" -p "443" -il "isf-260-images.json" -sds n
EOF
    exit 1
}

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

	# Scale
  if [ "${SDS}" == "y" -o "${SDS}" == "Y" -o "${SDS}" == "yes" -o "${SDS}" == "Yes" -o "${SDS}" == "YES" ]; then
        scale_csi_hci_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images."spectrum-scale-sds".csi | @sh') | tr -d '"' | tr -d \')
        scale_hci_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images."spectrum-scale-sds".scale | @sh') | tr -d '"' | tr -d \')
        scale_hci_index_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images."spectrum-scale-sds".catalog | @sh') | tr -d '"' | tr -d \')
        scale_data_mgmt_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images."spectrum-scale-sds"."data-management" | @sh') | tr -d '"' | tr -d \')
  else
	scale_csi_hci_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images."spectrum-scale-hci".csi | @sh') | tr -d '"' | tr -d \')
	scale_hci_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images."spectrum-scale-hci".scale | @sh') | tr -d '"' | tr -d \')
	scale_hci_index_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images."spectrum-scale-hci".catalog | @sh') | tr -d '"' | tr -d \')
	scale_ece_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images."spectrum-scale-hci"."erasure-code" | @sh') | tr -d '"' | tr -d \')
  fi
}

# Function to mirror Scale images
function mirror_scale_images {
	for img in ${scale_hci_index_images[@]}; do
		print debug "skopeo copy --authfile $PULLSECRET --all docker://${IBM_OPEN_REGISTRY}/${IBMOPENPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${img}  2>&1 > ${MIRROR_LOG}"
		skopeo copy --authfile $PULLSECRET --all docker://${IBM_OPEN_REGISTRY}/${IBMOPENPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${img}  2>&1 >> ${MIRROR_LOG}
		if [[ $? -ne 0 ]] ; then print error "Failed to copy image ${img} from ${IBM_OPEN_REGISTRY}/${IBMOPENPATH}/ to ${LOCAL_REGISTRY}/${MIRROR_PATH}"; failedtocopy=1; fi
	done

	for img in ${scale_hci_images[@]}; do
		print debug "skopeo copy --authfile $PULLSECRET --all docker://${IBM_REGISTRY}/${IBMPATH}/${SCALEPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${img}  2>&1 > ${MIRROR_LOG}"
		skopeo copy --authfile $PULLSECRET --all docker://${IBM_REGISTRY}/${IBMPATH}/${SCALEPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${img}  2>&1 >> ${MIRROR_LOG}
		if [[ $? -ne 0 ]] ; then print error "Failed to copy image ${img} from ${IBM_REGISTRY}/${IBMPATH}/${SCALEPATH} to ${LOCAL_REGISTRY}/${MIRROR_PATH}"; failedtocopy=1; fi
	done

	for img in ${scale_csi_hci_images[@]}; do
		print debug "skopeo copy --authfile $PULLSECRET --all docker://${IBM_REGISTRY}/${IBMPATH}/${CSIPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${CSI}/${img}  2>&1 > ${MIRROR_LOG}"
		skopeo copy --authfile $PULLSECRET --all docker://${IBM_REGISTRY}/${IBMPATH}/${CSIPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${CSI}/${img}  2>&1 >> ${MIRROR_LOG}
		if [[ $? -ne 0 ]] ; then print error "Failed to copy image ${img} from ${IBM_REGISTRY}/${IBMPATH}/${CSIPATH} to ${LOCAL_REGISTRY}/${MIRROR_PATH}/${CSI}"; failedtocopy=1; fi
	done

  if [ "${SDS}" == "y" -o "${SDS}" == "Y" -o "${SDS}" == "yes" -o "${SDS}" == "Yes" -o "${SDS}" == "YES" ]; then
    for img in ${scale_data_mgmt_images[@]}; do
      print debug "skopeo copy --authfile $PULLSECRET --all docker://${IBM_REGISTRY}/${IBMPATH}/${DATAMGMTPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${DATAMGMT}/${img}  2>&1 > ${MIRROR_LOG}"
      skopeo copy --authfile $PULLSECRET --all docker://${IBM_REGISTRY}/${IBMPATH}/${DATAMGMTPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${DATAMGMT}/${img}  2>&1 >> ${MIRROR_LOG}
      if [[ $? -ne 0 ]] ; then print error "Failed to copy image ${img} from ${IBM_REGISTRY}/${IBMPATH}/${DATAMGMTPATH} to ${LOCAL_REGISTRY}/${MIRROR_PATH}/${DATAMGMT}"; failedtocopy=1; fi
	  done
  else
    for img in ${scale_ece_images[@]}; do
		  print debug "skopeo copy --authfile $PULLSECRET --all docker://${IBM_REGISTRY}/${IBMPATH}/${ECEPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${ERASURE}/${img}  2>&1 > ${MIRROR_LOG}"
		  skopeo copy --authfile $PULLSECRET --all docker://${IBM_REGISTRY}/${IBMPATH}/${ECEPATH}/${img} docker://${LOCAL_REGISTRY}/${MIRROR_PATH}/${ERASURE}/${img}  2>&1 >> ${MIRROR_LOG}
		  if [[ $? -ne 0 ]] ; then print error "Failed to copy image ${img} from ${IBM_REGISTRY}/${IBMPATH}/${ECEPATH} to ${LOCAL_REGISTRY}/${MIRROR_PATH}/${ERASURE}"; failedtocopy=1; fi
	  done
  fi

  if [[ $failedtocopy -eq 1  ]] ; then
    print error "Some images are having issues to copy, please check nohup.out / output of execution"
		exit 1 # Exit with an error in image copy
  else
		print info "Successfully mirrored SCALE images."
  fi
}

########################## GLOBAL VALUES ##########################
# Set default values
IBM_REGISTRY_USER=cp
IBM_REGISTRY=cp.icr.io
IBM_OPEN_REGISTRY=icr.io
PRODUCT_REPO=openshift-release-dev
RELEASE_NAME=ocp-release
ARCHITECTURE=x86_64
QUAY=quay.io
DOCKERIO=docker.io
SCALEPATH=spectrum/scale
CSI=csi
ERASURE=erasure-code
DATAMGMT=data-management
DATAACCESS=data-access
CSIPATH=${SCALEPATH}/${CSI}
ECEPATH=${SCALEPATH}/${ERASURE}
DATAMGMTPATH=${SCALEPATH}/${DATAMGMT}
DATAACCESSPATH=${SCALEPATH}/${DATAACCESS}

IBMPATH=cp
IBMOPENPATH=cpopen
MIRROR_LOG="$(pwd)/mirror_out.log"
##################################################
##################################################

# Start main
# Process command arguments
echo "SRS: all arguments"
#echo $@
processArguments "$@"

[[  -z "$IMAGE_LIST_JSON" ]] && usage
[[  -z "$ENTERPRISE_REGISTRY_HOST" ]] && usage

# Set MIRROR_PATH
if [[ -z "$TARGET_PATH" ]] ; then
    print info "Target path within target registry was not specified so default is being used."
	MIRROR_PATH=$(cat ${IMAGE_LIST_JSON} | jq -r '."isf-target-path"')
else
    MIRROR_PATH=${TARGET_PATH}
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

if [[  -z "$PULLSECRET" ]] ; then
   print info "Pull secret directory is not defined!, using default ~/.docker/config.json"
   PULLSECRET="/root/.docker"
fi

if [ ! -f "$PULLSECRET/config.json" ]; then
    print info "Pull secret not found in directory $PULLSECRET"
	exit 1
fi

# Set regustry url
echo "========================================================="
echo "Inputs provided"
echo "========================================================="
echo Image list json file:	$IMAGE_LIST_JSON
echo Target registry path:	$LOCAL_REGISTRY/$MIRROR_PATH
echo Pull secret:		$PULLSECRET/config.json
if [ ${SDS} == "y" -o ${SDS} == "Y" -o ${SDS} == "yes" -o ${SDS} == "Yes" -o ${SDS} == "YES" ] ; then echo SDS Mirroring: "True"; else echo HCI Mirroring: "True"; fi
echo "========================================================="

# Remove old mirror logs
rm -f ${MIRROR_LOG}

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

for LOGIN_SRC_REG in ${IBM_REGISTRY} ${LOCAL_REGISTRY}
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

mirror_scale_images
