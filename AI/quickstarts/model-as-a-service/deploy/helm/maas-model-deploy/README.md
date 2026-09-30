# maas-model-deploy Helm Chart

Deploys a single LLM model to Red Hat OpenShift AI using a [`LLMInferenceService`](templates/llminferenceservice.yaml), an S3 data-connection Secret, a KServe [`storage-config`](templates/storage-config.yaml) Secret, and a [`ServiceAccount`](templates/serviceaccount.yaml).

Multiple models can be deployed into the **same namespace** by running this chart once per model with a separate set of values. The Namespace, S3 connection Secret, `storage-config` Secret, and ServiceAccount are shared across models in the same namespace; each model gets its own `LLMInferenceService`.

---

## Chart Location

```text
AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/
├── Chart.yaml
├── README.md
├── VAULT-SECRET-SETUP.md                    # ESO / Vault setup walkthrough
├── values.yaml                              # Base defaults (CPU/memory only, no GPU)
├── environments/
│   ├── CHANGELOG.md
│   ├── dev/values.yaml                      # Development overrides
│   ├── staging/values.yaml                  # Staging overrides
│   └── prod/
│       ├── values-tiny-llama.yaml           # Production overrides — tiny-llama model
│       └── values-gpt-oss-20b.yaml          # Production overrides — gpt-oss-20b model
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml
    ├── serviceaccount.yaml
    ├── s3-connection-secret.yaml            # Manual mode — rendered when ESO disabled
    ├── storage-config.yaml                  # Manual mode — rendered when ESO disabled
    ├── s3-externalsecret.yaml               # ESO mode — rendered when ESO enabled
    ├── storage-config-externalsecret.yaml   # ESO mode — rendered when ESO enabled
    ├── argocd-externalsecret-rbac.yaml      # ESO mode — rendered when ESO enabled
    ├── llminferenceservice.yaml
    └── maasmodelref.yaml
```

---

## What This Chart Creates

