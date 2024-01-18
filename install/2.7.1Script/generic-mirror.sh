#!/bin/bash
# Script to mirror IBM Storage Fusion HCI images before install, if going for IBM Storage Fusion HCI enterprise installation.
# Author: sivas.srr@in.ibm.com, anshugarg@in.ibm.com, divjain5@in.ibm.com, THANGALLAPALLI.ANVESH@ibm.com, prashansar@ibm.com

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

Prerequisites Required:
    Minimum Skopeo version should be 1.14

Available options:
    -ps    : Mandatory PULL-SECRET file path.
    -lreg  : Mandatory LOCAL_ISF_REGISTRY="<Your Enterprise Registry Host>:<Port>", PORT is optional.
    -lrep  : Mandatory LOCAL_ISF_REPOSITORY="<Your Image Path>", which is the image path to mirror the images.
    -ocpv  : Optional OCP_VERSION, Required only if '-all' or '-ocp' or '-redhat' or '-df' is used.
    -all   : Optional ALL_IMAGES, which mirrors all the images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING).
    -ocp   : Optional OCP_IMAGES, which mirrors all the OCP images.
    -redhat: Optional REDHAT_IMAGES, which mirrors all the REDHAT images.
    -fusion: Optional FUSION_IMAGES, which mirrors all the FUSION images.
    -gdp   : Optional GDP_IMAGES, which mirrors all the GLOBAL DATA PLATFORM images.
    -df    : Optional DF_IMAGES, which mirrors all the  DATA FOUNDATION images.
    -br    : Optional BR_IMAGES, which mirrors all the  BACKUP & RESTORE images.
    -dcs"  : Optional DCS_IMAGES, which mirrors all the  DATA CATALOGING images.
 
To Mirror images present in the enterprise registry, execute as following:
    To Mirror All Images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
        nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -all &
    To Mirror Only Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
        nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -ocp -redhat -fusion -gdp -df -br -dcs &

Example:
    nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.12.42" -all &

NOTE: 
- If port is used in LOCAL_ISF_REGISTRY(-lreg) make sure to add that entry in your pull-secret file
- The Input details like LOCAL_ISF_REGISTRY & LOCAL_ISF_REPOSITORY are based on mirroring in the IBM Knowledge centre, please refer the IBM Knowledge centre for more details https://www.ibm.com/docs/en/sfhs/2.7.x?topic=installation-mirroring-your-images-enterprise-registry .

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
		-ps)
			PULL_SECRET=$1
			shift ;;
	    -lreg)
			LOCAL_ISF_REGISTRY=$1
			shift ;;
	    -lrep)
			LOCAL_ISF_REPOSITORY=$1
			shift ;;
	    -pr)
            PRODUCT=$1
            shift ;;
		-env)
			ENV=$1
			shift ;;
	    -isf)
			ISF_VERSION=$1
			shift ;;
        -ocpv)
            OCP_VERSION=$1
            shift ;;
        -fusion)
            ISF=$arg ;;
        -gdp)
            GDP_IMAGES=$arg ;;
        -br)
            GUARDIAN_IMAGES=$arg ;;
        -dcs)
            DISCOVER_IMAGES=$arg ;;
        -df)
            FDF_IMAGES=$arg ;;
        -redhat)
            REDHAT_IMAGES=$arg ;;
        -ocp)
            OCP_IMAGES=$arg ;;
        -all)
            ALL_IMAGES=$arg ;;
		-*)
			print warn "Ignoring unrecognized option $arg" >&2
			# Discard option value
			shift ;;
		*)
			print warn "Ignoring unrecognized argument $arg" >&2;;
		esac
	done
}

function repo_login() {
  # Logging in to Repos manually
  print info "EXECUTING repo_login()"
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
  fi
  for LOGIN_SRC_REG in ${IBM_REGISTRY} ${REDHAT_REGISTRY} ${QUAY_REGISTRY} ${LOCAL_ISF_REGISTRY}
  do
    DECODED_AUTH_VALUE=$(jq -r ".auths[\"$LOGIN_SRC_REG\"].auth" ${PULL_SECRET} | base64 -d)
    USERNAME=$(echo $DECODED_AUTH_VALUE | cut -d':' -f1)
    PASSWORD=$(echo $DECODED_AUTH_VALUE | cut -d':' -f2)
    $CTOOL login -u $USERNAME -p $PASSWORD $LOGIN_SRC_REG
    if [[ $? -eq 0 ]] ; then
      print info "Login success to ${LOGIN_SRC_REG}"
    else
      print error "Login to ${LOGIN_SRC_REG} failed. Ensure you had correct ${LOGIN_SRC_REG} registry, auth credentials in ${PULL_SECRET} and check connectivity to registry.";
      usage;
      exit 1;
    fi
  done
}

