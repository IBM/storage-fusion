# GitOps Deployment Guide

Deploy and manage Red Hat OpenShift AI on IBM Fusion HCI using **Red Hat OpenShift GitOps (Argo CD)**. This approach treats all OpenShift AI configuration as source-controlled infrastructure, with Argo CD continuously reconciling the cluster state against Git.

For general information about Red Hat OpenShift AI, architecture, components, and common prerequisites, see the [main documentation](../../README.md).

**Best for:** Production environments, multi-environment workflows, and teams practising GitOps methodologies.

---

## Prerequisites

In addition to the [common prerequisites](../../README.md#prerequisites):

- **Red Hat OpenShift GitOps operator** installed and in a `Ready` state
- Argo CD instance accessible (default namespace: `openshift-gitops`)
- Your fork/clone of this repository pushed to a Git remote that Argo CD can reach

Verify Argo CD is running:
```bash
oc get pods -n openshift-gitops
```

---

## Argo CD Access and Permissions

After verifying that all prerequisites are satisfied, ensure you can access the Argo CD instance deployed by the OpenShift GitOps operator.

### Authenticate to the cluster:
```bash
oc login --token=<TOKEN> --server=<API_SERVER>
```

To allow the GitOps application to create required resources (namespaces, operators, and custom resources), temporarily grant cluster-admin permissions (lab environments only) to the Argo CD application controller:
```bash
oc adm policy add-cluster-role-to-user cluster-admin \
  -z openshift-gitops-argocd-application-controller \
  -n openshift-gitops
```

This ensures the Argo CD controller can successfully reconcile all manifests defined in this guide.

**NOTE:** This approach is suitable for lab or proof-of-concept environments. In production, use a dedicated ServiceAccount with scoped RBAC permissions aligned with organizational security policies.

With cluster access and Argo CD permissions configured, you can now prepare your GitOps repository for deployment.

---

## Repository Setup

1. Fork the repository so it can serve as your GitOps source of truth.

2. Clone the forked copy of this repository:
```bash
git clone git@github.com:<your-username>/storage-fusion.git
```

3. Ensure you push any changes (such as repoURL updates) back to your fork before bootstrapping.

---

## Preparing Argo CD for RHOAI Installation

Before bootstrapping the installation, Argo CD must be configured to evaluate the health of RHOAI operator-managed resources correctly. By default, Argo CD does not evaluate the health of Operator Lifecycle Manager (OLM) resources, such as `ClusterServiceVersion` or custom resources like `DataScienceCluster`. Without custom health checks, the Application would remain in an `Unknown` state.

### Apply RBAC for Argo CD Patching

Apply the RBAC required to patch the Argo CD instance:
```bash
oc apply -f fusion-openshift-ai/deploy/gitops/patch/argocd-patch-rbac.yaml
```

Expected output:
```bash
serviceaccount/argocd-patch-sa created
clusterrole.rbac.authorization.k8s.io/argocd-patch-clusterrole created
clusterrolebinding.rbac.authorization.k8s.io/argocd-patch-clusterrolebinding created
```

### Patch Argo CD for Health Checks

Next, patch the Argo CD Custom Resource to enable health checks for RHOAI components:
```bash
oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  --patch-file fusion-openshift-ai/deploy/gitops/patch/argocd-resource-health-patch.yaml
```

Expected output:
```bash
argocd.argoproj.io/openshift-gitops patched
```

This configuration enables Argo CD to accurately evaluate Operator lifecycle resources and OpenShift AI custom resources, ensuring the Application transitions to `Healthy` only after the defined health conditions are met, including:
- `ClusterServiceVersion` = `Succeeded`
- `DSCInitialization` = `Ready`
- `DataScienceCluster` = `Ready`

---

## Bootstrapping the Installation with an Argo CD Application

The installation begins with a single Argo CD Application resource defined in Git.

### Update Repository URL

Before applying the Application, update the `source.repoURL` field in [`rhoai-application.yaml`](./rhoai-application.yaml) to point to your forked repository:

```yaml
spec:
  source:
    repoURL: https://github.com/<your-username>/storage-fusion.git
```

Ensure the repository URL matches the fork you cloned and are using as your GitOps source of truth.

### Apply the Argo CD Application

To bootstrap the installation, apply the Application directly from your local repository:
```bash
oc apply -f AI/fusion-openshift-ai/deploy/gitops/rhoai-application.yaml
```

Argo CD immediately begins reconciling the desired state defined in Git. The reconciliation loop continues indefinitely, ensuring configuration drift is automatically corrected.

This Application instructs Argo CD to deploy all manifests from the following Git path:
```
fusion-openshift-ai/deploy/gitops/rhoai
```

Sync is fully automated, meaning Argo CD will both install and continuously self-heal the platform:
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

Once this Application is applied, Argo CD becomes responsible for the complete RHOAI installation lifecycle, managing operator installation, RBAC setup, CR creation, and ongoing reconciliation of the platform state.

---

## Verifying the Installation in Argo CD

After applying the Argo CD Application, the installation can be verified directly from the OpenShift console.

Navigate to:

**Red Hat Applications → OpenShift GitOps → Cluster Argo CD**

This opens the Argo CD dashboard, where the `rhoai-install` application appears once synchronization completes. When prompted, log in using your OpenShift (OCP) credentials via the integrated OAuth authentication.

### Expected Application Status

Once synchronization completes successfully, the application should display:
- **Application Name:** `rhoai-install`
- **Sync Status:** `Synced`
- **Health Status:** `Healthy`
- All associated Kubernetes resources reconciled under GitOps management

A synced and `Healthy` state confirms that the desired configuration stored in Git matches the live cluster state and that the OpenShift AI components are functioning as expected.

---

## How Argo CD Drives the Installation Flow

After the Application is applied, Argo CD orchestrates the installation sequence using the manifests defined in Git.

All manifests are organized with Kustomize ([`kustomization.yaml`](./rhoai/kustomization.yaml)), allowing Argo CD to apply resources declaratively. The operator must become ready before the DataScienceCluster resource becomes `Healthy`:

1. Install the operator ([`operator.yaml`](./rhoai/operator.yaml))
2. Initialize the platform ([`dsc.yaml`](./rhoai/dsc.yaml))

### Operator Installation Through GitOps

The installation begins with [`operator.yaml`](./rhoai/operator.yaml), which installs the Red Hat OpenShift AI operator through OLM (Namespace, OperatorGroup, and Subscription). In this example, the operator installs from the `stable-3.x` update channel.

Argo CD monitors the operator installation until the `ClusterServiceVersion` reaches the `Succeeded` phase. Once the operator is ready, the `DataScienceCluster` custom resource triggers deployment of all dependent OpenShift AI components through the operator's reconciliation loop.

### Initializing the AI Platform with DataScienceCluster

Finally, Argo CD applies [`dsc.yaml`](./rhoai/dsc.yaml), creating the `DataScienceCluster` resource that triggers deployment of the full OpenShift AI platform.

From this point onward, Argo CD continuously reconciles the platform state with the desired configuration stored in Git.

---

## Customizing OpenShift AI Components

The `DataScienceCluster` specification is organized by platform components. Each component is controlled through a simple switch called `managementState`:
- **`Managed`** → the component is enabled and deployed
- **`Removed`** → the component is disabled and not installed

This makes the `DataScienceCluster` the central place to customize exactly what gets installed in your OpenShift AI platform.

### Components Enabled in This Setup (Managed)

In this configuration, the following core services are enabled:
- **Dashboard** – provides the OpenShift AI user interface
- **Workbenches** – enables notebook environments created within user projects
- **KServe** – activates model serving using raw deployment mode
  - **NIM integration** (if configured and supported by your RHOAI version)
- **Model Registry** – deployed into `rhoai-model-registries` for managing model metadata
- **TrustyAI** – enables responsible AI evaluation, with restricted execution and no online access
- **Data Science Pipelines** – provides workflow and pipeline orchestration
- **Ray** – enables distributed compute workloads
- **Training Operator** – supports Kubernetes-native model training workloads

These components represent the core services typically required in production AI environments.

### Components Explicitly Disabled (Removed)

Several optional operators are intentionally excluded to keep the platform lightweight:
- **Feast Operator** – feature store integration
- **Trainer** – additional training abstraction layer
- **MLflow Operator** – experiment tracking and model lifecycle tooling
- **Llama Stack Operator** – advanced LLM stack services
- **Kueue** – batch scheduling and queue-based workload orchestration

Marking these as `Removed` ensures they are not installed at all, reducing cluster overhead and operator sprawl.

### Modifying Component Configuration

To customize which components are deployed, edit the [`dsc.yaml`](./rhoai/dsc.yaml) file in your Git repository:

```yaml
spec:
  components:
    dashboard:
      managementState: Managed  # Change to Removed to disable
    
    workbenches:
      managementState: Managed
      workbenchNamespace: rhods-notebooks
    
    kserve:
      managementState: Managed
      rawDeploymentServiceConfig: Headless
```

After committing and pushing changes to Git, Argo CD will automatically reconcile the cluster state to match your updated configuration.

---

## Monitoring Deployment

After applying the Application, monitor the rollout to ensure all resources are created successfully.

```bash
# Check Argo CD application status
oc get application rhoai-install -n openshift-gitops

# Check operator status
oc get csv -n redhat-ods-operator

# Check DataScienceCluster status
oc get datasciencecluster -n redhat-ods-operator

# Watch pod creation
oc get pods -n redhat-ods-operator -w
oc get pods -n redhat-ods-applications -w
```

### Installation Phases

During startup, the OpenShift AI installation typically moves through these states:

1. **Operator Installation**: OLM installs the RHOAI operator
2. **CSV Succeeded**: Operator is ready and running
3. **DSC Creation**: DataScienceCluster resource is created
4. **Component Deployment**: Individual components are deployed
5. **Platform Ready**: All components are healthy and serving

---

## Accessing the OpenShift AI Dashboard

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

## Updating the Installation

To update the OpenShift AI configuration:

1. Edit the desired files in your Git repository (e.g., [`dsc.yaml`](./rhoai/dsc.yaml))
2. Commit and push changes to Git
3. Argo CD automatically detects changes and reconciles the cluster state

To manually trigger a sync:
```bash
# Via CLI
oc patch application rhoai-install -n openshift-gitops \
  --type merge \
  --patch '{"operation":{"initiatedBy":{"username":"manual-sync"}}}'

# Or use the Argo CD UI
```

---

## Troubleshooting

### Application Stuck in Progressing

Check the Argo CD application status:
```bash
oc describe application rhoai-install -n openshift-gitops
```

View sync operation details in the Argo CD UI or check pod logs:
```bash
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller
```

### Operator Installation Fails

Check the operator subscription and CSV:
```bash
oc get subscription rhods-operator -n redhat-ods-operator
oc get csv -n redhat-ods-operator
oc describe csv <csv-name> -n redhat-ods-operator
```

### DataScienceCluster Not Ready

Check the DSC status and events:
```bash
oc get datasciencecluster -n redhat-ods-operator
oc describe datasciencecluster default-dsc -n redhat-ods-operator
```

View component pod logs:
```bash
oc get pods -n redhat-ods-applications
oc logs <pod-name> -n redhat-ods-applications
```

### Health Check Issues

If Argo CD shows `Unknown` health status, verify the health check patch was applied:
```bash
oc get argocd openshift-gitops -n openshift-gitops -o yaml | grep -A 20 resourceHealthChecks
```

---

## Uninstalling

To remove the OpenShift AI installation:

1. Delete the Argo CD Application:
```bash
oc delete application rhoai-install -n openshift-gitops
```

2. Manually clean up remaining resources if needed:
```bash
oc delete datasciencecluster default-dsc -n redhat-ods-operator
oc delete subscription rhods-operator -n redhat-ods-operator
oc delete namespace redhat-ods-operator
oc delete namespace redhat-ods-applications
```

---

## Additional Resources

- [Red Hat OpenShift GitOps Documentation](https://docs.openshift.com/gitops/latest/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- [OpenShift AI Architecture](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.15/html/introduction_to_red_hat_openshift_ai/architecture_openshift-ai)
