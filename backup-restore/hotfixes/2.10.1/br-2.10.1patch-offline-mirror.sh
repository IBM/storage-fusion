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


FBRVELERO=fbr-velero@sha256:b34f53ef2a02a883734f24dba9411baf6cfeef38983183862fa0ea773a7fc405
TRANSACTIONMANAGER=guardian-transaction-manager@sha256:bface27625e47932f792855827507dd5df50dc7e35f4780b2cc1629b8783fa79
GUARDIANDPOPERATOR=guardian-dp-operator@sha256:e7dce0d4817e545e5d40f90b116e85bd5ce9098f979284f12ad63cbc56f52d8c
GUARDIANIDPAGENTOPERATOR=idp-agent-operator@sha256:b2ab67807e79a064b14d7c79c902c5ec5949c0b6dc2ac4c990dcfb201f00ee0a
JOBMANAGER=guardian-job-manager@sha256:c3265f3e16e326bbd0fe42ae5e36fbf92b1907ce5f37c79953c31c3733b6237a
BACKUPSERVICE=guardian-backup-service@sha256:e59760cea7f93ef3809071d00d340afed5c22eebb662d030139ebc20e2b10172

declare -a IMAGES=(
  $FBRVELERO
  $TRANSACTIONMANAGER
  $JOBMANAGER
  $BACKUPSERVICE
)

declare -a CPOPENIMAGES=(
  "$GUARDIANDPOPERATOR"
  "$GUARDIANIDPAGENTOPERATOR"
)

for IMAGE in "${IMAGES[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/bnr/$IMAGE
  echo -e "Copying\n Image: $IMAGE\n Destination: docker://$TARGET_PATH/cp/bnr/$IMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/$IMAGE $DESTINATION
done

for CPOPENIMAGE in "${CPOPENIMAGES[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cpopen/$CPOPENIMAGE
  echo -e "Copying\n Image: $CPOPENIMAGE\n Destination: docker://$TARGET_PATH/cpopen/$CPOPENIMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://icr.io/cpopen/"$CPOPENIMAGE" "$DESTINATION"
done
