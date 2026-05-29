# Getting Started with IBM Fusion for AI - MaaS Platform

**Part of the IBM Fusion for AI Platform Strategy**

This quick start guide demonstrates how to configure IBM Fusion as a comprehensive AI inference platform on Red Hat OpenShift AI 3.3.0. You'll learn how to deploy the MaaS Runtime with IBM Fusion Object Storage integration, from prerequisites to your first model deployment.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start (5 Minutes)](#quick-start-5-minutes)
3. [Detailed Installation](#detailed-installation)
4. [Configuration Guide](#configuration-guide)
5. [Deploy Your First Model](#deploy-your-first-model)
6. [Verify Installation](#verify-installation)
7. [Next Steps](#next-steps)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required

- **Red Hat OpenShift Cluster** 4.20 or later
- **Cluster Admin Access** - Required for operator installation
- **GPU Nodes** - At least one node with NVIDIA GPUs for model inference
- **Helm CLI** - Version 3.8 or later ([Install Helm](https://helm.sh/docs/intro/install/))
- **OpenShift CLI (oc)** - Matching your cluster version ([Install oc](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html))

### IBM Fusion for AI Components

- **IBM Fusion Object Storage** - Required for Model Registry and Workbench storage (via OpenShift Data Foundation)
- **OpenShift Data Foundation (ODF)** - Provides IBM Fusion Object Storage with automatic bucket provisioning
- **ArgoCD** - For GitOps deployment (optional but recommended for production)
- **Sealed Secrets** - For secure credential management in GitOps (optional)

### Cluster Requirements

```bash
# Minimum cluster resources
- 3 worker nodes (1 with GPU)
- 32 vCPUs total
- 128 GB RAM total
- 500 GB storage
- 1+ NVIDIA GPU (T4, V100, A100, etc.)
```

### Verify Prerequisites

```bash
# Check OpenShift version
oc version

# Check cluster nodes
oc get nodes

# Check GPU availability
oc get nodes -l nvidia.com/gpu.present=true

# Verify you have cluster-admin
oc auth can-i '*' '*' --all-namespaces
```

---

## Quick Start (5 Minutes)

For users who want to get started immediately with default settings:

### 1. Clone the Repository

```bash
git clone https://github.com/rh-ai-quickstart/maas-platform.git
cd maas-platform
```

### 2. Set Required Credentials

```bash
# IBM Fusion Object Storage credentials (if using IBM Fusion)
export IBM_ACCESS_KEY="your-access-key-id"
export IBM_SECRET_KEY="your-secret-access-key"
export IBM_ENDPOINT="https://s3.us-south.cloud-object-storage.appdomain.cloud"

# Keycloak admin password (optional, for authentication)
export ADMIN_PASSWORD="your-secure-admin-password"
export USER_PASSWORD="your-secure-user-password"
```

### 3. Install Runtime

```bash
# Install with default configuration
./scripts/install-runtime.sh examples/Fusion-Agentic-Assistance-Platform/runtime-values.yaml
```

### 4. Deploy a Model

```bash
# Wait for runtime to be ready (2-3 minutes)
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=300s

# Deploy your first model
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml
```

### 5. Verify

```bash
# Check model status
oc get llminferenceservice -n maas-models

# Get model endpoint
oc get route -n maas-models
```

**🎉 Congratulations!** You now have a running MaaS platform with your first model deployed.

---

## Detailed Installation

### Step 1: Prepare Your Environment

#### 1.1 Create a Working Directory

```bash
mkdir -p ~/maas-deployment
cd ~/maas-deployment
git clone https://github.com/rh-ai-quickstart/maas-platform.git
cd maas-platform
```

#### 1.2 Review Available Examples

```bash
# List available example configurations
ls -la examples/

# Fusion-Agentic-Assistance-Platform/     - Fusion Agentic Assistance Platform use case (recommended for first deployment)
# workbench-model-testing/  - Model testing workflow
# maas-runtime-gitops-deployment/  - GitOps deployment
# maas-model-service-gitops-deployment/  - Model GitOps deployment
```

#### 1.3 Choose Your Configuration

For your first deployment, we recommend starting with the `Fusion-Agentic-Assistance-Platform` example:

```bash
# Review the runtime configuration
cat examples/Fusion-Agentic-Assistance-Platform/values.yaml

# Review available models
ls examples/Fusion-Agentic-Assistance-Platform/models/
```

### Step 2: Configure Object Storage

The MaaS Runtime uses object storage for:
- **Model Registry**: Store model artifacts and versions
- **Workbench Storage**: User workspace data and notebooks
- **Model Catalog**: Cache downloaded models

#### Option A: IBM Fusion Object Storage (Recommended)

```bash
# Set IBM Fusion credentials
export IBM_ACCESS_KEY="your-access-key-id"
export IBM_SECRET_KEY="your-secret-access-key"
export IBM_ENDPOINT="https://s3.us-south.cloud-object-storage.appdomain.cloud"

# Verify credentials
curl -I "$IBM_ENDPOINT"
```

#### Option B: AWS S3

```bash
# Set AWS credentials
export AWS_ACCESS_KEY_ID="your-aws-access-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret-key"
export AWS_REGION="us-east-1"
```

#### Option C: MinIO (Development)

```bash
# Deploy MinIO in your cluster
oc new-project minio
oc apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: minio
  namespace: minio
spec:
  containers:
  - name: minio
    image: quay.io/minio/minio:latest
    command: ["minio", "server", "/data", "--console-address", ":9001"]
    env:
    - name: MINIO_ROOT_USER
      value: "minioadmin"
    - name: MINIO_ROOT_PASSWORD
      value: "minioadmin"
    ports:
    - containerPort: 9000
    - containerPort: 9001
EOF

# Expose MinIO
oc expose pod/minio --port=9000 -n minio
oc expose svc/minio -n minio

# Get MinIO endpoint
export MINIO_ENDPOINT="http://$(oc get route minio -n minio -o jsonpath='{.spec.host}')"
export MINIO_ACCESS_KEY="minioadmin"
export MINIO_SECRET_KEY="minioadmin"
```

### Step 3: Customize Configuration (Optional)

Create a custom values file based on your needs:

```bash
# Copy example configuration
cp examples/Fusion-Agentic-Assistance-Platform/runtime-values.yaml my-runtime-values.yaml

# Edit configuration
vi my-runtime-values.yaml
```

#### Key Configuration Options

```yaml
# Update cluster domain
global:
  wildcardDomain: apps.your-cluster.example.com

# Configure object storage
modelRegistry:
  objectStorage:
    type: ibm-fusion  # or 's3', 'minio'
    ibmFusion:
      endpoint: "https://s3.us-south.cloud-object-storage.appdomain.cloud"
      bucket: model-registry-artifacts
      region: us-south

# Configure user tiers
tiers:
  free:
    requestRates:
      - limit: 5
        window: 2m
  premium:
    requestRates:
      - limit: 20
        window: 2m

# Map users to tiers
userMapping:
  premium:
    - user1@example.com
    - user2@example.com
  enterprise:
    - admin@example.com
```

### Step 4: Install the Runtime

#### Using the Install Script (Recommended)

```bash
# Install with IBM Fusion
./scripts/install-runtime.sh examples/Fusion-Agentic-Assistance-Platform/runtime-values.yaml \
  --set modelRegistry.objectStorage.ibmFusion.accessKeyId="$IBM_ACCESS_KEY" \
  --set modelRegistry.objectStorage.ibmFusion.secretAccessKey="$IBM_SECRET_KEY" \
  --set modelRegistry.objectStorage.ibmFusion.endpoint="$IBM_ENDPOINT" \
  --set workbench.objectStorage.ibmFusion.accessKeyId="$IBM_ACCESS_KEY" \
  --set workbench.objectStorage.ibmFusion.secretAccessKey="$IBM_SECRET_KEY" \
  --set workbench.objectStorage.ibmFusion.endpoint="$IBM_ENDPOINT"
```

#### Using Helm Directly

```bash
# Install runtime
helm upgrade --install maas-runtime deploy/maas-runtime \
  -f examples/Fusion-Agentic-Assistance-Platform/runtime-values.yaml \
  --set modelRegistry.objectStorage.ibmFusion.accessKeyId="$IBM_ACCESS_KEY" \
  --set modelRegistry.objectStorage.ibmFusion.secretAccessKey="$IBM_SECRET_KEY" \
  --set modelRegistry.objectStorage.ibmFusion.endpoint="$IBM_ENDPOINT" \
  --set workbench.objectStorage.ibmFusion.accessKeyId="$IBM_ACCESS_KEY" \
  --set workbench.objectStorage.ibmFusion.secretAccessKey="$IBM_SECRET_KEY" \
  --set workbench.objectStorage.ibmFusion.endpoint="$IBM_ENDPOINT" \
  --create-namespace \
  --wait \
  --timeout 15m
```

### Step 5: Monitor Installation Progress

```bash
# Watch operator installation
watch oc get csv -A

# Watch DataScienceCluster creation
watch oc get datasciencecluster

# Check all components
oc get pods -n redhat-ods-operator
oc get pods -n redhat-ods-applications
oc get pods -n kuadrant-system

# Wait for DataScienceCluster to be ready
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=600s
```

**Expected Installation Time**: 5-10 minutes

---

## Configuration Guide

### Understanding the Configuration Structure

The MaaS Runtime configuration is organized into several key sections:

#### 1. Global Settings

```yaml
global:
  wildcardDomain: apps.cluster.example.com  # Your cluster's wildcard domain
  modelsNamespace: maas-models              # Namespace for model deployments
  toolsImage: image-registry.openshift-image-registry.svc:5000/openshift/tools:latest
```

#### 2. Operators

```yaml
operators:
  enabled: true  # Set to false if operators are already installed
  openshiftAI:
    enabled: true
    channel: fast-3.x
    startingCSV: rhods-operator.3.3.0
```

#### 3. LLM-D Configuration (Default Model Serving)

```yaml
llmd:
  enabled: true
  defaultRuntime: true  # Use llm-d as default
  servingRuntime:
    defaultEngine: vllm  # Default inference engine
    defaultImage: registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.3.0
    gpuEnabled: true
```

#### 4. Model Catalog

```yaml
modelCatalog:
  enabled: true
  huggingface:
    enabled: true
    organization: rh-aiservices-bu  # Red Hat curated models
  modelImport:
    autoImport: true
    schedule: "0 2 * * *"  # Daily at 2 AM
```

#### 5. Model Registry

```yaml
modelRegistry:
  enabled: true
  objectStorage:
    type: ibm-fusion
    ibmFusion:
      endpoint: "https://s3.us-south.cloud-object-storage.appdomain.cloud"
      bucket: model-registry-artifacts
```

#### 6. Workbench Storage

```yaml
workbench:
  enabled: true
  objectStorage:
    defaultType: ibm-fusion
    ibmFusion:
      autoCreateBuckets: true  # Auto-create per-user buckets
      bucketSuffix: workbench
```

#### 7. Tier-Based Access Control

```yaml
tiers:
  free:
    requestRates:
      - limit: 5
        window: 2m
    tokenRates:
      - limit: 100
        window: 1m
  premium:
    requestRates:
      - limit: 20
        window: 2m
    tokenRates:
      - limit: 10000
        window: 1m
```

### Configuration Best Practices

1. **Start with Examples**: Use provided examples as templates
2. **Secure Credentials**: Never commit credentials to Git
3. **Use Sealed Secrets**: For GitOps deployments
4. **Test in Dev First**: Validate configuration in non-production
5. **Document Changes**: Keep track of customizations

---

## Deploy Your First Model

### Option 1: Using the Deploy Script

```bash
# Deploy GPT-OSS-20B model
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml

# Deploy Nemotron model
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/nemotron-values.yaml
```

### Option 2: Using Helm Directly

```bash
# Deploy a model
helm upgrade --install gpt-oss-20b deploy/maas-model-service \
  -f examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml \
  --create-namespace \
  --wait
```

### Option 3: Create Custom Model Configuration

```bash
# Create custom model values
cat > my-model-values.yaml <<EOF
model:
  name: my-custom-model
  displayName: "My Custom Model"
  namespace: maas-models

source:
  uri: oci://registry.example.com/models/my-model:latest

inference:
  engine: vllm
  replicas: 1
  extraArgs:
    - --max-model-len=131072
    - --gpu-memory-utilization=0.9

resources:
  limits:
    nvidia.com/gpu: "1"
    memory: 24Gi
  requests:
    cpu: "4"
    memory: 16Gi

tiers:
  - premium
  - enterprise

rateLimit:
  enabled: true

monitoring:
  enabled: true
EOF

# Deploy custom model
./scripts/deploy-model.sh my-model-values.yaml
```

### Monitor Model Deployment

```bash
# Watch model deployment
watch oc get llminferenceservice -n maas-models

# Check model pods
oc get pods -n maas-models

# View model logs
oc logs -f -n maas-models -l serving.kserve.io/inferenceservice=gpt-oss-20b

# Wait for model to be ready
oc wait --for=condition=Ready llminferenceservice/gpt-oss-20b -n maas-models --timeout=600s
```

### Exposing the Gateway for External Access

By default, the inference gateway service is only accessible within the cluster (ClusterIP). To access your models externally, you need to expose the gateway service.

#### Option 1: Automatic Exposure (via values file)

Add the following to your model values file:

```yaml
gateway:
  exposeExternally: true
```

Then deploy your model:

```bash
./scripts/deploy-model.sh examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml
```

The script will automatically expose the gateway and provide the external URL.

#### Option 2: Manual Exposure

If you prefer to expose the gateway manually:

```bash
# 1. Verify the gateway service name
oc get svc -n openshift-ingress

# 2. Expose the service (on IBM Fusion HCI)
oc expose service openshift-ai-inference-openshift-ai-inference -n openshift-ingress

# 3. Get the external route
oc get route openshift-ai-inference -n openshift-ingress

# 4. Construct your model endpoint
# Pattern: https://<route-host>/<namespace>/<model-name>
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')
echo "Model endpoint: https://$GATEWAY_HOST/maas-models/gpt-oss-20b"
```

**Note**: The service name may differ in other OpenShift environments. Always verify with `oc get svc -n openshift-ingress` first.

#### Test External Access

```bash
# Get the gateway host
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')

# Get authentication token
TOKEN=$(oc whoami -t)

# List available models
curl -k "https://${GATEWAY_HOST}/maas-models/gpt-oss-20b/v1/models" \
  -H "Authorization: Bearer ${TOKEN}"

# Test inference
curl -k -X POST "https://${GATEWAY_HOST}/maas-models/gpt-oss-20b/v1/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "prompt": "Write a Python function to calculate fibonacci numbers:",
    "max_tokens": 100
  }'
```

---

## Verify Installation

### 1. Check Runtime Components

```bash
# DataScienceCluster status
oc get datasciencecluster default-dsc -o yaml

# Operators
oc get csv -n redhat-ods-operator
oc get csv -n kuadrant-system

# Kuadrant
oc get kuadrant -n kuadrant-system

# Model Catalog
oc get modelcatalog -n redhat-ods-applications

# Model Registry
oc get modelregistry -n rhoai-model-registries
```

### 2. Check Model Deployments

```bash
# List all models
oc get llminferenceservice -n maas-models

# Check model status
oc describe llminferenceservice gpt-oss-20b -n maas-models

# View model endpoints
oc get routes -n maas-models
```

### 3. Test Model Inference

```bash
# Get model endpoint
MODEL_URL=$(oc get route gpt-oss-20b -n maas-models -o jsonpath='{.spec.host}')

# Test inference (if authentication is disabled)
curl -X POST "https://$MODEL_URL/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "prompt": "Write a Python function to calculate fibonacci numbers:",
    "max_tokens": 100
  }'
```

### 4. Access Dashboards

```bash
# OpenShift AI Dashboard
oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'

# Grafana (if enabled)
oc get route grafana-route -n grafana -o jsonpath='{.spec.host}'

# Model Registry UI
oc get route model-registry -n rhoai-model-registries -o jsonpath='{.spec.host}'
```

### 5. Verify Object Storage

```bash
# Check Model Registry storage
oc get secret model-registry-storage -n rhoai-model-registries

# Check Workbench storage
oc get secret workbench-storage -n rhods-notebooks

# List buckets (if using IBM Fusion)
aws s3 ls --endpoint-url "$IBM_ENDPOINT"
```

---

## Next Steps

### 1. Explore Features

- **[Model Catalog](02-model-catalog-and-registry/MODEL_CATALOG_GUIDE.md)**: Discover and import models from HuggingFace
- **[Model Registry](02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md)**: Version and manage model artifacts
- **[Workbench Storage](04-workbench-configuration/WORKBENCH_STORAGE_GUIDE.md)**: Configure object storage for workbenches
- **[Model Testing](../examples/workbench-model-testing/README.md)**: Test models in workbenches

### 2. Deploy Additional Models

```bash
# Browse available models in catalog
oc get models -n redhat-ods-applications

# Deploy from catalog
# (See Model Catalog Guide for details)
```

### 3. Set Up GitOps

```bash
# Deploy runtime via ArgoCD
cd examples/maas-runtime-gitops-deployment
oc apply -f argocd/appproject.yaml
oc apply -f argocd/application.yaml

# Deploy models via ArgoCD
cd examples/maas-model-service-gitops-deployment
oc apply -f argocd/appproject.yaml
oc apply -f argocd/gpt-oss-20b-app.yaml
```

### 4. Configure Monitoring

```bash
# Access Grafana dashboards
GRAFANA_URL=$(oc get route grafana-route -n grafana -o jsonpath='{.spec.host}')
echo "Grafana: https://$GRAFANA_URL"

# View Prometheus metrics
PROMETHEUS_URL=$(oc get route prometheus-k8s -n openshift-monitoring -o jsonpath='{.spec.host}')
echo "Prometheus: https://$PROMETHEUS_URL"
```

### 5. Create Workbenches

```bash
# Create a workbench for model testing
oc apply -f examples/workbench-model-testing/workbench-config.yaml

# Access workbench
oc get route -n rhods-notebooks
```

---

## Troubleshooting

### Common Issues

#### 1. Operators Not Installing

**Symptom**: Operators stuck in "Installing" state

```bash
# Check operator status
oc get csv -A | grep -E "Installing|Failed"

# View operator logs
oc logs -n openshift-operators -l name=rhods-operator

# Check subscription
oc get subscription -A
```

**Solution**:
```bash
# Delete and recreate subscription
oc delete subscription rhods-operator -n redhat-ods-operator
helm upgrade --install maas-runtime deploy/maas-runtime -f your-values.yaml
```

#### 2. DataScienceCluster Not Ready

**Symptom**: DSC stuck in "Progressing" state

```bash
# Check DSC status
oc get datasciencecluster default-dsc -o yaml

# Check component status
oc get pods -n redhat-ods-applications
```

**Solution**:
```bash
# Check for resource constraints
oc describe nodes | grep -A 5 "Allocated resources"

# Increase timeout
oc wait --for=condition=Ready datasciencecluster/default-dsc --timeout=900s
```

#### 3. Model Deployment Fails

**Symptom**: LLMInferenceService not becoming ready

```bash
# Check model status
oc describe llminferenceservice gpt-oss-20b -n maas-models

# Check pod events
oc get events -n maas-models --sort-by='.lastTimestamp'

# Check pod logs
oc logs -n maas-models -l serving.kserve.io/inferenceservice=gpt-oss-20b
```

**Common Causes**:
- Insufficient GPU resources
- Image pull errors
- Storage issues
- Resource limits too low

**Solution**:
```bash
# Check GPU availability
oc get nodes -l nvidia.com/gpu.present=true

# Increase resources
helm upgrade gpt-oss-20b deploy/maas-model-service \
  -f examples/Fusion-Agentic-Assistance-Platform/models/gpt-oss-values.yaml \
  --set resources.limits.memory=32Gi
```

#### 4. Object Storage Connection Issues

**Symptom**: Cannot connect to IBM Fusion or S3

```bash
# Test connectivity
curl -I "$IBM_ENDPOINT"

# Check credentials
oc get secret model-registry-storage -n rhoai-model-registries -o yaml

# Verify bucket access
aws s3 ls s3://model-registry-artifacts --endpoint-url "$IBM_ENDPOINT"
```

**Solution**:
```bash
# Update credentials
helm upgrade maas-runtime deploy/maas-runtime \
  -f your-values.yaml \
  --set modelRegistry.objectStorage.ibmFusion.accessKeyId="$NEW_ACCESS_KEY" \
  --set modelRegistry.objectStorage.ibmFusion.secretAccessKey="$NEW_SECRET_KEY"
```

#### 5. Rate Limiting Not Working

**Symptom**: Rate limits not being enforced

```bash
# Check RateLimitPolicy
oc get ratelimitpolicy -n maas-models

# Check Kuadrant
oc get kuadrant -n kuadrant-system

# Check Limitador
oc get pods -n kuadrant-system -l app=limitador
```

**Solution**:
```bash
# Restart Limitador
oc delete pod -n kuadrant-system -l app=limitador

# Verify policy
oc describe ratelimitpolicy gpt-oss-20b-ratelimit -n maas-models
```

### Getting Help

#### Check Logs

```bash
# Runtime logs
oc logs -n redhat-ods-operator -l name=rhods-operator

# Model logs
oc logs -n maas-models -l serving.kserve.io/inferenceservice=<model-name>

# Kuadrant logs
oc logs -n kuadrant-system -l app=kuadrant-operator
```

#### Collect Debug Information

```bash
# Create debug bundle
mkdir -p debug-info
oc get all -n redhat-ods-operator -o yaml > debug-info/ods-operator.yaml
oc get all -n maas-models -o yaml > debug-info/models.yaml
oc get datasciencecluster -o yaml > debug-info/dsc.yaml
oc get events -A --sort-by='.lastTimestamp' > debug-info/events.txt
```

#### Community Support

- **GitHub Issues**: [Report issues](https://github.com/rh-ai-quickstart/maas-platform/issues)
- **Documentation**: [Full documentation](../README.md)
- **Examples**: [Example configurations](../examples/)

---

## Summary

You've successfully:

✅ Installed the MaaS Runtime platform  
✅ Configured object storage  
✅ Deployed your first model  
✅ Verified the installation  
✅ Learned troubleshooting basics  

### What's Next?

- **Scale Up**: Deploy more models for different use cases
- **Customize**: Adjust tier limits and user mappings
- **Monitor**: Set up Grafana dashboards
- **Automate**: Implement GitOps workflows
- **Optimize**: Fine-tune resource allocation

### Key Resources

- [Model Catalog Guide](02-model-catalog-and-registry/MODEL_CATALOG_GUIDE.md)
- [Model Registry Guide](02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md)
- [Workbench Storage Guide](04-workbench-configuration/WORKBENCH_STORAGE_GUIDE.md)
- [GitOps Deployment](../examples/maas-runtime-gitops-deployment/README.md)
- [Model Testing](../examples/workbench-model-testing/README.md)

---

**Need Help?** Check our [troubleshooting section](#troubleshooting) or [open an issue](https://github.com/rh-ai-quickstart/maas-platform/issues).

**Ready for Production?** Review our [GitOps deployment guide](../examples/maas-runtime-gitops-deployment/README.md) for best practices.