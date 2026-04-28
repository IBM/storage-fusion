
# Red Hat OpenShift AI Installation on IBM Fusion HCI

Artificial Intelligence workloads are rapidly becoming a core part of modern enterprise platforms. Organizations require a scalable, Kubernetes-native platform to build, train, deploy, and manage machine learning models efficiently across hybrid cloud environments.

Red Hat OpenShift AI (RHOAI) extends Red Hat OpenShift with an enterprise-grade hybrid AI and MLOps platform, providing tooling across the full AI/ML lifecycle including training, serving, monitoring, and managing models.

This guide demonstrates how to install and configure Red Hat OpenShift AI on IBM Fusion HCI using three structured deployment approaches: GitOps with Argo CD, Helm charts, or native Kubernetes manifests. Each method is suited to different operational preferences and use cases, from production GitOps workflows to quick prototyping.

IBM Fusion HCI provides the infrastructure foundation for AI workloads, simplifying GPU enablement, storage integration, and operator readiness for enterprise AI deployments.

For details, refer to the official documentation: [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)

---

## Directory Structure

```
fusion-openshift-ai/
├── README.md                            # This file - general overview and deployment options
│
├── deploy/
│   ├── gitops/
│   │   ├── README.md                    # GitOps deployment guide
│   │   ├── rhoai-application.yaml       # Argo CD Application CR
│   │   ├── patch/
│   │   │   ├── argocd-patch-rbac.yaml   # RBAC for Argo CD patching
│   │   │   └── argocd-resource-health-patch.yaml  # Health checks for RHOAI CRs
│   │   └── rhoai/
│   │       ├── operator.yaml            # Operator subscription
│   │       ├── dsc.yaml                 # DataScienceCluster configuration
│   │       └── kustomization.yaml       # Kustomize base
│   │
│   ├── helm/
│   │   ├── README.md                    # Helm deployment guide
│   │   ├── Chart.yaml                   # Helm chart metadata
│   │   ├── values.yaml                  # Default configuration values
│   │   └── templates/
│   │       ├── _helpers.tpl             # Template helpers
│   │       ├── operator.yaml            # Operator template
│   │       └── dsc.yaml                 # DataScienceCluster template
│   │
│   └── kubernetes/
│       ├── README.md                    # Kubernetes manifest deployment guide
│       ├── operator.yaml                # Operator subscription manifest
│       └── dsc.yaml                     # DataScienceCluster manifest

```

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          Deployment method                                 │
│            choose one for installation and lifecycle management            │
│                                                                            │
│  ┌──────────────────┐  ┌──────────────────┐  ┌─────────────────────────┐   │
│  │  GitOps/Argo CD  │  │   Helm charts    │  │ Kubernetes manifests    │   │
│  │ Continuous sync, │  │   Templated,     │  │ Direct oc apply,        │   │
│  │   self-healing   │  │versioned installs│  │   full control          │   │
│  └──────────────────┘  └──────────────────┘  └─────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                      Red Hat OpenShift AI (RHOAI)                          │
│           installed via the RHOAI operator + DataScienceCluster CR         │
│                                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │  Dashboard   │  │ Workbenches  │  │   KServe     │  │ Model Registry │  │
│  │   Web UI     │  │Jupyter       │  │Model serving │  │  Versioning,   │  │
│  │              │  │notebooks     │  │              │  │   metadata     │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └────────────────┘  │
│                                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │DS Pipelines  │  │     Ray      │  │  Training    │  │   TrustyAI     │  │
│  │  Workflow    │  │ Distributed  │  │  Operator    │  │  Responsible   │  │
│  │orchestration │  │   compute    │  │K8s-native    │  │   AI evals     │  │
│  │              │  │              │  │  training    │  │                │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                  Red Hat OpenShift Container Platform                      │
│              ships with cluster · must be installed before RHOAI           │
│                                                                            │
│  ┌─────────────────────────────────┐  ┌────────────────────────────────┐   │
│  │    Ships with OpenShift         │  │  Pre-install prerequisites     │   │
│  │  Operator Lifecycle Manager     │  │  Node Feature Discovery (NFD)  │   │
│  │       (OLM)                     │  │  NVIDIA GPU Operator           │   │
│  │  OperatorHub / Marketplace      │  │  cert-manager · JobSet · LWS   │   │
│  │  OpenShift GitOps (Argo CD)     │  │  Red Hat Connectivity Link     │   │
│  │  Networking / Ingress           │  │                                │   │
│  └─────────────────────────────────┘  └────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                      IBM Fusion HCI infrastructure                         │
│                     hardware and storage foundation                        │
│                                                                            │
│            ┌──────────────────┐  ┌──────────────────────┐                  │
│            │ GPU worker nodes │  │Fusion Data Foundation│                  │
│            │  NVIDIA, AI      │  │   Ceph, RWX PVCs     │                  │
│            │   workloads      │  │                      │                  │
│            └──────────────────┘  └──────────────────────┘                  │
└────────────────────────────────────────────────────────────────────────────┘
```

---


## Prerequisites
Before installing the Red Hat OpenShift AI Operator, ensure the following prerequisites are in place on your IBM Fusion HCI cluster.

#### Cluster and Platform Requirements
  - IBM Fusion HCI cluster with Red Hat OpenShift Container Platform installed, running, and accessible
  - At least one worker node capable of supporting AI workloads (GPU-enabled if required)

#### Storage Configuration

  - A default StorageClass must be available for provisioning persistent volumes required by OpenShift AI components (workbenches, pipelines, and model storage)

Verify storage classes:
```
oc get sc
```
If no default storage class is set, configure one using IBM Fusion Data Foundation or another supported storage provider.
#### Required Platform Operators

The following operators must be installed before proceeding:
  - Node Feature Discovery (NFD) - to detect node hardware capabilities (such as GPUs)
  - NVIDIA GPU Operator (required only if GPU-based workloads are planned) - to enable GPU acceleration for training and serving
  - Job Set Operator - to manage job sets for batch workloads
  - cert-manager Operator for Red Hat OpenShift - to manage certificates and TLS configurations
  - Red Hat build of Leader Worker Set - to coordinate leader-worker distributed workloads
  - Red Hat Connectivity Link - to enable connectivity and networking features

#### Access and Permissions

  - `oc` CLI configured and authenticated to your OpenShift cluster

## Repository Setup

1. Fork the  [storage-fusion](https://github.com/IBM/storage-fusion) repository so it can serve as your GitOps source of truth.
  > **Note:** The `fusion-openshift-ai` directory is located under the `AI/` parent directory within the `storage-fusion` repository (path: `storage-fusion/AI/fusion-openshift-ai`).

2. Clone the forked copy of this repository:
```bash
   git clone git@github.com:<your-username>/storage-fusion.git
