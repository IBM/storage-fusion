#!/bin/bash
# Script to validate if most of required images is present in enterprise registry before install, if going for IBM Storage Fusion HCI enterprise installation.
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

For validation of images presence in enterprise registry, execute as following:
 ./mirror-hci-images.sh -rh1 "ENTERPRISE_REGISTRY_HOST" -il "IMAGE_LIST_JSON" -repo "1|2" [-sds y|n] -ps "/path/to/pull-secret.json"

Available options:
-il : Mandatory absolute path to image list json to be validated in registry
-rh1 : Mandatory enterprise registry URL for openshift, ex: https://mirror-registry.com:443/hci-230/mirror-openshift
-rh2 : Optional enterprise registry URL for ISF, ex: https://mirror-registry.com:443/hci-230/mirror-isf
-repo : Mandatory number of registries images are mirrored to. Expected value is 1|2
-sds : Optional parameter to indicate mirroring to be done for SDS. If not specified, default is HCI.
-ps : Mandatory pull-secret file fully qualified path. Required when mirroring is intended.
-sds: Optional parameter to indicate mirroring to be done for SDS. If not specified, default is HCI.
-scale: Optional parameter to validate mirroring done for IBM Spectrum Scale. If not specified, default is No.
-spp: Optional parameter to validate mirroring done for IBM Spectrum Protect Plus. If not specified, default is No.
-guardian: Optional parameter to validate mirroring done for Backup and Restore. If not specified, default is No.
-discover: Optional parameter to validate mirroring done for IBM Spectrum Discover. If not specified, default is No.
Example:
./validate-hci-images.sh -rh1 "test-jfrog-artifactory.com" -il "IMAGE_LIST_JSON" -repo 1 -sds "n" -ps "/root/mirror/pull-secret.json"
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
        arg=$1
        shift
        case $arg in
                -il)
                    IMAGE_LIST_JSON=$1
                    shift ;;
                -rh1)
                    REGISTRY_URL1=$1
                    shift ;;
                -rh2)
                    REGISTRY_URL2=$1
                    shift ;;
                -repo)
                    NO_OF_REGISTRY=$1
                    shift ;;
                -ps)
                    PULLSECRET=$1
                    shift ;;
                -sds)
	                SDS=$1
	                shift ;;
				-scale)
					SCALE_INSTALL=$1
					 shift ;;
				-spp)
					SPP_INSTALL=$1
					shift ;;  
				-guardian)
					GUARDIAN_INSTALL=$1
					shift ;; 
				-discover)
					DISCOVER_INSTALL=$1
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
	#scale
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

	#spp
	SPPAGENT_TAG=$(cat ${IMAGE_LIST_JSON} | jq -r '.images.spp."agent-tag"')
	spp_server_hci_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp.server | @sh') | tr -d '"' | tr -d \')
	spp_agent_hci_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp.agent | @sh') | tr -d '"' | tr -d \')
	spp_redhat_rhscl_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp."redhat-rhscl" | @sh') | tr -d '"' | tr -d \')
	spp_redhat_rhel8_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp."redhat-rhel8" | @sh') | tr -d '"' | tr -d \')
	spp_redhat_openshift4_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp."redhat-openshift4" | @sh') | tr -d '"' | tr -d \')
	spp_redhat_access_rhscl_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp."redhat-access-rhscl" | @sh') | tr -d '"' | tr -d \')
	spp_catalog_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp.catalog | @sh') | tr -d '"' | tr -d \')
	spp_strimzi_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp.strimzi | @sh') | tr -d '"' | tr -d \')
	spp_oadp_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp.oadp | @sh') | tr -d '"' | tr -d \')
	spp_amq7_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp.amq7 | @sh') | tr -d '"' | tr -d \')
        spp_amq_streams_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp."redhat-amq-streams" | @sh') | tr -d '"' | tr -d \')
        spp_ubi8_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.spp."ubi8" | @sh') | tr -d '"' | tr -d \')

	# ISF
	VERSION=$(cat ${IMAGE_LIST_JSON} | jq -r '.images.isf.version')
	isf_hci_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf.mgmt | @sh') | tr -d '"' | tr -d \')
	isf_hci_kube_proxy_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf."kube-proxy" | @sh') | tr -d '"' | tr -d \')
	isf_hci_submariner_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf."submariner" | @sh') | tr -d '"' | tr -d \')
	isf_hci_gcr_proxy_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf."gcr-kube-proxy" | @sh') | tr -d '"' | tr -d \')
	isf_sds_images=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.isf."sds-mgmt" | @sh') | tr -d '"' | tr -d \')

	# OCP
	HCI_OCP_VERSION=$(cat ${IMAGE_LIST_JSON} | jq -r '.images.ocp.version' | tr -d '"')
	OCP_DIGEST=$(cat ${IMAGE_LIST_JSON} | jq -r '.images.ocp."validation-release-digest"' | tr -d '"')

	# Red Hat
	RH_INDEX=$(cat ${IMAGE_LIST_JSON}  | jq -r '.images.redhat."redhat-operator-index"'| tr -d '"')
	RH_INDEX_VERSION=$(cat ${IMAGE_LIST_JSON}  | jq -r '.images.redhat."version"'| tr -d '"')
	RH_OPENSHIFT4=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.redhat.openshift4 | @sh') | tr -d '"' | tr -d \')
	RH_OPENSHIFT_LOGGING=$((cat ${IMAGE_LIST_JSON} | jq -r '.images.redhat."openshift-logging" | @sh') | tr -d '"' | tr -d \')
	RH_PATH=redhat
	rhpackage_list=$(cat ${IMAGE_LIST_JSON} | jq -r '.images.redhat.packages'|tr -d '"')
	OPENSHIFT_LOGGING=openshift-logging

  # Backup&Restore Guardian
  BKP_FBR=$((cat ${IMAGE_LIST_JSON}  | jq -r '.images."backup-restore".fbr | @sh') | tr -d '"' | tr -d \')
  BKP_BITNAMI=$((cat ${IMAGE_LIST_JSON}  | jq -r '.images."backup-restore"."docker-bitnami" | @sh') | tr -d '"' | tr -d \')
  BKP_IBM_OPEN=$((cat ${IMAGE_LIST_JSON}  | jq -r '.images."backup-restore"."ibm-open" | @sh') | tr -d '"' | tr -d \')

  #Data cataloging 
  DC_DB2U=$((cat ${IMAGE_LIST_JSON}  | jq -r '.images."data-cataloging"."ibm-db2u" | @sh') | tr -d '"' | tr -d \')
  DC_ISD=$((cat ${IMAGE_LIST_JSON}  | jq -r '.images."data-cataloging"."ibm-spectrum-discover" | @sh') | tr -d '"' | tr -d \')
  DC_IBM_OPEN=$((cat ${IMAGE_LIST_JSON}  | jq -r '.images."data-cataloging"."ibm-open" | @sh') | tr -d '"' | tr -d \')
}

function validate_ocp_images () {
	print info "Validating ocp image......"
	echo "************** Missing OCP images **************" >> ${MISSING_IMAGES_LIST}
	echo "************** Available OCP images **************" >> ${AVAILABLE_IMAGES_LIST}
	skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL1}@${OCP_DIGEST}  2>&1 > /dev/null
	if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}@${OCP_DIGEST}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}@${OCP_DIGEST}" >> ${AVAILABLE_IMAGES_LIST}; fi
	echo "****************************"
}

function validate_redhat_images () {
	print info "Validating redhat images......"
	echo "************** Missing RedHat operator images **************" >> ${MISSING_IMAGES_LIST}
	echo "************** Available RedHat operator images **************" >> ${AVAILABLE_IMAGES_LIST}

	skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${RH_INDEX}:${RH_INDEX_VERSION}   2>&1 > /dev/null
	if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${RH_INDEX}:${RH_INDEX_VERSION}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${RH_INDEX}:${RH_INDEX_VERSION}" >> ${AVAILABLE_IMAGES_LIST}; fi

	#for img in ${RH_OPENSHIFT4[@]}; do
	#	skopeo inspect --authfile $PULLSECRET docker://${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT4}-${img} 2>&1 > /dev/null
	#	if [[ $? -ne 0 ]] ; then echo "${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT4}-${img}" >> ${MISSING_IMAGES_LIST}; else echo "${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT4}-${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	#done

	#for img in ${RH_OPENSHIFT_LOGGING[@]}; do
	#	skopeo inspect --authfile $PULLSECRET docker://${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT_LOGGING}-${img}  2>&1 > /dev/null
	#	if [[ $? -ne 0 ]] ; then echo "${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT_LOGGING}-${img}" >> ${MISSING_IMAGES_LIST}; else echo "${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT_LOGGING}-${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	#done
  echo "****************************"
}

function validate_isf_images () {
	print info "Validating isf-operator images...."
	echo "************** Missing ISF images **************" >> ${MISSING_IMAGES_LIST}
	echo "************** Available ISF images **************" >> ${AVAILABLE_IMAGES_LIST}

	if [ "${SDS}" == "y" -o "${SDS}" == "Y" -o "${SDS}" == "yes" -o "${SDS}" == "Yes" -o "${SDS}" == "YES" ]; then
    #Start validating ISF-SDS images
		for img in ${isf_sds_images[@]}; do
			skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img} 2>&1 > /dev/null
			if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
		done
		for img in ${isf_hci_kube_proxy_images}; do
			skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${OPENSHIFT4}/${img}  2>&1 > /dev/null
			if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${OPENSHIFT4}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${OPENSHIFT4}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
		done
	else
		for img in ${isf_hci_images[@]}; do
			skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img} 2>&1 > /dev/null
			if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
		done

		for img in ${isf_hci_kube_proxy_images}; do
			skopeo inspect --authfile $PULLSECRET docker://${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT4}-${img}  2>&1 > /dev/null
    		if [[ $? -ne 0 ]] ; then echo "${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT4}-${img}" >> ${MISSING_IMAGES_LIST}; else echo "${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT4}-${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
  		done

  		for img in ${isf_hci_submariner_images[@]}; do
    		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${SUBMARINER}/${img} 2>&1 > /dev/null
    		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${SUBMARINER}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SUBMARINER}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
  		done

		for img in ${isf_hci_gcr_proxy_images[@]}; do
    		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${KUBEBUILDER}/${img} 2>&1 > /dev/null
    		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${KUBEBUILDER}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${KUBEBUILDER}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
  		done

		for img in ${isf_hci_gcr_proxy_images[@]}; do
    		skopeo inspect --authfile $PULLSECRET docker://${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${KUBEBUILDER}-${img} 2>&1 > /dev/null
    		if [[ $? -ne 0 ]] ; then echo "${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${KUBEBUILDER}-${img}" >> ${MISSING_IMAGES_LIST}; else echo "${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${KUBEBUILDER}-${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
  		done
	fi
	echo "****************************"
}

