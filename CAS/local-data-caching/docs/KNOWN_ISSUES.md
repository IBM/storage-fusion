# Known Issues and Manual Workarounds

This document describes known issues that require manual intervention and have no automated
fix at this time.

> **Note:** Workarounds marked *Recurrent* must be re-applied on every CAS install or upgrade.
> Workarounds marked *Non-Recurrent* are applied once to the cluster and persist.

---

## Workaround Index

| # | Title | Recurrence |
|---|-------|------------|
| [W001](workarounds/W001-eventmanager-networkpolicy.md) | CAS operator reconcile stalls ~60 s — missing EventManager NetworkPolicy | Non-Recurrent |
| [W002](workarounds/W002-fsgroup-scc-override.md) | docling / vllm / cast-runtime CrashLoopBackOff or permission denied — SCC fsGroup override | Non-Recurrent |
| [W003](workarounds/W003-kafka-version-unsupported.md) | Upgrade stalls — Kafka CR patched to unsupported version | Recurrent |
| [W004](workarounds/W004-kafka-certs-job-loop.md) | CAS upgrade never completes — Kafka certs job deleted and recreated in a loop | Recurrent |
| [W005](workarounds/W005-schema-init-ttl-requeue-loop.md) | Schema-init job requeue loop — cast-runtime Deployment never updated | Recurrent |
| [W006](workarounds/W006-cast-runtime-stale-pvc.md) | cast-runtime pod Pending — stale PVC reference after DataSource recreate | Recurrent |

## Ordered Application Sequence

Apply workarounds in phase order. Within each phase apply them top-to-bottom.

### Phase 0 — Pre-Install *(apply once, before CAS installation starts)*

| Workaround | When |
|------------|------|
| [W001 — EventManager NetworkPolicy](workarounds/W001-eventmanager-networkpolicy.md) | Before CAS install begins |
| [W002 — SCC fsGroup Override](workarounds/W002-fsgroup-scc-override.md) | Before DocumentProcessor / vllm / docling pods first start |

### Phase 1 — Post-Cache-Enable *(apply after `setup-data-cache.sh` exits, CAS 1.1.5 only)*

| Workaround | When |
|------------|------|
| [W003 — Kafka Version](workarounds/W003-kafka-version-unsupported.md) | Before triggering install re-entry (before W004 if both apply) |
| [W004 — Kafka Certs Job Loop](workarounds/W004-kafka-certs-job-loop.md) | After `spec.cache` confirmed set; within the window the certs job is `Succeeded` |

### Phase 2 — Post-Migration *(apply after a restore that causes DataSource deletion)*

| Workaround | When |
|------------|------|
| [W005 — Schema-Init Requeue Loop](workarounds/W005-schema-init-ttl-requeue-loop.md) | Within 5 minutes of schema-init job completing |
| [W006 — Stale PVC Reference](workarounds/W006-cast-runtime-stale-pvc.md) | After W005 is resolved and cast-runtime pod is still `Pending` |
