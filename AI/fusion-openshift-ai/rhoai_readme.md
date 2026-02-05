# Red Hat OpenShift AI Installation with Ansible

This Ansible playbook automates the installation of Red Hat OpenShift AI (RHOAI) on an OpenShift cluster.

**Playbook:** https://github.ibm.com/ProjectAbell/Fusion-AI/blob/main/fusion-openshift-ai/install-openshift-ai.yaml

## What This Installs

The playbook deploys Red Hat OpenShift AI, including:

### Operator Installation
- **Red Hat OpenShift AI Operator** in the `redhat-ods-operator` namespace
- Automated approval and completion of the operator's InstallPlan
- Operator lifecycle management through OLM (Operator Lifecycle Manager)

### Core Components
The playbook creates and configures:

1. **DataScienceCluster Initialization (DSCI)** - Sets up the foundational infrastructure:
   - Applications namespace: `redhat-ods-applications`
   - Monitoring namespace: `redhat-ods-monitoring`
   - Service Mesh integration with Istio
   - Trusted CA bundle configuration

2. **DataScienceCluster (DSC)** - Deploys the following managed components:
   - **Dashboard** - Web interface for OpenShift AI
   - **Workbenches** - Jupyter notebook environments
   - **Data Science Pipelines** - Kubeflow Pipelines for ML workflows
   - **KServe** - Model serving platform (RawDeployment mode)
   - **Ray** - Distributed computing framework
   - **Training Operator** - Distributed training for ML models
   - **Model Registry** - Model versioning and management
   - **Feast Operator** - Feature store for ML
   - **LlamaStack Operator** - LLM deployment and management


### Removed/Disabled Components
The following components are explicitly set to `Removed` or not managed:
- CodeFlare (for distributed workloads)
- TrustyAI (for AI explainability)
- Kueue (job queueing)
- ModelMesh Serving (alternative model serving)
- Knative Serving

## Prerequisites

Before running this playbook, ensure you have:

### 1. OpenShift Cluster Access
- A running OpenShift 4.x cluster
- Cluster administrator privileges

### 2. OpenShift CLI (oc)
Install the OpenShift CLI:
https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/cli_tools/openshift-cli-oc#cli-getting-started

### 3. Ansible Installation
Install Ansible and required collections:
```bash
# Install Ansible
pip install ansible

# Install Kubernetes collection
ansible-galaxy collection install kubernetes.core
```

### 4. Cluster Login
Log in to your OpenShift cluster as a cluster administrator:
```bash
oc login <cluster-api-url> -u <username> -p <password>

# Or using a token:
oc login --token=<token> --server=<cluster-api-url>

# Verify you have cluster-admin privileges:
oc whoami
oc auth can-i create namespace --all-namespaces
```

## Installation Instructions

### Step 1: Log in to OpenShift
```bash
oc login https://api.your-cluster.example.com:6443
```

### Step 2: Run the Ansible Playbook
Execute the playbook with the following command:

```bash
ansible-playbook install-openshift-ai.yaml
```

### Step 3: Monitor Installation Progress
The playbook will:
1. Create the operator namespace
2. Deploy the OpenShift AI operator
3. Wait for and approve the InstallPlan
4. Wait for the operator to be ready
5. Create the DataScienceCluster initialization
6. Deploy the DataScienceCluster with configured components
7. Display a summary upon completion

**Estimated installation time:** 10-20 minutes, depending on cluster resources and network speed.

## Customization

### Modify Operator Channel
To use a different operator channel, edit the `operator_channel` variable:

```yaml
vars:
  operator_channel: "stable"  # Options: stable, fast, eus-2.x
```

### Adjust Component Configuration
Edit the `DataScienceCluster` definition in the playbook to enable/disable components:

```yaml
components:
  kueue:
    managementState: Managed  # Change from Removed to Managed to enable
```

## Accessing OpenShift AI

1. **Via OpenShift Console:**
   - Navigate to the OpenShift web console
   - Click the application launcher (grid icon) in the top navigation
   - Select "Red Hat OpenShift AI"

2. **Via Direct Route:**
   ```bash
   oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'
   ```

## Support

For issues and questions:
- Red Hat OpenShift AI Documentation: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed
