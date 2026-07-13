# CAS Data Cache Migration

This migration is required when upgrading from CAS 1.1.4 to CAS 1.1.5 if you have an existing local Filesystem cache configured in CAS 1.1.4.

## Usage

```bash
./bin/migrate-data-cache.sh --migration-phase <phase> [OPTIONS]
```

Run `./bin/migrate-data-cache.sh --help` for the full flag and environment variable reference.

## Prerequisites

- OpenShift cluster connection (`oc login`)
- Cluster admin privileges
- CAS 1.1.4+
- Scale filesystem deployed by `setup-data-cache.sh`

## Migration Phases

| Phase     | Description |
| --------- | ----------- |
| `pre`     | Back up DataSources and record migration state before a Fusion/CAS upgrade |
| `post`    | Restore DataSources from backup after the upgrade completes; removes all migration resources on success |
| `full`    | Execute `pre` and `post` in sequence; removes all migration resources on success |
| `cleanup` | Delete all migration resources (Jobs, ConfigMaps, NetworkPolicy, PVC, RBAC) without running a migration Job |

## Workflow

### Standard upgrade

1. Run the `pre` phase before upgrading Fusion or CAS:
   ```bash
   ./bin/migrate-data-cache.sh --migration-phase pre
   ```
2. Delete the Scale Filesystem, LocalDisk CRs, and local storage namespace:
   ```bash
   oc label -n ibm-spectrum-scale filesystem cache-fs scale.spectrum.ibm.com/allowDelete=
   oc delete filesystem cache-fs -n ibm-spectrum-scale --ignore-not-found
   oc delete localdisk disk0 disk1 disk2 -n ibm-spectrum-scale --ignore-not-found
   oc delete namespace local-disk-as-pv --ignore-not-found
   ```
   Wait for the filesystem deletion to complete:
   ```bash
   oc wait filesystem cache-fs -n ibm-spectrum-scale --for=delete --timeout=300s
   ```
3. Perform the Fusion/CAS upgrade.
4. Run the `post` phase to restore:
   ```bash
   ./bin/migrate-data-cache.sh --migration-phase post
   ```

### Re-running after a failure

If a Job fails, delete it before re-running:

```bash
DELETE_PREVIOUS_JOBS=true ./bin/migrate-data-cache.sh --migration-phase pre
```

### Teardown

To remove all migration resources after a confirmed complete migration:

```bash
PRESERVE_JOB_RESOURCES=false ./bin/migrate-data-cache.sh --migration-phase cleanup
```

## Environment Variables

| Variable                    | Default  | Description |
| --------------------------- | -------- | ----------- |
| `DELETE_PREVIOUS_JOBS`      | `false`  | Delete existing Jobs for the phase before running (required to re-run after failure) |
| `PRESERVE_JOB_RESOURCES`    | `true`   | When `false`, delete all migration resources on exit |

## Running Tests

```bash
./tests/test_migrate_cas_filesystem.sh
```
