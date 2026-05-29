# From Registry to Production: Deploying AI Models with OpenShift AI and IBM Fusion

## Introduction: The Challenge of AI Model Deployment at Scale

In today's AI-driven landscape, organizations face a critical challenge: how do you move from experimenting with AI models to deploying them reliably in production? The journey from a model artifact to a production-ready inference endpoint involves numerous steps—version management, resource allocation, monitoring, security, and governance.

This is where **OpenShift AI's Model Registry** combined with **IBM Fusion's MaaS (Model-as-a-Service) Runtime** creates a powerful solution. In this blog, we'll walk through deploying the **Granite 3.1 8B Instruct** model directly from the Model Registry to a production-ready inference endpoint—all with a single command.

**What you'll learn:**
- How model-registry-based deployment simplifies AI operations
- Step-by-step deployment of the Granite 3.1 8B Instruct model
- Customizing deployments for different models and environments
- Enabling monitoring, rate limiting, and external access
- Best practices for production AI deployments

## Why Model Registry Matters

Before diving into the deployment, let's understand why a centralized Model Registry is crucial:

**Traditional Approach (Without Registry):**
```
Developer → Manual artifact upload → Manual configuration → Deployment
```
- Error-prone manual steps
- No version tracking
- Difficult to reproduce deployments
- Limited governance

**Model Registry Approach:**
```
Developer → Register model → Automated deployment → Production
```
- Single source of truth for model artifacts
- Automatic version management
- Reproducible deployments
- Built-in governance and audit trails

## Architecture: How It All Fits Together

The deployment workflow orchestrates several components seamlessly:

```
┌─────────────────────────────────┐
│  OpenShift AI Model Registry    │
│  (Centralized Model Storage)    │
└────────────┬────────────────────┘
             │ Query Model Metadata
             ▼
┌─────────────────────────────────┐
│    Deployment Script            │
│    (deploy-model.sh)            │
└────────────┬────────────────────┘
             │ Resolve Model URI
             ▼
┌─────────────────────────────────┐
│  Helm Chart (maas-model-service)│
└────────────┬────────────────────┘
             │ Generate Resources
             ▼
┌─────────────────────────────────┐
│   LLMInferenceService (KServe)  │
└────────────┬────────────────────┘
             │ Deploy Pods
             ▼
┌─────────────────────────────────┐
│  Inference Pods (vLLM Runtime)  │
└────────────┬────────────────────┘
             │ Expose Endpoint
             ▼
┌─────────────────────────────────┐
│  Gateway / Routes               │
│  (External Access)              │
└─────────────────────────────────┘
```

**The magic happens automatically:**
1. ✅ Validates model exists in registry
2. ✅ Retrieves latest version and artifact URI
3. ✅ Generates Kubernetes resources
4. ✅ Creates inference service with proper configuration
5. ✅ Exposes secure endpoints
6. ✅ Enables observability and governance

## Prerequisites: What You Need Before Starting

Before deploying your first model, ensure these components are in place:

### 1. OpenShift AI Platform

Verify the platform is running:
```bash
oc get pods -n redhat-ods-applications
```

### 2. Model Registry

Confirm the registry is available:
```bash
oc get modelregistry -n rhoai-model-registries
```

### 3. MaaS Runtime

Check that the runtime layer is installed:
```bash
helm list -A | grep maas-runtime
```

**Pro Tip:** The deployment script uses registry metadata to resolve model artifacts automatically—no manual URI configuration needed!

## Understanding the Deployment Configuration

Let's explore the configuration file that drives our deployment:

**File:** `examples/model-registry-deployment/granite-3.1-8b-instruct-values.yaml`

### Model Identity

```yaml
model:
  name: granite-31-8b-instruct-version-1
  displayName: "Granite 3.1 8B Instruct - Version 1"
  namespace: deploy-models-rhoai
```

This defines:
- **name**: Kubernetes resource identifier (used in all Kubernetes resources)
- **displayName**: Human-readable name shown in OpenShift AI console
- **namespace**: Deployment target namespace

### Model Registry Integration

```yaml
modelRegistry:
  enabled: true
  name: model-registry
  namespace: rhoai-model-registries
  registeredModelName: "granite-3.1-8b-instruct"
  connectionSecret: "model-registry-connection"
  createConnectionSecret: false
```

