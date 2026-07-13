# W004 — CAS Upgrade Never Completes: Kafka Certs Job Deleted and Recreated in a Loop

**Recurrence:** Recurrent — must be applied on every `1.1.4 → 1.1.5` upgrade where
`spec.cache` is configured on the CasInstall.

---

## Symptom

After `setup-data-cache.sh` exits with `spec.cache` set on CasInstall, the CAS upgrade from
1.1.4 to 1.1.5 never completes. `status.version.current` remains `1.1.4`. Operator logs
show the following pattern repeating:

```
KafkaCertificates, Job already exists
KafkaCertificates, Waiting for job to complete
...
KafkaCertificates, Job succeeded, deleting it
KafkaCertificates, Creating Job
KafkaCertificates, Waiting for job to complete
```

The `cas-kafka-certs-export-ceph` job is deleted immediately after completion, then
re-created, looping indefinitely. `AfterUpgrade` hooks and the step that writes
`status.version.current = 1.1.5` are never reached.

## Root Cause

Two code paths in the upgrade reconciler share the same hardcoded job name
(`cas-kafka-certs-export-ceph`). When the first path deletes the completed job, the second
path immediately recreates it. The upgrade can never advance past the job wait.

## When to Apply

**After `setup-data-cache.sh` exits and `spec.cache` is confirmed set on CasInstall.**
Watch for the `cas-kafka-certs-export-ceph` job to appear and reach `Succeeded` state — the
finalizer must be added inside that narrow window.

The finalizer must be removed after the upgrade completes (step 4 below).

## Steps

**Step 1 — Watch for the job and add a finalizer while it is in `Succeeded` state:**

```bash
# Poll until the job exists and is complete, then immediately run:
oc patch job cas-kafka-certs-export-ceph -n ibm-cas \
  --type=merge \
  -p '{"metadata":{"finalizers":["cas.isf.ibm.com/keep-for-upgrade"]}}'
```

**Step 2 — Wait for the upgrade to complete.** Watch operator logs for:

```
Upgrade reconciliation is complete
```

**Step 3 — Confirm the `operator-config` ConfigMap has a valid `KAFKA_AUTHEN_LOCAL` path:**

```bash
oc get configmap operator-config -n ibm-cas \
  -o jsonpath='{.data.KAFKA_AUTHEN_LOCAL}{"\n"}'
# Expected: non-empty path, e.g. /mnt/cache-fs/...
```

**Step 4 — Remove the finalizer:**

```bash
oc patch job cas-kafka-certs-export-ceph -n ibm-cas \
  --type=merge -p '{"metadata":{"finalizers":null}}'
```

## Verify

```bash
oc get casinstall ibm-cas-service-instance -n ibm-cas \
  -o jsonpath='{.status.version.current}{"\n"}'
# Expected: 1.1.5
```
