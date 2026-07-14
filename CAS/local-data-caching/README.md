# Local Data Caching for Content Aware Storage (CAS)

This tool deploys a configuration of IBM Fusion services that enable local caching of data from remote S3 buckets for ingestion by CAS. This is achieved by setting up an IBM Storage Scale Container Native (formerly known as CNSA) local Scale cluster on OpenShift Container Platform using local Data Foundation (DF) RBD volumes as backing storage devices.

The scripts in these directories work against both Fusion SDS and Fusion HCI.

---

## Cluster Requirements

* OpenShift version **4.18** or higher, **4.20** is recommended
* IBM Fusion SDS or HCI **2.12** or higher (default install target: **2.13**)
* **Cluster admin access**
* At least **3 worker nodes** OR **Compact cluster** with at least one local disk per node, recommended at least 1TB disks
* At least 1 node with [supported GPUs](https://www.ibm.com/docs/en/fusion-software/2.12.0?topic=prerequisites-system-requirements#systemrequirements__table_xpm_ddx_rgc)

### Required System Tools

* Host with connectivity to the OCP API
* `bash` or `zsh`
* `oc` client
* `envsubst`
* `yq` — used by `setup-data-cache.sh`
* `jq` — used by `setup-data-cache.sh` and `cleanup-data-cache.sh`
* `curl` — used by `cleanup-data-cache.sh` to download the CAS cleanup script if not already present locally

## Setup Script Usage

```bash
./bin/setup-data-cache.sh [--filesystem-name <name>] [--filesystem-capacity <Gi>]
```

### Optional Inputs

| Flag                    | Description                | Default    |
| ----------------------- | -------------------------- | ---------- |
| `--filesystem-name`     | Name of the filesystem     | `cache-fs` |
| `--filesystem-capacity` | Capacity of the filesystem as [Kubernetes Quantities](https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/) (e.g. Gi, Ti, G, T) | `256Gi` |

### Configuration Parameters

The script uses additional configuration parameters that can be modified either in the [config/config.env](./config/config.env) file or by exporting them in the shell prior to running the script. These include, among others:

* **FUSION_VERSION** – Version of Fusion to install (controls the CatalogSource image) (default: `2.13.0`)
* **FUSION_NAMESPACE** – Namespace where the Fusion operator will be installed (default: `ibm-spectrum-fusion-ns`)
* **INSTALL_STRATEGY** – Install strategy for the operator: `Automatic` or `Manual` (default: `Automatic`)
* **ODF_ALLOW_ROTATIONAL** – Set to `true` to allow rotational (HDD) disks to be used as ODF backing storage. Some platforms (VMware, Nutanix, Hyper-V, etc.) do not properly present drives as non-rotational; enabling this bypasses that check. (default: `false`)

### What the Script Does

#### 1. Pre-validations

Before launching the deployment, the script verifies:

* **Connectivity** – Confirms a successful connection to the OpenShift cluster.
* **Cluster version** – Ensures the cluster is on a supported OpenShift release.
* **Permissions** – Validates that the executing user holds Cluster-Admin privileges.
* **Local Storage Operator (LSO)** – Verifies the availability of the OpenShift Local Storage Operator.

#### 2. Fusion Deployment

If Fusion is not installed, the script will install the IBM Fusion Operator (`isf-operator`) and apply the Spectrum Fusion Custom Resource (CR).

#### 3. Deploying Data Foundation in Provider Mode

If DF is not already installed, the script deploys it in **Provider Mode** via the `data-foundation-service` FSI.
Once deployed, DF is configured with:

* **Worker node labeling** – Applies required labels to all worker nodes.
* **LocalVolumeSet creation** – Instantiates a `LocalVolumeSet` for the cluster.
* **StorageCluster provisioning** – Creates a `StorageCluster` that uses all available local disks as backing stores.

#### 4. Scale Container Native Configuration

* **Service installation** – Installs the Scale service and operator.
  * For Fusion 2.12, it patches the `SpectrumFusion` CR to enable Global Data Platform (GDP).
  * For Fusion 2.13+ with DF 4.21+, Scale is managed by DF and the operator is created when the first `Cluster` CR is detected.
* **Scale cluster creation** – Creates a Scale `Cluster` CR, dynamically retrieving the cluster's base domain and subdomain from the OpenShift environment.
* **Cluster verification** – Confirms the Scale Cluster is in a healthy, operational state.

> [!NOTE]
> Creating a Scale Cluster triggers a rollout on all worker nodes to build and mount the GPFS kernel module, which can take some time depending on the number of nodes in the cluster. Should the script time out or if connectivity is lost, the script can be safely re-run and will pick up where it left off.

#### 5. Deploying CAS with Scale Container Native Local Filesystem

The script will install and configure CAS with a local Scale Filesystem service as an AFM cache.

* **Set up AFM** – Configures the Scale cluster for AFM by applying the appropriate node labels.
* **Filesystem creation** – Creates the Scale `Filesystem` CR.
* **Configure Kafka Watch** – Automatically configures the Kafka Watch for the Scale cluster.
* **CAS installation** – Creates the Fusion Service Definition to deploy the `cas-operator` and `CasInstall` CR.

## Migration Script Usage

The migration is required when upgrading from CAS 1.1.4 to CAS 1.1.5 if you have an existing local Filesystem cache configured in CAS 1.1.4.

```bash
./bin/migrate-data-cache.sh --migration-phase <phase> [OPTIONS]
```

Run `./bin/migrate-data-cache.sh --help` for the full flag and environment variable reference.

See [docs/MIGRATION.md](docs/MIGRATION.md) for the complete migration guide including phases, workflow, and environment variables.

## Cleanup Script

Removes the data cache deployment. A required action flag determines the scope of cleanup.

```bash
./bin/cleanup-data-cache.sh <ACTION> [--filesystem-name <name>]
```

| Action      | Scope |
| ----------- | ----- |
| `--cas`     | CAS only |
| `--cnsa`    | CAS and Scale Container Native |
| `--df`      | CAS, Scale Container Native, and Data Foundation |
| `--all`     | CAS, Scale Container Native, Data Foundation, and Fusion (SDS only) |

Run `./bin/cleanup-data-cache.sh --help` for the full reference.

---

## Further Reading

* [Migration Guide](docs/MIGRATION.md)
* [Troubleshooting](docs/TROUBLESHOOTING.md)
* [Known Issues and Manual Workarounds](docs/KNOWN_ISSUES.md)
