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

BACKUPLOCATION=IMAGE-guardian-backup-location
TRANSACTIONMANAGER=IMAGE-guardian-transaction-manager
FBRVELERO=IMAGE-velero
GUARDIANDPOPERATOR=IMAGE-guardian-dp-operator

declare -a IMAGES=(
  "$BACKUPLOCATION"
  "$TRANSACTIONMANAGER"
  "$FBRVELERO"
)

declare -a CPOPENIMAGES=(
  "$GUARDIANDPOPERATOR"
)

for IMAGE in "${IMAGES[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/bnr/$IMAGE
  echo -e "Copying\n Image: $IMAGE\n Destination: docker://$TARGET_PATH/cp/bnr/$IMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/"$IMAGE" "$DESTINATION"
done

for CPOPENIMAGE in "${CPOPENIMAGES[@]}"; do
  DESTINATION=docker://$TARGET_PATH/cp/bnr/$CPOPENIMAGE
  echo -e "Copying\n Image: $CPOPENIMAGE\n Destination: docker://$TARGET_PATH/cp/bnr/$CPOPENIMAGE\n"
  skopeo copy --insecure-policy --preserve-digests --all docker://icr.io/cpopen/"$CPOPENIMAGE" "$DESTINATION"
done
