# Backup & Restore Hotfixes for Version 2.13.0

This document lists all hotfixes available for IBM Storage Fusion Backup & Restore version 2.13.0.

## Overview

Hotfixes are cumulative patches that address specific issues in the Backup & Restore component. Each hotfix builds upon previous fixes and should be applied to both hub and spoke clusters.

## Hotfix hotfix-2.13.0.1 (Latest)

**Release Date:** August 13th, 2026

### Issues Fixed

1. Backup fails with the error message ‘BMYBR0009 PVC utilization exceeds the 95% threshold’ due to an incorrect utilization calculation.

## Installation

### Required Files

Before applying the hotfix, download the following files:

- [`br-post-install-patch-2.13.0.sh`](br-post-install-patch-2.13.0.sh) 
- [`br-2.13.0patch-offline-mirror.sh`](br-2.13.0patch-offline-mirror.sh) 

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
./br-2.13.0patch-offline-mirror.sh <TARGET_PATH>
```

**Parameters:**
- `<TARGET_PATH>`: Your local registry path in format `$LOCAL_ISF_REGISTRY/$LOCAL_ISF_REPOSITORY`

**Example:**
```bash
./br-2.13.0patch-offline-mirror.sh myregistry.example.com:5000/isf-images
```

> **Note:** Skip this step if your cluster has direct internet access.

#### Step 2: Apply the Hotfix

**Installation procedure:**

1. **Download the hotfix scripts** to your local system:
   ```bash
   # Verify the scripts are present
   ls -lh br-post-install-patch-2.13.0.sh
   ls -lh br-2.13.0patch-offline-mirror.sh
   ```

2. **Make the script executable:**
   ```bash
   chmod +x br-post-install-patch-2.13.0.sh
   ```

3. **Execute the hotfix script** with the appropriate deployment type flag:

   **For HCI deployments:**
   ```bash
   ./br-post-install-patch-2.13.0.sh -hci
   ```

   **For SDS deployments:**
   ```bash
   ./br-post-install-patch-2.13.0.sh -sds
   ```


## Prerequisites

- IBM Storage Fusion Backup & Restore version 2.13.0 must be installed
- Cluster administrator access (kubectl/oc CLI configured)
- For offline installations: Access to container registry for image mirroring

## Important Notes

- **Hotfixes are cumulative**: The latest hotfix includes all fixes from the previous hotfixes
- **Apply to all clusters**: Run the patch script on both hub and spoke clusters


## Support

For issues or questions regarding these hotfixes, please refer to the IBM Storage Fusion documentation or contact IBM Support.

## Related Files

- `br-post-install-patch-2.13.0.sh` - Main hotfix installation script
- `br-2.13.0patch-offline-mirror.sh` - Offline image mirroring script
