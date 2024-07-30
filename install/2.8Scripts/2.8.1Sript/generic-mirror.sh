#!/bin/bash
# Script to mirror IBM Storage Fusion HCI images before install, if going for IBM Storage Fusion HCI enterprise installation.
# Author: sivas.srr@in.ibm.com, anshugarg@in.ibm.com, divjain5@in.ibm.com, THANGALLAPALLI.ANVESH@ibm.com, prashansar@ibm.com

# start_Copyright_Notice
# Licensed Materials - Property of IBM
#
# IBM Storage Fusion 5639-SPS
# (C) Copyright IBM Corp. 2024 All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

# usage - This function used for user guidance what are the flags they have to pass while running the script
usage(){
cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") error <args>

Prerequisites Required:
    - Please refer the "Before you begin" section in IBM Knowledge centre for prerequisites https://www.ibm.com/docs/en/sfhs/2.8.x?topic=installation-mirroring-your-images-enterprise-registry#tasktask_htj_h1w_stb__prereq__1

Available options:
    -ps    : Mandatory PULL-SECRET file path.
    -lreg  : Mandatory LOCAL_ISF_REGISTRY="<Your Enterprise Registry Host>:<Port>", PORT is optional.
    -lrep  : Mandatory LOCAL_ISF_REPOSITORY="<Your Image Path>", which is the image path to mirror the images.
    -pr    : Optional PRODUCT type, either "hci" or "sds", by default "hci" will be considered.
    -dest_as_tag_with_selfsigned_cert : Optional destination as tag with selfsigned certificate option, which does tag based mirroring with selfsigned certificate.
    -dest_as_tag : Optional destination as tag without selfsigned certificate option, which does tag based mirroring without selfsigned certificate.
    -dest_as_digest_with_selfsigned_cert : Optional(By default this option is used) destination as digest with selfsigned certificate option, which does digest based mirroring with selfsigned certificate.
    -dest_as_digest : Optional destination as digest without selfsigned certificate option, which does digest based mirroring without selfsigned certificate.
    -ocpv  : Optional OCP_VERSION (eg: "4.14.14" or multiple versions like "4.14.24,4.15.12"), Required only if '-all' or '-ocp' or '-redhat' is used.
    -fdfv  : Optional FDF_VERSION (eg: "4.14" or multiple versions like "4.14,4.15"), Required only if '-all' or '-fdf' or '-redhat' is used.
    -all   : Optional ALL_IMAGES, which mirrors all the images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING).
    -ocp   : Optional OCP_IMAGES, which mirrors all the OCP images.
    -redhat: Optional REDHAT_IMAGES, which mirrors all the REDHAT images.
    -fusion: Optional FUSION_IMAGES, which mirrors all the FUSION images.
    -gdp   : Optional GDP_IMAGES, which mirrors all the GLOBAL DATA PLATFORM images.
    -fdf   : Optional DF_IMAGES, which mirrors all the  DATA FOUNDATION images.
    -br    : Optional BR_IMAGES, which mirrors all the  BACKUP & RESTORE images.
    -dcs   : Optional DCS_IMAGES, which mirrors all the  DATA CATALOGING images.
    -validate : Optional VALIDATE_IMAGES, to only validate the mirrored images, should be used only with any/some of the -all/-ocp/-redhat/-fusion/-gdp/-fdf/-br/-dcs.
 
To Mirror images present in the enterprise registry, execute as following:
    To Mirror All Images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
        nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -all &
    To Mirror Only Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
        nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -ocp -redhat -fusion -gdp -fdf -br -dcs &
    To Mirror All Images with destination as tag with selfsigned certificate option(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
        nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -dest_as_tag_with_selfsigned_cert -all &

To only Validate the mirrored images:
    To only validate All Images(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
        nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -all -validate &
    To only validate Required Images(Any/Some of the OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
        nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -ocp -redhat -fusion -gdp -fdf -br -dcs -validate &
    To only validate All Images with destination as tag without selfsigned certificate option(OCP, REDHAT, FUSION, GLOBAL DATA PLATFORM, DATA FOUNDATION, BACKUP & RESTORE and DATA CATALOGING):
        nohup ./generic-mirror.sh -ps "PATH_TO_THE_PULL_SECRET_FILE" -lreg "LOCAL_ISF_REGISTRY:<PORT>" -lrep "LOCAL_ISF_REPOSITORY" -ocpv "OCP_VERSION" -fdfv "FDF_VERSION" -dest_as_tag -all -validate &

Examples for mirroring:
    - nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -all &
    - nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -dest_as_tag_with_selfsigned_cert -all &

Examples for only validation:
    - nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -all -validate &
    - nohup ./generic-mirror.sh -ps ./pull-secret.json -lreg "registryhost.com:443" -lrep "fusion-mirror" -ocpv "4.14.24" -dest_as_tag -all -validate &

NOTE: 
- If port is used in LOCAL_ISF_REGISTRY(-lreg) make sure to add that entry in your pull-secret file .
- For the required Pull-secret registries & input details like LOCAL_ISF_REGISTRY & LOCAL_ISF_REPOSITORY of respective images are based on mirroring steps in the IBM Knowledge centre, please refer the IBM Knowledge centre for more details .
  - "Download pull-secret.txt" section https://www.ibm.com/docs/en/sfhs/2.8.x?topic=installation-mirroring-your-images-enterprise-registry .
  - "See the following sample values" section under 1st point Procedure https://www.ibm.com/docs/en/sfhs/2.8.x?topic=registry-mirroring-storage-fusion-hci-images#tasksf_mirror_scale_images__steps__1 .
- This Script supports only single repo mirroring & validation, for multirepo please execute this script twice with appropriate options
- For mirroring 4.15 Redhat or Data Foundation images, please refer the 1st Note point in Procedure section's 1st point in IBM Knowledge centre for more details https://www.ibm.com/docs/en/sfhs/2.8.x?topic=registry-mirroring-red-hat-operator-images-enterprise#tasktask_vpk_nbw_stb__steps__1 .
- This script doesn't fully validate the OCP, Redhat, Data Cataloging and Data Foundation images .
- While installing Backup & Restore or Data cataloging service make sure to add the Redhat ImageContentSourcePolicy, please refer the 6th point Procedure section in IBM Knowledge centre for more details https://www.ibm.com/docs/en/sfhs/2.8.x?topic=registry-mirroring-red-hat-operator-images-enterprise . 
- For applying other ImageContentSourcePolicies & CatalogSources during installation, please refer the respective mirroring sections https://www.ibm.com/docs/en/sfhs/2.8.x?topic=installation-mirroring-your-images-enterprise-registry .

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
      -fdfv)
        FDF_VERSION=$1
        shift ;;
      -dest_as_tag_with_selfsigned_cert)
        DEST_TAG_SELF_CERT=$arg ;;
      -dest_as_tag)
        DEST_TAG=$arg ;;
      -dest_as_digest_with_selfsigned_cert)
        DEST_DIG_SELF_CERT=$arg ;;
      -dest_as_digest)
        DEST_DIG=$arg ;;
      -fusion)
          ISF=$arg ;;
      -gdp)
        GDP_IMAGES=$arg ;;
      -br)
        GUARDIAN_IMAGES=$arg ;;
      -dcs)
        DISCOVER_IMAGES=$arg ;;
      -fdf)
        FDF_IMAGES=$arg ;;
      -redhat)
        REDHAT_IMAGES=$arg ;;
      -ocp)
        OCP_IMAGES=$arg ;;
      -all)
        ALL_IMAGES=$arg ;;
      -validate)
        VALIDATE_IMAGES=$arg ;;
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
    if [[ $DEST_TAG = "-dest_as_tag" ]] || [[ $DEST_DIG = "-dest_as_digest" ]] ; then
      SKIPPODTLS="--tls-verify=false"
    fi
  fi
  for LOGIN_SRC_REG in ${IBM_REGISTRY} ${REDHAT_REGISTRY} ${QUAY_REGISTRY} ${LOCAL_ISF_REGISTRY}
  do
    DECODED_AUTH_VALUE=$(jq -r ".auths[\"$LOGIN_SRC_REG\"].auth" ${PULL_SECRET} | base64 -d)
    USERNAME=$(echo $DECODED_AUTH_VALUE | cut -d':' -f1)
    PASSWORD=$(echo $DECODED_AUTH_VALUE | cut -d':' -f2)
    echo "$CTOOL login $SKIPPODTLS -u $USERNAME -p $PASSWORD $LOGIN_SRC_REG 2>&1"
    $CTOOL login $SKIPPODTLS -u $USERNAME -p $PASSWORD $LOGIN_SRC_REG 2>&1
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
  if [[ $PRODUCT = "sds" ]] ; then
    IMAGE_LIST_JSON=./isf-281-sds-images.json
  else
    IMAGE_LIST_JSON=./isf-281-hci-images.json
  fi
  if [[ $? -ne 0 ]] ; then
		print error "Please make sure isf-281-hci-images.json & isf-281-sds-images.json files are in this folder"
		exit 1
	fi
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
    print error "Please make sure isf-281-hci-images.json or isf-281-sds-images.json files are in this folder"
    exit 1
  fi
}

