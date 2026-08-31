# model-deploy-vllm-cpu Helm Chart

Deploys a model on **CPU (x86)** using the **vLLM CPU ServingRuntime for KServe** on
Red Hat OpenShift AI. This chart follows the standard KServe path
(`ServingRuntime` + `InferenceService`) and is the correct choice for CPU-only
inference testing.

---

## Chart Layout

```
model-deploy-vllm-cpu/              ← this chart
├── Chart.yaml
├── values.yaml                     ← base defaults
├── templates/
│   ├── _helpers.tpl
│   ├── namespace.yaml
│   ├── servingruntime.yaml                     ← vLLM CPU ServingRuntime (conditional)
│   ├── inferenceservice.yaml                   ← KServe InferenceService (v1beta1)
│   ├── serviceaccount.yaml                     ← shared S3 storage SA
│   ├── external-access-sa.yaml                 ← bearer-token SA + RBAC (externalAccess.enabled)
│   ├── external-access-token.yaml              ← SA token Secret (externalAccess.enabled)
│   ├── argocd-rbac.yaml                        ← ArgoCD ClusterRole + RoleBinding (always)
│   ├── s3-connection-secret.yaml               ← manual credential mode
│   ├── s3-externalsecret.yaml                  ← ESO credential mode
│   ├── storage-config.yaml                     ← manual credential mode
│   └── storage-config-externalsecret.yaml      ← ESO credential mode
└── environments/
    ├── dev/
    │   ├── values-qwen2-5-1-5b-cpu.yaml
    │   ├── values-qwen2-5-coder-1-5b-cpu.yaml
    │   └── values-smollm2-1-7b-cpu.yaml
    ├── staging/
    │   ├── values-qwen2-5-1-5b-cpu.yaml
    │   ├── values-qwen2-5-coder-1-5b-cpu.yaml
    │   └── values-smollm2-1-7b-cpu.yaml
    └── prod/
        ├── values-qwen2-5-1-5b-cpu.yaml
        ├── values-qwen2-5-coder-1-5b-cpu.yaml
        └── values-smollm2-1-7b-cpu.yaml
```

