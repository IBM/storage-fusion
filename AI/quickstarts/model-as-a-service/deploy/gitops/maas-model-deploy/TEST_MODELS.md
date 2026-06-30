# Testing Deployed Models

This guide explains how to verify that models deployed by the ArgoCD Applications in
[`environments/`](environments/) are healthy and serving inference requests **through
the shared `openshift-ai-inference` Gateway**.

All external access uses a single base URL — the OpenShift Route that fronts the Gateway:

```
https://openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com
```

Each model is then reachable at:

```
https://<gateway-host>/<model-namespace>/<model-name>/v1/<endpoint>
```

Each section shows a **generic command** (using shell variables) followed by the
**exact command** for the models currently deployed in this repository, and the
**expected output** captured from the live cluster.

---

## Environment → Namespace Map

| Environment | ArgoCD Application(s) | Model Namespace |
|---|---|---|
| **Dev** | `fusion-maas-model-deploy-dev` | `deploy-models-dev` |
| **Staging** | `fusion-maas-model-deploy-staging` | `deploy-models-staging` |
| **Prod – tiny-llama** | `fusion-maas-model-deploy-prod-tiny-llama` | `deploy-models` |
| **Prod – gpt-oss-20b** | `fusion-maas-model-deploy-prod-gpt-oss-20b` | `deploy-models` |

---

## Gateway → Model URL Reference

| Model | External URL (via Gateway) |
|---|---|
| `tiny-llama-test` | `https://openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com/deploy-models/tiny-llama-test/v1/` |
| `gpt-oss-20b` | `https://openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com/deploy-models/gpt-oss-20b/v1/` |

---

## Step 1 — Confirm the ArgoCD Application is Synced and Healthy

### Generic

```bash
# All model-deploy Applications across every environment
oc get applications.argoproj.io -n openshift-gitops -l component=model-deploy

# Single application
oc get applications.argoproj.io <ARGOCD_APP_NAME> -n openshift-gitops
```

### Exact — Prod

```bash
oc get applications.argoproj.io \
  fusion-maas-model-deploy-prod-tiny-llama \
  fusion-maas-model-deploy-prod-gpt-oss-20b \
  -n openshift-gitops
```

**Expected output:**

```
NAME                                        SYNC STATUS   HEALTH STATUS
fusion-maas-model-deploy-prod-tiny-llama    OutOfSync     Healthy
fusion-maas-model-deploy-prod-gpt-oss-20b   OutOfSync     Healthy
```

> **Note:** `HEALTH STATUS = Healthy` confirms both models are running and serving
> requests. `SYNC STATUS = OutOfSync` in prod is expected — prod uses **manual sync
> only** (no `automated` block in the Application spec), so ArgoCD detects a diff
> between Git and the live cluster state but does not auto-apply it. Sync manually
> via the ArgoCD UI or `argocd app sync` only during an approved change window.

If `HEALTH STATUS` shows `Degraded`, inspect the Application:

```bash
oc describe applications.argoproj.io fusion-maas-model-deploy-prod-tiny-llama \
  -n openshift-gitops
```

---

## Step 2 — Verify the Gateway Route and HTTPRoutes

The `openshift-ai-inference` OpenShift Route and per-model HTTPRoutes must exist before
external traffic can reach any model.

```bash
# Confirm the shared gateway Route is present and has a hostname
oc get route openshift-ai-inference -n openshift-ingress \
  -o jsonpath='{.spec.host}{"\n"}'
```

**Expected output:**
```
openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com
```

```bash
# Confirm per-model HTTPRoutes are registered with the Gateway
oc get httproute -n deploy-models
```

**Expected output:**
```
NAME                           HOSTNAMES   AGE
gpt-oss-20b-kserve-route                   6h31m
tiny-llama-test-kserve-route               6h53m
```

> **Note:** The `HOSTNAMES` column is empty — this is expected. The HTTPRoutes use
> `parentRefs` to attach to the Gateway and rely on path-based routing (`/deploy-models/<model>/`),
> not hostname-based routing. Traffic is routed by path, not by virtual host.

```bash
# Inspect a specific HTTPRoute to confirm parentRef and path rules
oc get httproute tiny-llama-test-kserve-route -n deploy-models -o yaml | \
  grep -A5 "parentRefs\|matches\|backendRefs"
```

---

## Step 3 — Check LLMInferenceService CRs

Each Application deploys one `LLMInferenceService` CR. All eight conditions must be
`status: "True"` before a model can serve requests.

