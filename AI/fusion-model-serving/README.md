# GitOps-Driven Model Serving on Red Hat OpenShift AI with OpenShift GitOps (Argo CD) on IBM Fusion HCI
Model serving is where machine learning delivers real value, enabling applications to consume trained models through scalable, production-ready inference endpoints.

In this blog, we walk through a structured, GitOps-native approach to serving open-source LLMs on Red Hat OpenShift AI (RHOAI) using KServe and vLLM. Deployments are fully declarative and managed through Red Hat OpenShift GitOps (Argo CD), making model rollouts as simple as committing a YAML change. Running the stack on IBM Fusion HCI further simplifies GPU, storage, and operator readiness for enterprise AI workloads.

By the end of this guide, you will have:
  - A GitOps-managed InferenceService deployment using Red Hat OpenShift GitOps
  - A vLLM runtime serving an open-source LLM
  - External access enabled through OpenShift Routes
  - Continuous reconciliation of model-serving resources through GitOps workflows

Instead of manually creating InferenceServices and configuring serving runtimes, this approach uses Git as the single source of truth. Every model deployment becomes version-controlled, reviewable, and automatically reconciled by Argo CD.

### Model Serving with Red Hat OpenShift AI
Red Hat OpenShift AI (RHOAI) extends the capabilities of Red Hat OpenShift to deliver a consistent, enterprise-ready hybrid AI and MLOps platform. It provides tooling across the full lifecycle of AI/ML workloads, including training, serving, monitoring, and managing models and AI-enabled applications.

For details, refer to the official documentation: [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.2)

### Why GitOps for Model Serving?

Model serving environments often require frequent iteration: model versions change, resource requirements evolve, and new inference endpoints are introduced. Managing these deployments manually quickly becomes error-prone.

GitOps solves this by treating model serving configuration as source-controlled infrastructure. With Argo CD continuously reconciling the cluster against Git, deployments become:
  - Versioned and auditable
  - Fully automated
  - Self-healing
  - Consistent across environments
    
This repository provides a reusable GitOps pattern capable of deploying any supported model through KServe.

## GitOps Directory Structure
The fusion-model-serving GitOps application follows a clean layered architecture managed through Red Hat OpenShift GitOps (Argo CD).
#### Directory Layout 

```bash
fusion-model-serving/
├── README.md 
├── gitops/
│   ├── models/
│   │   ├── kustomization.yaml           # Kustomize base
│   │   ├── kserve-model-serving.yaml    # InferenceService template
│   │   ├── inferenceservice-config.yaml # ODH webhook ConfigMap
│   │   ├── rbac.yaml                    # Argo CD permissions for KServe
│   └── model-serving-application.yaml   # Model-serving Argo CD Application CR
└── scripts/
    └── expose-model.sh                  # OpenShift Route creation helper
```

#### How It All Fits Together
The application uses a two-layer GitOps pattern:
1.	Argo CD Application CR (model-serving-application.yaml) - defines what to deploy, where to deploy it, and how to customize it via Kustomize patches.
2.	Kustomize Base (gitops/models/) - contains the actual Kubernetes manifests (InferenceService, RBAC, ConfigMaps) as reusable templates.
The Application CR patches the base at sync time, injecting the right model name, resource limits, labels, and namespace without ever touching the base manifests. This means the base is truly reusable across different model deployments.

---

## Prerequisites
Before deploying the GitOps-based model serving stack on IBM Fusion HCI, ensure the following infrastructure and platform components are ready.

#### Cluster and Platform Requirements
  - IBM Fusion HCI cluster installed, running, and healthy
  - Red Hat OpenShift Container Platform 4.18 or later accessible
  - At least one worker node capable of running AI workloads
    - GPU-enabled if serving large language models (LLMs)
    
#### GPU Enablement (Required for LLM Serving)
If serving GPU-backed models such as vLLM-based LLMs, the following components must be installed:
  - NVIDIA GPU Operator
  - Node Feature Discovery (NFD) for hardware detection
  - Worker nodes labeled with: `nvidia.com/gpu.present=true`
    
Verify GPU availability:
```bash
oc describe node <worker-node> | grep -i gpu
```
If GPUs are not detected, ensure the NVIDIA drivers and operator are correctly installed.

#### Storage Configuration
Model serving workloads require persistent storage for:
  - Model caching
  - Runtime artifacts
  - Serving configuration
Ensure:
  - A default StorageClass is configured
  - Sufficient persistent storage capacity is available
Verify: `oc get sc`

