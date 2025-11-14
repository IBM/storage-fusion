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

TRANSACTIONMANAGER=guardian-transaction-manager@sha256:6465fadda4ca4402d098932d68563209ecfcc6ca7aa3e5accee02be98e4404dd
OADP_VELERO_14=cp.icr.io/cp/bnr/fbr-velero@sha256:1fd0dc018672507b24148a0fe71e69f91ab31576c7fa070c599d7a446b5095aa
OADP_VELERO_15=cp.icr.io/cp/bnr/fbr-velero15@sha256:7a57d50f9c1b6a338edf310c5e69182ac98ec6338376b4ddc0474ff7e592f4f4

declare -a IMAGES=(
  $TRANSACTIONMANAGER
  $OADP_VELERO_14
  $OADP_VELERO_15
)

for IMAGE in "${IMAGES[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/bnr/$IMAGE
  echo -e "Copying\n Image: $IMAGE\n Destination: docker://$TARGET_PATH/cp/bnr/$IMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/$IMAGE $DESTINATION
done
