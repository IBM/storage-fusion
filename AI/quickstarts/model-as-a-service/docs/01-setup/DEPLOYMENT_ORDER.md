# MaaS Platform Deployment Order Guide

This guide explains the correct order for deploying the MaaS platform components using Helm charts.

## Overview

The MaaS platform consists of four main Helm charts that must be deployed in a specific order:

1. **maas-operators** - Install required operators (OpenShift AI, Kuadrant, etc.)
2. **maas-platform** - Configure DataScienceCluster and platform components
3. **maas-runtime** - Deploy runtime infrastructure (Gateway, Model Registry, Storage)
4. **maas-model-service** - Deploy model inference services

## Deployment Architecture

```
┌────────────────────────────────────────────────────────────┐
│ Step 1: Install Operators (maas-operators chart)           │
│ ┌──────────────────────────────────────────────────────┐   │
│ │ • OpenShift AI Operator                              │   │
│ │ • Kuadrant Operator                                  │   │
│ │ • Cert-manager Operator                              │   |
│ │ • Leader Worker Set Operator                         │   │
│ └──────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────────┐
│ Step 2: Configure Platform (maas-platform chart)           │
│ ┌──────────────────────────────────────────────────────┐   │
│ │ • DataScienceCluster                                 │   │
│ │ • Kuadrant Instance                                  │   │
│ │ • Leader Worker Set clsuter Instance                 │   │
│ └──────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────────┐
│ Step 3: Deploy Runtime (maas-runtime chart)                │
│ ┌──────────────────────────────────────────────────────┐   │
│ │ • Gateway API Configuration                          │   │
│ │ • Model Registry                                     │   │
│ │ • Workbench Storage                                  │   │
│ │ • Tier Groups & Rate Limiting                        │   │
│ │ • RBAC Configuration                                 │   │
│ └──────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────────┐
│ Step 4: Deploy Models (maas-model-service chart)           │
│ ┌──────────────────────────────────────────────────────┐   │
│ │ • LLMInferenceService                                │   │
│ │ • Model pods (vLLM/TGI)                              │   │
│ │ • HTTPRoute                                          │   │
│ │ • RateLimitPolicy                                    │   │
│ │ • ServiceMonitor                                     │   │
│ └──────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

## Step-by-Step Deployment

### Step 1: Install Operators (Required)

The operators chart installs all required operators and must be deployed first.

#### What It Deploys

- **OpenShift AI Operator**: Core AI platform capabilities
- **Kuadrant Operator**: API gateway and rate limiting
- **Cert-manager Operator**: Certificate management
- **Service Mesh Operator**: Service mesh infrastructure
- **Authorino Operator**: Authentication and authorization

#### Deployment Command

```bash
# Using Helm
helm install maas-operators deploy/maas-operators \
  --create-namespace \
  --wait \
  --timeout 10m
```

#### Verification

```bash
# Check operators are installed
oc get csv -n redhat-ods-operator
oc get csv -n kuadrant-system
oc get csv -n cert-manager
oc get csv -n openshift-operators

# Check operator pods
oc get pods -n redhat-ods-operator
oc get pods -n kuadrant-system
```

#### Expected Duration

- **Operator installation**: 3-5 minutes

---

### Step 2: Configure Platform (Required)

The platform chart configures the DataScienceCluster and platform components.

#### What It Deploys

- **DataScienceCluster**: Core OpenShift AI components
- **Kuadrant Instance**: API gateway configuration
- **Service Mesh Configuration**: Mesh setup
- **Authorino Instance**: Auth configuration

#### Deployment Command

```bash
# Using Helm
helm install maas-platform deploy/maas-platform \
  --set global.wildcardDomain=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}') \
  --wait \
  --timeout 15m
```

#### Verification

```bash
# Wait for DataScienceCluster to be ready
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=600s

# Check platform components
oc get datasciencecluster
oc get kuadrant -n kuadrant-system

# Check component pods
oc get pods -n redhat-ods-applications
```

#### Expected Duration

- **DataScienceCluster creation**: 5-10 minutes

---

### Step 3: Deploy Runtime Infrastructure (Required)

The runtime chart deploys the operational infrastructure for model serving.

#### What It Deploys

- **Gateway API**: Ingress gateway for model endpoints
- **Model Registry**: Model versioning and metadata storage
- **Workbench Storage**: Object storage for data science workbenches
- **Tier Groups**: User tier management for rate limiting
- **RBAC Configuration**: Role-based access control

#### Deployment Command

```bash
# Using the install script (recommended)
./scripts/install-runtime.sh examples/Fusion-Agentic-Assistance-Platform/values.yaml

