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

TRANSACTIONMANAGER=guardian-transaction-manager@sha256:ded5bef2f272b16d7749fd4aac7cfe0eaf5f84c94d05b20bfcbd441612b686f9
OADP_VELERO_14=fbr-velero@sha256:1fd0dc018672507b24148a0fe71e69f91ab31576c7fa070c599d7a446b5095aa
OADP_VELERO_15=fbr-velero15@sha256:7a57d50f9c1b6a338edf310c5e69182ac98ec6338376b4ddc0474ff7e592f4f4

JOBMANAGER=guardian-job-manager@sha256:62fb326d26758d531f1912bd28238468f616553dfec99e2d704729f6caf39349
BACKUPSERVICE=guardian-backup-service@sha256:6517b55c0c3ab8aa44f2e5cc4554ee3efb49211f7eb8840623c4160076485611

ISFDATAPROTECTION_HCI=isf-data-protection-operator@sha256:63bdb2f47b02366fe39f98bb5d811878b44feed235bca22e0f16586a387c9a80
ISFDATAPROTECTION_SDS=isf-data-protection-operator@sha256:bdfe6ba1101d1de4dab81e513b2f4c7492da19b26186d20ee58d955689cb0be3

declare -a IMAGES=(
  $TRANSACTIONMANAGER
  $OADP_VELERO_14
  $OADP_VELERO_15
  $JOBMANAGER
  $BACKUPSERVICE
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
