# W003 — Upgrade Stalls: Kafka CR Patched to Unsupported Version

**Recurrence:** Recurrent — must be re-applied each time the CAS operator patches the Kafka
CR to an unsupported version (i.e., on every install re-entry or upgrade that triggers
`UpdateKafkaVersion`).

---

## Symptom

After enabling the cache filesystem or triggering any upgrade, the CAS operator logs repeat
indefinitely:

```
Kafka not yet ready.
```

Inspecting the Kafka CR shows:

```bash
oc get kafka kafka -n ibm-cas -o jsonpath='{.status.conditions}'
```

```json
[{
  "message": "Unsupported Kafka.spec.kafka.version: 3.9.0. Supported versions are: [4.0.0, 4.1.0]",
  "reason": "UnsupportedKafkaVersionException",
  "status": "True",
  "type": "NotReady"
}]
```

## Root Cause

The CAS operator hardcodes Kafka version `3.9.0` when patching the Kafka CR during upgrades
and install re-entry. With AMQ Streams 3.1.0-14, only versions `4.0.0` and `4.1.0` are
supported. The Kafka CR is immediately set to `NotReady`, and `IsHealthyKafkaCluster` never
returns `true`.

## When to Apply

**Before triggering install re-entry** (i.e., before applying the CasInstall status patch
that re-enters the cache filesystem install path). Strimzi needs approximately 30 seconds to
reconcile the Kafka CR to `Ready` after this patch.

If the operator has already entered the loop, apply the patch and wait for the next
reconcile cycle to proceed.

## Steps

```bash
oc patch kafka kafka -n ibm-cas --type=merge \
  -p '{"spec":{"kafka":{"version":"4.0.0"}}}'
```

## Verify

Within ~30 seconds, the Kafka CR should show `type=Ready, status=True`:

```bash
oc get kafka kafka -n ibm-cas \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
# Expected: True
```

The operator log should stop repeating `"Kafka not yet ready."` after the next reconcile
cycle.
