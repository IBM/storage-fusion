# Quickstart: IBM Fusion Model-as-a-Service Platform - GitOps Deployment and Customization

Organizations adopting generative AI need secure, scalable, and governed infrastructure for hosting foundation models. Without a declarative, version-controlled approach, AI infrastructure deployments suffer from configuration drift, undocumented manual changes, and environments that diverge over time — making production incidents difficult to diagnose and reproduce. GitOps solves this by treating infrastructure as code: all configuration lives in Git, ArgoCD continuously reconciles the live cluster state to match it, and every change is auditable and reproducible.

IBM Fusion provides this foundation as a platform — hosting the cluster, storage services, and the GitOps tooling (Red Hat OpenShift GitOps / ArgoCD) that declaratively manages all workloads running on it.

This quickstart demonstrates how to deploy a Model-as-a-Service (MaaS) platform on IBM Fusion using Red Hat OpenShift GitOps (ArgoCD). All platform services — Red Hat OpenShift AI for model lifecycle and inference, Red Hat Connectivity Link for API gateway and routing, and IBM Fusion storage for model artifact storage — are declared in Git and continuously reconciled by ArgoCD running on the IBM Fusion cluster.

This guide is intended for platform engineers, DevOps teams, and AI infrastructure teams building production-grade AI serving platforms on IBM Fusion. By following it, you will:

- Deploy the MaaS platform on IBM Fusion using Red Hat OpenShift GitOps
- Configure and compose Red Hat OpenShift AI capabilities declaratively through ArgoCD
- Configure Red Hat Connectivity Link for API gateway, routing, and policy enforcement
- Configure automated model registry synchronization from Git
- Implement environment-specific configurations (dev, staging, prod)
- Compose GPU-backed inference services through declarative model manifests
- Establish continuous deployment workflows for AI model lifecycle
- Manage secrets securely with External Secrets Operator (ESO) and HashiCorp Vault — no credentials committed to Git
- Validate platform health and test inference endpoints

By the end of this guide, you will have a GitOps-managed MaaS environment on IBM Fusion capable of serving foundation models through secure, version-controlled, and auditable deployment pipelines.

---

## Deployment Options

The MaaS platform on IBM Fusion supports two deployment approaches. Choose based on your team's operational model:

| Deployment Method | Recommended For |
|---|---|
| **Helm** | Evaluation environments, proof-of-concepts, and teams preferring direct installation and manual lifecycle management |
| **GitOps** | Production environments and teams managing deployments through Git-based workflows and automation |