# Or using Helm directly
helm install maas-runtime deploy/maas-runtime \
  -f examples/Fusion-Agentic-Assistance-Platform/values.yaml \
  --create-namespace \
  --wait \
  --timeout 15m
```

#### Verification

```bash
# Check Gateway
oc get gateway -n openshift-ingress

# Check Model Registry
oc get modelregistry -n rhoai-model-registries

# Check runtime namespaces
oc get namespace maas-models
oc get namespace rhods-notebooks
```

#### Expected Duration

- **Runtime deployment**: 3-5 minutes

---

### Step 4: Deploy Model Services (Required)

Deploy AI models as inference services. This must be done after the runtime is ready.

#### What It Deploys

- **LLMInferenceService**: KServe inference service
- **Model Pods**: vLLM, TGI, or llama.cpp containers
- **HTTPRoute**: Gateway routing configuration
- **RateLimitPolicy**: Tier-based rate limiting
- **ServiceMonitor**: Prometheus metrics collection

#### Deployment Options

**Option A: Deploy from Model Registry (Recommended)**

Deploy models that are registered in the OpenShift AI Model Registry:

```bash
# Deploy Granite 3.1 8B model from registry
./scripts/deploy-model.sh examples/model-registry-deployment/granite-3.1-8b-instruct-values.yaml

# Deploy Qwen3 8B model from registry
./scripts/deploy-model.sh examples/model-registry-deployment/qwen3-8b-fp8-dynamic-values.yaml

# Deploy GPT-OSS-20B model from registry
./scripts/deploy-model.sh examples/model-registry-deployment/gpt-oss-20b-values.yaml
```

The script automatically:
- Validates the model exists in the registry
- Fetches the model URI from the registry database
- Deploys the model with proper configuration

**Option B: Deploy from Code Assistant Examples**

```bash
# Using the deploy script (recommended)
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml

# Or using Helm directly
helm install gpt-oss-20b deploy/maas-model-service \
  -f examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml \
  --create-namespace \
  --wait
```

#### Verification

```bash
# Check LLMInferenceService
oc get llminferenceservice -n maas-models

# Check model pods
oc get pods -n maas-models

# Wait for model to be ready
oc wait --for=condition=Ready llminferenceservice/gpt-oss-20b -n maas-models --timeout=600s

# Test model endpoint
MODEL_URL=$(oc get route -n maas-models gpt-oss-20b -o jsonpath='{.spec.host}')
curl -k https://$MODEL_URL/v1/models
```

#### Expected Duration

- **Model download**: 2-5 minutes (depends on model size)
- **Pod startup**: 2-3 minutes
- **Total**: 5-10 minutes

---

## Complete Deployment Example

### Quick Deployment - Option 1: Using the Install Script (Recommended)

The `install-runtime.sh` script automatically handles all three infrastructure charts in the correct order:

```bash
# Single command to deploy all infrastructure (operators, platform, runtime)
./scripts/install-runtime.sh examples/Fusion-Agentic-Assistance-Platform/values.yaml

# The script automatically:
# - Phase 1: Installs maas-operators (OpenShift AI, Kuadrant, etc.)
# - Phase 2: Creates maas-platform (DataScienceCluster, operator instances)
# - Phase 3: Deploys maas-runtime (Gateway, Model Registry, Storage)

# Then deploy your models
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml

# Wait for model to be ready
oc wait --for=condition=Ready llminferenceservice/gpt-oss-20b -n maas-models --timeout=600s

# Verify deployment
oc get llminferenceservice -n maas-models
```

### Quick Deployment - Option 2: Manual Helm Installation

If you prefer to install each chart manually:

```bash
# Step 1: Install Operators
helm install maas-operators deploy/maas-operators \
  --create-namespace \
  --wait \
  --timeout 10m

# Step 2: Configure Platform
helm install maas-platform deploy/maas-platform \
  --set global.wildcardDomain=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}') \
  --wait \
  --timeout 15m

# Wait for platform to be ready
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=600s

# Step 3: Deploy Runtime
helm install maas-runtime deploy/maas-runtime \
  -f examples/Fusion-Agentic-Assistance-Platform/values.yaml \
  --wait \
  --timeout 10m

# Step 4: Deploy Models
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml

