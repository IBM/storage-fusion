# Fusion ManagedCluster Pre-Upgrade Precheck

[`fusion_managedcluster_preupgrade_precheck_v1.sh`](fusion_managedcluster_preupgrade_precheck_v1.sh) is a **read-only** health check. Run it before upgrading an IBM Fusion HCI hub that manages spoke clusters (ManagedClusters). Spoke kubeconfigs are fetched automatically for Hosted Control Plane (HCP) clusters. For any other ManagedCluster, pass its kubeconfig with `-s`. It only runs `get`, `logs` and `whoami`. It never creates, changes or deletes anything.

## What it checks

- **Hub:**
  - Operator CSVs and subscriptions.
  - Fusion controllers.
  - Ceph health.
  - Stuck deletions.
  - HostedCluster and NodePool health (HCP clusters only).
  - Duplicate IDMS/ICSP mirrors.
  - OCP/Fusion/Data Foundation version support.
- **Hub and spoke consistency:** `isf.ibm.com/fusion-*` ManagedCluster labels against StorageConsumers and spoke resources. This catches the case where a ManagedCluster was recreated without its addon labels.
- **Each spoke:** for HCP clusters the script gets the spoke's `admin-kubeconfig` automatically from the hub. For other clusters it uses the kubeconfig you pass with `-s`. It then checks:
  - Node quorum and OCP version skew.
  - Terminating namespaces, pods and PVCs.
  - The fusion-base, fusion-fdf, fusion-backup and fusion-gdp-rm addons (agents, CSVs, pods, FusionServiceInstances).
  - StorageClient connectivity.
  - In-flight backups and restores.

## Prerequisites

- `oc` (or `kubectl`), `bash`, `base64`.
- A hub kubeconfig with cluster-admin access.
- Network access to the hub and to each spoke API server.

## Run

```bash
# All ManagedClusters
./fusion_managedcluster_preupgrade_precheck_v1.sh -k /path/to/hub-kubeconfig

# One cluster
./fusion_managedcluster_preupgrade_precheck_v1.sh -k /path/to/hub-kubeconfig -c <cluster-name>
```

