# MaaS Deployment Verification

Run these checks after completing all steps in `POST_SYNC_MANUAL_STEPS.md` to
confirm that Models-as-a-Service is fully deployed and healthy.

**Ref:** `maas-1.md` §1.5

---

## Check 1 — MaaS CRDs are installed

```bash
oc get crd | grep maas.opendatahub.io
```

Expected output — all five CRDs must be present:

```
maasauthpolicies.maas.opendatahub.io
maasmodelrefs.maas.opendatahub.io
maassubscriptions.maas.opendatahub.io
externalmodels.maas.opendatahub.io
tenants.maas.opendatahub.io
```

> CRDs are installed by the RHOAI operator when `kserve.modelsAsService.managementState`
> is set to `Managed` in the DataScienceCluster. If any are missing, verify the
> DSC is reconciled and `ModelsAsServiceReady` condition is `True`:
> ```bash
> oc get datasciencecluster default-dsc \
>   -o jsonpath='{.status.conditions[?(@.type=="ModelsAsServiceReady")].status}'
> # Expected: True
> ```

---

## Check 2 — User Workload Monitoring is enabled

```bash
oc get configmap cluster-monitoring-config \
  -n openshift-monitoring \
  -o jsonpath='{.data.config\.yaml}' | grep enableUserWorkload
```

Expected output:

```
enableUserWorkload: true
```

Also confirm UWM pods are running:

```bash
oc get pods -n openshift-user-workload-monitoring
```

Expected: `prometheus-operator`, `prometheus-user-workload-0/1`, and
`thanos-ruler-user-workload-0/1` all `Running`.

> If not enabled, MaaS will show a `Degraded` status. Follow
> `POST_SYNC_MANUAL_STEPS.md` Step 1 to enable it.

---

## Check 3 — Tenant CR exists

```bash
oc get tenants.maas.opendatahub.io -n models-as-a-service
```

Expected output — at least one Tenant must be listed:

```
NAME             AGE
default-tenant   5m
```

---

## Check 4 — Tenant CR is Ready

```bash
oc get tenants.maas.opendatahub.io default-tenant \
  -n models-as-a-service \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

Expected output:

```
True
```

Check the full status including reason:

```bash
oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service
```

Expected output:

```
NAME             READY   REASON
default-tenant   True    AllComponentsReady
```

> If the output shows `False` or `Degraded`, retrieve the condition message for
> details:
> ```bash
> oc get tenants.maas.opendatahub.io default-tenant \
>   -n models-as-a-service \
>   -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'
> ```

---

## Check 5 — ExternalModel CRD (optional)

Run this only if you plan to use external models (AWS Bedrock, Azure OpenAI,
Google Vertex AI):

```bash
oc get crd externalmodels.maas.opendatahub.io
```

Expected output:

```
NAME                                  CREATED AT
externalmodels.maas.opendatahub.io   <timestamp>
```

---

## Summary checklist

| Check | Command | Expected |
|---|---|---|
| MaaS CRDs | `oc get crd \| grep maas.opendatahub.io` | 5 CRDs listed |
| User Workload Monitoring | `oc get cm cluster-monitoring-config -n openshift-monitoring ...` | `enableUserWorkload: true` |
| UWM pods | `oc get pods -n openshift-user-workload-monitoring` | All `Running` |
| Tenant exists | `oc get tenants.maas.opendatahub.io -n models-as-a-service` | `default-tenant` listed |
| Tenant Ready | `oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service` | `READY=True` |

---

## Troubleshooting — Tenant shows `False` or `Degraded`

Work through these checks in order:

1. **User Workload Monitoring not enabled** — follow `POST_SYNC_MANUAL_STEPS.md` Step 1.
2. **`maas-db-config` Secret missing** — verify it exists:
   ```bash
   oc get secret maas-db-config -n redhat-ods-applications
   ```
3. **Kuadrant CR not ready** — verify:
   ```bash
   oc get kuadrant -n kuadrant-system \
     -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'
   # Expected: True
   ```
4. **RHCL Subscription in wrong namespace** — the DSC controller checks for the
   `rhcl-operator` Subscription in `openshift-operators`:
   ```bash
   oc get subscription -n openshift-operators | grep rhcl
   ```
5. **Authorino TLS not configured** — follow `POST_SYNC_MANUAL_STEPS.md` Step 2.
6. **Review Tenant condition message** for specific error details:
   ```bash
   oc get tenants.maas.opendatahub.io default-tenant \
     -n models-as-a-service \
     -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'
   ```

---

## Related documents

- [`POST_SYNC_MANUAL_STEPS.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/POST_SYNC_MANUAL_STEPS.md) — manual steps to run after each ArgoCD sync
