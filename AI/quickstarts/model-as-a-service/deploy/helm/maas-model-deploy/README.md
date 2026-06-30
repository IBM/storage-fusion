# maas-model-deploy Helm Chart

Deploys a single LLM model to Red Hat OpenShift AI using a [`LLMInferenceService`](templates/llminferenceservice.yaml), an S3 data-connection [`Secret`](templates/s3-connection-secret.yaml), a [`storage-config`](templates/storage-config.yaml) secret, and a [`ServiceAccount`](templates/serviceaccount.yaml).

Multiple models can be deployed into the **same namespace** by running this chart once per model with a separate set of values. The Namespace, S3 connection Secret, `storage-config` Secret, and ServiceAccount are shared across models; each model gets its own `LLMInferenceService`.

---

## Chart Location

```text
AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/
├── Chart.yaml
├── README.md
├── values.yaml                              # Base defaults (cpu/memory only, no GPU)
├── environments/
│   ├── dev/values.yaml                      # Development overrides
│   ├── staging/values.yaml                  # Staging overrides
│   └── prod/
│       ├── values-tiny-llama.yaml           # Production overrides — tiny-llama model
│       └── values-gpt-oss-20b.yaml          # Production overrides — gpt-oss-20b model
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml
    ├── serviceaccount.yaml
    ├── s3-connection-secret.yaml
    ├── storage-config.yaml
    └── llminferenceservice.yaml
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

All shared resources carry `helm.sh/resource-policy: keep` so that a second model's sync does not attempt to recreate or overwrite them.

---

## Values Reference

### [`model`](values.yaml)

```yaml
model:
  name: tiny-llama-test       # Kubernetes resource name — must be unique per namespace
  displayName: "Tiny LLaMA Test"
  namespace: deploy-models
```

- `name`: Kubernetes name of the `LLMInferenceService` — **must be unique per namespace**
- `displayName`: user-facing display name shown in OpenShift AI
- `namespace`: target namespace for all deployed resources

### [`project`](values.yaml)

```yaml
project:
  create: true
  labels: {}
  annotations: {}
```

- `create`: when `true`, creates the target namespace
- `labels`: additional namespace labels
- `annotations`: additional namespace annotations

### [`s3`](values.yaml)

```yaml
s3:
  endpoint: "https://s3.openshift-storage.svc:443"
  region: "us-south"
  bucket: "model-registry-artifacts-p-ccc9b6a9-897a-4971-9161-9c0d25448836"
  modelPath: "tiny-llama-test/1.0.0"
  accessKeyId: ""
  secretAccessKey: ""
  verifySSL: "0"
  connectionSecretName: ""   # defaults to <model.namespace>-connection
  serviceAccountName: ""     # defaults to <connectionSecretName>-sa
```

- `endpoint`: S3-compatible endpoint URL
- `region`: region passed to the S3 connection
- `bucket`: bucket containing the model artifacts
- `modelPath`: prefix within the bucket — `<model-folder>/<version>`
- `accessKeyId` / `secretAccessKey`: required — supply via `--set` or sealed-secrets, never commit plain-text
- `verifySSL`: `"0"` for internal ODF/NooBaa with self-signed certs, `"1"` for public S3
- `connectionSecretName`: override the auto-generated connection secret name (default: `<model.namespace>-connection`)
- `serviceAccountName`: override the auto-generated ServiceAccount name (default: `<connectionSecretName>-sa`)

### [`inference`](values.yaml)

```yaml
inference:
  replicas: 1
```

- `replicas`: desired number of model serving replicas. Set to `0` to pause serving.

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

GPU keys (`nvidia.com/gpu`) are not in the base — see [Updating Values › Change the GPU resource](#change-the-gpu-resource) for why.

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

### [`labels`](values.yaml) and [`annotations`](values.yaml)

```yaml
labels: {}
annotations: {}
```

Additional labels and annotations applied to all chart resources.

---

## Updating Values

Values are layered — the base [`values.yaml`](values.yaml) provides defaults that every model inherits. The environment file (`environments/<env>/values-<model>.yaml`) overrides only what is model- or environment-specific. **Only set a key in the environment file if it differs from the base.**

### Change the model being deployed

Update `model.name`, `model.displayName`, and `s3.modelPath` in the environment values file:

```yaml
model:
  name: my-new-model            # Kubernetes resource name — unique per namespace
  displayName: "My New Model"   # Shown in the OpenShift AI dashboard
  namespace: deploy-models      # Shared namespace — leave as-is

