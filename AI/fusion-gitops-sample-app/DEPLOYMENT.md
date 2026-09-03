# Deployment Guide — Agentic Chat Assistant

> **New here?** Start with [README.md](./README.md) for an overview of the application,
> its architecture, and local development setup. Come back here when you're ready to deploy
> to an OpenShift cluster.

Step-by-step instructions to build, configure, and deploy the application on OpenShift
using ArgoCD + Helm. Read this before touching any configuration file.

---

## Table of Contents

1. [GitOps deployment topology](#1-gitops-deployment-topology)
2. [Prerequisites](#2-prerequisites)
   - [Cluster & operator prerequisites](#cluster--operator-prerequisites)
   - [Local tooling prerequisites](#local-tooling-prerequisites)
   - [Platform services that must be running](#platform-services-that-must-be-running)
3. [Before you begin — collect these values](#3-before-you-begin--collect-these-values)
4. [Step 1 — Fork & clone the repository](#step-1--fork--clone-the-repository)
5. [Step 2 — Build and push the container image](#step-2--build-and-push-the-container-image)
6. [Step 3 — Configure `chart/values.yaml`](#step-3--configure-chartvaluesyaml)
7. [Step 4 — Store secrets in Vault](#step-4--store-secrets-in-vault)
8. [Step 5 — Commit and push](#step-5--commit-and-push)
9. [Step 6 — Deploy with ArgoCD](#step-6--deploy-with-argocd)
10. [Step 7 — Verify the deployment](#step-7--verify-the-deployment)
11. [Accessing the application](#8-accessing-the-application)
12. [Day-2 operations](#9-day-2-operations)
13. [Troubleshooting](#10-troubleshooting)

---

## 1. GitOps deployment topology

For application architecture (components, API routes, code paths) see [README.md → Architecture](./README.md#architecture).

This diagram shows how ArgoCD orchestrates the cluster resources:

```
Git repository  (values.yaml changes)
       │
       ▼  ArgoCD auto-sync
┌──────────────────────────────────────────────────────┐
│  OpenShift cluster  (namespace: llmops-platform)     │
│                                                      │
│  Sync wave 0: RBAC                                   │
│  Sync wave 1: ConfigMap  (endpoints, model name)     │
│  Sync wave 2: Secrets    (ExternalSecret → Vault)    │
│  Sync wave 3: Deployment + Service + Route           │
│                                                      │
│  Pod: FastAPI (port 8000) + React SPA (static files) │
│        │                         │                   │
│        ▼  RAG path               ▼  CPU path         │
│  CAS vector store         KServe InferenceServices   │
│  Model Gateway (GPU)      (your models namespace)    │
│  (remote cluster)                                    │
└──────────────────────────────────────────────────────┘
```

---

## 2. Prerequisites

### Cluster & operator prerequisites

The following must already be installed and running on your OpenShift cluster
**before** you deploy this application.

| Requirement | Why it is needed | How to verify |
|---|---|---|
| **OpenShift GitOps (ArgoCD)** | Drives GitOps sync of the Helm chart | `oc get pods -n openshift-gitops` |
| **External Secrets Operator (ESO)** | Pulls `cas_api_key` and `model_gateway_api_key` from Vault into Kubernetes Secrets | `oc get pods -n external-secrets` |
| **HashiCorp Vault** | Stores all API keys and bearer tokens | `vault status` |
| **ESO `ClusterSecretStore`** named `vault-backend` | Connects ESO to your Vault instance | `oc get clustersecretstore vault-backend` |
| **Stakater Reloader** | Auto-restarts the pod when ConfigMap or Secrets change (optional but recommended) | `oc get pods -n reloader` |
| **LLM Models** (at least one source) | Provides inference; deploy based on available resources — see table below | — |
| **IBM CAS (Content-Aware Storage)** | Provides the RAG vector store | CAS Route URL accessible from cluster |

**LLM model sources** — deploy one or both based on your available resources:

| Source | When to use | Deployment guide |
|---|---|---|
| **Model Gateway** (GPU / remote cluster) | Accessible endpoint with Bearer token authentication | [IBM Fusion MaaS Platform — GitOps Deployment](https://community.ibm.com/community/user/blogs/harichandana-kotha/2026/06/29/quickstart-maas-ibm-fusion-gitops) |
| **CPU KServe InferenceServices** (local CPU) | Run small open-source LLMs on existing x86 nodes | [CPU-Based LLM Inference on IBM Fusion — GitOps Deployment](../quickstarts/model-as-a-service/infoDocs/gitops-cpu-deployment-guide.md) |

> Both sources can be used together — the application merges them into a single model dropdown automatically.

> **Reloader** can be deployed automatically by applying
> `gitops/llmops-with-reloader.yaml` (see [Step 6](#step-6--deploy-with-argocd)).

---

### Local tooling prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| `oc` / `kubectl` | 4.12 | [OpenShift CLI](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html) |
| `podman` | 4.x | `brew install podman` (macOS) |
| `helm` | 3.12 | `brew install helm` |
| `vault` CLI | 1.14 | `brew tap hashicorp/tap && brew install hashicorp/tap/vault` |
| `git` | 2.x | Installed with Xcode CLT |
| `python3` | 3.11 | Required only for `scripts/validate_*.py` and `scripts/verify_deployment.sh` |

---

### Platform services that must be running

Before you start, confirm the services you are using are reachable from within the cluster:

```bash
# CAS — should return 200 and a JSON list of vector stores
curl -sk -H "Authorization: Bearer <your-cas-api-key>" \
  https://<cas-route>/cas/api/v1/vector_stores | python3 -m json.tool

# Model Gateway (if using) — should return a list of available models
curl -sk -H "Authorization: Bearer <your-gateway-api-key>" \
  https://<gateway-route>/v1/models | python3 -m json.tool

# CPU KServe InferenceServices (if using) — all should show READY=True
oc get inferenceservice -n <your-models-namespace>
```

---

## 3. Before you begin — collect these values

Gather these values before editing any file. You will need them in Steps 3 and 4.

| Value | Where to find it | Used in |
|---|---|---|
| CAS Route URL | `oc get route -n ibm-cas` | `chart/values.yaml` → `cas.endpoint` |
| CAS API key | CAS admin / ServiceAccount token | Vault secret |
| Model Gateway Route URL | `oc get route -n model-gateway` | `chart/values.yaml` → `modelGateway.endpoint` |
| Model Gateway API key | Model Gateway admin / ServiceAccount token | Vault secret |
| Default model name | `curl .../v1/models` — pick a model ID | `chart/values.yaml` → `modelGateway.modelName` |
| Container image registry URL | Your Artifactory / Quay / registry | `chart/values.yaml` → `image.repository` |
| CPU model predictor URLs (if using CPU models) | `oc get inferenceservice -n <your-models-namespace> -o jsonpath=...` | `chart/values.yaml` → `cpu.models.*.url` |
| CPU SA bearer tokens ×3 (if using CPU models) | `oc get secret external-access-token-<model>-sa -n <your-models-namespace>` | Vault secret |

---

## Step 1 — Fork & clone the repository

```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/AI/fusion-gitops-sample-app
```

> ArgoCD will watch **your fork**, so all configuration changes must be committed
> and pushed to your fork's branch.

---

## Step 2 — Build and push the container image

The application is packaged as a single container (React SPA + FastAPI backend).

```bash
# Set your target registry and tag
export IMAGE_NAME="quay.io/my-org/chat-app:v1.0.0"

# Build (two-stage: Node 20 → Python 3.11) and push
bash scripts/build_and_push_chat_app.sh
```

> **Apple Silicon note:** Stage 1 (Node/React) builds on native arm64.
> Stage 2 (Python/FastAPI) builds for linux/amd64 under QEMU.
> No extra flags are needed — the Dockerfile handles this.

After a successful push you will see:
```
✅ Image ready: quay.io/my-org/chat-app:v1.0.0
```

Note the full image name and tag — you need it in the next step.

---

## Step 3 — Configure `chart/values.yaml`

Open [`chart/values.yaml`](./chart/values.yaml) and update every section
that contains a placeholder. A detailed explanation of every field is in
[`chart/VALUES.md`](./chart/VALUES.md).

### 3a. Container image

```yaml
image:
  repository: quay.io/my-org/chat-app    # ← your registry path (no tag)
  tag: v1.0.0                            # ← tag from Step 2
  pullPolicy: Always
```

### 3b. CAS endpoint

```yaml
cas:
  endpoint: "https://<cas-route-host>/"  # ← trailing slash required
  useMcp: "false"                         # "true" only if MCP is enabled on CAS
```

### 3c. Model Gateway

```yaml
modelGateway:
  endpoint: "https://<gateway-route-host>"   # ← no trailing slash
  modelName: "qwen2-5-72b-instruct"          # ← must match a model ID from /v1/models
  verifySSL: "false"                          # "true" if the Route has a valid cert
```

> `modelName` becomes the **default model** in the UI and the CAS+ fallback for
> Auto Detect. Set it to the largest / most capable model available on your gateway.

### 3d. CPU models

For each of the three task slots, update `id`, `url`, and `saName` to match your
KServe InferenceService deployments:

```bash
# Get the predictor URL for each InferenceService
oc get inferenceservice -n <your-models-namespace> \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.url}{"\n"}{end}'
```

Replace the example values below with the models you have deployed. The author deployed three CPU models following the [CPU-Based LLM Inference on IBM Fusion guide](../quickstarts/model-as-a-service/infoDocs/gitops-cpu-deployment-guide.md); you can deploy any models using the `model-deploy-vllm-cpu` Helm chart and reference them here.

```yaml
cpu:
  modelsNamespace: "<your-models-namespace>"   # ← namespace where InferenceServices live
  inferenceTimeoutSeconds: "300"

  models:
    chat:
      id: "qwen2-5-1-5b-cpu"                   # ← vLLM model ID (must match what vLLM loaded)
      url: "https://qwen2-5-1-5b-cpu-predictor.<your-models-namespace>.svc.cluster.local:8443"
      saName: "qwen2-5-1-5b-cpu-sa"            # ← SA name in modelsNamespace
      capabilities: "chat"
    code:
      id: "qwen2-5-coder-1-5b-cpu"
      url: "https://qwen2-5-coder-1-5b-cpu-predictor.<your-models-namespace>.svc.cluster.local:8443"
      saName: "qwen2-5-coder-1-5b-cpu-sa"
      capabilities: "code"
    summarize:
      id: "smollm2-1-7b-cpu"
      url: "https://smollm2-1-7b-cpu-predictor.<your-models-namespace>.svc.cluster.local:8443"
      saName: "smollm2-1-7b-cpu-sa"
      capabilities: "summarize"
```

### 3e. Secrets backend

**Production (default — Vault ExternalSecret):**
```yaml
secrets:
  externalSecret:
    enabled: true
    refreshInterval: "5m"
    secretStoreName: vault-backend          # ← must match your ClusterSecretStore name
    secretStoreKind: ClusterSecretStore
    vaultPath: "llmops-platform/secrets"    # ← Vault KV path (see Step 4)
  hardcoded:
    enabled: false
    casApiKey: ""
    modelGatewayApiKey: ""
```

**Development only (hardcoded — no Vault needed):**
```yaml
secrets:
  externalSecret:
    enabled: false
  hardcoded:
    enabled: true
    casApiKey: "sha256~your-cas-token"
    modelGatewayApiKey: "your-gateway-token"
```

### 3f. CPU token secrets backend

```yaml
cpu:
  tokens:
    externalSecret:
      enabled: true                           # ← production
      vaultPath: "llmops-platform/secrets"    # ← same Vault path as above
      chatTokenSecret: "external-access-token-qwen2-5-1-5b-cpu-sa"
      codeTokenSecret: "external-access-token-qwen2-5-coder-1-5b-cpu-sa"
      summarizeTokenSecret: "external-access-token-smollm2-1-7b-cpu-sa"
    hardcoded:
      enabled: false
```

### 3g. ArgoCD Application source (in `gitops/llmops-with-reloader.yaml`)

Update the `repoURL` and `targetRevision` to point to **your fork**:

```yaml
spec:
  source:
    repoURL: https://github.com/IBM/storage-fusion.git     # ← your fork
    targetRevision: master                                  # ← your branch
    path: AI/fusion-gitops-sample-app/chart
```

---

## Step 4 — Store secrets in Vault

All sensitive values are pulled from Vault by the External Secrets Operator.
Store them at the path you configured in `values.yaml` (`llmops-platform/secrets`):

```bash
# Log in to Vault
export VAULT_ADDR="https://your-vault-instance"
vault login

# Store CAS and Model Gateway API keys
vault kv put secret/llmops-platform/secrets \
  cas_api_key="<your-cas-api-key>" \
  model_gateway_api_key="<your-model-gateway-bearer-token>"
```

Now add the three CPU SA bearer tokens to the **same path**.
Retrieve each token from the InferenceService namespace first:

```bash
# Retrieve token for the chat CPU model SA
CHAT_TOKEN=$(oc get secret external-access-token-qwen2-5-1-5b-cpu-sa \
  -n <your-models-namespace> \
  -o jsonpath='{.data.token}' | base64 -d)

# Retrieve token for the code CPU model SA
CODE_TOKEN=$(oc get secret external-access-token-qwen2-5-coder-1-5b-cpu-sa \
  -n <your-models-namespace> \
  -o jsonpath='{.data.token}' | base64 -d)

# Retrieve token for the summarize CPU model SA
SUMMARIZE_TOKEN=$(oc get secret external-access-token-smollm2-1-7b-cpu-sa \
  -n <your-models-namespace> \
  -o jsonpath='{.data.token}' | base64 -d)

# Add all three tokens to the same Vault secret (patch preserves existing keys)
vault kv patch secret/llmops-platform/secrets \
  external-access-token-qwen2-5-1-5b-cpu-sa="$CHAT_TOKEN" \
  external-access-token-qwen2-5-coder-1-5b-cpu-sa="$CODE_TOKEN" \
  external-access-token-smollm2-1-7b-cpu-sa="$SUMMARIZE_TOKEN"
```

Verify the secret contains all five keys:

```bash
vault kv get secret/llmops-platform/secrets
```

Expected output (values redacted):
```
Key                                              Value
---                                              -----
cas_api_key                                      sha256~...
model_gateway_api_key                            eyJhbG...
external-access-token-qwen2-5-1-5b-cpu-sa       eyJhbG...
external-access-token-qwen2-5-coder-1-5b-cpu-sa eyJhbG...
external-access-token-smollm2-1-7b-cpu-sa        eyJhbG...
```

---

## Step 5 — Commit and push

```bash
cd storage-fusion   # repository root

git add AI/fusion-gitops-sample-app/chart/values.yaml \
        AI/fusion-gitops-sample-app/gitops/llmops-with-reloader.yaml

git commit -m "chore: configure values.yaml for <environment>"
git push origin master
```

> ArgoCD watches the repository and will auto-sync within seconds of the push.
> If automated sync is not yet configured, trigger a manual sync in Step 6.

---

## Step 6 — Deploy with ArgoCD

Apply the ArgoCD Applications once. Everything else is managed by ArgoCD from that point.

```bash
# Log in to OpenShift
oc login --token=<your-token> --server=https://<cluster-api>

# Apply both ArgoCD Applications:
#   1. reloader      — Stakater Reloader (watches ConfigMap/Secret changes)
#   2. llmops-platform — the chat app Helm chart
oc apply -f fusion-gitops-sample-app/gitops/llmops-with-reloader.yaml
```

ArgoCD will now manage both applications. Sync waves ensure resources are applied
in the correct order:

```
Wave 0  →  RBAC (Roles, RoleBindings, KServe ClusterRoleBinding)
Wave 1  →  ConfigMap llmops-config
Wave 2  →  ExternalSecret → ESO syncs → llmops-secrets + llmops-cpu-tokens
Wave 3  →  Deployment + Service + OpenShift Route
```

Monitor sync progress:

```bash
# Watch ArgoCD application status
oc get application llmops-platform -n openshift-gitops -w

# Or use the ArgoCD UI
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

Wait until both applications show `Synced` / `Healthy`:

```
NAME               SYNC STATUS   HEALTH STATUS
llmops-platform    Synced        Healthy
reloader           Synced        Healthy
```

---

## Step 7 — Verify the deployment

Run the verification script to confirm every component is working:

```bash
bash fusion-gitops-sample-app/scripts/verify_deployment.sh
```

The script checks:

| Check | What it validates |
|---|---|
| Pod status | Pod is `Running` and container is `Ready` |
| ConfigMap | All required keys are present and non-empty |
| Secret | `cas_api_key` and `model_gateway_api_key` are non-empty |
| `/healthz` | Returns `{"status":"ok","ready":true}` |
| `/api/models` | Returns at least one model (gateway + CPU) |
| `/api/vector-stores` | Returns at least one CAS vector store |
| ArgoCD status | Application is `Synced` and `Healthy` |

Expected output when healthy:
```
── Pod ──────────────────────────────────────────
  ✅ Phase: Running
  ✅ Container ready

── ConfigMap (llmops-config) ──────────────────────
  ✅ cas-endpoint         : https://ibm-cas...
  ✅ model-gateway-endpoint: https://model-gateway...
  ✅ model-name           : qwen2-5-72b-instruct

── Secret (llmops-secrets) ──────────────────────
  ✅ cas_api_key is set (47 chars)
  ✅ model_gateway_api_key is set (183 chars)

── Health (/healthz) ──────────────────────────
  ✅ Service is ready

── API — /api/models ──────────────────────────
  ✅ 4 model(s): [{"id":"qwen2-5-72b-instruct",...},...]

── API — /api/vector-stores ──────────────────────
  ✅ 1 vector store(s) available

── ArgoCD ──────────────────────────────────────
  ✅ Sync   : Synced
  ✅ Health : Healthy

═══════════════════════════════════════════════════════════════
  ✅  All checks passed — deployment is healthy
═══════════════════════════════════════════════════════════════
```

---

## 8. Accessing the application

### Via OpenShift Route (default)

```bash
# Get the Route URL
oc get route llmops-chat-app -n llmops-platform -o jsonpath='{.spec.host}'
# Open: https://<route-host>
```

### Via port-forward (no Route)

```bash
kubectl port-forward svc/llmops-chat-app 8000:8000 -n llmops-platform
# Open: http://localhost:8000
```

### Available API endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/healthz` | GET | Liveness / readiness probe |
| `/api/config` | GET | Active endpoint config (no secrets) |
| `/api/vector-stores` | GET | Available CAS vector stores |
| `/api/models` | GET | All models — gateway + CPU (unified list) |
| `/api/chat` | POST | Unified chat — gateway or CPU, with optional RAG |
| `/api/rag/chat` | POST | Legacy RAG-only endpoint (backward compat) |
| `/api/cpu/models` | GET | Legacy CPU task → model mapping |
| `/api/cpu/chat` | POST | Legacy CPU-only endpoint (backward compat) |

---

## 9. Day-2 operations

### Update the container image

```bash
# Build and push new image
export IMAGE_NAME="quay.io/my-org/chat-app:v1.1.0"
bash scripts/build_and_push_chat_app.sh

# Update values.yaml
# chart/values.yaml → image.tag: v1.1.0

git commit -am "chore: bump image to v1.1.0"
git push
# ArgoCD auto-syncs → rolling restart with new image
```

### Rotate an API key

```bash
# Update the key in Vault
vault kv patch secret/llmops-platform/secrets \
  cas_api_key="new-rotated-key"

# ESO refreshes the Secret within refreshInterval (default: 5m)
# Reloader detects the Secret change and triggers a rolling restart automatically
```

### Swap a CPU model

1. Deploy the new InferenceService in your models namespace.
2. Add its SA token to Vault.
3. Update `chart/values.yaml` → `cpu.models.<task>`:

```yaml
cpu:
  models:
    code:
      id: "new-code-model"
      url: "https://new-code-model-predictor.<your-models-namespace>.svc.cluster.local:8443"
      saName: "new-code-model-sa"
      capabilities: "code"
```

4. Commit and push — ArgoCD deploys the change.

### Scale the application

```yaml
# chart/values.yaml
replicaCount: 3
```

Commit and push — ArgoCD applies the scaling immediately.

---

## 10. Troubleshooting

### Pod is not starting

```bash
# Check pod events
oc describe pod -n llmops-platform -l app.kubernetes.io/name=llmops-chat-app

# Check container logs
oc logs -n llmops-platform deployment/llmops-chat-app
```

Common causes:
- `ImagePullBackOff` → registry credentials not configured or wrong image tag
- `CrashLoopBackOff` → missing env var; check ConfigMap and Secret are present

### `/healthz` returns `ready: false`

The backend started but could not connect to CAS or the Model Gateway at startup.

```bash
oc logs -n llmops-platform deployment/llmops-chat-app | grep -E "ERROR|WARNING|Failed"
```

Check:
- `CAS_ENDPOINT` is reachable from inside the cluster
- `MODEL_GATEWAY_ENDPOINT` is reachable
- `cas_api_key` and `model_gateway_api_key` in `llmops-secrets` are non-empty

### ExternalSecret not syncing

```bash
# Check ExternalSecret status
oc describe externalsecret llmops-secrets -n llmops-platform
oc describe externalsecret llmops-cpu-tokens -n llmops-platform
```

Common causes:
- `ClusterSecretStore` named `vault-backend` does not exist
- Vault path does not exist or the key names are wrong
- ESO service account lacks permission to read from Vault

### ArgoCD stuck in `OutOfSync`

```bash
oc get application llmops-platform -n openshift-gitops -o yaml | grep -A5 conditions
```

Force a manual sync:
```bash
argocd app sync llmops-platform
# or via oc
oc patch application llmops-platform -n openshift-gitops \
  --type merge -p '{"operation":{"sync":{}}}'
```

### CPU model returns 502 / connection refused

```bash
# Confirm the InferenceService is ready
oc get inferenceservice -n <your-models-namespace>

# Check the token in the cpu-tokens secret
oc get secret llmops-cpu-tokens -n llmops-platform \
  -o jsonpath='{.data.token_chat}' | base64 -d | head -c 20
```

Common causes:
- InferenceService not in `READY` state — it may still be loading the model
- Bearer token is expired or belongs to the wrong ServiceAccount
- `cpu.models.<task>.url` hostname does not match the predictor Service name

### 504 Gateway Timeout on long prompts

The OpenShift Route HAProxy timeout is shorter than the inference timeout.

```yaml
# chart/values.yaml
route:
  timeoutSeconds: 600   # increase to match or exceed cpu.inferenceTimeoutSeconds
cpu:
  inferenceTimeoutSeconds: "600"
```

---

## Reference

| File | Purpose |
|---|---|
| [`chart/values.yaml`](./chart/values.yaml) | All configuration — the only file you need to edit |
| [`chart/VALUES.md`](./chart/VALUES.md) | Full field-by-field reference for `values.yaml` |
| [`gitops/llmops-with-reloader.yaml`](./gitops/llmops-with-reloader.yaml) | ArgoCD Application manifests (apply once) |
| [`scripts/build_and_push_chat_app.sh`](./scripts/build_and_push_chat_app.sh) | Build and push the container image |
| [`scripts/verify_deployment.sh`](./scripts/verify_deployment.sh) | Post-deploy health check script |
| [`env.example`](./env.example) | Environment variable reference for local development |
