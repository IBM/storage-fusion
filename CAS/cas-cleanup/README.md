# IBM CAS Cleanup Script (Customer‑Safe)

## Overview

`customer_cas_cleanup.sh` is a **customer‑safe, interactive cleanup script** designed to uninstall **IBM Cloud Application Services (CAS)** from an **OpenShift** cluster.

The script focuses on **safe and controlled cleanup**:

* No forced deletions by default
* Finalizers are respected unless explicitly approved
* Interactive confirmation before destructive actions
* Optional preservation of data and namespace

It is suitable for **production and customer environments** where safety and visibility are critical.

---

## Key Features

* Removes CAS Custom Resources (CRs)
* Cleans up Kafka resources (Topics, Users, Brokers)
* Uninstalls CAS operators and ClusterServiceVersions (CSVs)
* Deletes CAS CatalogSource
* Cleans up namespace‑scoped RBAC artifacts
* Deletes Pods, PVCs, and associated PVs (Released / Failed states)
* Optional preservation of:

  * `cluster-parade` Pods and PVCs
  * Entire namespace
* Handles FusionServiceInstance cleanup (if present)
* Parallelized deletion for faster cleanup
* Retry mechanism with optional finalizer removal (manual approval)

---

## ⚠️ Safety Warnings

> **This script performs destructive operations.**

Before running:

* Ensure **backups or snapshots** exist
* Review all options carefully
* Run only with **cluster-admin** privileges

### Important Safety Guarantees

* ❌ No automatic force deletion
* ❌ No silent finalizer patching
* ✅ User confirmation required for risky operations

---

## Prerequisites

* OpenShift CLI (`oc`) installed
* Logged into the cluster:

  ```bash
  oc login
  ```
* Sufficient privileges:

  * `cluster-admin` or equivalent

---

## Usage

```bash
./customer_cas_cleanup.sh [options]
```

### Options

| Option                   | Description                             | Default   |
| ------------------------ | --------------------------------------- | --------- |
| `-n, --namespace <name>` | Target CAS namespace                    | `ibm-cas` |
| `--keep-paradedb`        | Preserve `cluster-parade` Pods and PVCs | `false`   |
| `--keep-namespace`       | Do not delete the namespace             | `false`   |
| `--help`                 | Display usage help                      | —         |

---

## Examples

### Full CAS Cleanup (Default)

Deletes all CAS components **including namespace**:

```bash
./customer_cas_cleanup.sh
```

---

### Preserve `cluster-parade` Data

Keeps ParadeDB Pods and PVCs:

```bash
./customer_cas_cleanup.sh --keep-paradedb
```

---

### Preserve Namespace

Cleans resources but **does not delete the namespace**:

```bash
./customer_cas_cleanup.sh --keep-namespace
```

---

### Custom Namespace Cleanup

```bash
./customer_cas_cleanup.sh -n custom-cas-namespace
```

---

## Execution Flow

The script executes cleanup in the following order:

1. **Interactive Confirmation**
2. Resource cleanup (Pods, Secrets, ConfigMaps, CRs)
3. PVC and PV cleanup (parallelized)
4. CAS CatalogSource deletion
5. Kafka resource cleanup
6. CAS‑specific CRD instance cleanup
7. Final namespace‑scoped cleanup
8. FusionServiceInstance removal (if present)
9. Operator and CSV uninstallation
10. Namespace deletion (optional)

Each step:

* Logs start and completion
* Retries deletion
* Requests approval before force removal

---

## Retry & Finalizer Handling

If a resource does not delete after multiple retries:

* The script **prompts the user**
* User may choose to:

  * Patch/remove finalizers
  * Force delete the resource

This ensures **no unsafe automatic force deletion**.

---

## FusionServiceInstance Handling

The script automatically:

* Detects the Fusion namespace
* Attempts deletion of:

  * `ibm-cas-service-instance` (mandatory)
  * `cas-install-redstack` (optional)

Missing optional instances are skipped safely.

---

## Logging & Output

* Clear step‑wise logs
* Resource‑level status messages
* Explicit confirmation prompts

Successful completion ends with:

```text
IBM CAS gets cleaned up successfully.
```

---

## Exit Conditions

* User aborts confirmation → **safe exit**
* Namespace not found → **exit with error**
* Individual step failures → logged and script continues

---

## Best Practices

* Run during maintenance window
* Avoid parallel cluster operations during cleanup
* Review logs before reinstallation
* Reboot nodes only if storage cleanup requires it

---

## Disclaimer

This script is provided **as‑is**.

Always validate in **lower environments** before executing in production.

---

## Maintainer

IBM CAS / ISF Platform Operations

---

## License

Internal / Customer Operations Utility