function retry_command() {
    retry_cmd="$@"
    attempts=0
    while true; do
      print info "Trying command: $retry_cmd 2>&1 at attempt: $attempts"
      $retry_cmd 2>&1
      if [ $? -eq 0 ]; then
        print info "Retry of $retry_cmd 2>&1 at attempt: $attempts successful"
        break
      else
        if [ $attempts -eq "$max_retries" ]; then
          print error "Failed to execute command: $retry_cmd 2>&1 , Max retries reached 3"
          failedtocopy=1
          break
        fi
        if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
          print info "Retry of $retry_cmd 2>&1 at attempt: $attempts failed, Retrying in 20 seconds."
          sleep 20
        else
          print info "Retry of $retry_cmd 2>&1 at attempt: $attempts failed, Retrying in 15 seconds."
          sleep 15
        fi
        attempts=$((attempts+1))
      fi
    done
}

function get_kc_df_images() {
  # Function for mirroring Data Cataloging images
  print info "EXECUTING get_kc_df_images()"
  FDF="$(pwd)/DF_images.txt"
  echo -e "================= Skopeo Commands for FDF Images =================\n" >> ${FDF}
  MIRROR_LOG=${FDF}
  IFS=',' read -ra FDF_ARRAY <<< "$FDF_VERSION"
  for FDFV in "${FDF_ARRAY[@]}"
  do
    if [[ ${FDFV} != "4.16" ]]; then
      cat <<EOF > imageset-config-df.yaml
      kind: ImageSetConfiguration
      apiVersion: mirror.openshift.io/v1alpha2
      storageConfig:
        registry:
          imageURL: "$TARGET_PATH/isf-df-metadata:latest"
          skipTLS: true
      mirror:
        operators:
          - catalog: icr.io/cpopen/isf-data-foundation-catalog:v${FDFV}
            packages:
              - name: "mcg-operator"
              - name: "ocs-operator"
              - name: "odf-csi-addons-operator"
              - name: "odf-multicluster-orchestrator"
              - name: "odf-operator"
              - name: "odr-cluster-operator"
              - name: "odr-hub-operator"
              - name: "ocs-client-operator"
EOF
    else
      cat <<EOF > imageset-config-df.yaml
      kind: ImageSetConfiguration
      apiVersion: mirror.openshift.io/v1alpha2
      storageConfig:
        registry:
          imageURL: "$TARGET_PATH/isf-df-metadata:latest"
          skipTLS: true
      mirror:
        operators:
          - catalog: icr.io/cpopen/isf-data-foundation-catalog:v${FDFV}
            packages:
              - name: "mcg-operator"
              - name: "ocs-operator"
              - name: "odf-csi-addons-operator"
              - name: "odf-multicluster-orchestrator"
              - name: "odf-operator"
              - name: "odr-cluster-operator"
              - name: "odr-hub-operator"
              - name: "ocs-client-operator"
              - name: "odf-prometheus-operator"
              - name: "recipe"
              - name: "rook-ceph-operator"
EOF
    fi
    print info "executing get_kc_df_images for v${FDFV}"
    print info "imageset-config-df.yaml contents are:"
    cat imageset-config-df.yaml
    print info "retry_command oc mirror --config imageset-config-df.yaml docker://$TARGET_PATH --dest-skip-tls --ignore-history $SKIPOCMIRRORTLS" >> ${MIRROR_LOG}
    retry_command "oc mirror --config imageset-config-df.yaml docker://$TARGET_PATH --dest-skip-tls --ignore-history $SKIPOCMIRRORTLS"
    if [[ $? -ne 0 ]] ; then print error "Failed to execute retry_command oc mirror --config imageset-config-df.yaml docker://$TARGET_PATH --dest-skip-tls --ignore-history $SKIPOCMIRRORTLS"; failedtocopy=1; fi
  done
}

