#!/bin/bash
LOG=/tmp/$(basename $0)_log.txt
exec &> >(tee -a $LOG)
echo "Logging to $LOG"

if [ -z "$1" ]
 then
   echo "ERROR: Usage: $0 <TARGET_PATH>"
   exit 1
fi
TARGET_PATH="$1"
export TARGET_PATH
set -e

skopeo copy --insecure-policy --preserve-digests --all docker://icr.io/cpopen/guardian-dm-operator@sha256:ef5095ae54a7140e51b17f02b0b591fc0736e28cca66d9f69199df997b74eb98 docker://$TARGET_PATH/guardian-dm-operator@sha256:ef5095ae54a7140e51b17f02b0b591fc0736e28cca66d9f69199df997b74eb98
skopeo copy --insecure-policy --preserve-digests --all docker://icr.io/cpopen/guardian-datamover@sha256:8617945fbbcf13c8ec15eccf85a18ed3aecd7432cff8380a06bc9ce3ab5d406b docker://$TARGET_PATH/guardian-datamover@sha256:8617945fbbcf13c8ec15eccf85a18ed3aecd7432cff8380a06bc9ce3ab5d406b
skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fbr/guardian-job-manager@sha256:5a99629999105bdc83862f4bf37842b8004dfb3db9eea20b07ab7e39e95c8edc docker://$TARGET_PATH/guardian-job-manager@sha256:5a99629999105bdc83862f4bf37842b8004dfb3db9eea20b07ab7e39e95c8edc
skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fbr/guardian-backup-location@sha256:c737450b02a9f415a4c4eea6cc6a67ce0723a8bf5c08ce41469c847c5b598e16 docker://$TARGET_PATH/guardian-backup-location@sha256:c737450b02a9f415a4c4eea6cc6a67ce0723a8bf5c08ce41469c847c5b598e16
skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fbr/guardian-backup-policy@sha256:32a4ffba0dd2da241bd128ab694fd6fc34a7087aab053a29658e3e0f69ef11aa docker://$TARGET_PATH/guardian-backup-policy@sha256:32a4ffba0dd2da241bd128ab694fd6fc34a7087aab053a29658e3e0f69ef11aa
skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fbr/guardian-backup-service@sha256:e26efc87da06657c54aedc7f048855adf8c1fc76c6f3bd35dfa2e545caadbe98 docker://$TARGET_PATH/guardian-backup-service@sha256:e26efc87da06657c54aedc7f048855adf8c1fc76c6f3bd35dfa2e545caadbe98
skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fbr/guardian-transaction-manager@sha256:0ae46fc2f6e744f79f81005579f4dcb7c9981b201f239433bf1e132f9c89c8cd docker://$TARGET_PATH/guardian-transaction-manager@sha256:0ae46fc2f6e744f79f81005579f4dcb7c9981b201f239433bf1e132f9c89c8cd
skopeo copy --insecure-policy --preserve-digests --all docker://quay.io/minio/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3 docker://$TARGET_PATH/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3
