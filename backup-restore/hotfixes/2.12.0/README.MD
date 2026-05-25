# Backup & Restore Hotfixes for Version 2.12.0

This document lists all hotfixes available for IBM Storage Fusion Backup & Restore version 2.12.0.

## Overview

Hotfixes are cumulative patches that address specific issues in the Backup & Restore component. Each hotfix builds upon previous fixes and should be applied to both hub and spoke clusters.

## Hotfix hotfix-2.12.0.5 (Latest)
**Release Date:** May 25th, 2026

### Issues Fixed

1. **Fix broken 2.12.0.4 hotfix idp-agent-operator patch which causing invalidImage references for agent pods** (#73843)

## Hotfix hotfix-2.12.0.4

### Issues Fixed

1. **Fix issue with missing fields in guardian-configmap which causes spoke upgrades to be stuck** (#69600)

## Hotfix hotfix-2.12.0.3

### Issues Fixed

1. **Backport ignoreDelayBinding option from OADP-1.5 to OADP-1.4**. This fixes restore failure with StorageClass field `bindingMode: WaitForFirstConsumer` on single zone clusters with volumes that can be remounted on different nodes. (#68350)
2. **Fix Bridge failure on container restart**. (#68299)
3. **Change AWS S3 connections with OADP to use virtual host style URLs instead of host path style by default for proxy compatibility**. Proxy services may rely on the bucket in the URL's subdomain for validation. Buckets with `.` in their name will still default to path style for compatibility. S3 compatibles will continue to use path style URLs. Path style format may be forced by adding `FORCEAWSPATHSTYLE` to `.spec.transactionManager.testFlags` in the DataProtectionAgent. (#68134)

## Hotfix hotfix-2.12.0.1

### Issues Fixed

1. **Force idp-agent-operator to reconcile spoke-hub communication settings due to incorrect state-1 mirroring of ConfigMap guardian-configmap** (#69600)

## Installation

### Required Files

Before applying the hotfix, download the following files:

- [`br-post-install-patch-2.12.0.sh`](br-post-install-patch-2.12.0.sh)
- [`br-2.12.0patch-offline-mirror.sh`](br-2.12.0patch-offline-mirror.sh)

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
./br-2.12.0patch-offline-mirror.sh <TARGET_PATH>
```

**Parameters:**
- `<TARGET_PATH>`: Your local registry path in format `$LOCAL_ISF_REGISTRY/$LOCAL_ISF_REPOSITORY`

**Example:**
```bash
./br-2.12.0patch-offline-mirror.sh myregistry.example.com:5000/isf-images
```

> **Note:** Skip this step if your cluster has direct internet access.

#### Step 2: Apply the Hotfix

**Installation procedure:**

1. **Download the hotfix scripts** to your local system:
   ```bash
   # Verify the scripts are present
   ls -lh br-post-install-patch-2.12.0.sh
   ls -lh br-2.12.0patch-offline-mirror.sh
   ```

2. **Make the script executable:**
   ```bash
   chmod +x br-post-install-patch-2.12.0.sh
   ```

3. **Execute the hotfix script** with the appropriate deployment type flag:

   **For HCI deployments:**
   ```bash
   ./br-post-install-patch-2.12.0.sh -hci
   ```

   **For SDS deployments:**
   ```bash
   ./br-post-install-patch-2.12.0.sh -sds
   ```

## Prerequisites

- IBM Storage Fusion Backup & Restore version 2.12.0 must be installed
- Cluster administrator access (kubectl/oc CLI configured)
- For offline installations: Access to container registry for image mirroring

## Important Notes

- **Hotfixes are cumulative**: The latest hotfix includes all fixes from the previous hotfixes
- **Apply to all clusters**: Run the patch script on both hub and spoke clusters

## Support

For issues or questions regarding these hotfixes, please refer to the IBM Storage Fusion documentation or contact IBM Support.

## Related Files

- [`br-post-install-patch-2.12.0.sh`](br-post-install-patch-2.12.0.sh) - Main hotfix installation script
- [`br-2.12.0patch-offline-mirror.sh`](br-2.12.0patch-offline-mirror.sh) - Offline image mirroring script