function get_kc_local_df_images() {
  # Function for mirroring Data Cataloging images
  print info "EXECUTING get_kc_local_df_images()"
  MIRROR_LOG=${FDF}
  echo -e "================= oc mirror for local storage operator FDF Images =================\n" >> ${FDF}
  IFS=',' read -ra FDF_ARRAY <<< "$FDF_VERSION"
  for FDFV in "${FDF_ARRAY[@]}"
  do
    cat << EOF > imageset-config-lso.yaml
    kind: ImageSetConfiguration
    apiVersion: mirror.openshift.io/v1alpha2
    storageConfig:
      registry:
        imageURL: "$TARGET_PATH/df/odf-lso-metadata:latest"
        skipTLS: true
    mirror:
      operators:
        - catalog: registry.redhat.io/redhat/redhat-operator-index:v${FDFV}
          packages:
            - name: "local-storage-operator"
            - name: "lvms-operator"
            - name: "kubernetes-nmstate-operator"
            - name: "redhat-oadp-operator"
            - name: "amq-streams"
            - name: "kubevirt-hyperconverged"
EOF
    print info "executing get_kc_local_df_images for v${FDFV}"
    print info "imageset-config-lso.yaml contents are:"
    cat imageset-config-lso.yaml
    print info "retry_command oc mirror --config imageset-config-lso.yaml docker://${TARGET_PATH} --dest-skip-tls --ignore-history $SKIPOCMIRRORTLS" >> ${MIRROR_LOG}
    retry_command "oc mirror --config imageset-config-lso.yaml docker://${TARGET_PATH} --dest-skip-tls --ignore-history $SKIPOCMIRRORTLS"
    if [[ $? -ne 0 ]] ; then print error "Failed to execute retry_command oc mirror --config imageset-config-lso.yaml docker://${TARGET_PATH} --dest-skip-tls --ignore-history $SKIPOCMIRRORTLS"; failedtocopy=1; fi
  done
}

function get_kc_redhat_external() {
  # Function for mirroring Redhat external images
  print info "EXECUTING get_kc_redhat_external()"
  REDHAT="$(pwd)/Redhat_images.txt"
  echo -e "================= Skopeo Commands for Redhat Images =================\n" >> ${REDHAT}
  MIRROR_LOG=${REDHAT}
  IFS=',' read -ra OCP_ARRAY <<< "$OCP_VERSION"
  for OCPV in "${OCP_ARRAY[@]}"
  do
    REDHAT_VERSION=$(echo $OCPV | cut -d'.' -f1,2)
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
    print info "executing get_kc_redhat_external for v${REDHAT_VERSION}"
    print info "imageset-redhat-external.yaml contents are:"
    cat imageset-redhat-external.yaml
    print info "retry_command oc mirror --config imageset-redhat-external.yaml docker://$TARGET_PATH --dest-skip-tls --ignore-history $SKIPOCMIRRORTLS" >> ${MIRROR_LOG}
    retry_command "oc mirror --config imageset-redhat-external.yaml docker://$TARGET_PATH --dest-skip-tls --ignore-history $SKIPOCMIRRORTLS"
    if [[ $? -ne 0 ]] ; then print error "Failed to execute retry_command oc mirror --config imageset-redhat-external.yaml docker://$TARGET_PATH --dest-skip-tls --ignore-history $SKIPOCMIRRORTLS"; failedtocopy=1; fi
  done
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
    if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
      DIGEST[i]=$(echo "${DIGEST[i]}" | sed 's/sha256//')
      IMAGE_URL="docker://${TARGET_PATH}/${INT_IMAGE[i]}${DIGEST[i]}"
    else
      IMAGE_URL="docker://${TARGET_PATH}/${INT_IMAGE[i]}@${DIGEST[i]}"
    fi
    if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GDP}
      if [[ "${INT_SERVICE[i]}" = "cnsa" ]] ; then
        if [[ "${INT_IMAGE[i]}" = "ibm-spectrum-scale-daemon" ]] || [[ "${INT_IMAGE[i]}" = "csi-snapshotter" ]] || [[ "${INT_IMAGE[i]}" = "csi-attacher" ]] || [[ "${INT_IMAGE[i]}" = "csi-provisioner" ]] || [[ "${INT_IMAGE[i]}" = "livenessprobe" ]] || [[ "${INT_IMAGE[i]}" = "csi-node-driver-registrar" ]] || [[ "${INT_IMAGE[i]}" = "csi-resizer" ]] || [[ "${INT_IMAGE[i]}" = "ibm-spectrum-scale-csi-driver" ]] ; then
          DEST_FOLDER=$(basename "$IMG_LOC")
          if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
            IMAGE_URL="docker://${TARGET_PATH}/${DEST_FOLDER}/${INT_IMAGE[i]}${DIGEST[i]}"
          else
            IMAGE_URL="docker://${TARGET_PATH}/${DEST_FOLDER}/${INT_IMAGE[i]}@${DIGEST[i]}"
          fi
        fi
        echo "retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS" >> ${MIRROR_LOG}
        retry_command "skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"
        if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"; failedtocopy=1; fi
      fi
    fi
    if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GUARDIAN}
      if [[ $CATALOGMIRROR != "-catalogmirror" ]] ; then
        if [[ "${INT_SERVICE[i]}" = "backup-restore-agent" ]] || [[ "${INT_SERVICE[i]}" = "backup-restore-server" ]] ; then
          echo "retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS" >> ${MIRROR_LOG}
          retry_command "skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"
          if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"; failedtocopy=1; fi
        fi
      fi
    fi
    if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${FUSION}
      if [[ $CATALOGMIRROR != "-catalogmirror" ]] ; then
        if [[ "${INT_SERVICE[i]}" = "fusion" ]] ; then
          if [[ ${INT_IMAGE[i]} = "isf-operator-software-catalog" ]] ; then
            echo -e "retry_command skopeo copy --insecure-policy --preserve-digests --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION} docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION} $SKIPTLS\n" >> ${MIRROR_LOG}
            retry_command "skopeo copy --insecure-policy --preserve-digests --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION} docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION} $SKIPTLS"
            if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION} docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION} $SKIPTLS"; failedtocopy=1; fi
          elif [[ ${INT_IMAGE[i]} = "isf-operator-catalog" ]] ; then
            echo -e "retry_command skopeo copy --insecure-policy --preserve-digests --all docker://$IMG_LOC/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64 docker://\$TARGET_PATH/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64 $SKIPTLS\n" >> ${MIRROR_LOG}
            retry_command "skopeo copy --insecure-policy --preserve-digests --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64 docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64 $SKIPTLS"
            if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all docker://${IMG_LOC}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64 docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64 $SKIPTLS"; failedtocopy=1; fi
          else
            echo "retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS" >> ${MIRROR_LOG}
            retry_command "skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"
            if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"; failedtocopy=1; fi
          fi
        fi
      fi
    fi
  done
}

