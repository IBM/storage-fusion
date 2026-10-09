#!/usr/bin/env bash
# delete-minio-resources.sh
# Manually deletes the deprecated MinIO resources from the DataProtectionAgent namespace.
# Usage: ./delete-minio-resources.sh [NAMESPACE]
#   NAMESPACE defaults to ibm-backup-restore if not provided.

set -euo pipefail

NAMESPACE="${1:-ibm-backup-restore}"

echo "Deleting deprecated MinIO resources from namespace: ${NAMESPACE}"

# StatefulSet first — stops the running pod before removing its dependencies
kubectl delete statefulset   guardian-minio       -n "${NAMESPACE}" --ignore-not-found
kubectl delete service       guardian-minio-svc   -n "${NAMESPACE}" --ignore-not-found
kubectl delete serviceaccount guardian-minio      -n "${NAMESPACE}" --ignore-not-found
kubectl delete pvc           minio                -n "${NAMESPACE}" --ignore-not-found
kubectl delete secret        cloud-credentials    -n "${NAMESPACE}" --ignore-not-found
kubectl delete backupstoragelocation.velero.io guardian-minio -n "${NAMESPACE}" --ignore-not-found

echo "Done."

