# W006 — cast-runtime Pod Pending: Stale PVC Reference After DataSource Recreate

**Recurrence:** Recurrent — must be applied after every migration restore that causes a
DataSource CR to be deleted and recreated with a new PVC name.

---

## Symptom

After a migration restore that causes a DataSource CR to be deleted and recreated, the
cast-runtime pod stays `Pending`. Pod events show a missing or inaccessible volume. The
Deployment still references the old (deleted) PVC while the recreated DataSource has
published a new PVC name:

```bash
# New PVC as advertised by the DataSource
oc get datasource <domain>-datasource -n ibm-cas \
  -o jsonpath='{.metadata.annotations.pvc-name}{"\n"}'
# prints: <new-pvc-name>

# PVC still in the Deployment (mismatch)
oc get deployment <cast-deploy> -n ibm-cas \
  -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{"="}{.persistentVolumeClaim.claimName}{"\n"}{end}'
# prints: <old-pvc-name>=<old-pvc-name>
```

## Root Cause

The operator does not reconcile the cast-runtime Deployment's PVC reference against the
DataSource `pvc-name` annotation after a DataSource delete-and-recreate. The stale reference
persists in the Deployment until manually patched.

## When to Apply

**After the schema-init requeue loop ([W005](W005-schema-init-ttl-requeue-loop.md)) is
resolved** and the cast-runtime pod is still `Pending` with a PVC mismatch confirmed. Both
issues must be addressed for the cast-runtime pod to reach `Running`.

## Steps

```bash
DOMAIN=$(oc get domain -n ibm-cas -o jsonpath='{.items[0].metadata.name}')
CAST_DEPLOY=$(oc get deployment -n ibm-cas \
  -l app.kubernetes.io/component=cast-runtime \
  -o jsonpath='{.items[0].metadata.name}')
NEW_PVC=$(oc get datasource -n ibm-cas "${DOMAIN}-datasource" \
  -o jsonpath='{.metadata.annotations.pvc-name}')

oc patch deployment "${CAST_DEPLOY}" -n ibm-cas --type=json -p="[
  {\"op\":\"replace\",\"path\":\"/spec/template/spec/volumes/1/name\",\"value\":\"${NEW_PVC}\"},
  {\"op\":\"replace\",\"path\":\"/spec/template/spec/volumes/1/persistentVolumeClaim/claimName\",\"value\":\"${NEW_PVC}\"},
  {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/volumeMounts/1/name\",\"value\":\"${NEW_PVC}\"}
]"
```

## Verify

```bash
oc get pod -n ibm-cas -l app.kubernetes.io/component=cast-runtime
# Expected: Running

oc get datasource -n ibm-cas \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.connectionStatus}{"\n"}{end}'
# Expected: Connected
```
