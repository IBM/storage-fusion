# Quickstart: Model as a Service (MaaS) on IBM Fusion

Organizations adopting generative AI require a secure, scalable, high-performance, and governed platform to host foundation models within their private enterprise infrastructure. Running models on-premises ensures complete data sovereignty, predictable inference latency, fine-grained access control, and cost optimization.

This guide provides a **comprehensive, single end-to-end walkthrough** for deploying and operating the **Model-as-a-Service (MaaS) v2 platform** on **IBM Fusion** with **Red Hat OpenShift AI (RHOAI 3.5.1)**, **Kuadrant Gateway API**, and **vLLM ModelCars**. It supports both **automated script-based** and **GitOps (ArgoCD)** deployment workflows, complete multi-model serving, API key governance, and a **dedicated integration section for IBM Bob On-Premises with the Bifrost AI Gateway**.

---

## Table of Contents

- [1. Architecture Overview](#1-architecture-overview)
- [2. Prerequisites & Environment Verification](#2-prerequisites--environment-verification)
  - [Hardware & Accelerators (NVIDIA & AMD)](#hardware--accelerators-nvidia--amd)
  - [Storage & Secret Management (ODF, S3 & Vault/ESO)](#storage--secret-management-odf-s3--vaulteso)
  - [Air-Gapped / Disconnected Cluster Considerations](#air-gapped--disconnected-cluster-considerations)
- [3. End-to-End Walkthrough](#3-end-to-end-walkthrough)
  - [Step 1: Deploy & Upgrade the MaaS Platform](#step-1-deploy--upgrade-the-maas-platform)
    - [Option A: Automated Script (Quick Start & PoC)](#option-a-automated-script-quick-start--poc)
    - [Option B: Declarative GitOps with ArgoCD (Production)](#option-b-declarative-gitops-with-argocd-production)
  - [Step 2: Model Registry & Multi-Model Registration](#step-2-model-registry--multi-model-registration)
    - [Option A: Automated Script Registration (Recommended)](#option-a-automated-script-registration-recommended)
    - [Option B: OpenShift AI Dashboard UI Registration](#option-b-openshift-ai-dashboard-ui-registration)
    - [Option C: GitOps-Based Model Registration](#option-c-gitops-based-model-registration)
  - [Step 3: Deploy GPU Model Inference Services](#step-3-deploy-gpu-model-inference-services)
    - [Option A: Helm / Script Serving Deployment](#option-a-helm--script-serving-deployment)
    - [Option B: GitOps Model Deployment (`maas-model-deploy`)](#option-b-gitops-model-deployment-maas-model-deploy)
  - [Step 4: Authentication, API Keys & Governance](#step-4-authentication-api-keys--governance)
    - [Method A: Native MaaS API Keys (`sk-oai-*`) [Recommended]](#method-a-native-maas-api-keys-sk-oai-recommended)
    - [Method B: Red Hat SSO / Keycloak (OAuth2 `client_credentials`)](#method-b-red-hat-sso--keycloak-oauth2-client_credentials)
  - [Step 5: Validate Inference Endpoints (cURL & Python SDK)](#step-5-validate-inference-endpoints-curl--python-sdk)
- [4. Dedicated Section: IBM Bob On-Premises & Bifrost Integration](#4-dedicated-section-ibm-bob-on-premises--bifrost-integration)
  - [4.1 Architecture & Ingress Routing](#41-architecture--ingress-routing)
  - [4.2 Gateway Routing Profiles (Plan B, Plan D, Plan C)](#42-gateway-routing-profiles-plan-b-plan-d-plan-c)
  - [4.3 Bob Installation & Secret Wiring](#43-bob-installation--secret-wiring)
  - [4.4 Developer Client Setup (VS Code / JetBrains / CLI)](#44-developer-client-setup-vs-code--jetbrains--cli)
  - [4.5 Day-2 Operations & Hot Model Switching](#45-day-2-operations--hot-model-switching)
- [5. Operational Runbook & Health Checks](#5-operational-runbook--health-checks)
- [6. Platform Cleanup & Teardown](#6-platform-cleanup--teardown)
- [7. Project Structure & Compatibility Guide](#7-project-structure--compatibility-guide)

---

## 1. Architecture Overview

The IBM Fusion MaaS platform brings together high-performance enterprise storage, declarative Kubernetes model serving, and AI Gateway traffic governance into a single cohesive architecture:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              IBM Fusion for AI — MaaS Platform                         │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│   CLIENT ACCESS LAYER                                                                  │
│   ┌───────────────────────────┐    ┌───────────────────────────┐                       │
│   │   IBM Bob On-Premises     │    │   Enterprise Applications │                       │
│   │   (VS Code / JetBrains)   │    │   (Agents / Chatbots / SDK)│                      │
│   └─────────────┬─────────────┘    └─────────────┬─────────────┘                       │
│                 │                                │                                     │
│                 ▼                                ▼                                     │
│   INGRESS & GOVERNANCE LAYER (Kuadrant + Envoy Gateway)                                │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ OpenShift Route (Re-encrypt TLS) → Gateway: openshift-ai-inference (Port 443)  │   │
│   │                                                                                │   │
│   │ ┌───────────────────────────┐ ┌───────────────────────────┐ ┌────────────────┐│   │
│   │ │ Authorino (AuthPolicy)    │ │ Limitador (Rate Limiting) │ │ EnvoyFilter    ││   │
│   │ │ • MaaS API Key (sk-oai-*) │ │ • Tier Subscriptions      │ │ • Dynamic Route││   │
│   │ │ • Keycloak / RH-SSO OAuth │ │ • Quota Enforcement       │ │ • KServe Direct││   │
│   │ └───────────────────────────┘ └───────────────────────────┘ └────────────────┘│   │
│   └──────────────────────────────────────┬─────────────────────────────────────────┘   │
│                                          │                                             │
│                                          ▼                                             │
│   MANAGEMENT & CONTROL PLANE                                                           │
│   ┌───────────────────────────┐    ┌───────────────────────────┐                       │
│   │ MaaS API Control Plane    │    │ RHOAI Model Registry      │                       │
│   │ (PostgreSQL, TenantConfig)│    │ (OCI ModelCar Registrations)                      │
│   └───────────────────────────┘    └───────────────────────────┘                       │
│                                          │                                             │
│                                          ▼                                             │
│   MODEL INFERENCE RUNTIME (RHOAI 3.5.1 + vLLM)                                         │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ Namespace: deploy-models-rhoai                                                 │   │
│   │                                                                                │   │
│   │ ┌──────────────────────────┐  ┌──────────────────────────┐ ┌─────────────────┐ │   │
│   │ │ gpt-oss-20b              │  │ poolside/Laguna-S-2.1    │ │ Nemotron-3-8B   │ │   │
│   │ │ (vLLM ModelCar, 1x GPU)  │  │ (Multi-GPU Distributed)  │ │ (vLLM, 1x GPU)  │ │   │
│   │ └──────────────────────────┘  └──────────────────────────┘ └─────────────────┘ │   │
│   └──────────────────────────────────────┬─────────────────────────────────────────┘   │
│                                          │                                             │
│                                          ▼                                             │
│   STORAGE & HARDWARE LAYER (IBM Fusion + NVIDIA / AMD)                                 │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ • Fusion Data Foundation / ODF StorageClasses (CephFS, RBD, Object Storage)    │   │
│   │ • NVIDIA / AMD GPU Acceleration (A100 / H100 / L40S / MI350)                   │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### Key Technical Pillars
1. **OCI ModelCar Packaging:** Model weights are packaged directly as container layers (`oci://registry.redhat.io/...`) and mounted via ephemeral containers, eliminating multi-gigabyte S3 downloads at pod startup.
2. **KServe LLMInferenceService:** Declarative Kubernetes resource managing vLLM runtime parameters, autoscaling, tensor parallelism, and health probes.
3. **Kuadrant AI Gateway & Authorino TLS:** Envoy-based Gateway API providing rate limiting, API token authentication, and path-based routing (`/deploy-models-rhoai/<model>/v1/*`).
4. **IBM Fusion Storage:** Enterprise-grade persistent volumes for Model Registry database storage, caching, and stateful workloads.

---

## 2. Prerequisites & Environment Verification

### Required Tooling
Ensure your bastion or management workstation has the following installed:
- OpenShift CLI (`oc` v4.16+)
- Helm (`helm` v3.12+)
- `curl`, `jq`, and `python3` (with `requests` and `openai` libraries)

### Hardware & Accelerators (NVIDIA & AMD)
The MaaS platform is vendor-neutral and natively supports both **NVIDIA** and **AMD** GPU acceleration:
- **NVIDIA GPU Nodes:** Managed via NVIDIA GPU Operator and Node Feature Discovery (NFD). Worker nodes are labeled with `nvidia.com/gpu.present=true`.
- **AMD GPU Nodes:** Managed via AMD GPU Operator, Kernel Module Management (KMM), and NFD. Worker nodes are labeled with `amd.com/gpu=true`.

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

Expected storage classes include `ocs-storagecluster-ceph-rbd` or `ocs-storagecluster-cephfs`.

### Storage & Secret Management (ODF, S3 & Vault/ESO)
1. **IBM Fusion Object Storage (ODF):** Buckets can be auto-provisioned via `ObjectBucketClaim` without manual credentials.
2. **External Secrets Operator (ESO / Vault):** For GitOps production deployments, keep database and storage credentials out of Git by managing them in HashiCorp Vault. See [`deploy/helm/maas-platform/VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md).

### Air-Gapped / Disconnected Cluster Considerations
For offline clusters where images are mirrored via `ImageDigestMirrorSet` (IDMS):

1. **Pin Images by Digest (No `:latest` tags):** IDMS does not rewrite mutable `:latest` tags. Override database and tooling images in your environment values file (`environments/<env>/values.yaml`):
   - **MaaS Database:** `maasDatabase.image: "registry.redhat.io/rhel9/postgresql-16@sha256:<digest>"`
   - **Model Registry DB:** `modelRegistry.database.internalDatabase.image: "registry.redhat.io/rhel9/postgresql-16@sha256:<digest>"`
   - **Tools Image:** `global.toolsImage: "<internal-registry>/openshift4/ose-cli@sha256:<digest>"`
2. **Mirror Catalogs & Channels (`maas-operators`):** Set `source` to your mirrored CatalogSource (e.g. `cs-redhat-operator-index-v4-20`) and `channel` to what is mirrored (e.g. `stable-3.x`) in `deploy/helm/maas-operators/environments/<env>/values.yaml`.
3. **Inference Images & Model Storage:**
   - In `models/<model>.yaml`, point `inference.image` to your internal registry mirror for vLLM.
   - If using S3 storage for model weights, set `s3.endpoint` and credentials to your accessible S3-compatible storage (e.g. internal ODF NooBaa, MinIO, Ceph, or enterprise S3).

---

## 3. End-to-End Walkthrough

### Step 1: Deploy & Upgrade the MaaS Platform

Choose your preferred deployment method:

#### Option A: Automated Script (Quick Start & PoC)
The automated installation script [`quickstarts/model-as-a-service/scripts/install-runtime.sh`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service/scripts/install-runtime.sh) deploys all operators, platform configurations, and runtime resources idempotently and handles zero-downtime upgrades.

The platform provides two configuration patterns:

##### 1. Environment-Specific Overlays (`dev` / `staging` / `prod`) [Recommended for Multi-Tier Clusters]
Each chart in `deploy/helm/` contains dedicated environment overlays:
- **`dev`:** Single-node non-HA setup for rapid development.
- **`staging`:** Pre-production validation topology.
- **`prod`:** Production-hardened settings (OpenShift Re-encrypt Route with `service-ca` CA certificates, dedicated GatewayClass, persistent PostgreSQL, strict Authorino gRPC TLS mTLS).

```bash
cd quickstarts/model-as-a-service

# Deploy or upgrade using the production environment overlay:
./scripts/install-runtime.sh -e prod

# (Or deploy dev/staging overlays: ./scripts/install-runtime.sh -e dev)
```

##### 2. Unified All-In-One Values [Recommended for Quick PoCs]
If you prefer a single file combining operator, platform, and runtime settings into one place:
```bash
# Deploy using the unified single-file values:
./scripts/install-runtime.sh examples/Fusion-Agentic-Assistance-Platform/values.yaml
```

**What `install-runtime.sh` Executes Across All Phases:**
1. **Phase 1 (Operators):** Installs RHOAI Operator (`3.5.1`), Kuadrant Operator (`v1.4.3`), Authorino, Limitador, and Gateway API CRDs with template lookup guards.
2. **Phase 2 (Platform & DSC):** Deploys `DataScienceCluster` (`default-dsc` in Headless mode with `aigateway=Managed` and `modelregistry=Managed`), PostgreSQL backend, and `MaasTenantConfig`.
3. **Phase 3 (Runtime & Gateway):** Deploys Envoy Gateway (`openshift-ai-inference`), OpenShift Re-encrypt Route with Service-CA certificates, and `ModelRegistry` in `rhoai-model-registries`.
4. **Phase 4 (Security Wiring & Authorino TLS):** Configures OpenShift Service-CA certificates on Authorino gRPC listener (`authorino-server-cert`), copies `maas-db-config` secret to `redhat-ai-gateway-infra`, and binds `rhods-admins` RBAC.

#### Option B: Declarative GitOps with ArgoCD (Production)
For production environments managed via OpenShift GitOps (ArgoCD):

1. **Deploy the AppProject:**
   ```bash
   oc apply -f deploy/gitops/maas-gitops-deployment/environments/prod/appproject-prod.yaml
   ```
2. **Deploy the App-of-Apps:**
   ```bash
   oc apply -f deploy/gitops/maas-gitops-deployment/environments/prod/00-prod-app-of-apps.yaml
   ```
3. **Synchronize Child Applications in Order:**
   ```bash
   argocd app sync fusion-maas-operators-prod --prune
   argocd app sync fusion-maas-platform-config-prod --prune
   argocd app sync fusion-maas-runtime-prod --prune
   ```

#### Verify Platform Health
```bash
# Verify DSC is Ready
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}{"\n"}'
# Output: Ready

# Verify Gateway is Programmed
oc get gateway openshift-ai-inference -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}{"\n"}'
# Output: True

# Verify Model Registry instance is Available (created by fusion-maas-runtime-prod)
oc get modelregistries.modelregistry.opendatahub.io model-registry -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}'
# Output: True
```

---

### Step 2: Model Registry & Multi-Model Registration

Register your target foundation models into the RHOAI Model Registry:

#### Option A: Automated Script Registration (Recommended)
```bash
./scripts/register-models.sh
```
Registers `gpt-oss-20b` (v1.0), `laguna-s2-1` (v1.0), and `nemotron-3` (v1.0) with OCI ModelCar URIs.

#### Option B: OpenShift AI Dashboard UI Registration
1. In OpenShift AI Console, navigate to **Models and Model Serving** → **Model Catalog**.
2. Search for your desired model (e.g., `gpt-oss-20b`).
3. Click **Register Model** and fill in:
   - **Model Name:** `gpt-oss-20b`
   - **Version Name:** `v1.0`
   - **Model Registry:** `default-modelregistry`
   - **Source URI:** `oci://registry.redhat.io/rhelai1/modelcar-gpt-oss-20b:latest`
4. Click **Register**.

#### Option C: GitOps-Based Model Registration
Deploy the automated model registry reconciler application. For the full walkthrough, see [`QUICKSTART.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service/deploy/gitops/model-registry-gitops/docs/QUICKSTART.md).

1. Apply the AppProject, then the Application:
   ```bash
   oc apply -f deploy/gitops/model-registry-gitops/argocd/environments/prod/appproject-prod.yaml
   oc apply -f deploy/gitops/model-registry-gitops/argocd/environments/prod/application.yaml
   ```
2. Sync the Application. Production does not auto-sync, and the first sync creates the `fusion-model-registry-gitops-prod` namespace:
   ```bash
   argocd app sync fusion-model-registry-gitops-prod
   ```
3. Create the `git-credentials` secret in that namespace. The reconciler image build clones the repository with it, so it is required when the repository is private:
   ```bash
   oc create secret generic git-credentials \
     -n fusion-model-registry-gitops-prod \
     --type=kubernetes.io/basic-auth \
     --from-literal=username=<git-username> \
     --from-literal=password=<personal-access-token>
   ```
   Use a token with read access to the repository, and do not commit the secret to Git. For production, you can manage it with External Secrets Operator instead; see [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md).
4. Wait for the build and the reconciler to start. The build waits for the secret and continues once it exists:
   ```bash
   oc get builds -n fusion-model-registry-gitops-prod -w
   oc get pods -n fusion-model-registry-gitops-prod
   ```
   If the build was started before the secret existed and does not proceed, start it manually:
   ```bash
   oc start-build model-reconciler -n fusion-model-registry-gitops-prod
   ```
   If the reconciler pod stays in `ImagePullBackOff` after the build succeeds, delete the pod so the Deployment recreates it:
   ```bash
   oc delete pod -n fusion-model-registry-gitops-prod -l component=reconciler
   ```

#### Verify Registered Models
```bash
TOKEN=$(oc whoami -t)
REGISTRY_HOST=$(oc get route model-registry-https -n rhoai-model-registries -o jsonpath='{.spec.host}')

curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${REGISTRY_HOST}/api/model_registry/v1alpha3/registered_models" | jq '.items[].name'
```

---

### Step 3: Deploy GPU Model Inference Services

#### Option A: Helm / Script Serving Deployment
Deploy foundation models using [`quickstarts/model-as-a-service/scripts/deploy-model.sh`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service/scripts/deploy-model.sh) and the standardized values files in [`models/`](https://github.com/IBM/storage-fusion/tree/master/AI/quickstarts/model-as-a-service/models):

```bash
# Deploy GPT-OSS 20B (Standard Single-GPU Model)
./scripts/deploy-model.sh models/gpt-oss-20b.yaml

# Deploy Laguna S2.1 (Multi-GPU Distributed Model)
./scripts/deploy-model.sh models/laguna-s2-1.yaml

# Deploy Nemotron 3 8B (High Throughput Agentic Model)
./scripts/deploy-model.sh models/nemotron-3-8b.yaml
```

#### Understanding the Model Serving Specification (`models/gpt-oss-20b.yaml`):
```yaml
accelerator:
  vendor: nvidia                  # 'nvidia' (nvidia.com/gpu) or 'amd' (amd.com/gpu)

model:
  name: gpt-oss-20b-version-1
  displayName: "GPT-OSS 20B (Standard Serving)"
  namespace: deploy-models-rhoai

modelRegistry:
  enabled: true
  name: default-modelregistry
  namespace: rhoai-model-registries
  registeredModelName: "gpt-oss-20b"

inference:
  engine: vllm
  image: registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.3.0
  replicas: 1
  env:
    - name: VLLM_ADDITIONAL_ARGS
      value: "--max-model-len=8192 --gpu-memory-utilization=0.90 --trust-remote-code --dtype=bfloat16"

resources:
  limits:
    cpu: "8"
    memory: 32Gi
    nvidia.com/gpu: "1"
  requests:
    cpu: "4"
    memory: 16Gi
    nvidia.com/gpu: "1"
```

#### Option B: Declarative GitOps Model Deployment (`maas-model-deploy`)
For enterprise environments using Red Hat OpenShift GitOps (ArgoCD):
1. Place your model values in Git (`deploy/helm/maas-model-deploy/environments/prod/values-<model>.yaml`). Set `s3.bucket`, `s3.region` and `wildcardDomain` for your cluster.
2. If you set `s3.createSecrets: false` (for example when External Secrets is not available), create the S3 connection secrets in the `deploy-models` namespace **before** syncing, otherwise the `LLMInferenceService` webhook rejects the resource:
   - `deploy-models-connection`: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `AWS_S3_BUCKET`, `AWS_S3_ENDPOINT`, plus the KServe/ODH connection annotations.
   - `storage-config`: the KServe storage JSON.
3. Deploy or synchronize the model serving ArgoCD application:
   ```bash
   oc apply -f deploy/gitops/maas-model-deploy/environments/prod/application-gpt-oss-20b.yaml
   argocd app sync fusion-maas-model-deploy-prod-gpt-oss-20b
   ```
4. ArgoCD continuously reconciles the `LLMInferenceService` and `MaaSModelRef` custom resources from Git. The prod Application deploys into the **`deploy-models`** namespace.

   > **Note:** `maasModelRef.enabled: true` (default) attaches MaaS auth enforcement to the gateway — all inference traffic is denied until a `MaaSSubscription` exists (Step 4). Set `maasModelRef.enabled: false` if you want the model reachable through the gateway without a subscription.

#### Option C: Monitoring & Managing Models via OpenShift AI Web Console UI
Platform administrators and data scientists can manage and inspect models directly via the Red Hat OpenShift AI Web Console:
1. **Model Catalog & Registry:** Navigate to **Models and Model Serving** → **Model Registry** to view registered models, versions, and OCI artifacts.
2. **Data Science Projects & Deployments:** Navigate to **Data Science Projects** → **`deploy-models-rhoai`** → **Models** to view live serving endpoints, status (`Ready`), and allocated accelerator hardware (NVIDIA/AMD GPUs).
3. **Metrics & Telemetry:** Select any deployed model to inspect live inference graphs (requests per second, token throughput, time to first token, and GPU VRAM utilization).

#### Monitor Model Readiness via CLI
Use `deploy-models-rhoai` for Option A (Helm script) or `deploy-models` for Option B (GitOps).
```bash
NS=deploy-models   # or deploy-models-rhoai for Option A

# Check LLMInferenceService condition
oc get llminferenceservice -n ${NS}

# Check the vLLM serving pod and router-scheduler pod (both carry this label)
oc get pods -n ${NS} -l app.kubernetes.io/name=gpt-oss-20b

# Check MaaS registration (Option B)
oc get maasmodelref -n ${NS}
```

---

### Step 4: Authentication, API Keys & Governance

#### Method A: Native MaaS API Keys (`sk-oai-*`) [Recommended]

1. **Apply Governance Subscription and AuthPolicy:**
   ```bash
   oc apply -f - <<'EOF'
   apiVersion: maas.opendatahub.io/v1alpha1
   kind: MaaSSubscription
   metadata:
     name: maas-sub-all-models
     namespace: redhat-ai-gateway-infra
   spec:
     tier: premium
     models:
       - gpt-oss-20b-version-1
       - laguna-s2-1-version-1
       - nemotron-3-version-1
     rateLimit:
       requestsPerMinute: 1200
   ---
   apiVersion: kuadrant.io/v1beta2
   kind: AuthPolicy
   metadata:
     name: maas-auth-policy
     namespace: openshift-ingress
   spec:
     targetRef:
       group: gateway.networking.k8s.io
       kind: Gateway
       name: openshift-ai-inference
     rules:
       authentication:
         "api-key-auth":
           apiKey:
             selector:
               matchLabels:
                 authorino.kuadrant.io/managed-by: authorino
             allTokens: true
   EOF
   ```

2. **Issue an API Key via MaaS API:**
   ```bash
   TOKEN=$(oc whoami -t)
   MAAS_API_HOST=$(oc get route maas-api -n redhat-ai-gateway-infra -o jsonpath='{.spec.host}')

   API_KEY=$(curl -sk -X POST \
     -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{"name":"bob-developer-key"}' \
     "https://${MAAS_API_HOST}/maas-api/v1/api-keys" | jq -r '.key')

   echo "Generated MaaS API Key: ${API_KEY}"
   ```

#### Method B: Red Hat SSO / Keycloak (OAuth2 `client_credentials`)
For enterprise environments using OpenID Connect (OIDC) JWT tokens, authenticate against Red Hat SSO:
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
GATEWAY_HOST=$(oc get route maas-default-gateway-route -n openshift-ingress -o jsonpath='{.spec.host}')

curl -sk -H "Authorization: Bearer ${API_KEY}" \
  "https://${GATEWAY_HOST}/deploy-models-rhoai/gpt-oss-20b-version-1/v1/models" | jq .
```

#### 2. Chat Completion Request (`/v1/chat/completions`)
```bash
curl -sk -X POST "https://${GATEWAY_HOST}/deploy-models-rhoai/gpt-oss-20b-version-1/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [
      {"role": "system", "content": "You are a helpful coding assistant on IBM Fusion."},
      {"role": "user", "content": "Write a Python function to check if a Kubernetes pod is healthy."}
    ],
    "temperature": 0.2,
    "max_tokens": 150
  }' | jq .
```

#### 3. OpenAI Python SDK Integration
```python
import os
from openai import OpenAI

client = OpenAI(
    api_key=os.environ["API_KEY"],
    base_url=f"https://{os.environ['GATEWAY_HOST']}/deploy-models-rhoai/gpt-oss-20b-version-1/v1",
)

response = client.chat.completions.create(
    model="gpt-oss-20b",
    messages=[{"role": "user", "content": "Hello from IBM Fusion MaaS!"}],
)

print(response.choices[0].message.content)
```

---

## 4. Dedicated Section: IBM Bob On-Premises & Bifrost Integration

IBM Bob On-Premises uses the **Bifrost AI Gateway** to route code completion, chat, agentic reasoning, and guardrail verification requests to on-premise foundation models running on MaaS.

### 4.1 Architecture & Ingress Routing

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        IBM Bob On-Premises ↔ MaaS Architecture                         │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│   DEVELOPER WORKSTATION                                                                │
│   ┌────────────────────────────────────────────────────────┐                           │
│   │ IBM Bob VS Code / JetBrains Plugin                     │                           │
│   │ Endpoint: https://bob.apps.<cluster-domain>            │                           │
│   └───────────────────────────┬────────────────────────────┘                           │
│                               │ HTTPS / OAuth / API Key                                │
│                               ▼                                                        │
│   BOB ON-PREMISES CLUSTER (Namespace: bob-enterprise)                                  │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ Bob Enterprise Control Plane                                                   │   │
│   │                                                                                │   │
│   │ ┌────────────────────────────────────────────────────────────────────────────┐ │   │
│   │ │ Bifrost AI Gateway (model-gateway-config.yaml)                             │ │   │
│   │ │                                                                            │ │   │
│   │ │ • Code Completion Route  ─────────► MaaS: gpt-oss-20b / Laguna S2.1        │ │   │
│   │ │ • Chat & Agentic Route   ─────────► MaaS: gpt-oss-20b / Nemotron 3         │ │   │
│   │ │ • Guardrail Audit Route  ─────────► MaaS: gpt-oss-20b                      │ │   │
│   │ │ • Secret: maas-bearer-token (Injected into Authorization header)           │ │   │
│   │ └────────────────────────────────────────────────────────────────────────────┘ │   │
│   └───────────────────────────────────┬────────────────────────────────────────────┘   │
│                                       │ Secure HTTPS (Internal / Re-encrypt)           │
│                                       ▼                                                │
│   MAAS PLATFORM ON IBM FUSION                                                          │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ Kuadrant Envoy Gateway → vLLM (deploy-models-rhoai)                            │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Gateway Routing Profiles (Plan B, Plan D, Plan C)

| Profile | Primary Inference Model | Guardrail Model | GPU Footprint | Best For |
|---|---|---|---|---|
| **Plan B-Remote (Recommended)** | `gpt-oss-20b` | `gpt-oss-20b` | 1x A100/H100 (Single GPU) | Standard enterprise coding & chat assistant |
| **Plan D-Remote** | `poolside/Laguna-S-2.1` | `gpt-oss-20b` | Multi-GPU Distributed | Advanced reasoning, massive context & multi-file coding |
| **Plan C-Remote** | `nvidia/Nemotron-3-8B` | `gpt-oss-20b` | 2x Single GPU | High-throughput agentic workflows & low latency |

#### Configuration: Plan B-Remote (`model-gateway-config.yaml`)
```yaml
gateways:
  - id: maas-gateway
    name: "IBM Fusion MaaS Gateway"
    type: openai-compatible
    baseUrl: "https://maas-default-gateway-route-openshift-ingress.apps.f32l007.fusion.tadn.ibm.com"
    auth:
      type: bearer
      secretRef:
        name: maas-bearer-token
        key: token
    tls:
      insecureSkipVerify: false
      caCertConfigMap:
        name: openshift-service-ca
        key: service-ca.crt

models:
  - id: gpt-oss-20b
    name: "GPT-OSS 20B (MaaS)"
    gatewayId: maas-gateway
    path: "/deploy-models-rhoai/gpt-oss-20b-version-1/v1"
    capabilities:
      - chat
      - code-completion
      - agent-planning
    contextWindow: 8192
    maxOutputTokens: 4096

  - id: gpt-oss-20b-guardrail
    name: "GPT-OSS 20B Guardrail"
    gatewayId: maas-gateway
    path: "/deploy-models-rhoai/gpt-oss-20b-version-1/v1"
    capabilities:
      - moderation
      - guardrail
    contextWindow: 4096
    maxOutputTokens: 512

routing:
  defaultChatModel: gpt-oss-20b
  defaultCompletionModel: gpt-oss-20b
  guardrailModel: gpt-oss-20b-guardrail
```

---

### 4.3 Bob Installation & Secret Wiring

```bash
# 1. Create Bob namespace
oc create namespace bob-enterprise --dry-run=client -o yaml | oc apply -f -

# 2. Inject MaaS Token Secret into bob-enterprise
oc create secret generic maas-bearer-token \
  -n bob-enterprise \
  --from-literal=token="${API_KEY}" \
  --dry-run=client -o yaml | oc apply -f -

# 3. Apply Bifrost Gateway ConfigMap
oc create configmap model-gateway-config \
  -n bob-enterprise \
  --from-file=config.yaml=model-gateway-config.yaml \
  --dry-run=client -o yaml | oc apply -f -

# 4. Restart Bob services to reload configuration
oc rollout restart deployment/bifrost-gateway -n bob-enterprise
oc rollout restart deployment/bob-backend -n bob-enterprise
```

---

### 4.4 Developer Client Setup (VS Code / JetBrains / CLI)

1. **Install Extension:** Install **IBM Bob** in VS Code or JetBrains.
2. **Configure IDE Settings (`settings.json`):**
   ```json
   {
     "bob.serverUrl": "https://bob.apps.f32l007.fusion.tadn.ibm.com",
     "bob.authProvider": "openshift-oauth",
     "bob.model": "gpt-oss-20b",
     "bob.enableInlineCompletion": true,
     "bob.enableStreaming": true,
     "bob.tls.customCAs": ["/path/to/openshift-service-ca.crt"]
   }
   ```
3. **Log In:** Execute `Bob: Login` in the IDE Command Palette to authenticate and start coding.

---

### 4.5 Day-2 Operations & Hot Model Switching

To switch Bob's backend model (e.g. from `gpt-oss-20b` to `laguna-s2-1`) without downtime:
1. Deploy the new model using `./scripts/deploy-model.sh models/laguna-s2-1.yaml`.
2. Update `model-gateway-config.yaml` with the new model path (`/deploy-models-rhoai/laguna-s2-1-version-1/v1`).
3. Re-apply the ConfigMap and trigger a rolling reload:
   ```bash
   oc create configmap model-gateway-config -n bob-enterprise --from-file=config.yaml=model-gateway-config.yaml -o yaml --dry-run=client | oc apply -f -
   oc rollout restart deployment/bifrost-gateway -n bob-enterprise
   ```

---

## 5. Operational Runbook & Health Checks

### Comprehensive Verification Matrix

| Component | Target Namespace | Health Check Command | Expected Healthy Output |
|---|---|---|---|
| **DataScienceCluster** | `redhat-ods-applications` | `oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'` | `Ready` |
| **Model Registry** | `rhoai-model-registries` | `oc get modelregistries.modelregistry.opendatahub.io model-registry -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'` | `True` |
| **Envoy Gateway** | `openshift-ingress` | `oc get gateway openshift-ai-inference -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'` | `True` |
| **Authorino Service** | `openshift-operators` | `oc get authorino authorino -o jsonpath='{.status.ready}'` | `true` |
| **vLLM Inference Service** | `deploy-models-rhoai` | `oc get llminferenceservice -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'` | `True` |
| **vLLM Engine Pod** | `deploy-models-rhoai` | `oc get pods -l app.kubernetes.io/name=gpt-oss-20b -o jsonpath='{.items[*].status.containerStatuses[*].ready}'` | `true true` (2/2) |

---

### Common Failure Modes & Quick Fixes

#### 1. Ingress Returns `HTTP 500 Internal Server Error` (Authorino TLS Mismatch)
- **Root Cause:** Gateway EnvoyFilter connects to Authorino over gRPC TLS, but Authorino is running without service-ca certificates.
- **Fix:**
  ```bash
  oc annotate service authorino-authorino-authorization -n openshift-operators service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert --overwrite
  oc patch authorino authorino -n openshift-operators --type=merge --patch '{"spec":{"listener":{"tls":{"enabled":true,"certSecretRef":{"name":"authorino-server-cert"}}}}}'
  oc rollout restart deployment/authorino -n openshift-operators
  oc rollout restart deployment/maas-default-gateway-data-science-gateway-class -n openshift-ingress
  ```

#### 2. Model Pod in `Pending` or `CrashLoopBackOff` (GPU / Memory Pressure)
- **Fix:** Lower `--gpu-memory-utilization` down to `0.85` or enable `--cpu-offload-gb=4` in model values file, then re-run `./scripts/deploy-model.sh`.

---

## 6. Platform Cleanup & Teardown

```bash
# 1. Delete a specific model
helm uninstall gpt-oss-20b -n deploy-models-rhoai

# 2. Clean teardown of MaaS platform releases
./scripts/cleanup-runtime.sh
```

---

## 7. Project Structure & Compatibility Guide

```
quickstarts/model-as-a-service/
├── README.md                                      # ← Single complete walkthrough & quickstart (this file)
│
├── models/                                        # 🎯 Standard Generic Model Catalog (Canonical)
│   ├── README.md                                  # Model catalog guide & parameter reference
│   ├── gpt-oss-20b.yaml                           # GPT-OSS-20B (1x GPU — Bob / General)
│   ├── laguna-s2-1.yaml                           # Laguna S2.1 (Multi-GPU Distributed)
│   ├── nemotron-3-8b.yaml                         # Nemotron-3 8B (High Throughput Agentic)
│   ├── granite-3.1-8b.yaml                        # IBM Granite 3.1 8B Instruct
│   └── qwen3-8b-fp8.yaml                          # Qwen FP8 Dynamic Quantized
│
├── scripts/                                       # ⚡ Standard Automation & Operational Tooling
│   ├── install-runtime.sh                         # Platform installer & zero-downtime upgrader
│   ├── register-models.sh                         # Model Registry automated multi-model registration
│   ├── deploy-model.sh                            # Model serving deployment & readiness watcher
│   └── cleanup-runtime.sh                         # Platform teardown utility
│
├── deploy/helm/                                   # 📦 Core Helm Charts
│   ├── maas-operators/                            # Phase 1: RHOAI, Kuadrant & CRDs
│   ├── maas-platform/                             # Phase 2: DataScienceCluster & PostgreSQL
│   ├── maas-runtime/                              # Phase 3: Gateways, Model Registry, AuthPolicy
│   └── maas-model-service/                        # Phase 4: vLLM LLMInferenceService templates
│
└── examples/                                      # 📚 Use-Case Overlays & Backward-Compatible Paths
    ├── Fusion-Agentic-Assistance-Platform/        # Agentic platform sample values & models
    └── model-registry-deployment/                 # Model Registry reference tutorial & Bob presets
```

### Upgrading from Prior Quickstart Versions:
1. **Zero Breaking Changes:** Existing models in `examples/` continue to deploy seamlessly with `./scripts/deploy-model.sh`.
2. **In-Place Upgrade:** Run `./scripts/install-runtime.sh -e prod` to perform an automated rolling upgrade of all operators, CRDs, Authorino TLS wiring, and gateway routes.
3. **Canonical Models:** Use [`models/`](https://github.com/IBM/storage-fusion/tree/master/AI/quickstarts/model-as-a-service/models) for all new deployments to take advantage of pre-tuned GPU settings.
