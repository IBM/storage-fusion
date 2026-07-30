# GitOps Post-Sync Manual Steps

After each ArgoCD Application sync, a small number of steps cannot be expressed
as declarative Kubernetes manifests and must be run manually. This document lists
every such step in the order they must be performed.

> **When do I need to run these?**
> On **first install** — run all steps in order after `02-maas-platform` syncs
> successfully. On **upgrades** — only re-run the step whose resource changed.

---

## Step 1 — Enable User Workload Monitoring

**When:** After `02-maas-platform` ArgoCD Application syncs (first install only).
**Why:** MaaS metrics collection requires `enableUserWorkload: true` in the
`cluster-monitoring-config` ConfigMap in `openshift-monitoring`. Without this,
MaaS shows a **Degraded** status (ref: `maas-1.md` §1.2).

> **Why this is manual:** `cluster-monitoring-config` is a singleton ConfigMap
> owned by OpenShift cluster monitoring infrastructure. It may already exist with
> other monitoring settings (e.g. retention periods, storage class, external
> labels). Helm cannot safely own or overwrite it — doing so would clobber any
> pre-existing configuration. Instead, verify the flag is set and act only if
> missing.

> **`patch` vs `apply`:** The `config.yaml` field is a **YAML-in-a-string** value.
> `--type=merge` patch replaces the entire string, not individual keys within it,
> so it has the same clobber risk as `apply`. The safe options are:
> - **ConfigMap does not exist yet** → use `oc apply` to create it.
> - **ConfigMap exists, `config.yaml` is empty or only has `enableUserWorkload`**
>   → use `oc patch` (shown below).
> - **ConfigMap exists with other settings already in `config.yaml`** → use
>   `oc edit` interactively and add `enableUserWorkload: true` as a new line,
>   preserving all existing content.

### Step 1a — Check current state

```bash
oc get configmap cluster-monitoring-config \
  -n openshift-monitoring -o yaml 2>&1
```

This shows the full ConfigMap. Read the output before proceeding — it determines
which path below to follow.

### Step 1b — Act based on what you see

**Case 1 — ConfigMap does not exist:**

```bash
oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF
```

**Case 2 — ConfigMap exists and `config.yaml` is empty or only contains
`enableUserWorkload`:**

```bash
oc patch configmap cluster-monitoring-config \
  -n openshift-monitoring \
  --type=merge \
  --patch '{"data":{"config.yaml":"enableUserWorkload: true\n"}}'
```

**Case 3 — ConfigMap exists with other settings in `config.yaml`
(e.g. retention, storageClass):**

```bash
# Edit interactively — add 'enableUserWorkload: true' as a new line
# under the existing content, preserving everything else.
oc -n openshift-monitoring edit configmap cluster-monitoring-config
```

Add `enableUserWorkload: true` under `data.config.yaml`, for example:

```yaml
data:
  config.yaml: |
    enableUserWorkload: true
    prometheusK8s:
      retention: 15d          # existing setting — do not remove
```

### Verify

```bash
oc get configmap cluster-monitoring-config \
  -n openshift-monitoring \
  -o jsonpath='{.data.config\.yaml}' | grep enableUserWorkload
```

Expected output:

```
enableUserWorkload: true
```

Confirm UWM pods are running:

```bash
oc get pods -n openshift-user-workload-monitoring
```

Expected: `prometheus-operator`, `prometheus-user-workload-0/1`, and
`thanos-ruler-user-workload-0/1` all `Running`.

---

## Step 2 — Configure Authorino TLS

**When:** After `02-maas-platform` syncs AND the Gateway is `Programmed`.
**Why:** MaaS authentication requires TLS between the Gateway (Envoy) and
Authorino. These patches target operator-managed resources that ArgoCD cannot
own — they must be applied imperatively.
**Ref:** `maas-1.md` §1.4

> **Authorino namespace:** Both RHOAI (RHCL) and ODH deploy Authorino in
> `kuadrant-system`. Confirm with:
> ```bash
> oc get pods -n kuadrant-system -l app=authorino
> ```

Set the namespace variable before running any command below:

```bash
AUTHORINO_NAMESPACE=kuadrant-system
```

### Action 1 — Annotate the Authorino Service

Triggers the OpenShift service-ca-operator to generate a signed TLS certificate
and store it in the `authorino-server-cert` Secret:

```bash
oc annotate service authorino-authorino-authorization \
  -n ${AUTHORINO_NAMESPACE} \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
  --overwrite
```

> **Wait ~30 seconds** after this step before proceeding — the service-ca-operator
> needs time to generate and populate the `authorino-server-cert` Secret.

