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


FBRVELERO=fbr-velero@sha256:726af6360d5a7cb4431cd3e4b903699a8684999e3a73b078b590493a5ca482db
TRANSACTIONMANAGER=guardian-transaction-manager@sha256:081c7a1269a9058f2c2e7a5b432ac4adbbcbdbf6a8fcc779bf16de9a915c4bd6
GUARDIANDPOPERATOR=guardian-dp-operator@sha256:e7dce0d4817e545e5d40f90b116e85bd5ce9098f979284f12ad63cbc56f52d8c
GUARDIANIDPAGENTOPERATOR=idp-agent-operator@sha256:b2ab67807e79a064b14d7c79c902c5ec5949c0b6dc2ac4c990dcfb201f00ee0a
JOBMANAGER=guardian-job-manager@sha256:c3265f3e16e326bbd0fe42ae5e36fbf92b1907ce5f37c79953c31c3733b6237a
BACKUPSERVICE=guardian-backup-service@sha256:a636ef2d9e1b1022cc5a74ca0d5972019aef95579ea673abd0c2acc8cc48b590

ISFDATAPROTECTION_HCI=isf-data-protection-operator@sha256:58d468ea4ac16e263aef4bbf3a8eb6d0fc14f9438d0dec0b99dbfd40ed8c287f
ISFDATAPROTECTION_SDS=isf-data-protection-operator@sha256:25aa94788c2e387812a53b7c452ae05ef4bde72e6a1b60c4132bafdbea83eeec

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