function validate_scale_images () {
	print info "Validating Scale images...."
	echo "************** Missing Scale images **************" >> ${MISSING_IMAGES_LIST}
	echo "************** Available Scale images **************" >> ${AVAILABLE_IMAGES_LIST}

	for img in ${scale_hci_index_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img} 2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${scale_hci_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img} 2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${scale_csi_hci_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${CSI}/${img} >> ${MISSING_IMAGES_LIST} 2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${CSI}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${CSI}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	if [ "${SDS}" == "y" -o "${SDS}" == "Y" -o "${SDS}" == "yes" -o "${SDS}" == "Yes" -o "${SDS}" == "YES" ]; then
		for img in ${scale_data_mgmt_images[@]}; do
			skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${DATAMGMT}/${img} >> ${MISSING_IMAGES_LIST} 2>&1 > /dev/null
			if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${DATAMGMT}/${img}" >> ${MISSING_IMAGES_LIST} ; else echo "${REGISTRY_URL2}/${DATAMGMT}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
		done
	else
		for img in ${scale_ece_images[@]}; do
    		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${ERASURE}/${img}  2>&1 > /dev/null
    		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${ERASURE}/${img}" >> ${MISSING_IMAGES_LIST} ; else echo "${REGISTRY_URL2}/${ERASURE}/${img}" >> ${AVAILABLE_IMAGES_LIST} ;fi
  		done
	fi
	echo "****************************"
}

function validate_spp_images () {
	print info "Validating SPP images...."
	echo "************** Missing SPP images **************" >> ${MISSING_IMAGES_LIST}
	echo "************** Available SPP images **************" >> ${AVAILABLE_IMAGES_LIST}
  
	for img in ${spp_oadp_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${SPPAGENT}/${img}  2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${OADP}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SPPAGENT}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${spp_strimzi_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${STRIMZI}/${img}  2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${STRIMZI}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SPPAGENT}/${STRIMZI}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${spp_server_hci_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${SPPSERVER}/${img}  2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${SPPSERVER}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SPPSERVER}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${spp_agent_hci_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${SPPAGENT}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${SPPAGENT}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SPPAGENT}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${spp_redhat_rhscl_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${SPPSERVER}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${SPPSERVER}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SPPSERVER}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${spp_redhat_rhel8_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${SPPSERVER}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${SPPSERVER}/${img}" >>  ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SPPSERVER}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${spp_redhat_openshift4_images[@]}; do
		# as per openshift mirroring
		skopeo inspect --authfile $PULLSECRET docker://${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT4}-${img}    2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${ISF_URL2}/${IMAGE_NS2}/${REPO_PREFIX2}${OPENSHIFT4}-${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${OPENSHIFT4}-${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${spp_redhat_access_rhscl_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${SPPSERVER}/${img} 2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${SPPSERVER}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SPPSERVER}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${spp_catalog_images[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

        for img in ${spp_amq_streams_images[@]}; do
                skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${SPPAGENT}/${img}   2>&1 > /dev/null
                if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${SPPAGENT}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SPPAGENT}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
        done

        for img in ${spp_amq7_images[@]}; do
                skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${SPPAGENT}/${img}   2>&1 > /dev/null
                if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${SPPAGENT}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${SPPAGENT}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
        done

        for img in ${spp_ubi8_images[@]}; do
                skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${UBI8}/${img}   2>&1 > /dev/null
                if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${UBI8}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${UBI8}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
        done
	echo "****************************"
}

function validate_guardian_images () {
	print info "Validating backup and restore image......"
	echo "************** Missing Backup and Restore images **************" >> ${MISSING_IMAGES_LIST}
	echo "************** Available Backup and Restore images **************" >> ${AVAILABLE_IMAGES_LIST}

	for img in ${BKP_FBR[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

    for img in ${BKP_BITNAMI[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img}   2>&1 > /dev/null
        if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
    done

	for img in ${BKP_IBM_OPEN[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done
	echo "****************************"
}

function validate_isd_images () {
	print info "Validating Data cataloging image......"
	echo "************** Missing Data cataloging images **************" >> ${MISSING_IMAGES_LIST}
	echo "************** Available Data cataloging images **************" >> ${AVAILABLE_IMAGES_LIST}

	for img in ${DC_DB2U[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${DB2U}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${DB2U}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${DB2U}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${DC_ISD[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${ISD}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${ISD}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${ISD}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${DC_IBM_OPEN[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done

	for img in ${DC_RH_AMQ7[@]}; do
		skopeo inspect --authfile $PULLSECRET docker://${REGISTRY_URL2}/${img}   2>&1 > /dev/null
		if [[ $? -ne 0 ]] ; then echo "${REGISTRY_URL2}/${img}" >> ${MISSING_IMAGES_LIST}; else echo "${REGISTRY_URL2}/${img}" >> ${AVAILABLE_IMAGES_LIST}; fi
	done
	echo "****************************"
}

function validate_images () {
	rm -f ${MISSING_IMAGES_LIST}
	rm -f ${AVAILABLE_IMAGES_LIST}
	touch ${MISSING_IMAGES_LIST}
	touch ${AVAILABLE_IMAGES_LIST}
	if [ "${SDS}" == "y" -o "${SDS}" == "Y" -o "${SDS}" == "yes" -o "${SDS}" == "Yes" -o "${SDS}" == "YES" ]; then
		validate_isf_images
    	if [ "${SCALE_INSTALL}" == "y" -o "${SCALE_INSTALL}" == "Y" -o "${SCALE_INSTALL}" == "yes" -o "${SCALE_INSTALL}" == "Yes" -o "${SCALE_INSTALL}" == "YES" ]; then validate_scale_images; fi
		if [ "${SPP_INSTALL}" == "y" -o "${SPP_INSTALL}" == "Y" -o "${SPP_INSTALL}" == "yes" -o "${SPP_INSTALL}" == "Yes" -o "${SPP_INSTALL}" == "YES" ]; then validate_spp_images; fi
    	if [ "${GUARDIAN_INSTALL}" == "y" -o "${GUARDIAN_INSTALL}" == "Y" -o "${GUARDIAN_INSTALL}" == "yes" -o "${GUARDIAN_INSTALL}" == "Yes" -o "${GUARDIAN_INSTALL}" == "YES" ]; then validate_guardian_images; fi
    	if [ "${DISCOVER_INSTALL}" == "y" -o "${DISCOVER_INSTALL}" == "Y" -o "${DISCOVER_INSTALL}" == "yes" -o "${DISCOVER_INSTALL}" == "Yes" -o "${DISCOVER_INSTALL}" == "YES" ]; then validate_isd_images; fi
	else
		validate_ocp_images
		validate_redhat_images
		validate_isf_images
		validate_scale_images
    	if [ "${SPP_INSTALL}" == "y" -o "${SPP_INSTALL}" == "Y" -o "${SPP_INSTALL}" == "yes" -o "${SPP_INSTALL}" == "Yes" -o "${SPP_INSTALL}" == "YES" ]; then validate_spp_images; fi
    	if [ "${GUARDIAN_INSTALL}" == "y" -o "${GUARDIAN_INSTALL}" == "Y" -o "${GUARDIAN_INSTALL}" == "yes" -o "${GUARDIAN_INSTALL}" == "Yes" -o "${GUARDIAN_INSTALL}" == "YES" ]; then validate_guardian_images; fi
    	if [ "${DISCOVER_INSTALL}" == "y" -o "${DISCOVER_INSTALL}" == "Y" -o "${DISCOVER_INSTALL}" == "yes" -o "${DISCOVER_INSTALL}" == "Yes" -o "${DISCOVER_INSTALL}" == "YES" ]; then validate_isd_images; fi
	fi
}

########################## GLOBAL VALUES ##########################
# Set default values
LOCAL_OCP_REPOSITORY=ocp4/openshift4
PRODUCT_REPO=openshift-release-dev
RELEASE_NAME=ocp-release
ARCHITECTURE=x86_64
QUAY=quay.io
DOCKERIO=docker.io
REDHAT_REGISTRY=registry.redhat.io
REDHAT_ACCESS_REGISTRY=registry.access.redhat.com
IBMPATH=cp
ISF_SUBPATH=isf
IBMOPENPATH=cpopen
ISF_OPERATOR_PATH=isf-operator
MISSING_IMAGES_LIST="$(pwd)/missing_images.txt"
AVAILABLE_IMAGES_LIST="$(pwd)/available_images.txt"
SPPSERVER=sppserver
SPPAGENT=sppc
STRIMZI=strimzi
OADP=oadp
RHSCL=rhscl
RHEL8=rhel8
OPENSHIFT4=openshift4
OPERATORHUBIO=operatorhubio
SUBMARINER=submariner
#scale
SCALEPATH=spectrum/scale
CSI=csi
ERASURE=erasure-code
DATAMGMT=data-management
DATAACCESS=data-access
CSIPATH=${SCALEPATH}/${CSI}
ECEPATH=${SCALEPATH}/${ERASURE}
DATAMGMTPATH=${SCALEPATH}/${DATAMGMT}
DATAACCESSPATH=${SCALEPATH}/${DATAACCESS}
#community-operator
GRAFANA_OPERATOR=grafana-operator
OS=linux/amd64
GCR=gcr.io
GRAFANA_INTEGREATLY_PATH=integreatly
GRAFANA=grafana
KUBEBUILDER=kubebuilder
KONVEYOR=konveyor
#Backup and Restore
#Data cataloging
DB2U=db2u
ISD=ibm-spectrum-discover
AMQSTREAM=amq-streams
UBI8=ubi8
AMQ7=amq7
##################################################
##################################################

# Start main
# Process command arguments
processArguments "$@"

[[  -z "$IMAGE_LIST_JSON" ]] && usage

if [[ -z "$SDS" ]]; then
        print info "sds option not provided, so validating for IBM Storage Fusion images."
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

if [[ -z "$REPO_COUNT" ]]; then
        print info "Considering single repository installtion for HCI."
        REPO_COUNT=1
fi

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

REPO_COUNT=$NO_OF_REGISTRY
if [[ $REPO_COUNT == 1 ]]; then
	if [[  -z "$REGISTRY_URL1" ]] ; then
		print error "Provide complete registry details"
		usage; exit 1
	else
		REGISTRY_HOST=`echo ${REGISTRY_URL1} | cut -d '/' -f 3`
		for LOGIN_SRC_REG in ${REGISTRY_HOST}
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
		if [[ `echo ${REGISTRY_URL1} | cut -d '/' -f 4` == ""  ]]; then
			print error "Provide complete path for ${REGISTRY_URL1}.PATH is missing"
			usage; exit 1
		fi
		REGISTRY_URL1=`echo ${REGISTRY_URL1} | cut -b 9-`
		REGISTRY_URL2=${REGISTRY_URL1}
		REGISTRY_USER2=${REGISTRY_USER1}
		REGISTRY_PASSWORD2=${REGISTRY_PASSWORD1}
	fi
elif [[ $REPO_COUNT = 2 ]]; then
	if [[ -z "$REGISTRY_URL1" ]] && [[ -z "$REGISTRY_URL2" ]]; then
		print error "Provide enterprise registry url for both repositories, if using single repository for install re-execute script using repo=1"
		usage; exit 1
	else
		REGISTRY_HOST1=`echo ${REGISTRY_URL1} | cut -d '/' -f3`    
		REGISTRY_HOST2=`echo ${REGISTRY_URL2} | cut -d '/' -f3`

		for LOGIN_SRC_REG in ${REGISTRY_HOST1} ${REGISTRY_HOST2}
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

		REGISTRY_URL1=`echo ${REGISTRY_URL1} | cut -b 9-`
    	REGISTRY_URL2=`echo ${REGISTRY_URL2} | cut -b 9-`
	fi
else
	print error "Either value 1 or 2 is supported. 1 if all images mirrored to single repo, else 2."
	usage; exit 1
fi

#Set namespace and repo prefix from registry_url
ISF_URL2=`echo ${REGISTRY_URL2} | cut -d '/' -f1`
REPOSITORY2=`echo ${REGISTRY_URL2} | cut -d '/' -f2-`
IFS='/' read -r NAMESPACE PREFIX <<< "${REPOSITORY2}"
if [[ "$PREFIX" != "" ]]; then IMAGE_NS2=${NAMESPACE}; REPO_PREFIX2=$(echo "${PREFIX}"| sed -r 's/\//-/g')-; else IMAGE_NS2=${NAMESPACE}; REPO_PREFIX2=""; fi

# Set regustry url
echo "========================================================="
echo "Inputs provided"
echo "========================================================="
echo Image list json file:	$IMAGE_LIST_JSON
if [[ $REPO_COUNT == 1 ]]; then
	echo Repo1:	$REGISTRY_URL1
elif [[ $REPO_COUNT == 2 ]]; then
	echo Repo1:	$REGISTRY_URL1
	echo Repo2:	$REGISTRY_URL2
fi
echo Pull secret:		$PULLSECRET/config.json
if [ ${SDS} == "y" -o ${SDS} == "Y" -o ${SDS} == "yes" -o ${SDS} == "Yes" -o ${SDS} == "YES" ] ; then
echo SDS Mirroring:	        "True"
else
echo HCI Mirroring:         "True"
fi
echo "========================================================="

if [[ $CTOOL == "docker" ]]; then
# Reset the pull-secret value as it will be used for skopeo copy
PULLSECRET="$PULLSECRET/config.json"
fi

validate_images

echo "========================================================="
echo "Attention: Before starting Install/upgrade"
echo "========================================================="
echo "1. Scripts does not mirror or validates used external packages for any of services, ensure you have completed those following KC before starting install or upgrade."
echo "2. Ensure you have applied ICSP and completed pre-requisites following KC for services you want to install/upgrade."
echo "IBM Knowledge Centre link: https://www.ibm.com/docs/en/storage-fusion/2.6?topic=installation-mirroring-your-images-enterprise-registry"
echo "========================================================="