If no default StorageClass is set, configure one using IBM Fusion Data Foundation or another supported storage provider.

#### Required Platform Operators
The following operators must be installed and in a Ready state:
  - Red Hat OpenShift GitOps (Argo CD)
    - Enables declarative, Git-driven deployment and reconciliation.
  - Red Hat OpenShift AI (RHOAI)
    - Provides KServe, ODH Model Controller, and AI platform components.
  - Red Hat OpenShift Service Mesh 3
    - Required for KServe networking and internal traffic management.

#### Access and Permissions
  - `oc` CLI configured and authenticated to your OpenShift cluster
  - Cluster-admin or sufficient RBAC to create namespaces, roles, and Argo CD Applications
  - Access to the Argo CD UI and `oc apply` permissions in the `openshift-gitops` namespace

---
## Argo CD Access and Permissions
After verifying that all prerequisites are satisfied, ensure you can access the Argo CD instance deployed by the OpenShift GitOps operator.

#### Authenticate to the cluster:
```bash
oc login --token=<TOKEN> --server=<API_SERVER>
```
To allow the GitOps application to create required resources (namespaces, roles, rolebindings, and KServe custom resources), grant elevated permissions to the Argo CD application controller:
```bash
oc adm policy add-cluster-role-to-user cluster-admin \
  -z openshift-gitops-argocd-application-controller \
  -n openshift-gitops
```
This ensures the Argo CD controller can successfully reconcile all manifests defined in this guide.

**NOTE:** This approach is suitable for lab or proof-of-concept environments.
In production, use a dedicated ServiceAccount with scoped RBAC permissions aligned with organizational security policies.

With cluster access and Argo CD permissions configured, you can now prepare your GitOps repository for deployment.

---

## Repository Setup

