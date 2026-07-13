# W005 — Schema-Init Job Requeue Loop: cast-runtime Deployment Never Updated

**Recurrence:** Recurrent — must be applied after every DataSource delete-and-recreate that
triggers a schema-init job (e.g., after each migration restore).

---

## Symptom

After a DataSource is deleted and recreated (e.g., following a migration restore), the
cast-runtime pod remains `Pending` and the operator logs repeat:

```
Created schema initialization job, requeuing  Job=db-schema-init-<domain>
Requeue requested  reason="requeue requested while waiting for schema job to complete"
```

The cast-runtime `Deployment` is never updated with the new PVC name. The pod stays
`Pending` indefinitely.

## Root Cause

The `db-schema-init-<domain>` Job has a 5-minute TTL (`ttlSecondsAfterFinished: 300`).
After Kubernetes garbage-collects the completed job, the operator has no record that schema
init already succeeded. On every subsequent reconcile it re-creates the job and returns a
requeue error before ever reaching the Deployment update step.

## When to Apply

**Within 5 minutes of the `db-schema-init-<domain>` job completing** — before the TTL
garbage collector fires.

If the 5-minute window is missed, the job will already be gone and the loop will have
started. In that case:

1. Delete the looping job so the operator recreates it fresh:
   ```bash
   oc delete job db-schema-init-<domain> -n ibm-cas
   ```
2. Immediately apply the patch below on the newly created job before it completes.

## Steps

```bash
# Replace <domain> with your domain name (e.g. deucalion-domain)
oc patch job db-schema-init-<domain> -n ibm-cas --type=json \
  -p='[{"op":"remove","path":"/spec/ttlSecondsAfterFinished"}]'
```

## Verify

The operator should stop producing requeue log entries and proceed to update the cast-runtime
Deployment. The cast-runtime pod should transition from `Pending` to `Running` within a
minute or two as subsequent reconcile steps complete.

```bash
oc get pod -n ibm-cas -l app.kubernetes.io/component=cast-runtime
# Expected: Running
```

> **Note:** If the cast-runtime pod is still `Pending` after the requeue loop stops, also
> check for a stale PVC reference in the Deployment — see
> [W006](W006-cast-runtime-stale-pvc.md).
