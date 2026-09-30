# values.yaml — Field Reference

Complete field-by-field documentation for `values.yaml` in the `model-deploy-vllm-cpu` Helm chart.

This document covers every key: its type, default value, whether it is required, and how the templates use it. For deployment workflows, environment-specific examples, `helm install` commands, and troubleshooting, see [`README.md`](README.md).

---

## `model`

Identity fields used as the base name for every Kubernetes resource this chart creates.

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `model.name` | `string` | `qwen2-5-1-5b-cpu` | **Yes** | Kubernetes resource name. Used as the `InferenceService` name and, when `servingRuntime.name` is empty, as the `ServingRuntime` name. Must be a valid DNS label (lowercase, hyphens, ≤ 63 chars). |
| `model.displayName` | `string` | `"Qwen2.5-1.5B (CPU)"` | No | Human-readable label surfaced in the Red Hat OpenShift AI dashboard. Has no effect on Kubernetes resource names. |
| `model.namespace` | `string` | `deploy-models-cpu` | **Yes** | Target namespace for all resources. Must match the namespace passed to `helm install -n`. |

---

## `project`

Controls whether the chart creates the target namespace.

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `project.create` | `bool` | `true` | No | `true` — renders `templates/namespace.yaml`, creating the namespace. `false` — skips namespace creation; the namespace must already exist. |
| `project.labels` | `map[string]string` | `{}` | No | Extra labels added to the `Namespace` metadata. Merged with any labels set by the chart itself (e.g. environment labels in environment values files). |
| `project.annotations` | `map[string]string` | `{}` | No | Extra annotations added to the `Namespace` metadata. |

---

## `servingRuntime`