1. Fork the [storage-fusion](https://github.com/IBM/storage-fusion) repository on GitHub. Forking is required because your fork becomes the Git source monitored by Argo CD.
  > **Note:** The `fusion-model-serving` directory is located under the `AI/` parent directory within the `storage-fusion` repository (path: `storage-fusion/AI/fusion-model-serving`).

2. Clone the forked copy of this repository:
```bash
   git clone git@github.com:<your-username>/storage-fusion.git
```

3. Login to your cluster using `oc login` or by exporting the KUBECONFIG:
```bash
   oc login --token=<TOKEN> --server=<API_SERVER>
```
---

## Deploying the Model Serving Application 

Model serving is deployed using an Argo CD Application that continuously syncs Kubernetes manifests from Git.

### Apply the Argo CD Application
Before applying the Application, update the `source.repoURL` field in model-serving-application.yaml to point to your forked repository:
```bash
spec:
  source:
    repoURL: https://github.com/<your-username>/storage-fusion.git
```
Ensure the repository URL matches the fork you cloned and are using as your GitOps source of truth.


Apply the application YAML:
```bash
oc apply -f fusion-model-serving/gitops/model-serving-application.yaml
```

This creates an Argo CD Application that points to:
```
fusion-model-serving/gitops/models
```
The Application name defaults to llmops-models but can be customized in the Application manifest metadata.

This creates an Argo CD Application (llmops-models) in the openshift-gitops namespace, which points to:
  - **Git repository path:** fusion-model-serving/gitops/models
  - **Target namespace**: test-model-serving (default)
The target namespace can be customized directly in the Application manifest by modifying `spec.destination.namespace`.



Once applied, Argo CD will automatically:
  - **Create the target namespace** (test-model-serving) where all model-serving resources will be deployed.
  - **Provision RBAC permissions** (ServiceAccounts, Roles, RoleBindings) required for KServe and model pods to run securely.
  - **Generate ConfigMaps** such as model-config, which defines the model to be served — by default ibm-granite/granite-3.2-8b-instruct.
  - **Deploy the InferenceService CR**, triggering OpenShift AI + KServe to launch the Granite predictor workload on IBM Fusion HCI.
  - **Create Kubernetes Services** (via KServe) and optionally expose them externally using OpenShift Routes.

Any drift from the declared Git state is automatically corrected by Argo CD.

### Monitor Deployment

After applying the Application, monitor the rollout to ensure all resources are created successfully.

Watch the deployment progress:

```bash
# Check Argo CD application status
oc get application llmops-models -n openshift-gitops

# Monitor InferenceService
oc get inferenceservice -n test-model-serving

# Watch pod creation
oc get pods -n test-model-serving -w
```

#### Model Deployment Phases

During startup, the model typically moves through these states:
  - **Pending** - Waiting for scheduling onto a GPU-enabled Fusion HCI worker node
  - **ContainerCreating** - Container image pulling and initialization
  - **Running** - vLLM container started, and model download begins
  - **Ready** - Model fully loaded and serving inference traffic


## Argo CD Application View

After applying the Argo CD Application, the deployment can be verified from the OpenShift console.

Navigate to:

**Red Hat Applications → OpenShift GitOps → Cluster Argo CD**

<p align="center"><img width="309" alt="argocd" src="https://github.com/user-attachments/assets/437f0463-61d9-4e11-86b0-af2a65a9c3a9" /><p>

When prompted, log in using your OpenShift (OCP) credentials via the integrated OAuth authentication.

This opens the Argo CD dashboard, where the llmops-models application will appear once synchronization completes.


### Expected Application Status

Once the Argo CD application is successfully synced, it will appear in the Argo CD UI as shown below.

The application should display:
- **Application Name:** `llmops-models`
- **Sync Status:** `Synced`
- **Health Status:** `Healthy`
- All Kubernetes resources managed under GitOps

<img width="3102" height="1642" alt="model-serving" src="https://github.com/user-attachments/assets/56de81c6-85b5-4e8a-9b50-0ba6a9fd2af1" />


---
## Exposing the Model for External Access
By default, KServe creates internal ClusterIP services for InferenceServices. These services are not externally accessible in OpenShift unless explicitly exposed using a Route or Ingress.

By default, KServe InferenceServices are only accessible within the cluster. To make them available to external applications (dashboards, APIs, or client tools), use the included expose-model.sh script to create an OpenShift Edge-terminated Route.

The `expose-model.sh` utility automatically generates OpenShift Routes with TLS encryption, making your models available outside the cluster.

It supports two usage modes:

#### 1. Expose All Models in a Namespace

To expose every deployed InferenceService in a given namespace:
```bash
# Expose all models in a namespace
./scripts/expose-model.sh <namespace>
```

```bash
# Example
./scripts/expose-model.sh test-model-serving
```

This will:
  - Discover all InferenceServices in the namespace
  - Create TLS-secured OpenShift Routes for each model
  - Display the external access URLs and test commands

#### 2. Expose a Specific Model
To expose only a single model (example: Granite):

```bash
# Expose a specific model (InferenceService) in a namespace
./scripts/expose-model.sh <inferenceservice> <namespace>
```

```bash
# Example
./scripts/expose-model.sh granite-3-2-8b-instruct test-model-serving
```

This is useful when multiple models are deployed, but only one should be made externally accessible.

#### What the Script Does

When executed, the `expose-model.sh` script automates the entire external exposure process by:
  - Validating resources - Confirms that the InferenceService and its backing Kubernetes Service are present
  - Creating an OpenShift Route - Sets up an edge-terminated TLS Route for secure access
  - Enabling HTTPS connectivity - Ensures traffic is encrypted using TLS termination at the router
  - Printing the model endpoint URL - Outputs the external HTTPS URL for immediate use
  - Generating test commands - Provides ready-to-run curl examples to verify the deployment

#### Example Output

```bash
╔════════════════════════════════════════════════════════════╗
║         Expose Models - External Access                    ║
╚════════════════════════════════════════════════════════════╝

Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Namespace: test-model-serving
  Mode:      Expose ALL InferenceServices
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Found InferenceServices:
  - granite-3-2-8b-instruct

Processing: granite-3-2-8b-instruct
  ✓ Exposed at: https://granite-3-2-8b-instruct-external-test-model-serving.apps.cluster.example.com

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Successfully exposed 1 InferenceService(s)!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test your models:
  granite-3-2-8b-instruct:
    curl -k https://granite-3-2-8b-instruct-external-test-model-serving.apps.cluster.example.com/v1/models -H 'Authorization: Bearer EMPTY'
```

#### Testing External Access

Once exposed, test your model with OpenAI-compatible API calls:

```bash
# Get the route URL
ROUTE_URL=$(oc get route granite-3-2-8b-instruct-external -n test-model-serving -o jsonpath='{.spec.host}')

# List available models
curl -k https://${ROUTE_URL}/v1/models \
  -H "Authorization: Bearer EMPTY"

# Test chat completions
curl -k -X POST https://${ROUTE_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer EMPTY" \
  -d '{
    "model": "ibm-granite/granite-3.2-8b-instruct",
    "messages": [
      {"role": "user", "content": "Explain about Red Hat Openshift AI"}
    ],
    "max_tokens": 200,
    "temperature": 0.7
  }'

```
---

## Customizing the Model Serving Application

The deployment is designed with stable base manifests, while customization is handled through the OpenShift GitOps Application resource.

Instead of editing multiple YAML files, model name, resources, and metadata are adjusted using spec.source.kustomize.patches. This keeps the setup reusable and allows you to serve different models by changing only a few values.

All customization happens in the Argo CD Application manifest, while the base templates remain reusable and unchanged.

Customization is grouped into three key areas.

### 1. Application Identity and Labels
The first customization controls the labels applied across all resources deployed by this application.

Within the Application YAML, the following patch overrides the commonLabels defined in the base Kustomization:

```
- target:
    kind: Kustomization
  patch: |-
    - op: replace
      path: /commonLabels/app.kubernetes.io~1name
      value: llmops-models
    - op: replace
      path: /commonLabels/validated-patterns.io~1pattern
      value: llmops-platform
```
To customize this for a different application, users only need to change the values:
  - Change `llmops-models` to the desired application name
  - Change `llmops-platform` to match the target platform or environment label

For example:

``` value: text-generation-serving```

This ensures that all resources deployed by Argo CD automatically carry the correct application identity.
### 2. Selecting the Model to Serve

The model served by this deployment is configured through the model-config ConfigMap.

The Argo CD Application YAML includes a patch that sets the Hugging Face model reference:
```
- target:
    kind: ConfigMap
    name: model-config
  patch: |-
    - op: replace
      path: /data/MODEL_NAME
      value: ibm-granite/granite-3.2-8b-instruct
```
Updating the MODEL_NAME value is sufficient to deploy a different model from Hugging Face. The serving runtime automatically consumes this configuration through environment injection into the InferenceService.

For example, to serve Mistral:

```
value: mistralai/Mistral-7B-Instruct-v0.2
```
At runtime, the InferenceService reads the model reference from this ConfigMap and dynamically pulls the model during startup. 

This approach enables fully Git-driven model switching, requiring only a single configuration change without modifying the serving manifests.

### 3. Configuring the InferenceService Deployment

This patch customizes the deployed InferenceService by defining its service identity, model labeling, and runtime resource requirements. All updates are applied together in a single patch to ensure consistent serving behavior.

In the Application YAML, the following patch defines these values:
```
- target:
    kind: InferenceService
  patch: |-
    - op: replace
      path: /metadata/name
      value: granite-3-2-8b-instruct
    - op: replace
      path: /metadata/labels/model
      value: granite
    - op: replace
      path: /spec/predictor/containers/0/resources/limits/nvidia.com~1gpu
      value: "1"
    - op: replace
      path: /spec/predictor/containers/0/resources/limits/memory
      value: "16Gi"
    - op: replace
      path: /spec/predictor/containers/0/resources/requests/nvidia.com~1gpu
      value: "1"
    - op: replace
      path: /spec/predictor/containers/0/resources/requests/memory
      value: "16Gi"
```

  - `metadata.name` defines the Kubernetes InferenceService name, which becomes the serving endpoint identifier.
  - `labels.model` adds a model-family label (granite) for tracking, filtering, and observability.
  - `limits.nvidia.com/gpu` sets the maximum GPU count the serving container can consume during inference.
  - `limits.memory` caps the memory usage to prevent resource exhaustion or OOM termination.
  - `requests.nvidia.com/gpu` ensures the pod is scheduled only on nodes with an available GPU by reserving one.
  - `requests.memory` reserves the required RAM upfront to guarantee stable scheduling and startup.

By configuring both requests and limits, this patch ensures predictable GPU-backed model serving and makes the application flexible enough to support anything from lightweight models to GPU-heavy LLM workloads.

Ensure that the requested GPU and memory values align with the actual node capacity. 
If insufficient resources are available, the InferenceService will remain Pending.

---

## Key Takeaways
In this guide, we deployed an open-source LLM on Red Hat OpenShift AI using KServe and vLLM through a structured, GitOps-driven workflow.

By leveraging OpenShift GitOps (Argo CD), model serving becomes declarative, version-controlled, and continuously reconciled — allowing updates and scaling through simple Git changes.

Running the stack on IBM Fusion HCI simplifies GPU enablement, storage integration, and operator readiness, providing a consistent path from experimentation to scalable AI deployments.

Platform operators manage infrastructure, while GitOps governs model lifecycle, creating a clean separation of responsibilities for reliable AI operations.