function get_image_list_json() {
  # get the megabom from a json file
  print info "EXECUTING get_image_list_json()"
  IMAGE_LIST_JSON=./isf-271-images.json
}

function get_megabom_images() {
  # Reading megabom images list
  print info "EXECUTING get_megabom_images()"
  INT_IMAGE=($(jq -r '.internal[]."image_name"' $IMAGE_LIST_JSON))
  DIGEST=($(jq -r '.internal[]."digest"' $IMAGE_LIST_JSON))
  INT_SERVICE=($(jq -r '.internal[]."service"' $IMAGE_LIST_JSON))
  IMG_GA=($(jq -r '.internal[]."ga"' $IMAGE_LIST_JSON))
  ARTIFACTORY_LOC=($(jq -r '.internal[]."art_location"' $IMAGE_LIST_JSON))
  ENTITLED=($(jq -r '.internal[]."entitled"' $IMAGE_LIST_JSON))
  STAGE_LOC=($(jq -r '.internal[]."staging_location"' $IMAGE_LIST_JSON))
  PRODUCT_LOC=($(jq -r '.internal[]."prod_location"' $IMAGE_LIST_JSON))
  PARENT_LOC=($(jq -r '.internal[]."parent_location"' $IMAGE_LIST_JSON))
  INT_OCP_VER=($(jq -r '.internal[]."ocp_version"' $IMAGE_LIST_JSON))

  # Reading external image list
  EXT_SERVICE=($(jq -r '.external[]."service"' $IMAGE_LIST_JSON))
  EXT_IMAGE=($(jq -r '.external[]."image_name"' $IMAGE_LIST_JSON))
  EXT_PARENT_LOC=($(jq -r '.external[]."parent_location"' $IMAGE_LIST_JSON))
  EXT_OCP_VER=($(jq -r '.external[]."ocp_version"' $IMAGE_LIST_JSON))
  if [[ $? -ne 0 ]] ; then
    print error "Please make sure isf-271-images.json file is in this folder"
    exit 1
  fi
}

function get_kc_df_images() {
  # Function for mirroring Data Cataloging images
  print info "EXECUTING get_kc_df_images()"
  REDHAT_VERSION=$(echo $OCP_VERSION | cut -d'.' -f1,2)
  cat <<EOF > imageset-config-df.yaml
  kind: ImageSetConfiguration
  apiVersion: mirror.openshift.io/v1alpha2
  storageConfig:
    registry:
      imageURL: "$TARGET_PATH/isf-df-metadata:latest"
      skipTLS: true
  mirror:
    operators:
      - catalog: icr.io/cpopen/isf-data-foundation-catalog:v${REDHAT_VERSION}
        packages:
          - name: "mcg-operator"
          - name: "ocs-operator"
          - name: "odf-csi-addons-operator"
          - name: "odf-multicluster-orchestrator"
          - name: "odf-operator"
          - name: "odr-cluster-operator"
          - name: "odr-hub-operator"
EOF
  FDF="$(pwd)/DF_images.txt"
  echo -e "================= Skopeo Commands for FDF Images =================\n" >> ${FDF}
  MIRROR_LOG=${FDF}
  print info "oc mirror --config imageset-config-df.yaml docker://"$TARGET_PATH" --dest-skip-tls --ignore-history" >> ${MIRROR_LOG}
  oc mirror --config imageset-config-df.yaml docker://"$TARGET_PATH" --dest-skip-tls --ignore-history
  if [[ $? -ne 0 ]] ; then print error "Failed to execute oc mirror --config imageset-config-df.yaml docker://"$TARGET_PATH" --dest-skip-tls --ignore-history"; failedtocopy=1; fi
  if [[ $failedtocopy -eq 1  ]] ; then
		print error "Some get_kc_df_images() are having issues to copy, please check nohup.out / output of execution"
		exit 1
	else
		print info "Successfully mirrored get_kc_df_images()!!!"
	fi
}

function get_kc_local_df_images() {
  # Function for mirroring Data Cataloging images
  print info "EXECUTING get_kc_local_df_images()"
  REDHAT_VERSION=$(echo $OCP_VERSION | cut -d'.' -f1,2)
  cat << EOF > imageset-config-lso.yaml
  kind: ImageSetConfiguration
  apiVersion: mirror.openshift.io/v1alpha2
  storageConfig:
    registry:
      imageURL: "$TARGET_PATH/df/odf-lso-metadata:latest"
      skipTLS: true
  mirror:
    operators:
      - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.14
        packages:
          - name: "local-storage-operator"
          - name: "lvms-operator"
EOF
  MIRROR_LOG=${FDF}
  echo -e "================= Skopeo Commands for local storage operator FDF Images =================\n" >> ${FDF}
  print info "oc mirror --config imageset-config-lso.yaml docker://${TARGET_PATH} --dest-skip-tls --ignore-history" >> ${MIRROR_LOG}
  oc mirror --config imageset-config-lso.yaml docker://${TARGET_PATH} --dest-skip-tls --ignore-history
  if [[ $? -ne 0 ]] ; then print error "Failed to execute oc mirror --config imageset-config-lso.yaml docker://${TARGET_PATH} --dest-skip-tls --ignore-history"; failedtocopy=1; fi
  if [[ $failedtocopy -eq 1  ]] ; then
		print error "Some get_kc_local_df_images() are having issues to copy, please check nohup.out / output of execution"
		exit 1
	else
		print info "Successfully mirrored get_kc_local_df_images()!!!"
	fi
}

