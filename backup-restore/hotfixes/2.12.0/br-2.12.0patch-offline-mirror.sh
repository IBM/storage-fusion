#!/bin/bash

usage() {
    echo "Usage: ${0} <image repository> <log file>]"
}

OADP_VELERO_14=fbr-velero@sha256:379a6d6a6dbe78fd09c3aa91b2f3fb44dff514ff5d62a1654cc1b3a126b8aee9

# build icr path from the docker image path
build_icr_path() {
  echo "cp.icr.io/cp/bnr/${1}"
}

# copy images from icr to local repository
copy_images() {
  TARGET_PATH=${1}
  for IMAGE in "${IMAGES[@]}"; do
    DESTINATION=docker://$TARGET_PATH/cp/bnr/$IMAGE
    echo -e "Copying\n Image: $(build_icr_path ${IMAGE})\n Destination: docker://$TARGET_PATH/cp/bnr/$IMAGE\n"
    skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/$IMAGE $DESTINATION
  done

  for FUSIONHCIIMAGE in "${FUSIONIMAGES_HCI[@]}"; do
    DESTINATION=docker://$TARGET_PATH/cp/fusion-hci/$FUSIONHCIIMAGE
    echo -e "Copying\n Image: $(build_icr_path ${FUSIONHCIIMAGE})\n Destination: docker://$TARGET_PATH/cp/fusion-hci/$FUSIONHCIIMAGE\n"
    skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fusion-hci/"$FUSIONHCIIMAGE" "$DESTINATION"
  done

  for FUSIONSDSIMAGE in "${FUSIONIMAGES_SDS[@]}"; do
    DESTINATION=docker://$TARGET_PATH/cp/fusion-sds/$FUSIONSDSIMAGE
    echo -e "Copying\n Image: $(build_icr_path ${FUSIONSDSIMAGE})\n Destination: docker://$TARGET_PATH/cp/fusion-sds/$FUSIONSDSIMAGE\n"
    skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fusion-sds/"$FUSIONSDSIMAGE" "$DESTINATION"
  done
}

declare -a IMAGES=(
  $OADP_VELERO_14
)

declare -a FUSIONIMAGES_HCI=()

declare -a FUSIONIMAGES_SDS=()

ICR_IMAGE_PATHS=()

for IMAGE in "${FUSIONIMAGES_HCI[@]}"; do
  ICR_PATH=
  ICR_IMAGE_PATHS+=($(build_icr_path ${IMAGE}))
done

for IMAGE in "${IMAGES[@]}"; do
  ICR_PATH=
  ICR_IMAGE_PATHS+=($(build_icr_path ${IMAGE}))
done

for IMAGE in "${FUSIONIMAGES_SDS[@]}"; do
  ICR_PATH=
  ICR_IMAGE_PATHS+=($(build_icr_path ${IMAGE}))
done

# execution when copying images rather than as image path source
if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  if [ -z "${1}" ]; then
     usage
     exit 1
  fi

  if [ -z "${2}" ]; then
    LOG=/tmp/$(basename $0)_log.txt
  else
    LOG=${2}
  fi
  
  touch ${LOG}
  exec &> >(tee -a $LOG)
  echo -e "Logging to $LOG\n"
  set -e

  copy_images ${1}
fi