function mirror_megabom_external_images() {
  # Function for mirroring external images from megabom
  print info "EXECUTING mirror_megabom_external_images()"
  for ((i=0; i<${#EXT_IMAGE[@]}; i++)); do
    SOURCE_IMAGE="docker://${EXT_IMAGE[i]}"
    DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|.*/|/|')
    if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
      DEST_IMAGE=$(echo "${DEST_IMAGE}" | sed 's/@sha256//')
    fi
    IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
    if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GDP}
      if [[ "${EXT_SERVICE[i]}" = "cnsa" ]] ; then
        echo "retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS" >> ${MIRROR_LOG}
        retry_command "skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"
        if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"; failedtocopy=1; fi
      fi
    fi
    if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GUARDIAN}
      if [[ $CATALOGMIRROR != "-catalogmirror" ]] ; then
        if [[ "${EXT_SERVICE[i]}" = "backup-restore-agent" ]] || [[ "${EXT_SERVICE[i]}" = "backup-restore-server" ]] ; then
          if [[ ${EXT_IMAGE[i]} = *"ose-kube-rbac-proxy"* ]] ; then
            DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|[^/]*/|/|')
            if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
              DEST_IMAGE=$(echo "${DEST_IMAGE}" | sed 's/@sha256//')
            fi
            IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
            echo "retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS" >> ${MIRROR_LOG}
            retry_command "skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"
            if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"; failedtocopy=1; fi
          fi
          if [[ ${EXT_IMAGE[i]} = *"redis-7"* ]] ; then
            DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|[^/]*/|/|')
            if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
              DEST_IMAGE=$(echo "${DEST_IMAGE}" | sed 's/@sha256//')
            fi
            IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
            echo "retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS" >> ${MIRROR_LOG}
            retry_command "skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"
            if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"; failedtocopy=1; fi
          fi
          echo "retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS" >> ${MIRROR_LOG}
          retry_command "skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"
          if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"; failedtocopy=1; fi
        fi
      fi
    fi
    if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${FUSION}
      if [[ $CATALOGMIRROR != "-catalogmirror" ]] ; then
        if [[ "${EXT_SERVICE[i]}" = "fusion" ]] ; then
          if [[ ${EXT_IMAGE[i]} = *"ose-kube-rbac-proxy"* ]] ; then
            SRC_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|.*/||')
            if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
              SRC_IMAGE=$(echo "${SRC_IMAGE}" | sed 's/@sha256//')
            fi
            echo "retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)openshift4-$SRC_IMAGE $SKIPTLS" >> ${MIRROR_LOG}
            retry_command "skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)openshift4-$SRC_IMAGE $SKIPTLS"
            if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)openshift4-$SRC_IMAGE $SKIPTLS"; failedtocopy=1; fi
          fi
          DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|[^/]*/|/|')
          if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
            DEST_IMAGE=$(echo "${DEST_IMAGE}" | sed 's/@sha256//')
          fi
          IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
          echo "retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS" >> ${MIRROR_LOG}
          retry_command "skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"
          if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --insecure-policy --preserve-digests --all $SOURCE_IMAGE $IMAGE_URL $SKIPTLS"; failedtocopy=1; fi
        fi
      fi
    fi
  done
}

function mirror_submariner_images () {
  # Hard Coding the copy commands for submariner images
  # Can be removed if the images are added to the megabom
  print info "EXECUTING mirror_submariner_images()"
  echo "skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-operator:0.16.3 docker://$TARGET_PATH/submariner/submariner-operator:0.16.3 $SKIPTLS" >> "$FUSION"
  echo "retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-operator:0.16.3 docker://$TARGET_PATH/submariner/submariner-operator:0.16.3 $SKIPTLS" >> "$FUSION"
  retry_command "skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-operator:0.16.3 docker://$TARGET_PATH/submariner/submariner-operator:0.16.3 $SKIPTLS"
  if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-operator:0.16.3 docker://$TARGET_PATH/submariner/submariner-operator:0.16.3 $SKIPTLS"; failedtocopy=1; fi
  echo "retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-gateway:0.16.3 docker://$TARGET_PATH/submariner/submariner-gateway:0.16.3 $SKIPTLS" >> "$FUSION"
  retry_command "skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-gateway:0.16.3 docker://$TARGET_PATH/submariner/submariner-gateway:0.16.3 $SKIPTLS"
  if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-operator:0.16.3 docker://$TARGET_PATH/submariner/submariner-operator:0.16.3 $SKIPTLS"; failedtocopy=1; fi
  echo "retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/lighthouse-agent:0.16.3 docker://$TARGET_PATH/submariner/lighthouse-agent:0.16.3 $SKIPTLS" >> "$FUSION"
  retry_command "skopeo copy --all --preserve-digests docker://quay.io/submariner/lighthouse-agent:0.16.3 docker://$TARGET_PATH/submariner/lighthouse-agent:0.16.3 $SKIPTLS"
  if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/lighthouse-agent:0.16.3 docker://$TARGET_PATH/submariner/lighthouse-agent:0.16.3 $SKIPTLS"; failedtocopy=1; fi
  echo "retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/lighthouse-coredns:0.16.3 docker://$TARGET_PATH/submariner/lighthouse-coredns:0.16.3 $SKIPTLS" >> "$FUSION"
  retry_command "skopeo copy --all --preserve-digests docker://quay.io/submariner/lighthouse-coredns:0.16.3 docker://$TARGET_PATH/submariner/lighthouse-coredns:0.16.3 $SKIPTLS"
  if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/lighthouse-coredns:0.16.3 docker://$TARGET_PATH/submariner/lighthouse-coredns:0.16.3 $SKIPTLS"; failedtocopy=1; fi
  echo "retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-route-agent:0.16.3 docker://$TARGET_PATH/submariner/submariner-route-agent:0.16.3 $SKIPTLS" >> "$FUSION"
  retry_command "skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-route-agent:0.16.3 docker://$TARGET_PATH/submariner/submariner-route-agent:0.16.3 $SKIPTLS"
  if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/submariner-route-agent:0.16.3 docker://$TARGET_PATH/submariner/submariner-route-agent:0.16.3 $SKIPTLS"; failedtocopy=1; fi
  echo "retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/nettest:0.16.3 docker://$TARGET_PATH/submariner/nettest:0.16.3 $SKIPTLS" >> "$FUSION"
  retry_command "skopeo copy --all --preserve-digests docker://quay.io/submariner/nettest:0.16.3 docker://$TARGET_PATH/submariner/nettest:0.16.3 $SKIPTLS"
  if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --all --preserve-digests docker://quay.io/submariner/nettest:0.16.3 docker://$TARGET_PATH/submariner/nettest:0.16.3 $SKIPTLS"; failedtocopy=1; fi
  echo "retry_command skopeo copy --all --preserve-digests docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1 docker://$TARGET_PATH/kubebuilder/kube-rbac-proxy:v0.13.1 $SKIPTLS" >> "$FUSION"
  retry_command "skopeo copy --all --preserve-digests docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1 docker://$TARGET_PATH/kubebuilder/kube-rbac-proxy:v0.13.1 $SKIPTLS"
  if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --all --preserve-digests docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1 docker://$TARGET_PATH/kubebuilder/kube-rbac-proxy:v0.13.1 $SKIPTLS"; failedtocopy=1; fi
  echo "retry_command skopeo copy --all --preserve-digests docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1 docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)kubebuilder-kube-rbac-proxy:v0.13.1 $SKIPTLS" >> "$FUSION"
  retry_command "skopeo copy --all --preserve-digests docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1 docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)kubebuilder-kube-rbac-proxy:v0.13.1 $SKIPTLS"
  if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command skopeo copy --all --preserve-digests docker://gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1 docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)kubebuilder-kube-rbac-proxy:v0.13.1 $SKIPTLS"; failedtocopy=1; fi
}