### Generic

```bash
# List all LLMInferenceService CRs in the target namespace
oc get llminferenceservice -n <MODEL_NAMESPACE>

# Full YAML for detailed condition inspection
oc get llminferenceservice <MODEL_NAME> -n <MODEL_NAMESPACE> -o yaml

# One-line ready summary
oc get llminferenceservice -n <MODEL_NAMESPACE> \
  -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status'
```

### Exact — Prod

```bash
oc get llminferenceservice -n deploy-models \
  -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status'
```

**Expected output:**

```
NAME              READY
gpt-oss-20b       True
tiny-llama-test   True
```

### Healthy CR conditions — all eight must show `status: "True"`

| Condition | Meaning |
|---|---|
| `PresetsCombined` | KServe config templates merged and applied |
| `InferencePoolReady` | Gateway InferencePool object created |
| `HTTPRoutesReady` | HTTPRoute objects registered with the gateway |
| `SchedulerWorkloadReady` | Scheduler pod running and ready |
| `RouterReady` | Router pod running and ready |
| `MainWorkloadReady` | vLLM model-server pod running and ready |
| `WorkloadsReady` | All component workloads are running |
| `Ready` | Overall CR ready — model is accepting requests |

---

## Step 4 — Verify Pods are Running

### Generic

```bash
# All pods in the model namespace
oc get pods -n <MODEL_NAMESPACE>

# Events for a failing namespace
oc get events -n <MODEL_NAMESPACE> --sort-by='.lastTimestamp'
```

### Exact — Prod

```bash
oc get pods -n deploy-models
```

**Expected output:**

```
NAME                                                       READY   STATUS    RESTARTS   AGE
gpt-oss-20b-kserve-6c578495d8-9j55c                        1/1     Running   0          5h4m
gpt-oss-20b-kserve-router-scheduler-749b854cd9-wgvk2       2/2     Running   0          5h4m
tiny-llama-test-kserve-5fc7599597-6fsjn                    1/1     Running   0          5h7m
tiny-llama-test-kserve-router-scheduler-7bf9477dc8-9hvn6   2/2     Running   0          5h8m
```

Each model has two pod types:
- **`<model>-kserve-*`** — the vLLM decode-worker; `1/1 Running`
- **`<model>-kserve-router-scheduler-*`** — combined router + scheduler sidecar; `2/2 Running`

`Pending` indicates a GPU scheduling issue; `CrashLoopBackOff` requires log inspection:

```bash
oc logs -n deploy-models <POD_NAME> --previous
```

---

## Step 5 — Send a Test Inference Prompt via the Gateway

Before running any inference command, you need to know the **full gateway hostname**.
It is composed of two parts:

```
https://<route-name>-<route-namespace>.<wildcard-domain>/<model-namespace>/<model-name>/v1/
         ─────────────────────────────  ────────────────────────────────────
               Part 1: Route host              Part 2: Cluster wildcard domain
```

---

### Part 1 — The Route hostname prefix (`openshift-ai-inference-openshift-ingress`)

This comes from the OpenShift Route created by the `gateway-route.yaml` template.
The Route is named `openshift-ai-inference` and lives in namespace `openshift-ingress`.
OpenShift constructs the hostname as `<route-name>-<route-namespace>`:

```
openshift-ai-inference  +  -  +  openshift-ingress
= openshift-ai-inference-openshift-ingress
```

Confirm the Route exists and read its hostname directly from the cluster:

```bash
oc get route openshift-ai-inference -n openshift-ingress \
  -o jsonpath='{.spec.host}{"\n"}'
```

**Expected output:**
```
openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com
```

---

### Part 2 — The cluster wildcard domain (`apps.f55l020.fusion.tadn.ibm.com`)

Every OpenShift cluster has a wildcard DNS domain that all Routes resolve under.
It is set when the cluster is installed and does not change.

Read it directly from the cluster's ingress configuration:

```bash
oc get ingresses.config.openshift.io cluster \
  -o jsonpath='{.spec.domain}{"\n"}'
```

**Expected output:**
```
apps.f55l020.fusion.tadn.ibm.com
```

This is also the value used for `gateway.wildcardDomain` in the Helm values files.

---

### Putting it together — the full gateway URL

```
https://  openshift-ai-inference-openshift-ingress  .  apps.f55l020.fusion.tadn.ibm.com  /  deploy-models  /  <model-name>  /v1/chat/completions
          ─────── Part 1: route name + namespace ────   ──────── Part 2: wildcard domain ───   ── namespace ──   ─ model name ─
```