**Here's what happens behind the scenes:**

When you deploy, the script:
1. Connects to the Model Registry in `rhoai-model-registries` namespace
2. Searches for the registered model `granite-3.1-8b-instruct`
3. Retrieves the registered model ID and latest version
4. Extracts the artifact URI (OCI image location)
5. Updates Helm values dynamically

**Result:** You don't need to specify the source URI manually!

```yaml
source:
  uri: ""  # Automatically resolved from registry at deploy time
```

**Connection Secret:**
The `model-registry-connection` secret contains OCI registry credentials for pulling model artifacts. With `createConnectionSecret: false`, the deployment reuses an existing namespace-level secret, allowing multiple models to share the same credentials efficiently.

### Inference Engine Configuration

```yaml
inference:
  engine: vllm
  replicas: 1
  env:
    - name: VLLM_ADDITIONAL_ARGS
      value: "--max-model-len=32768 --gpu-memory-utilization=0.95"
```

**Key parameters:**
- **engine**: vLLM (optimized for LLM inference)
- **replicas**: Number of serving instances
- **max-model-len**: Context window size (32K tokens)
- **gpu-memory-utilization**: GPU allocation (95%)

### Resource Allocation

```yaml
resources:
  limits:
    cpu: "2"
    memory: 4Gi
  requests:
    cpu: "2"
    memory: 4Gi
```

**For production workloads, scale up:**

```yaml
resources:
  limits:
    cpu: "16"
    memory: 64Gi
    nvidia.com/gpu: "1"
  requests:
    cpu: "8"
    memory: 32Gi
    nvidia.com/gpu: "1"
```

### GPU Node Scheduling

```yaml
scheduling:
  tolerations:
    - effect: NoSchedule
      key: nvidia.com/gpu
      operator: Exists
```

This ensures inference pods land on GPU-enabled nodes.

### Monitoring (Enabled by Default)

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
```

**Metrics collected:**
- Request count and latency
- Throughput and error rates
- GPU utilization
- Model-specific performance metrics

### Rate Limiting (Production-Ready)

The Granite 3.1 8B Instruct configuration comes with **rate limiting enabled by default**:

```yaml
rateLimiting:
  enabled: true
  customLimits:
    free:
      requestRates:
        - limit: 10
          window: 1m
    premium:
      requestRates:
        - limit: 100
          window: 1m
    enterprise:
      requestRates:
        - limit: 1000
          window: 1m
```

**Tier-based access control:**
```yaml
tiers:
  - free
  - premium
  - enterprise
```

This creates separate `RateLimitPolicy` resources for each tier, integrating with Kuadrant and Gateway API for sophisticated traffic management.

## Deployment: From Zero to Production in Minutes

Now for the exciting part—deploying the model!

### Step 1: Navigate to the Repository

```bash
cd quickstarts/model-as-a-service
```

### Step 2: Verify the Model

```bash
./scripts/query-model-registry.sh --model granite-3.1-8b-instruct
```

**Expected output:**
```
✓ Model found: granite-3.1-8b-instruct
✓ Latest version: 1
✓ Artifact URI: oci://registry.redhat.io/...
```

### Step 3: Deploy

```bash
./scripts/deploy-model.sh \
  examples/model-registry-deployment/granite-3.1-8b-instruct-values.yaml
```

**What happens during deployment:**

```
[1/8] Validating model registry connection...
[2/8] Querying model metadata...
[3/8] Resolving artifact URI...
[4/8] Deploying Helm chart...
[5/8] Creating LLMInferenceService...
[6/8] Generating routes and services...
[7/8] Configuring monitoring...
[8/8] Running readiness checks...

✓ Deployment complete!
```

### Step 4: Monitor Deployment Progress

```bash
# Watch pods come online
oc get pods -n deploy-models-rhoai -w
```

**Deployment timeline:**

| Time | Status | What's Happening |
|------|--------|------------------|
| 0-2 min | LLMInferenceService created | Resource created, waiting for pods |
| 2-5 min | Pods starting | Pulling container images |
| 5-10 min | Model loading | Downloading model artifacts from registry |
| 10-15 min | Service ready | Model loaded, inference operational |

**Note:** First-time deployments take longer due to image and model downloads. Subsequent deployments are much faster!

## Verification: Ensuring Everything Works

After deployment, let's verify all components are operational.

### Quick Verification Script

```bash
# Set your model details
MODEL_NAME="granite-31-8b-instruct-version-1"
NAMESPACE="deploy-models-rhoai"