s3:
  modelPath: "my-new-model/1.0.0"   # <folder>/<version> inside the bucket
```

### Change the S3 bucket or endpoint

Override only the keys that differ. If all models share the same bucket, update the base [`values.yaml`](values.yaml). If only one model uses a different bucket, override it in that model's environment file:

```yaml
s3:
  endpoint: "https://s3.amazonaws.com"      # different endpoint for this model
  bucket: "my-other-bucket"
  region: "us-east-1"
```

### Change the S3 credentials

Do **not** commit credentials in plain text. Set them at sync time via `--set` or store them in a sealed-secret. To update the credentials used for a model, update the environment file:

```yaml
s3:
  accessKeyId: ""      # leave blank — supply via --set or sealed-secret
  secretAccessKey: ""
```

Then pass credentials at deploy time:
```bash
helm upgrade --install ... --set s3.accessKeyId=<key> --set s3.secretAccessKey=<secret>
```

### Change the GPU resource

Edit `resources` in the model's environment values file. **Do not add GPU keys to the base `values.yaml`** — Helm merges resource maps shallowly, so a GPU key in the base would be combined with the one in the env file, causing both to be requested and the pod to fail scheduling.

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

To check which GPUs are available on the cluster:
```bash
oc get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
```

### Scale replicas up or down

```yaml
inference:
  replicas: 1   # set to 0 to pause serving without deleting the model
```

### Change CPU or memory

Override in the environment file. Both `limits` and `requests` must be set together to avoid a partial merge:

```yaml
resources:
  limits:
    cpu: "4"
    memory: 8Gi
    nvidia.com/gpu: "1"   # always re-include the GPU key
  requests:
    cpu: "4"
    memory: 8Gi
    nvidia.com/gpu: "1"
```

### Add a new model or remove a model

See [`environments/CHANGELOG.md`](environments/CHANGELOG.md#how-to-maintain-values-files) for the full add/remove procedure including the matching ArgoCD Application steps.

---

## Example: Render Locally

### tiny-llama (prod)

```bash
helm template fusion-maas-model-deploy-prod-tiny-llama \
  AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy \
  --namespace deploy-models \
  -f AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/values.yaml \
  -f AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/environments/prod/values-tiny-llama.yaml \
  --set s3.accessKeyId=<key> \
  --set s3.secretAccessKey=<secret>
```

### gpt-oss-20b (prod)

```bash
helm template fusion-maas-model-deploy-prod-gpt-oss-20b \
  AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy \
  --namespace deploy-models \
  -f AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/values.yaml \
  -f AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/environments/prod/values-gpt-oss-20b.yaml \
  --set s3.accessKeyId=<key> \
  --set s3.secretAccessKey=<secret>
```

---

## Example: Install with Helm

```bash
# Deploy tiny-llama
helm upgrade --install fusion-maas-model-deploy-prod-tiny-llama \
  AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy \
  --namespace deploy-models --create-namespace \
  -f AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/values.yaml \
  -f AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/environments/prod/values-tiny-llama.yaml

# Deploy gpt-oss-20b (into the same namespace)
helm upgrade --install fusion-maas-model-deploy-prod-gpt-oss-20b \
  AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy \
  --namespace deploy-models --create-namespace \
  -f AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/values.yaml \
  -f AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy/environments/prod/values-gpt-oss-20b.yaml
```

---

## Troubleshooting

### Pod stuck in `Init`

The `storage-initializer` downloads all model weights before the main container starts. For 20B+ models this takes time. Check progress:

```bash
oc exec -n deploy-models <pod-name> -c storage-initializer -- du -sh /mnt/models/
oc exec -n deploy-models <pod-name> -c storage-initializer -- ls -lh /mnt/models/
```

A temp filename (e.g. `model.safetensors.27Fef63c`) means the download is still running — this is normal.

### Pod stuck in `Pending` — insufficient GPU

```bash
oc describe pod -n deploy-models <pod-name> | grep -A5 "Events:"
```

If you see `Insufficient nvidia.com/gpu`, check available GPUs and adjust the GPU key in the model's env values file — see [Change the GPU resource](#change-the-gpu-resource).

### `s3.accessKeyId is required`

Render locally to verify the merged values contain the credentials:

```bash
helm template test AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy \
  -f values.yaml \
  -f environments/prod/values-tiny-llama.yaml
```

### Check deployed resources

```bash
oc get llminferenceservice,secret,sa -n deploy-models
```
