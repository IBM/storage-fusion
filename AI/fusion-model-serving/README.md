# Model Serving on Red Hat OpenShift AI on IBM Fusion

This repository demonstrates how **Red Hat OpenShift GitOps** and **Red Hat OpenShift AI** can be combined on **IBM Fusion** to enable **simple, scalable, GitOps-driven model serving using KServe**.

By bringing together:
- **OpenShift AI** for data science and model serving
- **OpenShift GitOps (Argo CD)** for declarative deployments

we enable a repeatable and production-ready approach to deploy and manage AI/LLM models on IBM Fusion.

---

## Prerequisites

### 1. OpenShift Cluster Access
- A running **Red Hat OpenShift 4.x** cluster (on IBM Fusion)
- Cluster administrator privileges

### 2. OpenShift CLI (`oc`)
Install the OpenShift CLI by following the official documentation:

https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/cli_tools/openshift-cli-oc#cli-getting-started

Verify installation:
```bash
oc version
```

### 3. Red Hat OpenShift AI

Red Hat OpenShift AI must be installed before proceeding.

Follow the README below to install OpenShift AI using the provided Ansible automation: Fusion-AI/fusion-openshift-ai/rhoai_readme.md

### 4. Red Hat OpenShift GitOps

OpenShift GitOps (Argo CD) is required to deploy model serving resources using GitOps.

Follow the README below to install OpenShift GitOps: Fusion-AI/fusion-gitops-argocd/docs/FusionGitOpsGuide.md

## Repository Setup

1. Fork the Fusion-AI repository on GitHub. It is necessary to fork because your fork will be updated as part of the GitOps and DevOps processes.

2. Clone the forked copy of this repository:
```bash
   git clone git@github.com:<your-username>/Fusion-AI.git
```

3. Login to your cluster using `oc login` or by exporting the KUBECONFIG:
```bash
   oc login
```

## Deploy Model Serving via GitOps

Model serving is deployed using an Argo CD Application that continuously syncs Kubernetes manifests from Git.

### Apply the Argo CD Application

Apply the application YAML:
```bash
oc apply -f fusion-model-serving/gitops/llmops-application.yaml
```

This creates an Argo CD Application that points to:
```
fusion-model-serving/gitops/models
```

## Accessing the Argo CD Console

After installation, access the Argo CD UI from:

Red Hat Applications → OpenShift GitOps → Cluster Argo CD

<p align="center"><img width="308" alt="image" src="https://github.ibm.com/user-attachments/assets/8076101f-8dd2-49db-b2f2-35d2832ddea9" /></p>


ArgoCD console:

<p align="center"><img width="1049" alt="image" src="https://github.ibm.com/user-attachments/assets/f6bb488e-d842-4408-9a26-8a428b6bd5b9" /></p>


## Argo CD Authentication Methods

There are two ways authenticate via log in.

**OpenShift Authentication**

Users in the cluster-admins group can log in using OpenShift credentials.

**Local Admin User**

Login to the cluster:

```bash
oc login --token=<TOKEN> --server=<API_SERVER>
```

Grant the required permissions:

```bash
oc adm policy add-cluster-role-to-user cluster-admin \
  -z openshift-gitops-argocd-application-controller \
  -n openshift-gitops
```

Retrieve the Argo CD admin password:

```bash
argoPass=$(oc get secret/openshift-gitops-cluster \
  -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d)

echo $argoPass
```

## What Gets Deployed

The GitOps application creates the following resources in the `default-dsc` namespace:

### Namespace
* `default-dsc` – Default namespace used by OpenShift AI for model serving

### Core Resources

**RBAC**
* Grants Argo CD permission to manage KServe resources

**ConfigMap**
* Required for OpenShift AI / ODH webhook validation

**InferenceService (KServe)**
* Deploys an LLM using vLLM
* Exposes an OpenAI-compatible API
* Requests GPU resources

**Missing CRDs (if required)**
* Ensures smooth reconciliation in environments where CRDs may not yet exist

All resources are managed declaratively through GitOps and continuously reconciled by Argo CD.
While OpenShift authentication is recommended for production environments, the local admin user is practical for learning, demos, and troubleshooting scenarios.

## Argo CD Application View

Once the Argo CD application is successfully synced, it will appear in the Argo CD UI as shown below.

The application should display:
- **Application Name:** `llmops-models`
- **Sync Status:** `Synced`
- **Health Status:** `Healthy`
- All Kubernetes resources managed under GitOps

<p align="center"><img width="1725" alt="Screenshot 2026-02-03 at 10 01 17 AM" src="https://github.ibm.com/user-attachments/assets/92cd649e-e18e-4d72-ab33-34b1b8983b34" /></p>



## Deploying a Different Model

You can deploy any supported model by modifying the InferenceService definition.

### Path to Update
```
fusion-model-serving/gitops/models/kserve-model-serving.yaml
```

### What You Can Change

* Model name (Hugging Face / custom model)
* Container image (vLLM, Triton, custom runtime)
* GPU / CPU / memory requests
* Environment variables

### Once Committed and Pushed

* Argo CD automatically syncs changes
* The new model is deployed without manual intervention

## Summary

This setup demonstrates how IBM Fusion, OpenShift AI, and OpenShift GitOps work together to:

* Simplify LLM and model serving
* Enable GitOps-driven, repeatable deployments
* Leverage GPUs efficiently on IBM Fusion
* Allow teams to deploy and switch models with minimal effort

🚀 **Model serving becomes as simple as a Git commit.**