echo "=== Checking LLMInferenceService ==="
oc get llminferenceservice ${MODEL_NAME} -n ${NAMESPACE}

echo -e "\n=== Checking Pods ==="
oc get pods -n ${NAMESPACE}

echo -e "\n=== Checking HTTPRoute ==="
oc get httproute -n ${NAMESPACE}

echo -e "\n=== Checking Gateway Routes ==="
oc get route -n openshift-ingress | grep openshift-ai-inference

echo -e "\n=== Checking ServiceMonitor ==="
oc get servicemonitor -n ${NAMESPACE}

echo -e "\n=== Getting Gateway URL ==="
GATEWAY_HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')
echo "Gateway URL: https://${GATEWAY_HOST}"
echo "Model Endpoint: https://${GATEWAY_HOST}/${NAMESPACE}/${MODEL_NAME}"
```

### Expected Resources

**1. LLMInferenceService (Primary Resource)**
```bash
oc get llminferenceservice -n deploy-models-rhoai
```
```
NAME                              READY   AGE
granite-31-8b-instruct-version-1  True    13m
```

**2. Running Pods**
```bash
oc get pods -n deploy-models-rhoai
```
```
NAME                                                       READY   STATUS    AGE
granite-31-8b-instruct-version-1-kserve-79ddbd6796-zx4xh   2/2     Running   13m
granite-31-8b-instruct-version-1-router-scheduler-84ff     1/1     Running   13m
```

**3. ServiceMonitor (Metrics Collection)**
```bash
oc get servicemonitor -n deploy-models-rhoai
```
```
NAME                              AGE
granite-31-8b-instruct-version-1  14m
kserve-llm-isvc-scheduler         14m
```

**4. Gateway Route (External Access)**
```bash
oc get route -n openshift-ingress | grep openshift-ai-inference
```
```
openshift-ai-inference   openshift-ai-inference-openshift-ingress.apps.cluster.com
```

## Testing Your Model: First Inference Request

Let's validate the endpoint with a real inference request!

### Get Authentication Token

```bash
TOKEN=$(oc whoami -t)
```

### Get Gateway Host

```bash
HOST=$(oc get route openshift-ai-inference -n openshift-ingress -o jsonpath='{.spec.host}')
```

### List Available Models

```bash
curl -k \
  https://${HOST}/deploy-models-rhoai/granite-31-8b-instruct-version-1/v1/models \
  -H "Authorization: Bearer ${TOKEN}"
```

**Expected response:**
```json
{
  "data": [
    {
      "id": "granite-31-8b-instruct-version-1"
    }
  ]
}
```

### Execute Inference Request

```bash
curl -k -X POST \
  https://${HOST}/deploy-models-rhoai/granite-31-8b-instruct-version-1/v1/completions \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "granite-31-8b-instruct-version-1",
    "prompt": "Explain Retrieval Augmented Generation in simple terms",
    "max_tokens": 128
  }'
```

**Successful response confirms:**
- ✅ Model downloaded and loaded
- ✅ Runtime initialized correctly
- ✅ Endpoint operational
- ✅ Gateway routing functional
- ✅ Authentication working

## Customization: Adapting to Your Needs

The beauty of this approach is its flexibility. Here are common customizations:

### Deploy a Different Model

Simply change the registered model name and update the resource name:

```yaml
modelRegistry:
  registeredModelName: "qwen3-8b-fp8-dynamic"

model:
  name: qwen3-8b-version-1
  displayName: "Qwen 3 8B FP8 Dynamic - Version 1"
```

### Scale for High Availability

```yaml
inference:
  replicas: 3  # Multiple instances for load balancing
```

### Increase Context Window

```yaml
inference:
  env:
    - name: VLLM_ADDITIONAL_ARGS
      value: "--max-model-len=65536"  # 64K context
```

### Customize Rate Limiting

Adjust limits based on your use case:

```yaml
rateLimiting:
  enabled: true
  customLimits:
    free:
      requestRates:
        - limit: 5
          window: 1m
    premium:
      requestRates:
        - limit: 50
          window: 1m
    enterprise:
      requestRates:
        - limit: 500
          window: 1m
