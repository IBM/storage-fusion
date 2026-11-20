# IBM Bob On-Premises & Openshift-AI LLM-D Integration Guide

This guide details how to connect **IBM Bob On-Premises** to high-performance foundation models served on **Red Hat OpenShift AI (RHOAI)** and **IBM Storage Fusion** using **KServe `LLMInferenceService` (LLM-D)**.

---

## Table of Contents

- [1. Architecture Topologies](#1-architecture-topologies)
  - [Topology A: Direct LLM-D Mode (Default / Low Latency)](#topology-a-direct-llm-d-mode-default--low-latency)
  - [Topology B: Governed Gateway Mode (Multi-Tenant & Metered)](#topology-b-governed-gateway-mode-multi-tenant--metered)
- [2. Pre-Tuned Model Profiles for IBM Storage Fusion](#2-pre-tuned-model-profiles-for-ibm-storage-fusion)
- [3. Prerequisites & Environment Verification](#3-prerequisites--environment-verification)
- [4. Step-by-Step Deployment Walkthrough](#4-step-by-step-deployment-walkthrough)
  - [Step 1: Deploy LLM-D Runtime (Once Per Cluster)](#step-1-deploy-llm-d-runtime-once-per-cluster)
  - [Step 2: Deploy Foundation Model on Storage Fusion](#step-2-deploy-foundation-model-on-storage-fusion)
  - [Step 3: Generate Bob Model Configuration](#step-3-generate-bob-model-configuration)
  - [Step 4: Apply Configuration to Bob Cluster](#step-4-apply-configuration-to-bob-cluster)
- [5. Verification & Health Checks](#5-verification--health-checks)
  - [6-Layer Automated Verification (`verify.sh`)](#6-layer-automated-verification-verifysh)
  - [End-to-End Chat & Tool Calling Test (`test-bob-e2e.sh`)](#end-to-end-chat--tool-calling-test-test-bob-e2esh)
- [6. Day-2 Operations: Hot Model Switching](#6-day-2-operations-hot-model-switching)
- [7. User Management & Client Setup (VS Code / JetBrains / CLI)](#7-user-management--client-setup-vs-code--jetbrains--cli)
- [8. Troubleshooting & FAQ](#8-troubleshooting--faq)

---

## 1. Architecture Topologies

IBM Bob On-Premises contains an embedded AI routing proxy called **Bifrost Gateway** that translates client requests from IDEs (VS Code, JetBrains) into OpenAI-compatible API calls directed to backend LLMs.

MaaS supports two distinct connectivity patterns for IBM Bob On-Premises:

### Topology A: Direct LLM-D Mode (Default / Low Latency)
*Recommended for co-located developer clusters and dedicated AI assistant nodes.*

```
┌────────────────────────────────────────────────────────┐    In-Cluster HTTP (:8000)    ┌───────────────────────────────────┐
│ IBM Bob On-Premises (Namespace: bob)                  │ ─────────────────────────────> │ <model>-kserve-workload-svc       │
│ ┌────────────────────────────────────────────────────┐ │                                │ (vLLM Engine Pods on NVIDIA GPUs) │
│ │ Bifrost Gateway (Embedded AI Router)               │ │                                └───────────────────────────────────┘
│ │ - Model Capability Aliases:                        │ │
│ │   • premium-ide  -> Nemotron 550B / Laguna         │ │
│ │   • fast         -> Granite 8B                     │ │
│ │   • security     -> Guardrail Engine               │ │
│ └────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```
- **Direct in-cluster routing:** Bob's internal Bifrost gateway connects directly to `http://<model>-kserve-workload-svc.<namespace>.svc.cluster.local:8000`.
- **Zero latency overhead:** Bypasses external ingress routes and proxy hops for maximum token streaming throughput.
- **Simplified footprint:** Disables Kuadrant, Authorino, Limitador, and gateway databases using [`values-llmd-only.yaml`](values-llmd-only.yaml).

---

### Topology B: Governed Gateway Mode (Multi-Tenant & Metered)
*Recommended for enterprise shared clusters requiring departmental budget enforcement.*

```
┌──────────────────────────────────────┐   HTTPS (:443) + API Key   ┌───────────────────┐   Proxy   ┌───────────────────┐
│ IBM Bob On-Premises                  │ ─────────────────────────> │ Kuadrant Gateway  │ ────────> │ LLM-D Model Pods  │
│ (Bifrost Gateway with Department Key)│                            │ (Authorino/Limit) │           │ (vLLM Engine)     │
└──────────────────────────────────────┘                            └───────────────────┘           └───────────────────┘
```
- **Governed ingress:** Bob's Bifrost gateway connects to `https://maas-default-gateway.apps.<cluster-domain>/v1` using an authorized API Key (`sk-oai-*`).
- **Quota enforcement:** Limitador tracks token usage and rate limits per department.

---

## 2. Pre-Tuned Model Profiles for IBM Storage Fusion

This repository provides pre-tuned, validated configurations for IBM Storage Fusion and NVIDIA hardware:

| Model | Sizing / Precision | Storage Backend | Hardware | vLLM Engine Optimizations | Best For |
|---|---|---|---|---|---|
| **NVIDIA Nemotron 3 Ultra** | 550B (NVFP4) | CephFS RWX PVC | 4x NVIDIA Blackwell / H100 | Multi-Token Prediction (`nemotron_h_mtp`), Mamba `flashinfer` backend, 262k context | Primary Developer Assistant (Complex code & reasoning) |
| **IBM Granite 3.1** | 8B Instruct | Red Hat OCI Registry | 1x NVIDIA GPU (A10G/L40S/H100) | Chunked prefill, FP16/BF16, fast startup | Fast inline autocomplete & lightweight chat |
| **Laguna S2.1** | 14B MoE | S3 Object Storage | 2x NVIDIA GPU | Triton MoE kernel, `dFlash` speculative decoding | Multi-file code refactoring & complex context |
| **GPT-OSS** | 20B Causal | S3 / HuggingFace | 2–4x NVIDIA GPU | Tensor Parallelism (TP=2/4), Prefix Caching | General conversational AI & tool-calling |
| **Mistral Medium 3.5** | 12B (FP8) | S3 / HuggingFace | 1–2x NVIDIA GPU | `Eagle` speculative decoding, FP8 KV-Cache | Guardrail & moderation model |

---

## 3. Prerequisites & Environment Verification

### Repository Setup & Working Directory
Clone the repository and change directory to this integration quickstart:

```bash
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/AI/quickstarts/bob-on-prem-for-fusion
```
> **Note:** All scripts (`./gen-model-config.sh`, `./verify.sh`, `./scripts/...`) and relative paths (e.g., `../model-as-a-service/...`) in this guide assume you are executing from inside `AI/quickstarts/bob-on-prem-for-fusion`.

### Cluster & Tooling Prerequisites
- **OpenShift Cluster:** 4.16+ with `cluster-admin` privileges.
- **GPU Accelerators:** NVIDIA GPU Operator installed (`oc get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'`).
- **Storage:** IBM Storage Fusion Data Foundation with `ocs-storagecluster-cephfs` or `ocs-storagecluster-ceph-rbd`.
- **IBM Bob On-Premises:** Installed and healthy (`oc get bob -A` shows `READY=True`).
- **Bob CLI:** `bobctl` utility available in your environment path.
- **Client Tools:** `helm` (v3.12+), `oc`, `curl`, and `jq`.

---

## 4. Step-by-Step Deployment Walkthrough

### Step 1: Deploy LLM-D Runtime (Once Per Cluster)

Deploy OpenShift AI KServe (`LLMInferenceService`), cert-manager, and LeaderWorkerSet while disabling non-essential gateway components using [`values-llmd-only.yaml`](values-llmd-only.yaml):

```bash
# 1. Install Operators
helm upgrade --install maas-operators ../model-as-a-service/runtime/charts/maas-operators \
  -n openshift-operators \
  -f ../model-as-a-service/runtime/config/helm/prod/operators-values.yaml \
  -f values-llmd-only.yaml --wait --timeout 20m

# 2. Deploy Platform (DataScienceCluster & LeaderWorkerSet)
helm upgrade --install maas-platform ../model-as-a-service/runtime/charts/maas-platform \
  -n rhoai-model-registries --create-namespace \
  -f ../model-as-a-service/runtime/config/helm/prod/platform-values.yaml \
  -f values-llmd-only.yaml --wait --timeout 20m

# 3. Deploy Model Registry (Kubeflow Model Registry instance + database for OpenShift AI UI)
helm upgrade --install maas-runtime ../model-as-a-service/runtime/charts/maas-runtime \
  -n rhoai-model-registries \
  -f ../model-as-a-service/runtime/config/helm/prod/runtime-values.yaml \
  -f values-llmd-only.yaml --wait --timeout 15m
```

Verify that the DataScienceCluster reaches `Ready`:
```bash
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}{"\n"}'
# Output: Ready
```

---

### Step 2: Register & Deploy Foundation Model on Storage Fusion

#### 2.1 Register Model into Model Registry
Register the model into the Model Registry using [`../model-as-a-service/models/scripts/register-models.sh`](../model-as-a-service/models/scripts/register-models.sh):

```bash
../model-as-a-service/models/scripts/register-models.sh ../model-as-a-service/models/config/helm/nemotron-3-ultra-550b-nvfp4.yaml
```

#### 2.2 Deploy Foundation Model
Deploy the registered model using [`../model-as-a-service/models/scripts/deploy-model.sh`](../model-as-a-service/models/scripts/deploy-model.sh):

```bash
../model-as-a-service/models/scripts/deploy-model.sh ../model-as-a-service/models/config/helm/nemotron-3-ultra-550b-nvfp4.yaml
```

Monitor model readiness:
```bash
oc get llminferenceservice -n deploy-models-rhoai -w
# Wait until READY=True
```

---

### Step 3: Generate Bob Model Configuration

IBM Bob relies on an internal component called **Bifrost** to route various IDE tasks (code completion, inline reasoning, security scans) to appropriate LLM backends via standard capability aliases (`premium-ide`, `fast`, `security`, `background`, `explorer`, `default`).

> **💡 Single Model vs Multi-Model Deployments:**
> - **Only 1 model deployed?** You **do not** need to deploy separate models for each capability. When targeting a single model (e.g., `nemotron-3-ultra-550b-nvfp4` or `granite-3.1-8b`), `gen-model-config.sh` automatically maps **all capability roles** to that single model endpoint. Bob is 100% operational with just one deployed model!
> - **Multi-Model tiering (Optional):** If you deploy multiple models (e.g. Laguna for coding and GPT-OSS for guardrails), pass `--guardrail <model>` to split roles across dedicated model endpoints.

The [`gen-model-config.sh`](gen-model-config.sh) script automatically inspects the model's Helm definition in `../model-as-a-service/models/config/helm/<model>.yaml`, extracts context windows (`max_input_tokens`, `max_output_tokens`), sets the in-cluster KServe endpoint URL (`http://<model>-kserve-workload-svc.<namespace>.svc.cluster.local:8000`), and formats the exact `config.yaml` schema expected by the Bob Operator:

```bash
# Generate config for a single model (maps all Bob capability roles to Nemotron):
./gen-model-config.sh nemotron-3-ultra-550b-nvfp4 --out /tmp/model-config.yaml
```

*To specify multi-model tiering (e.g., Laguna for primary reasoning + GPT-OSS for guardrails):*
```bash
./gen-model-config.sh laguna-s2-1 --guardrail gpt-oss-20b --out /tmp/model-config.yaml
```

---

### Step 4: Apply Configuration to Bob Cluster

Apply the generated configuration to the Bob cluster using `bobctl`:

```bash
# Run from your Bob installation directory:
bobctl update-model-config --model-config /tmp/model-config.yaml
```

> **How this works under the hood:**
> - `bobctl` validates the model configuration and pushes it to the `bob-inference-config` ConfigMap in namespace `bob`.
> - The Bob Operator immediately reloads the internal **Bifrost Gateway**, exposing your Fusion-hosted LLMs to all connected IDE clients (VS Code, JetBrains).
> - Always pass `--model-config /tmp/model-config.yaml` on subsequent `bobctl install/upgrade` runs to preserve these settings.

---

## 5. Verification & Health Checks

### 6-Layer Automated Verification (`verify.sh`)

Run the built-in diagnostic script:

```bash
BOB_NAMESPACE=<bob-namespace> ./verify.sh nemotron-3-ultra-550b-nvfp4
```

**Expected Healthy Diagnostic Output:**
```
============================================================
IBM Bob & LLM-D End-to-End Verification
Model: nemotron-3-ultra-550b-nvfp4
============================================================
[1/6] OpenShift AI Model Service  ... PASS (nemotron-kserve-workload-svc on port 8000)
[2/6] LLMInferenceService Status  ... PASS (Ready=True, model: nemotron-ultra)
[3/6] IBM Bob Bifrost Mode        ... PASS (Bifrost routing active)
[4/6] Bob Inference Health API    ... PASS (HTTP 200 OK)
[5/6] Model Registry Visibility   ... PASS (Registered model ID linked)
[6/6] Chat Completion (vLLM)     ... PASS (Streaming tokens received successfully)
============================================================
ALL CHECKS PASSED
============================================================
```

### End-to-End Chat & Tool Calling Test (`test-bob-e2e.sh`)

Validate live token streaming, context reasoning, and tool calling with the real Bob Shell:

```bash
./scripts/test-bob-e2e.sh <bob-namespace>
```

---

## 6. Day-2 Operations: Hot Model Switching

To switch Bob's active model without restarting Bob control plane components:

```bash
# 1. Deploy the new model (e.g. IBM Granite 3.1 8B)
../model-as-a-service/models/scripts/deploy-model.sh ../model-as-a-service/models/config/helm/granite-3.1-8b.yaml

# 2. Re-generate configuration
./gen-model-config.sh granite-3.1-8b --out /tmp/model-config.yaml

# 3. Apply the updated configuration
bobctl update-model-config --model-config /tmp/model-config.yaml

# 4. Verify the new model routing
BOB_NAMESPACE=<bob-namespace> ./verify.sh granite-3.1-8b
```

---

## 7. User Management & Client Setup (VS Code / JetBrains / CLI)

### 1. Create a User Login
```bash
./scripts/create-bob-user.sh <bob-ns> <email> <username> [--admin] --out user-credentials.txt
```

### 2. Connect Your IDE Plugin (Bob IDE / VS Code / JetBrains)

Refer to official documentation: [Accessing Bob self-hosted](https://bob.ibm.com/docs/ide/enterprise/on-premises/accessing).

1. Open **IBM Bob IDE** (or install the IBM Bob extension in VS Code).
2. Configure the Bob Gateway URL (in the **Bob Settings** tab under **Server URL**, or in `~/.bob/settings/settings.json`):
   ```json
   {
     "gatewayUrl": "https://api.bob.<bob-ns>.<apps-domain>",
     "session": {
       "model": "premium-ide"
     }
   }
   ```
3. **Configure CA Certificate Trust (On-Premises Clusters):**
   Enterprise on-premises OpenShift clusters use internal self-signed Ingress certificates. To allow Node.js / Bob IDE to trust the connection:
   * Export the certificate:
     ```bash
     oc get secret bob-external-tls -n <bob-ns> -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/.bob/bob-ca.crt
     ```
   * Add the certificate to your macOS Keychain (`sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/.bob/bob-ca.crt`) or set `"http.proxyStrictSSL": false` in Bob Settings.
4. Click **Log in to Bob** in the IDE and authenticate using your Keycloak / OpenShift credentials.

### 3. Configure CLI (Bob Shell)
```bash
# Trust the Bob External TLS Certificate
oc get secret bob-external-tls -n <bob-ns> -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/.bob/bob-ca.crt
export NODE_EXTRA_CA_CERTS=$HOME/.bob/bob-ca.crt

export BOB_GATEWAY_URL=https://api.bob.<bob-ns>.<apps-domain>
bob
```

---

## 8. Troubleshooting & FAQ

| Symptom / Error | Root Cause | Fix |
|---|---|---|
| `curl: (52) Empty reply from server` | RHOAI 3.5 enforces internal TLS on port 8000 by default | `values-llmd-only.yaml` sets `enableLLMInferenceServiceTLS: false` on KServe. |
| `Could not find model registry database pod` | Model YAML specifies `modelRegistry.enabled: true` without `maas-runtime` | Deploy `maas-runtime` in Step 1 (or set `modelRegistry.enabled: false`). |
| `max_tokens must be at least 1, got negative` | Model context window is smaller than Bob system instructions (~22k tokens) | Set `--max-model-len=32768` (or higher) in model YAML. |
| `prompt 2 failed` (tool calling) | vLLM started without tool parser flags | Ensure `--enable-auto-tool-choice` and `--tool-call-parser=openai` are in `extraArgs`. |
| `Sign in failed: fetch failed` | Self-signed ingress CA rejected by Node.js | Set `"http.proxyStrictSSL": false` in Bob Settings or import CA into keychain. |
| `HTTP 404 on /v1/v1/chat/completions` | Extra `/v1` in `base_url` | Bifrost appends `/v1` automatically. Regenerate config using `./gen-model-config.sh`. |
| `x-subscription-id header is required` | Bob Budget Metering active | Use `./scripts/test-bob-e2e.sh <bob-ns>` which auto-detects active Redis subscription IDs. |
| `Bob UI shows no models` | Model pod still loading weights | Models >20GB take several minutes to load weights into GPU RAM. Wait until `oc get llminferenceservice` shows `READY=True`. |

---

## 📁 Files in This Integration Hub

| File | Description |
|---|---|
| [`values-llmd-only.yaml`](values-llmd-only.yaml) | Lightweight Helm override disabling non-essential gateway components for direct LLM-D serving. |
| [`gen-model-config.sh`](gen-model-config.sh) | Generates `model-config.yaml` for `bobctl update-model-config`. |
| [`verify.sh`](verify.sh) | 6-layer diagnostic and verification tool. |
| [`scripts/test-bob-e2e.sh`](scripts/test-bob-e2e.sh) | End-to-end token generation & tool calling validation script. |
| [`scripts/verify-nemotron.sh`](scripts/verify-nemotron.sh) | Direct pod health and completion shortcut. |
| [`scripts/create-bob-user.sh`](scripts/create-bob-user.sh) | Bob user creation and credentials provisioning script. |
| [`scripts/lib.sh`](scripts/lib.sh) | Shared utility library for CLI diagnostics. |
