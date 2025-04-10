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

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/guardian-job-manager@sha256:7f31cb89d2279a3a54d85a23a4fd65c1745316c1d72c40ce8df32096469de47c docker://$TARGET_PATH/cp/bnr/guardian-job-manager@sha256:7f31cb89d2279a3a54d85a23a4fd65c1745316c1d72c40ce8df32096469de47c

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/guardian-backup-service@sha256:b310c5128b6b655e884a9629da7361c80625dd76378cea52eb6b351b3a70c139 docker://$TARGET_PATH/cp/bnr/guardian-backup-service@sha256:b310c5128b6b655e884a9629da7361c80625dd76378cea52eb6b351b3a70c139

skopeo copy --insecure-policy --preserve-digests --all docker://icr.io/cpopen/guardian-dm-operator@sha256:736babab4ab22bf3d2bdf6ea54100031a3e800cea9bf2226a6c1a80a69206ea6 docker://$TARGET_PATH/cpopen/guardian-dm-operator@sha256:736babab4ab22bf3d2bdf6ea54100031a3e800cea9bf2226a6c1a80a69206ea6

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cpopen/guardian-datamover@sha256:4555ad7c0b4f95535a89cb9c6cd021f05d41a87aa1276d90e1e3a0b7b8d36799 docker://$TARGET_PATH/cpopen/guardian-datamover@sha256:4555ad7c0b4f95535a89cb9c6cd021f05d41a87aa1276d90e1e3a0b7b8d36799

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:33ceae1dd8632993952b74eaf01ae72b5911be87f64b675de269161628b87d35 docker://$TARGET_PATH/cp/bnr/guardian-transaction-manager@sha256:33ceae1dd8632993952b74eaf01ae72b5911be87f64b675de269161628b87d35

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fusion-hci/isf-data-protection-operator@sha256:d6f1081340eed3b18e714acd86e4cc406b9c43ba92705cad76c7688c6d325581 docker://$TARGET_PATH/cp/fusion-hci/isf-data-protection-operator@sha256:d6f1081340eed3b18e714acd86e4cc406b9c43ba92705cad76c7688c6d325581

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fusion-sds/isf-data-protection-operator@sha256:8d0d7ef3064271b948a4b9a3b05177ae959613a0b353062a286edb972112cfc4 docker://$TARGET_PATH/cp/fusion-sds/isf-data-protection-operator@sha256:8d0d7ef3064271b948a4b9a3b05177ae959613a0b353062a286edb972112cfc4

skopeo copy --insecure-policy --preserve-digests --all docker://quay.io/minio/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3 docker://$TARGET_PATH/minio/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/fbr-velero@sha256:99c8ccf942196d813dae94edcd18ff05c4c76bdee2ddd2cbbe2da3fa2810dd49 docker://$TARGET_PATH/cp/bnr/fbr-velero@sha256:99c8ccf942196d813dae94edcd18ff05c4c76bdee2ddd2cbbe2da3fa2810dd49