function mirror_ocp_images() {
  # Function to mirror the ocp images
  print info "EXECUTING mirror_ocp_images()"
  OCP="$(pwd)/OCP_images.txt"
  echo -e "================= Skopeo Commands for OCP Images =================\n" >> ${OCP}
  MIRROR_LOG=${OCP}
  IFS=',' read -ra OCP_ARRAY <<< "$OCP_VERSION"
  for OCPV in "${OCP_ARRAY[@]}"
  do
    print info "executing mirror_ocp_images for v${OCPV}"
    echo "retry_command oc adm release mirror -a ${PULL_SECRET} --from=quay.io/openshift-release-dev/ocp-release:${OCPV}-x86_64 --to=$TARGET_PATH --to-release-image=$TARGET_PATH:${OCPV}-x86_64 $SKIPOCPTLS" >> ${MIRROR_LOG}
    retry_command "oc adm release mirror -a ${PULL_SECRET} --from=quay.io/openshift-release-dev/ocp-release:${OCPV}-x86_64 --to=$TARGET_PATH --to-release-image=$TARGET_PATH:${OCPV}-x86_64 $SKIPOCPTLS"
    if [[ $? -ne 0 ]] ; then print error "Failed to copy retry_command oc adm release mirror -a ${PULL_SECRET} --from=quay.io/openshift-release-dev/ocp-release:${OCPV}-x86_64 --to=$TARGET_PATH --to-release-image=$TARGET_PATH:${OCPV}-x86_64 $SKIPOCPTLS"; failedtocopy=1; fi
  done
}