```
3. Ensure you push any changes (such as repoURL updates) back to your fork before bootstrapping.

4. Login to your cluster using `oc login` or by exporting the KUBECONFIG:
```bash
   oc login --token=<TOKEN> --server=<API_SERVER>
```

----

## Deployment Methods

This repository provides **three deployment approaches** for installing Red Hat OpenShift AI, each suited to different use cases and operational preferences:

### 1. GitOps with Red Hat OpenShift GitOps (Argo CD)

Uses Red Hat OpenShift GitOps (Argo CD) to continuously reconcile OpenShift AI configuration from Git. All resources are version-controlled, drift is auto-corrected, and deployments are self-healing.

**Best for:** Production environments, multi-environment workflows, teams practising GitOps.

**[Read the Complete GitOps Deployment Guide](./deploy/gitops/README.md)**

---

### 2. Helm Charts

Uses Helm charts with configurable `values.yaml` files. Supports easy component customization, upgrades, and rollbacks from the command line.

**Best for:** Templated deployments, teams familiar with Helm, quick component management.

**[Read the Complete Helm Deployment Guide](./deploy/helm/README.md)**

---

### 3. Kubernetes Manifests

Uses native Kubernetes YAML manifests applied with `oc apply -f`. Provides direct control over every resource definition with minimal tooling.

**Best for:** Quick prototyping, learning, CI/CD pipelines, direct resource control.

**[Read the Complete Kubernetes Deployment Guide](./deploy/kubernetes/README.md)**

---

## Quick Comparison

| Feature | GitOps | Helm | Kubernetes Manifests |
|---------|--------|------|---------------------|
| **Deployment Method** | Argo CD Application | Helm install/upgrade | oc apply |
| **Version Control** |  Git-native |  Manual |  Manual |
| **Automated Sync** |  Continuous |  Manual |  Manual |
| **Self-Healing** |  Automatic |  Manual |  Manual |
| **Rollback** |  Git revert |  helm rollback |  Manual |
| **Multi-Environment** |  Branch-based |  Values files |  Multiple files |
| **Learning Curve** | Medium | Low-Medium | Low |
| **Best For** | Production | Templated deploys | Quick prototyping |

---
## Customizing OpenShift AI with DataScienceCluster Components

The DataScienceCluster specification is organized by platform components.

Each component is controlled through a simple switch called managementState:
  - **Managed** → the component is enabled and deployed
  - **Removed** → the component is disabled and not installed

This makes the DataScienceCluster the central place to customize exactly what gets installed in your OpenShift AI platform.

  ####  Components Enabled in This Setup (Managed)
In this configuration, the following core services are enabled:
  - **Dashboard** – provides the OpenShift AI user interface
  - **Workbenches** – enables notebook environments created within user projects
  - **KServe** – activates model serving using raw deployment mode
      - **NIM integration** (if configured and supported by your RHOAI version)
  - **Model Registry** – deployed into rhoai-model-registries for managing model metadata
  - **TrustyAI** – enables responsible AI evaluation, with restricted execution and no online access
  - **AI Pipelines** – provides workflow and pipeline orchestration
  - **Ray** – enables distributed compute workloads
  - **Training Operator** – supports Kubernetes-native model training workloads

These components represent the core services typically required in production AI environments.

  #### Components Explicitly Disabled (Removed)
Several optional operators are intentionally excluded to keep the platform lightweight:
  - **Feast Operator** – feature store integration
  - **Trainer** – additional training abstraction layer
  - **MLflow Operator** – experiment tracking and model lifecycle tooling
  - **LlamaStack Operator** – advanced LLM stack services
  - **Kueue** – batch scheduling and queue-based workload orchestration

Marking these as Removed ensures they are not installed at all, reducing cluster overhead and operator sprawl.
---
## Verifying the Installation

After deployment, verify the OpenShift AI installation:

```bash
# Check operator status
oc get csv -n redhat-ods-operator

