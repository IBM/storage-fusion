# Backup & Restore Hotfixes for Version 2.11.0

This document lists all hotfixes available for IBM Storage Fusion Backup & Restore version 2.11.0.

## Overview

Hotfixes are cumulative patches that address specific issues in the Backup & Restore component. Each hotfix builds upon previous fixes and should be applied to both hub and spoke clusters.

## Hotfix hotfix-2.11.0.10 (Latest)

**Release Date:** May 7, 2026

### Issues Fixed

1. Added the early validation to check if the volume utilization is very high during backup, so it will not fail later on while restore. (#72776)

## Hotfix hotfix-2.11.0.9

### Issues Fixed

1. Fixes rbdsnapshot typo - ceph storage was getting filled up fast with daily vm backups (#71802)

## Hotfix hotfix-2.11.0.8

### Issues Fixed

1. Fixed issue with missing fields in guardian-configmap which causes spoke upgrades to be stuck. (#69600)

## Hotfix hotfix-2.11.0.7

### Issues Fixed

1. Change AWS S3 connections with OADP to use virtual host style urls instead of host path style by default for proxy compatibility. Proxy services may rely on the bucket in the url's subdomain for validation. Buckets with "." in their name will still default to path style for compatibility. S3 compatibles will continue to use path style urls. Path style format may be forced by adding "FORCEAWSPATHSTYLE" to .spec.transactionManager.testFlags in the DataProtectionAgent. (#68134)

## Hotfix hotfix-2.11.0.6

### Issues Fixed

1.  Restore fails with error Backup inventory info not returned from application service for applicationId (#59191)
2.  Unable to restore pre 2.9 backup with 2.10.* (61073)
3.  Backup fails intermittently with error Hit exception during "group/rg" : argument of type 'NoneType' is not iterable (61235, 62741))
4.  Jobs taking long to go from CancelPending to Cancelled state (61518)
5.  Alert triggered for old backup job completion (62403)
6. Backup fails due to a timeout when deleting VolumeSnapshotContent (Issue: 64678)

## Hotfix hotfix-2.11.0.5

### Issues Fixed

1.  OADP datamover Pods get assigned to a node without the backup volumes when PV topology is a subset of the StorageClass topology with StorageClass field volumeBindingMode: WaitForFirstConsumer (Issue: 62485)


## Hotfix hotfix-2.11.0.3

### Issues Fixed
1. Redis certificate expiration causes jobs to fail (Issue: 59690)

## Hotfix hotfix-2.11.0.2

### Issues Fixed
1.  Fix KeyError while accessing intrinsic variable APP.namespace.name during restore.(Issue: 60235)

## Hotfix hotfix-2.11.0.1

### Issues Fixed
1.  Removed the validation for label, if label more than 63 character label will be truncated for Velero Backup CR.(Issue: 59712)


## Installation

### Required Files

Before applying the hotfix, download the following files:

- [`br-post-install-patch-2.11.0.sh`](br-post-install-patch-2.11.0.sh) 
- [`br-2.11.0patch-offline-mirror.sh`](br-2.11.0patch-offline-mirror.sh) 

### Installation Steps

The hotfix must be applied to **the hub and all spoke cluster** in your environment.

#### Step 1: Offline Image Mirroring (Air-Gapped Environments Only)

If your environment does not have direct internet access, mirror the hotfix images to your local registry before applying the hotfix.

**Prerequisites:**
- Authenticate to both source and destination registries:
  ```bash
  # Login to IBM Container Registry
  podman login cp.icr.io
  
  # Login to your local registry
  podman login <YOUR_LOCAL_REGISTRY>
  ```

**Execute the mirroring script:**
```bash
./br-2.11.0patch-offline-mirror.sh <TARGET_PATH>
```

**Parameters:**
- `<TARGET_PATH>`: Your local registry path in format `$LOCAL_ISF_REGISTRY/$LOCAL_ISF_REPOSITORY`

**Example:**
```bash
./br-2.11.0patch-offline-mirror.sh myregistry.example.com:5000/isf-images
```

> **Note:** Skip this step if your cluster has direct internet access.

#### Step 2: Apply the Hotfix

**Installation procedure:**

1. **Download the hotfix scripts** to your local system:
   ```bash
   # Verify the scripts are present
   ls -lh br-post-install-patch-2.11.0.sh
   ls -lh br-2.11.0patch-offline-mirror.sh
   ```

2. **Make the script executable:**
   ```bash
   chmod +x br-post-install-patch-2.11.0.sh
   ```

3. **Execute the hotfix script** with the appropriate deployment type flag:

   **For HCI deployments:**
   ```bash
   ./br-post-install-patch-2.11.0.sh -hci
   ```

   **For SDS deployments:**
   ```bash
   ./br-post-install-patch-2.11.0.sh -sds
   ```


## Prerequisites

- IBM Storage Fusion Backup & Restore version 2.11.0 must be installed
- Cluster administrator access (kubectl/oc CLI configured)
- For offline installations: Access to container registry for image mirroring

## Important Notes

- **Hotfixes are cumulative**: The latest hotfix includes all fixes from the previous hotfixes
- **Apply to all clusters**: Run the patch script on both hub and spoke clusters


## Support

For issues or questions regarding these hotfixes, please refer to the IBM Storage Fusion documentation or contact IBM Support.

## Related Files

- `br-post-install-patch-2.11.0.sh` - Main hotfix installation script
- `br-2.11.0patch-offline-mirror.sh` - Offline image mirroring script