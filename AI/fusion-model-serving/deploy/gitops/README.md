
# GitOps Deployment Guide

Deploy and manage model serving on Red Hat OpenShift AI using **Red Hat OpenShift GitOps (Argo CD)**. This approach treats all model serving configuration as source-controlled infrastructure, with Argo CD continuously reconciling the cluster state against Git.

For general information about model serving, architecture, supported models, and common prerequisites, see the [main documentation](../../README.md).

**Best for:** Production environments, multi-environment workflows, and teams practising GitOps methodologies.

## Prerequisites

In addition to the [common prerequisites](../../README.md#prerequisites):

- **Red Hat OpenShift GitOps operator** installed and in a `Ready` state
- Argo CD instance accessible (default namespace: `openshift-gitops`)
- Your fork/clone of this repository pushed to a Git remote that Argo CD can reach

Verify Argo CD is running:
```bash
oc get pods -n openshift-gitops
```
## Argo CD Access and Permissions
After verifying that all prerequisites are satisfied, ensure you can access the Argo CD instance deployed by the OpenShift GitOps operator.

#### Authenticate to the cluster:
```bash
oc login --token=<TOKEN> --server=<API_SERVER>
```
To allow the GitOps application to create required resources (namespaces, roles, rolebindings, and KServe custom resources), temporarily grant cluster-admin permissions (lab environments only) to the Argo CD application controller:
```bash
oc adm policy add-cluster-role-to-user cluster-admin \
  -z openshift-gitops-argocd-application-controller \
  -n openshift-gitops
```
This ensures the Argo CD controller can successfully reconcile all manifests defined in this guide.

**NOTE:** This approach is suitable for lab or proof-of-concept environments.
In production, use a dedicated ServiceAccount with scoped RBAC permissions aligned with organizational security policies.

With cluster access and Argo CD permissions configured, you can now prepare your GitOps repository for deployment.

    
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
oc apply -f fusion-model-serving/deploy/gitops/applications/model-serving-application.yaml
```

This creates an Argo CD Application that points to:
```
fusion-model-serving/deploy/gitops/cluster
```
The Application name defaults to llmops-models but can be customized in the Application manifest metadata.

This creates an Argo CD Application (llmops-models) in the openshift-gitops namespace, which points to:
  - **Git repository path:** fusion-model-serving/deploy/gitops/cluster
  - **Target namespace**: model-serving (default)
The target namespace can be customized directly in the Application manifest by modifying `spec.destination.namespace`.



Once applied, Argo CD will automatically:
  - **Create the target namespace** (model-serving) if namespace auto-creation is enabled in the sync policy.
  - **Provision RBAC permissions** (Roles, RoleBindings) required for KServe and model pods to run securely.
  - **Deploy the InferenceService CR**, triggering OpenShift AI + KServe to launch the predictor workload on IBM Fusion HCI.- by default ibm-granite/granite-3.2-8b-instruct.
  - **Create internal Kubernetes Services** (via KServe), and external access is optional and must be configured separately using OpenShift Routes.

Any drift from the declared Git state is automatically corrected by Argo CD.

### Monitor Deployment

After applying the Application, monitor the rollout to ensure all resources are created successfully.

Watch the deployment progress:

```bash
# Check Argo CD application status
oc get application llmops-models -n openshift-gitops

# Monitor InferenceService
oc get inferenceservice -n model-serving

# Watch pod creation
oc get pods -n model-serving -w
```

#### Model Deployment Phases

During startup, the model-serving workload typically moves through these states:

- Pending: Waiting for scheduling onto a GPU-enabled Fusion HCI worker node
- ContainerCreating: Container image pulling and initialization
- Running: vLLM container started, and model download begins
- Ready: Model fully loaded and serving inference traffic

These states primarily reflect the lifecycle of the predictor pod created by the KServe InferenceService, with final readiness determined by the InferenceService status.


## Argo CD Application View

After applying the Argo CD Application, the deployment can be verified from the OpenShift console.

Navigate to:

**Red Hat Applications → OpenShift GitOps → Cluster Argo CD**

<p align="center"><img width="309" alt="image" src="https://github.ibm.com/user-attachments/assets/030d4eb7-2dca-4bd8-9476-d517ecaf4486" /><p>


When prompted, log in using your OpenShift (OCP) credentials via the integrated OAuth authentication.

This opens the Argo CD dashboard, where the llmops-models application will appear once synchronization completes.


### Expected Application Status

Once the Argo CD application is successfully synced, it will appear in the Argo CD UI as shown below.

The application should display:
- **Application Name:** `llmops-models`
- **Sync Status:** `Synced`
- **Health Status:** `Healthy`
- All Kubernetes resources managed under GitOps

<p align="center"><img width="1725" alt="model-serving" src="https://github.ibm.com/user-attachments/assets/0497640d-1b0d-4a27-b469-b0b92f0120fb" /></p>


---

## Customizing the Model Serving Application

The deployment is designed with stable base manifests, while customization is handled through the OpenShift GitOps Application resource.

Instead of editing multiple YAML files, model name, resources, and metadata are adjusted using spec.source.kustomize.patches. This keeps the setup reusable and allows you to serve different models by changing only a few values.

All customization happens in the Argo CD Application manifest, while the base templates remain reusable and unchanged.

Customization is grouped into two key areas.

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

### 2. Configuring the Model and InferenceService Deployment

The model name and all InferenceService settings are configured together in a single patch. The model is set directly as an environment variable on the container — no ConfigMap is involved. This avoids naming conflicts when multiple models are deployed to the same namespace.

In the Application YAML, the following patch defines the model identity, resource requirements, and serving configuration:
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
      path: /spec/predictor/containers/0/env/0/value
      value: ibm-granite/granite-3.2-8b-instruct
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
  - `env[0].value` sets the Hugging Face model ID (`MODEL`) passed directly to the vLLM container — no ConfigMap required. To serve a different model, update this value only. For example, to serve Mistral: `value: mistralai/Mistral-7B-Instruct-v0.2`
  - `limits.nvidia.com/gpu` sets the maximum GPU count the serving container can consume during inference.
  - `limits.memory` caps the memory usage to prevent resource exhaustion or OOM termination.
  - `requests.nvidia.com/gpu` ensures the pod is scheduled only on nodes with an available GPU by reserving one.
  - `requests.memory` reserves the required RAM upfront to guarantee stable scheduling and startup.

By configuring both requests and limits, this patch ensures predictable GPU-backed model serving and makes the application flexible enough to support anything from lightweight models to GPU-heavy LLM workloads.

Ensure that the requested GPU and memory values align with the actual node capacity.
If insufficient resources are available, the InferenceService will remain Pending.


## Additional Resources

- [Red Hat OpenShift GitOps Documentation](https://docs.openshift.com/gitops/latest/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [KServe Documentation](https://kserve.github.io/website/)
- [vLLM Documentation](https://docs.vllm.ai/)
- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)