function get_kc_redhat_external() {
  # Function for mirroring Redhat external images
  print info "EXECUTING get_kc_redhat_external()"
  REDHAT_VERSION=$(echo $OCP_VERSION | cut -d'.' -f1,2)
    cat << EOF > imageset-redhat-external.yaml
    kind: ImageSetConfiguration
    apiVersion: mirror.openshift.io/v1alpha2
    mirror:
      operators:
        - catalog: registry.redhat.io/redhat/redhat-operator-index:v${REDHAT_VERSION}
          packages:
            - name: kubernetes-nmstate-operator
            - name: kubevirt-hyperconverged
            - name: redhat-oadp-operator
            - name: amq-streams
EOF
  REDHAT="$(pwd)/Redhat_images.txt"
  echo -e "================= Skopeo Commands for Redhat Images =================\n" >> ${REDHAT}
  MIRROR_LOG=${REDHAT}
  print info "oc-mirror --config imageset-redhat-external.yaml docker://"$TARGET_PATH" --dest-skip-tls --ignore-history" >> ${MIRROR_LOG}
  oc-mirror --config imageset-redhat-external.yaml docker://"$TARGET_PATH" --dest-skip-tls --ignore-history
  if [[ $? -ne 0 ]] ; then print error "Failed to execute oc-mirror --config imageset-redhat-external.yaml docker://"$TARGET_PATH" --dest-skip-tls --ignore-history"; failedtocopy=1; fi
  if [[ $failedtocopy -eq 1  ]] ; then
		print error "Some get_kc_redhat_external() are having issues to copy, please check nohup.out / output of execution"
		exit 1
	else
		print info "Successfully mirrored get_kc_redhat_external()!!!"
	fi
}

function mirror_internal_images() {
  # Function for mirroring internal images from megabom
  print info "EXECUTING mirror_internal_images()"
  for ((i=0; i<${#INT_IMAGE[@]}; i++)); do
    if [[ "${IMG_GA[i]}" = "true" ]] ; then
      IMG_LOC="${PRODUCT_LOC[i]}"
    else
      IMG_LOC="${ARTIFACTORY_LOC[i]}"
    fi
    SOURCE_IMAGE="docker://${IMG_LOC}/${INT_IMAGE[i]}@${DIGEST[i]}"
    DEST_IMAGE=$(echo "${PRODUCT_LOC[i]}/${INT_IMAGE[i]}@${DIGEST[i]}" | sed "s|${PARENT_LOC[i]}||")
    IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
    if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GDP}
      if [[ "${INT_SERVICE[i]}" = "cnsa" ]] ; then
        echo "skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"" >> ${MIRROR_LOG}
        skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL""; failedtocopy=1; fi
      fi
    fi
    if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GUARDIAN}
      if [[ "${INT_SERVICE[i]}" = "backup-restore-agent" ]] || [[ "${INT_SERVICE[i]}" = "backup-restore-server" ]] ; then
        echo "skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"" >> ${MIRROR_LOG}
        skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL""; failedtocopy=1; fi
      fi
    fi
    if [[ $DISCOVER_IMAGES = "-dcs" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${DISCOVER}
      if [[ "${INT_SERVICE[i]}" = "discover" ]] ; then
        echo "skopeo copy --override-os=linux --multi-arch=all "$SOURCE_IMAGE" "$IMAGE_URL"" >> ${MIRROR_LOG}
        skopeo copy --override-os=linux --multi-arch=all "$SOURCE_IMAGE" "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --override-os=linux --multi-arch=all "$SOURCE_IMAGE" "$IMAGE_URL""; failedtocopy=1; fi
      fi
    fi
    if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${FUSION}
      if [[ "${INT_SERVICE[i]}" = "fusion" ]] ; then
        if [[ ${INT_IMAGE[i]} = "isf-operator-software-catalog" ]] ; then
          echo -e "skopeo copy --insecure-policy --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION} docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}\n" >> ${MIRROR_LOG}
          skopeo copy --insecure-policy --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION} docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}
          if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --insecure-policy --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION} docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}"; failedtocopy=1; fi
        elif [[ ${INT_IMAGE[i]} = "isf-operator-catalog" ]] ; then
          echo -e "skopeo copy --insecure-policy --all docker://$IMG_LOC/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64 docker://\$TARGET_PATH/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64\n" >> ${MIRROR_LOG}
          skopeo copy --insecure-policy --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64 docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64
          if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --insecure-policy --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64 docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64"; failedtocopy=1; fi
        else
          echo "skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"" >> ${MIRROR_LOG}
          skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"
          if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL""; failedtocopy=1; fi
        fi
      fi
    fi
  done
  if [[ $failedtocopy -eq 1  ]] ; then
		print error "Some mirror_internal_images() are having issues to copy, please check nohup.out / output of execution"
		exit 1
	else
		print info "Successfully mirrored mirror_internal_images()!!!"
	fi
}

