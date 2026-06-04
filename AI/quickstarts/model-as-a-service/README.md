# Quickstart: Model as a Service on IBM Fusion

Organizations adopting generative AI often need a secure, scalable, and governed way to host foundation models within their own infrastructure. Running models internally helps teams maintain control over data, access, performance, compliance, and operational costs while creating a consistent platform for enterprise AI workloads.

This quickstart demonstrates how to deploy a Model-as-a-Service (MaaS) platform on IBM Fusion using Red Hat OpenShift AI. The guide brings together model serving, storage, registry, gateway, and observability components into a unified deployment workflow for private AI inference on OpenShift.

IBM Fusion provides the storage foundation for model artifacts and platform data, while Red Hat OpenShift AI delivers model lifecycle, registry, and inference capabilities. Together, the platform components and Helm-based automation provide a streamlined foundation for deploying private AI inference workloads on OpenShift.

This quickstart provides a reference implementation for deploying private AI inference services on OpenShift using IBM Fusion and Red Hat OpenShift AI. The repository integrates storage, model management, inference, gateway access, and observability into a cohesive operational environment.

This guide is intended for platform engineers and AI infrastructure teams building internal AI serving platforms. By following it, you will:

- Deploy the core OpenShift AI platform components and required services
- Configure storage and Model Registry integration
- Import and register models from the Model Catalog
- Deploy GPU-backed inference services using LLM-D inference
- Expose models through secure OpenShift gateway endpoints
- Validate deployment health and test inference access with sample requests

By the end of this guide, you will have a working MaaS environment capable of serving foundation models such as `gpt-oss-20b` through secure, OpenShift-native inference APIs on IBM Fusion.

---

## What This Quickstart Deploys

This quickstart deploys a complete Model-as-a-Service (MaaS) environment on IBM Fusion and Red Hat OpenShift AI for enterprise AI model serving.

The deployment includes:

- Red Hat OpenShift AI platform services
- IBM Fusion object storage integration
- Model Registry services
- Gateway-based API routing and exposure
- GPU-backed inference runtimes using LLM-D
- Monitoring and observability components
- Example model deployment configurations

Together, these components provide a baseline environment for running and managing enterprise AI inference services on OpenShift.

---

## IBM Fusion for AI Architecture - MaaS Platform

```
┌────────────────────────────────────────────────────────────────┐
│              IBM Fusion for AI - MaaS Platform                 │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌───────────────────────────────────────────────────────┐     │
│  │              MaaS Runtime Infrastructure              │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │     │
│  │  │ Gateway  │  │   Rate   │  │   Auth   │  │ Model  │ │     │
│  │  │   API    │  │ Limiting │  │(Keycloak)│  │Catalog │ │     │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │     │
│  │  │   Model  │  │Monitoring│  │ Grafana  │  │ Tier   │ │     │
│  │  │ Registry │  │Prometheus│  │Dashboards│  │ Groups │ │     │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │     │
│  └───────────────────────────────────────────────────────┘     │
│                              │                                 │
│                              ▼                                 │
│  ┌───────────────────────────────────────────────────────┐     │
│  │           IBM Fusion Object Storage Layer             │     │
│  │         (OpenShift Data Foundation - ODF)             │     │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │     │
│  │  │    Model     │  │  Workbench   │  │   Model     │  │     │
│  │  │  Artifacts   │  │    Data      │  │  Registry   │  │     │
│  │  │   Storage    │  │   Storage    │  │   Backend   │  │     │
│  │  └──────────────┘  └──────────────┘  └─────────────┘  │     │
│  │  • Auto-provisioned buckets via ObjectBucketClaim     │     │
│  │  • Zero-configuration credential management           │     │
│  │  • Enterprise-grade performance and reliability       │     │
│  └───────────────────────────────────────────────────────┘     │
│                              │                                 │
│                              ▼                                 │
│  ┌───────────────────────────────────────────────────────┐     │
│  │              AI Model Inference Services              │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │     │
│  │  │ Model A  │  │ Model B  │  │ Model C  │  │Model D │ │     │
│  │  │All Tiers │  │Premium+  │  │Enterprise│  │Custom  │ │     │
│  │  │  (vLLM)  │  │  (TGI)   │  │ (vLLM)   │  │(Custom)│ │     │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │     │
│  └───────────────────────────────────────────────────────┘     │
│                              │                                 │
│                              ▼                                 │
│  ┌───────────────────────────────────────────────────────┐     │
│  │                  AI Applications                      │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐│     │
│  │  │   Code   │  │ Chatbot  │  │  Custom  │  │  Data   ││     │
│  │  │Assistant │  │    UI    │  │   Apps   │  │Science  ││     │
│  │  │DevSpaces │  │          │  │          │  │Workbench││     │
│  │  └──────────┘  └──────────┘  └──────────┘  └─────────┘│     │
│  └───────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────┘
```