# Wait for model to be ready
oc wait --for=condition=Ready llminferenceservice/gpt-oss-20b -n maas-models --timeout=600s

# Verify deployment
oc get llminferenceservice -n maas-models
```

### Total Deployment Time

- **Operators**: 3-5 minutes
- **Platform**: 5-10 minutes
- **Runtime**: 3-5 minutes
- **Model Deployment**: 5-10 minutes
- **Total**: 16-30 minutes

---

## Deployment Dependencies

### Chart Dependencies

```
maas-operators (MUST deploy first)
    ↓
maas-platform (MUST deploy after operators)
    ↓
maas-runtime (MUST deploy after platform is ready)
    ↓
maas-model-service (MUST deploy after runtime is ready)
```

### Why This Order?

1. **Operators First**: Installs required operators (OpenShift AI, Kuadrant, etc.)
2. **Platform Second**: Configures DataScienceCluster and platform components
3. **Runtime Third**: Deploys gateway, model registry, and storage integration
4. **Model Service Last**: Requires all infrastructure to be ready

---

## Common Deployment Scenarios

### Scenario 1: First-Time Deployment (Recommended)

```bash
# Use the install script - handles all infrastructure in one command
./scripts/install-runtime.sh examples/Fusion-Agentic-Assistance-Platform/values.yaml

# Deploy your first model
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml
```

### Scenario 1b: First-Time Deployment (Manual)

```bash
# If you prefer manual control over each chart
# 1. Install operators
helm install maas-operators deploy/maas-operators --wait --timeout 10m

# 2. Configure platform
helm install maas-platform deploy/maas-platform \
  --set global.wildcardDomain=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}') \
  --wait --timeout 15m

# 3. Deploy runtime
helm install maas-runtime deploy/maas-runtime \
  -f examples/Fusion-Agentic-Assistance-Platform/values.yaml \
  --wait --timeout 10m

# 4. Deploy first model
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml
```

### Scenario 2: Add New Model to Existing Platform

```bash
# All infrastructure already deployed, just deploy new model

# Option A: Deploy from Model Registry (Recommended)
./scripts/deploy-model.sh examples/model-registry-deployment/granite-3.1-8b-instruct-values.yaml

# Option B: Deploy from code assistant examples
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/nemotron-values.yaml
```

### Scenario 3: GitOps Deployment

```bash
# 1. Deploy operators via ArgoCD
oc apply -f examples/operators-gitops-deployment/argocd/application.yaml

# 2. Deploy platform via ArgoCD
oc apply -f examples/platform-gitops-deployment/argocd/application.yaml

# 3. Wait for platform
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=600s

# 4. Deploy runtime via ArgoCD
oc apply -f examples/maas-runtime-gitops-deployment/argocd/application.yaml

# 5. Deploy models via ArgoCD
oc apply -f examples/maas-model-service-gitops-deployment/argocd/gpt-oss-20b-app.yaml
```

---

## Troubleshooting Deployment Order Issues

### Issue: Operators Not Installing

**Symptom**: Operators stuck in "Installing" state

**Cause**: Subscription or catalog source issues

**Solution**:
```bash
# Check operator status
oc get csv -A | grep -E "Installing|Failed"

# Check subscriptions
oc get subscription -A

# If needed, reinstall operators
helm uninstall maas-operators
helm install maas-operators deploy/maas-operators --wait --timeout 10m
```

### Issue: DataScienceCluster Not Ready

**Symptom**: DSC stuck in "Progressing" state

**Cause**: Platform components not fully deployed

**Solution**:
```bash
# Check platform status
oc get datasciencecluster
oc get pods -n redhat-ods-applications

# Wait longer or check for resource constraints
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=900s
```

### Issue: Model Deployment Fails

**Symptom**: Model service fails to deploy with namespace or resource errors

**Cause**: Runtime not fully deployed

**Solution**:
```bash
# Check runtime status
oc get gateway -n openshift-ingress
oc get modelregistry -n rhoai-model-registries
oc get namespace maas-models

# Ensure runtime is deployed
helm list | grep maas-runtime

# Then retry model deployment
helm install my-model deploy/maas-model-service -f my-model-values.yaml
```

### Issue: Namespace Already Exists Error

**Symptom**: Model deployment fails with "namespace already exists"

**Cause**: Using `project.create: true` when namespace already exists

**Solution**:
```bash
# Option 1: Set create to false
# project:
#   create: false