For the ArgoCD `AppProject` and `Application` manifests that deploy this chart, see [`../../gitops/model-deploy-vllm-cpu/`](https://github.com/IBM/storage-fusion/tree/master/AI/quickstarts/model-as-a-service/deploy/gitops/model-deploy-vllm-cpu).

---

## Deployed Models

See [`../../gitops/model-deploy-vllm-cpu/README.md`](https://github.com/IBM/storage-fusion/tree/master/AI/quickstarts/model-as-a-service/deploy/gitops/model-deploy-vllm-cpu/README.md) for the full model table with ArgoCD Application names, S3 paths, and per-environment namespaces.

---

## What This Chart Creates

| Resource | Kind | API | Notes |
|---|---|---|---|
| Namespace | `Namespace` | `v1` | Optional — `project.create: false` to skip |
| vLLM CPU runtime | `ServingRuntime` | `serving.kserve.io/v1alpha1` | Conditional — `servingRuntime.create: false` to skip |
| Model serving CR | `InferenceService` | `serving.kserve.io/v1beta1` | Binds model to runtime; sync-wave 2 (after ExternalSecrets) |
| S3 credentials | `Secret` | `v1` | Manual mode (default) |
| S3 credentials | `ExternalSecret` | `external-secrets.io/v1` | ESO mode — sync-wave 1 |
| KServe storage config | `Secret` (storage-config) | `v1` | Manual mode |
| KServe storage config | `ExternalSecret` (storage-config) | `external-secrets.io/v1` | ESO mode — sync-wave 1 |
| Storage SA | `ServiceAccount` | `v1` | Shared — references connection secret; `helm.sh/resource-policy: keep` |
| ArgoCD RBAC | `ClusterRole` + `RoleBinding` | `rbac.authorization.k8s.io/v1` | Always created; covers KServe + ESO (when enabled); sync-wave 0 |
| Bearer-token SA | `ServiceAccount` | `v1` | `externalAccess.enabled: true` only — named `<model.name>-sa` |
| Bearer-token Secret | `Secret` (kubernetes.io/service-account-token) | `v1` | `externalAccess.enabled: true` only — auto-populated by OpenShift |
| Auth-delegator binding | `ClusterRoleBinding` → `system:auth-delegator` | `rbac.authorization.k8s.io/v1` | `externalAccess.enabled: true` — required for `kube-rbac-proxy` TokenReview |
| InferenceService viewer | `Role` + `RoleBinding` | `rbac.authorization.k8s.io/v1` | `externalAccess.enabled: true` — grants `get inferenceservices/<model>` to bearer-token SA for `kube-rbac-proxy` SAR check |

---

## Values Reference

### `model`

| Key | Default | Description |
|---|---|---|
| `model.name` | `qwen2-5-1-5b-cpu` | Kubernetes resource name — used as `InferenceService` name and default `ServingRuntime` name |
| `model.displayName` | `"Qwen2.5-1.5B (CPU)"` | Display name shown in RHOAI dashboard |
| `model.namespace` | `deploy-models-cpu` | Target namespace for all resources |

---

### `servingRuntime`

Each model deployment can either **create its own** `ServingRuntime` or **reuse an existing** one already present in the namespace.

| Key | Default | Description |
|---|---|---|
| `servingRuntime.create` | `true` | `true` = create a new `ServingRuntime`; `false` = skip creation and reference an existing one |
| `servingRuntime.name` | _(model.name)_ | Name of the `ServingRuntime`. Defaults to `model.name` when empty. Set explicitly to reference a shared runtime. |
| `servingRuntime.image` | `registry.redhat.io/rhaii-early-access/vllm-cpu-rhel9@sha256:…` | vLLM CPU container image — pin to a digest, never use `:latest` |
| `servingRuntime.extraArgs` | `[]` | Extra CLI args appended to `vllm.entrypoints.openai.api_server` |
| `servingRuntime.extraEnv` | `[]` | Extra env vars injected into the `kserve-container` |

#### ServingRuntime: per-model (default — recommended for shared namespaces)

```yaml
# Each model gets its own ServingRuntime named after it.
# Two models in deploy-models-cpu → two runtimes: qwen2-5-1-5b-cpu, qwen2-5-coder-1-5b-cpu
servingRuntime:
  create: true
  # name: ""   ← omit; defaults to model.name automatically
```

#### ServingRuntime: reuse existing

```yaml
# No ServingRuntime is created. The InferenceService points to an existing one.
servingRuntime:
  create: false
  name: vllm-cpu-runtime   # must already exist in the namespace
```

#### ⚠️ `extraArgs`

These two flags are **not set** in the base values and should remain absent unless you have a specific tested reason:

| Arg | Risk |
|---|---|
| `--dtype=float32` | Doubles weight memory vs `bfloat16` (~5.6 GiB vs ~3 GiB). Combined with KV cache allocation, pushes past the 12 GiB container limit → **OOMKill**. |
| `--max-model-len=4096` | Counter-intuitively **increases** KV cache slot count (112,256 tokens with 4096 ctx vs far fewer with larger ctx), consuming more RAM, not less. |

The working reference runtime (`test-models-cpu`) passes no extra args and uses `bfloat16` by default.

#### `VLLM_CPU_KVCACHE_SPACE`

Controls how much RAM (GiB) vLLM reserves for the KV cache. Formula:

```
VLLM_CPU_KVCACHE_SPACE = container_memory_limit - model_weights(bfloat16) - runtime_overhead
```

| Environment | Container limit | Weights (~bfloat16) | Overhead | Recommended value |
|---|---|---|---|---|
| prod | 12 GiB | ~3 GiB | ~2 GiB | `6` |
| dev | 16 GiB | ~3 GiB | ~2 GiB | `6` |
| staging | 24 GiB | ~3 GiB | ~2 GiB | `10` |

```yaml
servingRuntime:
  extraEnv:
    - name: VLLM_CPU_KVCACHE_SPACE
      value: "6"
```

---

### `s3`

Two credential modes — choose one:

#### Manual mode (default — `s3.externalSecret.enabled: false`)

Supply credentials at deploy time via `--set`. **Never commit real credentials to source control.**

```bash
helm install ... \
  --set s3.accessKeyId=<key> \
  --set s3.secretAccessKey=<secret>
```

| Key | Default | Description |
|---|---|---|
| `s3.endpoint` | `https://s3.openshift-storage.svc:443` | S3 endpoint URL |
| `s3.region` | `us-east-1` | S3 region (`us-south` for prod cluster) |
| `s3.bucket` | `""` | Bucket name (required) |
| `s3.modelPath` | `""` | Path prefix to model files in the bucket (required) |
| `s3.accessKeyId` | `""` | Access key — supply via `--set`, never commit |
| `s3.secretAccessKey` | `""` | Secret key — supply via `--set`, never commit |
| `s3.verifySSL` | `"0"` | `"1"` to enable SSL cert verification |
| `s3.connectionSecretName` | `<namespace>-connection` | Override the connection Secret name |
| `s3.serviceAccountName` | `<connectionSecretName>-sa` | Override the ServiceAccount name |

---

#### ESO mode (`s3.externalSecret.enabled: true`) — Production default

All five S3 fields (`access_key_id`, `secret_access_key`, `endpoint`, `region`, `bucket`) are pulled from **HashiCorp Vault** via External Secrets Operator. Credentials are never written to Git or Kubernetes Secrets directly — ESO syncs them on a configurable interval.

##### Prerequisites

1. **ESO installed** — `ClusterSecretStore/vault-backend` must exist and report `Ready`:
   ```bash
   oc get clustersecretstore vault-backend
   # STATUS: Ready
   ```

2. **Vault secret populated** — all five keys must be present at the configured path:
   ```bash
   vault kv put secret/maas/model-registry/object-storage \
     access_key_id="<key>" \
     secret_access_key="<secret>" \
     endpoint="https://s3.openshift-storage.svc:443" \
     region="us-south" \
     bucket="<bucket-name>"
   ```

   > **All three prod models share a single Vault path** (`maas/model-registry/object-storage`)
   > because they share the same S3 bucket and credentials. The per-model ESO key
   > (`s3.externalSecret.remoteRef.key`) in each environment values file must point
   > to this path.

3. **Vault policy** — the Kubernetes auth role bound to the `ClusterSecretStore` (`external-secrets` SA in `external-secrets` namespace) must have `read` capability on `secret/data/maas/model-registry/object-storage`.

##### Values configuration (ESO mode)

```yaml
s3:
  modelPath: "qwen2-5-1-5b-instruct-hf/1.0.0"   # still required — not in Vault
  verifySSL: "0"
  connectionSecretName: "deploy-models-cpu-connection"

  externalSecret:
    enabled: true
    refreshInterval: 1h
    secretStoreRef:
      name: vault-backend         # must match the ClusterSecretStore name
      kind: ClusterSecretStore
    remoteRef:
      key: maas/model-registry/object-storage   # Vault KV path (without "secret/data/" prefix)
```

##### What ESO creates

When ArgoCD syncs the Application, ESO reconciles two `ExternalSecret` CRs into real Kubernetes `Secret` objects:

| ExternalSecret name | Resulting Secret | Used by |
|---|---|---|
| `deploy-models-cpu-connection` | S3 connection credentials (`AWS_*` keys) | RHOAI dashboard, KServe storage-initialiser |
| `storage-config` | KServe storage-initialiser JSON (keyed by connection name) | KServe storage-initialiser init-container |

##### Sync-wave ordering

The `InferenceService` carries `argocd.argoproj.io/sync-wave: "2"` so ArgoCD always applies resources in this order:

```
wave 0 → ClusterRole + RoleBinding     (ArgoCD RBAC)
wave 1 → ExternalSecret CRs            (ESO reconciles → Secrets created)
wave 2 → InferenceService              (RHOAI webhook validates Secret exists ✓)
```

> Without this ordering, the RHOAI admission webhook (`connection-isvc.opendatahub.io`)
> rejects the `InferenceService` CREATE because the connection Secret does not yet exist,
> blocking the entire sync.

##### Verify ESO sync status

```bash
# Check ExternalSecret reconciliation status
oc get externalsecret -n deploy-models-cpu

# Detailed status for each CR
oc describe externalsecret deploy-models-cpu-connection -n deploy-models-cpu
oc describe externalsecret storage-config -n deploy-models-cpu

# Confirm the backing Secrets were created and have the expected keys
oc get secret deploy-models-cpu-connection -n deploy-models-cpu \
  -o jsonpath='{.data}' | python3 -m json.tool
```

##### Rotating credentials

Update the Vault secret — ESO picks up the change automatically at the next `refreshInterval`:

```bash
vault kv put secret/maas/model-registry/object-storage \
  access_key_id="<new-key>" \
  secret_access_key="<new-secret>" \
  endpoint="https://s3.openshift-storage.svc:443" \
  region="us-south" \
  bucket="<bucket-name>"
```

To force an immediate refresh without waiting for the interval:

```bash
# Annotate the ExternalSecrets to trigger an immediate re-sync
oc annotate externalsecret deploy-models-cpu-connection \
  force-sync=$(date +%s) --overwrite -n deploy-models-cpu
oc annotate externalsecret storage-config \
  force-sync=$(date +%s) --overwrite -n deploy-models-cpu
```

---

### `externalAccess`

When enabled, exposes the model outside the cluster via an OpenShift Route (TLS reencrypt/Redirect) and enforces bearer-token authentication via `kube-rbac-proxy` (injected by RHOAI alongside every `InferenceService`).

| Key | Default | Description |
|---|---|---|
| `externalAccess.enabled` | `false` | `true` to create a Route and enable auth |
| `externalAccess.routeTimeoutSeconds` | `300` | Route + predictor timeout (must match or exceed inference time) |
| `externalAccess.tokenSAName` | `external-access-token` | Prefix for the token Secret name |

```yaml
externalAccess:
  enabled: true
  routeTimeoutSeconds: 300
  tokenSAName: "external-access-token"
```

When `externalAccess.enabled: true` the chart creates **five** additional resources:

| Resource | Name pattern | Purpose |
|---|---|---|
| `ServiceAccount` | `<model.name>-sa` | Identity that owns the bearer token |
| `Secret` (SA token) | `external-access-token-<model.name>-sa` | Auto-populated bearer token |
| `ClusterRoleBinding` | `<namespace>-<model.name>-sa-auth-delegator` | Grants `system:auth-delegator` so `kube-rbac-proxy` can call the TokenReview API |
| `Role` | `<model.name>-sa-inferenceservice-viewer` | Allows `get` on `inferenceservices/<model.name>` |
| `RoleBinding` | `<model.name>-sa-inferenceservice-viewer` | Binds the Role to `<model.name>-sa` |

**Why both bindings?** `kube-rbac-proxy` performs two checks on every request:
1. **TokenReview** — validates the bearer token. Requires `system:auth-delegator` at cluster scope.
2. **SubjectAccessReview (SAR)** — checks the token identity has `get` on the specific `InferenceService`. Satisfied by the namespace-scoped `Role` + `RoleBinding`.

Retrieve the token after deployment:
```bash
TOKEN=$(oc get secret external-access-token-<model.name>-sa \
  -n <namespace> \
  -o jsonpath='{.data.token}' | base64 -d)
```

Test the endpoint:
```bash
ENDPOINT=$(oc get inferenceservice <model.name> -n <namespace> -o jsonpath='{.status.url}')

curl -sk "${ENDPOINT}/v1/models" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

---

### `resources`

CPU-only — no `nvidia.com/gpu` field. Size by model parameter count:

| Model size | dtype | Recommended limits |
|---|---|---|
| ≤ 1.5B | `bfloat16` | `cpu: 4, memory: 12Gi` |
| ≤ 1.5B | `float32` | `cpu: 8, memory: 16Gi` |
| 3B | `bfloat16` | `cpu: 8, memory: 16Gi` |
| 7B | `bfloat16` | `cpu: 16, memory: 32Gi` |

```yaml
resources:
  limits:
    cpu: "4"
    memory: 12Gi
  requests:
    cpu: "4"
    memory: 12Gi
```

---

### `scheduling`

CPU nodes should have **no GPU taint** — keep `tolerations: []`.

```yaml
scheduling:
  nodeSelector:
    kubernetes.io/arch: amd64   # optional: pin to x86 nodes explicitly
  tolerations: []               # do NOT add nvidia.com/gpu toleration
  affinity: {}
```

---

## Add a New CPU Model

1. Copy the closest prod values file and rename:
   ```bash
   cp environments/prod/values-qwen2-5-1-5b-cpu.yaml \
      environments/prod/values-<model-name>.yaml
   ```

2. Update these fields in the new file:
   - `model.name` — kebab-case Kubernetes name (e.g. `my-model-cpu`)
   - `model.displayName` — human-readable name for the RHOAI dashboard
   - `s3.modelPath` — exact S3 prefix (with hyphens, matching the actual bucket key)
   - `s3.externalSecret.remoteRef.key` — Vault path for this model's S3 credentials (or the shared path if credentials are shared)
   - `resources` — size for the model's parameter count and dtype

3. Copy and update the ArgoCD Application:
   ```bash
   cp ../../gitops/model-deploy-vllm-cpu/environments/prod/application-qwen2-5-1-5b-cpu.yaml \
      ../../gitops/model-deploy-vllm-cpu/environments/prod/application-<model-name>.yaml
   ```
   Update: `metadata.name`, `metadata.labels.model`, `helm.valueFiles`, `info`.
   The `ignoreDifferences` block for shared `ExternalSecret` resources is already present — **do not remove it**.

4. Repeat steps 1–3 for `dev/` and `staging/` environments.

> **S3 path naming:** The S3 prefix uses **hyphens** (`qwen2-5-1-5b-instruct-hf/1.0.0`),
> not dots. Always verify the actual bucket key with:
> ```bash
> kubectl run s3-ls --rm -i --restart=Never --image=amazon/aws-cli -n <namespace> \
>   --env="AWS_ACCESS_KEY_ID=<key>" --env="AWS_SECRET_ACCESS_KEY=<secret>" \
>   --env="AWS_DEFAULT_REGION=us-south" \
>   --command -- aws s3 ls s3://<bucket>/ \
>   --endpoint-url https://s3.openshift-storage.svc:443 --no-verify-ssl
> ```

---

## Render Locally

```bash
# ESO mode (production default) — verify templates render without credential values
helm template qwen2-5-1-5b-cpu . \
  -f values.yaml \
  -f environments/prod/values-qwen2-5-1-5b-cpu.yaml
```

```bash
# Manual mode — dry run with placeholder credentials
helm template qwen2-5-1-5b-cpu . \
  -f values.yaml \
  -f environments/prod/values-qwen2-5-1-5b-cpu.yaml \
  --set s3.externalSecret.enabled=false \
  --set s3.accessKeyId=TEST \
  --set s3.secretAccessKey=TEST \
  --set s3.bucket=my-bucket
```

```bash
# Reuse existing shared runtime
helm template qwen2-5-coder-1-5b-cpu . \
  -f values.yaml \
  -f environments/prod/values-qwen2-5-coder-1-5b-cpu.yaml \
  --set servingRuntime.create=false \
  --set servingRuntime.name=qwen2-5-1-5b-cpu
```

---

## Install with Helm (ESO mode)

```bash
# ESO mode — credentials come from Vault, no --set needed for credentials
helm install qwen2-5-1-5b-cpu . \
  -n deploy-models-cpu \
  --create-namespace \
  -f values.yaml \
  -f environments/prod/values-qwen2-5-1-5b-cpu.yaml
```

## Install with Helm (Manual mode)

```bash
# Manual mode — pass credentials at install time, never commit them
helm install qwen2-5-1-5b-cpu . \
  -n deploy-models-cpu \
  --create-namespace \
  -f values.yaml \
  -f environments/prod/values-qwen2-5-1-5b-cpu.yaml \
  --set s3.externalSecret.enabled=false \
  --set s3.accessKeyId=<key> \
  --set s3.secretAccessKey=<secret>
```

---

## Troubleshooting

### ExternalSecret `SyncFailed` — `Unsupported value: "None"` for `conversionStrategy`

ESO v1 only accepts `"Default"` or `"Unicode"` for `conversionStrategy`. The templates use `conversionStrategy: Default` explicitly. If you see this on a live object that pre-dates this fix, the live object still has stale fields from a previous chart version. ArgoCD will patch them out on the next sync when `ServerSideApply=true` is set — or patch manually:

```bash
oc patch externalsecret deploy-models-cpu-connection -n deploy-models-cpu \
  --type=merge -p '{"spec":{"dataFrom":[{"extract":{"key":"maas/model-registry/object-storage","conversionStrategy":"Default","decodingStrategy":"None","metadataPolicy":"None","nullBytePolicy":"Ignore"}}]}}'
```

### ExternalSecret `SyncFailed` — admission webhook denied `InferenceService`

```
admission webhook "connection-isvc.opendatahub.io" denied the request:
Secret 'deploy-models-cpu-connection' not found in namespace 'deploy-models-cpu'
```

The `InferenceService` was applied before the `ExternalSecret` CRs had been reconciled by ESO. The `InferenceService` template carries `argocd.argoproj.io/sync-wave: "2"` to prevent this. If you see this error on an older release, verify the annotation is present:

```bash
helm template qwen2-5-1-5b-cpu . \
  -f values.yaml \
  -f environments/prod/values-qwen2-5-1-5b-cpu.yaml \
  -s templates/inferenceservice.yaml | grep sync-wave
# Expected: argocd.argoproj.io/sync-wave: "2"
```

### Multiple Applications `OutOfSync` on shared ExternalSecrets

When three Applications share `deploy-models-cpu-connection` and `storage-config` ExternalSecrets, label drift causes every non-owning Application to show `OutOfSync`. This is suppressed by the `ignoreDifferences` entries for `group: external-secrets.io / kind: ExternalSecret` in each Application manifest. If you see this, verify the entries are present:

```bash
oc get application <app-name> -n openshift-gitops \
  -o jsonpath='{.spec.ignoreDifferences}' | python3 -m json.tool | grep -A3 'ExternalSecret'
```

### ExternalSecret reconciled but Secret missing expected keys

Vault must contain **all five keys** under the configured path:

```bash
vault kv get secret/maas/model-registry/object-storage
# Must show: access_key_id, secret_access_key, endpoint, region, bucket
```

If any key is missing, ESO will create the Secret but leave that field empty, causing the storage-initialiser to fail authentication.

### Pod stuck in `Init` — model download in progress

```bash
kubectl logs -n deploy-models-cpu \
  $(kubectl get pod -n deploy-models-cpu -l serving.kserve.io/inferenceservice=qwen2-5-1-5b-cpu \
    -o jsonpath='{.items[0].metadata.name}') \
  -c storage-initializer --follow
```

### `Storage initialization failed: No model found`

The S3 path in `s3.modelPath` does not exist in the bucket. Verify the exact prefix:

```bash
kubectl run s3-ls --rm -i --restart=Never --image=amazon/aws-cli -n deploy-models-cpu \
  --env="AWS_ACCESS_KEY_ID=<key>" --env="AWS_SECRET_ACCESS_KEY=<secret>" \
  --env="AWS_DEFAULT_REGION=us-south" \
  --command -- aws s3 ls s3://<bucket>/ \
  --endpoint-url https://s3.openshift-storage.svc:443 --no-verify-ssl
```

> The bucket keys use **hyphens** (`qwen2-5-1-5b-instruct-hf/1.0.0`), not dots.

### Pod in `ImagePullBackOff`

The registry `registry.redhat.io/rhaii-early-access/vllm-cpu-rhel9` does not support the
`:latest` tag. Always pin to a digest:

```yaml
servingRuntime:
  image: "registry.redhat.io/rhaii-early-access/vllm-cpu-rhel9@sha256:139e070c2e4e2bc0254aa852b436c35ec2659e8424e228cc4c77a3bc2ddf50b6"
```

### Pod `OOMKilled` (exit code 137)

The container exceeded its memory limit during vLLM AOT compilation warmup. Common causes:

1. **`--dtype=float32` in `extraArgs`** — doubles weight memory. Remove it; vLLM defaults to `bfloat16`.
2. **`--max-model-len` set too small** — paradoxically increases KV cache slot count. Remove it.
3. **`VLLM_CPU_KVCACHE_SPACE` too large** — reduce to `container_limit - weights - 2 GiB overhead`.

### Pod stuck in `Pending` — insufficient CPU/memory

```bash
kubectl describe pod -n deploy-models-cpu \
  -l serving.kserve.io/inferenceservice=qwen2-5-1-5b-cpu
```

Increase `resources.requests.cpu` / `resources.requests.memory` or schedule on a larger node.

### `ServingRuntime not found` on InferenceService

```bash
kubectl get servingruntime -n deploy-models-cpu
```

With `servingRuntime.create: true` (default), the runtime is named after the model (`model.name`).
With `servingRuntime.create: false`, ensure the runtime named in `servingRuntime.name` exists in the namespace.

### Get the inference endpoint URL

```bash
kubectl get inferenceservice qwen2-5-1-5b-cpu -n deploy-models-cpu \
  -o jsonpath='{.status.url}'
```

Test inference (with external access token):
```bash
TOKEN=$(oc get secret external-access-token-qwen2-5-1-5b-cpu-sa \
  -n deploy-models-cpu \
  -o jsonpath='{.data.token}' | base64 -d)

ENDPOINT=$(oc get inferenceservice qwen2-5-1-5b-cpu \
  -n deploy-models-cpu -o jsonpath='{.status.url}')

curl -sk "${ENDPOINT}/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2-5-1-5b-cpu","messages":[{"role":"user","content":"Hello!"}],"max_tokens":50}'
```

---

## Related Documents

- [`maas-cpu-vs-gpu-capabilities.md`](https://github.com/IBM/storage-fusion/tree/master/AI/quickstarts/model-as-a-service/infoDocs/maas-cpu-vs-gpu-capabilities.md) — Full CPU vs GPU capability matrix
- [`maas-model-deploy`](https://github.com/IBM/storage-fusion/tree/master/AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/README.md) — GPU / LLMInferenceService chart (MaaS-publishable)
- [KServe InferenceService API](https://kserve.github.io/website/latest/reference/api/)
- [KServe ServingRuntime API](https://kserve.github.io/website/latest/modelserving/servingruntimes/)
