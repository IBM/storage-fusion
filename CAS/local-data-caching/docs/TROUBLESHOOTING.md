# Troubleshooting

## Image Pull Errors

- Check pod events for failures.
- Verify manifests for IDMS/ITMS issues.
- Ensure pull secrets are valid.

For restricted network environments, see [Offline / Internal Registry Configuration](OFFLINE_REGISTRY.md).

## Leftover Ceph Metadata

If `StorageCluster` is stuck in `Provisioning` phase (e.g., `failed to get device already provisioned by ceph-volume`), clean old Ceph metadata: [Red Hat Solution 7115651](https://access.redhat.com/solutions/7115651).

After cleanup, wait for the storage cluster to reach `Ready` phase:

```bash
oc get storagecluster "$OCS_CLUSTER_NAME" -n $OCS_NAMESPACE -o jsonpath='{.status.phase}'
```

## IBM Spectrum Scale Webhook Issues

If webhook errors occur (`no endpoints available for service "ibm-spectrum-scale-controller-manager-service"`), check for duplicate or conflicting webhooks and set `failurePolicy: Ignore` to disable the webhook.

## LocalDisks In Use

If a disk is reported as already in use, set `skipVerify: true` in the `LocalDisk` CR in the `$SCALE_NAMESPACE` namespace.

## Node Draining / Stuck Node Issues

If an upgrade or node drain process appears to be stuck, refer to the following documentation:
- [Troubleshooting blocked upgrades and blocked node drains](https://www.ibm.com/docs/en/scalecontainernative/6.0.1?topic=troubleshooting-blocked-upgrades-blocked-node-drains)
- [Draining nodes](https://www.ibm.com/docs/en/scalecontainernative/6.0.1?topic=nodes-draining)

Checking the Pod logs in the `openshift-machine-config-operator` Namespace can also help reveal additional information.

## Scale Container Native Lingering Files and Kernel Modules

If a previous installation of Scale Container Native was not cleanly uninstalled, it could lead to a stale or failed kernel module load on one or more nodes. To resolve this, it may be necessary to reboot the OpenShift nodes to bring the system back to a clean state.

- Only reboot one node at a time, and wait for it to come back `Ready` before proceeding to another node.
- See the [Scale Container Native documentation](https://www.ibm.com/docs/en/scalecontainernative/6.0.1?topic=cleanup) for complete cleanup instructions.

## Namespace Stuck in Terminating

If a Namespace (e.g. `ibm-cas`) is stuck in `Terminating`, CRs with finalizers are blocking deletion. Identify and patch them:

```bash
# Find all CRs in ibm-cas with finalizers
for crd in $(oc api-resources --verbs=list --namespaced -o name 2>/dev/null); do
  items=$(oc get "${crd}" -n ibm-cas \
    -o jsonpath='{range .items[?(@.metadata.finalizers)]}{.metadata.name}{" ("}{.kind}{")"}{ "\n"}{end}' 2>/dev/null)
  [[ -n "${items}" ]] && echo "${items}"
done

# Remove finalizers from each stuck CR:
oc patch <kind> <name> -n ibm-cas \
  --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
```

Once all finalizers are cleared the namespace will finish terminating. Wait before re-running setup:

```bash
oc wait namespace ibm-cas --for=delete --timeout=120s
```

## Scale Daemon Timeout with ODF ≥ 4.21.0

If `setup-data-cache.sh` exits with `Timeout: Scale Daemon did not come up within 300s` on a cluster running ODF 4.21.0 or higher, the `odf-operator-controller-manager` pod has failed to scale up the Scale operator Deployment. Restart it and re-run setup:

```bash
oc rollout restart deployment/odf-operator-controller-manager -n openshift-storage
oc rollout status deployment/odf-operator-controller-manager -n openshift-storage --timeout=120s
./bin/setup-data-cache.sh
```
