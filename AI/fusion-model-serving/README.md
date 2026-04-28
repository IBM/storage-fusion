# Model Serving on Red Hat OpenShift AI with IBM Fusion HCI


Model serving is where machine learning delivers real value, enabling applications to consume trained models through scalable, production-ready inference endpoints.

In this guide, we walk through structured approaches to serving open-source LLMs on Red Hat OpenShift AI (RHOAI) using KServe and vLLM. Deployments can be managed through GitOps, Helm charts, or native Kubernetes manifests. Running the stack on IBM Fusion HCI further simplifies GPU, storage, and operator readiness for enterprise AI workloads.

## Model Serving with Red Hat OpenShift AI

Red Hat OpenShift AI (RHOAI) extends the capabilities of Red Hat OpenShift to deliver a consistent, enterprise-ready hybrid AI and MLOps platform. It provides tooling across the full lifecycle of AI/ML workloads, including training, serving, monitoring, and managing models and AI-enabled applications.

For details, refer to the official documentation: [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    External Clients                         │
│              (Applications, APIs, Dashboards)               |
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ HTTPS (TLS)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              OpenShift Route (Edge Termination)             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  KServe InferenceService                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Predictor (vLLM Runtime)                │   │
│  │  • Model: Hugging Face LLM                           │   │
│  │  • Runtime: vLLM with OpenAI-compatible API          │   │
│  │  • Resources: GPU, Memory, CPU                       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  IBM Fusion HCI Infrastructure              │
│  • GPU-enabled Worker Nodes (NVIDIA GPU Operator)           │
│  • Persistent Storage (IBM Fusion Data Foundation)          │
│  • High-performance Networking                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Supported Models

This repository includes pre-configured deployments for popular open-source LLMs:

| Model | Size | Description |
|-------|------|-------------|
| **IBM Granite 3.2 8B Instruct** | 8B | Enterprise-focused instruction-tuned model |
| **Qwen 2.5 7B Instruct** | 7B | High-performance multilingual model |
| **Ministral 3 8B Instruct** | 8B | Efficient instruction-following model |

**Custom Models:** All deployment methods support custom model configurations. Refer to the respective deployment guides for instructions on deploying your own models from Hugging Face or other sources.

---

## Prerequisites

Before deploying models, ensure the following infrastructure and platform components are ready:

### Cluster and Platform Requirements
- IBM Fusion HCI cluster installed, running, and healthy
- Red Hat OpenShift Container Platform 4.18 or later is accessible
- At least one worker node capable of running AI workloads
  - GPU-enabled if serving large language models (LLMs)

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

### Storage Configuration
Model serving workloads require persistent storage for:
- Model caching
- Runtime artifacts
- Serving configuration

Ensure:
- A default StorageClass is configured
- Sufficient persistent storage capacity is available

Verify: `oc get sc`

If no default StorageClass is set, configure one using IBM Fusion Data Foundation or another supported storage provider.

### Required Platform Operators
The following operators must be installed and in a Ready state:
- **Red Hat OpenShift AI (RHOAI)**
  - Provides KServe, ODH Model Controller, and AI platform components
  - For installation instructions, see the [RHOAI Deployment Guide](../fusion-openshift-ai/README.md)

### Access and Permissions
- `oc` CLI configured and authenticated to your OpenShift cluster
- Cluster-admin or sufficient RBAC to create namespaces, roles, and Argo CD Applications
- Access to the Argo CD UI (for GitOps) and `oc apply` permissions
- Access to Hugging Face model repositories (or your model storage location)

---

## Deployment Methods

This repository provides **three deployment approaches** for model serving, each suited to different use cases and operational preferences:

### 1. GitOps with Red Hat OpenShift GitOps (Argo CD)

Uses Red Hat OpenShift GitOps (Argo CD) to continuously reconcile model serving configuration from Git. All resources are version-controlled, drift is auto-corrected, and deployments are self-healing.

**Best for:** Production environments, multi-environment workflows, teams practising GitOps.


**[Read the Complete GitOps Deployment Guide](./deploy/gitops/README.md)**

---

### 2. Helm Charts

Uses Helm charts with pre-configured model presets and `values.yaml` files. Supports easy multi-model deployment, upgrades, and rollbacks from the command line.

**Best for:** Templated deployments, teams familiar with Helm, quick multi-model management.


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

## Exposing Models for External Access

By default, KServe creates internal ClusterIP services that are only accessible within the cluster. To make models available to external applications (dashboards, APIs, or client tools), use the included `expose-model.sh` script to create an OpenShift Edge-terminated Route.

The `expose-model.sh` utility automatically generates OpenShift Routes with TLS encryption, making your models available outside the cluster.

### Expose All Models in a Namespace

To expose every deployed InferenceService in a given namespace:
```bash
./fusion-model-serving/scripts/expose-model.sh model-serving
```

### Expose a Specific Model

To expose only a single model (example: Granite):
```bash
./fusion-model-serving/scripts/expose-model.sh granite-3-2-8b-instruct model-serving
```

### What the Script Does

When executed, the `expose-model.sh` script automates the entire external exposure process by:
- Validating resources - Confirms that the InferenceService and its backing Kubernetes Service are present
- Creating an OpenShift Route - Sets up an edge-terminated TLS Route for secure access
- Enabling HTTPS connectivity - Ensures TLS termination at the OpenShift ingress router
- Printing the model endpoint URL - Outputs the external HTTPS URL for immediate use
- Generating test commands - Provides ready-to-run curl examples to verify the deployment

### Example Output

```bash
╔════════════════════════════════════════════════════════════╗
║         Expose Models - External Access                    ║
╚════════════════════════════════════════════════════════════╝

Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Namespace: model-serving
  Mode:      Expose ALL InferenceServices
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Found InferenceServices:
  - granite-3-2-8b-instruct

Processing: granite-3-2-8b-instruct
route/granite-3-2-8b-instruct-external created
✓ Exposed at: https://granite-3-2-8b-instruct-external-model-serving.apps.cluster.example.com

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Successfully exposed 1 InferenceService(s)!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test your models:
  granite-3-2-8b-instruct:
    curl -k https://granite-3-2-8b-instruct-external-model-serving.apps.cluster.example.com/v1/models \
      -H 'Authorization: Bearer EMPTY'
```

### Testing External Access

Once exposed, test your model with OpenAI-compatible API calls:

```bash
# List available models
curl -k https://granite-3-2-8b-instruct-external-model-serving.apps.cluster.example.com/v1/models \
  -H "Authorization: Bearer EMPTY"

# Test chat completions
curl -k -X POST https://granite-3-2-8b-instruct-external-model-serving.apps.cluster.example.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer EMPTY" \
  -d '{
    "model": "ibm-granite/granite-3.2-8b-instruct",
    "messages": [
      {"role": "user", "content": "Explain about Red Hat OpenShift AI operator"}
    ],
    "max_tokens": 200
  }'
```

---


## Key Takeaways

By leveraging Red Hat OpenShift AI with KServe and vLLM, model serving becomes:
- **Scalable**: Automatic scaling based on inference load
- **Declarative**: Infrastructure as code for all deployments
- **Flexible**: Support for multiple deployment methods
- **Production-Ready**: Enterprise-grade reliability and security

Running the stack on IBM Fusion HCI simplifies GPU enablement, storage integration, and operator readiness, providing a consistent path from experimentation to scalable AI deployments.

Platform operators manage infrastructure, while your chosen deployment method (GitOps, Helm, or Kubernetes manifests) governs model lifecycle, creating a clean separation of responsibilities for reliable AI operations.

---

## Additional Resources

### Documentation
- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- [KServe Documentation](https://kserve.github.io/website/)
- [vLLM Documentation](https://docs.vllm.ai/)
- [Red Hat OpenShift GitOps Documentation](https://docs.openshift.com/gitops/latest/)
- [Helm Documentation](https://helm.sh/docs/)

### IBM Fusion HCI
- [IBM Fusion HCI Documentation](https://www.ibm.com/docs/en/storage-fusion)
- [IBM Fusion Data Foundation](https://www.ibm.com/products/storage-fusion)

### Community
- [OpenShift AI Community](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai)
- [KServe Community](https://github.com/kserve/kserve)
- [vLLM Community](https://github.com/vllm-project/vllm)
