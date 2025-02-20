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

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/guardian-job-manager@sha256:8daeb9bf614d8e72aeded5f0e17e1a93bc5c071638e6adff1c28c30650ff26e0 docker://$TARGET_PATH/cp/bnr/guardian-job-manager@sha256:8daeb9bf614d8e72aeded5f0e17e1a93bc5c071638e6adff1c28c30650ff26e0

skopeo copy --insecure-policy --preserve-digests --all docker://icr.io/cpopen/guardian-dm-operator@sha256:736babab4ab22bf3d2bdf6ea54100031a3e800cea9bf2226a6c1a80a69206ea6 docker://$TARGET_PATH/cpopen/guardian-dm-operator@sha256:736babab4ab22bf3d2bdf6ea54100031a3e800cea9bf2226a6c1a80a69206ea6

skopeo copy --insecure-policy --preserve-digests --all docker://icr.io/cpopen/guardian-datamover@sha256:1c8af5f70feda2d0074b90cc5fdeb53409718691530e7d64e8d8a3574cc0befa docker://$TARGET_PATH/cpopen/guardian-datamover@sha256:1c8af5f70feda2d0074b90cc5fdeb53409718691530e7d64e8d8a3574cc0befa

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:3e28cda75450285980a2f3ad61fba8c12786c908cd743bba70f056793b050d43 docker://$TARGET_PATH/cp/bnr/guardian-transaction-manager@sha256:3e28cda75450285980a2f3ad61fba8c12786c908cd743bba70f056793b050d43

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fusion-hci/isf-data-protection-operator@sha256:d6f1081340eed3b18e714acd86e4cc406b9c43ba92705cad76c7688c6d325581 docker://$TARGET_PATH/cp/fusion-hci/isf-data-protection-operator@sha256:d6f1081340eed3b18e714acd86e4cc406b9c43ba92705cad76c7688c6d325581

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/fusion-sds/isf-data-protection-operator@sha256:8d0d7ef3064271b948a4b9a3b05177ae959613a0b353062a286edb972112cfc4 docker://$TARGET_PATH/cp/fusion-sds/isf-data-protection-operator@sha256:8d0d7ef3064271b948a4b9a3b05177ae959613a0b353062a286edb972112cfc4

skopeo copy --insecure-policy --preserve-digests --all docker://quay.io/minio/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3 docker://$TARGET_PATH/minio/minio@sha256:ea15e53e66f96f63e12f45509d2d2d8fad774808debb490f48508b3130bd22d3