| Option / env var | Purpose |
|---|---|
| `-k`, `HUB_KUBECONFIG` | Hub kubeconfig. Defaults to `$KUBECONFIG`, then `~/.kube/config`. |
| `-c`, `TARGET_CLUSTER` | Limit the per-cluster checks (label audit, addon/ManifestWork, HostedCluster/NodePool and spoke checks) to one ManagedCluster. Hub-wide checks (operators, controllers, Ceph, GitOps) still run. |
| `-s`, `SPOKE_KUBECONFIGS` | Spoke kubeconfig files. **Required for non-HCP clusters.** Also use it for an HCP cluster when automatic extraction fails. See [Providing spoke kubeconfigs](#providing-spoke-kubeconfigs--s). |
| `--ns-fusion`, `--ns-storage` | Override `ibm-spectrum-fusion-ns` and `openshift-storage`. |
| `MIN_SPOKE_READY_NODES` | Minimum Ready, schedulable nodes per spoke. Default `3`. |
| `CONTROLLER_RESTART_THRESHOLD` | Maximum container restarts for hub controllers. Default `50`. |
| `--skip-redaction` | Keep tokens and secrets in the output. Do not use this for files you will share. |

### Providing spoke kubeconfigs (`-s`)

HCP clusters need nothing extra: the script reads each one's `admin-kubeconfig` secret from the hub. For every other ManagedCluster, save a kubeconfig for that cluster and pass the file with `-s`. Without it, that cluster gets a `WARN` and `NO_KUBECONFIG`, and its spoke checks are skipped.

Rules:

- Pass **files**, not a directory.
- Put all files in **one quoted, space-separated argument**. Paths cannot contain spaces.
- The path must contain the ManagedCluster name. The script matches by substring, so `edge1` also matches `edge10`. Use unambiguous names.
- Each kubeconfig must point at the spoke, not the hub. A kubeconfig that points at the hub gets a `STOP`.
- Clusters you don't list are handled as usual: HCP clusters use the automatic path, and others get `NO_KUBECONFIG`.

Example: the hub also manages two standalone clusters, `edge-site1` and `edge-site2`, and you want the whole fleet checked:

```bash
./fusion_managedcluster_preupgrade_precheck_v1.sh \
  -k /path/to/hub-kubeconfig \
  -s "/path/to/kubeconfigs/edge-site1.kubeconfig /path/to/kubeconfigs/edge-site2.kubeconfig"
```

To check just one of them:

```bash
./fusion_managedcluster_preupgrade_precheck_v1.sh \
  -k /path/to/hub-kubeconfig -c edge-site1 \
  -s /path/to/kubeconfigs/edge-site1.kubeconfig
```

The environment variable form is equivalent: `SPOKE_KUBECONFIGS="<file> <file>"`.

## Reading the results

Each line is tagged `[PASS]`, `[INFO]`, `[WARN]` or `[STOP]`.

| Result | Exit code | Action |
|---|---|---|
| `NOT SAFE TO UPGRADE` (one or more `STOP`) | `2` | **Do not upgrade.** Fix every `STOP` and re-run. |
| `SAFE TO UPGRADE WITH WARNINGS` | `0` | Review each `WARN`. Resolve it, or get IBM Support to confirm it is acceptable. |
| `SAFE TO UPGRADE` | `0` | Proceed. |
| Prerequisite or usage error | `1` | Fix the kubeconfig, CLI or option and re-run. |

A per-cluster readiness table is printed at the end. Spokes that show `NO_KUBECONFIG` or `FAILED_CONNECT` were **not** fully checked. Restore access, or pass `-s`, and re-run.

**Non-HCP ManagedClusters:** the hub-side checks run for every ManagedCluster. Automatic spoke access only works for HCP clusters. For any other cluster you get a `WARN` and `NO_KUBECONFIG` unless you supply its kubeconfig with `-s`. The spoke checks with `-s` are best-effort and have not been verified on non-HCP clusters.

### Output

The script writes a `precheck-<UTC timestamp>/` directory:

- `SUMMARY.txt`: every PASS, WARN and STOP message.
- `WORKFLOW_STATUS_REPORT.txt`: the per-cluster readiness table.
- `clusters/`, `snapshot/` and `hub_*.txt`: the raw command output behind each finding.

The temporary spoke kubeconfigs are deleted when the script exits. Tokens and secrets are redacted by default. Check the directory before sharing it.

## Resolving common findings

| Finding | What to do |
|---|---|
| Ceph not `HEALTH_OK` | Fix storage health first. Never upgrade on degraded storage. |
| CSV not `Succeeded`, controller or agent has 0 ready replicas, pod in CrashLoop | Check the pod logs and events. Fix the cause, or open an IBM Support case. |
| Terminating or stuck-deletion objects (StorageConsumer, CephClient, ManagedClusterAddOn, ManifestWork, namespace, PVC, StorageClient) | Find what is blocking deletion (finalizers, dependent resources). Let the deletion finish, or get IBM Support guidance before removing finalizers. |
| ManagedCluster missing `isf.ibm.com/fusion-*` label while the spoke has that addon, or a ManagedCluster newer than its StorageConsumer | **Stop and contact IBM Support.** The ManagedCluster was probably recreated or pruned. Do not re-label or delete anything on your own. |
| StorageConsumer has no matching ManagedCluster | Contact IBM Support. |
| GitOps (ArgoCD/Flux) `prune` or `selfHeal` warning | Turn off automated prune for the upgrade window. |
| HostedCluster or NodePool not Available, updating or paused | Wait for it to finish or unpause it. Re-run when it is stable. |
| `status-reporter` reports `no storageConsumer found` | The StorageConsumer is missing on the hub. Contact IBM Support. |
| Fusion subscription set to `Automatic` | Switch to `Manual` approval before upgrading. |
| In-flight backups or restores | Wait for them to finish or cancel them. |
| Version warnings (OCP, Data Foundation) | Compare against the supported matrix for your target Fusion release. |
| Duplicate IDMS/ICSP mirror source | The warning shows which objects define the source and whether their mirrors are `identical` or `DIFFERENT`. Identical is usually harmless, so remove the redundant entry when convenient. If the mirrors differ, make sure each one is reachable and has the images, and fix any stale entry. Changing IDMS/ICSP reboots nodes, so do it outside the upgrade window. |
| Spoke below node minimum or too far behind the hub OCP version (0–2 minors) | Fix the spoke capacity or version first. |
| Node under Memory/Disk/PID pressure, or NodePool `AllNodesHealthy=False` / fewer ready nodes than desired | Check `oc describe node <node>` on the spoke. Free memory, disk or PIDs, or add capacity, until the node is healthy. Re-run. |

Re-run the script until the result is `SAFE TO UPGRADE`. If you need IBM Support, attach `SUMMARY.txt` and the relevant `clusters/` and `snapshot/` files.