function mirror_megabom_external_images() {
  # Function for mirroring external images from megabom
  print info "EXECUTING mirror_megabom_external_images()"
  for ((i=0; i<${#EXT_IMAGE[@]}; i++)); do
    SOURCE_IMAGE="docker://${EXT_IMAGE[i]}"
    DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed "s|${EXT_PARENT_LOC[i]}||")
    IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
    if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GDP}
      if [[ "${EXT_SERVICE[i]}" = "cnsa" ]] ; then
        echo "skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"" >> ${MIRROR_LOG}
        skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL""; failedtocopy=1; fi
      fi
    fi
    if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GUARDIAN}
      if [[ "${EXT_SERVICE[i]}" = "backup-restore-agent" ]] || [[ "${INT_SERVICE[i]}" = "backup-restore-server" ]] ; then
        echo "skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"" >> ${MIRROR_LOG}
        skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL""; failedtocopy=1; fi
      fi
    fi
    if [[ $DISCOVER_IMAGES = "-dcs" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${DISCOVER}
      if [[ "${EXT_SERVICE[i]}" = "discover" ]] ; then
        echo "skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"" >> ${MIRROR_LOG}
        skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL""; failedtocopy=1; fi
      fi
    fi
    if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${FUSION}
      if [[ "${EXT_SERVICE[i]}" = "fusion" ]] ; then
        if [[ ${EXT_IMAGE[i]} = *"ose-kube-rbac-proxy"* ]] ; then
          SRC_IMAGE=$(echo $DEST_IMAGE | cut -d'/' -f 3-)
          echo "skopeo copy --all --preserve-digests "$SOURCE_IMAGE" docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)openshift4-$SRC_IMAGE" >> ${MIRROR_LOG}
          skopeo copy --all --preserve-digests "$SOURCE_IMAGE" docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)openshift4-$SRC_IMAGE
          if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --all --preserve-digests "$SOURCE_IMAGE" docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)openshift4-$SRC_IMAGE"; failedtocopy=1; fi
        fi
        echo "skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"" >> ${MIRROR_LOG}
        skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --insecure-policy --all "$SOURCE_IMAGE" "$IMAGE_URL""; failedtocopy=1; fi
      fi
    fi
  done
  if [[ $failedtocopy -eq 1  ]] ; then
		print error "Some mirror_megabom_external_images() are having issues to copy, please check nohup.out / output of execution"
		exit 1
	else
		print info "Successfully mirrored mirror_megabom_external_images()!!!"
	fi
}

