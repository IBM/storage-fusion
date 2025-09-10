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

TRANSACTIONMANAGER=guardian-transaction-manager@sha256:950a851ff61b748abc0e141922c17eaca6a944e3f8a1d74b73855322a0f74568

declare -a IMAGES=(
  $TRANSACTIONMANAGER
)

for IMAGE in "${IMAGES[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/bnr/$IMAGE
  echo -e "Copying\n Image: $IMAGE\n Destination: docker://$TARGET_PATH/cp/bnr/$IMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/$IMAGE $DESTINATION
done