Configures the `ServingRuntime` resource that tells KServe how to start the vLLM CPU server container.

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `servingRuntime.create` | `bool` | `true` | No | `true` — renders `templates/servingruntime.yaml`. `false` — skips `ServingRuntime` creation; the `InferenceService` will reference the runtime named in `servingRuntime.name`. |
| `servingRuntime.name` | `string` | `""` | No | Name of the `ServingRuntime`. When empty, defaults to `model.name` (via `_helpers.tpl`). Set an explicit value only when reusing a shared runtime already present in the namespace. |
| `servingRuntime.image` | `string` | `registry.redhat.io/rhaii-early-access/vllm-cpu-rhel9:latest` | **Yes** | vLLM CPU container image pulled into the `kserve-container`. **Pin to a digest in all non-development deployments** — the `:latest` tag is not reliably available on this registry. |
| `servingRuntime.extraArgs` | `list[string]` | `[]` | No | Additional CLI arguments appended to the `vllm.entrypoints.openai.api_server` command inside the container. See [known-bad args](#known-bad-extraargs) below. |
| `servingRuntime.extraEnv` | `list[EnvVar]` | `[]` | No | Additional environment variables injected into `kserve-container`. Each item follows the Kubernetes `EnvVar` schema (`name` + `value` or `valueFrom`). Primary use is setting `VLLM_CPU_KVCACHE_SPACE`. |

### `servingRuntime.extraEnv` — `VLLM_CPU_KVCACHE_SPACE`

| Sub-field | Type | Description |
|---|---|---|
| `name` | `string` | Environment variable name, e.g. `VLLM_CPU_KVCACHE_SPACE`. |
| `value` | `string` | Amount of RAM (in GiB) vLLM reserves for the KV cache. Compute as: `container_memory_limit − model_weights(bfloat16) − runtime_overhead(~2 GiB)`. |

Example:
```yaml
servingRuntime:
  extraEnv:
    - name: VLLM_CPU_KVCACHE_SPACE
      value: "6"
```

### Known-bad `extraArgs`

Do **not** add these unless you have tested the effect:

| Argument | Why it is dangerous |
|---|---|
| `--dtype=float32` | Doubles weight memory vs the default `bfloat16` (~5.6 GiB vs ~3 GiB for a 1.5B model). When combined with KV cache and AOT warmup, this exceeds a 12 GiB container limit and causes `OOMKill`. |
| `--max-model-len=<small value>` | Counter-intuitively **increases** KV cache slot count (e.g. 112,256 slots at 4096 ctx), consuming more RAM. Remove this flag rather than tuning it down. |

---

## `s3`

Connection details for the S3-compatible object store that holds the model weights. Two mutually exclusive credential modes exist; the mode is selected by `s3.externalSecret.enabled`.

### Core S3 fields (both modes)

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `s3.endpoint` | `string` | `https://s3.openshift-storage.svc:443` | **Yes** | Full URL of the S3-compatible endpoint (OpenShift Data Foundation internal address shown as default). |
| `s3.region` | `string` | `us-east-1` | **Yes** | S3 region. Override to `us-south` for the production cluster. |
| `s3.bucket` | `string` | `""` | **Yes** | Name of the bucket that contains the model files. |
| `s3.modelPath` | `string` | `""` | **Yes** | S3 key prefix pointing to the model directory (e.g. `qwen2-5-1-5b-instruct-hf/1.0.0`). Uses **hyphens**, not dots. The trailing path component is the model version. |
| `s3.verifySSL` | `string` | `"0"` | No | Set to `"1"` to enable TLS certificate verification on the S3 endpoint. `"0"` disables it (required for self-signed certs on internal ODF endpoints). |
| `s3.connectionSecretName` | `string` | `""` | No | Name of the `Secret` holding the S3 connection. Defaults to `<model.namespace>-connection` when empty (resolved in `_helpers.tpl`). |
| `s3.serviceAccountName` | `string` | `""` | No | Name of the `ServiceAccount` that KServe uses to access the S3 secret. Defaults to `<connectionSecretName>-sa` when empty (resolved in `_helpers.tpl`). |

### Manual credential mode fields (`s3.externalSecret.enabled: false`)

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `s3.accessKeyId` | `string` | `""` | **Yes** | S3 access key ID. **Supply at deploy time via `--set`**; never commit a real value to source control. Written into `templates/s3-connection-secret.yaml`. |
| `s3.secretAccessKey` | `string` | `""` | **Yes** | S3 secret access key. **Supply at deploy time via `--set`**; never commit a real value to source control. Written into `templates/s3-connection-secret.yaml`. |

### `s3.externalSecret` — ESO credential mode

When `s3.externalSecret.enabled: true`, the chart renders `templates/s3-externalsecret.yaml` and `templates/storage-config-externalsecret.yaml` instead of the manual Secret templates. The `s3.accessKeyId` and `s3.secretAccessKey` fields are **ignored** in this mode.

All five S3 credential fields (`access_key_id`, `secret_access_key`, `endpoint`, `region`, `bucket`) must be stored as keys in a single Vault KV v2 secret at the path configured by `s3.externalSecret.remoteRef.key`. The three prod models share the path `maas/model-registry/object-storage`.

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `s3.externalSecret.enabled` | `bool` | `false` | No | `true` activates ESO mode. Requires External Secrets Operator to be installed on the cluster with a `ClusterSecretStore` named `vault-backend`. |
| `s3.externalSecret.refreshInterval` | `string` | `1h` | No | How often ESO re-syncs the secret from Vault. Any Go duration string (`30m`, `6h`, `0` to disable auto-refresh). |
| `s3.externalSecret.secretStoreRef.name` | `string` | `vault-backend` | **Yes (ESO mode)** | Name of the `ClusterSecretStore` or `SecretStore` that connects ESO to Vault. The cluster-installed store is named `vault-backend`. |
| `s3.externalSecret.secretStoreRef.kind` | `string` | `ClusterSecretStore` | No | `ClusterSecretStore` (cluster-scoped, default) or `SecretStore` (namespace-scoped). |
| `s3.externalSecret.remoteRef.key` | `string` | `maas/model-deploy/cpu/s3` | **Yes (ESO mode)** | Vault KV v2 path (without the `secret/data/` prefix) where all five S3 fields are stored. All prod models override this to `maas/model-registry/object-storage`. |

#### Required Vault secret structure

The Vault path must contain **all five keys** — ESO's `dataFrom.extract` pulls every key at the path into the ESO template namespace. Missing keys result in empty `Secret` fields and storage-initialiser auth failures.

```bash
# Write (or update) the shared prod S3 credentials
vault kv put secret/maas/model-registry/object-storage \
  access_key_id="<key>" \
  secret_access_key="<secret>" \
  endpoint="https://s3.openshift-storage.svc:443" \
  region="us-south" \
  bucket="<bucket-name>"

# Verify all five keys are present
vault kv get secret/maas/model-registry/object-storage
```

#### ExternalSecret `dataFrom` field constraints (ESO v1)

The `dataFrom[].extract` block in the rendered `ExternalSecret` uses these fields with the only values ESO v1 accepts:

| Field | Value used | Valid enum values |
|---|---|---|
| `conversionStrategy` | `Default` | `Default`, `Unicode` |
| `decodingStrategy` | `None` | `Auto`, `Base64`, `Base64URL`, `None` |
| `metadataPolicy` | `None` | `None`, `Fetch` |
| `nullBytePolicy` | `Ignore` | `Ignore`, `Fail` |

> Do not set `conversionStrategy: None` — it is **not** a valid value and ESO will reject the `ExternalSecret` with a `SyncFailed` validation error.

---

## `externalAccess`

Controls whether the model is reachable from outside the cluster. When enabled, the chart creates an OpenShift `Route` (TLS reencrypt/Redirect), a `ServiceAccount` + token `Secret` for bearer-token authentication, and the RBAC bindings required by `kube-rbac-proxy` to validate those tokens.

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `externalAccess.enabled` | `bool` | `false` | No | `true` — renders the external-access resources listed below. `false` — model is only reachable in-cluster via the `InferenceService` internal URL. |
| `externalAccess.routeTimeoutSeconds` | `int` | `300` | No | Timeout (seconds) set on the `Route` and matched on the `InferenceService` predictor. Must be ≥ the expected worst-case inference latency to avoid 504 errors on long requests. |
| `externalAccess.tokenSAName` | `string` | `external-access-token` | No | Prefix for the token `Secret` name. The Secret is named `<tokenSAName>-<model.name>-sa`. |

### Resources created when `externalAccess.enabled: true`

| Resource | Kind | Name | Notes |
|---|---|---|---|
| Bearer-token SA | `ServiceAccount` | `<model.name>-sa` | Identity that owns the bearer token; has `opendatahub.io/dashboard: "true"` label |
| Bearer-token Secret | `Secret` (`kubernetes.io/service-account-token`) | `<externalAccess.tokenSAName>-<model.name>-sa` | Auto-populated by OpenShift; contains the JWT used in `Authorization: Bearer` headers |
| Auth-delegator binding | `ClusterRoleBinding` → `system:auth-delegator` | `<namespace>-<model.name>-sa-auth-delegator` | Cluster-scoped; allows `kube-rbac-proxy` to call the TokenReview API to validate the bearer token |
| InferenceService viewer | `Role` | `<model.name>-sa-inferenceservice-viewer` | Namespace-scoped; grants `get` on `inferenceservices/<model.name>` in the model namespace |
| InferenceService viewer binding | `RoleBinding` | `<model.name>-sa-inferenceservice-viewer` | Binds the Role to `<model.name>-sa`; satisfies the `kube-rbac-proxy` SubjectAccessReview (SAR) check |

> **Why both bindings?** RHOAI injects a `kube-rbac-proxy` sidecar into every `InferenceService` predictor pod. It performs two checks on every inbound request: (1) a **TokenReview** to validate the JWT — requires `system:auth-delegator` at cluster scope; (2) a **SubjectAccessReview** to confirm the identity has `get` on the specific `InferenceService` — satisfied by the namespace-scoped `Role` + `RoleBinding`. Without both, requests return `403 Forbidden`.

---

## `inference`

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `inference.replicas` | `int` | `1` | No | Number of `InferenceService` predictor replicas. Each replica runs one vLLM CPU container. Scaling beyond 1 multiplies CPU and memory consumption linearly. |

---

## `resources`

Kubernetes resource requests and limits for the vLLM CPU container (`kserve-container`). There is no GPU field — this chart is CPU-only.

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `resources.limits.cpu` | `string` | `"8"` | No | Maximum CPU cores the container may use. vLLM CPU uses all available cores for tensor parallelism; set to the node's allocatable core count for best throughput. |
| `resources.limits.memory` | `string` | `16Gi` | No | Maximum RAM. Must accommodate: model weights + `VLLM_CPU_KVCACHE_SPACE` + ~2 GiB runtime overhead. See sizing table below. |
| `resources.requests.cpu` | `string` | `"4"` | No | CPU cores reserved on the node at scheduling time. Kubernetes uses this for pod placement; does not cap actual usage. |
| `resources.requests.memory` | `string` | `8Gi` | No | Memory reserved at scheduling time. Setting this equal to `limits.memory` avoids the pod being OOM-killed before vLLM even starts. |

### Memory sizing guidance

| Model params | dtype | Weights | Recommended `limits.memory` |
|---|---|---|---|
| ≤ 1.5B | `bfloat16` (default) | ~3 GiB | `12Gi` |
| ≤ 1.5B | `float32` | ~6 GiB | `16Gi` |
| 3B | `bfloat16` | ~6 GiB | `16Gi` |
| 7B | `bfloat16` | ~14 GiB | `32Gi` |

---

## `scheduling`

Controls which nodes the predictor pod is placed on. CPU inference pods should **not** carry GPU tolerations.

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `scheduling.nodeSelector` | `map[string]string` | `{}` | No | Label selector to constrain the pod to specific nodes. Use `kubernetes.io/arch: amd64` to pin to x86 nodes when the cluster has mixed architectures. |
| `scheduling.tolerations` | `list[Toleration]` | `[]` | No | Kubernetes `Toleration` objects applied to the pod spec. Do **not** add `nvidia.com/gpu` — the vLLM CPU image has no CUDA runtime and the GPU taint is for GPU-only nodes. |
| `scheduling.affinity` | `object` | `{}` | No | Full Kubernetes `Affinity` object (`nodeAffinity`, `podAffinity`, `podAntiAffinity`). Applied verbatim to the pod spec. |

---

## `argocd`

Configures the ArgoCD application controller identity for RBAC bindings this chart creates. `templates/argocd-rbac.yaml` is **always rendered** (not ESO-only) and grants the ArgoCD controller access to `ServingRuntime` and `InferenceService` resources. The ESO rules are added to the same `ClusterRole` when `s3.externalSecret.enabled: true`.

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `argocd.namespace` | `string` | `openshift-gitops` | **Yes** | Namespace where the ArgoCD application controller `ServiceAccount` lives. Used as the subject namespace in the `RoleBinding` rendered by `templates/argocd-rbac.yaml`. |
| `argocd.serviceAccountName` | `string` | `openshift-gitops-argocd-application-controller` | **Yes** | Name of the ArgoCD application controller `ServiceAccount` bound to the `argocd-manager-vllm-cpu` `ClusterRole`. |

---

## `labels` / `annotations`

| Field | Type | Default | Required | Description |
|---|---|---|---|---|
| `labels` | `map[string]string` | `{}` | No | Extra labels applied to every resource created by this chart (merged with resource-specific labels). |
| `annotations` | `map[string]string` | `{}` | No | Extra annotations applied to every resource created by this chart. |

---

## Full field inventory

Quick-reference listing of every key, in the order they appear in `values.yaml`:

```
model.name
model.displayName
model.namespace

project.create
project.labels
project.annotations

servingRuntime.create
servingRuntime.name
servingRuntime.image
servingRuntime.extraArgs
servingRuntime.extraEnv

s3.endpoint
s3.region
s3.bucket
s3.modelPath
s3.accessKeyId
s3.secretAccessKey
s3.verifySSL
s3.connectionSecretName
s3.serviceAccountName
s3.externalSecret.enabled
s3.externalSecret.refreshInterval
s3.externalSecret.secretStoreRef.name
s3.externalSecret.secretStoreRef.kind
s3.externalSecret.remoteRef.key

externalAccess.enabled
externalAccess.routeTimeoutSeconds
externalAccess.tokenSAName

inference.replicas

resources.limits.cpu
resources.limits.memory
resources.requests.cpu
resources.requests.memory

scheduling.nodeSelector
scheduling.tolerations
scheduling.affinity

argocd.namespace
argocd.serviceAccountName

labels
annotations
```
