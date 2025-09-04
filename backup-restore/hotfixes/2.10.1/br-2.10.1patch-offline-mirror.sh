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


FBRVELERO=fbr-velero@sha256:910ffee32ec4121df8fc2002278f971cd6b0d923db04d530f31cf5739e08e24c
TRANSACTIONMANAGER=guardian-transaction-manager@sha256:62c62ec0cd03945bcbc408faa62338e65476617c427373fd609e4809605127a3

declare -a IMAGES=(
  $FBRVELERO
  $TRANSACTIONMANAGER
)

for IMAGE in "${IMAGES[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/bnr/$IMAGE
  echo -e "Copying\n Image: $IMAGE\n Destination: docker://$TARGET_PATH/cp/bnr/$IMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/$IMAGE $DESTINATION
done
