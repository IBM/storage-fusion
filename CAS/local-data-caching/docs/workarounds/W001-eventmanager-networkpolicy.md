# W001 — CAS Operator Reconcile Stalls: Missing EventManager NetworkPolicy

**Recurrence:** Non-Recurrent — apply once before CAS installation; persists across installs
and upgrades unless `isf-serviceability-operator` reconciles it away.

---

## Symptom

The CAS operator logs repeat the following pattern approximately every 60 seconds throughout
the entire install and any subsequent reconcile:

```
Event Manager service url: https://<clusterIP>:10666/api/v1/eventmanager/alerts
Error POSTing info request (...): Post "https://<clusterIP>:10666/api/v1/eventmanager/alerts":
  context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

Each timeout adds ~60 s of dead time to every reconcile cycle, visibly slowing install and
upgrade progress.

## Root Cause

The `eventmanager-network-policy` in `ibm-spectrum-fusion-ns` has no ingress rule permitting
traffic from the `ibm-cas` namespace to port `10666`. Every outbound POST from the CAS
operator is silently dropped and the HTTP client blocks until the OS TCP timeout expires.

## When to Apply

**Before CAS installation begins.** Every reconcile cycle stalls without this.

Re-apply if the symptom returns after an `isf-serviceability-operator` reconcile overwrites
the policy.

## Steps

Save the following manifest and apply it:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-cas-operator-to-eventmanager
  namespace: ibm-spectrum-fusion-ns
  labels:
    app.kubernetes.io/managed-by: cas-operator
spec:
  podSelector:
    matchLabels:
      app: isfemdep
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ibm-cas
      podSelector:
        matchLabels:
          app.kubernetes.io/component: operator
          app.kubernetes.io/name: cas.isf.ibm.com
    ports:
    - port: 10666
      protocol: TCP
```

```bash
oc apply -f allow-cas-operator-to-eventmanager.yaml
```

## Verify

After applying, operator logs should no longer show `context deadline exceeded` for Event
Manager POST calls.
