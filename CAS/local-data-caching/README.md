# Local Data Caching for Content Aware Storage (CAS)

This tool deploys a configuration of IBM Fusion services that enable local caching of data from remote S3 buckets for ingestion by CAS. This is achieved by setting up an IBM Storage Scale Container Native (formerly known as CNSA) local Scale cluster on OpenShift Container Platform using local Data Foundation (DF) RBD volumes as backing storage devices.

The scripts in these directories work against both Fusion SDS 2.12 and Fusion HCI 2.12.

---

## Requirements

* OpenShift version **4.17** or higher, **4.20** is recommended
* IBM Fusion SDS or HCI **2.12** or higher
* **Cluster admin access**
* At least **3 worker nodes** OR **Compact cluster** with at least one local disk per node, recommended at least 1TB disks
* At least 1 node with [supported GPUs](https://www.ibm.com/docs/en/fusion-software/2.12.0?topic=prerequisites-system-requirements#systemrequirements__table_xpm_ddx_rgc)

### Prerequisites

* Linux host with connectivity to the OCP API
* `bash`
* `oc` client
* `envsubst` CLI utility

## Setup Script Usage

```bash
$ ./bin/setup-data-cache.sh [--filesystem-name <name>] [--filesystem-capacity <Gi>]
```

### Optional Inputs

| Flag                    | Description                | Default    |
| ----------------------- | -------------------------- | ---------- |
| `--filesystem-name`     | Name of the filesystem     | `cache-fs` |
| `--filesystem-capacity` | Capacity of the filesystem as [Kubernetes Quantities](https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/) (e.g. Gi, Ti, G, T) | `250Gi`   |

### Configuration Parameters

The script uses additional configuration parameters that can be modified either in the [config/config.env](./config/config.env) file or by exporting them in the shell prior to running the script. These include, among others:

* **FUSION_VERSION** – Version of Fusion to install (controls the CatalogSource image) (default: `2.12.0`)
* **FUSION_NAMESPACE** – Namespace where the Fusion operator will be installed (default: `ibm-spectrum-fusion-ns`)
* **INSTALL_STRATEGY** – Install strategy for the operator: `Automatic` or `Manual` (default: `Automatic`)
* **LOCAL_STORAGE_PROJECT** – Project name for PVCs (default: `local-disk-as-pv`)

> [!NOTE]
> Some platforms (VMWare, Nutanix, Hyper-V, etc.) do not properly present the drives to OpenShift Data Foundation as a flash drive (i.e. SSD or "non-rotational"). It is recommended to set the environment variable `CONVERT_HDD_TO_SSD` to convert rotational (HDD) disks to SSD on worker nodes during setup. For more information, including how to make this change persistent across node reboots, see [this Red Hat Knowledgebase article](https://access.redhat.com/articles/6547891).

### What the Script Does

#### 1. Pre-validations

Before launching the deployment, the script verifies:

* **Connectivity** – Confirms a successful connection to the OpenShift cluster.
* **Cluster version** – Ensures the cluster is on a supported OpenShift release.
* **Permissions** – Validates that the executing user holds Cluster-Admin privileges.
* **Local Storage Operator (LSO)** – Verifies the availability of the OpenShift Local Storage Operator.

#### 2. Fusion Deployment

Applies the Spectrum Fusion Custom Resource (CR). For Fusion SDS, it will also install the IBM Fusion Operator (`isf-operator`) if it is not present.

#### 3. Deploying Data Foundation in Provider Mode

If DF is not already installed, the script deploys it in **Provider Mode** via the `data-foundation-service` FSI.
Once deployed, DF is configured with:

* **Worker node labeling** – Applies required labels to all worker nodes.
* **LocalVolumeSet creation** – Instantiates a `LocalVolumeSet` for the cluster.
* **StorageCluster provisioning** – Creates a `StorageCluster` with a capacity that looks for and uses all local disks as backing stores.

#### 4. Creating DaemonSets with Assigned PVCs

Deploys a DaemonSet using PersistentVolumeClaims (PVCs) provisioned from a custom RBD StorageClass. This DaemonSet runs on all nodes that will run Scale Container Native and mounts the RBD volumes as local block devices.

#### 5. Mapping Device IDs to LocalDisk PVCs

The script automates mapping between **RBD block devices** and **PersistentVolumeClaims (PVCs)**:

* **Collect RBD devices** – Retrieves all RBD devices from the `csi-rbdplugin` container and records the node on which each pod runs.
* **Extract PV metadata** – For each PVC, locates its PV and reads the `pool` and `imageName` fields.
* **Match devices** – Uses the `pool` and `imageName` values to identify the corresponding device name in the RBD list.

#### 6. Scale Container Native Configuration

* **Service installation** – For Fusion SDS, patches the Spectrum Fusion CR to install the Global Data Platform (GDP) service. For Fusion HCI, installs the `scalemanager` Fusion service.
* **Scale cluster creation** – Creates a Scale `Cluster` CR, dynamically retrieving the cluster’s base domain and subdomain from the OpenShift environment to instantiate the initial Spectrum Scale cluster using the root domain.
* **Cluster verification** – Confirms the Scale Cluster is in a healthy, operational state.
* **Device-ID patch** – Applies a regex-formatted device ID to the `Cluster` CR.
* **LocalDisk creation** – Generates `LocalDisk` CRs based on the device-ID and node-name mapping.
* **Validation** – Ensures each `LocalDisk` reaches the *Ready* state and is shared.
* **Filesystem provisioning** – Creates a Scale `Filesystem` CR that utilizes the created `LocalDisks`.
* **Health check** – Verifies the `Filesystem`’s health and that it reaches the *Established* status.
* **Usage verification** – Confirms that the `LocalDisks` are actively used by the `Filesystem`.
* **Set up AFM** - Configures the Scale cluster for AFM by applying the appropriate node labels.

> [!NOTE]
> Installing GDP (if missing) triggers an MCO rollout on all worker nodes to deploy the kernel-devel package, which may take some time. Should the script time out or if connectivity is lost, the script can be safely re-run and will pick up where it left off.

#### 7. Deploying CAS with Scale Container Native local Filesystem

Finally, the script will install and configure CAS.

* **CAS installation** - Creates the Fusion Service Definition to deploy the `cas-operator` and `CasInstall` CR.
* **Configure Kafka Watch** - Automatically configures the Kafka Watch for the Scale cluster.

## Verification Script Usage

```bash
test/verify.sh
```

Example output:
```bash
$ ./tests/verify.sh
🔍 Running IBM Spectrum Scale Health Checks...
✅ StorageCluster is Ready
✅ Spectrum Scale Daemon is Available
✅ All Daemon pods running (6/6)
✅ Spectrum Scale Daemon is Healthy
✅ All pods are Running/Completed in ibm-spectrum-scale namespace
✅ All LocalDisks are shared & Healthy
✅ Filesystem is Healthy
🔧 Deploying test PVC...
⏳ Waiting for PVC 'cache-fs-test-pvc' to become Bound...
⏳ Attempt 1/6 → PVC Status: Pending
🎯 PVC Test: PASS
🧹 Cleanup: Removing test PVC and Namespace...
✅ Cleanup Complete.
```

## Cleanup Script

```bash
$ ./bin/cleanup-data-cache.sh [--filesystem-name <name>]
```

---
---

## Troubleshooting

### Image Pull Errors

* Check pod events for failures.
* Verify manifests for IDMS/ITMS issues.
* Ensure pull secrets are valid.

> [!NOTE]
> The image `registry.access.redhat.com/ubi8/ubi` must be **mirrored** into the internal registry and **IDMS/ITMS** must be configured. Missing mirroring will cause deployment failures in restricted networks.

<details>
<summary><strong>Show Offline / Internal Registry Configuration</strong></summary>

<br>

Log in to the IBM Entitled Container Registry by using the IBM entitlement key:

```bash
docker login cp.icr.io -u cp -p <your entitlement key>
```

> [!NOTE]
> Ensure that your entitlement key for IBM Fusion contains the correct entitlement.

Set the following environment variables:

```bash
export LOCAL_ISF_REGISTRY="<Your enterprise registry host>:<port>"
export LOCAL_ISF_REPOSITORY="<Your image path>"
export TARGET_PATH="$LOCAL_ISF_REGISTRY/$LOCAL_ISF_REPOSITORY"
```

Run the following commands to create files with the properly replaced variables:

```bash
$ cat << EOF > isf-mirror-idms.yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: isf-mirror-idms
spec:
  imageDigestMirrors:
  - mirrors:
      - $TARGET_PATH/cp
    source: icr.io/cp
  - mirrors:
      - $TARGET_PATH/cpopen
    source: icr.io/cpopen
  - mirrors:
      - $TARGET_PATH/cp
    source: cp.icr.io/cp
  - mirrors:
      - $TARGET_PATH/cpopen
    source: cp.icr.io/cpopen
EOF

$ oc apply -f isf-mirror-idms.yaml
```

```bash
$ cat << EOF > isf-gdp-idms.yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: isf-gdp-idms
spec:
  imageDigestMirrors:
  - mirrors:
      - $TARGET_PATH/cp/gpfs
    source: cp.icr.io/cp/gpfs
  - mirrors:
      - $TARGET_PATH/cp/spectrum/scale
    source: cp.icr.io/cp/spectrum/scale
EOF

$ oc apply -f isf-gdp-idms.yaml
```

```bash
$ cat << EOF > isf-fdf-idms.yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  labels:
    operators.openshift.org/catalog: "true"
  name: isf-fdf-idms
spec:
  imageDigestMirrors:
  - mirrors:
    - $TARGET_PATH/openshift4
    source: registry.redhat.io/openshift4
  - mirrors:
    - $TARGET_PATH/redhat
    source: registry.redhat.io/redhat
  - mirrors:
    - $TARGET_PATH/rhel9
    source: registry.redhat.io/rhel9
  - mirrors:
    - $TARGET_PATH/rhel8
    source: registry.redhat.io/rhel8
  - mirrors:
    - $TARGET_PATH/cp/df
    source: cp.icr.io/cp/df
  - mirrors:
    - $TARGET_PATH/cp/ibm-ceph
    source: cp.icr.io/cp/ibm-ceph
  - mirrors:
    - $TARGET_PATH/odf4
    source: registry.redhat.io/odf4
  - mirrors:
    - $TARGET_PATH/lvms4
    source: registry.redhat.io/lvms4
EOF

$ oc apply -f isf-fdf-idms.yaml
```

```bash
$ cat << EOF > isf-fdf-itms.yaml
apiVersion: config.openshift.io/v1
kind: ImageTagMirrorSet
metadata:
  name: isf-fdf-itms
spec:
  imageTagMirrors:
    - mirrors:
        - $TARGET_PATH/cpopen/isf-data-foundation-catalog
      source: icr.io/cpopen/isf-data-foundation-catalog
      mirrorSourcePolicy: AllowContactingSource
EOF

$ oc apply -f isf-fdf-itms.yaml
```

</details>

### Leftover Ceph metadata

* If StorageCluster is stuck in `Provisioning` phase (e.g., `failed to get device already provisioned by ceph-volume`), clean old Ceph metadata: [Red Hat Solution 7115651](https://access.redhat.com/solutions/7115651).
* After cleanup, wait for the storage cluster to reach `Ready` phase. Inspect with the following command:
  ```bash
  oc get storagecluster "$OCS_CLUSTER_NAME" -n $OCS_NAMESPACE -o jsonpath='{.status.phase}'
  ```

### IBM Spectrum Scale webhook issues

* If webhook errors occur (`no endpoints available for service "ibm-spectrum-scale-controller-manager-service"`), check for duplicate or conflicting webhooks.
* Set `failurePolicy: Ignore` to disable the webhook.

### LocalDisks in use

* If a disk is reported as already in use, set `skipVerify: true` in the `LocalDisk` CR in the `$SCALE_NAMESPACE` namespace.

### Node draining / stuck Node issues

* If a node is stuck during draining, check Machine Config Operator (MCO) logs and either manually scale down or force delete the affected pod replicas to proceed.
* If MCO shows no issues and the node is cordoned (scheduling disabled), uncordon the node manually.

### Scale Container Native lingering files and kernel modules

* If, prior to running the script, a previous installation of Scale Container Native was not cleanly uninstalled, it may be necessary to reboot the OpenShift nodes to bring the system back to a clean state.
  * Only reboot one node at a time, and wait for it to come back `Ready` before proceeding to another node.
* See the [Scale Container Native documentation](https://www.ibm.com/docs/en/scalecontainernative/6.0.0?topic=cleanup) for complete cleanup instructions.