function mirror_submariner_images () {
  # Hard Coding the copy commands for submariner images
  # Can be removed if the images are added to the megabom
  print info "EXECUTING mirror_submariner_images()"
  echo "skopeo copy --all docker://quay.io/submariner/submariner-operator:0.15.2 docker://$TARGET_PATH/submariner/submariner-operator:0.15.2" >> "$FUSION"
  skopeo copy --all docker://quay.io/submariner/submariner-operator:0.15.2 docker://$TARGET_PATH/submariner/submariner-operator:0.15.2
  if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --all docker://quay.io/submariner/submariner-operator:0.15.2 docker://$TARGET_PATH/submariner/submariner-operator:0.15.2"; failedtocopy=1; fi
  echo "skopeo copy --all docker://quay.io/submariner/submariner-gateway:0.15.2 docker://$TARGET_PATH/submariner/submariner-gateway:0.15.2" >> "$FUSION"
  skopeo copy --all docker://quay.io/submariner/submariner-gateway:0.15.2 docker://$TARGET_PATH/submariner/submariner-gateway:0.15.2
  if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --all docker://quay.io/submariner/submariner-operator:0.15.2 docker://$TARGET_PATH/submariner/submariner-operator:0.15.2"; failedtocopy=1; fi
  echo "skopeo copy --all docker://quay.io/submariner/lighthouse-agent:0.15.2 docker://$TARGET_PATH/submariner/lighthouse-agent:0.15.2" >> "$FUSION"
  skopeo copy --all docker://quay.io/submariner/lighthouse-agent:0.15.2 docker://$TARGET_PATH/submariner/lighthouse-agent:0.15.2
  if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --all docker://quay.io/submariner/lighthouse-agent:0.15.2 docker://$TARGET_PATH/submariner/lighthouse-agent:0.15.2"; failedtocopy=1; fi
  echo "skopeo copy --all docker://quay.io/submariner/lighthouse-coredns:0.15.2 docker://$TARGET_PATH/submariner/lighthouse-coredns:0.15.2" >> "$FUSION"
  skopeo copy --all docker://quay.io/submariner/lighthouse-coredns:0.15.2 docker://$TARGET_PATH/submariner/lighthouse-coredns:0.15.2
  if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --all docker://quay.io/submariner/lighthouse-coredns:0.15.2 docker://$TARGET_PATH/submariner/lighthouse-coredns:0.15.2"; failedtocopy=1; fi
  echo "skopeo copy --all docker://quay.io/submariner/submariner-networkplugin-syncer:0.15.2 docker://$TARGET_PATH/submariner/submariner-networkplugin-syncer:0.15.2" >> "$FUSION"
  skopeo copy --all docker://quay.io/submariner/submariner-networkplugin-syncer:0.15.2 docker://$TARGET_PATH/submariner/submariner-networkplugin-syncer:0.15.2
  if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --all docker://quay.io/submariner/submariner-networkplugin-syncer:0.15.2 docker://$TARGET_PATH/submariner/submariner-networkplugin-syncer:0.15.2"; failedtocopy=1; fi
  echo "skopeo copy --all docker://quay.io/submariner/submariner-route-agent:0.15.2 docker://$TARGET_PATH/submariner/submariner-route-agent:0.15.2" >> "$FUSION"
  skopeo copy --all docker://quay.io/submariner/submariner-route-agent:0.15.2 docker://$TARGET_PATH/submariner/submariner-route-agent:0.15.2
  if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --all docker://quay.io/submariner/submariner-route-agent:0.15.2 docker://$TARGET_PATH/submariner/submariner-route-agent:0.15.2"; failedtocopy=1; fi
  echo "skopeo copy --all docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.8.0 docker://$TARGET_PATH/kubebuilder/kube-rbac-proxy:v0.8.0" >> "$FUSION"
  skopeo copy --all docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.8.0 docker://$TARGET_PATH/kubebuilder/kube-rbac-proxy:v0.8.0
  if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --all docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.8.0 docker://$TARGET_PATH/kubebuilder/kube-rbac-proxy:v0.8.0"; failedtocopy=1; fi
  echo "skopeo copy --all docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.8.0 docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)kubebuilder-kube-rbac-proxy:v0.8.0" >> "$FUSION"
  skopeo copy --all docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.8.0 docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)kubebuilder-kube-rbac-proxy:v0.8.0
  if [[ $? -ne 0 ]] ; then print error "Failed to copy skopeo copy --all docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.8.0 docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)kubebuilder-kube-rbac-proxy:v0.8.0"; failedtocopy=1; fi
  if [[ $failedtocopy -eq 1  ]] ; then
    print error "Some mirror_submariner_images() are having issues to copy, please check nohup.out / output of execution"
    exit 1 
  else
    print info "Successfully mirrored mirror_submariner_images()!!!"
  fi
}

function mirror_ocp_images() {
  # Function to mirror the ocp images
  print info "EXECUTING mirror_ocp_images()"
  OCP="$(pwd)/OCP_images.txt"
  echo -e "================= Skopeo Commands for Redhat Images =================\n" >> ${OCP}
  MIRROR_LOG=${OCP}
  echo "oc adm release mirror -a ${PULL_SECRET} --from=quay.io/openshift-release-dev/ocp-release:${OCP_VERSION}-x86_64 --to=$TARGET_PATH --to-release-image=$TARGET_PATH:${OCP_VERSION}-x86_64" >> ${MIRROR_LOG}
  oc adm release mirror -a ${PULL_SECRET} --from=quay.io/openshift-release-dev/ocp-release:${OCP_VERSION}-x86_64 --to=$TARGET_PATH --to-release-image=$TARGET_PATH:${OCP_VERSION}-x86_64
  if [[ $? -ne 0 ]] ; then print error "Failed to copy oc adm release mirror -a ${PULL_SECRET} --from=quay.io/openshift-release-dev/ocp-release:${OCP_VERSION}-x86_64 --to=$TARGET_PATH --to-release-image=$TARGET_PATH:${OCP_VERSION}-x86_64"; failedtocopy=1; fi
  if [[ $failedtocopy -eq 1  ]] ; then
    print error "Some mirror_ocp_images() are having issues to copy, please check nohup.out / output of execution"
    exit 1 
  else
    print info "Successfully mirrored mirror_ocp_images()!!!"
  fi
}

