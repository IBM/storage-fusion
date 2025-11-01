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


FBRVELERO=fbr-velero@sha256:5c26f3a18fc4a9ad1d0d1b85e69ca576819b8e6bc92826a603db4b32095b4ac9
TRANSACTIONMANAGER=guardian-transaction-manager@sha256:1ed31e6ad1f8ee4f3d29bcb3b5f8caba5b4c571d2f2f8035fe3ff5edce037c27
GUARDIANDPOPERATOR=guardian-dp-operator@sha256:e7dce0d4817e545e5d40f90b116e85bd5ce9098f979284f12ad63cbc56f52d8c
GUARDIANIDPAGENTOPERATOR=idp-agent-operator@sha256:b2ab67807e79a064b14d7c79c902c5ec5949c0b6dc2ac4c990dcfb201f00ee0a
JOBMANAGER=guardian-job-manager@sha256:c3265f3e16e326bbd0fe42ae5e36fbf92b1907ce5f37c79953c31c3733b6237a
BACKUPSERVICE=guardian-backup-service@sha256:e59760cea7f93ef3809071d00d340afed5c22eebb662d030139ebc20e2b10172

ISFDATAPROTECTION_HCI=isf-data-protection-operator@sha256:aba0aeee52dd7472b1628222f9e2250cff062501687bdd8c98fd3fad0f47f1cd
ISFDATAPROTECTION_SDS=isf-data-protection-operator@sha256:94a9b349fea12e37c61836448b9840ac6beda6655649eb5d5b7db6c68e8bdfdc

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

declare -a FUSIONIMAGES_HCI=(
  "$ISFDATAPROTECTION_HCI"
)

declare -a FUSIONIMAGES_SDS=(
  "$ISFDATAPROTECTION_SDS"
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

for FUSIONHCIIMAGE in "${FUSIONIMAGES_HCI[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/fusion-hci/$FUSIONHCIIMAGE
  echo -e "Copying\n Image: $FUSIONHCIIMAGE\n Destination: docker://$TARGET_PATH/cp/fusion-hci/$FUSIONHCIIMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fusion-hci/"$FUSIONHCIIMAGE" "$DESTINATION"
done

for FUSIONSDSIMAGE in "${FUSIONIMAGES_SDS[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/fusion-sds/$FUSIONSDSIMAGE
  echo -e "Copying\n Image: $FUSIONSDSIMAGE\n Destination: docker://$TARGET_PATH/cp/fusion-sds/$FUSIONSDSIMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fusion-sds/"$FUSIONSDSIMAGE" "$DESTINATION"
done