## Table of Contents

This document is organized into deployment, validation, and reference sections:

- [What You'll Build](#what-youll-build)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [What's Deployed](#whats-deployed)
- [Learn More](#learn-more)
- [IBM Fusion for AI Architecture](#ibm-fusion-for-ai-architecture)
- [Key Features](#key-features)
- [Project Structure](#project-structure)
- [Use Cases](#use-cases)
- [Helm Charts Overview](#helm-charts-overview)
- [Chart Dependencies](#chart-dependencies)
- [Documentation](#documentation)
- [Benefits](#benefits)

---

## What You'll Build

By completing this quickstart, you will deploy a Red Hat OpenShift AI environment integrated with IBM Fusion storage services and a sample model-serving path. The resulting environment includes the core AI platform operators, a centralized model registry, gateway-based routing, GPU-backed inference services, monitoring integration, and storage for workbench users.

This quickstart is intended to help platform engineers and AI infrastructure teams understand how the repository components fit together and how to stand up the baseline services needed for model onboarding and inference delivery.

---

## Prerequisites

Before you begin, verify that the target environment satisfies the platform, GPU, CLI, and storage requirements listed below.

### Required

- **Red Hat OpenShift 4.20+** with cluster-admin access
- **GPU nodes** with at least one NVIDIA GPU-capable worker
- **Helm 3.8+** - [Install Helm](https://helm.sh/docs/intro/install/)
- **OpenShift CLI (`oc`)** - [Install oc](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)

### GPU Enablement (Required for LLM Serving)
If serving GPU-backed models such as vLLM-based LLMs, the following components must be installed:
- Node Feature Discovery (NFD) for hardware detection
- NVIDIA GPU Operator
- Worker nodes automatically labelled by the NVIDIA GPU Operator (for example: nvidia.com/gpu.present=true)

Verify GPU availability:
```bash
oc describe node <worker-node> | grep -i gpu
```
If GPUs are not detected, ensure the NVIDIA drivers and operator are correctly installed.


### Storage Options

Choose one supported S3-compatible storage backend for registry artifacts and related data:

- **OpenShift Data Foundation (ODF)** with S3-compatible storage with nooba
- **AWS S3 or other S3-compatible storage** such as MinIO or Ceph

### Verify Your Environment

```bash
# Check OpenShift version (should be 4.20+)
oc version

# Verify cluster-admin access
oc auth can-i '*' '*' --all-namespaces

# Check GPU availability (should show at least 1 node)
oc get nodes -l nvidia.com/gpu.present=true

# Verify Helm installation
helm version
```

---

## Deploy MaaS

The following procedure walks through repository access, storage credential setup, platform installation, model deployment, and endpoint validation.

### Step 1: Fork and Clone the Storage Fusion Repository
The quickstart examples reference configurations from the storage-fusion repository. Fork this repository to your GitHub account and clone it locally.

Fork the repository: Fork the storage-fusion repository

Clone the forked copy of this repository:
```
git clone git@github.com:<your-username>/storage-fusion.git
cd storage-fusion/quickstarts/model-as-a-service
```
Note: The quickstarts/model-as-a-service directory is located under the AI/ parent directory within the storage-fusion repository (path: storage-fusion/AI/quickstarts/model-as-a-service).

### Step 2: Configure Storage Credentials

Select the storage backend that matches your environment and export the corresponding credentials before starting the deployment.

**For OpenShift Data Foundation(ODF) Object Storage:**

IBM Fusion Data Foundation Object Storage can be configured in two ways:

1. **Automatic Bucket Creation (Recommended)** - When using OpenShift Data Foundation (ODF) with IBM Fusion, the platform automatically creates and configures object storage buckets using ObjectBucketClaim. This is the default configuration and **does not require manual credentials**.

   ```yaml
   # In your values.yaml (e.g., examples/Fusion-Agentic-Assistance-Platform/values.yaml)
   modelRegistry:
     objectStorage:
       enabled: true
       autoCreateBucket: true  # Automatic provisioning
       odfStorageClass: openshift-storage.noobaa.io
       bucketClass: noobaa-default-bucket-class
   ```

   With this configuration, credentials are automatically extracted from the ObjectBucketClaim and no manual setup is needed.

2. **Manual Credentials** - If you're using IBM Fusion Object Storage without ODF or prefer manual configuration, you need to provide credentials:

   ```bash
   export IBM_ACCESS_KEY="your-access-key-id"
   export IBM_SECRET_KEY="your-secret-access-key"
   export IBM_ENDPOINT="https://s3.us-south.cloud-object-storage.appdomain.cloud"
   ```

   Then configure in your values.yaml:
   ```yaml
   modelRegistry:
     objectStorage:
       enabled: true
       autoCreateBucket: false  # Manual configuration
       accessKeyId: "${IBM_ACCESS_KEY}"
       secretAccessKey: "${IBM_SECRET_KEY}"
       endpoint: "${IBM_ENDPOINT}"
       bucket: "model-registry-artifacts"
   ```

**Note:** The quickstart examples use automatic bucket creation by default. Manual credentials are only required when `autoCreateBucket: false` or when using external S3-compatible storage outside of IBM Fusion/ODF.

**For AWS S3:**
```bash
export AWS_ACCESS_KEY_ID="your-aws-access-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret-key"
export AWS_REGION="us-east-1"
```

**For MinIO (Development):**
```bash
export MINIO_ENDPOINT="http://minio.example.com:9000"
export MINIO_ACCESS_KEY="minioadmin"
export MINIO_SECRET_KEY="minioadmin"
```

### Step 3: Deploy the MAAS Platform

Use the automated installation script to deploy the operators, platform services, and runtime components in sequence. This step provisions the baseline infrastructure required for model registration, gateway exposure, and workbench storage.

```bash
# Deploy operators, platform, and runtime infrastructure in one command
./quickstarts/model-as-a-service/scripts/install-runtime.sh \
  quickstarts/model-as-a-service/examples/Fusion-Agentic-Assistance-Platform/values.yaml

# The script will:
# 1. Install maas-operators (OpenShift AI, Kuadrant, cert-manager)
# 2. Bootstrap maas-platform (DataScienceCluster, Gateway API)
# 3. Deploy maas-runtime (Model Registry, Workbench Storage, Gateway)
```

Expected output
```bash
 % ./quickstarts/mode-as-a-service/scripts/install-runtime.sh quickstarts/mode-as-a-service/examples/Fusion-Agentic-Assistance-Platform/values.yaml
=== MaaS Runtime Installation ===

Checking prerequisites...
✓ Prerequisites check passed

Checking for default StorageClass...
✓ Default StorageClass found

Keycloak is enabled. Please provide passwords:

Enter admin password: 
Enter user password: 

=== Phase 1: Installing Dependency Operator Subscriptions ===
Values file: quickstarts/mode-as-a-service/examples/Fusion-Agentic-Assistance-Platform/values.yaml
Chart: /Users/harichandanakotha/Documents/MAAS/Fusion-AI/quickstarts/mode-as-a-service/charts/maas-operators

Release "maas-operators" has been upgraded. Happy Helming!
NAME: maas-operators
LAST DEPLOYED: Sun May 24 22:11:03 2026
NAMESPACE: default
STATUS: deployed
REVISION: 2
TEST SUITE: None

✓ Dependency operator subscriptions installed

Waiting for OpenShift AI operator to be ready...
deployment.apps/rhods-operator condition met
✓ OpenShift AI operator ready
Waiting for DataScienceCluster CRD to be available...
✓ DataScienceCluster CRD available
Waiting for Kuadrant CRD to be available...
✓ Kuadrant CRD available
Waiting for LeaderWorkerSetOperator CRD to be available...
✓ LeaderWorkerSetOperator CRD available

=== Phase 2: Creating DataScienceCluster and Operator Instances ===
Values file: quickstarts/mode-as-a-service/examples/Fusion-Agentic-Assistance-Platform/values.yaml
Chart: /Users/harichandanakotha/Documents/MAAS/Fusion-AI/quickstarts/mode-as-a-service/charts/maas-platform

Release "maas-platform" has been upgraded. Happy Helming!
NAME: maas-platform
LAST DEPLOYED: Sun May 24 22:11:28 2026
NAMESPACE: default
STATUS: deployed
REVISION: 2
TEST SUITE: None

Waiting for DataScienceCluster to be ready...
datasciencecluster.datasciencecluster.opendatahub.io/default-dsc condition met
✓ DataScienceCluster ready

=== Phase 3: Installing MaaS Runtime Resources ===
Values file: quickstarts/mode-as-a-service/examples/Fusion-Agentic-Assistance-Platform/values.yaml
Chart: /Users/harichandanakotha/Documents/MAAS/Fusion-AI/quickstarts/mode-as-a-service/charts/maas-runtime

Installing MaaS runtime resources (gateway, model registry, workbench storage, etc.)...
I0524 22:12:09.207063   96967 warnings.go:110] "Warning: unknown field \"spec.istio\""
Release "maas-runtime" has been upgraded. Happy Helming!
NAME: maas-runtime
LAST DEPLOYED: Sun May 24 22:11:41 2026
NAMESPACE: default
STATUS: deployed
REVISION: 2
TEST SUITE: None

✓ MaaS Runtime resources installation complete

Waiting for additional components to be ready...

Waiting for Kuadrant...
kuadrant.kuadrant.io/kuadrant condition met
✓ Kuadrant ready
Waiting for Keycloak...
⚠ Keycloak not ready yet

=== Installation Summary ===

MaaS Runtime has been deployed!

Next steps:
1. Deploy models using: ./deploy-model.sh <model-values-file>
2. Check status: oc get all -n maas-models
3. View logs: oc logs -n maas-models -l app.kubernetes.io/component=model-service

Useful URLs:
  OpenShift Console: https://console-openshift-console.apps.f55l020.fusion.tadn.ibm.com
  Keycloak: https://N/A

Installation complete!
```
After the script completes, verify that the expected platform resources are present and reporting ready status:

```bash
# Check operators are running
oc get csv -n redhat-ods-operator
oc get csv -n kuadrant-system

# Verify platform is ready
oc get datasciencecluster
oc get kuadrant -n kuadrant-system

# Check runtime components
oc get modelregistry -n rhoai-model-registries
oc get gateway -n openshift-ingress
```

**Expected Output:**
```
# Operators
NAME                           DISPLAY                    VERSION   PHASE
rhods-operator.3.3.0          Red Hat OpenShift AI       3.3.0     Succeeded
kuadrant-operator.v0.8.0      Kuadrant Operator          0.8.0     Succeeded

# Platform
NAME          AGE   PHASE   CREATED AT
default-dsc   5m    Ready   2024-01-15T10:30:00Z

# Runtime
NAME             AGE   READY
model-registry   3m    True
```
### Step 3: Register Model from Model Catalog

Before deploying a model, you need to register it in the Model Registry. The Model Catalog provides access to curated foundation models from various sources including HuggingFace and Red Hat's model repository.

**Quick Registration Steps:**

1. Navigate to the OpenShift AI Dashboard:
   - **Models and Model Serving** → **Model Catalog**

2. Search for your desired model (e.g., `gpt-oss-20b`)

3. Select the model and click **Register Model**

4. Provide registration details:
   - **Name**: `gpt-oss-20b`
   - **Version**: `Version 1`
   - **Model Registry**: `model-registry` (created by the installation script)

5. Click **Register Model**

The model metadata is stored in the Model Registry while model artifacts remain in object storage. This separation allows for efficient version management and deployment tracking.

**For detailed instructions with screenshots and advanced options, see:**
- **[Registering Models from Catalog](docs/02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md)** - Complete registration guide
- **[Model Catalog Guide](docs/02-model-catalog-and-registry/MODEL_CATALOG_GUIDE.md)** - Adding custom catalog sources

### Step 4: Deploy Your First AI Model

```bash
# Deploy GPT-OSS-20B model for Fusion Agentic Assistance Platform using the deployment script
./quickstarts/model-as-a-service/scripts/deploy-model.sh \
  quickstarts/model-as-a-service/examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-20b-values.yaml

# The script will:
# 1. Deploy the model using maas-model-service chart
# 2. Configure rate limiting policies
# 3. Set up monitoring and routes
```

#### Expected output:

```bash
% ./quickstarts/model-as-a-service/scripts/deploy-model.sh \
  quickstarts/model-as-a-service/examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-20b-values.yaml
=== MaaS Model Deployment ===

Checking prerequisites...
✓ Prerequisites check passed

Model deployment details:
  Release name: gpt-oss-20b-version-1
  Values file: quickstarts/model-as-a-service/examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-20b-values.yaml
  Chart: /Users/harichandanakotha/Documents/MAAS/Fusion-AI/quickstarts/model-as-a-service/deploy/maas-model-service

Checking for MaaS runtime...
Model registry deployment mode detected
Checking if model 'gpt-oss-20b' exists in model registry...
✓ Model found in registry
  Registered Model ID: 1
  Model Name: gpt-oss-20b
  Latest Model Version ID: 2
  Latest Model Version Name: 1:Version 1
  Model URI: oci://registry.redhat.io/rhelai1/modelcar-gpt-oss-20b:1.5

✓ Model validation passed

Detecting cluster wildcard domain...
✓ Detected cluster wildcard domain: apps.f55l020.fusion.tadn.ibm.com

Namespace deploy-models-rhoai will be created by Helm

Deploying model...
Release "gpt-oss-20b-version-1" does not exist. Installing it now.
NAME: gpt-oss-20b-version-1
LAST DEPLOYED: Thu May 28 22:14:48 2026
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None

✓ Model deployment initiated

Waiting for model to be ready...
llminferenceservice.serving.kserve.io/gpt-oss-20b-version-1 condition met
✓ Model is ready

Gateway route will be created by Helm...
✓ Gateway route created successfully

Gateway URL: https://openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com
Model endpoint: https://openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com/deploy-models-rhoai/gpt-oss-20b-version-1

=== Deployment Summary ===

Model: gpt-oss-20b-version-1
Namespace: deploy-models-rhoai
Status: oc get llminferenceservice gpt-oss-20b-version-1 -n deploy-models-rhoai

Test the model:
  TOKEN=$(oc whoami -t)
  curl -k "https://openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com/deploy-models-rhoai/gpt-oss-20b-version-1/v1/models" \
    -H "Authorization: Bearer ${TOKEN}"

  curl -k -X POST "https://openshift-ai-inference-openshift-ingress.apps.f55l020.fusion.tadn.ibm.com/deploy-models-rhoai/gpt-oss-20b-version-1/v1/completions" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"model": "gpt-oss-20b-version-1", "prompt": "Hello", "max_tokens": 50}'

View logs:
  oc logs -n deploy-models-rhoai -l serving.kserve.io/inferenceservice=gpt-oss-20b-version-1 -c kserve-container -f

Troubleshooting:
  oc describe llminferenceservice gpt-oss-20b-version-1 -n deploy-models-rhoai
  oc get events -n deploy-models-rhoai --sort-by='.lastTimestamp'

Deployment complete!
```

Monitor the deployment until the inference service reports a ready condition:

```bash
# Stream status changes for the inference service
oc get llminferenceservice -n deploy-models-rhoai -w

# Check model pods
oc get pods -n deploy-models-rhoai
```

**Expected Output:**
```
NAME          READY   URL                                                  AGE
gpt-oss-20b   True    https://gateway.example.com/deploy-models-rhoai/...   3m
```

### Step 5: Test Your Model

```bash
# Get the model endpoint
MODEL_URL=$(oc get route gpt-oss-20b -n deploy-models-rhoai -o jsonpath='{.spec.host}')

# Get authentication token
TOKEN=$(oc whoami -t)

# Test the model
curl -k -X POST "https://${MODEL_URL}/v1/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "prompt": "Write a Python function to calculate fibonacci numbers:",
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

The model is automatically exposed through the gateway route when external gateway exposure is enabled in the values file.

```bash
# Get the gateway route (exposed automatically by the deployment)
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')

# Get authentication token
TOKEN=$(oc whoami -t)

# Test the model through the gateway
# Pattern: https://<gateway-host>/<namespace>/<model-name>/v1/completions
curl -k -X POST "https://${GATEWAY_HOST}/deploy-models-rhoai/gpt-oss-20b-version-1/v1/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b-version-1",
    "prompt": "Write a Python function to calculate fibonacci numbers:",
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

At this stage, the platform is ready with a deployed model that is accessible through the configured gateway endpoint.

---

## What's Deployed

After completing the quickstart, the environment includes the following platform and runtime components:

| Component | Description | Namespace |
|-----------|-------------|-----------|
| **OpenShift AI** | Core AI platform | `redhat-ods-operator` |
| **Kuadrant** | API gateway & rate limiting | `kuadrant-system` |
| **Model Registry** | Model versioning & storage | `rhoai-model-registries` |
| **Gateway** | Intelligent routing | `openshift-ingress` |
| **GPT-OSS-20B** | Code assistance model | `deploy-models-rhoai` |
| **Monitoring** | Prometheus & Grafana | `openshift-monitoring` |

---


## Key Features

### IBM Fusion for AI Integration

IBM Fusion provides the storage foundation for this deployment model. The platform can use IBM Fusion Object Storage through OpenShift Data Foundation to store model artifacts, workbench data, and registry-backed assets. Automatic bucket provisioning through ObjectBucketClaim simplifies storage setup and helps standardize the way model-serving components consume object storage.

### Model Management

The platform supports centralized model management through a model registry backed by IBM Fusion-integrated storage. It also supports curated model discovery and controlled deployment flows, allowing teams to register, version, and expose models using a repeatable operational pattern.

### Flexibility

The deployment model supports multiple use cases on the same shared platform. Teams can deploy models independently, choose among supported storage backends, and adapt the same runtime foundation to different application requirements.

### Governance

Tier-based access control and request limiting allow platform teams to define differentiated service levels for model consumers. These controls help support internal governance, quota enforcement, and usage management across shared inference endpoints.

### Observability

The runtime integrates with Prometheus and Grafana so that operators can monitor model-serving health, endpoint usage, and related platform signals. This observability model supports day-to-day operations and troubleshooting for shared inference infrastructure.

## Project Structure

```text
model-as-a-service/
├── deploy/
│   ├── maas-operators/            # Operator installation chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── namespaces.yaml
│   │       ├── operatorgroups.yaml
│   │       └── subscriptions.yaml
│   │
│   ├── maas-platform/             # Platform bootstrap chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── datasciencecluster.yaml
│   │       └── operator-instances.yaml
│   │
│   ├── maas-runtime/              # Core MaaS infrastructure
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── namespace.yaml
│   │       ├── rbac.yaml
│   │       ├── tier-groups.yaml
│   │       ├── gateway.yaml
│   │       ├── modelregistry.yaml
│   │       └── workbench-storage.yaml
│   │
│   ├── maas-model-service/        # Generic model deployment
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── llminferenceservice.yaml
│           ├── ratelimitpolicy.yaml
│           ├── servicemonitor.yaml
│           ├── connection-secret.yaml
│           ├── route.yaml
│           └── namespace.yaml
│
├── examples/
│   ├── Fusion-Agentic-Assistance-Platform/  # Fusion Agentic Assistance Platform use case
│   │   ├── README.md
│   │   ├── values.yaml
│   │   └── models/
│   │       ├── gpt-oss-values.yaml
│   │       ├── gpt-oss-20b-values.yaml
│   │       └── nemotron-values.yaml
│   │
│   ├── model-registry-deployment/ # Model registry examples
│   │   ├── README.md
│   │   ├── gpt-oss-20b-values.yaml
│   │   ├── granite-31-8b-lab-v1-values.yaml
│   │   └── qwen3-8b-fp8-dynamic-values.yaml
│   │
│   ├── model-registry-gitops/     # GitOps for model registry
│   ├── operators-gitops-deployment/ # GitOps for operators
│   ├── maas-runtime-gitops-deployment/ # GitOps for runtime
│   ├── maas-model-service-gitops-deployment/ # GitOps for models
│   └── workbench-model-testing/   # Model testing workflow
│
├── docs/
│   ├── GETTING_STARTED.md
│   ├── DEPLOYMENT_ORDER.md
│   ├── configuration/
│   │   ├── MODEL_CATALOG_GUIDE.md
│   │   ├── MODEL_REGISTRY_GUIDE.md
│   │   └── WORKBENCH_STORAGE_GUIDE.md
│   ├── deployment/
│   │   └── DEPLOYING_MODEL_SERVICES.md
│   └── operations/
│       └── ADDING_MODELS_TO_REGISTRY.md
│
└── blogs/
    ├── published/
    │   ├── gitops-series/
    │   ├── quick-start/
    │   └── techxchange-series/
    └── planning/
```

## IBM Fusion for AI Quick Start Features

### IBM Fusion Object Storage Integration

This quickstart uses IBM Fusion as the storage foundation for the MaaS platform. In practice, that means model artifacts, registry-backed metadata flows, and workbench-related data can be mapped to a common storage layer exposed through OpenShift-native patterns such as ObjectBucketClaim.

For model registry workflows, the platform supports IBM Fusion Object Storage integration through OpenShift Data Foundation, automated bucket provisioning, model version tracking, metadata management, and PostgreSQL-backed registry state. Additional implementation details are available in [docs/02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md](docs/02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md).


## Use Cases

### Fusion Agentic Assistance Platform

The Fusion Agentic Assistance Platform demonstrates how the platform can serve AI-powered assistance workloads with agentic capabilities. Reference material is available in [fusion-AgenticAssistanceSampleApp/README.md](../../fusion-AgenticAssistanceSampleApp/README.md), with example model configurations for GPT-OSS-20B and Nemotron-based deployments.

### Chatbot (Coming Soon)

Customer service chatbot with web UI.

- Models: Llama-3-70B, Mistral-7B
- Application: Custom chatbot interface

### Document Analysis (Coming Soon)

A document analysis scenario is also planned for multimodal processing workloads. This use case will focus on text-and-image processing patterns and the service composition needed for document-centric AI pipelines.

## Documentation

The MaaS platform is deployed using four Helm charts that must be installed in sequence:

```text
maas-operators (install first)
    ↓
maas-platform (requires operators)
    ↓
maas-runtime (requires platform)
    ↓
maas-model-service (requires runtime)
```

### Helm Chart Guides

| Chart | Purpose | Documentation |
|-------|---------|---------------|
| **maas-operators** | Installs OpenShift AI and dependent operators | [MaaS Operators Guide](docs/01-setup/MAAS_OPERATORS_GUIDE.md) |
| **maas-platform** | Configures DataScienceCluster and platform components | [Platform Customization Guide](docs/01-setup/MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md) |
| **maas-runtime** | Deploys gateway, model registry, and storage integration | [Runtime Customization Guide](docs/01-setup/MAAS_RUNTIME_CUSTOMIZATION_GUIDE.md) |
| **maas-model-service** | Deploys individual AI models as inference services | [Deploying Model Services](docs/03-model-deployment/DEPLOYING_MODEL_SERVICES.md) |

### Getting Started
- [Getting Started Guide](docs/GETTING_STARTED.md) - Complete installation and setup guide
- [Deployment Order Guide](docs/01-setup/DEPLOYMENT_ORDER.md) - Step-by-step deployment sequence

### Configuration Guides
- [Model Catalog Guide](docs/02-model-catalog-and-registry/MODEL_CATALOG_GUIDE.md) - HuggingFace integration and model discovery
- [Registering Models](docs/02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md) - Model registration from catalog

### Examples
- [Fusion Agentic Assistance Platform](examples/Fusion-Agentic-Assistance-Platform/README.md) - Complete use case with multiple models
- [Model Registry Deployment](examples/model-registry-deployment/README.md) - Model registry entry examples
