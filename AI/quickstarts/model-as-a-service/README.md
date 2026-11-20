# Quickstart: Model as a Service (MaaS) on IBM Fusion HCI

Organizations adopting generative AI require a secure, scalable, high-performance, and governed platform to host foundation models within their private enterprise infrastructure. Running models on-premises with **IBM Storage Fusion** and **Red Hat OpenShift AI (RHOAI)** ensures complete data sovereignty, predictable inference latency, fine-grained access control, and hardware cost optimization.

This guide provides a comprehensive, enterprise-ready end-to-end walkthrough for deploying, serving, governing, and operating the Model-as-a-Service (MaaS) platform using **KServe `LLMInferenceService` (LLM-D)**, **Kuadrant Gateway API**, and **vLLM**. It supports automated script-based deployment, declarative GitOps (ArgoCD) multi-cluster workflows, Model Registry integration, API key governance, and a dedicated integration hub for **IBM Bob On-Premises**.

---

## Table of Contents

- [1. Architecture Overview](#1-architecture-overview)
  - [Key Technical Pillars](#key-technical-pillars)
- [2. Repository Structure & Mental Model](#2-repository-structure--mental-model)
  - [Immutable Code vs. Configuration Overlays](#immutable-code-vs-configuration-overlays)
- [3. Prerequisites & Environment Verification](#3-prerequisites--environment-verification)
  - [Required Tooling](#required-tooling)
  - [Hardware & Accelerators (NVIDIA & AMD)](#hardware--accelerators-nvidia--amd)
  - [Storage Classes & Secrets (IBM Fusion ODF, S3 & Vault/ESO)](#storage-classes--secrets-ibm-fusion-odf-s3--vaulteso)
  - [Air-Gapped / Disconnected Cluster Considerations](#air-gapped--disconnected-cluster-considerations)
- [4. End-to-End Walkthrough](#4-end-to-end-walkthrough)
  - [Step 1: Deploy & Upgrade the MaaS Platform Runtime](#step-1-deploy--upgrade-the-maas-platform-runtime)
  - [Step 2: Model Registry & Multi-Model Registration](#step-2-model-registry--multi-model-registration)
  - [Step 3: Deploy GPU Model Inference Services (LLM-D)](#step-3-deploy-gpu-model-inference-services-llm-d)
  - [Step 4: Authentication, API Keys & Governance](#step-4-authentication-api-keys--governance)
  - [Step 5: Validate Inference Endpoints (cURL & Python SDK)](#step-5-validate-inference-endpoints-curl--python-sdk)
- [5. Client Integrations & IBM Bob Hub](#5-client-integrations--ibm-bob-hub)
- [6. Operational Runbook & Health Checks](#6-operational-runbook--health-checks)
  - [Verification Matrix](#verification-matrix)
  - [Common Failure Modes & Quick Fixes](#common-failure-modes--quick-fixes)
- [7. Platform Cleanup & Teardown](#7-platform-cleanup--teardown)
- [8. Project Structure Reference](#8-project-structure-reference)

---

## 1. Architecture Overview

The IBM Storage Fusion MaaS platform brings together high-performance enterprise storage, declarative Kubernetes model serving, and AI Gateway traffic governance into a single cohesive architecture:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              IBM Storage Fusion — MaaS Platform                        │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│   CLIENT ACCESS LAYER                                                                  │
│   ┌───────────────────────────┐    ┌───────────────────────────┐                       │
│   │   IBM Bob On-Premises     │    │   Enterprise Applications │                       │
│   │   (VS Code / CLI / Agents)│    │   (Chatbots / SDKs / REST)│                       │
│   └─────────────┬─────────────┘    └─────────────┬─────────────┘                       │
│                 │                                │                                     │
│                 ▼ (Direct :8000 or HTTPS)        ▼ (HTTPS / Bearer Token)              │
│   INGRESS & GOVERNANCE LAYER (Kuadrant + Envoy Gateway)                                │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ OpenShift Route (TLS) → Gateway: maas-default-gateway (Port 443)                │   │
│   │                                                                                │   │
│   │ ┌───────────────────────────┐ ┌───────────────────────────┐ ┌────────────────┐│   │
│   │ │ Authorino (AuthPolicy)    │ │ Limitador (Rate Limiting) │ │ EnvoyFilter    ││   │
│   │ │ • MaaS API Key (sk-oai-*) │ │ • Tier Subscriptions      │ │ • Dynamic Route││   │
│   │ │ • Keycloak / RH-SSO OAuth │ │ • Token Quota Enforcement │ │ • Direct Proxy ││   │
│   │ └───────────────────────────┘ └───────────────────────────┘ └────────────────┘│   │
│   └──────────────────────────────────────┬─────────────────────────────────────────┘   │
│                                          │                                             │
│                                          ▼                                             │
│   DISTRIBUTED ORCHESTRATION LAYER (LLM-D / KServe Controller)                          │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ • LLMInferenceService Custom Resource                                          │   │
│   │ • LeaderWorkerSet (LWS) Gang Scheduling & Inter-node NCCL Ring                 │   │
│   │ • Automated Service Creation (<model>-kserve-workload-svc:8000)                │   │
│   └──────────────────────────────────────┬─────────────────────────────────────────┘   │
│                                          │                                             │
│                                          ▼                                             │
│   INFERENCE RUNTIME (vLLM Engine Pods in deploy-models-rhoai)                          │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ ┌──────────────────────────┐  ┌──────────────────────────┐ ┌─────────────────┐ │   │
│   │ │ NVIDIA Nemotron 3 Ultra  │  │ IBM Granite 3.1 8B       │ │ GPT-OSS 20B     │ │   │
│   │ │ (550B NVFP4, TP=4)       │  │ (OCI ModelCar, 1x GPU)   │ │ (S3 / PVC)      │ │   │
│   │ └──────────────────────────┘  └──────────────────────────┘ └─────────────────┘ │   │
│   └──────────────────────────────────────┬─────────────────────────────────────────┘   │
│                                          │                                             │
│                                          ▼                                             │
│   STORAGE & HARDWARE ACCELERATION (IBM Fusion Data Foundation + NVIDIA / AMD)          │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ • Fusion CephFS RWX PVCs (Multi-GPU model weights >50GB, NVMe caching)         │   │
│   │ • Fusion Ceph-RBD RWO PVCs (PostgreSQL Model Registry database)                │   │
│   │ • NooBaa / S3 Object Storage (Model weight staging and artifacts)              │   │
│   │ • NVIDIA GPUs (Blackwell RTX Pro 6000, H100, A100, L40S) & AMD MI300           │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### Key Technical Pillars

1. **vLLM Engine & PagedAttention:** High-throughput LLM serving engine managing KV-cache memory dynamically in fixed 16-token blocks, eliminating GPU memory fragmentation.
2. **LLM-D Distributed Orchestration:** Red Hat OpenShift AI's distributed model serving controller. It manages multi-GPU and multi-node models using Kubernetes **LeaderWorkerSet (LWS)**, ensuring gang scheduling and synchronized recovery across all GPU worker pods.
3. **Kuadrant AI Gateway & Authorino:** Envoy-based cloud-native gateway managing API keys, OpenShift service certificates, and Token Rate Limiting via **Limitador** and Redis.
4. **IBM Storage Fusion Data Foundation:** Enterprise NVMe-backed CephFS ReadWriteMany (RWX) storage allowing large model weights (>50GB) to be shared across distributed GPU nodes concurrently.
5. **OpenShift AI Model Registry:** Relational model catalog backed by PostgreSQL, managing model versions, metadata, and dashboard UI linking.

---

## 2. Repository Structure & Mental Model

This quickstart lives at `AI/quickstarts/model-as-a-service` in the [`IBM/storage-fusion`](https://github.com/IBM/storage-fusion) repository and is organized into independent, modular concerns:

```
AI/quickstarts/model-as-a-service/
├── README.md                                  # Enterprise master guide (this file)
├── ARCHITECTURE.md                            # Architecture diagrams, data flows & wave ordering
│
├── runtime/                                   # ── Deploy ONCE per cluster ────────────────────────
│   ├── README.md                              # Platform runtime installation guide
│   ├── charts/                                # Helm chart source (Operators, Platform, Gateway, Registry)
│   ├── config/                                # Deployment configuration (dev, staging, prod values & GitOps)
│   └── scripts/                               # install-runtime.sh, cleanup-runtime.sh, uninstall_rhoai.sh
│
├── models/                                    # ── Deploy ANY TIME, independently ─────────────────
│   ├── README.md                              # Model onboarding, registry & serving guide
│   ├── charts/                                # Generic model serving charts (maas-model-service)
│   ├── config/                                # Per-model Helm values (nemotron, granite, qwen, laguna, etc.)
│   └── scripts/                               # register-models.sh, deploy-model.sh
│
├── governance/                                # ── Managed by Platform Ops / Security ─────────────
│   ├── README.md                              # Multi-tenant subscriptions & rate limits guide
│   ├── charts/maas-config/                    # MaaSSubscription, MaaSAuthPolicy, Groups Helm chart
│   └── config/                                # Per-environment values (dev, staging, prod)
│
└── docs/                                      # ── Operational Runbooks & Reference Guides ────────
    ├── OPERATIONS.md                          # Health checks, metric endpoints & runbooks
    ├── SECRETS.md                             # Vault, External Secrets Operator & manual credentials
    ├── AIR_GAPPED.md                          # Disconnected cluster mirror and install guide
    ├── CONTRIBUTING.md                        # Guidelines for contributing new models or charts
    └── model-registry-ui-guide/               # OpenShift AI Dashboard UI step-by-step screenshots
```

### Immutable Code vs. Configuration Overlays

| Component | Responsibility | Change Cadence |
|---|---|---|
| **Helm Charts (`charts/`)** | Generic, parameter-driven Kubernetes templates. Standardized across all environments. | **Immutable / Released with platform** |
| **Configuration Overlays (`config/`)** | Environment values (`dev`, `staging`, `prod`) controlling replica counts, GPU sizing, and quotas. | **Customized per cluster / Promoted via GitOps** |

---

## 3. Prerequisites & Environment Verification

### Repository Setup & Working Directory
Clone the repository and change directory to the Model-as-a-Service quickstart root:

```bash
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/AI/quickstarts/model-as-a-service
```
> **Note:** All CLI commands, scripts (`./runtime/scripts/...`, `./models/scripts/...`), and Helm file paths in this guide assume you are operating from within `AI/quickstarts/model-as-a-service`.

### Required Tooling
Ensure your bastion or management workstation has the following installed:
- OpenShift CLI (`oc` v4.16+)
- Helm (`helm` v3.12+)
- Git (`git`)
- `curl`, `jq`, and Python 3 (with `requests` and `openai` libraries)

### Hardware & Accelerators (NVIDIA & AMD)
The MaaS platform natively supports both NVIDIA and AMD GPU acceleration:

```bash
# 1. Verify cluster connection
oc whoami
oc cluster-info

# 2. Check NVIDIA GPU nodes & allocatable capacity
oc get nodes -o custom-columns='NODE:.metadata.name,NVIDIA_GPUS:.status.allocatable.nvidia\.com/gpu'

# 3. Check AMD GPU nodes & allocatable capacity
oc get nodes -o custom-columns='NODE:.metadata.name,AMD_GPUS:.status.allocatable.amd\.com/gpu'

# 4. Verify Fusion StorageClasses
oc get storageclass
```
*Expected storage classes include `ocs-storagecluster-ceph-rbd` or `ocs-storagecluster-cephfs`.*

### Storage Classes & Secrets (IBM Fusion ODF, S3 & Vault/ESO)
- **CephFS RWX PVCs:** Used for storing multi-GPU models (>50GB) such as Nemotron 550B NVFP4.
- **External Secrets Operator (ESO / Vault):** For GitOps production deployments, manage database and registry credentials in HashiCorp Vault. See [`docs/SECRETS.md`](docs/SECRETS.md).

### Air-Gapped / Disconnected Cluster Considerations
For offline clusters where container images are mirrored via `ImageDigestMirrorSet` (IDMS):
1. **Pin Images by Digest:** IDMS does not rewrite mutable `:latest` tags. Override database and tooling images in `runtime/config/helm/<env>/` with explicit `@sha256:<digest>` hashes.
2. **Mirror Operator Catalogs:** Point `maas-operators` to your internal mirrored CatalogSource.
3. For full air-gapped procedures, see [`docs/AIR_GAPPED.md`](docs/AIR_GAPPED.md).

---

## 4. End-to-End Walkthrough

### Step 1: Deploy & Upgrade the MaaS Platform Runtime

Choose your preferred deployment method:

#### Option A: Automated Script (Quick Start & PoC)
The automated installation script [`runtime/scripts/install-runtime.sh`](runtime/scripts/install-runtime.sh) deploys all operators, platform configurations, and runtime resources idempotently:

```bash
# Deploy using the production environment overlay:
./runtime/scripts/install-runtime.sh -e prod

# (Or deploy dev overlay for minimal footprint: ./runtime/scripts/install-runtime.sh -e dev)
```

**What `install-runtime.sh` Executes:**
- **Phase 1 (Operators):** Installs RHOAI Operator, Kuadrant Operator, Authorino, Limitador, and LeaderWorkerSet.
- **Phase 2 (Platform & DSC):** Deploys DataScienceCluster (`default-dsc`), PostgreSQL backend, and SecretStores.
- **Phase 3 (Runtime & Gateway):** Deploys Envoy Gateway (`maas-default-gateway`), OpenShift Re-encrypt Route with Service-CA certificates, and Model Registry REST Service.
- **Phase 4 (Security Wiring):** Configures OpenShift Service-CA certificates on Authorino gRPC listener and binds RBAC.

#### Option B: Declarative GitOps with ArgoCD (Production)
For production environments managed via OpenShift GitOps:

```bash
# 1. Apply AppProject and root App-of-Apps
oc apply -f runtime/config/gitops/prod/appproject.yaml
oc apply -f runtime/config/gitops/prod/app-of-apps.yaml

# 2. ArgoCD synchronizes child applications in wave order:
#    Wave 1: 01-maas-operators-prod.yaml
#    Wave 2: 02-maas-platform-prod.yaml
#    Wave 3: 03-maas-runtime-prod.yaml
#    Wave 4: 04-model-registry-prod.yaml
```

#### Verify Platform Health
```bash
# Verify DSC is Ready
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}{"\n"}'
# Output: Ready

# Verify Gateway is Programmed
oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}{"\n"}'
# Output: True

# Verify Model Registry Service is Available
oc get modelregistries.modelregistry.opendatahub.io model-registry -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}'
# Output: True
```

---

### Step 2: Private AI Catalog & Model Registration

In an air-gapped or self-hosted deployment, models can be browsed in the OpenShift AI Catalog and registered into the Model Registry:

#### 2.1 Private Model Catalog (UI Discovery Feed)
To make your curated models discoverable in the OpenShift AI Catalog UI without external internet access:
1. In OpenShift AI Console, navigate to **Settings → Model resources and operations → AI catalog sources**.
2. Click **Add source** → select **Custom YAML Catalog (YAML file)**.
3. Upload or paste the schema from [`models/catalog/private-model-catalog.yaml`](models/catalog/private-model-catalog.yaml).
4. Models (Nemotron, Granite, GPT-OSS, Laguna) will immediately appear under **AI Hub → Models → Catalog** for user discovery. (See [docs/model-registry-ui-guide/MODEL_CATALOG_GUIDE.md](docs/model-registry-ui-guide/MODEL_CATALOG_GUIDE.md) for details).

#### 2.2 Model Registry (Governed Inventory)
Register your target foundation models into the RHOAI Kubeflow Model Registry:

##### Option A: Automated Script Registration (Recommended)
```bash
# Register a specific model values file:
./models/scripts/register-models.sh models/config/helm/nemotron-3-ultra-550b-nvfp4.yaml

# Or register all active platform models:
./models/scripts/register-models.sh --all
```

##### Option B: OpenShift AI Dashboard UI Registration
1. In OpenShift AI Console, navigate to **AI Hub → Models → Registry** (or click **Register model** directly from the Catalog card).
2. Fill in:
   - **Model Name:** `nemotron-ultra`
   - **Version Name:** `1.0.0`
   - **Source URI:** `s3://models/nemotron-3-ultra-550b-nvfp4/` (or `pvc://nemotron-model-weights-pvc/`)
3. Click **Register**. (See [docs/model-registry-ui-guide/ADDING_MODELS_TO_REGISTRY.md](docs/model-registry-ui-guide/ADDING_MODELS_TO_REGISTRY.md) for screenshots).

#### Verify Registered Models via CLI
```bash
TOKEN=$(oc whoami -t)
REGISTRY_HOST=$(oc get route model-registry-https -n rhoai-model-registries -o jsonpath='{.spec.host}')

curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${REGISTRY_HOST}/api/model_registry/v1alpha3/registered_models" | jq '.items[].name'
```

---

### Step 3: Deploy GPU Model Inference Services (LLM-D)

#### Option A: Helm / Script Serving Deployment (Production-Tuned)
Deploy foundation models using [`models/scripts/deploy-model.sh`](models/scripts/deploy-model.sh) and the standardized values files in `models/config/helm/`:

```bash
# Deploy NVIDIA Nemotron 3 Ultra 550B (CephFS RWX PVC, 4x Blackwell GPUs, TP=4)
./models/scripts/deploy-model.sh models/config/helm/nemotron-3-ultra-550b-nvfp4.yaml

# Deploy IBM Granite 3.1 8B Instruct (Red Hat OCI ModelCar, 1x GPU)
./models/scripts/deploy-model.sh models/config/helm/granite-3.1-8b.yaml

# Deploy GPT-OSS 20B (S3 / PVC, 2x GPUs)
./models/scripts/deploy-model.sh models/config/helm/gpt-oss-20b.yaml

# Deploy Laguna S2.1 (S3 Object Storage, 2x GPUs)
./models/scripts/deploy-model.sh models/config/helm/laguna-s2-1.yaml
```

#### Option B: OpenShift AI Dashboard (UI-Driven Deployment)
Customers who prefer a visual experience can deploy models directly through the OpenShift AI Web Console:
1. Navigate to **AI Hub → Models → Catalog** (or **Registry**).
2. Click on any model card (e.g. `IBM Granite 3.1 8B Instruct` or `NVIDIA Nemotron 3 Ultra`).
3. Click **Deploy**.
4. Configure the serving runtime (vLLM / KServe), select GPU hardware profile (e.g. `1x GPU` or `4x GPU`), and specify the model storage source (`s3://models/...` or PVC).
5. Click **Deploy Model** — OpenShift AI launches the inference pod into the selected data science project.

> **💡 Automated vs UI Deployments:**
> - **Automated Script/GitOps (`deploy-model.sh`):** Applies production-grade hardware tuning (Tensor Parallelism, NVFP4, MTP speculation, chunked prefill, and CephFS mounts) automatically.
> - **UI-Driven Deployment:** Empowers users to test custom models on their own without CLI dependencies while interacting with the self-hosted private catalog.

**Understanding the Model Specification (`models/config/helm/nemotron-3-ultra-550b-nvfp4.yaml`):**
```yaml
model:
  name: nemotron-ultra
  displayName: "NVIDIA Nemotron 3 Ultra 550B NVFP4"
  storageUri: "pvc://nemotron-model-weights-pvc/"

vllm:
  tensorParallelSize: 4
  maxModelLen: 262144
  gpuMemoryUtilization: 0.90
  additionalArgs:
    - "--speculative-model=nemotron_h_mtp"
    - "--mamba-ssm-backend=flashinfer"

resources:
  requests:
    nvidia.com/gpu: "4"
  limits:
    nvidia.com/gpu: "4"
```

#### Option B: Declarative GitOps Model Deployment (ArgoCD)
```bash
# Apply model application in production
oc apply -f models/config/gitops/prod/appproject.yaml
oc apply -f models/config/gitops/prod/applications/application-gpt-oss-20b.yaml
```

#### Monitor Model Readiness via CLI
```bash
# Check LLMInferenceService condition (READY=True)
oc get llminferenceservice -n deploy-models-rhoai

# Check the vLLM serving pods
oc get pods -n deploy-models-rhoai -l app.kubernetes.io/name=nemotron-ultra
```

---

### Step 4: Authentication, API Keys & Governance

#### Method A: Native MaaS API Keys & Quotas (Recommended)
Deploy multi-tenant governance policies (`MaaSSubscription` and `MaaSAuthPolicy`):

```bash
helm upgrade --install maas-governance ./governance/charts/maas-config \
  -n redhat-ai-gateway-infra \
  -f ./governance/config/helm/prod/values.yaml
```

Generate a MaaS API Key:
```bash
TOKEN=$(oc whoami -t)
MAAS_API_HOST=$(oc get route maas-api -n redhat-ai-gateway-infra -o jsonpath='{.spec.host}')

API_KEY=$(curl -sk -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"developer-key"}' \
  "https://${MAAS_API_HOST}/maas-api/v1/api-keys" | jq -r '.key')

echo "Generated MaaS API Key: ${API_KEY}"
```

#### Method B: Red Hat SSO / Keycloak (OAuth2 JWT)
For environments using OpenID Connect (OIDC) JWT tokens:
```bash
KEYCLOAK_HOST=$(oc get route keycloak -n keycloak -o jsonpath='{.spec.host}')

TOKEN=$(curl -sk -X POST "https://${KEYCLOAK_HOST}/auth/realms/maas/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=maas-client" \
  -d "client_secret=<secret>" | jq -r '.access_token')
```

---

### Step 5: Validate Inference Endpoints (cURL & Python SDK)

#### 1. List Available Models via Gateway
```bash
GATEWAY_HOST=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.host}')

curl -sk -H "Authorization: Bearer ${API_KEY}" \
  "https://${GATEWAY_HOST}/v1/models" | jq .
```

#### 2. Chat Completion Request (`/v1/chat/completions`)
```bash
curl -sk -X POST "https://${GATEWAY_HOST}/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nemotron-ultra",
    "messages": [
      {"role": "system", "content": "You are a helpful coding assistant on IBM Storage Fusion."},
      {"role": "user", "content": "Write a Kubernetes operator in Go."}
    ],
    "temperature": 0.2,
    "max_tokens": 200
  }' | jq .
```

#### 3. OpenAI Python SDK Integration
```python
import os
from openai import OpenAI

client = OpenAI(
    api_key=os.environ.get("API_KEY", "sk-oai-default"),
    base_url=f"https://{os.environ['GATEWAY_HOST']}/v1",
)

response = client.chat.completions.create(
    model="nemotron-ultra",
    messages=[{"role": "user", "content": "Hello from IBM Storage Fusion MaaS!"}],
)

print(response.choices[0].message.content)
```

---

## 5. Client Integrations & IBM Bob Hub

The MaaS platform exposes standard OpenAI-compatible endpoints (`/v1/chat/completions`, `/v1/models`) consumable by any enterprise application, SDK, LangChain/LlamaIndex pipeline, or developer assistant.

For a dedicated, end-to-end integration walkthrough for **IBM Bob On-Premises** (including pre-tuned Fusion model profiles, direct LLM-D in-cluster routing, automatic configuration generator, and verification diagnostics), see:

👉 [**IBM Bob On-Premises Integration Quickstart**](../bob-on-prem-for-fusion/README.md)

---

## 6. Operational Runbook & Health Checks

### Verification Matrix

| Component | Target Namespace | Health Check Command | Expected Healthy Output |
|---|---|---|---|
| **DataScienceCluster** | `redhat-ods-applications` | `oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'` | `Ready` |
| **Model Registry Service** | `rhoai-model-registries` | `oc get modelregistries.modelregistry.opendatahub.io model-registry -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'` | `True` |
| **Kuadrant Gateway** | `openshift-ingress` | `oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'` | `True` |
| **Authorino Service** | `openshift-operators` | `oc get authorino authorino -n openshift-operators -o jsonpath='{.status.ready}'` | `true` |
| **LLMInferenceService** | `deploy-models-rhoai` | `oc get llminferenceservice -n deploy-models-rhoai -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'` | `True` |
| **vLLM Engine Pods** | `deploy-models-rhoai` | `oc get pods -n deploy-models-rhoai -l app.kubernetes.io/name=nemotron-ultra -o jsonpath='{.items[*].status.containerStatuses[*].ready}'` | `true true (2/2)` |

### Common Failure Modes & Quick Fixes

1. **HTTP 500 / Authorino TLS Mismatch:**
   - *Cause:* Gateway connects to Authorino over gRPC TLS, but Authorino lacks OpenShift `service-ca` certificates.
   - *Fix:* Ensure `authorino-server-cert` secret is created and annotated with `service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert`.
2. **Model Pod in Pending / OOM CrashLoop:**
   - *Cause:* Insufficient GPU memory or oversized KV-cache.
   - *Fix:* Adjust `vllm.gpuMemoryUtilization: 0.85` or reduce `vllm.maxModelLen` in `models/config/helm/<model>.yaml`, then re-run `./models/scripts/deploy-model.sh`.

---

## 7. Platform Cleanup & Teardown

```bash
# 1. Delete a specific model
helm uninstall nemotron-ultra -n deploy-models-rhoai

# 2. Teardown MaaS platform runtime releases
./runtime/scripts/cleanup-runtime.sh

# 3. (Optional) Full operator uninstall
./runtime/scripts/uninstall_rhoai.sh
```

---

## 8. Project Structure Reference

```
AI/quickstarts/model-as-a-service/
├── README.md                                  # Enterprise master guide (this file)
├── ARCHITECTURE.md                            # Architecture diagrams, data flows & wave ordering
│
├── runtime/                                   # Platform Runtime (Deploy Once)
│   ├── README.md
│   ├── charts/
│   │   ├── maas-operators/                    # RHOAI, Kuadrant, LWS, cert-manager
│   │   ├── maas-platform/                     # DSC, PostgreSQL, SecretStores
│   │   ├── maas-runtime/                      # Gateway, OpenShift Route, RBAC, TLS
│   │   └── maas-model-registry/               # OpenShift AI Model Registry REST service
│   ├── config/
│   │   ├── helm/{dev,staging,prod}/           # Per-environment runtime values
│   │   └── gitops/{dev,staging,prod}/         # ArgoCD AppProjects & App-of-Apps
│   └── scripts/
│       ├── install-runtime.sh                 # One-command installer & rolling upgrader
│       ├── cleanup-runtime.sh                 # Runtime teardown script
│       └── uninstall_rhoai.sh                 # Operator cleanup utility
│
├── models/                                    # Model Serving & Lifecycle (Deploy Anytime)
│   ├── README.md
│   ├── charts/
│   │   ├── maas-model-service/                # Production LLMInferenceService + HTTPRoute
│   │   ├── maas-model-deploy/                 # Staging download pipeline chart
│   │   └── model-deploy-vllm-cpu/             # CPU-optimized vLLM serving
│   ├── config/
│   │   ├── helm/                              # Model values (nemotron, granite, gpt-oss, laguna, etc.)
│   │   └── gitops/{dev,staging,prod}/         # Per-model ArgoCD applications
│   └── scripts/
│       ├── register-models.sh                 # Model Registry API registration utility
│       └── deploy-model.sh                    # Automated model deployer with RHOAI validation
│
├── governance/                                # Multi-Tenant Governance & Access Control
│   ├── README.md
│   ├── charts/
│   │   └── maas-config/                       # MaaSSubscription, MaaSAuthPolicy, Groups chart
│   └── config/
│       ├── helm/{dev,staging,prod}/           # Per-environment governance values
│       └── gitops/{dev,staging,prod}/         # ArgoCD governance applications
│
└── docs/                                      # Operational Runbooks & Reference Guides
    ├── OPERATIONS.md                          # Health checks, metric endpoints & runbooks
    ├── SECRETS.md                             # Vault, External Secrets Operator & manual credentials
    ├── AIR_GAPPED.md                          # Disconnected cluster mirror and install guide
    ├── CONTRIBUTING.md                        # Guidelines for contributing new models or charts
    └── model-registry-ui-guide/               # OpenShift AI Dashboard UI step-by-step screenshots
```
