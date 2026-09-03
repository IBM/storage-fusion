# Helm Values Reference — `values.yaml`

This document describes every field in
[`values.yaml`](./values.yaml) for the **llmops-chat-app** Helm chart.
It explains what each field does, which Kubernetes resource it drives, and how to
change it for your environment.

> **Rule of thumb:** never edit the templates directly.
> All environment-specific customisation belongs in `values.yaml`
> (or an environment override file passed with `helm install -f my-env.yaml`).

---

## Table of Contents

1. [namespace](#1-namespace)
2. [image](#2-image)
3. [cas — CAS / Content-Aware Storage](#3-cas)
4. [modelGateway — Model Gateway](#4-modelgateway)
5. [app — Application tuning](#5-app)
6. [replicaCount](#6-replicacount)
7. [service](#7-service)
8. [route — OpenShift Route](#8-route)
9. [resources — CPU / Memory](#9-resources)
10. [secrets — API key management](#10-secrets)
    - [Option A: ExternalSecret (Vault)](#option-a-externalsecret--vault--production)
    - [Option B: Hardcoded Secret (dev/CI)](#option-b-hardcoded-secret-devci)
11. [cpu — CPU multi-model KServe](#11-cpu)
    - [cpu.models — per-task model config](#cpumodels)
    - [cpu.tokens — bearer token management](#cputokens)
        - [Option A: ExternalSecret (Vault)](#option-a-externalsecret--vault--production-1)
        - [Option B: Hardcoded tokens (dev/CI)](#option-b-hardcoded-tokens-devci)
12. [reloader — Stakater Reloader](#12-reloader)
13. [syncWaves — ArgoCD sync ordering](#13-syncwaves)
14. [Common Scenarios](#14-common-scenarios)

---

## 1. `namespace`

```yaml
namespace: llmops-platform
```

The Kubernetes namespace where **all** chart resources are created:
Deployment, Service, ConfigMap, Secrets, RBAC, and the OpenShift Route.

**How to change:**  
Set this to the namespace that already exists (or will be created) on your cluster.

```yaml
namespace: my-team-namespace
```

> ⚠ The KServe RBAC resources (`rbac-kserve.yaml`) are created in
> `cpu.modelsNamespace`, not here. See [§11](#11-cpu).

---

## 2. `image`

```yaml
image:
  repository: docker-na-public.artifactory.swg-devops.com/.../chat-app
  tag: v1.0.3
  pullPolicy: Always
```

Controls which container image the Deployment runs.

| Field | Description | How to change |
|---|---|---|
| `repository` | Full registry path (without tag). | Point to your own registry after running `scripts/build_and_push_chat_app.sh`. |
| `tag` | Image tag / version. | Bump this after every new image push. ArgoCD will detect the change and roll out. |
| `pullPolicy` | Kubernetes image pull policy. | `Always` ensures the latest tag is pulled. Use `IfNotPresent` to avoid unnecessary pulls in airgapped environments. |

**Example — use your own registry:**
```yaml
image:
  repository: quay.io/my-org/chat-app
  tag: v2.0.0
  pullPolicy: Always
```

---

## 3. `cas`

```yaml
cas:
  endpoint: "https://ibm-cas-ibm-cas.apps.f73l056.fusion.tadn.ibm.com/"
  useMcp: "false"
```

Connection settings for **CAS (Content-Aware Storage)** — the vector store used for
RAG document retrieval. These values are rendered into the `llmops-config` ConfigMap
and injected into the pod as `CAS_ENDPOINT` and `CAS_USE_MCP` env vars.

| Field | Description | How to change |
|---|---|---|
| `endpoint` | Base URL of your CAS instance. Must include the trailing `/`. | Replace with your cluster's CAS Route URL. |
| `useMcp` | `"true"` = use MCP protocol for CAS search. `"false"` = use REST API. | Set to `"true"` only if your CAS instance has MCP enabled and you want to use it. |

> The CAS **API key** is not set here. It is injected from the Secret created by
> the `secrets` block — see [§10](#10-secrets).

---

## 4. `modelGateway`

```yaml
modelGateway:
  endpoint: "https://model-gateway-model-gateway.apps.f73l056.fusion.tadn.ibm.com"
  modelName: "qwen2-5-72b-instruct"
  verifySSL: "false"
```

Connection settings for the **Model Gateway** — the OpenAI-compatible LLM endpoint
that serves large (GPU-backed) models. Drives `MODEL_GATEWAY_ENDPOINT`, `MODEL_NAME`,
and `MODEL_GATEWAY_VERIFY_SSL` env vars.

| Field | Description | How to change |
|---|---|---|
| `endpoint` | Base URL of the Model Gateway. No trailing slash. | Replace with your cluster's Model Gateway Route URL. |
| `modelName` | The default LLM model ID. This model is marked `default: true` in the unified `/api/models` response and is pre-selected in the UI dropdown. It is also the CAS+ fallback for Auto Detect. | Change to any model ID returned by `GET /v1/models` on your gateway. |
| `verifySSL` | `"false"` = skip TLS certificate verification (required for self-signed OpenShift Routes). `"true"` = enforce verification. | Set to `"true"` in environments with valid certificates. |

> The Model Gateway **API key** is not set here — see [§10](#10-secrets).

---

## 5. `app`

```yaml
app:
  defaultTopK: "5"
```

Application-level tuning parameters.

| Field | Description | How to change |
|---|---|---|
| `defaultTopK` | Number of document chunks retrieved from CAS per RAG query. A higher value gives the LLM more context but increases latency. | Set to any positive integer string, e.g. `"10"`. |

---

## 6. `replicaCount`

```yaml
replicaCount: 1
```

Number of pod replicas for the Deployment.

**How to change:**  
Increase for high availability. The application is stateless so multiple replicas work without additional configuration.

```yaml
replicaCount: 2
```

---

## 7. `service`

```yaml
service:
  port: 8000
  targetPort: 8000
  type: ClusterIP
```

Configures the Kubernetes `Service` that fronts the Deployment.

| Field | Description | How to change |
|---|---|---|
| `port` | Port the Service exposes to the cluster. | Only change if `8000` conflicts with another service. |
| `targetPort` | Port the container listens on. Must match `EXPOSE 8000` in the Dockerfile. | Do not change unless you rebuild the image with a different port. |
| `type` | Kubernetes service type. `ClusterIP` is correct when an OpenShift Route (or Ingress) is used for external access. | Use `NodePort` or `LoadBalancer` only on non-OpenShift clusters without an Ingress controller. |

---

## 8. `route`

```yaml
route:
  enabled: true
  timeoutSeconds: 300
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

Renders an **OpenShift Route** for external access. Has no effect on vanilla Kubernetes
clusters (set `enabled: false` and add an Ingress instead).

| Field | Description | How to change |
|---|---|---|
| `enabled` | `true` = create an OpenShift Route. `false` = skip (use Ingress). | Set `false` on non-OpenShift clusters. |
| `timeoutSeconds` | HAProxy Route timeout in seconds. Must be **≥** `cpu.inferenceTimeoutSeconds` to avoid HTTP 504 errors on long CPU inference requests. OpenShift's default is 30 s — too short. | Increase if you see 504 errors for slow queries. |
| `tls.termination` | TLS termination mode. `edge` = TLS terminated at the router. | `passthrough` or `reencrypt` for end-to-end TLS. |
| `tls.insecureEdgeTerminationPolicy` | What to do with plain HTTP traffic. `Redirect` = 301 to HTTPS. | Use `Allow` only for testing. |

---

## 9. `resources`

```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

Kubernetes resource requests and limits for the chat-app container.

| Field | Description | Guidance |
|---|---|---|
| `requests.memory` | Minimum memory the scheduler guarantees. | `512Mi` is sufficient for the FastAPI + static file server. |
| `requests.cpu` | Minimum CPU the scheduler guarantees (in millicores). | `250m` = ¼ of a core. |
| `limits.memory` | Hard cap on memory. OOMKill if exceeded. | Increase to `4Gi` for heavy concurrent traffic. |
| `limits.cpu` | Hard cap on CPU. Pod is throttled if exceeded. | `1000m` = 1 full core. Increase for high request throughput. |

---

## 10. `secrets`

The application needs two API keys at runtime:

| Secret key | Used for |
|---|---|
| `cas_api_key` | Authenticating to the CAS REST / MCP API |
| `model_gateway_api_key` | Bearer token for the Model Gateway |

Both are mounted into the pod from a Kubernetes Secret named `llmops-secrets`.
Choose **exactly one** of the two options below to create that Secret.

---

### Option A: ExternalSecret — Vault (production)

```yaml
secrets:
  externalSecret:
    enabled: true               # ← must be true
    refreshInterval: "5m"
    secretStoreName: vault-backend
    secretStoreKind: ClusterSecretStore
    vaultPath: "llmops-platform/secrets"
  hardcoded:
    enabled: false              # ← must be false
```

Renders an `ExternalSecret` resource. The **External Secrets Operator (ESO)** must be
installed on the cluster. ESO reads `cas_api_key` and `model_gateway_api_key` from
HashiCorp Vault and writes them into the `llmops-secrets` Kubernetes Secret automatically,
refreshing every `refreshInterval`.

| Field | Description | How to change |
|---|---|---|
| `enabled` | Toggle this option on. | `true` |
| `refreshInterval` | How often ESO re-syncs from Vault. | `"1m"` for faster rotation, `"1h"` for less Vault load. |
| `secretStoreName` | Name of the ESO `ClusterSecretStore` / `SecretStore` that points to your Vault instance. | Change to match your ESO store name. |
| `secretStoreKind` | `ClusterSecretStore` (cluster-scoped) or `SecretStore` (namespace-scoped). | Use `SecretStore` if your ESO store is namespace-scoped. |
| `vaultPath` | Vault KV v2 path. The path must contain keys `cas_api_key` and `model_gateway_api_key`. | Change to match your Vault layout. |

**Required Vault setup:**
```bash
vault kv put secret/llmops-platform/secrets \
  cas_api_key="<your-cas-token>" \
  model_gateway_api_key="<your-gateway-bearer-token>"
```

---

### Option B: Hardcoded Secret (dev/CI)

```yaml
secrets:
  externalSecret:
    enabled: false              # ← must be false
  hardcoded:
    enabled: true               # ← must be true
    casApiKey: "sha256~..."
    modelGatewayApiKey: "my-token"
```

Renders a plain `kind: Secret`. Useful for local development and CI pipelines where
Vault is not available.

| Field | Description |
|---|---|
| `casApiKey` | Raw CAS API key string. |
| `modelGatewayApiKey` | Raw Model Gateway bearer token. |

> ⛔ **Never commit real credentials here.** Use a `.gitignore`-d override file or
> inject values at deploy time with `helm install --set secrets.hardcoded.casApiKey=...`.

---

## 11. `cpu`

Configures the three CPU-backed KServe InferenceServices used for
**chat**, **code**, and **summarization** tasks.

```yaml
cpu:
  modelsNamespace: "deploy-models-cpu"
  inferenceTimeoutSeconds: "300"
  models:
    chat: { ... }
    code: { ... }
    summarize: { ... }
  tokens:
    externalSecret: { ... }
    hardcoded: { ... }
```

| Field | Description | How to change |
|---|---|---|
| `modelsNamespace` | Namespace where the KServe InferenceServices and their ServiceAccounts live. The KServe RBAC RoleBinding is created in **this** namespace. | Change if you deployed InferenceServices in a different namespace. |
| `inferenceTimeoutSeconds` | Timeout (seconds) for requests to KServe predictors, set as `INFERENCE_TIMEOUT_S` env var in the pod. Must also be ≤ `route.timeoutSeconds`. | Increase for very large CPU models that take longer to respond. |

---

### `cpu.models`

Each task slot (`chat`, `code`, `summarize`) configures one KServe InferenceService.
The Helm template emits four env vars per slot:
`MODEL_URL_<TASK>`, `MODEL_ID_<TASK>`, `MODEL_TOKEN_<TASK>`, `MODEL_CAPS_<TASK>`.

```yaml
cpu:
  models:
    chat:
      id: "qwen2-5-1-5b-cpu"
      url: "https://qwen2-5-1-5b-cpu-predictor.deploy-models-cpu.svc.cluster.local:8443"
      saName: "qwen2-5-1-5b-cpu-sa"
      capabilities: "chat"
    code:
      id: "qwen2-5-coder-1-5b-cpu"
      url: "https://qwen2-5-coder-1-5b-cpu-predictor.deploy-models-cpu.svc.cluster.local:8443"
      saName: "qwen2-5-coder-1-5b-cpu-sa"
      capabilities: "code"
    summarize:
      id: "smollm2-1-7b-cpu"
      url: "https://smollm2-1-7b-cpu-predictor.deploy-models-cpu.svc.cluster.local:8443"
      saName: "smollm2-1-7b-cpu-sa"
      capabilities: "summarize"
```

For each task, the following fields apply:

| Field | Description | How to change |
|---|---|---|
| `id` | The vLLM model ID string sent in the `"model"` field of the OpenAI `/v1/chat/completions` payload. Must match the model loaded by vLLM inside the InferenceService. | Change when you deploy a different model. |
| `url` | Internal cluster URL of the KServe predictor Service. Format: `https://<name>-predictor.<namespace>.svc.cluster.local:8443`. | Update when you deploy InferenceServices with different names or in a different namespace. |
| `saName` | The Kubernetes ServiceAccount name whose token is used to authenticate to the KServe predictor (Authorino token review). The RBAC templates bind `kserve-view` to all `saName` values listed here. | Must match the SA created by the InferenceService in `modelsNamespace`. |
| `capabilities` | Comma-separated string of use-case labels this model supports. Consumed by the backend's **Auto Detect** feature to select the right model for a prompt. If omitted, defaults to the task slot name. | Add multiple values, e.g. `"chat,summarize"`, if one model covers several use cases. |

**Example — swap the code model:**
```yaml
cpu:
  models:
    code:
      id: "deepseek-coder-1-3b-cpu"
      url: "https://deepseek-coder-1-3b-cpu-predictor.deploy-models-cpu.svc.cluster.local:8443"
      saName: "deepseek-coder-1-3b-cpu-sa"
      capabilities: "code"
```

**Example — one model covers both chat and summarize:**
```yaml
cpu:
  models:
    chat:
      id: "my-general-cpu-model"
      url: "https://my-general-cpu-model-predictor.deploy-models-cpu.svc.cluster.local:8443"
      saName: "my-general-cpu-model-sa"
      capabilities: "chat,summarize"
```

---

### `cpu.tokens`

The KServe predictors require a bearer token to authorise incoming requests (Authorino /
KServe token review). These tokens originate as Kubernetes Secrets in `modelsNamespace`
but **cannot be referenced across namespaces** with a `secretKeyRef`. The chart therefore
copies them into the app namespace (`llmops-platform`) as a Secret named `llmops-cpu-tokens`,
which the Deployment reads via `MODEL_TOKEN_<TASK>` env vars.

Choose **exactly one** option:

---

#### Option A: ExternalSecret — Vault (production)

```yaml
cpu:
  tokens:
    externalSecret:
      enabled: true
      refreshInterval: "5m"
      secretStoreName: vault-backend
      secretStoreKind: ClusterSecretStore
      vaultPath: "llmops-platform/secrets"
      chatTokenSecret: "external-access-token-qwen2-5-1-5b-cpu-sa"
      codeTokenSecret: "external-access-token-qwen2-5-coder-1-5b-cpu-sa"
      summarizeTokenSecret: "external-access-token-smollm2-1-7b-cpu-sa"
    hardcoded:
      enabled: false
```

| Field | Description | How to change |
|---|---|---|
| `enabled` | Toggle this option on. | `true` |
| `refreshInterval` | ESO re-sync frequency. | Same guidance as `secrets.externalSecret.refreshInterval`. |
| `secretStoreName` | ESO store name pointing to Vault. | Usually the same store as `secrets.externalSecret.secretStoreName`. |
| `secretStoreKind` | `ClusterSecretStore` or `SecretStore`. | Match your ESO setup. |
| `vaultPath` | Vault KV path. The three token keys are stored **in the same path** as `cas_api_key` and `model_gateway_api_key`. | Add the token keys to the existing path or use a different path. |
| `chatTokenSecret` | Vault key name that holds the bearer token for the **chat** CPU model's ServiceAccount. | Change to match the Vault key name for your model's SA token. |
| `codeTokenSecret` | Same for the **code** CPU model. | Change when you swap the code model. |
| `summarizeTokenSecret` | Same for the **summarize** CPU model. | Change when you swap the summarize model. |

**Required Vault setup** (run once per model, or add to your existing secret):
```bash
vault kv patch secret/llmops-platform/secrets \
  external-access-token-qwen2-5-1-5b-cpu-sa="<chat-token>" \
  external-access-token-qwen2-5-coder-1-5b-cpu-sa="<code-token>" \
  external-access-token-smollm2-1-7b-cpu-sa="<summarize-token>"
```

Retrieve the raw token from OpenShift before storing in Vault:
```bash
oc get secret external-access-token-<model>-sa \
  -n deploy-models-cpu \
  -o jsonpath='{.data.token}' | base64 -d
```

---

#### Option B: Hardcoded tokens (dev/CI)

```yaml
cpu:
  tokens:
    externalSecret:
      enabled: false
    hardcoded:
      enabled: true
      chatToken: "eyJhbGci..."
      codeToken: "eyJhbGci..."
      summarizeToken: "eyJhbGci..."
```

| Field | Description |
|---|---|
| `chatToken` | Raw bearer token for the chat CPU model SA. |
| `codeToken` | Raw bearer token for the code CPU model SA. |
| `summarizeToken` | Raw bearer token for the summarize CPU model SA. |

Retrieve token values with:
```bash
oc get secret external-access-token-<model>-sa \
  -n deploy-models-cpu \
  -o jsonpath='{.data.token}' | base64 -d
```

> ⛔ Do not commit tokens to Git. Pass them at deploy time:
> ```bash
> helm upgrade --install llmops-chat-app ./chart \
>   --set cpu.tokens.hardcoded.chatToken="$(cat chat.token)"
> ```

---

## 12. `reloader`

```yaml
reloader:
  enabled: true
```

When `true`, the Deployment is annotated for **Stakater Reloader**. Reloader watches
`llmops-config` (ConfigMap) and `llmops-secrets` / `llmops-cpu-tokens` (Secrets) and
automatically triggers a rolling restart when any of them change.

| Value | Effect |
|---|---|
| `true` | Pod restarts automatically when config or secrets change — no manual `kubectl rollout restart` needed after a GitOps push. |
| `false` | Pod does not restart automatically. You must trigger a restart manually or via ArgoCD. Use this if Reloader is not installed. |

> Reloader must be installed on the cluster (`helm install reloader stakater/reloader`).
> Setting `enabled: true` without Reloader installed has no effect — it only adds
> annotations to the Deployment.

---

## 13. `syncWaves`

```yaml
syncWaves:
  rbac: "0"
  config: "1"
  secrets: "2"
  app: "3"
```

Controls the **ArgoCD sync-wave** order — the sequence in which ArgoCD applies
Kubernetes resources during a sync operation.

| Wave | Resources applied | Why this order |
|---|---|---|
| `"0"` — rbac | ServiceAccounts, Roles, RoleBindings, KServe RBAC | Must exist before secrets and the app can reference them |
| `"1"` — config | `llmops-config` ConfigMap | Must exist before the Deployment reads env vars from it |
| `"2"` — secrets | `llmops-secrets`, `llmops-cpu-tokens` (ExternalSecret or plain Secret) | Must exist before the Deployment mounts them |
| `"3"` — app | Deployment, Service, Route | Starts only after all dependencies are ready |

**How to change:**  
Only change these if you have other chart dependencies that need to be interleaved.
Increase the `app` wave number if you need other resources to apply first.

```yaml
syncWaves:
  rbac: "0"
  config: "1"
  secrets: "2"
  app: "5"   # ← let wave 3 and 4 be used by other charts
```

---

## 14. Common Scenarios

### Deploy to a new cluster

1. Update `namespace` to your target namespace.
2. Set `cas.endpoint` and `modelGateway.endpoint` to your cluster's Route URLs.
3. Set `modelGateway.modelName` to a model available on your gateway.
4. Update `cpu.models.*` URLs to match your KServe InferenceService hostnames.
5. Choose a secrets backend (Vault or hardcoded) and populate credentials.
6. Push — ArgoCD syncs automatically.

---

### Switch from hardcoded secrets to Vault

```yaml
secrets:
  externalSecret:
    enabled: true          # ← turn on
    vaultPath: "my-team/llmops-secrets"
  hardcoded:
    enabled: false         # ← turn off
    casApiKey: ""          # ← clear (optional but recommended)
    modelGatewayApiKey: "" # ← clear
```

---

### Swap a CPU model

Change the relevant task slot. All four fields must be consistent with the new
InferenceService deployment:

```yaml
cpu:
  models:
    code:
      id: "my-new-code-model"
      url: "https://my-new-code-model-predictor.deploy-models-cpu.svc.cluster.local:8443"
      saName: "my-new-code-model-sa"
      capabilities: "code"
```

Also update the token in Vault (or in `cpu.tokens.hardcoded.codeToken`) to the SA token
for the new model.

---

### Disable CPU models entirely

Remove (or comment out) all entries under `cpu.models`. The backend will start without
any CPU model registrations. The unified model dropdown will show only gateway models.

```yaml
cpu:
  modelsNamespace: "deploy-models-cpu"
  inferenceTimeoutSeconds: "300"
  models: {}   # ← empty map — no CPU models registered
```

---

### Run without an OpenShift Route (vanilla Kubernetes)

```yaml
route:
  enabled: false
```

Then add a standard `Ingress` resource manually or via a separate chart.

---

### Scale up replicas

```yaml
replicaCount: 3
```

The application is stateless; all replicas share the same ConfigMap and Secrets.
No session affinity is required.