This guide covers the **GitOps-based deployment**. For a direct Helm-based deployment — including prerequisites, operator installation, and step-by-step configuration — see the [Quickstart: Model as a Service on IBM Fusion — Helm-based automation](https://community.ibm.com/community/user/blogs/harichandana-kotha/2026/05/27/quickstart-model-as-a-service-on-ibm-fusion).

For production deployments, GitOps is the recommended approach — configuration changes are tracked in Git, applied through Red Hat OpenShift GitOps (ArgoCD), and every deployment is declarative, auditable, and self-healing.

---

## Table of Contents

This document is organized into deployment, validation, and reference sections:

- [Deployment Options](#deployment-options)
- [IBM Fusion for AI Architecture - GitOps MaaS Platform](#ibm-fusion-for-ai-architecture---gitops-maas-platform)
- [What You'll Build](#what-youll-build)
- [Prerequisites](#prerequisites)
- [GitOps Deployment Workflow](#gitops-deployment-workflow)
- [Deployment Steps](#deployment-steps)
  - [Step 1: Fork and Clone the Repository](#step-1-fork-and-clone-the-storage-fusion-repository)
  - [Step 2: Configure ArgoCD RBAC](#step-2-configure-argocd-rbac)
  - [Step 3: Update Application Manifests](#step-3-update-application-manifests-with-custom-values)
  - [Step 4: Deploy the AppProject](#step-4-deploy-the-appproject)
  - [Step 5: Deploy the App-of-Apps](#step-5-deploy-the-app-of-apps)
  - [Step 6: Sync Applications](#step-6-sync-applications-production)
  - [Step 7: Verify Platform Deployment](#step-7-verify-platform-deployment)
  - [Step 8: Deploy Model Registry GitOps](#step-8-deploy-model-registry-gitops)
  - [Step 9: Verify Model Registration](#step-9-verify-model-registration)
  - [Step 10: Deploy Your First AI Model](#step-10-deploy-your-first-ai-model)
  - [Step 11: Test Your Model](#step-11-test-your-model)
- [What's Deployed](#whats-deployed)
- [Documentation](#documentation)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)
- [Summary](#summary)

> All reference material — internal guides and external upstream docs — is consolidated under [Documentation](#documentation).

---

## IBM Fusion for AI Architecture - GitOps MaaS Platform

```
┌────────────────────────────────────────────────────────────────┐
│         IBM Fusion for AI - GitOps MaaS Platform               │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌───────────────────────────────────────────────────────┐     │
│  │              GitOps Control Plane                     │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │     │
│  │  │ ArgoCD   │  │   Git    │  │App-of-   │  │ Sync   │ │     │
│  │  │  Apps    │  │  Repo    │  │  Apps    │  │ Waves  │ │     │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │     │
│  │  │   Auto   │  │  Manual  │  │  Health  │  │ Prune  │ │     │
│  │  │   Sync   │  │  Approval│  │  Checks  │  │ Policy │ │     │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │     │
│  └───────────────────────────────────────────────────────┘     │
│                              │                                 │
│                              ▼                                 │
│  ┌───────────────────────────────────────────────────────┐     │
│  │             MaaS Runtime Infrastructure               │     │
│  │          (OpenShift AI + Connectivity Link)           │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │     │
│  │  │Connecti- │  │   Rate   │  │   Auth   │  │ Model  │ │     │
│  │  │  vity    │  │  Policy  │  │(Keycloak)│  │Catalog │ │     │
│  │  │  Link    │  │          │  │          │  │        │ │     │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │     │
│  │  │   Model  │  │Monitoring│  │ Grafana  │  │ Tier   │ │     │
│  │  │ Registry │  │Prometheus│  │Dashboards│  │ Groups │ │     │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │     │
│  └───────────────────────────────────────────────────────┘     │
│                              │                                 │
│                              ▼                                 │
│  ┌───────────────────────────────────────────────────────┐     │
│  │         AI Model Inference Services (GitOps)          │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │     │
│  │  │ Model A  │  │ Model B  │  │ Model C  │  │Model D │ │     │
│  │  │All Tiers │  │Premium+  │  │Enterprise│  │Custom  │ │     │
│  │  │  (vLLM)  │  │  (TGI)   │  │ (vLLM)   │  │(Custom)│ │     │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │     │
│  │  • Declarative model definitions in Git               │     │
│  │  • Automated model registration and deployment        │     │
│  │  • Version-controlled inference configurations        │     │
│  └───────────────────────────────────────────────────────┘     │
│                              │                                 │
│                              ▼                                 │
│  ┌───────────────────────────────────────────────────────┐     │
│  │                  AI Applications                      │     │
│  │        ┌──────────┐  ┌──────────┐  ┌──────────┐       │     │
│  │        │  Fusion  │  │ Chatbot  │  │  Custom  │       │     │
│  │        │Assistant │  │    UI    │  │   Apps   │       │     │
│  │        │          │  │          │  │          │       │     │
│  │        └──────────┘  └──────────┘  └──────────┘       │     │
│  └───────────────────────────────────────────────────────┘     │
│                              │                                 │
│                              ▼                                 │
│  ┌───────────────────────────────────────────────────────┐     │
│  │      IBM Fusion Storage — Foundation Layer            │     │
│  │         (OpenShift Data Foundation - ODF)             │     │
│  │      ┌──────────────┐  ┌─────────────┐                │     │
│  │      │    Model     │  │   Model     │                │     │
│  │      │  Artifacts   │  │  Registry   │                │     │
│  │      │   Storage    │  │   Backend   │                │     │
│  │      └──────────────┘  └─────────────┘                │     │
│  │  • Auto-provisioned buckets via ObjectBucketClaim     │     │
│  │  • GitOps-managed storage configurations              │     │
│  │  • Backing service for inference and registry layers  │     │
│  └───────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────┘
```


## What You'll Build

By completing this quickstart, you will deploy a Model-as-a-Service platform on IBM Fusion using Red Hat OpenShift GitOps (ArgoCD). The platform composes:

- **Red Hat OpenShift AI** for model lifecycle, registry, and inference
- **Red Hat Connectivity Link** for API gateway, routing, rate limiting, and policy enforcement (powered by Kuadrant)
- **IBM Fusion storage** for scalable, S3-compatible model artifact and registry storage

All platform capabilities are declared in Git and continuously reconciled by ArgoCD running on the IBM Fusion cluster. The deployment includes:

- **GitOps Infrastructure**: ArgoCD Applications with App-of-Apps pattern
- **Declarative Infrastructure**: All platform components defined in Git
- **Automated Deployments**: ArgoCD-managed continuous deployment with sync waves
- **Multi-Environment Support**: Separate dev, staging, and production configurations
- **Model Registry GitOps**: Automated model registration from Git repositories
- **GPU-backed Inference**: LLM-D runtimes managed through GitOps
- **Version Control**: Full audit trail of all infrastructure and model changes
- **Self-Healing**: Automatic drift detection and correction via ArgoCD reconciliation
- **Progressive Rollouts**: Controlled deployment ordering with sync wave sequencing
- **Secure Secret Management**: External Secrets Operator (ESO) syncs database passwords, S3 credentials, and Git tokens from HashiCorp Vault — no plaintext credentials in Git

Together, these platform capabilities — composed and managed through Red Hat OpenShift GitOps on IBM Fusion — provide a production-ready, declarative infrastructure for running and managing enterprise AI inference services with full version control and audit trails.

This quickstart is intended for platform engineers and DevOps teams building production-grade AI serving platforms on IBM Fusion with GitOps workflows.

---

## Prerequisites

Before you begin, verify that the target environment satisfies the platform, GPU, CLI, and storage requirements listed below.

### Required

- **Red Hat OpenShift 4.20+** with cluster-admin access
- **Red Hat OpenShift GitOps operator** installed and configured — deploys ArgoCD into the `openshift-gitops` namespace. See [Quickstart: GitOps (ArgoCD) on IBM Fusion](https://community.ibm.com/community/user/blogs/christo-abraham/2026/05/27/fusion-gitops-quickstart) for installation steps
- **GPU nodes** with at least one NVIDIA GPU-capable worker
- **OpenShift CLI (`oc`)** — [Install oc](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)
- **ArgoCD CLI (`argocd`) v2.9+** — [Install argocd](https://argo-cd.readthedocs.io/en/stable/cli_installation/)
- **GitHub account with write access** to a fork of the [storage-fusion](https://github.com/IBM/storage-fusion) repository — you must fork and push manifest changes; read-only access is not sufficient

### External Secrets Operator — ESO (Recommended for Production)

For production deployments, use External Secrets Operator to keep all credentials out of Git. ESO syncs secrets from HashiCorp Vault into the cluster at sync time — database passwords, S3 access keys, and Git tokens are never written to any YAML file.

**Prerequisites:**
- **External Secrets Operator (ESO)** installed in the cluster
- **HashiCorp Vault** (or compatible backend) with a `ClusterSecretStore` named `vault-backend` ready and `Ready`
- Vault secrets **must be populated before the first ArgoCD sync** — ESO resolves `ExternalSecret` CRs at sync time; missing paths cause `SecretSyncedError`

> **If ESO is not available**, fall back to the manual credential methods shown in each step below. For dev/quick-start environments this is fine; for production use ESO.

Per-chart setup guides (read before syncing the corresponding ArgoCD Application):

| Chart | Secrets managed | Guide |
|---|---|---|
| **maas-platform** | `maas-db-config` (DB connection URL), `maas-postgres-creds` | [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) |
| **maas-model-deploy** | S3 connection Secret + KServe `storage-config` Secret (per model) | [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md) |
| **maas-model-registry** | Git credentials + Hugging Face token | [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) |

### GPU Enablement (Required for LLM Serving)

If serving GPU-backed models such as vLLM-based LLMs, the following components must be installed:
- Node Feature Discovery (NFD) Operator for hardware detection
- NVIDIA GPU Operator
- Worker nodes automatically labelled by the NVIDIA GPU Operator (e.g., `nvidia.com/gpu.present=true`)

Verify GPU availability:
```bash
oc describe node <worker-node> | grep -i gpu
```

### Storage Options

Choose one supported S3-compatible storage backend for registry artifacts and related data:

> **Recommended:** OpenShift Data Foundation (ODF) with NooBaa is the default storage backend for IBM Fusion clusters and requires no additional configuration. Use AWS S3, MinIO, or Ceph as alternatives only if ODF is not available on your cluster.

- **OpenShift Data Foundation (ODF)** with S3-compatible storage (NooBaa) — recommended default for IBM Fusion
- **AWS S3 or other S3-compatible storage** such as MinIO or Ceph

### Verify Your Environment

```bash
# Check OpenShift version (should be 4.20+)
oc version

# Verify cluster-admin access
oc auth can-i '*' '*' --all-namespaces

# Check OpenShift GitOps installation
oc get pods -n openshift-gitops

# Verify ArgoCD is accessible
argocd version

# Check GPU availability (should show at least 1 node)
oc get nodes -l nvidia.com/gpu.present=true
```

---

## GitOps Deployment Workflow

The following diagram shows the end-to-end GitOps flow — from a Git commit to a live model endpoint — and how each layer of the platform is involved.

```
┌──────────────────────────────────────────────────────────────────────┐
│           GitOps Deployment Flow — IBM Fusion MaaS Platform          │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Developer / Platform Engineer                                      │
│          │                                                           │
│          │  git commit + push (manifests / model definitions)        │
│          ▼                                                           │
│   ┌──────────────────────────────────┐                               │
│   │  Git Repository (storage-fusion) │                               │
│   │  • Platform manifests            │                               │
│   │  • Model registry definitions    │                               │
│   │  • Environment values files      │                               │
│   └──────────────┬───────────────────┘                               │
│                  │  ArgoCD watches & reconciles                      │
│                  ▼                                                   │
│   ┌──────────────────────────────────────────────────────────┐       │
│   │       Red Hat OpenShift GitOps (ArgoCD)                  │       │
│   │       running on IBM Fusion cluster                      │       │
│   │  • App-of-Apps pattern                                   │       │
│   │  • Sync waves (-10 → 0 → 50 → 100)                       │       │
│   │  • Health checks & drift correction                      │       │
│   └───────────────┬──────────────────────────────────────────┘       │
│                   │  deploys & configures                            │
│          ┌────────┴─────────┐                                        │
│          ▼                  ▼                                        │
│  ┌───────────────┐  ┌────────────────────────────────┐               │
│  │ Red Hat       │  │ Red Hat Connectivity Link      │               │
│  │ OpenShift AI  │  │ • Gateway API routing          │               │
│  │ • Operators   │  │ • Rate limiting policies       │               │
│  │ • DataScience │  │ • Auth policies (Keycloak)     │               │
│  │   Cluster     │  │ • TLS / cert management        │               │
│  │ • Model       │  └──────────────┬─────────────────┘               │
│  │   Registry    │                 │                                 │
│  └───────┬───────┘                 │  routes requests via            │
│          │  serves models via      │  Gateway API                    │
│          ▼                         ▼                                 │
│   ┌──────────────────────────────────────────────────────────┐       │
│   │              Model Inference Endpoints                   │       │
│   │   POST /v1/completions    POST /v1/chat/completions      │       │
│   │   (vLLM / TGI runtimes — GPU-backed, KServe-managed)     │       │
│   └──────────────────────────────────────────────────────────┘       │
│                              │                                       │
│                              │  model artifacts pulled from          │
│                              ▼                                       │
│   ┌──────────────────────────────────────────────────────────┐       │
│   │         IBM Fusion Storage — Foundation Layer            │       │
│   │         (OpenShift Data Foundation / ODF / NooBaa)       │       │
│   │   • Model artifact buckets (ObjectBucketClaim)           │       │
│   │   • Model Registry backend storage                       │       │
│   │   • GitOps-managed, auto-provisioned                     │       │
│   └──────────────────────────────────────────────────────────┘       │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Sync Wave Strategy

ArgoCD deploys components in a specific order using sync waves to respect dependencies:

- **Wave -10**: Infrastructure setup — AppProject and cluster RBAC
- **Wave 0**: Operator installations — OpenShift AI, Connectivity Link, Cert-Manager, LWS
- **Wave 50**: Platform configuration — DataScienceCluster, Connectivity Link instance, LWS instance
- **Wave 100**: Runtime services — Gateway, Model Registry, storage
- **Independent**: Model Registry GitOps — automated model registration via CronJob

---

## Deployment Steps

> **Environment note:** This guide uses the `prod` environment throughout as the example. For `dev` or `staging`, replace `prod` in all paths, filenames, and namespace references — for example `environments/prod/` → `environments/dev/` and `fusion-maas-operators-prod` → `fusion-maas-operators-dev`.

The following procedure walks through GitOps-based deployment of the MaaS platform.

### Step 1: Fork and Clone the Storage Fusion Repository

The quickstart examples reference configurations from the storage-fusion repository. Fork this repository to your GitHub account and clone it locally.

**Fork the repository:** Fork the [storage-fusion](https://github.com/IBM/storage-fusion) repository

**Clone the forked copy of this repository:**

```bash
git clone git@github.com:<your-username>/storage-fusion.git
cd storage-fusion/AI/quickstarts/model-as-a-service
```

**Note:** The `AI/quickstarts/model-as-a-service-rhoai-3.5` directory is located under the `AI/` parent directory within the storage-fusion repository (path: `storage-fusion/AI/AI/quickstarts/model-as-a-service-rhoai-3.5`).

### Step 2: Configure ArgoCD RBAC

Apply cluster-level RBAC permissions for ArgoCD to manage MaaS resources:

```bash
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/argocd-cluster-rbac.yaml
```

This creates:
- `ClusterRole`: `argocd-maas-cluster-admin` with permissions for DataScienceCluster, Kuadrant, ModelRegistry, Gateway API, and other MaaS resources
- `ClusterRoleBinding`: Binds the role to the ArgoCD application controller service account

**Verify RBAC:**
```bash
oc get clusterrole argocd-maas-cluster-admin
oc get clusterrolebinding argocd-maas-cluster-admin
```

### Step 3: Update Application Manifests with Custom Values

Before deploying, update all application manifests in `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/applications/` to reference your custom values file.

**Edit each application file** (`01-maas-operators-prod.yaml`, `02-maas-platform-prod.yaml`, `03-maas-runtime-prod.yaml`) and make two changes:

1. **Update the repository URL** to point to your forked repository
2. **Append the custom values file** to the `helm.valueFiles` section

**Example for `01-maas-operators-prod.yaml`:**
```yaml
spec:
  source:
    repoURL: https://github.com/<your-username>/storage-fusion.git  # Update this
    targetRevision: master  # Or your branch name
    path: AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-operators
    helm:
      valueFiles:
        - values.yaml
        - environments/prod/values.yaml
        - ../../../examples/Fusion-Agentic-Assistance-Platform/values.yaml  # Add this line
```

**Apply both changes to all three application files:**
- `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/applications/01-maas-operators-prod.yaml`
- `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/applications/02-maas-platform-prod.yaml`
- `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/applications/03-maas-runtime-prod.yaml`

**Commit and push your changes to Git:**

Since this is a GitOps deployment, ArgoCD needs to pull the updated manifests from your Git repository. Commit and push your changes:

```bash
git add AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/applications/
git commit -m "Add custom values file to MaaS GitOps applications"
git push
```

**Important:** Make sure you push to your forked repository. ArgoCD will sync from the Git repository URL specified in the Application manifests.

### Step 4: Deploy the AppProject

Create the ArgoCD AppProject for the production environment:

```bash
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/appproject-prod.yaml
```

The AppProject defines:
- Source repositories
- Destination namespaces
- Resource whitelists
- RBAC policies

**Verify AppProject:**
```bash
oc get appproject -n openshift-gitops
```

**Note:** For other environments (dev, staging), you can find the corresponding AppProject files in `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/`.

### Step 5: Deploy the App-of-Apps

Deploy the main orchestrator application that manages all MaaS components:

```bash
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/prod/00-prod-app-of-apps.yaml
```

This creates the `fusion-maas-platform-orchestrator` Application that manages three child applications:
- `fusion-maas-operators-{env}` (Wave 0)
- `fusion-maas-platform-config-{env}` (Wave 50)
- `fusion-maas-runtime-{env}` (Wave 100)

**Verify App-of-Apps:**
```bash
# Check the orchestrator application
oc get application.argoproj.io -n openshift-gitops | grep fusion-maas-platform-orchestrator

# View in ArgoCD UI
argocd app list
```

> **Note:** The orchestrator Application is configured with **manual sync** for child applications. Syncing the orchestrator does not automatically sync child applications — you control this explicitly in Step 6. If you have modified the sync policy to `automated`, child applications may sync immediately without waiting for Step 6.

### Step 6: Sync Applications (Production)

Production environments use **manual sync** for change control. Sync each application in order:

> The `--prune` flag removes cluster resources that are no longer present in your Git repository. Ensure your Git state is complete and correct before syncing with this flag, especially in production environments.

#### 6.1: Sync MaaS Operators

```bash
# Via ArgoCD CLI
argocd app sync fusion-maas-operators-prod --prune

# Or via OpenShift GitOps UI:
# 1. Navigate to OpenShift GitOps in the console
# 2. Find fusion-maas-operators-prod application
# 3. Click Sync → Synchronize
```

**Wait for operators to be ready:**
```bash
# Check operator subscriptions
oc get csv -n redhat-ods-operator | grep rhods-operator
oc get csv -n kuadrant-system

# Wait for OpenShift AI operator
oc wait --for=condition=Available deployment/rhods-operator \
  -n redhat-ods-operator --timeout=600s
```

> If this wait times out, check the operator status and events:
> ```bash
> oc describe subscription rhods-operator -n redhat-ods-operator
> oc get events -n redhat-ods-operator --sort-by='.lastTimestamp' | tail -20
> ```

**Expected Output:**
```text
NAME                           DISPLAY                    VERSION   PHASE
rhods-operator.3.4.1          Red Hat OpenShift AI       3.4.1    Succeeded
kuadrant-operator.v0.8.0      Kuadrant Operator          0.8.0     Succeeded
cert-manager.v1.14.0          Cert Manager               1.14.0    Succeeded
leader-worker-set.v0.3.0      Leader Worker Set          0.3.0     Succeeded
```

#### 6.2: Sync MaaS Platform

> **If using ESO for database credentials:** Populate Vault secrets before this sync. See [maas-platform VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md). Verify the `ClusterSecretStore` named `vault-backend` is `Ready` before syncing.

```bash
# Via ArgoCD CLI
argocd app sync fusion-maas-platform-config-prod --prune

# Or via OpenShift GitOps UI
```

**Wait for platform to be ready:**
```bash
# Check DataScienceCluster
oc get datasciencecluster

# Wait for DSC to be ready
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=900s
```

> If this wait times out, check the DataScienceCluster status and events:
> ```bash
> oc describe datasciencecluster default-dsc
> oc get events -n redhat-ods-operator --sort-by='.lastTimestamp' | tail -20
> ```

**Expected Output:**
```text
NAME          AGE   PHASE   CREATED AT
default-dsc   5m    Ready   2024-01-15T10:30:00Z
```

> **Post-sync manual steps required** after `maas-platform` syncs. These steps configure resources that ArgoCD cannot own declaratively. Run them in order before proceeding to Step 6.3:
>
> 1. **Enable User Workload Monitoring** — required for MaaS metrics; without it, MaaS shows `Degraded` status
> 2. **Configure Authorino TLS** — required for gateway authentication
> 3. **Patch `OdhDashboardConfig`** — enable MaaS dashboard features (`modelAsService`, `genAiStudio`, `maasAuthPolicies`)
>
> Full commands and verification steps: [POST_SYNC_MANUAL_STEPS.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/POST_SYNC_MANUAL_STEPS.md)
>
> Run the full verification checklist afterwards: [VERIFICATION.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VERIFICATION.md)

#### 6.3: Sync MaaS Runtime

```bash
# Via ArgoCD CLI
argocd app sync fusion-maas-runtime-prod --prune

# Or via OpenShift GitOps UI
```

**Wait for runtime to be ready:**
```bash
# Check Model Registry
oc get modelregistry.modelregistry.opendatahub.io -n rhoai-model-registries

# Verify object storage
oc get objectbucketclaim -n rhoai-model-registries
```

**Expected Output:**
```text
NAME             AVAILABLE   AGE
model-registry   True        6h34m
```

### Step 7: Verify Platform Deployment

Check the health of all applications:

```bash
# Via ArgoCD CLI
argocd app list | grep fusion-maas

# Check application health
argocd app get fusion-maas-platform-orchestrator-prod

# Via kubectl
oc get application.argoproj.io -n openshift-gitops | grep fusion-maas
```

**Expected Output:**
```text
NAME                                      SYNC STATUS   HEALTH STATUS
fusion-maas-platform-orchestrator-prod    Synced        Healthy
fusion-maas-operators-prod                Synced        Healthy
fusion-maas-platform-config-prod          Synced        Healthy
fusion-maas-runtime-prod                  Synced        Healthy
```

---

> **Platform configuration complete.** At this stage, the AI platform has been configured on IBM Fusion using Red Hat OpenShift AI and Red Hat Connectivity Link. All operators, platform services, gateway, and storage components are healthy and GitOps-managed. The following steps enable model lifecycle automation through GitOps — registering, deploying, and serving foundation models.

---

### Step 8: Deploy Model Registry GitOps

Enable automated model registration from Git repositories:

#### 8.1: Deploy Model Registry AppProject

Create the ArgoCD AppProject for model registry:

```bash
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/argocd/environments/prod/appproject-prod.yaml
```

This creates the `fusion-model-registry-gitops-prod` namespace and AppProject.

#### 8.2: Create Git Credentials Secret

The model reconciler needs Git credentials to clone model definitions from your private repository. Choose the method that matches your environment.

**Option A — ESO / Vault (production, recommended)**

Store credentials in Vault before the first sync, then enable ESO in the values overlay. No credentials touch Git or the cluster manifest:

```bash
# Store Git credentials in Vault
vault kv put secret/maas/model-registry/git \
  username="<your-github-username>" \
  password="<your-github-token>"
```

In `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/environments/prod/values.yaml`, set:

```yaml
gitCredentials:
  externalSecret:
    enabled: true
    refreshInterval: 24h
    secretStoreRef:
      name: vault-backend
      kind: ClusterSecretStore
    remoteRef:
      key: maas/model-registry/git
```

Full walkthrough: [maas-model-registry VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) — Scenario A.

**Option B — kubectl (development / non-production)**

```bash
# Write credentials to temp files (values are not echoed to terminal history)
echo -n "<your-github-username>" > ./git-username.txt
echo -n "<your-github-token>" > ./git-token.txt

# Create the secret from files
oc create secret generic git-credentials \
  --from-file=username=./git-username.txt \
  --from-file=password=./git-token.txt \
  --namespace=fusion-model-registry-gitops-prod

# Remove temp files immediately
rm ./git-username.txt ./git-token.txt
```

> The secret must be created in the `fusion-model-registry-gitops-prod` namespace **before** the ArgoCD Application syncs.

#### 8.3: Update and Deploy Model Registry Application

Update the application manifest with your forked repository URL in `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/argocd/environments/prod/application.yaml`:

```yaml
spec:
  source:
    repoURL: https://github.com/<your-username>/storage-fusion.git
    targetRevision: master  # or your branch name
```

Push the changes to Git, then register the Application with ArgoCD using a direct apply. This is a one-time bootstrap — ArgoCD cannot sync an Application it does not yet know about. Once registered, ArgoCD takes over and all subsequent syncs go through GitOps:

```bash
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/argocd/environments/prod/application.yaml
```

#### 8.4: Sync Model Registry Application

```bash
# Via ArgoCD CLI
argocd app sync fusion-model-registry-gitops-prod --prune

# Or via OpenShift GitOps UI
```

**Verify Model Registry GitOps:**
```bash
# Check pods
oc get pods -n fusion-model-registry-gitops-prod

# Check CronJob for periodic sync
oc get cronjob -n fusion-model-registry-gitops-prod

# View reconciler logs
oc logs -n fusion-model-registry-gitops-prod -l app=model-reconciler --tail=50
```

**Expected Output:**
```text
NAME                                READY   STATUS      RESTARTS   AGE
model-reconciler-1-build            0/1     Completed   0          5m
model-reconciler-666576944c-542bb   1/1     Running     0          5m
model-sync-29710880-d4pr2           0/1     Completed   0          3m
```

The Model Registry GitOps system will:
- Watch model definitions in `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/models/`
- Download models from HuggingFace or other sources
- Upload artifacts to S3 object storage
- Register models in the Model Registry
- Run periodic synchronization via CronJob

### Step 9: Verify Model Registration

**Access Model Registry via RHOAI UI:**

1. Navigate to Red Hat OpenShift AI Dashboard
2. Go to **AI hub** → **Models** → **Registry** tab
3. Select **model-registry** from the dropdown
4. Verify registered models are displayed

**Available Models:**

The following models are pre-configured in `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/models/`:

| Model ID | Display Name |
|---|---|
| `gpt-oss-20b` | GPT-OSS 20B |
| `qwen3-8b-fp8-dynamic` | Qwen3 8B FP8 Dynamic |
| `granite-4.1-8b` | IBM Granite 4.1 8B |
| `tiny-llama` | TinyLlama Test Model |


---

### Step 10: Deploy Your First AI Model

With the platform running and models registered, deploy an inference service using GitOps. ArgoCD manages the full lifecycle — commit a manifest to Git and ArgoCD reconciles it on the cluster. Manual sync is required in production so every deployment is explicit and auditable.

#### 10.1: Verify Prerequisites

Before deploying a model, confirm that the MaaS runtime and model registration are healthy:

```bash
# Confirm the MaaS runtime (Gateway + ModelRegistry) is healthy
oc get application fusion-maas-runtime-prod -n openshift-gitops

# Confirm model is registered in the Model Registry
oc get registeredmodel -n rhoai-model-registries

# Confirm ArgoCD pods are running
oc get pods -n openshift-gitops
```

**Expected Output:**
```text
NAME                         SYNC STATUS   HEALTH STATUS
fusion-maas-runtime-prod     Synced        Healthy
```

#### 10.2: Configure Model Values Files

Each model has its own per-model values file under `environments/prod/`. Do **not** edit the shared `values.yaml` directly — only override what differs from the base defaults in the model-specific file.

**Values file per model (production):**

| Model | Values file |
|---|---|
| `gpt-oss-20b` | [`environments/prod/values-gpt-oss-20b.yaml`](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/prod/values-gpt-oss-20b.yaml) |
| `tiny-llama-test` | [`environments/prod/values-tiny-llama.yaml`](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/prod/values-tiny-llama.yaml) |

Each file overrides only the model-specific keys — `model.name`, `model.displayName`, `s3.modelPath`, and resource allocation. Shared S3 settings (`endpoint`, `region`, `bucket`) are inherited from the base [`values.yaml`](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/values.yaml) and only overridden if they differ for a specific model.

**Option A — ESO / Vault (production, recommended)**

Store all five S3 fields in Vault at `secret/maas/model-deploy/<model-name>/s3` and enable `s3.externalSecret.enabled: true`. No credentials are committed to Git. See [maas-model-deploy VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md) — **Vault secrets must exist before the first ArgoCD sync.**

```bash
# Store S3 credentials in Vault
vault kv put secret/maas/model-deploy/gpt-oss-20b/s3 \
  access_key_id="<your-s3-access-key-id>" \
  secret_access_key="<your-s3-secret-access-key>" \
  endpoint="https://s3.openshift-storage.svc:443" \
  region="us-east-1" \
  bucket="<your-bucket-name>"
```

**Example — `values-gpt-oss-20b.yaml` with ESO:**

```yaml
model:
  name: gpt-oss-20b
  displayName: "GPT-OSS-20b"
  namespace: deploy-models

s3:
  modelPath: "gpt-oss-20b-hf/1.0.0"   # still required — used for the model URI
  verifySSL: "0"                        # still required — not stored in Vault

  externalSecret:
    enabled: true
    refreshInterval: 1h
    secretStoreRef:
      name: vault-backend               # must match your ClusterSecretStore name
      kind: ClusterSecretStore
    remoteRef:
      key: maas/model-deploy/gpt-oss-20b/s3

resources:
  limits:
    cpu: "2"
    memory: 4Gi
    nvidia.com/mig-3g.20gb: "1"
  requests:
    cpu: "2"
    memory: 4Gi
    nvidia.com/mig-3g.20gb: "1"
```

**Option B — Manual credentials (dev / quick-start only)**

```yaml
model:
  name: gpt-oss-20b
  displayName: "GPT-OSS-20b"
  namespace: deploy-models

s3:
  modelPath: "gpt-oss-20b-hf/1.0.0"
  accessKeyId: ""                       # supply via --helm-set at sync time
  secretAccessKey: ""                   # supply via --helm-set at sync time

resources:
  limits:
    cpu: "2"
    memory: 4Gi
    nvidia.com/mig-3g.20gb: "1"
  requests:
    cpu: "2"
    memory: 4Gi
    nvidia.com/mig-3g.20gb: "1"
```

To add a new model, create a new `values-<model-name>.yaml` in `environments/prod/` following the same structure. See [`environments/CHANGELOG.md`](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/environments/CHANGELOG.md) for the full add/remove procedure.

#### 10.3: Update the Application Manifests

Production uses one ArgoCD `Application` per model. Each Application points to its own model values file. The prod directory contains:

```text
deploy/gitops/maas-model-deploy/environments/prod/
├── application-gpt-oss-20b.yaml     # ArgoCD Application for gpt-oss-20b
└── application-tiny-llama.yaml      # ArgoCD Application for tiny-llama
```

Open the Application manifest for your model (e.g. [`environments/prod/application-gpt-oss-20b.yaml`](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/environments/prod/application-gpt-oss-20b.yaml)) and update the two source fields to point to your forked repository:

```yaml
spec:
  source:
    repoURL: https://github.com/<your-username>/storage-fusion.git  # your forked repo
    targetRevision: master                                           # your branch or tag
    path: AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy
    helm:
      valueFiles:
        - values.yaml
        - environments/prod/values-gpt-oss-20b.yaml   # per-model values file
  destination:
    server: https://kubernetes.default.svc
    namespace: deploy-models
```

Repeat for each model's Application manifest, then commit and push:

```bash
git add AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/environments/prod/
git commit -m "Configure prod model deployment applications"
git push
```

#### 10.4: Deploy the AppProject and Applications

The AppProject is shared across all prod model Applications and only needs to be applied once. Each model then gets its own Application manifest:

```bash
# 1. Create the shared AppProject (RBAC) — apply once for all prod models
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/environments/prod/appproject-prod.yaml

# 2. Register each model's Application with ArgoCD
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/environments/prod/application-gpt-oss-20b.yaml
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/environments/prod/application-tiny-llama.yaml
```

Verify ArgoCD has registered both Applications:

```bash
oc get applications.argoproj.io -n openshift-gitops | grep fusion-maas-model-deploy
```

**Expected Output:**
```text
fusion-maas-model-deploy-prod-gpt-oss-20b   OutOfSync   Healthy
fusion-maas-model-deploy-prod-tiny-llama    OutOfSync   Healthy
```

`OutOfSync` is expected before the first sync — the resources do not exist on the cluster yet.

#### 10.5: Sync the Applications

Production uses **manual sync** for change control.

**Option A — ESO / Vault (recommended)**

If you configured `s3.externalSecret.enabled: true` in the values file and pre-populated Vault in Step 10.2, sync without any credential flags. ESO creates the S3 secrets automatically at sync time:

```bash
argocd app sync fusion-maas-model-deploy-prod-gpt-oss-20b
argocd app sync fusion-maas-model-deploy-prod-tiny-llama
```

Verify ESO created the secrets after sync:

```bash
oc get externalsecret -n deploy-models
oc get secret deploy-models-connection storage-config -n deploy-models
```

**Option B — Manual credentials at sync time (dev / quick-start only)**

Pass credentials as Helm parameters at sync time — they are not stored in Git:

```bash
# Sync gpt-oss-20b — supply S3 credentials at sync time
argocd app sync fusion-maas-model-deploy-prod-gpt-oss-20b \
  --helm-set s3.accessKeyId=<your-access-key> \
  --helm-set s3.secretAccessKey=<your-secret-key>

# Sync tiny-llama — supply S3 credentials at sync time
argocd app sync fusion-maas-model-deploy-prod-tiny-llama \
  --helm-set s3.accessKeyId=<your-access-key> \
  --helm-set s3.secretAccessKey=<your-secret-key>
```

Alternatively, sync through the **OpenShift GitOps UI**:
1. Open the ArgoCD console
2. Locate `fusion-maas-model-deploy-prod-gpt-oss-20b`
3. Click **Diff** to review changes
4. Click **Sync → Parameters** and add `s3.accessKeyId` and `s3.secretAccessKey` as Helm parameter overrides
5. Click **Synchronize**

Repeat for each model Application.

#### 10.6: Monitor the Deployment

Track the inference services as they initialise. Model pods require GPU allocation and image pull time before becoming ready — allow up to 10 minutes for large models:

```bash
# Stream status changes for all inference services
oc get llminferenceservice -n deploy-models -w

# Check ArgoCD sync and health status for all model applications
oc get applications.argoproj.io -n openshift-gitops | grep fusion-maas-model-deploy

# Check model pods
oc get pods -n deploy-models

# View model container logs (replace <model-name> as needed)
oc logs -n deploy-models -l serving.kserve.io/inferenceservice=gpt-oss-20b -c kserve-container -f
```

**Expected Output:**
```
NAME              URL                                                 READY   REASON   AGE
gpt-oss-20b       http://10.x.x.x/deploy-models/gpt-oss-20b         True             8m
tiny-llama-test   http://10.x.x.x/deploy-models/tiny-llama-test     True             8m
```

If the `READY` column shows `False` after 10 minutes, see the [Troubleshooting](#troubleshooting) section for diagnostic commands.

---

### Step 11: Test Your Model

Once the inference service reports `READY=True`, validate the deployment end-to-end with live API calls.

#### 11.1: Resolve the Gateway Endpoint

The gateway route name depends on the `ingressMode` configured in the `maas-platform` Helm chart:

| `ingressMode` | Route name | Host pattern |
|---|---|---|
| `route` (cloud / ROSA) | `openshift-ai-inference` | `openshift-ai-inference-openshift-ingress.apps.<domain>` |
| `clusterip` (on-prem / bare-metal) | `maas-gateway-route` | `maas.apps.<domain>` |

```bash
# clusterip mode (on-prem / bare-metal — default prod configuration)
GATEWAY_HOST=$(oc get route maas-gateway-route -n openshift-ingress -o jsonpath='{.spec.host}')

# route mode (cloud / ROSA)
# GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')

echo "Gateway: https://${GATEWAY_HOST}"

# Retrieve a short-lived OpenShift token for authentication
TOKEN=$(oc whoami -t)
```

**Expected Output (clusterip mode):**
```text
Gateway: https://maas.apps.<cluster-domain>
```

#### 11.2: Confirm the Inference Services are Ready

```bash
# Check all inference services in the namespace
oc get llminferenceservice -n deploy-models
```

**Expected Output:**
```text
NAME              URL                                                 READY   REASON   AGE
gpt-oss-20b       http://10.x.x.x/deploy-models/gpt-oss-20b         True             ...
tiny-llama-test   http://10.x.x.x/deploy-models/tiny-llama-test     True             ...
```

Once both show `READY=True`, verify the model list endpoint for each model:

```bash
# Pattern: https://<gateway-host>/<namespace>/<model-name>/v1/models
curl -k "https://${GATEWAY_HOST}/deploy-models/gpt-oss-20b/v1/models" \
  -H "Authorization: Bearer ${TOKEN}"

curl -k "https://${GATEWAY_HOST}/deploy-models/tiny-llama-test/v1/models" \
  -H "Authorization: Bearer ${TOKEN}"
```

**Expected Output (per model):**
```json
{
  "object": "list",
  "data": [
    {
      "id": "gpt-oss-20b",
      "object": "model",
      "owned_by": "vllm",
      "max_model_len": 131072
    }
  ]
}
```

#### 11.3: Send a Completions Request

```bash
# Pattern: https://<gateway-host>/<namespace>/<model-name>/v1/completions
curl -k -X POST "https://${GATEWAY_HOST}/deploy-models/gpt-oss-20b/v1/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "prompt": "Write a Python function to calculate fibonacci numbers:",
    "max_tokens": 50,
    "temperature": 0.7
  }'
```

**Expected Output:**
```json
{
  "id": "cmpl-...",
  "object": "text_completion",
  "model": "gpt-oss-20b",
  "choices": [
    {
      "text": " `def fibonacci(n: int) -> int: pass` ...",
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 9,
    "completion_tokens": 50,
    "total_tokens": 59
  }
}
```

#### 11.4: Send a Chat Completions Request

```bash
# Pattern: https://<gateway-host>/<namespace>/<model-name>/v1/chat/completions
curl -k -X POST "https://${GATEWAY_HOST}/deploy-models/gpt-oss-20b/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [
      {"role": "system", "content": "You are a helpful AI assistant."},
      {"role": "user", "content": "What is IBM Fusion and how does it integrate with OpenShift AI?"}
    ],
    "max_tokens": 200,
    "temperature": 0.7
  }'
```

**Expected Output:**
```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "model": "gpt-oss-20b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "IBM Fusion is ..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 83,
    "completion_tokens": 200,
    "total_tokens": 283
  }
}
```

#### 11.5: Verify ArgoCD Health

Each model is deployed as its own ArgoCD Application named `fusion-maas-model-deploy-prod-<model-name>`. Confirm each is healthy:

```bash
# List all model deploy applications
oc get applications.argoproj.io -n openshift-gitops | grep fusion-maas-model-deploy

# Check sync and health status for a specific model
oc get applications.argoproj.io fusion-maas-model-deploy-prod-gpt-oss-20b \
  -n openshift-gitops \
  -o jsonpath='{.status.sync.status} {.status.health.status}'
```

**Expected Output:**
```text
NAME                                        SYNC STATUS   HEALTH STATUS
fusion-maas-model-deploy-prod-gpt-oss-20b   Synced        Healthy
fusion-maas-model-deploy-prod-tiny-llama    Synced        Healthy
```

#### 11.6: Verify HTTPRoute and Gateway

```bash
# Check HTTPRoutes are created for each model
oc get httproute -n deploy-models

# Verify the gateway is programmed and has an address
oc get gateway -n openshift-ingress
```

**Expected Output:**
```text
NAME                           HOSTNAMES   AGE
gpt-oss-20b-kserve-route                   ...
tiny-llama-test-kserve-route               ...

NAME                  CLASS             ADDRESS    PROGRAMMED
maas-default-gateway  openshift-default 10.x.x.x   True
```

For the full testing runbook — including rate-limit validation, token refresh, and rollback procedures — see [`deploy/gitops/maas-model-deploy/TEST_MODELS.md`](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/TEST_MODELS.md).

---

## What's Deployed

After completing the quickstart, the environment includes the following GitOps-managed components:

| Component | Description | Namespace |
|-----------|-------------|-----------|
| **AppProject** | ArgoCD project for MaaS | `openshift-gitops` |
| **RBAC** | Cluster-level permissions | Cluster-wide |
| **OpenShift AI** | Core AI platform | `redhat-ods-operator` |
| **Red Hat Connectivity Link** | API gateway, routing & rate limiting (Kuadrant) | `kuadrant-system` |
| **Cert-Manager** | Certificate management | `cert-manager-operator` |
| **Leader-Worker-Set** | Distributed workload operator | `openshift-operators` |
| **DataScienceCluster** | Platform configuration | `redhat-ods-operator` |
| **Connectivity Link Instance** | Connectivity Link CR instance (Kuadrant) | `kuadrant-system` |
| **LWS Instance** | LeaderWorkerSet CR instance | `openshift-operators` |
| **Model Registry** | Model versioning & storage | `rhoai-model-registries` |
| **Gateway** | Intelligent routing | `openshift-ingress` |
| **Model Registry GitOps** | Automated model registration | `fusion-model-registry-gitops-prod` |
| **Monitoring** | Prometheus platform monitoring; Grafana operator installed (dashboards not configured) | `openshift-monitoring` |

---

## Documentation

For additional information, refer to the guides below, grouped by topic.

### MaaS GitOps Deployment

- **[MaaS GitOps Deployment README](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/README.md)** — Environment-specific GitOps deployment structure for the MaaS platform
- **[MaaS Platform Deployment Guide](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment/environments/DEPLOYMENT_GUIDE.md)** — Full operational runbook: step-by-step sync, troubleshooting, RBAC, and migration

### Platform Post-Deploy

- **[Post-Sync Manual Steps](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/POST_SYNC_MANUAL_STEPS.md)** — Required steps after every `maas-platform` ArgoCD sync: User Workload Monitoring, Authorino TLS, OdhDashboardConfig
- **[MaaS Deployment Verification](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VERIFICATION.md)** — Full health check checklist to confirm MaaS is operational after deployment

### Secret Management (ESO / Vault)

Populate Vault secrets **before** the first ArgoCD sync for each chart. ESO resolves `ExternalSecret` CRs at sync time — missing Vault paths cause `SecretSyncedError`.

- **[maas-platform VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md)** — DB connection URL (`maas-db-config`) and in-cluster PostgreSQL credentials (`maas-postgres-creds`): Scenario A (in-cluster PG) and Scenario B (external managed DB); includes testing, rotation, and troubleshooting
- **[maas-model-deploy VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy/VAULT-SECRET-SETUP.md)** — S3 connection Secret and KServe `storage-config` Secret per model; Vault path convention `secret/maas/model-deploy/<model-name>/s3`; includes credential rotation and troubleshooting
- **[maas-model-registry VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md)** — Git credentials (Scenario A), Hugging Face token (Scenario B), and both together (Scenario C); includes rotation and troubleshooting

### Model Registry GitOps

- **[Model Registry GitOps README](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/README.md)** — Architecture overview and prerequisites for automated model registration
- **[Model Registry Quick Start](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/docs/QUICKSTART.md)** — Step-by-step guide to get from zero to a registered model in production
- **[Model Registry Environment Deployment Guide](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/argocd/environments/DEPLOYMENT_GUIDE.md)** — Operational runbook for deploying across dev, staging, and prod
- **[Adding a Model to the Registry](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/models/ADDING_A_MODEL.md)** — How to register a new model via a GitOps YAML commit
- **[Model Registry Verification Guide](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/docs/VERIFICATION_GUIDE.md)** — Post-deployment health checks for the GitOps pipeline

### Model Deployment

- **[Model Deploy GitOps README](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/README.md)** — Per-model ArgoCD Applications, multi-model design, and values file conventions
- **[Test Models Guide](https://github.com/IBM/storage-fusion/blob/master/AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/TEST_MODELS.md)** — End-to-end testing: API calls, rate-limit validation, token refresh, and rollback

### Use Case Examples

- **[Agentic Chat Assistant Sample Application](https://github.com/IBM/storage-fusion/blob/master/AI/fusion-gitops-sample-app/README.md)** — A reference implementation of an AI-powered chat application with RAG, secure secret management, and GitOps continuous delivery deployed on IBM Fusion

### External References

- **[ArgoCD Documentation](https://argo-cd.readthedocs.io/)** — Official ArgoCD documentation
- **[OpenShift GitOps](https://docs.openshift.com/gitops/)** — OpenShift GitOps operator documentation
- **[Red Hat OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)** — OpenShift AI product documentation
- **[Kuadrant](https://docs.kuadrant.io/)** — API gateway, rate limiting, and auth policy documentation
- **[External Secrets Operator](https://external-secrets.io/latest/)** — ESO documentation
- **[HashiCorp Vault](https://developer.hashicorp.com/vault/docs)** — Vault documentation

---

## Troubleshooting

### Model Inference Test Failures

```bash
# Describe the inference service for detailed status
oc describe llminferenceservice gpt-oss-20b -n deploy-models

# Check model pod logs for runtime errors
oc logs -n deploy-models -l serving.kserve.io/inferenceservice=gpt-oss-20b -c kserve-container --tail=100

# Check recent events in the namespace
oc get events -n deploy-models --sort-by='.lastTimestamp'

# Validate the HTTPRoute is correctly configured
oc describe httproute -n deploy-models

# Check Gateway is programmed and has an address
oc get gateway -n openshift-ingress

# Check Connectivity Link policies
oc get ratelimitpolicy -n deploy-models
oc get authpolicy -n deploy-models
```

### Application Not Syncing

```bash
# Check application status
argocd app get <app-name>

# View sync errors
argocd app sync <app-name> --dry-run

# Check ArgoCD logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=argocd-application-controller
```

### Operator Installation Issues

```bash
# Check operator subscriptions
oc get subscription -n redhat-ods-operator
oc get subscription -n kuadrant-system

# View operator logs
oc logs -n redhat-ods-operator -l name=rhods-operator

# Check install plans
oc get installplan -n redhat-ods-operator
```

### Model Registry GitOps Issues

```bash
# Check reconciler logs
oc logs -n fusion-model-registry-gitops-prod -l app=model-reconciler --tail=100

# Verify Git credentials (manual mode)
oc get secret git-credentials -n fusion-model-registry-gitops-prod

# Check CronJob status
oc get cronjob -n fusion-model-registry-gitops-prod
oc describe cronjob model-sync -n fusion-model-registry-gitops-prod
```

### ESO / Vault Issues

**`ExternalSecret` shows `SecretSyncedError` or `NotReady`:**

```bash
# Inspect the ExternalSecret conditions
oc get externalsecret -A
oc describe externalsecret <name> -n <namespace>

# Check ClusterSecretStore is Ready
oc get clustersecretstore vault-backend

# Check ESO operator pods
oc get pods -n external-secrets-operator

# Verify Vault path exists and has the expected fields
vault kv get secret/maas/postgres
vault kv get secret/maas/model-deploy/<model-name>/s3
vault kv get secret/maas/model-registry/git
```

**ArgoCD sync fails — `forbidden` on ExternalSecret resource:**

The chart auto-creates a `ClusterRole` + `RoleBinding` at sync-wave 0. If missing, the ESO flag may be `false`:

```bash
# Check the ClusterRole / RoleBinding exists
oc get clusterrole argocd-externalsecret-manager-model-deploy
oc get rolebinding argocd-externalsecret-manager -n redhat-ods-applications

# Confirm ESO is enabled in values (should print the template)
helm template test \
  AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy \
  --values environments/prod/values-gpt-oss-20b.yaml \
  --show-only templates/argocd-externalsecret-rbac.yaml
```

**Force an immediate ESO refresh without waiting for the refresh interval:**

```bash
oc annotate externalsecret <name> -n <namespace> \
  force-sync=$(date +%s) --overwrite
```

For the complete troubleshooting reference for each chart, see the per-chart `VAULT-SECRET-SETUP.md` files listed in the [Secret Management](#secret-management-eso--vault) section.

### Health Check Failures

```bash
# Check resource status
oc get datasciencecluster
oc get kuadrant -n kuadrant-system
oc get modelregistry.modelregistry.opendatahub.io -n rhoai-model-registries

# View events
oc get events -n <namespace> --sort-by='.lastTimestamp'

# Describe resources
oc describe datasciencecluster default-dsc
```

---

## Next Steps

After completing this quickstart, you can:

1. **Add More Models**: Add new model YAML files to `deploy/gitops/model-registry-gitops/models/` and commit — the Model Registry GitOps CronJob will register them automatically
2. **Deploy Additional Inference Services**: Repeat Steps 10–11 for each model, using a separate `values.yaml` per model
3. **Configure Environments**: Promote configurations from dev → staging → prod by copying and editing environment-specific `values.yaml` files
4. **Set Up CI/CD**: Integrate ArgoCD with your CI pipeline to trigger model deploys on merged PRs
5. **Add Monitoring**: Configure Prometheus recording rules and import the pre-built Grafana dashboards for inference latency and throughput
6. **Implement Policies**: Apply Kuadrant `RateLimitPolicy` and `AuthPolicy` resources to enforce per-tier rate limits and JWT authentication
7. **Scale Out**: Deploy the same App-of-Apps pattern to additional clusters for multi-region inference

---

## Summary

This quickstart demonstrated how to deploy a production-ready Model-as-a-Service platform using GitOps practices. You now have:

✅ **GitOps-Managed Infrastructure**: All platform and model components defined in Git
✅ **Automated Deployments**: ArgoCD-based continuous deployment with manual sync gates for production
✅ **Multi-Environment Support**: Dev, staging, and production configurations with isolated namespaces
✅ **Model Registry GitOps**: Automated model registration and artifact synchronisation from Git
✅ **IBM Fusion Storage**: Integrated ODF/NooBaa object storage for model artifacts and registry backends
✅ **Deployed Inference Services**: GPU-backed LLM inference services serving live traffic
✅ **Validated Endpoints**: Gateway routes tested with completions and chat API calls
✅ **Version Control**: Complete audit trail of all infrastructure and model changes
✅ **Self-Healing**: Automatic drift detection and correction via ArgoCD reconciliation
✅ **Secure Secret Management**: ESO syncs credentials from Vault — no plaintext secrets in Git

The IBM Fusion-hosted MaaS platform is now fully operational — models are registered, deployed through Red Hat OpenShift GitOps, and accessible through the secured gateway endpoint."