Confirm the Secret was generated before continuing:

```bash
oc get secret authorino-server-cert -n ${AUTHORINO_NAMESPACE}
# Expected: TYPE=kubernetes.io/tls
```

### Action 2 — Patch the Authorino CR

Enable the TLS listener and reference the generated certificate:

```bash
oc patch authorino authorino \
  -n ${AUTHORINO_NAMESPACE} \
  --type=merge --patch '{
    "spec": {
      "listener": {
        "tls": {
          "enabled": true,
          "certSecretRef": {"name": "authorino-server-cert"}
        }
      }
    }
  }'
```

### Action 3 — Set CA bundle env vars on the Authorino Deployment

Allows Authorino to trust the cluster service CA when making outbound calls:

```bash
oc -n ${AUTHORINO_NAMESPACE} set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt
```

### Action 4 — Annotate the Gateway

Signals the MaaS controller to create the EnvoyFilter that configures the Envoy
proxy to use TLS when communicating with Authorino. The Gateway annotation is
already set by the Helm chart (`security.opendatahub.io/authorino-tls-bootstrap: "true"`).
Run this only if the Gateway was created outside the chart or the annotation is missing:

```bash
oc annotate gateway maas-default-gateway \
  -n openshift-ingress \
  security.opendatahub.io/authorino-tls-bootstrap="true" \
  --overwrite
```

### Restart deployments to pick up the new configuration

```bash
oc rollout restart deployment/maas-api -n redhat-ods-applications
oc rollout restart deployment/authorino -n ${AUTHORINO_NAMESPACE}
```

### Verify

```bash
# 1. Authorino service has the serving-cert annotation
oc get service authorino-authorino-authorization \
  -n ${AUTHORINO_NAMESPACE} \
  -o jsonpath='{.metadata.annotations.service\.beta\.openshift\.io/serving-cert-secret-name}'
# Expected: authorino-server-cert

# 2. authorino-server-cert Secret exists
oc get secret authorino-server-cert -n ${AUTHORINO_NAMESPACE}
# Expected: TYPE=kubernetes.io/tls

# 3. Authorino CR has TLS enabled
oc get authorino authorino \
  -n ${AUTHORINO_NAMESPACE} \
  -o jsonpath='{.spec.listener.tls.enabled}'
# Expected: true

# 4. Authorino Deployment has CA bundle env vars
oc get deployment/authorino \
  -n ${AUTHORINO_NAMESPACE} \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SSL_CERT_FILE")].value}'
# Expected: /etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt

# 5. Gateway has the TLS bootstrap annotation
oc get gateway maas-default-gateway \
  -n openshift-ingress \
  -o jsonpath='{.metadata.annotations.security\.opendatahub\.io/authorino-tls-bootstrap}'
# Expected: true
```

---

## Step 3 — Patch OdhDashboardConfig for MaaS Dashboard Features

**When:** After `02-maas-platform` syncs successfully and the `DataScienceCluster`
is healthy enough that `odh-dashboard-config` exists.
**Why:** `OdhDashboardConfig` is created by the RHOAI dashboard controller after
DSC reconciliation. The live resource already contains operator-managed `spec`
fields, so use a merge patch to add only the MaaS dashboard flags without
changing existing configuration.
**Ref:** [`maas-1.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/infoDocs/maas-config-governance-guide.md) §1.2 dashboard configuration

### Step 3a — Check current state

```bash
oc get odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications -o yaml
```

Confirm the resource exists before patching. If it is not found, wait for the
Dashboard component to finish reconciling and run the command again.

### Step 3b — Patch only the required MaaS fields

```bash
oc patch odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications \
  --type=merge \
  --patch '{
    "spec": {
      "dashboardConfig": {
        "modelAsService": true,
        "genAiStudio": true,
        "maasAuthPolicies": true
      }
    }
  }'
```

This merge patch adds only the MaaS dashboard flags and preserves existing live
fields such as `disableTracking`, `hardwareProfileOrder`,
`notebookController`, `templateDisablement`, and `templateOrder`.

### Optional — Enable the MaaS observability dashboard

Only do this after the observability prerequisites in
[`maas-1.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/infoDocs/maas-config-governance-guide.md) are complete, including OpenShift AI
observability configuration, Cluster Observability Operator setup, Kuadrant
observability, and Tenant telemetry.

```bash
oc patch odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications \
  --type=merge \
  --patch '{
    "spec": {
      "dashboardConfig": {
        "observabilityDashboard": true
      }
    }
  }'
```

### Verify

```bash
oc get odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.modelAsService}{"\n"}{.spec.dashboardConfig.genAiStudio}{"\n"}{.spec.dashboardConfig.maasAuthPolicies}{"\n"}'
```

