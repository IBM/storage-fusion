# How to Apply — MinIO → RADOS Migration

## Pre-requisites

- IBM Backup & Restore is installed in the **`ibm-backup-restore`** namespace.
- The following secrets exist in that namespace **before** running the job:
  - `cloud-credentials` — keys `miniouser` and `miniopassword` (MinIO credentials)
  - `zgw-posix-user` — keys `ACCESS_KEY` and `SECRET_KEY` (RADOS credentials)
- Either `oc` (OpenShift CLI) **or** `kubectl` is available on your workstation.  
  If neither is available, follow the **OCP Web Console** path in Step 1.

---

## Step 1 — Apply the migration Job

### Option A — Using `oc` or `kubectl`

```bash
# Switch to the correct namespace
oc project ibm-backup-restore
# -- or --
kubectl config set-context --current --namespace=ibm-backup-restore

# Apply the Job
oc apply -f job.yaml
# -- or --
kubectl apply -f job.yaml
```

### Option B — Using the OCP Web Console (no CLI required)

1. Open the OpenShift Web Console in your browser.
2. In the top-left project dropdown, select **`ibm-backup-restore`**.
3. Navigate to **Workloads → Jobs**.
4. Click **Create Job** (top-right corner).
5. Switch the editor to **YAML view**.
6. Delete the placeholder content, then paste the **entire contents** of [`job.yaml`](./job.yaml).
7. Click **Create**.

---

## Step 2 — Monitor the Job

```bash
# Watch Job status
oc get job minio-to-rados-migration -n ibm-backup-restore -w

# Stream logs from the migration pod
oc logs -n ibm-backup-restore -l app=minio-to-rados-migration -f
```

A successful run ends with:

```
========================================
MIGRATION COMPLETED SUCCESSFULLY
========================================
```

> **Note:** The Job has `backoffLimit: 0` and will **not** retry automatically on failure.  
> If it fails, inspect the logs, fix the issue, then follow the re-run steps below.

---

## Step 3 — Delete deprecated MinIO resources

Once migration is confirmed successful, run the cleanup script:

```bash
# Default namespace: ibm-backup-restore
./delete-minio-resources.sh

# Or pass a custom namespace
./delete-minio-resources.sh <NAMESPACE>
```

The script removes:

- `StatefulSet/guardian-minio`
- `Service/guardian-minio-svc`
- `ServiceAccount/guardian-minio`
- `PersistentVolumeClaim/minio`
- `Secret/cloud-credentials`
- `BackupStorageLocation.velero.io/guardian-minio`

> All deletes use `--ignore-not-found` — safe to run even if some resources were already removed.

---

## Troubleshooting

### Job stays in `Pending`

Verify both secrets exist in the namespace:

```bash
oc get secret cloud-credentials zgw-posix-user -n ibm-backup-restore
```

### MinIO connectivity fails

```bash
# Check MinIO pod is running
oc get pod -n ibm-backup-restore -l app=guardian-minio

# Check MinIO service exists
oc get svc guardian-minio-svc -n ibm-backup-restore
```

### RADOS connectivity fails

```bash
# Check ZGW/Posix service exists
oc get svc s3-posix -n ibm-backup-restore

# Verify RADOS credentials secret
oc get secret zgw-posix-user -n ibm-backup-restore
```

### Re-running the Job after a failure

```bash
# Delete the failed Job (and its pod)
oc delete job minio-to-rados-migration -n ibm-backup-restore

# Re-apply
oc apply -f job.yaml
```
