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

skopeo copy --insecure-policy --preserve-digests --all docker://cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:b407e1c6585cc38938d52b750dddef57a97846edc4752b37da55014d1b9ef732
