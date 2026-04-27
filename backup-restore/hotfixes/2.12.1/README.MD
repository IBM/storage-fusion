# Backup & Restore Hotfixes for Version 2.12.1

This document lists all hotfixes available for IBM Storage Fusion Backup & Restore version 2.12.1.

## Overview

Hotfixes are cumulative patches that address specific issues in the Backup & Restore component. Each hotfix builds upon previous fixes and should be applied to both hub and spoke clusters.

## Hotfix 3 (Latest)

**Release Date:** Apr 27th, 2026

### Issues Fixed


1. **Fusion creates hundreds of pods during cleanup jobs** (#69959)
2. **Backup jobs remain in pending state on spoke** (#71255)
3. **Slow service protection backup** (#71410) 
   

## Hotfix 2

### Issues Fixed

1. **Fix issue with missing fields in guardian-configmap which causes spoke upgrades to be stuck** (#69600)
  

## Hotfix 1

### Issues Fixed

1. **Force idp-agent-operator to reconcile spoke-hub communication settings due to incorrect state-1 mirroring of ConfigMap guardian-configmap**  (#69600)


## Installation

### Required Files

Before applying the hotfix, download the following files:

- `br-post-install-patch-2.12.1.sh` 
- `br-2.12.1patch-offline-mirror.sh` 

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
./br-2.12.1patch-offline-mirror.sh <TARGET_PATH>
```

**Parameters:**
- `<TARGET_PATH>`: Your local registry path in format `$LOCAL_ISF_REGISTRY/$LOCAL_ISF_REPOSITORY`

**Example:**
```bash
./br-2.12.1patch-offline-mirror.sh myregistry.example.com:5000/isf-images
```

> **Note:** Skip this step if your cluster has direct internet access.

#### Step 2: Apply the Hotfix

**Installation procedure:**

1. **Download the hotfix scripts** to your local system:
   ```bash
   # Verify the scripts are present
   ls -lh br-post-install-patch-2.12.1.sh
   ls -lh br-2.12.1patch-offline-mirror.sh
   ```

2. **Make the script executable:**
   ```bash
   chmod +x br-post-install-patch-2.12.1.sh
   ```

3. **Execute the hotfix script** with the appropriate deployment type flag:

   **For HCI deployments:**
   ```bash
   ./br-post-install-patch-2.12.1.sh -hci
   ```

   **For SDS deployments:**
   ```bash
   ./br-post-install-patch-2.12.1.sh -sds
   ```


## Prerequisites

- IBM Storage Fusion Backup & Restore version 2.12.1 must be installed
- Cluster administrator access (kubectl/oc CLI configured)
- For offline installations: Access to container registry for image mirroring

## Important Notes

- **Hotfixes are cumulative**: The latest hotfix includes all fixes from the previous hotfixes
- **Apply to all clusters**: Run the patch script on both hub and spoke clusters


## Support

For issues or questions regarding these hotfixes, please refer to the IBM Storage Fusion documentation or contact IBM Support.

## Related Files

- `br-post-install-patch-2.12.1.sh` - Main hotfix installation script
- `br-2.12.1patch-offline-mirror.sh` - Offline image mirroring script