Or, retrieve it in one command:

```bash
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress \
  -o jsonpath='{.spec.host}')
echo "Gateway host: ${GATEWAY_HOST}"

# Full URL for tiny-llama-test
echo "https://${GATEWAY_HOST}/deploy-models/tiny-llama-test/v1/chat/completions"

# Full URL for gpt-oss-20b
echo "https://${GATEWAY_HOST}/deploy-models/gpt-oss-20b/v1/chat/completions"
```

---

### Generic curl template (run directly in your terminal)

Ensure you are logged in to the cluster (`oc whoami` should return your username), then
run these commands directly — no pod creation needed.

Set `temperature: 0` for deterministic, reproducible output during testing.

```bash
# Step 1 — resolve the gateway hostname once
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress \
  -o jsonpath='{.spec.host}')

# Step 2 — send the request directly from your terminal
curl -sk -X POST "https://${GATEWAY_HOST}/deploy-models/<model-name>/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<model-name>",
    "messages": [{"role": "user", "content": "<YOUR_PROMPT>"}],
    "max_tokens": <MAX_TOKENS>,
    "temperature": 0
  }'
```

> **Prerequisites:**
> - `oc` CLI installed and logged in (`oc login ...`)
> - `curl` available in your terminal
> - The `-k` flag skips TLS certificate verification for the cluster self-signed wildcard cert

---

## Step 6 — Professional Inference Tests via Gateway (Live Results)

The prompts below were executed against the live cluster through the gateway and the
responses are the actual output captured from that run.

---

### 6a. tiny-llama-test (`deploy-models` namespace)

> **Model:** Lightweight instruction-following model (1.1 B parameters),
> MIG slice `nvidia.com/mig-2g.10gb`. Best suited for short, factual completions.
> Use `max_tokens: 120` or lower to match the slice size.
>
> **Gateway URL:** `https://openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com/deploy-models/tiny-llama-test/v1/`

#### Prompt 1 — OpenShift AI and KServe

```bash
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')

curl -sk -X POST "https://${GATEWAY_HOST}/deploy-models/tiny-llama-test/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tiny-llama-test",
    "messages": [{"role": "user", "content": "What is Red Hat OpenShift AI and what role does KServe play in it? Answer in two sentences."}],
    "max_tokens": 120,
    "temperature": 0
  }'
```

**Live output (captured from cluster):**

```json
{
  "id": "chatcmpl-594511d8-9fd9-4d30-a9ad-7cbce9ac160b",
  "object": "chat.completion",
  "created": 1782826686,
  "model": "tiny-llama-test",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Red Hat OpenShift AI is a container-based platform for building and deploying machine learning (ML) and deep learning (DL) applications. KServe is a Kubernetes service that provides a scalable and efficient way to deploy and manage machine learning models in OpenShift AI. KServe is designed to help developers and data scientists quickly and easily deploy and manage ML models in OpenShift AI, making it a key component of Red Hat OpenShift AI.",
        "reasoning": null
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 40,
    "completion_tokens": 99,
    "total_tokens": 139
  }
}
```

---

#### Prompt 2 — LLMInferenceService CR

```bash
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')

curl -sk -X POST "https://${GATEWAY_HOST}/deploy-models/tiny-llama-test/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tiny-llama-test",
    "messages": [{"role": "user", "content": "In one sentence, what is the purpose of an LLMInferenceService custom resource in OpenShift AI?"}],
    "max_tokens": 80,
    "temperature": 0
  }'
```

**Live output (captured from cluster):**

```json
{
  "id": "chatcmpl-85115dc6-4379-4444-b77e-6e95308b59f1",
  "object": "chat.completion",
  "created": 1782821641,
  "model": "tiny-llama-test",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "An LLMInferenceService custom resource in OpenShift AI is used to deploy and manage LLM inference services, which are used for natural language processing and other tasks.",
        "reasoning": null
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 39,
    "completion_tokens": 36,
    "total_tokens": 75
  }
}
```

---

#### Prompt 3 — NVIDIA MIG and GPU partitioning

```bash
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')

curl -sk -X POST "https://${GATEWAY_HOST}/deploy-models/tiny-llama-test/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tiny-llama-test",
    "messages": [{"role": "user", "content": "What is NVIDIA Multi-Instance GPU (MIG) and why is it useful for serving multiple LLMs on a single GPU in OpenShift AI? Answer in two sentences."}],
    "max_tokens": 120,
    "temperature": 0
  }'
```