| Resource | Name (default) | Shared across models? |
|---|---|---|
| `Namespace` | `<model.namespace>` | ✅ Yes — created once, `helm.sh/resource-policy: keep` |
| `Secret` — S3 connection | `<model.namespace>-connection` | ✅ Yes — one per namespace |
| `Secret` — KServe storage | `storage-config` | ✅ Yes — one per namespace |
| `ServiceAccount` | `<model.namespace>-connection-sa` | ✅ Yes — one per namespace |
| `LLMInferenceService` | `<model.name>` | ❌ No — one per model |
| `MaaSModelRef` | `<model.name>` | ❌ No — one per model (optional, see [`maasModelRef`](#maasmodelref)) |

All shared resources carry `helm.sh/resource-policy: keep` so that a second model's sync does not attempt to recreate or overwrite them.

In ESO mode the chart additionally creates:

| Resource | Name | Purpose |
|---|---|---|
| `ExternalSecret` — S3 connection | `<model.namespace>-connection` | ESO writes the connection Secret from Vault |
| `ExternalSecret` — KServe storage | `storage-config` | ESO writes the KServe JSON Secret from Vault |
| `ClusterRole` | `argocd-externalsecret-manager-model-deploy` | ArgoCD RBAC for ExternalSecret objects |
| `RoleBinding` | `argocd-externalsecret-manager-model-deploy` | Scoped to `model.namespace` |

---

## Values Reference

### [`model`](values.yaml)

```yaml
model:
  name: tiny-llama-test
  displayName: "Tiny LLaMA Test"
  namespace: deploy-models
```

| Key | Default | Description |
|-----|---------|-------------|
| `model.name` | `tiny-llama-test` | Kubernetes resource name of the `LLMInferenceService` — must be unique per namespace |
| `model.displayName` | `"Tiny LLaMA Test"` | User-facing display name shown in the OpenShift AI dashboard |
| `model.namespace` | `deploy-models` | Target namespace for all deployed resources |

---

### [`project`](values.yaml)

```yaml
project:
  create: true
  labels: {}
  annotations: {}
```

| Key | Default | Description |
|-----|---------|-------------|
| `project.create` | `true` | When `true`, creates the target namespace |
| `project.labels` | `{}` | Additional labels applied to the namespace |
| `project.annotations` | `{}` | Additional annotations applied to the namespace |

---

### [`s3`](values.yaml)

Two credential modes are supported. Choose one and configure accordingly.

#### Manual mode (default)

All five S3 fields are supplied directly in `values.yaml` or via `--set` flags.
Never commit real credentials to source control.

```yaml
# environments/prod/values-gpt-oss-20b.yaml
s3:
  endpoint: "https://s3.openshift-storage.svc:443"
  region: "us-east-1"
  bucket: "model-registry-artifacts-p-ccc9b6a9-897a-4971-9161-9c0d25448836"
  modelPath: "gpt-oss-20b-hf/1.0.0"
  accessKeyId: ""       # supply via --set at deploy time
  secretAccessKey: ""   # supply via --set at deploy time
  verifySSL: "0"
```

```bash
helm upgrade --install ... \
  --set s3.accessKeyId=<key> \
  --set s3.secretAccessKey=<secret>
```

#### ESO mode — Vault manages the credentials

Set `s3.externalSecret.enabled: true`. Helm creates two `ExternalSecret` CRs;
ESO reads **all five S3 fields** from a single Vault KV path and writes both
Secrets (`<namespace>-connection` and `storage-config`) into the model namespace.

The fields `s3.endpoint`, `s3.region`, `s3.bucket`, `s3.accessKeyId`, and
`s3.secretAccessKey` are **ignored** in ESO mode — they all come from Vault.
Only `s3.modelPath` (model URI) and `s3.verifySSL` (non-sensitive) remain in values.

```yaml
# environments/prod/values-gpt-oss-20b.yaml
s3:
  modelPath: "gpt-oss-20b-hf/1.0.0"   # still required — constructs s3://<bucket>/<modelPath>
  verifySSL: "0"                        # still required — not stored in Vault

  externalSecret:
    enabled: true
    refreshInterval: 1h
    secretStoreRef:
      name: vault-backend               # must match your ClusterSecretStore name
      kind: ClusterSecretStore
    remoteRef:
      key: maas/model-deploy/gpt-oss-20b/s3   # Vault path — all five fields live here
```

Pre-populate Vault **before** the first ArgoCD sync:

```bash
vault kv put secret/maas/model-deploy/gpt-oss-20b/s3 \
  access_key_id="<key>" \
  secret_access_key="<secret>" \
  endpoint="https://s3.openshift-storage.svc:443" \
  region="us-east-1" \
  bucket="<bucket-name>"
```

> **Full walkthrough:** See [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md).

#### Full `s3.externalSecret` schema

| Key | Default | Description |
|-----|---------|-------------|
| `s3.externalSecret.enabled` | `false` | `true` = ESO creates both Secrets from Vault. `false` = credentials come from `s3.*` values. |
| `s3.externalSecret.refreshInterval` | `1h` | How often ESO re-reads all five fields from Vault. |
| `s3.externalSecret.secretStoreRef.name` | `vault-backend` | Name of the `ClusterSecretStore` or `SecretStore`. |
| `s3.externalSecret.secretStoreRef.kind` | `ClusterSecretStore` | `ClusterSecretStore` (cluster-wide) or `SecretStore` (namespaced). |
| `s3.externalSecret.remoteRef.key` | `maas/model-deploy/tiny-llama-test/s3` | Vault KV path. Override per model in the environment values file. |

---

### [`inference`](values.yaml)

```yaml
inference:
  replicas: 1
```

| Key | Default | Description |
|-----|---------|-------------|
| `inference.replicas` | `1` | Desired number of model serving replicas. Set to `0` to pause serving without deleting the model. |

---

### [`resources`](values.yaml)

```yaml
resources:
  limits:
    cpu: "2"
    memory: 4Gi
  requests:
    cpu: "2"
    memory: 4Gi
```

GPU keys (`nvidia.com/gpu`) are intentionally absent from the base. See [Change the GPU resource](#change-the-gpu-resource) for the reason and how to add them.

---

### [`scheduling`](values.yaml)

```yaml
scheduling:
  nodeSelector: {}
  tolerations:
    - effect: NoSchedule
      key: nvidia.com/gpu
      operator: Exists
  affinity: {}
```

Optional scheduling controls for GPU node placement.

---

### [`gateway`](values.yaml)

```yaml
gateway:
  name: maas-default-gateway
  namespace: openshift-ingress
```

Name and namespace of the shared Gateway created by `maas-platform`. The `LLMInferenceService` router is wired to this gateway so inference requests are routed correctly.

---

### [`maasModelRef`](values.yaml)

```yaml
maasModelRef:
  enabled: false
```

When `true`, creates a `MaaSModelRef` CR that registers this model with the MaaS controller. The controller then attaches a subscription-aware `AuthPolicy` and a `TokenRateLimitPolicy` (per-subscription token quota via Kuadrant). Set to `true` to activate "Publish as MaaS" governance via GitOps.

---

### [`argocd`](values.yaml)

```yaml
argocd:
  namespace: openshift-gitops
  serviceAccountName: openshift-gitops-argocd-application-controller
```

Used only when `s3.externalSecret.enabled: true`. The `argocd-externalsecret-rbac.yaml` template uses these values to bind the ArgoCD application-controller ServiceAccount to the `ClusterRole` it needs to manage `ExternalSecret` CRs.

| Key | Default | Description |
|-----|---------|-------------|
| `argocd.namespace` | `openshift-gitops` | Namespace where the ArgoCD application-controller SA lives. |
| `argocd.serviceAccountName` | `openshift-gitops-argocd-application-controller` | Name of the ArgoCD application-controller ServiceAccount. |

---

### [`labels`](values.yaml) and [`annotations`](values.yaml)

```yaml
labels: {}
annotations: {}
```

Additional labels and annotations applied to all chart resources.

---

## External Secrets Operator (ESO) Integration

The chart supports ESO for managing the two S3 secrets that must not be committed to Git.

### At a glance

| Secret | Namespace | Consumers | ESO flag |
|--------|-----------|-----------|----------|
| `<model.namespace>-connection` | `model.namespace` | `LLMInferenceService` + `ServiceAccount` — KServe storage-initializer authenticates to S3 | `s3.externalSecret.enabled` |
| `storage-config` | `model.namespace` | KServe storage-initializer init-container — JSON blob with all S3 fields | `s3.externalSecret.enabled` |

Both secrets are controlled by the **same single flag** and sourced from the **same single Vault path** — enabling ESO activates management of both simultaneously.

### Prerequisites

1. External Secrets Operator installed (via `external-secrets-operator` Helm chart or OLM).
2. A `ClusterSecretStore` named `vault-backend` (or the name set in `s3.externalSecret.secretStoreRef.name`) exists and is `Ready`.
3. Vault path populated **before** the first ArgoCD sync — see [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md).

### Templates rendered when ESO is enabled

| Template | Renders when |
|----------|-------------|
| `s3-externalsecret.yaml` | `s3.externalSecret.enabled: true` |
| `storage-config-externalsecret.yaml` | `s3.externalSecret.enabled: true` |
| `argocd-externalsecret-rbac.yaml` | `s3.externalSecret.enabled: true` |
| `s3-connection-secret.yaml` | `s3.externalSecret.enabled: false` (Manual mode) |
| `storage-config.yaml` | `s3.externalSecret.enabled: false` (Manual mode) |

### Sync-wave order

```
Wave 0  ClusterRole + RoleBinding      ArgoCD RBAC — must exist before ESO CRs
Wave 1  ExternalSecret CRs             ESO resolves both Secrets from Vault
Wave 2  ServiceAccount                 binds the connection Secret
Wave 2  LLMInferenceService            KServe init-container reads storage-config
```

### What ESO pulls from Vault and where it goes

| Vault field | Connection Secret key | `storage-config` JSON field | KServe annotation |
|---|---|---|---|
| `access_key_id` | `AWS_ACCESS_KEY_ID` | `access_key_id` | — |
| `secret_access_key` | `AWS_SECRET_ACCESS_KEY` | `secret_access_key` | — |
| `endpoint` | `AWS_S3_ENDPOINT` | `endpoint_url` | `serving.kserve.io/s3-endpoint` |
| `region` | `AWS_DEFAULT_REGION` | `region` | `serving.kserve.io/s3-region` |
| `bucket` | `AWS_S3_BUCKET` | `bucket` | — |

---

## Updating Values

Values are layered — the base [`values.yaml`](values.yaml) provides defaults every model inherits. The environment file (`environments/<env>/values-<model>.yaml`) overrides only what is model- or environment-specific. **Only set a key in the environment file if it differs from the base.**

### Change the model being deployed

Update `model.name`, `model.displayName`, and `s3.modelPath` in the environment values file:

```yaml
model:
  name: my-new-model
  displayName: "My New Model"
  namespace: deploy-models      # shared namespace — leave as-is

s3:
  modelPath: "my-new-model/1.0.0"
```

### Change the S3 bucket or endpoint

Override only the keys that differ. If all models share the same bucket, update the base [`values.yaml`](values.yaml). If only one model uses a different bucket, override it in that model's environment file:

```yaml
s3:
  endpoint: "https://s3.amazonaws.com"
  bucket: "my-other-bucket"
  region: "us-east-1"
```

> In ESO mode, `endpoint`, `bucket`, and `region` come from Vault — update the Vault path instead of values.yaml.

### Change the S3 credentials

**Manual mode:** Do not commit credentials in plain text. Pass them at deploy time:

```bash
helm upgrade --install ... \
  --set s3.accessKeyId=<key> \
  --set s3.secretAccessKey=<secret>
```

**ESO mode:** Update the Vault path and force an ESO refresh — no Git commit needed:

```bash
vault kv patch secret/maas/model-deploy/<model-name>/s3 \
  access_key_id="<new-key>" \
  secret_access_key="<new-secret>"

oc annotate externalsecret deploy-models-connection \
  -n deploy-models force-sync=$(date +%s) --overwrite
oc annotate externalsecret storage-config \
  -n deploy-models force-sync=$(date +%s) --overwrite
```

### Change the GPU resource

Edit `resources` in the model's environment values file. **Do not add GPU keys to the base `values.yaml`** — Helm merges resource maps shallowly, so a GPU key in the base would combine with the env file key causing the pod to request duplicate GPU resources and fail scheduling.

```yaml
resources:
  limits:
    cpu: "2"
    memory: 4Gi
    nvidia.com/gpu: "1"
  requests:
    cpu: "2"
    memory: 4Gi
    nvidia.com/gpu: "1"
```

To check which GPUs are available:

```bash
oc get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
```

### Scale replicas up or down

```yaml
inference:
  replicas: 1   # set to 0 to pause serving without deleting the model
```

### Change CPU or memory

Override both `limits` and `requests` together to avoid a partial merge:

```yaml
resources:
  limits:
    cpu: "4"
    memory: 8Gi
    nvidia.com/gpu: "1"   # always re-include the GPU key when overriding resources
  requests:
    cpu: "4"
    memory: 8Gi
    nvidia.com/gpu: "1"
```

### Add a new model or remove a model

See [`environments/CHANGELOG.md`](environments/CHANGELOG.md#add-a-new-model-to-production) for the full add/remove procedure including the matching ArgoCD Application steps.

---

## Example: Render Locally

### Manual mode — tiny-llama (prod)

```bash
helm template fusion-maas-model-deploy-prod-tiny-llama \
  AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy \
  --namespace deploy-models \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/values.yaml \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/prod/values-tiny-llama.yaml \
  --set s3.accessKeyId=<key> \
  --set s3.secretAccessKey=<secret>
```

### Manual mode — gpt-oss-20b (prod)

```bash
helm template fusion-maas-model-deploy-prod-gpt-oss-20b \
  AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy \
  --namespace deploy-models \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/values.yaml \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/prod/values-gpt-oss-20b.yaml \
  --set s3.accessKeyId=<key> \
  --set s3.secretAccessKey=<secret>
```

### ESO mode — verify templates render correctly

```bash
# Confirm the two ExternalSecrets and RBAC resources appear (no plain Secret)
helm template fusion-maas-model-deploy-prod-gpt-oss-20b \
  AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy \
  --namespace deploy-models \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/values.yaml \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/prod/values-gpt-oss-20b.yaml \
  --set s3.externalSecret.enabled=true \
  --set s3.externalSecret.remoteRef.key=maas/model-deploy/gpt-oss-20b/s3 \
  --show-only templates/s3-externalsecret.yaml \
  --show-only templates/storage-config-externalsecret.yaml \
  --show-only templates/argocd-externalsecret-rbac.yaml
```

---

## Example: Install with Helm

```bash
# Deploy tiny-llama
helm upgrade --install fusion-maas-model-deploy-prod-tiny-llama \
  AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy \
  --namespace deploy-models --create-namespace \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/values.yaml \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/prod/values-tiny-llama.yaml

# Deploy gpt-oss-20b into the same namespace
helm upgrade --install fusion-maas-model-deploy-prod-gpt-oss-20b \
  AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy \
  --namespace deploy-models --create-namespace \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/values.yaml \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/prod/values-gpt-oss-20b.yaml
```

---

## Troubleshooting

### Check what values Helm resolved

```bash
helm template test \
  AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy \
  -f values.yaml \
  -f environments/prod/values-gpt-oss-20b.yaml \
  --debug 2>&1 | head -60
```

### Check deployed resources

```bash
oc get llminferenceservice,secret,serviceaccount -n deploy-models
```

### Pod stuck in `Init` — model download in progress

The `storage-initializer` downloads all model weights before the main container starts. For large models this is expected. Check progress:

```bash
oc exec -n deploy-models <pod-name> -c storage-initializer -- du -sh /mnt/models/
oc exec -n deploy-models <pod-name> -c storage-initializer -- ls -lh /mnt/models/
```

A temp filename (e.g. `model.safetensors.27Fef63c`) means the download is still running — this is normal.

### Pod stuck in `Init:Error` — S3 authentication failed

Check that both Secrets exist and contain the expected keys:

```bash
# Manual mode
oc get secret deploy-models-connection -n deploy-models \
  -o jsonpath='{.data}' | python3 -c \
  "import sys,json; d=json.load(sys.stdin); [print(k) for k in sorted(d)]"

# Inspect the storage-config JSON
oc get secret storage-config -n deploy-models \
  -o jsonpath='{.data.deploy-models-connection}' | base64 -d | python3 -m json.tool
```

If using ESO mode, also check the ExternalSecret status — see [ESO secret status](#eso-secret-status).

### Pod stuck in `Pending` — insufficient GPU

```bash
oc describe pod -n deploy-models <pod-name> | grep -A5 "Events:"
```

If you see `Insufficient nvidia.com/gpu`, check available GPUs and adjust the GPU key in the model's env values file — see [Change the GPU resource](#change-the-gpu-resource).

### `s3.accessKeyId is required` error at helm render time

This error appears in Manual mode when `s3.accessKeyId` is empty and ESO is not enabled. Either pass credentials via `--set` or enable ESO mode (`s3.externalSecret.enabled: true`).

### ESO secret status

```bash
# Check both ExternalSecrets — both should show Ready=True
oc get externalsecret -n deploy-models

# Inspect conditions if status is not Ready
oc describe externalsecret deploy-models-connection -n deploy-models
oc describe externalsecret storage-config           -n deploy-models
```

Common causes: ClusterSecretStore not ready, Vault path missing, wrong field names in Vault.
See [VAULT-SECRET-SETUP.md — Troubleshooting](./VAULT-SECRET-SETUP.md#troubleshooting) for full diagnosis steps.

### Force immediate ESO refresh without waiting for the interval

```bash
oc annotate externalsecret deploy-models-connection \
  -n deploy-models force-sync=$(date +%s) --overwrite
oc annotate externalsecret storage-config \
  -n deploy-models force-sync=$(date +%s) --overwrite
```

### ArgoCD sync fails — `forbidden` on ExternalSecret resource

Confirm the RBAC resources were created:

```bash
oc get clusterrole argocd-externalsecret-manager-model-deploy
oc get rolebinding argocd-externalsecret-manager-model-deploy -n deploy-models
```

If missing, verify `s3.externalSecret.enabled: true` is set and the template renders:

```bash
helm template test \
  AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy \
  -f values.yaml \
  -f environments/prod/values-gpt-oss-20b.yaml \
  --show-only templates/argocd-externalsecret-rbac.yaml
```

---

## Related Documents

- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md) — step-by-step Vault and ESO setup guide for this chart
- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-model-registry` (Git credentials + Hugging Face token)
- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-platform` (Postgres + DB config)
- [`docs/deploying-external-secrets-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — ESO operator installation
- [`docs/deploying-vault-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — Vault operator installation
- [`environments/CHANGELOG.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/CHANGELOG.md) — add/remove model procedures and version history