function data_cataloging_catalog_mirror() {
  # Function for mirroring catalog based Data cataloging images
  print info "EXECUTING data_cataloging_catalog_mirror()"
  MIRROR_LOG=${DISCOVER}
  echo -e "================= Commands for Data Cataloging Images =================\n" >> ${DISCOVER}
  cat << EOF > imagesetconfiguration_dcs.yaml
  kind: ImageSetConfiguration
  apiVersion: mirror.openshift.io/v1alpha2
  storageConfig:
    registry:
      imageURL: "${TARGET_PATH}/isf-dcs-metadata:latest"
      skipTLS: true
  mirror:
    operators:
      - catalog: "oci:///tmp/dcs_catalog"
        packages:
          - name: "ibm-spectrum-discover-operator"
      - catalog: icr.io/cpopen/ibm-operator-catalog:latest
        packages:
          - name: "db2u-operator"
            channels:
              - name: "v110509.0"
    additionalImages:
      - name: icr.io/db2u/db2u@sha256:91627bc7259d06f08ca1dda64c94fadeeaa3489e3d698968fecbfb23f149da8f
      - name: icr.io/db2u/db2u.restricted@sha256:81495ca6d7f7dd6c91c82837b20f855c0b945190f950ea20839bec7b9225f9a4
      - name: icr.io/db2u/db2u.db2wh@sha256:468559121358b46c11ec31e723d9dab3f503c417edb8b43b60c6d16056e6d6e8
      - name: icr.io/db2u/db2u.dv.api@sha256:779d08c24297fca720814e64d102356d9882522ea6daf4866c589ec0f6de2372
      - name: icr.io/db2u/db2u.dv.caching@sha256:d69928fdbad9d287896127176a863f0e0d9b6814719e826460725e363cc66deb
      - name: icr.io/db2u/db2u.dv.utils@sha256:9fea3bb80d5e7a87b28a2dc04afe4d49263ab16b4f018b5521f7ae03c64bd221
      - name: icr.io/db2u/etcd@sha256:3bcc3595cb3c3b2ea016a8394fa1e56b31b9b4d57ef20bd1a48e106e5b391b93
      - name: icr.io/db2u/db2u.logstreaming.fluentd@sha256:85c2a09ff908113eafe871a2cb759d74f2ff1ca653519fefd11801e4d096adb4
      - name: icr.io/db2u/db2u.hurricane@sha256:48c97b818eafd19dc452128ca897592a47c7bd7fed34a5413d9ec733742f3445
      - name: icr.io/db2u/db2u.instdb@sha256:47d3a39acd3ed5e9f05c9a014ca771bfc7daff5001f747876aaf4ca55e9c126c
      - name: icr.io/db2u/db2u.instdb.restricted@sha256:e9360ddb23c4c01a6c4d752e20c37cbeb1517f45c31223d7fb880224ac0c8516
      - name: icr.io/db2u/db2u.auxiliary.auth@sha256:1788efcf35d4b17293953efe2d808daa318e49d0c45cbf22c658a477bcd8b901
      - name: icr.io/db2u/db2u.mustgather@sha256:3fa70f0ebd5f21d93881f5c2a85b985bbf257dfebcf9218ac2b29b647d59d117
      - name: icr.io/db2u/db2u.qrep@sha256:b5b5e7dca205e907ab6ee54efeb00e3665cde1cbfcb04561c01f6d09e56d2714
      - name: icr.io/db2u/db2u.rest@sha256:a6bc412bb0c7917a8fc9c0578d3e42f3578bebfd014c80368a1969cb2cebfa9a
      - name: icr.io/db2u/db2u.update.image@sha256:f6260e6eef8d1432b19353e37b29c4532c08879d3c508b3ba79a8848612bbf21
      - name: icr.io/db2u/db2u.tools@sha256:0c7ce0dd872b900a8a44a7347fad46c471cb3e4e40b87c0eb61ec4de8a1c6838
      - name: icr.io/db2u/db2u.veleroplugin@sha256:e35c931ff7d375cbd5c6a7f5ef80379ee3f766f2bb644eccd11e1498ffec2d00
      - name: icr.io/db2u/db2u.watsonquery@sha256:fa4baca4cded68a9cbb9cc41920274c1d36ef0be2256a7cbd3e9b485a9cf2608
EOF

  print info "retry_command skopeo --override-os=linux copy docker://icr.io/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 oci:///tmp/dcs_catalog --format v2s2 $SKIPTLS" >> ${MIRROR_LOG}
  retry_command "skopeo --override-os=linux copy docker://icr.io/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 oci:///tmp/dcs_catalog --format v2s2 $SKIPTLS"
  if [[ $? -ne 0 ]] ; then print error "Failed to execute retry_command skopeo --override-os=linux copy docker://icr.io/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 oci:///tmp/dcs_catalog --format v2s2 $SKIPTLS"; failedtocopy=1; fi
  if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
    print info "retry_command skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 docker://${TARGET_PATH}/cpopen/ibm-spectrum-discover-operator-catalog:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 $SKIPTLS" >> ${MIRROR_LOG}
    retry_command "skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 docker://${TARGET_PATH}/cpopen/ibm-spectrum-discover-operator-catalog:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 $SKIPTLS"
    if [[ $? -ne 0 ]] ; then print error "Failed to execute retry_command skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 docker://${TARGET_PATH}/cpopen/ibm-spectrum-discover-operator-catalog:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 $SKIPTLS"; failedtocopy=1; fi
    print info "retry_command skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-operator-catalog@sha256:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a docker://${TARGET_PATH}/ibm-operator-catalog:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a $SKIPTLS" >> ${MIRROR_LOG}
    retry_command "skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-operator-catalog@sha256:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a docker://${TARGET_PATH}/ibm-operator-catalog:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a $SKIPTLS"
    if [[ $? -ne 0 ]] ; then print error "Failed to execute retry_command skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-operator-catalog@sha256:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a docker://${TARGET_PATH}/ibm-operator-catalog:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a $SKIPTLS"; failedtocopy=1; fi
  else
    print info "retry_command skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 docker://${TARGET_PATH}/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 $SKIPTLS" >> ${MIRROR_LOG}
    retry_command "skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 docker://${TARGET_PATH}/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 $SKIPTLS"
    if [[ $? -ne 0 ]] ; then print error "Failed to execute retry_command skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 docker://${TARGET_PATH}/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619 $SKIPTLS"; failedtocopy=1; fi
    print info "retry_command skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-operator-catalog@sha256:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a docker://${TARGET_PATH}/ibm-operator-catalog@sha256:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a $SKIPTLS" >> ${MIRROR_LOG}
    retry_command "skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-operator-catalog@sha256:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a docker://${TARGET_PATH}/ibm-operator-catalog@sha256:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a $SKIPTLS"
    if [[ $? -ne 0 ]] ; then print error "Failed to execute retry_command skopeo --override-os=linux copy --all docker://icr.io/cpopen/ibm-operator-catalog@sha256:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a docker://${TARGET_PATH}/ibm-operator-catalog@sha256:5d606e4eb2b875e0b975f892e80343105ea5fb0d67f96e1400d77a715f6df72a $SKIPTLS"; failedtocopy=1; fi
  fi

  cat << EOF > registries_dcs.conf
  [[registry]]
    location = "icr.io/cp/ibm-spectrum-discover"
    insecure = false
    blocked = false
    mirror-by-digest-only = true
    prefix = ""

    [[registry.mirror]]
      location = "cp.icr.io/cp/ibm-spectrum-discover"
      insecure = false
EOF

print info "imagesetconfiguration_dcs.yaml contents are:"
cat ./imagesetconfiguration_dcs.yaml
print info "registries_dcs.conf contents are:"
cat ./registries_dcs.conf
print info "retry_command oc mirror --config ./imagesetconfiguration_dcs.yaml docker://${TARGET_PATH} --dest-skip-tls --ignore-history --oci-registries-config ./registries_dcs.conf $SKIPOCMIRRORTLS" >> ${MIRROR_LOG}
retry_command "oc mirror --config ./imagesetconfiguration_dcs.yaml docker://${TARGET_PATH} --dest-skip-tls --ignore-history --oci-registries-config ./registries_dcs.conf $SKIPOCMIRRORTLS"
if [[ $? -ne 0 ]] ; then print error "Failed to execute retry_command oc mirror --config ./imagesetconfiguration_dcs.yaml docker://${TARGET_PATH} --dest-skip-tls --ignore-history --oci-registries-config ./registries_dcs.conf $SKIPOCMIRRORTLS"; failedtocopy=1; fi
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
  if [[ ($ALL_IMAGES = "-all" || $ISF = "-fusion") && $PRODUCT = "hci" ]] ; then
    mirror_submariner_images
  fi
  mirror_internal_images
  if [[ $DISCOVER_IMAGES = "-dcs" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    data_cataloging_catalog_mirror
  fi
  if [[ $FDF_IMAGES = "-fdf" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
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
    if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
      DIGEST[i]=$(echo "${DIGEST[i]}" | sed 's/sha256//')
      IMAGE_URL="docker://${TARGET_PATH}/${INT_IMAGE[i]}${DIGEST[i]}"
    else
      IMAGE_URL="docker://${TARGET_PATH}/${INT_IMAGE[i]}@${DIGEST[i]}"
    fi
    if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GDP}
      if [[ "${INT_SERVICE[i]}" = "cnsa" ]] ; then
        if [[ "${INT_IMAGE[i]}" = "ibm-spectrum-scale-daemon" ]] || [[ "${INT_IMAGE[i]}" = "csi-snapshotter" ]] || [[ "${INT_IMAGE[i]}" = "csi-attacher" ]] || [[ "${INT_IMAGE[i]}" = "csi-provisioner" ]] || [[ "${INT_IMAGE[i]}" = "livenessprobe" ]] || [[ "${INT_IMAGE[i]}" = "csi-node-driver-registrar" ]] || [[ "${INT_IMAGE[i]}" = "csi-resizer" ]] || [[ "${INT_IMAGE[i]}" = "ibm-spectrum-scale-csi-driver" ]] ; then
          DEST_FOLDER=$(basename "$IMG_LOC")
          if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
            IMAGE_URL="docker://${TARGET_PATH}/${DEST_FOLDER}/${INT_IMAGE[i]}${DIGEST[i]}"
          else
            IMAGE_URL="docker://${TARGET_PATH}/${DEST_FOLDER}/${INT_IMAGE[i]}@${DIGEST[i]}"
          fi
        fi
        echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
        skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
        if [[ $? -ne 0 ]] ; then
          echo -e "skopeo inspect ${IMAGE_URL} $SKIPTLS 2>&1\n" >> ${MISSING_IMAGES}
          failedtocopy=1
        else
          if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
            echo -e "${INT_IMAGE[i]}${DIGEST[i]} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
          else
            echo -e "${INT_IMAGE[i]}@${DIGEST[i]} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
          fi
        fi
      fi
    fi
    if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GUARDIAN}
      if [[ $CATALOGMIRROR != "-catalogmirror" ]] ; then
        if [[ "${INT_SERVICE[i]}" = "backup-restore-agent" ]] || [[ "${INT_SERVICE[i]}" = "backup-restore-server" ]] ; then
          echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
          skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
          if [[ $? -ne 0 ]] ; then
            echo -e "skopeo inspect ${IMAGE_URL} 2>&1\n" >> ${MISSING_IMAGES}
            failedtocopy=1
          else
            if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
              echo -e "${INT_IMAGE[i]}${DIGEST[i]} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
            else
              echo -e "${INT_IMAGE[i]}@${DIGEST[i]} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
            fi
          fi
        fi
      fi
    fi
    if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${FUSION}
      if [[ $CATALOGMIRROR != "-catalogmirror" ]] ; then
        if [[ "${INT_SERVICE[i]}" = "fusion" ]] ; then
          if [[ ${INT_IMAGE[i]} = "isf-operator-software-catalog" ]] ; then
            IMAGE_URL="docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}"
          elif [[ ${INT_IMAGE[i]} = "isf-operator-catalog" ]] ; then
            IMAGE_URL="docker://${TARGET_PATH}/${INT_IMAGE[i]}:${ISF_VERSION}-linux.amd64"
          fi
          echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
          skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
          if [[ $? -ne 0 ]] ; then
            echo -e "skopeo inspect ${IMAGE_URL} $SKIPTLS 2>&1\n" >> ${MISSING_IMAGES}
            failedtocopy=1
          else
            if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
              echo -e "${INT_IMAGE[i]}${DIGEST[i]} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
            else
              echo -e "${INT_IMAGE[i]}@${DIGEST[i]} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
            fi
          fi
        fi
      fi
    fi
  done
  # Loop through the EXTERNAL images and validate them
  for ((i=0; i<${#EXT_IMAGE[@]}; i++)); do
    EXT_CNT=$(($i + 1))
    echo VALIDATING EXTERNAL IMAGE [${EXT_CNT}/${#EXT_SERVICE[@]}]....${EXT_IMAGE[i]}
    #SOURCE_IMAGE="docker://${EXT_IMAGE[i]}"
    #DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed "s|${EXT_PARENT_LOC[i]}||")
    DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|.*/|/|')
    if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
      DEST_IMAGE=$(echo "${DEST_IMAGE}" | sed 's/@sha256//')
    fi
    IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
    if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GDP}
      if [[ "${EXT_SERVICE[i]}" = "cnsa" ]] ; then
        echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
        skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
        if [[ $? -ne 0 ]] ; then
          echo -e "${IMAGE_URL} $SKIPTLS \n" >> ${MISSING_IMAGES}
          failedtocopy=1
        else
          echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
        fi
      fi
    fi
    if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${GUARDIAN}
      if [[ $CATALOGMIRROR != "-catalogmirror" ]] ; then
        if [[ "${EXT_SERVICE[i]}" = "backup-restore-agent" ]] || [[ "${EXT_SERVICE[i]}" = "backup-restore-server" ]] ; then
          if [[ ${EXT_IMAGE[i]} = *"ose-kube-rbac-proxy"* ]] ; then
            DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|[^/]*/|/|')
            if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
              DEST_IMAGE=$(echo "${DEST_IMAGE}" | sed 's/@sha256//')
            fi
            IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
            echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
            skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
            if [[ $? -ne 0 ]] ; then
              echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
              failedtocopy=1
            else
              echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
            fi
          fi
          if [[ ${EXT_IMAGE[i]} = *"redis-7"* ]] ; then
            DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|[^/]*/|/|')
            if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
              DEST_IMAGE=$(echo "${DEST_IMAGE}" | sed 's/@sha256//')
            fi
            IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
            echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
            skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
            if [[ $? -ne 0 ]] ; then
              echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
              failedtocopy=1
            else
              echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
            fi
          fi
          echo "skopeo inspect $IMAGE_URL $SKIPTLS"
          skopeo inspect $IMAGE_URL $SKIPTLS
          if [[ $? -ne 0 ]] ; then
            echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
            failedtocopy=1
          else
            echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
          fi
        fi
      fi
    fi
    if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
      MIRROR_LOG=${FUSION}
      if [[ $CATALOGMIRROR != "-catalogmirror" ]] ; then
        if [[ "${EXT_SERVICE[i]}" = "fusion" ]] ; then
          if [[ ${EXT_IMAGE[i]} = *"ose-kube-rbac-proxy"* ]] ; then
            SRC_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|.*/||')
            if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
              SRC_IMAGE=$(echo "${SRC_IMAGE}" | sed 's/@sha256//')
            fi
            IMAGE_URL="docker://$LOCAL_ISF_REGISTRY/$NAMESPACE/$(echo $REPO_PREFIX)openshift4-$SRC_IMAGE"
            echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
            skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
            if [[ $? -ne 0 ]] ; then
              echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
              failedtocopy=1
            else
              echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
            fi
          else
            DEST_IMAGE=$(echo "${EXT_IMAGE[i]}" | sed 's|[^/]*/|/|')
            if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
              DEST_IMAGE=$(echo "${DEST_IMAGE}" | sed 's/@sha256//')
            fi
            IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
            echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
            skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
            if [[ $? -ne 0 ]] ; then
              echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
              failedtocopy=1
            else
              echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
            fi
          fi
        fi
      fi
    fi
  done
  # Loop through the Redhat images and validate them
  if [[ $REDHAT_IMAGES = "-redhat" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    MIRROR_LOG=${REDHAT}
    IFS=',' read -ra OCP_ARRAY <<< "$OCP_VERSION"
    for OCPV in "${OCP_ARRAY[@]}"
    do
      REDHAT_VERSION=$(echo $OCPV | cut -d'.' -f1,2)
      DEST_IMAGE=/redhat/redhat-operator-index:v${REDHAT_VERSION}
      IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
      echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
      skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
      if [[ $? -ne 0 ]] ; then
        echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
        failedtocopy=1
      else
        echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
      fi
    done
  fi
  # Loop through the OCP images and validate them
  if [[ $OCP_IMAGES = "-ocp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    MIRROR_LOG=${OCP}
    IFS=',' read -ra OCP_ARRAY <<< "$OCP_VERSION"
    for OCPV in "${OCP_ARRAY[@]}"
    do
      DEST_IMAGE="$(oc adm release info quay.io/openshift-release-dev/ocp-release:${OCPV}-x86_64 | sed -n 's/Pull From: .*@//p')"
      IMAGE_URL="docker://${TARGET_PATH}@${DEST_IMAGE}"
      echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
      skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
      if [[ $? -ne 0 ]] ; then
        echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
        failedtocopy=1
      else
        echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
      fi
    done
  fi
  # Loop through the FDF images and validate them
  if [[ $FDF_IMAGES = "-fdf" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    MIRROR_LOG=${FDF}
    IFS=',' read -ra FDF_ARRAY <<< "$FDF_VERSION"
    for FDFV in "${FDF_ARRAY[@]}"
    do
      DEST_IMAGE=/cpopen/isf-data-foundation-catalog:v${FDFV}
      IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
      echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
      skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
      if [[ $? -ne 0 ]] ; then
        echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
        failedtocopy=1
      else
        echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
      fi
    done
    # Loop through the local storage operator FDF Images and validate them
    IFS=',' read -ra FDF_ARRAY <<< "$FDF_VERSION"
    for FDFV in "${FDF_ARRAY[@]}"
    do
      DEST_IMAGE=/redhat/redhat-operator-index:v${FDFV}
      IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
      echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
      skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
      if [[ $? -ne 0 ]] ; then
        echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
        failedtocopy=1
      else
        echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
      fi
    done
  fi
  # Loop through the DCS images and validate them
  if [[ $DISCOVER_IMAGES = "-dcs" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
    MIRROR_LOG=${DISCOVER}
    if [[ $DEST_TAG_SELF_CERT = "-dest_as_tag_with_selfsigned_cert" ]] || [[ $DEST_TAG = "-dest_as_tag" ]] ; then
      DEST_IMAGE=/cpopen/ibm-spectrum-discover-operator-catalog:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619
    else
      DEST_IMAGE=/cpopen/ibm-spectrum-discover-operator-catalog@sha256:e99cd9c968fcf04e4c91f6869b6a952bd6cd725f44361f1c6331f194f449b619
    fi
    IMAGE_URL="docker://${TARGET_PATH}${DEST_IMAGE}"
    echo "skopeo inspect $IMAGE_URL $SKIPTLS 2>&1"
    skopeo inspect $IMAGE_URL $SKIPTLS 2>&1
    if [[ $? -ne 0 ]] ; then
      echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${MISSING_IMAGES}
      failedtocopy=1
    else
      echo -e "${IMAGE_URL} $SKIPTLS\n" >> ${AVAILABLE_IMAGES}
    fi
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
max_retries=3
if [[ $DEST_TAG = "-dest_as_tag" ]] || [[ $DEST_DIG = "-dest_as_digest" ]] ; then
  SKIPOCPTLS="--insecure=true"
  SKIPOCMIRRORTLS="--skip-verification"
  SKIPTLS="--tls-verify=false"
fi

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
	print info "No $ISF_VERSION -isf is provided, using 2.8.1 as default"
	ISF_VERSION="2.8.1"
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

if [[ $REDHAT_IMAGES = "-redhat" ]] || [[ $OCP_IMAGES = "-ocp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  [[  -z "$OCP_VERSION" ]] && usage
fi

if [[ $FDF_IMAGES = "-fdf" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  [[  -z "$FDF_VERSION" ]] && usage
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
if [[ $VALIDATE_IMAGES != "-validate" ]]; then
  mirror_images
fi

#Validating the Images
validate_images

if [[ $ISF = "-fusion" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${FUSION}
  rm -f ${FUSION}
fi
if [[ $GDP_IMAGES = "-gdp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${GDP}
  rm -f ${GDP}
fi
if [[ $GUARDIAN_IMAGES = "-br" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${GUARDIAN}
  rm -f ${GUARDIAN}
fi
if [[ $DISCOVER_IMAGES = "-dcs" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${DISCOVER}
  rm -f ${DISCOVER}
fi
if [[ $REDHAT_IMAGES = "-redhat" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${REDHAT}
  rm -f ${REDHAT}
fi
if [[ $FDF_IMAGES = "-fdf" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${FDF}
  rm -f ${FDF}
fi
if [[ $OCP_IMAGES = "-ocp" ]] || [[ $ALL_IMAGES = "-all" ]] ; then
  cat ${OCP}
  rm -f ${OCP}
fi

echo "These are the available images: "
cat ${AVAILABLE_IMAGES}
rm -f ${AVAILABLE_IMAGES}

echo "These are the missing images: "
cat ${MISSING_IMAGES}
rm -f ${MISSING_IMAGES}

if [[ $failedtocopy -ne 1  ]] ; then
  if [[ $VALIDATE_IMAGES = "-validate" ]]; then
    print info "VALIDATION DONE Successfully!!!"
  else
    print info "MIRRORING DONE Successfully!!!"
  fi
  exit 0
else
  if [[ $VALIDATE_IMAGES = "-validate" ]]; then
    print error "Failed to validate some images, please check for the error in nohup.out or missing_img.txt !!!"
  else
    print error "Failed to mirror some images, please check for the error in nohup.out or missing_img.txt !!!"
  fi
  exit 1
fi
