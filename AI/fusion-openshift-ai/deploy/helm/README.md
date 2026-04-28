# Red Hat OpenShift AI Installation with Helm Charts

Deploy Red Hat OpenShift AI on IBM Fusion HCI using **Helm charts**. This guide covers Helm-specific deployment steps and configuration.

For general information about Red Hat OpenShift AI, architecture, components, and common prerequisites, see the [main documentation](../../README.md).

**Best for:** Templated deployments, component customization, teams familiar with Helm workflows.

---

## Prerequisites

In addition to the [common prerequisites](../../README.md#prerequisites):

- **Helm 3.x** installed on your workstation

Install Helm if needed:
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

---

## Quick Start

### Deploy with Default Configuration

Deploy Red Hat OpenShift AI with default component settings:

```bash
helm install rhoai-platform ./fusion-openshift-ai/deploy/helm \
  --namespace redhat-ods-operator \
  --create-namespace
```

This installs:
- Red Hat OpenShift AI operator (stable-3.x channel)
- DataScienceCluster with default component configuration
- All managed components enabled

---

## Understanding the Helm Chart

The Helm chart is organized into the following structure:

```
helm/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default configuration values
└── templates/
    ├── _helpers.tpl        # Template helper functions
    ├── operator.yaml       # Operator subscription template
    └── dsc.yaml            # DataScienceCluster template
```

### Chart Metadata

The [`Chart.yaml`](./Chart.yaml) defines the chart version and metadata:

```yaml
apiVersion: v2
name: rhoai-platform
description: Red Hat OpenShift AI Platform Deployment
version: 1.0.0
appVersion: "3.x"
```

### Default Values

The [`values.yaml`](./values.yaml) file contains all configurable parameters with sensible defaults.

---

## Configuration Options

### Operator Configuration

Control operator installation and update channel:

```yaml
namespace:
  create: false                   
  name: redhat-ods-operator

subscription:
  create: true
  name: rhods-operator
  channel: stable-3.x              # Options: stable-3.x, fast-3.x, eus-3.x
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic   # Options: Automatic, Manual
```

### DataScienceCluster Components

Each component can be individually enabled or disabled:

```yaml
dataScienceCluster:
  create: true
  name: default-dsc
  components:
    dashboard:
      managementState: Managed     # Options: Managed, Removed
    
    workbenches:
      managementState: Managed
    
    kserve:
      managementState: Managed
      nim:
        managementState: Managed
    
    modelregistry:
      managementState: Managed
      registriesNamespace: rhoai-model-registries
    
    trustyai:
      managementState: Managed
    
    aipipelines:
      managementState: Managed
    
    ray:
      managementState: Managed
    
    trainingoperator:
      managementState: Managed
```

---

## Customizing Your Deployment

### Method 1: Create Custom Values File

Create a custom values file for your environment:

```bash
cp ./fusion-openshift-ai/deploy/helm/values.yaml ./my-rhoai-config.yaml
```

Edit `my-rhoai-config.yaml` to customize components:

```yaml
dataScienceCluster:
  components:
    # Enable only specific components
    dashboard:
      managementState: Managed
    workbenches:
      managementState: Managed
    kserve:
      managementState: Managed
    
    # Disable optional components
    ray:
      managementState: Removed
    trainingoperator:
      managementState: Removed
    feastoperator:
      managementState: Removed
```

Deploy with custom values:
```bash
helm install rhoai-platform ./fusion-openshift-ai/deploy/helm \
  --namespace redhat-ods-operator \
  --create-namespace \
  -f ./my-rhoai-config.yaml
```

### Method 2: Override Values at Runtime

Override specific values directly from the command line:

```bash
helm install rhoai-platform ./fusion-openshift-ai/deploy/helm \
  --namespace redhat-ods-operator \
  --create-namespace \
  --set subscription.channel=fast-3.x \
  --set dataScienceCluster.components.ray.managementState=Removed \
  --set dataScienceCluster.components.trainingoperator.managementState=Removed
```

---

## Managing Deployments

### View Installed Release

```bash
# List all releases
helm list -n redhat-ods-operator

# View current values for a release
helm get values rhoai-platform -n redhat-ods-operator

# View rendered manifests
helm get manifest rhoai-platform -n redhat-ods-operator

# View release history
helm history rhoai-platform -n redhat-ods-operator
```

### Upgrade Deployment

Update your values file and upgrade:

```bash
helm upgrade rhoai-platform ./fusion-openshift-ai/deploy/helm \
  --namespace redhat-ods-operator \
  -f ./my-rhoai-config.yaml
```

Override values during upgrade:
```bash
helm upgrade rhoai-platform ./fusion-openshift-ai/deploy/helm \
  --namespace redhat-ods-operator \
  --set dataScienceCluster.components.ray.managementState=Managed \
  --reuse-values
```

### Rollback to Previous Version

```bash
# View history
helm history rhoai-platform -n redhat-ods-operator

# Rollback to previous revision
helm rollback rhoai-platform -n redhat-ods-operator

# Rollback to specific revision
helm rollback rhoai-platform 1 -n redhat-ods-operator
```

---

## Monitoring Deployment

### Check Installation Status

```bash
# Check Helm release status
helm status rhoai-platform -n redhat-ods-operator

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

```bash
# Get dashboard URL
oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'
```

Or navigate via the OpenShift Console:
1. Go to **Networking → Routes** in the `redhat-ods-applications` namespace
2. Find the `rhods-dashboard` route
3. Click the URL to access the dashboard

---

## Advanced Configuration

### Using Different Operator Channels

Switch to a different update channel:

```yaml
subscription:
  channel: fast-3.x  # Get latest features faster
```

Or use Extended Update Support (EUS):
```yaml
subscription:
  channel: eus-3.x   # Longer support lifecycle
```

### Manual Approval for Updates

Require manual approval for operator updates:

```yaml
subscription:
  installPlanApproval: Manual
```

Then approve updates manually:
```bash
oc get installplan -n redhat-ods-operator
oc patch installplan <install-plan-name> -n redhat-ods-operator \
  --type merge \
  --patch '{"spec":{"approved":true}}'
```

### Custom Component Namespaces

Configure custom namespaces for components:

```yaml
dataScienceCluster:
  components:
    workbenches:
      managementState: Managed
      workbenchNamespace: custom-notebooks
    
    modelregistry:
      managementState: Managed
      registriesNamespace: custom-model-registry
```

---

## Troubleshooting

### Helm Release Fails

Check the Helm release status:
```bash
helm status rhoai-platform -n redhat-ods-operator
helm get notes rhoai-platform -n redhat-ods-operator
```

View rendered templates for debugging:
```bash
helm template rhoai-platform ./fusion-openshift-ai/deploy/helm \
  -f ./my-rhoai-config.yaml \
  --debug
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

### Values Not Applied

Verify your values are being used:
```bash
helm get values rhoai-platform -n redhat-ods-operator
```

Check the rendered manifest:
```bash
helm get manifest rhoai-platform -n redhat-ods-operator
```

---

## Useful Helm Commands

```bash
# Dry-run to see what would be installed
helm install rhoai-platform ./fusion-openshift-ai/deploy/helm \
  --namespace redhat-ods-operator \
  --dry-run --debug

# Validate chart
helm lint ./fusion-openshift-ai/deploy/helm

# Package chart
helm package ./fusion-openshift-ai/deploy/helm

# Show chart information
helm show chart ./fusion-openshift-ai/deploy/helm
helm show values ./fusion-openshift-ai/deploy/helm
helm show readme ./fusion-openshift-ai/deploy/helm
```

---

## Additional Resources

- [Helm Documentation](https://helm.sh/docs/)
- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- [OpenShift AI Architecture](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.15/html/introduction_to_red_hat_openshift_ai/architecture_openshift-ai)
- [Operator Lifecycle Manager Documentation](https://olm.operatorframework.io/)