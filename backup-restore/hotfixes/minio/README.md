# Customer Advisory: MinIO Image Removal from Quay Registry

## Overview

IBM has identified an issue affecting IBM Storage Fusion Backup and Restore deployments that depend on a MinIO container image previously hosted on the public Quay registry. The image has been removed by MinIO and is no longer available for download.

As a result, environments that attempt to pull the image from Quay may experience installation, upgrade, and runtime failures.

## Problem Details

When the MinIO image cannot be retrieved, the `guardian-minio` pod will fail to start. The message in the pod event will contain error similar to:

```
Failed to pull image "quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e": initializing source docker://quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e: reading manifest sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e in quay.io/minio/minio: unauthorized: access to the requested resource is not authorized
```

This error indicates that the required image is no longer accessible from the Quay registry.

## Impact Assessment

This issue does not affect existing air-gapped environments where the MinIO image has already been mirrored into a local registry and remains available to the cluster.

However, customers using connected environments may experience the following impacts across all IBM Storage Fusion releases:

### 1. Installation and Upgrade Failures

New installations and upgrade operations may fail because the required MinIO image can no longer be pulled from the public Quay registry.

### 2. Transaction Manager Service Disruption

If the Transaction Manager pod is restarted or rescheduled to a node where the image is not already cached, the pod may fail to start.

### 3. Backup and Restore Operation Failures

Backup and restore jobs may fail when scheduled on nodes that do not have the required MinIO image available locally.

## Affected Versions

If the customer is using Backup and Restore function, this issue affects all IBM Storage Fusion releases.

## Resolution

To resolve this issue, download and apply the ImageDigestMirrorSet (IDMS) YAML:

<https://github.com/IBM/storage-fusion/tree/master/backup-restore/hotfixes/minio/minio-idms.yaml>

The manifest creates a new image mirror configuration that redirects image pulls to a supported image source.

After applying the YAML, verify that the ImageDigestMirrorSet has been successfully created and allow sufficient time for the cluster image configuration to propagate across all nodes.
