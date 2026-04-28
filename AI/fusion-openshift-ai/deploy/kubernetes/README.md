# Red Hat OpenShift AI Installation with Kubernetes Manifests

Deploy Red Hat OpenShift AI on IBM Fusion HCI using native Kubernetes manifests and the `oc` command-line tool. This guide covers direct YAML manifest deployment.

For general information about Red Hat OpenShift AI, architecture, components, and common prerequisites, see the [main documentation](../../README.md).

**Best for:** Quick prototyping, learning, CI/CD integration, and scenarios requiring direct control over resource definitions.

---

## Prerequisites

In addition to the [common prerequisites](../../README.md#prerequisites):

- `oc` CLI authenticated to your cluster
- Sufficient RBAC to create namespaces, operators, and custom resources

---

## Quick Start

### Step 1: Install the Operator

Deploy the Red Hat OpenShift AI operator:

```bash
oc apply -f fusion-openshift-ai/deploy/kubernetes/operator.yaml
```

This creates:
- Namespace: `redhat-ods-operator`
- OperatorGroup for the RHOAI operator
- Subscription to the `stable-3.x` channel

### Step 2: Wait for Operator to be Ready

Monitor the operator installation:

```bash
# Watch the ClusterServiceVersion
oc get csv -n redhat-ods-operator -w

# Wait for Succeeded phase
oc wait --for=jsonpath='{.status.phase}'=Succeeded \
  csv -l operators.coreos.com/rhods-operator.redhat-ods-operator \
  -n redhat-ods-operator \
  --timeout=600s
```

### Step 3: Deploy the DataScienceCluster

Once the operator is ready, create the DataScienceCluster:

```bash
oc apply -f fusion-openshift-ai/deploy/kubernetes/dsc.yaml
```

### Step 4: Monitor Deployment

```bash
# Check DataScienceCluster status
oc get datasciencecluster -n redhat-ods-operator

# Watch component deployment
oc get pods -n redhat-ods-operator -w
oc get pods -n redhat-ods-applications -w

# View detailed information
oc describe datasciencecluster default-dsc -n redhat-ods-operator
```

**Deployment Phases:**
1. **Operator Installation**: OLM installs the RHOAI operator
2. **CSV Succeeded**: Operator is ready and running
3. **DSC Creation**: DataScienceCluster resource is created
4. **Component Deployment**: Individual components are deployed
5. **Platform Ready**: All components are healthy and serving

---

## Understanding the Manifests

### Operator Manifest

The [`operator.yaml`](./operator.yaml) defines the operator installation through OLM:

#### Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: redhat-ods-operator
```

#### OperatorGroup
```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  upgradeStrategy: Default
```

#### Subscription
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: stable-3.x              # Update channel
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic   # Auto-approve updates
```

### DataScienceCluster Manifest

The [`dsc.yaml`](./dsc.yaml) defines the OpenShift AI platform configuration:

```yaml
apiVersion: datasciencecluster.opendatahub.io/v2
kind: DataScienceCluster
metadata:
  name: default-dsc
  namespace: redhat-ods-operator
spec:
  components:
    dashboard:
      managementState: Managed     # Enable component
    
    workbenches:
      managementState: Managed
    
    kserve:
      managementState: Managed
      rawDeploymentServiceConfig: Headless
      nim:
        managementState: Managed
```

---

## Customizing Component Configuration

### Enabling/Disabling Components

Each component can be individually controlled by setting `managementState`:
- **`Managed`** → Component is enabled and deployed
- **`Removed`** → Component is disabled and not installed

---

## Required Changes for Different Configurations

When customizing the deployment, **must update**:

1. **Component Management State** (`managementState`)
   - Set to `Managed` to enable
   - Set to `Removed` to disable

2. **Component-Specific Configuration** (optional)
   - Namespace settings (e.g., `workbenchNamespace`, `registriesNamespace`)
   - Service configuration (e.g., `rawDeploymentServiceConfig`)
   - Feature flags (e.g., NIM integration)

### Optional Customizations

**Change operator update channel:**
```yaml
# In operator.yaml
spec:
  channel: fast-3.x  # Options: stable-3.x, fast-3.x, eus-3.x
```

**Require manual approval for updates:**
```yaml
# In operator.yaml
spec:
  installPlanApproval: Manual
```

**Custom component namespaces:**
```yaml
# In dsc.yaml
workbenches:
  managementState: Managed
  workbenchNamespace: custom-notebooks

modelregistry:
  managementState: Managed
  registriesNamespace: custom-model-registry
```

**Configure TrustyAI restrictions:**
```yaml
trustyai:
  managementState: Managed
  eval:
    lmeval:
      permitCodeExecution: deny    # Security: deny code execution
      permitOnline: deny           # Security: deny online access
```

---

## Managing Deployments

### View Resources

```bash
# Check operator status
oc get csv -n redhat-ods-operator
oc get subscription rhods-operator -n redhat-ods-operator

# Check DataScienceCluster
oc get datasciencecluster -n redhat-ods-operator

# View all OpenShift AI pods
oc get pods -n redhat-ods-operator
oc get pods -n redhat-ods-applications
oc get pods -n rhods-notebooks
```

### Get Detailed Information

```bash
# Operator details
oc describe csv -l operators.coreos.com/rhods-operator.redhat-ods-operator \
  -n redhat-ods-operator

# DataScienceCluster details
oc describe datasciencecluster default-dsc -n redhat-ods-operator

# Component pod logs
oc logs <pod-name> -n redhat-ods-applications
```

### Update Configuration

Edit the DataScienceCluster manifest and reapply:

```bash
# Edit the file
vi fusion-openshift-ai/deploy/kubernetes/dsc.yaml

# Apply changes
oc apply -f fusion-openshift-ai/deploy/kubernetes/dsc.yaml
```

Or edit directly:
```bash
oc edit datasciencecluster default-dsc -n redhat-ods-operator
```

### Delete Resources

```bash
# Delete DataScienceCluster (keeps operator)
oc delete -f fusion-openshift-ai/deploy/kubernetes/dsc.yaml

# Delete operator
oc delete -f fusion-openshift-ai/deploy/kubernetes/operator.yaml

# Clean up remaining resources
oc delete namespace redhat-ods-applications
oc delete namespace rhods-notebooks
oc delete namespace rhoai-model-registries
```

---

## Accessing the OpenShift AI Dashboard

Once installed, access the OpenShift AI dashboard:

```bash
# Get dashboard URL
oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'
```

Or navigate via the OpenShift Console:
1. Go to **Networking → Routes** in the `redhat-ods-applications` namespace
2. Find the `rhods-dashboard` route
3. Click the URL to access the dashboard

---

## Troubleshooting

### Operator Installation Fails

Check the subscription and CSV:
```bash
oc get subscription rhods-operator -n redhat-ods-operator
oc get csv -n redhat-ods-operator
oc describe csv <csv-name> -n redhat-ods-operator
```

View operator pod logs:
```bash
oc get pods -n redhat-ods-operator
oc logs <operator-pod> -n redhat-ods-operator
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

### Component Deployment Issues

Check specific component status:
```bash
# Dashboard
oc get pods -n redhat-ods-applications -l app=rhods-dashboard

# Workbenches
oc get pods -n rhods-notebooks

# Model Registry
oc get pods -n rhoai-model-registries
```

### Storage Issues

Verify storage class availability:
```bash
oc get sc
oc get pvc -A | grep -E 'redhat-ods|rhods|rhoai'
```

### Manual Operator Update Approval

If using manual approval, approve pending install plans:
```bash
oc get installplan -n redhat-ods-operator
oc patch installplan <install-plan-name> -n redhat-ods-operator \
  --type merge \
  --patch '{"spec":{"approved":true}}'
```

---

## Verification Checklist

After deployment, verify the installation:

```bash
# 1. Operator is running
oc get csv -n redhat-ods-operator | grep Succeeded

# 2. DataScienceCluster is ready
oc get datasciencecluster -n redhat-ods-operator

# 3. Core pods are running
oc get pods -n redhat-ods-operator
oc get pods -n redhat-ods-applications

# 4. Dashboard is accessible
oc get route rhods-dashboard -n redhat-ods-applications

# 5. Storage is provisioned
oc get pvc -n redhat-ods-applications
```

---

## Additional Resources

- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- [OpenShift AI Architecture](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.15/html/introduction_to_red_hat_openshift_ai/architecture_openshift-ai)
- [OpenShift CLI Documentation](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)
- [Operator Lifecycle Manager Documentation](https://olm.operatorframework.io/)