**Live output (captured from cluster):**

```json
{
  "id": "chatcmpl-df266603-383f-48d4-9fc5-22ca1f5eadc3",
  "object": "chat.completion",
  "created": 1782821642,
  "model": "tiny-llama-test",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "NVIDIA Multi-Instance GPU (MIG) is a feature in NVIDIA GPUs that allows multiple GPUs to work together to serve multiple instances of the same application or service on a single GPU. This is useful for serving multiple LLMs on a single GPU in OpenShift AI, as it allows for efficient and parallel processing of the LLMs on a single GPU.",
        "reasoning": null
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 55,
    "completion_tokens": 113,
    "total_tokens": 168
  }
}
```

---

### 6b. gpt-oss-20b (`deploy-models` namespace)

> **Model:** 20 B parameter reasoning model, MIG slice `nvidia.com/mig-3g.20gb`.
> Produces a chain-of-thought `reasoning` field before the final `content`.
> Always use **`max_tokens: 400` or higher** — the reasoning pass consumes tokens
> before the final answer is written. If `content` is `null` and `finish_reason`
> is `"length"`, the reasoning phase exhausted the budget; increase `max_tokens`.
>
> **Gateway URL:** `https://openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com/deploy-models/gpt-oss-20b/v1/`

#### Prompt 1 — GitOps and model lifecycle

```bash
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')

curl -sk -X POST "https://${GATEWAY_HOST}/deploy-models/gpt-oss-20b/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "Explain how GitOps with ArgoCD can be used to manage the lifecycle of LLM inference services in Red Hat OpenShift AI. Cover deployment, versioning, and rollback in three concise bullet points."}],
    "max_tokens": 500,
    "temperature": 0
  }'
```

**Live output (captured from cluster):**

```json
{
  "id": "chatcmpl-76c6bac7-f481-4fa6-975e-d28f436080cf",
  "object": "chat.completion",
  "created": 1782821721,
  "model": "gpt-oss-20b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "reasoning": "We need to explain how GitOps with ArgoCD can manage lifecycle of LLM inference services in Red Hat OpenShift AI. Cover deployment, versioning, rollback in three concise bullet points.",
        "content": "- **Deployment** – ArgoCD watches a Git repo that holds the Helm/Kustomize manifests for the LLM inference service (container image, config maps, resource limits, etc.). On every commit, ArgoCD automatically syncs the desired state to the OpenShift AI cluster, spinning up the new inference pod with the updated model weights.\n\n- **Versioning** – Each commit or Git tag represents a specific model version. ArgoCD records the commit hash in the application status, so the cluster always runs the exact image and configuration tied to that tag, enabling reproducible, version-controlled deployments.\n\n- **Rollback** – If a new inference service fails or degrades performance, ArgoCD can instantly revert to the previous commit/tag (or any earlier commit) by re-applying the older manifests, restoring the prior model version and configuration with minimal downtime."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 108,
    "completion_tokens": 414,
    "total_tokens": 522
  }
}
```

---

#### Prompt 2 — vLLM decode-worker pod

```bash
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')

curl -sk -X POST "https://${GATEWAY_HOST}/deploy-models/gpt-oss-20b/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "In two sentences, what does a decode-worker pod do in a vLLM deployment on OpenShift AI?"}],
    "max_tokens": 400,
    "temperature": 0
  }'
```

**Live output (captured from cluster):**

```json
{
  "id": "chatcmpl-177471d3-f8dd-4274-90d0-703d93dd8f37",
  "object": "chat.completion",
  "created": 1782826709,
  "model": "gpt-oss-20b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "reasoning": "The user asks: \"In two sentences, what does a decode-worker pod do in a vLLM deployment on OpenShift AI?\" vLLM is a high-performance inference engine for LLMs. In OpenShift AI, decode-worker pods handle decoding of model outputs, performing token generation, and streaming responses.",
        "content": "In a vLLM deployment on OpenShift AI, a decode-worker pod receives the raw logits produced by the inference worker and applies the chosen decoding strategy (greedy, beam, sampling, etc.) to turn those logits into actual tokens. It then streams the generated tokens back to the client while managing token caching and ensuring efficient, low-latency decoding across concurrent requests."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 89,
    "completion_tokens": 344,
    "total_tokens": 433
  }
}
```