# Option 2: Delete and recreate
oc delete namespace maas-models
helm install my-model deploy/maas-model-service -f my-model-values.yaml
```

---

## Best Practices

### 1. Use the Install Script for Infrastructure

```bash
# ✅ Recommended: Use install-runtime.sh (handles all 3 infrastructure charts)
./scripts/install-runtime.sh examples/Fusion-Agentic-Assistance-Platform/values.yaml
./scripts/deploy-model.sh model-values.yaml

# ✅ Alternative: Manual installation (more control)
helm install maas-operators deploy/maas-operators
helm install maas-platform deploy/maas-platform
helm install maas-runtime deploy/maas-runtime -f values.yaml
./scripts/deploy-model.sh model-values.yaml

# ❌ Wrong: Deploy models before infrastructure
./scripts/deploy-model.sh model-values.yaml  # Will fail!
./scripts/install-runtime.sh values.yaml
```

### 2. Wait for Each Step to Complete

```bash
# ✅ The install-runtime.sh script handles waiting automatically
./scripts/install-runtime.sh values.yaml  # Waits for each phase
./scripts/deploy-model.sh model-values.yaml

# ✅ If installing manually, use --wait flags
helm install maas-operators deploy/maas-operators --wait
helm install maas-platform deploy/maas-platform --wait
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=600s
helm install maas-runtime deploy/maas-runtime -f values.yaml --wait
./scripts/deploy-model.sh model-values.yaml

# ❌ Don't skip waiting
helm install maas-operators deploy/maas-operators
helm install maas-platform deploy/maas-platform
./scripts/deploy-model.sh model-values.yaml  # May fail!
```

### 3. Use Scripts for Consistency

```bash
# ✅ Recommended: Use scripts (they handle all dependencies)
./scripts/install-runtime.sh values.yaml  # Installs operators, platform, AND runtime
./scripts/deploy-model.sh model-values.yaml

# ⚠️ Manual Helm works but requires more steps
helm install maas-operators deploy/maas-operators
helm install maas-platform deploy/maas-platform
helm install maas-runtime deploy/maas-runtime -f values.yaml
helm install my-model deploy/maas-model-service -f model-values.yaml
```

### 4. Verify Each Step

```bash
# After operators
oc get csv -A | grep -E "rhods-operator|kuadrant"

# After platform
oc get datasciencecluster

# After runtime
oc get gateway -n openshift-ingress
oc get modelregistry -n rhoai-model-registries

# After model deployment
oc get llminferenceservice -n maas-models
oc get pods -n maas-models
```

---

## Available Model Examples

### Model Registry Deployment Examples

Located in `examples/model-registry-deployment/`:

| Model | Values File | Description |
|-------|-------------|-------------|
| **Granite 3.1 8B** | `granite-3.1-8b-instruct-values.yaml` | IBM Granite 3.1 8B instruction-tuned model |
| **Qwen3 8B FP8** | `qwen3-8b-fp8-dynamic-values.yaml` | Qwen3 8B with FP8 quantization |
| **GPT-OSS-20B** | `gpt-oss-20b-values.yaml` | GPT-OSS 20B code generation model |

**Usage:**
```bash
./scripts/deploy-model.sh examples/model-registry-deployment/<values-file>
```

**Features:**
- Automatic model registry validation
- Connection secret management
- Monitoring and rate limiting support

See [Model Registry Deployment README](../examples/model-registry-deployment/README.md) for detailed documentation.

### Code Assistant Examples

Located in `examples/Fusion-Agentic-Assistance-Platform/models/`:

| Model | Values File | Description |
|-------|-------------|-------------|
| **GPT-OSS** | `gpt-oss-values.yaml` | Code generation model |
| **Nemotron** | `nemotron-values.yaml` | NVIDIA Nemotron model |

---

## Related Documentation

- [Getting Started Guide](../GETTING_STARTED.md) - Complete installation guide
- [MaaS Operators Guide](MAAS_OPERATORS_GUIDE.md) - Operator installation and configuration
- [Platform Customization Guide](MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md) - Platform configuration
- [Runtime Customization Guide](MAAS_RUNTIME_CUSTOMIZATION_GUIDE.md) - Runtime configuration
- [Deploying Model Services](../03-model-deployment/DEPLOYING_MODEL_SERVICES.md) - Detailed model deployment
- [Model Registry Guide](../02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md) - Registry configuration
- [Model Registry Deployment Examples](../../examples/model-registry-deployment/README.md) - Deploy from registry

---

**Last Updated:** 2026-05-26
**Version:** 2.0