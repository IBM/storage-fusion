#!/bin/bash
LOG=/tmp/$(basename $0)_log.txt
exec &> >(tee -a $LOG)
echo -e "Logging to $LOG\n"

if [ -z "$1" ]
 then
   echo "ERROR: Usage: $0 <TARGET_PATH>"
   exit 1
fi
TARGET_PATH="$1"
export TARGET_PATH
set -e

TRANSACTIONMANAGER=guardian-transaction-manager@sha256:c935e0c4a2d9b29c86bacc9322bbd6330a7a30fcb8ccfce2d068abf082d2805e
IDPSERVEROPERATOR=idp-server-operator@sha256:ec54933ec22c0b1175a1d017240401032caff5de0bdf99e7b5acea3a03686470

declare -a IMAGES=(
  $TRANSACTIONMANAGER
)

declare -a CPOPENIMAGES=(
  $IDPSERVEROPERATOR
)

for IMAGE in "${IMAGES[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/bnr/$IMAGE
  echo -e "Copying\n Image: $IMAGE\n Destination: docker://$TARGET_PATH/cp/bnr/$IMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/$IMAGE $DESTINATION
done

for CPOPENIMAGE in "${CPOPENIMAGES[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/bnr/$CPOPENIMAGE
  echo -e "Copying\n Image: $CPOPENIMAGE\n Destination: docker://$TARGET_PATH/cp/bnr/$CPOPENIMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://icr.io/cpopen/$CPOPENIMAGE $DESTINATION
done
