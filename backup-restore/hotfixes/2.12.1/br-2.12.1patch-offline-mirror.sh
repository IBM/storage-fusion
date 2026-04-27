#!/bin/bash

usage() {
    echo "Usage: ${0} <image repository>"
}

BNR_PREFIX="cp.icr.io/cp/bnr"
HCI_PREFIX="cp.icr.io/cp/fusion-hci"
SDS_PREFIX="cp.icr.io/cp/fusion-sds"
CPOPEN_PREFIX="icr.io/cpopen"

TRANSACTIONMANAGER=guardian-transaction-manager@sha256:38dce505864c7644b10da8a5f7daf05e21de510cd41c09a925444e3f0a52a99e
IDP_AGENT_OPERATOR=idp-agent-operator@sha256:a12594769e8c0e718280875a22006265385e6d866b7b4507d6065e16a0dfd5bf


#check_cmd:
# Returns:
#   0 on finding the command
#   1 if the command does not exist
check_cmd ()
{
   type $1 > /dev/null
   echo $?
}

check_for_required_dependencies_mirror() {
    REQUIREDCOMMANDS=("skopeo")
    echo -e "Checking for required commands: ${REQUIREDCOMMANDS[*]}"
    for COMMAND in "${REQUIREDCOMMANDS[@]}"; do
        IS_COMMAND=$(check_cmd $COMMAND)
        if [ $IS_COMMAND -ne 0 ]; then
            echo "ERROR: $COMMAND command not found, install $COMMAND command to apply patch"
            exit $IS_COMMAND
        fi
    done
}

# build icr path from the docker image path
build_icr_path() {
  prefix="${1}"
  image="${2}"
  echo "${prefix}/${image}"
}


# copy images from icr to local repository
copy_images() {
  TARGET_PATH=${1}
  for IMAGE in "${IMAGES[@]}"; do
    DESTINATION=docker://$TARGET_PATH/cp/bnr/$IMAGE
    echo -e "Copying\n Image: $(build_icr_path ${BNR_PREFIX} ${IMAGE})\n Destination: docker://$TARGET_PATH/cp/bnr/$IMAGE\n"
    skopeo copy --insecure-policy --preserve-digests --all docker://"$BNR_PREFIX"/"$IMAGE" "$DESTINATION"
  done

  for IMAGE in "${CPOPENIMAGES[@]}"; do
    DESTINATION=docker://$TARGET_PATH/cpopen/$IMAGE
    echo -e "Copying\n Image: $(build_icr_path ${CPOPEN_PREFIX} ${IMAGE})\n Destination: docker://$TARGET_PATH/cpopen/$IMAGE\n"
    skopeo copy --insecure-policy --preserve-digests --all docker://"$CPOPEN_PREFIX"/"$IMAGE" "$DESTINATION"
  done

  for FUSIONHCIIMAGE in "${FUSIONIMAGES_HCI[@]}"; do
    DESTINATION=docker://$TARGET_PATH/cp/fusion-hci/$FUSIONHCIIMAGE
    echo -e "Copying\n Image: $(build_icr_path ${HCI_PREFIX} ${FUSIONHCIIMAGE})\n Destination: docker://$TARGET_PATH/cp/fusion-hci/$FUSIONHCIIMAGE\n"
    skopeo copy --insecure-policy --preserve-digests --all docker://"$HCI_PREFIX"/"$FUSIONHCIIMAGE" "$DESTINATION"
  done

  for FUSIONSDSIMAGE in "${FUSIONIMAGES_SDS[@]}"; do
    DESTINATION=docker://$TARGET_PATH/cp/fusion-sds/$FUSIONSDSIMAGE
    echo -e "Copying\n Image: $(build_icr_path ${SDS_PREFIX} ${FUSIONSDSIMAGE})\n Destination: docker://$TARGET_PATH/cp/fusion-sds/$FUSIONSDSIMAGE\n"
    skopeo copy --insecure-policy --preserve-digests --all docker://"$SDS_PREFIX"/"$FUSIONSDSIMAGE" "$DESTINATION"
  done
}

declare -a IMAGES=(
  $TRANSACTIONMANAGER
)

declare -a CPOPENIMAGES=(
  $IDP_AGENT_OPERATOR
)

declare -a FUSIONIMAGES_HCI=()

declare -a FUSIONIMAGES_SDS=()

ICR_IMAGE_PATHS=()

for IMAGE in "${FUSIONIMAGES_HCI[@]}"; do
  ICR_PATH=
  ICR_IMAGE_PATHS+=($(build_icr_path ${HCI_PREFIX} ${IMAGE}))
done

for IMAGE in "${IMAGES[@]}"; do
  ICR_PATH=
  ICR_IMAGE_PATHS+=($(build_icr_path ${BNR_PREFIX} ${IMAGE}))
done

for IMAGE in "${CPOPENIMAGES[@]}"; do
  ICR_PATH=
  ICR_IMAGE_PATHS+=($(build_icr_path ${CPOPEN_PREFIX} ${IMAGE}))
done

for IMAGE in "${FUSIONIMAGES_SDS[@]}"; do
  ICR_PATH=
  ICR_IMAGE_PATHS+=($(build_icr_path ${SDS_PREFIX} ${IMAGE}))
done

# execution when copying images rather than as image path source
if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  if [ -z "${1}" ]; then
     usage
     exit 1
  fi

  check_for_required_dependencies_mirror

  if [ -z "${2}" ]; then
    LOG=/tmp/$(basename "${0}")_log.txt
  else
    LOG=${2}
  fi

  touch ${LOG}
  exec &> >(tee -a $LOG)
  echo -e "Logging to $LOG\n"
  set -e

  copy_images ${1}
fi