```

### Add GPU Resources

```yaml
resources:
  limits:
    nvidia.com/gpu: "2"  # Multi-GPU deployment
  requests:
    nvidia.com/gpu: "2"
```

### Configure Node Affinity

```yaml
scheduling:
  nodeSelector:
    accelerator: nvidia-a100
  tolerations:
    - effect: NoSchedule
      key: nvidia.com/gpu
      operator: Exists
```

## Troubleshooting: Common Issues and Solutions

### Issue: Pods Not Starting

**Check pod status:**
```bash
oc get pods -n deploy-models-rhoai
oc describe pod <pod-name> -n deploy-models-rhoai
```

**Common causes:**
- Insufficient GPU resources
- Image pull errors
- Node scheduling issues

### Issue: Model Not Loading

**Check logs:**
```bash
oc logs -n deploy-models-rhoai <pod-name> -c kserve-container
```

**Common causes:**
- Incorrect model URI
- Registry authentication issues
- Insufficient memory

### Issue: Endpoint Not Accessible

**Verify route:**
```bash
oc get route -n openshift-ingress
oc describe route openshift-ai-inference -n openshift-ingress
```

**Common causes:**
- Gateway not configured
- Route not created
- Certificate issues

## Best Practices for Production Deployments

### 1. Resource Planning
- **Development**: 1 replica, minimal resources
- **Staging**: 2 replicas, production-like resources
- **Production**: 3+ replicas, full resources with autoscaling

### 2. Monitoring and Observability
- Always enable ServiceMonitor
- Set up alerts for latency and error rates
- Monitor GPU utilization

### 3. Security
- Use rate limiting to prevent abuse
- Implement proper RBAC policies
- Rotate authentication tokens regularly

### 4. Version Management
- Use semantic versioning for models
- Test new versions in staging first
- Implement blue-green deployments for zero-downtime updates

### 5. Cost Optimization
- Right-size GPU resources
- Use autoscaling for variable workloads
- Monitor and optimize context window sizes

## Conclusion: The Power of Automated AI Deployment

Deploying AI models from the OpenShift AI Model Registry to production-ready inference endpoints doesn't have to be complex. With the MaaS Runtime Helm chart and IBM Fusion, you get:

**✅ Automation**: One command deploys everything
**✅ Consistency**: Reproducible deployments across environments
**✅ Governance**: Built-in version control and audit trails
**✅ Observability**: Integrated monitoring and metrics
**✅ Scalability**: Easy to scale from dev to production
**✅ Flexibility**: Customize for any model or use case

The **Granite 3.1 8B Instruct** model deployment we walked through demonstrates a production-ready configuration with rate limiting, monitoring, and external access enabled by default. This same approach works for any model in your registry—from small code assistants to large language models.

**What's Next?**
- Explore multi-model deployments
- Implement A/B testing with model versions
- Set up automated CI/CD pipelines for model updates
- Integrate with your MLOps workflows

Ready to deploy your first model? Clone the repository and follow along:

```bash
git clone <repository-url>
cd quickstarts/model-as-a-service
./scripts/deploy-model.sh examples/model-registry-deployment/granite-3.1-8b-instruct-values.yaml
```

Happy deploying! 🚀

---

## Additional Resources

- **Documentation**: [MaaS Platform Guide](../01-setup/MAAS_OPERATORS_GUIDE.md)
- **Examples**: [Model Registry Deployment Examples](../../examples/model-registry-deployment/)
- **Customization**: [Runtime Customization Guide](../01-setup/MAAS_RUNTIME_CUSTOMIZATION_GUIDE.md)
- **Operations**: [Adding Models to Registry](../02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md)

## About the MaaS Runtime

The MaaS (Model-as-a-Service) Runtime is part of a comprehensive platform for deploying and managing AI models on IBM Fusion with OpenShift AI. It consists of four layers:

1. **maas-operators**: Core operator installations
2. **maas-platform**: OpenShift AI platform configuration
3. **maas-runtime**: Model registry and gateway setup
4. **maas-model-service**: Individual model deployments ← This blog

Each layer builds on the previous one, creating a complete AI deployment platform.