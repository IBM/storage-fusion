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

## Deployment Options

The MaaS platform on IBM Fusion supports two deployment approaches. Choose based on your team's operational model:

| Deployment Method | Recommended For |
|---|---|
| **Helm** | Evaluation environments, proof-of-concepts, and teams preferring direct installation and manual lifecycle management |
| **GitOps** | Production environments and teams managing deployments through Git-based workflows and automation |

This guide covers the **Helm-based deployment**. For a production-grade GitOps deployment — where all platform services are declared in Git and continuously reconciled by Red Hat OpenShift GitOps (ArgoCD) — see the [Quickstart: IBM Fusion Model-as-a-Service Platform — GitOps Deployment and Customization](https://community.ibm.com/community/user/blogs/harichandana-kotha/2026/06/29/quickstart-maas-ibm-fusion-gitops).

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
- **Helm 3.8+** — [Install Helm](https://helm.sh/docs/intro/install/)
- **OpenShift CLI (`oc`)** — [Install oc](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)

#### For GitOps Deployment (Option B)

- **Red Hat OpenShift GitOps operator** installed and configured — deploys ArgoCD into the `openshift-gitops` namespace. See [Red Hat GitOps Deployment for Fusion HCI](../fusion-gitops/README.md) for installation steps
- **ArgoCD CLI (`argocd`)** — [Install argocd](https://argo-cd.readthedocs.io/en/stable/cli_installation/)

#### For ESO-Based Secret Management (Recommended for Production)

- **External Secrets Operator (ESO)** installed in the cluster with a `ClusterSecretStore` named `vault-backend` pointing at HashiCorp Vault (or an equivalent secrets backend). ESO is used to inject S3 credentials, database passwords, and Git tokens into the cluster without committing them to Git. See the per-chart Vault setup guides:
  - [`deploy/helm/maas-platform/VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — DB config and PostgreSQL credentials
  - [`deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md) — S3 credentials per model
  - [`deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) — Git credentials and Hugging Face token

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

### Step 1: Clone the Repository

```bash
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/AI/quickstarts/model-as-a-service-rhoai-3.5
```

### Step 2: Configure Storage Credentials

Select the storage backend that matches your environment. For production, use External Secrets Operator (ESO) to manage credentials — no plaintext secrets are committed to Git. For development or quick-start, manual credentials work fine.

> **Production recommendation:** Before running ArgoCD sync, store all S3 credentials in Vault and enable ESO in your environment overlay. See [`deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md) for step-by-step instructions. Vault secrets must exist **before** the first ArgoCD sync — ESO resolves them at sync time.

**For OpenShift Data Foundation (ODF) Object Storage:**

IBM Fusion Data Foundation Object Storage can be configured in two ways:

1. **Automatic Bucket Creation (Recommended)** — When using OpenShift Data Foundation (ODF) with IBM Fusion, the platform automatically creates and configures object storage buckets using ObjectBucketClaim. This is the default configuration and **does not require manual credentials**.

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

2. **Manual Credentials** — If you're using IBM Fusion Object Storage without ODF or prefer manual configuration, provide credentials directly:

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

3. **ESO / Vault (Production)** — Store S3 credentials in Vault and let ESO inject them. See [`deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md).

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

You can deploy the MaaS platform using either the automated installation script or GitOps with ArgoCD. Both methods provision the baseline infrastructure required for model registration, gateway exposure, and workbench storage.

#### Option A: Script-Based Deployment (Recommended for Quick Start)

Use the automated installation script to deploy the operators, platform services, and runtime components in sequence:

```bash
# Deploy operators, platform, and runtime infrastructure in one command
./AI/quickstarts/model-as-a-service-rhoai-3.5/scripts/install-runtime.sh \
  AI/quickstarts/model-as-a-service-rhoai-3.5/examples/Fusion-Agentic-Assistance-Platform/values.yaml

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
Chart: /Users/harichandanakotha/Documents/storage-fusion/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-operators

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
Chart: /Users/harichandanakotha/Documents/storage-fusion/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform

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
Chart: /Users/harichandanakotha/Documents/storage-fusion/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-runtime

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


#### Option B: GitOps Deployment with ArgoCD (Recommended for Production)

For production environments or GitOps-based workflows, deploy using ArgoCD Applications:

**Prerequisites:**
- **Red Hat OpenShift GitOps operator** installed and configured — see [Red Hat GitOps Deployment for Fusion HCI](../fusion-gitops/README.md) for installation steps
- **ArgoCD CLI (`argocd`)** — [Install argocd](https://argo-cd.readthedocs.io/en/stable/cli_installation/)
- Access to the Git repository containing the MaaS configurations

**Step 3.1: Update Application Value Files**

Before deploying, update all application manifests in `AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/applications/` to reference your custom values file:

```bash
# Edit each application file (01-maas-operators-prod.yaml, 02-maas-platform-prod.yaml, 03-maas-runtime-prod.yaml)
# Update the helm.valueFiles section to include your custom values:

# Example for 01-maas-operators-prod.yaml:
spec:
  source:
    helm:
      valueFiles:
        - values.yaml
        - environments/prod/values.yaml
        - ../../../../../../examples/Fusion-Agentic-Assistance-Platform/values.yaml  # Add this line
```

**Step 3.2: Deploy the AppProject**

Create the ArgoCD AppProject for production:

```bash
oc apply -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/appproject-prod.yaml
```

**Step 3.3: Deploy the App-of-Apps**

Deploy the main application that manages all MaaS components:

```bash
oc apply -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/00-prod-app-of-apps.yaml
```

This creates an ArgoCD Application that manages three child applications:
- `maas-operators-prod` (sync-wave: 0) - Installs required operators
- `maas-platform-prod` (sync-wave: 50) - Configures DataScienceCluster and platform
- `maas-runtime-prod` (sync-wave: 100) - Deploys runtime infrastructure

**Step 3.4: Sync Applications in Order**

Since production uses manual sync policy, you must sync each application manually in the correct order:

```bash
# 1. Sync operators first
argocd app sync maas-operators-prod --prune

# Wait for operators to be ready (check CSVs are in Succeeded phase)
oc get csv -n redhat-ods-operator
oc get csv -n kuadrant-system

# 2. Sync platform
argocd app sync fusion-maas-platform-prod --prune

# Wait for DataScienceCluster to be ready
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=600s

# 3. Sync runtime
argocd app sync fusion-maas-runtime-prod --prune

# Wait for runtime components to be ready
oc get modelregistry -n rhoai-model-registries
oc get gateway -n openshift-ingress
```

**Alternative: Sync via OpenShift GitOps UI**

1. Navigate to **OpenShift GitOps** in the OpenShift Console
2. Find the `maas-platform-prod` application
3. Click **Sync** → **Synchronize** for each child application in order:
   - First: `maas-operators-prod`
   - Second: `maas-platform-prod`
   - Third: `maas-runtime-prod`

> **Post-sync manual steps required.** After `maas-platform` syncs, run the steps in [`deploy/helm/maas-platform/POST_SYNC_MANUAL_STEPS.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/POST_SYNC_MANUAL_STEPS.md):
> 1. Enable User Workload Monitoring (`cluster-monitoring-config`)
> 2. Configure Authorino TLS
> 3. Patch `OdhDashboardConfig` for MaaS dashboard features (`modelAsService`, `genAiStudio`, `maasAuthPolicies`)
>
> Run [`deploy/helm/maas-platform/VERIFICATION.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VERIFICATION.md) afterwards to confirm the platform is healthy.

> **If using ESO for database credentials**, store Vault secrets before syncing `maas-platform`. See [`deploy/helm/maas-platform/VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — credentials must exist in Vault before ArgoCD resolves the `ExternalSecret` CRs at sync time.

### Step 4: Register Model from Model Catalog

Before deploying a model, you need to register it in the Model Registry. The Model Catalog provides access to curated foundation models from various sources including HuggingFace and Red Hat's model repository.

You can register models using either the UI-based approach or GitOps automation.

#### Option A: UI-Based Registration (Quick Start)

**Quick Registration Steps:**

1. Navigate to the OpenShift AI Dashboard:
   - **Models and Model Serving** → **Model Catalog**

2. Search for your desired model (e.g., `gpt-oss-20b`)

3. Select the model and click **Register Model**

4. Provide registration details:
   - **Name**: `gpt-oss-20b`
   - **Version**: `Version 1`
   - **Model Registry**: `model-registry` (created during Step 3)

5. Click **Register Model**

The model metadata is stored in the Model Registry while model artifacts remain in object storage. This separation allows for efficient version management and deployment tracking.

**For detailed instructions with screenshots and advanced options, see:**
- **[Registering Models from Catalog](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md)** - Complete registration guide
- **[Model Catalog Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/02-model-catalog-and-registry/MODEL_CATALOG_GUIDE.md)** - Adding custom catalog sources

#### Option B: GitOps-Based Model Registration (Recommended for Production)

For automated model registration using GitOps, deploy the Model Registry GitOps application. This approach automatically registers models defined in Git and stores them in the S3 object storage created during Step 3.

**Prerequisites:**
- ArgoCD/OpenShift GitOps installed
- MaaS Platform deployed (Step 3 completed)
- Model Registry and S3 storage available
- **ESO/Vault (recommended for production):** Store Git credentials and Hugging Face token in Vault before the first sync. See [`deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md).

**Step 4.1: Deploy the AppProject**

Create the ArgoCD AppProject for model registry:

```bash
oc apply -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/argocd/environments/prod/appproject-prod.yaml
```

**Step 4.2: Deploy the Model Registry GitOps Application**

Deploy the application that manages model registration:

```bash
oc apply -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/argocd/environments/prod/application.yaml
```

This creates an ArgoCD Application (`model-registry-gitops-prod`) that:
- Watches model definitions in `AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/models/`
- Automatically downloads models from HuggingFace or other sources
- Uploads model artifacts to the S3 object storage (created in Step 3)
- Registers model metadata in the Model Registry
- Runs periodic synchronization via CronJob

**Step 4.3: Sync the Application**

Since production uses manual sync, trigger the initial sync:

```bash
# Sync the application
argocd app sync model-registry-gitops-prod --prune

# Verify the reconciler is running
oc get pods -n model-registry-gitops-prod
oc get cronjob -n model-registry-gitops-prod
```

**Step 4.4: Verify Model Registration**

Check that models are being registered:

```bash
# Check reconciler logs
oc logs -n model-registry-gitops-prod -l app=model-reconciler --tail=50

# Verify models in the registry (via Model Registry API)
oc get configmap -n model-registry-gitops-prod

# Check S3 storage for model artifacts
oc get objectbucketclaim -n rhoai-model-registries
```

**Available Models:**

The following models are pre-configured in `AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/models/`:
- **Granite Models**: `granite/granite-4.1-8b.yaml`
- **GPT-OSS Models**: `gpt-oss/gpt-oss-20b-hf.yaml`
- **Qwen Models**: `qwen/qwen3-8b-fp8-dynamic-hf.yaml`
- **Test Models**: `test-model/tiny-llama.yaml`

**Adding New Models:**

See [`deploy/gitops/model-registry-gitops/models/ADDING_A_MODEL.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/models/ADDING_A_MODEL.md) for how to create a `ModelVersion` YAML and commit it.

Commit the file to Git, and ArgoCD will automatically sync and register the model.


**For more details, see:**
- **[Model Registry GitOps README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/README.md)** - Complete GitOps setup guide
- **[Model Schema](deploy/gitops/model-registry-gitops/models/schema.yaml)** - Model definition schema

### Step 5: Deploy Your First AI Model

Use **Option A (Helm)** for a quick, imperative deployment — ideal for local development or a first-time setup. Use **Option B (GitOps)** for production, where Git is the source of truth and ArgoCD handles reconciliation automatically on every approved sync.

---

#### Option A: Helm Deployment (Quick Start)

```bash
# Deploy GPT-OSS-20B model for Fusion Agentic Assistance Platform using the deployment script
./AI/quickstarts/model-as-a-service-rhoai-3.5/scripts/deploy-model.sh \
  AI/quickstarts/model-as-a-service-rhoai-3.5/examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-20b-values.yaml

# The script will:
# 1. Deploy the model using maas-model-service chart
# 2. Configure rate limiting policies
# 3. Set up monitoring and routes
```

##### Expected output:

```bash
% ./AI/quickstarts/model-as-a-service-rhoai-3.5/scripts/deploy-model.sh \
  AI/quickstarts/model-as-a-service-rhoai-3.5/examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-20b-values.yaml
=== MaaS Model Deployment ===

Checking prerequisites...
✓ Prerequisites check passed

Model deployment details:
  Release name: gpt-oss-20b-version-1
  Values file: AI/quickstarts/model-as-a-service-rhoai-3.5/examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-20b-values.yaml
  Chart: /Users/harichandanakotha/Documents/storage-fusion/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/maas-model-service

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

Gateway URL: https://maas.apps.f55l020.fusion.tadn.ibm.com
Model endpoint: https://maas.apps.f55l020.fusion.tadn.ibm.com/deploy-models-rhoai/gpt-oss-20b-version-1

=== Deployment Summary ===

Model: gpt-oss-20b-version-1
Namespace: deploy-models-rhoai
Status: oc get llminferenceservice gpt-oss-20b-version-1 -n deploy-models-rhoai

Test the model:
  TOKEN=$(oc whoami -t)
  curl -k "https://maas.apps.f55l020.fusion.tadn.ibm.com/deploy-models-rhoai/gpt-oss-20b-version-1/v1/models" \
    -H "Authorization: Bearer ${TOKEN}"

  curl -k -X POST "https://maas.apps.f55l020.fusion.tadn.ibm.com/deploy-models-rhoai/gpt-oss-20b-version-1/v1/completions" \
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

---

#### Option B: GitOps Deployment with ArgoCD (Recommended for Production)

ArgoCD manages the model deployment lifecycle declaratively — commit a change to Git and ArgoCD reconciles it on the cluster. Manual sync is required for production so every deployment is intentional.

##### Prerequisites

Verify the MaaS runtime and ArgoCD are healthy before deploying, and store S3 credentials in Vault if using ESO:

```bash
# Confirm the MaaS runtime (Gateway + ModelRegistry) is running
oc get application fusion-maas-runtime-prod -n openshift-gitops

# Confirm ArgoCD pods are running
oc get pods -n openshift-gitops
```

##### Configure your model and S3 credentials

Edit [`AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/prod/values.yaml`](AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/prod/values.yaml) with your model and S3 details.

**Option A — ESO / Vault (recommended for production):** Store all five S3 fields in Vault at `secret/maas/model-deploy/<model-name>/s3` and enable `s3.externalSecret.enabled: true`. No credentials are committed to Git. See [`deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md) for the full walkthrough. **Vault secrets must exist before the first ArgoCD sync.**

```yaml
model:
  name: my-model
  namespace: deploy-models

s3:
  modelPath: "my-model/1.0.0"   # still required — used for the model URI
  verifySSL: "0"                 # still required — not stored in Vault

  externalSecret:
    enabled: true
    refreshInterval: 1h
    secretStoreRef:
      name: vault-backend        # must match your ClusterSecretStore name
      kind: ClusterSecretStore
    remoteRef:
      key: maas/model-deploy/my-model/s3   # Vault path from VAULT-SECRET-SETUP.md Step 1
```

**Option B — Manual credentials (quick-start / dev only):**

```yaml
model:
  name: my-model           # Kubernetes resource name
  displayName: "My Model"  # Shown in RHOAI dashboard
  namespace: deploy-models

s3:
  endpoint: "https://s3.openshift-storage.svc:443"
  region: "us-south"
  bucket: "my-model-bucket"
  modelPath: "my-model/1.0.0"
  verifySSL: "0"
  accessKeyId: ""                # Supply at sync time via --set or env overlay
  secretAccessKey: ""            # Supply at sync time — do not commit to Git
```


##### Update the Application manifest

Before applying, confirm the Application CR points to your repository and branch.

Open [`AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/environments/prod/application.yaml`](AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/environments/prod/application.yaml) and set:

```yaml
spec:
  source:
    repoURL: https://github.com/IBM/storage-fusion.git  # your repo
    targetRevision: master                                         # your branch or tag
    path: AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy
    helm:
      valueFiles:
        - values.yaml
        - environments/prod/values.yaml
```

##### Deploy to Production

```bash
# 1. Apply the AppProject (creates RBAC)
oc apply -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/environments/prod/appproject-prod.yaml

# 2. Apply the Application manifest
oc apply -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/environments/prod/application.yaml

# 3. In the ArgoCD UI: open fusion-maas-model-deploy-prod, review the diff,
#    then click Sync during an approved change window.
# Or via CLI (requires appropriate role):
argocd app sync fusion-maas-model-deploy-prod
```

##### Monitor

```bash
# Check ArgoCD application sync status
oc get applications.argoproj.io fusion-maas-model-deploy-prod -n openshift-gitops

# Check model resources
oc get llminferenceservice -n deploy-models
oc get pods -n deploy-models
oc get secret -n deploy-models
```

See [`AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/README.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/README.md) for the full runbook including rollback and troubleshooting.

### Step 6: Test Your Model

Use the option that matches how you deployed the model in Step 5.

---

#### Option A: Helm Deployment (Quick Start)

The Helm script deploys into namespace `deploy-models-rhoai` and exposes the model through the `maas-gateway-route` OpenShift Route automatically.

```bash
# Get the gateway route (clusterip ingressMode — route name is maas-gateway-route)
GATEWAY_HOST=$(oc get route maas-gateway-route -n openshift-ingress -o jsonpath='{.spec.host}')

# Get authentication token
TOKEN=$(oc whoami -t)

# List available models
curl -k "https://${GATEWAY_HOST}/deploy-models-rhoai/gpt-oss-20b-version-1/v1/models" \
  -H "Authorization: Bearer ${TOKEN}"

# Test the model
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

---

#### Option B: GitOps Deployment with ArgoCD (Production)

The GitOps deployment lands in namespace `deploy-models`. Replace `<model-name>` with the value you set for `model.name` in your prod values file.

```bash
# 1. Confirm the inference service is ready
oc get llminferenceservice -n deploy-models

# 2. Resolve the gateway hostname and your token
#    (clusterip ingressMode — route name is maas-gateway-route, host is maas.<wildcard-domain>)
GATEWAY_HOST=$(oc get route maas-gateway-route -n openshift-ingress -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

# 3. Send a test prompt
# Pattern: https://<gateway-host>/<namespace>/<model-name>/v1/completions
curl -k -X POST "https://${GATEWAY_HOST}/deploy-models/<model-name>/v1/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"model": "<model-name>", "prompt": "Hello", "max_tokens": 50}'
```

For full testing steps — ArgoCD health checks, HTTPRoute verification, live inference examples, and troubleshooting — see [`deploy/gitops/maas-model-deploy/TEST_MODELS.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/TEST_MODELS.md).

---

At this stage, the platform is ready with a deployed model that is accessible through the configured gateway endpoint.

---

### Step 7: Configure Subscription-Based Governance (`maas-config`)

With models running, apply the `maas-config` layer to enforce who can call them, with what token quotas, and through which API keys. This step deploys `MaaSSubscription` and `MaaSAuthPolicy` custom resources via GitOps (ArgoCD sync wave 300, after the model deploy layer in wave 200).

> **Prerequisites:** All `MaaSModelRef` resources must be `Ready` before this step. Verify with `oc get maasmodelref -n deploy-models`. For full details see [`infoDocs/maas-config-governance-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/infoDocs/maas-config-governance-guide.md).

**1. Verify MaaSModelRef resources are Ready**

```bash
oc get maasmodelref -n deploy-models
```

**2. Configure the values file**

Edit `deploy/helm/maas-config/environments/prod/values-prod.yaml` with your model names, namespaces, groups, and token rate limits:

```yaml
maasNamespace: models-as-a-service

subscriptions:
  - name: maas-prod-subscription
    displayName: "MaaS Production Subscription"
    priority: 100
    groups:
      - rhods-admins
    modelRefs:
      - name: <model-name>           # output of: oc get maasmodelref -n deploy-models
        namespace: deploy-models
        tokenRateLimits:
          - limit: 10000
            window: "1h"

authPolicies:
  - name: maas-prod-auth-policy
    groups:
      - rhods-admins                 # must match subscriptions[].groups exactly
    modelRefs:
      - name: <model-name>           # must match subscriptions[].modelRefs
        namespace: deploy-models

groups:
  - name: rhods-admins
    users:
      - <username>
```

> `authPolicies[].groups` and `authPolicies[].modelRefs` must exactly match the values in `subscriptions[]`.

**3. Update the Application manifest**

In `deploy/gitops/maas-config/environments/prod/application-governance-prod.yaml`, set `repoURL` and `targetRevision` to point to your fork:

```yaml
spec:
  source:
    repoURL: https://github.com/<your-username>/storage-fusion.git
    targetRevision: master
```

**4. Commit, push, and deploy**

```bash
git add AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-config/environments/prod/
git add AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/environments/prod/
git commit -m "Configure maas-config governance for production"
git push

# Apply the AppProject (once per cluster)
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-config/environments/prod/appproject-prod.yaml

# Register the Application with ArgoCD
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-config/environments/prod/application-governance-prod.yaml

# Sync (production uses manual sync)
argocd app sync fusion-maas-governance-config-prod
```

**5. Verify governance resources**

```bash
oc get maassubscription -n models-as-a-service
oc get maasauthpolicy -n models-as-a-service
```

Expected output:

```text
NAME                     PHASE    PRIORITY   AGE
maas-prod-subscription   Active   100        2m

NAME                    PHASE    AGE
maas-prod-auth-policy   Active   2m
```

**6. Create an API key and test model access**

Users create API keys bound to a subscription. Keys carry the `sk-oai-` prefix and are shown only once at creation.

```bash
# Resolve the gateway URL
MAAS_HOST="maas.$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')"

# Obtain an auth token
AUTH_TOKEN=$(oc whoami -t)

# Create an API key
curl -s -X POST "https://${MAAS_HOST}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-prod-key", "subscription": "maas-prod-subscription", "expiresIn": "30d"}'
# Copy the "key" field (sk-oai-...) — it is displayed only once.
```

Alternatively, create a key through the OpenShift AI dashboard: **Gen AI Studio → API keys → Create API key**.

**7. Send a governed inference request**

```bash
export MAAS_API_KEY="<your-sk-oai-key>"

curl -s \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  "https://${MAAS_HOST}/deploy-models/<model-name>/v1/chat/completions" \
  -d '{"model": "<model-name>", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 100}'
```

| HTTP Status | Meaning |
|---|---|
| `200 OK` | `MaaSSubscription` and `MaaSAuthPolicy` are active and aligned |
| `403 Forbidden` | API key revoked, or user's group not in `MaaSAuthPolicy` |
| `429 Too Many Requests` | Token quota exhausted — check `tokenRateLimits` in the values file |

For full details on API key lifecycle, troubleshooting, and adding governance for new models, see [`infoDocs/maas-config-governance-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/infoDocs/maas-config-governance-guide.md).

---

## What's Deployed

After completing the quickstart, the environment includes the following platform and runtime components:

| Component | Description | Namespace |
|-----------|-------------|-----------|
| **OpenShift AI** | Core AI platform | `redhat-ods-operator` |
| **Red Hat Connectivity Link** | API gateway, routing & rate limiting (Kuadrant) | `kuadrant-system` |
| **Model Registry** | Model versioning & storage | `rhoai-model-registries` |
| **Gateway** | Intelligent routing | `openshift-ingress` |
| **GPT-OSS-20B** | Code assistance model | `deploy-models-rhoai` |
| **Monitoring** | Prometheus platform monitoring; Grafana operator installed (dashboards not configured) | `openshift-monitoring` |

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
│   ├── helm/                      # Helm charts
│   │   ├── maas-operators/        # Operator subscriptions
│   │   ├── maas-platform/         # DataScienceCluster & platform config
│   │   ├── maas-runtime/          # Gateway, Model Registry, RBAC
│   │   ├── maas-model-service/    # Model deployment chart
│   │   └── maas-model-registry/   # Model registry reconciler
│   │
│   └── gitops/                    # ArgoCD Applications
│       ├── maas-gitops-deployment/      # Platform GitOps (operators, platform, runtime)
│       │   └── environments/            # dev, staging, prod
│       │       └── prod/
│       │           ├── 00-prod-app-of-apps.yaml
│       │           ├── appproject-prod.yaml
│       │           └── applications/
│       │               ├── 01-maas-operators-prod.yaml
│       │               ├── 02-maas-platform-prod.yaml
│       │               └── 03-maas-runtime-prod.yaml
│       │
│       └── model-registry-gitops/       # Model registration GitOps
│           ├── argocd/environments/     # ArgoCD apps (dev, staging, prod)
│           ├── models/                  # Model definitions (granite, gpt-oss, qwen)
│           └── docs/
│
├── examples/
│   ├── Fusion-Agentic-Assistance-Platform/  # Complete use case
│   │   ├── values.yaml                      # Combined configuration
│   │   └── models/                          # Model-specific values
│   └── model-registry-deployment/           # Model deployment examples
│
├── scripts/
│   ├── install-runtime.sh         # Automated platform deployment
│   └── deploy-model.sh            # Model deployment
│
└── docs/
    ├── GETTING_STARTED.md
    ├── 01-setup/                  # Deployment guides
    ├── 02-model-catalog-and-registry/
    └── 03-model-deployment/
```

## IBM Fusion for AI Quick Start Features

### IBM Fusion Object Storage Integration

This quickstart uses IBM Fusion as the storage foundation for the MaaS platform. In practice, that means model artifacts, registry-backed metadata flows, and workbench-related data can be mapped to a common storage layer exposed through OpenShift-native patterns such as ObjectBucketClaim.

For model registry workflows, the platform supports IBM Fusion Object Storage integration through OpenShift Data Foundation, automated bucket provisioning, model version tracking, metadata management, and PostgreSQL-backed registry state. Additional implementation details are available in [docs/02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md).


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

### GitOps Deployment Guides

For production deployments using Red Hat OpenShift GitOps (ArgoCD):

- **[MaaS GitOps Deployment README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/README.md)** — Environment-specific GitOps deployment structure (dev / staging / prod app-of-apps)
- **[MaaS Platform Deployment Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/DEPLOYMENT_GUIDE.md)** — Full operational runbook: step-by-step sync, troubleshooting, RBAC, and migration
- **[Model Registry GitOps README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/README.md)** — Architecture overview and prerequisites for automated model registration
- **[Model Registry GitOps — Quick Start](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/docs/QUICKSTART.md)** — Get from zero to a registered model in production
- **[Model Registry GitOps — Deployment Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/argocd/environments/DEPLOYMENT_GUIDE.md)** — Operational runbook for all three environments (dev / staging / prod)
- **[Model Registry GitOps — Verification Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/docs/VERIFICATION_GUIDE.md)** — Post-deployment health checks for the model registry pipeline
- **[Adding a Model to the Registry](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/models/ADDING_A_MODEL.md)** — How to register a new model via GitOps (create a `ModelVersion` YAML and commit)
- **[Model Deploy GitOps README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/README.md)** — Per-model ArgoCD Applications, multi-model design, and values file conventions
- **[Test Deployed Models](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/TEST_MODELS.md)** — Verify deployed models are healthy and serving inference requests through the gateway
- **[MaaS Config GitOps README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-config/README.md)** — ArgoCD manifests for `MaaSSubscription`, `MaaSAuthPolicy`, and `Group` governance resources

### Helm Chart Guides

| Chart | Purpose | Documentation |
|-------|---------|---------------|
| **maas-operators** | Installs OpenShift AI and dependent operators | [MaaS Operators Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/01-setup/MAAS_OPERATORS_GUIDE.md) |
| **maas-platform** | Configures DataScienceCluster and platform components | [Platform Customization Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/01-setup/MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md) · [Post-Sync Manual Steps](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/POST_SYNC_MANUAL_STEPS.md) · [Verification](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VERIFICATION.md) |
| **maas-runtime** | Deploys gateway, model registry, and storage integration | [Runtime Customization Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/01-setup/MAAS_RUNTIME_CUSTOMIZATION_GUIDE.md) |
| **maas-model-service** | Deploys individual AI models as inference services (Helm quick-start) | [Deploying Model Services](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/03-model-deployment/DEPLOYING_MODEL_SERVICES.md) |
| **maas-model-deploy** | Deploys LLM models via GitOps (`LLMInferenceService` + `MaaSModelRef`) | [maas-model-deploy README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/README.md) · [Vault/ESO Setup](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md) · [Changelog](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/CHANGELOG.md) |
| **maas-model-registry** | Deploys the Model Registry GitOps reconciler | [maas-model-registry README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/README.md) · [Vault/ESO Setup](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) |
| **maas-config** | Manages `MaaSSubscription`, `MaaSAuthPolicy`, and `Group` governance resources | [maas-config README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/README.md) · [Changelog](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/environments/CHANGELOG.md) |

### Getting Started
- [Getting Started Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/GETTING_STARTED.md) — Complete installation and setup guide
- [Deployment Order Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/01-setup/DEPLOYMENT_ORDER.md) — Step-by-step deployment sequence
- [Helm Version Management](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/VERSION_MANAGEMENT.md) — Versioning strategy and archive conventions for all Helm chart values files

### Configuration Guides
- [Model Catalog Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/02-model-catalog-and-registry/MODEL_CATALOG_GUIDE.md) — HuggingFace integration and model discovery
- [Registering Models](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/docs/02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md) — Model registration from catalog
- [Governance Configuration Guide](infoDocs/maas-config-governance-guide.md) — Subscription-based access control, API key lifecycle, and troubleshooting

#### ESO / Vault Secret Guides (Production Credential Management)

Use External Secrets Operator to keep all credentials out of Git. Vault secrets must be populated **before** the first ArgoCD sync for each chart.

| Chart | Secrets managed | Guide |
|---|---|---|
| **maas-platform** | `maas-db-config` (DB connection URL), `maas-postgres-creds` (in-cluster PG) | [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) |
| **maas-model-deploy** | S3 connection Secret + KServe `storage-config` Secret (per model) | [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md) |
| **maas-model-registry** | Git credentials (BuildConfig + CronJob) + Hugging Face token (Reconciler) | [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) |

### Examples
- [Fusion Agentic Assistance Platform](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/examples/Fusion-Agentic-Assistance-Platform/README.md) — Complete use case with multiple models
- [Model Registry Deployment](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/examples/model-registry-deployment/README.md) — Model registry entry examples
- [IBM Granite Models](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/models/granite/README.md) — Granite model definitions for the registry
- [Qwen Models](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/models/qwen/README.md) — Qwen model definitions for the registry