---

#### Prompt 3 — Observability: Time to First Token

```bash
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')

curl -sk -X POST "https://${GATEWAY_HOST}/deploy-models/gpt-oss-20b/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "In two sentences, explain what Time to First Token (TTFT) measures for an LLM inference service and how Prometheus is used to track it on OpenShift AI."}],
    "max_tokens": 400,
    "temperature": 0
  }'
```

**Live output (captured from cluster):**

```json
{
  "id": "chatcmpl-b6409554-6c41-47f0-a616-e7b8f651cf9c",
  "object": "chat.completion",
  "created": 1782821777,
  "model": "gpt-oss-20b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "reasoning": "We need to answer: In two sentences, explain what Time to First Token (TTFT) measures for an LLM inference service and how Prometheus is used to track it on OpenShift AI.",
        "content": "Time to First Token (TTFT) measures the latency from the moment an inference request reaches the LLM service until the first token is emitted back to the client, indicating how quickly the model begins generating output. In OpenShift AI, Prometheus scrapes this metric from the inference service's exporter, stores it, and the platform's dashboards and alerts query Prometheus to visualize and monitor TTFT in real time."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 102,
    "completion_tokens": 365,
    "total_tokens": 467
  }
}
```

---

## Validating the Response

Regardless of the prompt used, check these fields in every response:

| Field | Expected | Failure signal |
|---|---|---|
| HTTP status | `200 OK` | `4xx` / `5xx` — model not reachable or misconfigured |
| `choices[0].message.content` | Non-null, coherent string | `null` → `max_tokens` too low; raise it |
| `choices[0].finish_reason` | `"stop"` | `"length"` → response truncated; raise `max_tokens` |
| `usage.completion_tokens` | > 0 | `0` → model generated nothing |
| Response latency | < 30 s for short prompts | Timeout → workload pod not ready or GPU contention |

> **Reasoning model note (`gpt-oss-20b`):** The `choices[0].message.reasoning` field
> contains the internal chain-of-thought. This is expected and normal. The actionable
> answer is always in `choices[0].message.content`. A `content: null` with a non-empty
> `reasoning` means the model ran out of tokens during its thinking pass — increase
> `max_tokens` to 400+.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `content: null` + `finish_reason: "length"` | `max_tokens` exhausted by reasoning pass | Raise `max_tokens` to 400+ for `gpt-oss-20b` |
| `curl: (7) Failed to connect` | Gateway Route missing or pod not running | Verify Route: `oc get route openshift-ai-inference -n openshift-ingress` |
| `404 Not Found` from gateway | HTTPRoute not yet registered with Gateway | Check: `oc get httproute -n deploy-models`; check `HTTPRoutesReady` condition on CR |
| `502 Bad Gateway` | Gateway can't reach model Service / InferencePool not ready | Check `InferencePoolReady` condition; check pod status |
| `Ready: False` on CR | Workload still initialising | Wait; check `oc logs -n deploy-models <pod> --previous` |
| Pod stuck in `Pending` | GPU / MIG slice not available | `oc describe node \| grep -A5 nvidia` to check capacity |
| ArgoCD `OutOfSync` in prod | Manual-sync policy + no auto-sync | Expected in prod — sync manually during a change window |
| ArgoCD `OutOfSync` on Route labels | Two Applications share the Route — label drift | Expected — `ignoreDifferences` suppresses it |
| Route `spec.host` permission error | ArgoCD SA missing `routes/custom-host` RBAC | Apply: `oc apply -f deploy/gitops/maas-gitops-deployment/argocd-cluster-rbac.yaml` |

---

## Related

| Resource | Location |
|---|---|
| GitOps README | [`README.md`](README.md) |
| Helm chart README | [`../../helm/maas-model-deploy/README.md`](../../helm/maas-model-deploy/README.md) |
| ArgoCD RBAC | [`../maas-gitops-deployment/argocd-cluster-rbac.yaml`](../maas-gitops-deployment/argocd-cluster-rbac.yaml) |
| Gateway Route template | [`../../helm/maas-model-deploy/templates/gateway-route.yaml`](../../helm/maas-model-deploy/templates/gateway-route.yaml) |
| Dev Application | [`environments/dev/application.yaml`](environments/dev/application.yaml) |
| Staging Application | [`environments/staging/application.yaml`](environments/staging/application.yaml) |
| Prod Applications | [`environments/prod/`](environments/prod/) |