# Check DataScienceCluster status
oc get datasciencecluster -n redhat-ods-operator

# View all OpenShift AI pods
oc get pods -n redhat-ods-operator
oc get pods -n redhat-ods-applications
oc get pods -n rhods-notebooks
```

### Access the Dashboard

Once installed, access the OpenShift AI dashboard:

1. Navigate to the OpenShift Console
2. Go to **Networking → Routes** in the `redhat-ods-applications` namespace
3. Find the `rhods-dashboard` route
4. Click the URL to access the dashboard

Or use the CLI:
```bash
oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'
```

---

## Key Takeaways

By leveraging Red Hat OpenShift AI on IBM Fusion HCI, AI/ML platform deployment becomes:
- **Scalable**: Enterprise-grade platform for production AI workloads
- **Declarative**: Infrastructure as code for all deployments
- **Flexible**: Support for multiple deployment methods
- **Production-Ready**: Enterprise reliability and security

Running on IBM Fusion HCI simplifies GPU enablement, storage integration, and operator readiness, providing a consistent path from experimentation to production AI deployments.

Platform operators manage infrastructure, while your chosen deployment method (GitOps, Helm, or Kubernetes manifests) governs the AI platform lifecycle, creating a clean separation of responsibilities for reliable AI operations.

---

## Additional Resources

### Documentation
- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- [Red Hat OpenShift GitOps Documentation](https://docs.openshift.com/gitops/latest/)
- [Helm Documentation](https://helm.sh/docs/)

### Platform Operators
- [Node Feature Discovery Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.10/html/specialized_hardware_and_driver_enablement/node-feature-discovery-operator)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/index.html)
- [Red Hat build of Leader Worker Set](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/ai_workloads/leader-worker-set-operator)
- [Job Set Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/ai_workloads/jobset-operator)
- [Red Hat Connectivity Link](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.3/html/installing_on_openshift_container_platform/rhcl-install-on-ocp)

### IBM Fusion HCI
- [IBM Fusion HCI Documentation](https://www.ibm.com/docs/en/storage-fusion)