Expected output:

```
true
true
true
```

---

## Step 4 — Replace Placeholder Credentials Before Go-Live

**When:** Before promoting from testing to production.  
**Why:** The prod environment values file ships with placeholder passwords that
must never remain in a live cluster.

### Items to replace

| File | Field | Action |
|---|---|---|
| `environments/prod/values.yaml` | `maasDatabase.internal.password` | Set a strong password or switch to `external: true` with a managed DB |
| `environments/prod/values.yaml` | `maasDatabase.externalDatabase.password` | Set real credential (when `external: true`) |
| `environments/prod/values.yaml` | `maasDatabase.external` | Flip to `true` for go-live; use RDS / CloudSQL / Crunchy |

### Recommended credential injection methods (in order of preference)

1. **External Secrets Operator** — syncs secrets from Vault / AWS Secrets Manager / Azure Key Vault into the cluster. Set `maasDatabase.enabled: false` and let ESO create `maas-db-config` directly.
2. **Sealed Secrets** — encrypt the Secret with `kubeseal` and commit the `SealedSecret` to Git.
3. **ArgoCD Vault Plugin** — template credentials at sync time from Vault.

---

## Step 5 — Switch to External Database for Production Go-Live

**When:** Before go-live (currently `external: false` in prod for testing).  
**Why:** The in-cluster PostgreSQL uses a single pod with a PVC — no HA, no
automatic backups, no connection pooling. Not suitable for production.

```yaml
# environments/prod/values.yaml — change these two blocks:
maasDatabase:
  external: true
  connectionUrl: ""            # Option A: full URL, OR
  externalDatabase:            # Option B: individual fields
    host: "your-rds-endpoint.region.rds.amazonaws.com"
    port: 5432
    database: maasdb
    username: maasadmin
    password: ""               # inject via ESO / Sealed Secrets
    sslMode: require
```

After updating values, sync the `02-maas-platform` ArgoCD Application. The
`postgresql.yaml` Deployment and Service will be removed (since `external: true`
skips that template) and the `maas-db-config` Secret will be updated to point
at the new host.

```bash
# Restart maas-api to pick up the new connection string
oc rollout restart deployment/maas-api -n redhat-ods-applications
```

---

## Quick Reference — Complete Post-Sync Checklist

Run after every **first install** or after syncing `02-maas-platform`:

```bash
# ── Step 1: User Workload Monitoring ────────────────────────────────────────
oc get configmap cluster-monitoring-config -n openshift-monitoring \
  -o jsonpath='{.data.config\.yaml}' | grep enableUserWorkload
# If not "true", follow Step 1 above.

# ── Step 2: Authorino TLS ────────────────────────────────────────────────────
AUTHORINO_NAMESPACE=kuadrant-system

oc annotate service authorino-authorino-authorization \
  -n ${AUTHORINO_NAMESPACE} \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
  --overwrite
# Wait ~30s, then:
oc patch authorino authorino -n ${AUTHORINO_NAMESPACE} --type=merge --patch \
  '{"spec":{"listener":{"tls":{"enabled":true,"certSecretRef":{"name":"authorino-server-cert"}}}}}'
oc -n ${AUTHORINO_NAMESPACE} set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt
oc annotate gateway maas-default-gateway -n openshift-ingress \
  security.opendatahub.io/authorino-tls-bootstrap="true" --overwrite

oc rollout restart deployment/maas-api -n redhat-ods-applications
oc rollout restart deployment/authorino -n ${AUTHORINO_NAMESPACE}

# ── Step 3: Patch OdhDashboardConfig ─────────────────────────────────────────
oc patch odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications \
  --type=merge \
  --patch '{"spec":{"dashboardConfig":{"modelAsService":true,"genAiStudio":true,"maasAuthPolicies":true}}}'

# ── Step 4: Verify full deployment ───────────────────────────────────────────
# See VERIFICATION.md for the complete checklist.
oc get tenants.maas.opendatahub.io default-tenant \
  -n models-as-a-service \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Expected: True
```

---

## Related Documents

- [`VERIFICATION.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VERIFICATION.md) — full deployment verification checklist (maas-1.md §1.5)
- [`DEPLOYMENT_ORDER.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/01-setup/DEPLOYMENT_ORDER.md) — ArgoCD Application wave order and sync strategy
- [`MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/01-setup/MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md) — all `maas-platform` Helm values explained
- [`models-as-a-service/docs/content/install/maas-setup.md`](../../../../models-as-a-service/docs/content/install/maas-setup.md) — upstream install guide