function mirror_images() {
  # Function to call the other mirroring functions
  print info "EXECUTING mirror_images()"
  get_megabom_images
  mirror_megabom_external_images
  if [[ $REDHAT_IMAGES = "-redhat" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    get_kc_redhat_external
  fi
  if [[ $OCP_IMAGES = "-ocp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    mirror_ocp_images
  fi
  if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    mirror_submariner_images
  fi
  mirror_internal_images
  mirror_megabom_missing_images
  if [[ $FDF_IMAGES = "-df" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    get_kc_df_images
    get_kc_local_df_images
  fi
}

function validate_images() {
  # Function to validate the mirrored images
  print info "EXECUTING validate_images()"
  get_megabom_images
  # Loop through the INTERNAL images and validate them
  for ((i=0; i<${#INT_IMAGE[@]}; i++)); do
    INT_CNT=$(($i + 1))
    echo VALIDATING INTERNAL IMAGE [${INT_CNT}/${#INT_IMAGE[@]}]....${INT_IMAGE[i]}
    if [[ "${IMG_GA[i]}" = "true" ]] ; then
      IMG_LOC="${PRODUCT_LOC[i]}"
    else
      IMG_LOC="${ARTIFACTORY_LOC[i]}"
    fi
    DEST_IMAGE=$(echo "${PRODUCT_LOC[i]}/${INT_IMAGE[i]}@${DIGEST[i]}" | sed "s|${PARENT_LOC[i]}||")
    IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
    if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GDP}
      if [[ "${INT_SERVICE[i]}" = "cnsa" ]] ; then
        echo "skopeo inspect "$IMAGE_URL""
        skopeo inspect "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then
          echo -e "skopeo inspect ${IMAGE_URL}\n" >> ${MISSING_IMAGES}
          failedtocopy=1
        else
          echo -e "${INT_IMAGE[i]}@${DIGEST[i]}\n" >> ${AVAILABLE_IMAGES}
        fi
      fi
    fi
    if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GUARDIAN}
      if [[ "${INT_SERVICE[i]}" = "backup-restore-agent" ]] || [[ "${INT_SERVICE[i]}" = "backup-restore-server" ]] ; then\
        echo "skopeo inspect "$IMAGE_URL""
        skopeo inspect "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then
          echo -e "skopeo inspect ${IMAGE_URL}\n" >> ${MISSING_IMAGES}
          failedtocopy=1
        else
          echo -e "${INT_IMAGE[i]}@${DIGEST[i]}\n" >> ${AVAILABLE_IMAGES}
        fi
      fi
    fi
    if [[ $DISCOVER_IMAGES = "-dcs" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${DISCOVER}
      if [[ "${INT_SERVICE[i]}" = "discover" ]] ; then
        echo "skopeo inspect "$IMAGE_URL""
        skopeo inspect "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then
          echo -e "skopeo inspect ${IMAGE_URL}\n" >> ${MISSING_IMAGES}
          failedtocopy=1
        else
          echo -e "${INT_IMAGE[i]}@${DIGEST[i]}\n" >> ${AVAILABLE_IMAGES}
        fi
      fi
    fi
    if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${FUSION}
      if [[ "${INT_SERVICE[i]}" = "fusion" ]] ; then
        if [[ ${INT_IMAGE[i]} = "isf-operator-software-catalog" ]] ; then
          IMAGE_URL="docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}"
        elif [[ ${INT_IMAGE[i]} = "isf-operator-catalog" ]] ; then
          IMAGE_URL="docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64"
        else
          echo "skopeo inspect "$IMAGE_URL""
          skopeo inspect "$IMAGE_URL"
          if [[ $? -ne 0 ]] ; then
            echo -e "skopeo inspect ${IMAGE_URL}\n" >> ${MISSING_IMAGES}
            failedtocopy=1
          else
            echo -e "${INT_IMAGE[i]}@${DIGEST[i]}\n" >> ${AVAILABLE_IMAGES}
          fi
        fi
      fi
    fi
  done
  # Loop through the EXTERNAL images and validate them
  for ((i=0; i<${#EXT_IMAGE[@]}; i++)); do
    EXT_CNT=$(($i + 1))
    echo VALIDATING EXTERNAL IMAGE [${EXT_CNT}/${#EXT_SERVICE[@]}]....${EXT_IMAGE[i]}
    SOURCE_IMAGE="docker://${EXT_IMAGE[i]}"
    DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed "s|${EXT_PARENT_LOC[i]}||")
    IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
    if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GDP}
      if [[ "${EXT_SERVICE[i]}" = "cnsa" ]] ; then
        echo "skopeo inspect "$IMAGE_URL""
        skopeo inspect "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then
          echo -e "${EXT_IMAGE[i]}\n" >> ${MISSING_IMAGES}
          failedtocopy=1
        else
          echo -e "${EXT_IMAGE[i]}\n" >> ${AVAILABLE_IMAGES}
        fi
      fi
    fi
    if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GUARDIAN}
      if [[ "${EXT_SERVICE[i]}" = "backup-restore-agent" ]] || [[ "${INT_SERVICE[i]}" = "backup-restore-server" ]] ; then
        echo "skopeo inspect "$IMAGE_URL""
        skopeo inspect "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then
          echo -e "${EXT_IMAGE[i]}\n" >> ${MISSING_IMAGES}
          failedtocopy=1
        else
          echo -e "${EXT_IMAGE[i]}\n" >> ${AVAILABLE_IMAGES}
        fi
      fi
    fi
    if [[ $DISCOVER_IMAGES = "-dcs" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${DISCOVER}
      if [[ "${EXT_SERVICE[i]}" = "discover" ]] ; then
        echo "skopeo inspect "$IMAGE_URL""
        skopeo inspect "$IMAGE_URL"
        if [[ $? -ne 0 ]] ; then
          echo -e "${EXT_IMAGE[i]}\n" >> ${MISSING_IMAGES}
          failedtocopy=1
        else
          echo -e "${EXT_IMAGE[i]}\n" >> ${AVAILABLE_IMAGES}
        fi
      fi
    fi
    if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${FUSION}
      if [[ "${EXT_SERVICE[i]}" = "fusion" ]] ; then
        if [[ ${EXT_IMAGE[i]} = *"ose-kube-rbac-proxy"* ]] ; then
          SRC_IMAGE=$(echo $DEST_IMAGE | cut -d'/' -f 3-)
          IMAGE_URL="docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)openshift4-$SRC_IMAGE"
          echo "skopeo inspect "$IMAGE_URL""
          skopeo inspect $IMAGE_URL
          if [[ $? -ne 0 ]] ; then
            echo -e "${EXT_IMAGE[i]}\n" >> ${MISSING_IMAGES}
            failedtocopy=1
          else
            echo -e "${EXT_IMAGE[i]}\n" >> ${AVAILABLE_IMAGES}
          fi
        else
          echo "skopeo inspect "$IMAGE_URL""
          skopeo inspect "$IMAGE_URL"
          if [[ $? -ne 0 ]] ; then
            echo -e "${EXT_IMAGE[i]}\n" >> ${MISSING_IMAGES}
            failedtocopy=1
          else
            echo -e "${EXT_IMAGE[i]}\n" >> ${AVAILABLE_IMAGES}
          fi
        fi
      fi
    fi
  done
  # Loop through the Redhat images and validate them
  if [[ $REDHAT_IMAGES = "-redhat" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    MIRROR_LOG=${REDHAT}
    REDHAT_VERSION=$(echo $OCP_VERSION | cut -d'.' -f1,2)
    DEST_IMAGE=/redhat/redhat-operator-index:v${REDHAT_VERSION}
    IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
    echo "skopeo inspect "$IMAGE_URL""
    skopeo inspect "$IMAGE_URL"
    if [[ $? -ne 0 ]] ; then
      echo -e "${EXT_IMAGE[i]}\n" >> ${MISSING_IMAGES}
      failedtocopy=1
    else
      echo -e "${EXT_IMAGE[i]}\n" >> ${AVAILABLE_IMAGES}
    fi
  fi
  # Loop through the OCP images and validate them
  if [[ $OCP_IMAGES = "-ocp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    MIRROR_LOG=${OCP}
    DEST_IMAGE="$(oc adm release info quay.io/openshift-release-dev/ocp-release:${OCP_VERSION}-x86_64 | sed -n 's/Pull From: .*@//p')"
    IMAGE_URL="docker://${TARGET_PATH}@${DEST_IMAGE}"
    echo "skopeo inspect "$IMAGE_URL""
    skopeo inspect "$IMAGE_URL"
    if [[ $? -ne 0 ]] ; then
      echo -e "${EXT_IMAGE[i]}\n" >> ${MISSING_IMAGES}
      failedtocopy=1
    else
      echo -e "${EXT_IMAGE[i]}\n" >> ${AVAILABLE_IMAGES}
    fi
  fi
  if [[ $failedtocopy -eq 1  ]] ; then
    print error "Some validate_images() are having issues please check nohup.out / output of execution"
    exit 1
  else
    print info "Successfully validated validate_images()!!!"
  fi
}

##################################################
# Start main
# Process command arguments
##################################################
echo "SRS: all arguments"
processArguments "$@"

REDHAT_REGISTRY=registry.redhat.io
QUAY_REGISTRY=quay.io
IBM_REGISTRY=cp.icr.io
failedtocopy=0

########################## GLOBAL VALUES ##########################
#Removing existing files to collect skopeo cmds
echo "================= Deleting existing files if any ================="
rm -f ${AVAILABLE_IMAGES}
rm -f ${MISSING_IMAGES}
rm -f ${FUSION}
rm -f ${GDP}
rm -f ${FDF}
rm -f ${OCP}
rm -f ${REDHAT}
rm -f ${DISCOVER}
rm -f ${GUARDIAN}
rm -rf ./temporary
rm -f ./nohup.out
rm -f imageset-config-df.yaml
rm -f imageset-config-lso.yaml

# Set default values
MISSING_IMAGES="$(pwd)/missing_img.txt"
AVAILABLE_IMAGES="$(pwd)/avail_img.txt"

if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  FUSION="$(pwd)/Fusion_images.txt"
  echo -e "================= Skopeo Commands for Fusion Images =================\n" >> ${FUSION}
fi
if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  GDP="$(pwd)/GDP_images.txt"
  echo -e "================= Skopeo Commands for GDP Images =================\n" >> ${GDP}
fi
if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  GUARDIAN="$(pwd)/BackupRestore_images.txt"
  echo -e "================= Skopeo Commands for Guardian Images =================\n" >> ${GUARDIAN}
fi
if [[ $DISCOVER_IMAGES = "-dcs" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  DISCOVER="$(pwd)/DataCataloging_images.txt"
  echo -e "================= Skopeo Commands for Discover Images =================\n" >> ${DISCOVER}
fi

IFS='/' read -r NAMESPACE PREFIX <<< "$LOCAL_ISF_REPOSITORY"
if [[ "$PREFIX" != "" ]]; then export TARGET_PATH="$LOCAL_ISF_REGISTRY/$NAMESPACE/$PREFIX"; export REPO_PREFIX=$(echo "$PREFIX"| sed -r 's/\//-/g')-; export NAMESPACE="$NAMESPACE"; else export TARGET_PATH="$LOCAL_ISF_REGISTRY/$NAMESPACE"; export REPO_PREFIX=""; fi
#verify the variables set correctly
echo "TARGET_PATH: $TARGET_PATH"
echo "NAMESPACE: $NAMESPACE"
echo "REPO_PREFIX: $REPO_PREFIX"

[[  -z "$PULL_SECRET" ]] && usage

if [[  -z "$ISF_VERSION" ]] ; then
	print info "No $ISF_VERSION -isf is provided, using 2.7.1 as default"
	ISF_VERSION="2.7.1"
else
  ISF_VERSION=$ISF_VERSION
fi

if [[ ${#ISF_VERSION} -eq 5  ]] ; then
	IMAGE_ID="${ISF_VERSION}-latest"
else
  IMAGE_ID="${ISF_VERSION}"
fi

if [[ -z "$PRODUCT" ]] ; then
	print info "No PRODUCT -pr is provided, using HCI as default"
	PRODUCT="hci"
else
  PRODUCT=$PRODUCT
fi

if [[ $REDHAT_IMAGES = "-redhat" ]] || [[ $FDF_IMAGES = "-df" ]] || [[ $OCP_IMAGES = "-ocp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  [[  -z "$OCP_VERSION" ]] && usage
fi

if [[ -z "$ENV" ]] ; then
	print info "No ENV -env is provided, using PRODUCTION as the default environment"
	ENV="production"
else
  ENV=$ENV
fi

#Login to registries
repo_login

#Copying the Image Lst from artifactory
get_image_list_json

echo -e "================= List of images mirrored successfully =================\n" >> ${AVAILABLE_IMAGES}
echo -e "================= Below images are missing!!!! =================\n" >> ${MISSING_IMAGES}

#Mirroring the Images
mirror_images

#Validating the Images
validate_images

if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${FUSION}
fi
if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${GDP}
fi
if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${GUARDIAN}
fi
if [[ $DISCOVER_IMAGES = "-dcs" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${DISCOVER}
fi
if [[ $REDHAT_IMAGES = "-redhat" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${REDHAT}
fi
if [[ $FDF_IMAGES = "-df" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${FDF}
fi
if [[ $OCP_IMAGES = "-ocp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${OCP}
fi

echo "This is the missing images file: "
cat ${MISSING_IMAGES}
echo "This is the available images file: "
cat ${AVAILABLE_IMAGES}

if [[ $failedtocopy -ne 1  ]] ; then
  print info "MIRRORING DONE Successfully!!!"
  exit 1
fi
