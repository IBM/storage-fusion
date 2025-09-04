#!/bin/bash
LOG=/tmp/$(basename "$0")_log.txt
exec &> >(tee -a "$LOG")
echo -e "Logging to $LOG\n"

if [ -z "$1" ]; then
  echo "ERROR: Usage: $0 <TARGET_PATH>"
  exit 1
fi
TARGET_PATH="$1"
export TARGET_PATH
set -e

BACKUPLOCATION=guardian-backup-location@sha256:5efd82d5e568cc3cd17cc1fd931d4228f87804683cffc87d34c81eec73dd4986
BACKUPSERVICE=guardian-backup-service@sha256:2c8f3cd0fe7e2a5db9ba9fb5bb230266b960195ba76ebf0a9cf2cdb7e3c5ab98
BACKUPPOLICY=guardian-backup-policy@sha256:7a6e5982598e093f6be50dbf89e7638ed67600403a7681e3fb328e27eab8360a
GUARDIANDPOPERATOR=guardian-dp-operator@sha256:04a3446eb98d03eddfce27ff77def52b2c3f89c57d662190f61891d8bd3167fc
TRANSACTIONMANAGER=guardian-transaction-manager@sha256:c6ee0b30aedc5dcc83c50df5d33ff3b7ca4cc086cb2ff984d10a190b1c5efc6f
FBRVELERO=fbr-velero@sha256:d4e54c0e98983f78b4f022ae5fd9dc4f751d725b19d15d355e73055cfeec863d

ISFDATAPROTECTION_HCI=isf-data-protection-operator@sha256:74990bffe171264a3d08eab53398dd5e98491a24269642b38688d854c1549224
ISFDATAPROTECTION_SDS=isf-data-protection-operator@sha256:c060b4b34da3edc756dbc5f6d3f6afd8e895ece52dff3d4aad8965217365a966


declare -a IMAGES=(
  "$BACKUPLOCATION"
  "$BACKUPSERVICE"
  "$BACKUPPOLICY"
  "$TRANSACTIONMANAGER"
  "$FBRVELERO"
)

declare -a CPOPENIMAGES=(
  "$GUARDIANDPOPERATOR"
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
  skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/"$IMAGE" "$DESTINATION"
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
