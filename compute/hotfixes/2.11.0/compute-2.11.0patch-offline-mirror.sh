#!/bin/bash

set -euo pipefail

if ! command -v skopeo &> /dev/null; then
  echo "ERROR: skopeo is not installed."
  exit 1
fi

if [ $# -ne 2 ]; then
  echo "ERROR: Usage: $0 <SOURCE_IMAGE> <TARGET_PATH>"
  exit 1
fi

SOURCE_IMAGE="$1"
TARGET_PATH="$2"

LOG=/tmp/$(basename "$0")_log.txt
exec &> >(tee -a "$LOG")
echo "Logging to $LOG"

# Extract image name from source image (handle both @sha256 and :tag formats)
IMAGE_NAME=$(echo "$SOURCE_IMAGE" | rev | cut -d'/' -f1 | rev)

DEST_IMAGE="docker://$TARGET_PATH/$IMAGE_NAME"

echo -e "Copying \nImage: docker://$SOURCE_IMAGE\n Destination: $DEST_IMAGE\n"

# Copy image using skopeo
skopeo copy --insecure-policy --preserve-digests --all "docker://$SOURCE_IMAGE" "$DEST_IMAGE"

# After copying, print the final mirrored image path
echo "Mirrored image: $TARGET_PATH/$IMAGE_NAME"
