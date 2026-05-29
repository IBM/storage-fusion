# Red Hat GitOps Deployment Guide

This comprehensive guide covers deploying and managing Red Hat GitOps (ArgoCD) on Fusion HCI using automated deployment and cleanup scripts.

## Overview

The deployment and cleanup scripts provide a streamlined approach to managing Red Hat GitOps on your Fusion HCI cluster:

- **`deploy-gitops.sh`** - Automated deployment using Helm with configurable profiles
- **`cleanup-gitops.sh`** - Safe, ordered cleanup with verification

### Key Benefits

- **Simplified Deployment** - One-command deployment with sensible defaults
- **Flexible Configuration** - Three pre-configured profiles (minimal, default, production)
- **GitOps-Ready** - Immediate access to ArgoCD for application deployment
- **Safe Cleanup** - Proper resource removal order with verification
- **Production-Ready** - HA configurations with persistent storage

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Guide](#deployment-guide)
- [Configuration Profiles](#configuration-profiles)
- [Validation](#validation)
- [Post-Deployment](#post-deployment)
- [Cleanup Guide](#cleanup-guide)
- [Troubleshooting](#troubleshooting)
- [Related Documentation](#related-documentation)

## Prerequisites

### Required Tools

Before deploying Red Hat GitOps, ensure you have the following tools installed:

| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| **Helm** | 3.x | Package manager for Kubernetes | [Install Helm](https://helm.sh/docs/intro/install/) |
| **oc/kubectl** | Latest | Kubernetes/OpenShift CLI | [Install kubectl](https://kubernetes.io/docs/tasks/tools/) or [Install oc](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html) |

### Cluster Access Requirements

- **Valid kubeconfig** - Configured cluster access
  ```bash
  # Verify cluster connectivity
  oc cluster-info  # or kubectl cluster-info
  ```

- **Permissions Required**:
  - Create and manage namespaces
  - Deploy operators and subscriptions
  - Create PersistentVolumeClaims
  - Manage pods, services, and routes
  - Create ArgoCD custom resources

### Storage Requirements

The deployment requires a storage class that supports:

- **ReadWriteMany (RWX)** access mode for repository cache (when using multiple replicas)
- **Default**: `ocs-storagecluster-cephfs` (OpenShift Data Foundation)

Verify available storage classes:

```bash
oc get storageclass
# or
kubectl get storageclass
```

> **Note**: For minimal deployments without persistent storage, use the `values-minimal.yaml` profile.

### Resource Requirements

Ensure your cluster has sufficient resources based on your chosen profile:

| Profile | CPU | Memory | Storage | Use Case |
|---------|-----|--------|---------|----------|
| **Minimal** | ~1.1 CPU | ~1.2Gi RAM | Ephemeral | Development, testing |
| **Default** | ~3.5 CPU | ~5.5Gi RAM | 10Gi | Standard production |
| **Production** | ~8 CPU | ~12Gi RAM | 50Gi | Mission-critical |

## Deployment Guide

### Script Location

```
quickstarts/fusion-gitops/scripts/deploy-gitops.sh
```

### Command-Line Options

The `deploy-gitops.sh` script supports the following options:

| Option | Description | Default |
|--------|-------------|---------|
| `-h, --help` | Show help message | - |
| `-n, --namespace NAME` | Kubernetes namespace for Helm release | `default` |
| `-r, --release NAME` | Helm release name | `fusion-gitops` |
| `-f, --values FILE` | Helm values file (minimal/production) | None (uses default) |
| `-d, --dry-run` | Perform dry-run without making changes | `false` |
| `--skip-preflight` | Skip pre-flight checks | `false` |
| `--skip-validation` | Skip post-deployment validation | `false` |
| `-v, --verbose` | Enable verbose output | `false` |
| `--force` | Skip confirmation prompts | `false` |
| `--timeout DURATION` | Helm timeout duration | `15m` |

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `KUBECONFIG` | Path to kubeconfig file | `~/.kube/config` |
| `DEBUG` | Enable debug output | `true` or `false` |

### Deployment Examples

#### 1. Minimal Deployment (Getting Started)

Perfect for development, testing, or learning GitOps:

```bash
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-minimal.yaml
```

**What you get**:
- 1 replica of each component
- No high availability
- Ephemeral storage (no PVCs)
- ~1.1 CPU, ~1.2Gi RAM
- Quick startup time

#### 2. Default Deployment (Standard Production)

Recommended for most production workloads:

```bash
./scripts/deploy-gitops.sh
```

**What you get**:
- 2 replicas with basic HA
- 10Gi persistent storage
- Autoscaling enabled
- ~3.5 CPU, ~5.5Gi RAM
- Production-ready configuration

#### 3. Production Deployment (Mission-Critical)

For high-availability, mission-critical deployments:

```bash
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-production.yaml
```

**What you get**:
- 3 replicas with full HA
- 50Gi persistent storage
- Controller sharding enabled
- ~8 CPU, ~12Gi RAM
- Enhanced monitoring and security

#### 4. Dry-Run Deployment

Preview what will be deployed without making changes:

```bash
./scripts/deploy-gitops.sh --dry-run
```

#### 5. Deploy to Specific Namespace

Deploy to a custom namespace:

```bash
./scripts/deploy-gitops.sh -n openshift-gitops
```

#### 6. Verbose Deployment with Custom Release Name

Get detailed output during deployment:

```bash
./scripts/deploy-gitops.sh -v -r my-gitops -n my-namespace
```

#### 7. Automated Deployment (CI/CD)

Skip confirmation prompts for automation:

```bash
./scripts/deploy-gitops.sh --force -f helm/fusion-gitops/values-production.yaml
```

### Deployment Process

The script follows this process:

1. **Pre-flight Checks**
   - Verifies Helm installation
   - Checks cluster connectivity
   - Validates Helm chart
   - Confirms storage class availability

2. **Configuration Display**
   - Shows deployment parameters
   - Displays resource requirements
   - Requests confirmation (unless `--force`)

3. **Helm Deployment**
   - Installs or upgrades the release
   - Deploys GitOps operator
   - Creates ArgoCD instance
   - Configures storage (if applicable)

4. **Information Display**
   - Provides ArgoCD credentials
   - Shows access URL
   - Lists next steps

## Configuration Profiles

### Minimal Profile (`values-minimal.yaml`)

**Best for**: Development, testing, learning, resource-constrained environments

**Configuration**:
- **Replicas**: 1 (all components)
- **High Availability**: Disabled
- **Storage**: Ephemeral (no PVCs)
- **Autoscaling**: Disabled
- **Notifications**: Disabled
- **Network Policies**: Disabled
- **Resource Quotas**: Disabled

**Resource Requirements**:
- CPU: ~1.1 cores
- Memory: ~1.2Gi
- Storage: None (ephemeral)

**Use Cases**:
- Getting started with GitOps
- Development environments
- Testing and evaluation
- Learning ArgoCD features
- Resource-limited clusters

**Deployment**:
```bash
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-minimal.yaml
```

### Default Profile (No values file)

**Best for**: Standard production workloads, general-purpose deployments

**Configuration**:
- **Replicas**: 2 (server, repo)
- **High Availability**: Basic (Redis HA enabled)
- **Storage**: 10Gi persistent (RWX)
- **Autoscaling**: Enabled (2-4 replicas)
- **Notifications**: Enabled
- **Network Policies**: Enabled
- **Resource Quotas**: Enabled

**Resource Requirements**:
- CPU: ~3.5 cores
- Memory: ~5.5Gi
- Storage: 10Gi

**Use Cases**:
- Standard production deployments
- Multi-team environments
- Moderate application workloads
- Balanced performance and cost

**Deployment**:
```bash
./scripts/deploy-gitops.sh
```

### Production Profile (`values-production.yaml`)

**Best for**: Mission-critical deployments, high-scale environments

**Configuration**:
- **Replicas**: 3 (server, repo), 2 (controller with sharding)
- **High Availability**: Full (all components)
- **Storage**: 50Gi persistent (RWX)
- **Autoscaling**: Enabled (3-5 replicas)
- **Controller Sharding**: Enabled
- **Notifications**: Enabled with HA
- **Network Policies**: Enabled
- **Resource Quotas**: Enhanced limits

**Resource Requirements**:
- CPU: ~8 cores
- Memory: ~12Gi
- Storage: 50Gi

**Use Cases**:
- Mission-critical applications
- Large-scale deployments
- High-availability requirements
- Enterprise production environments
- Compliance-sensitive workloads

**Deployment**:
```bash
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-production.yaml
```

### Custom Configuration

You can create your own values file by copying and modifying an existing profile:

```bash
# Copy a profile as a starting point
cp helm/fusion-gitops/values-production.yaml helm/fusion-gitops/values-custom.yaml

# Edit the file
vim helm/fusion-gitops/values-custom.yaml

# Deploy with custom values
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-custom.yaml
```

## Validation

After deployment, it's important to validate that all components are running correctly. The deployment includes an automated validation script that performs comprehensive checks.

### Automated Validation Script

The [`validate-gitops.sh`](../scripts/validate-gitops.sh) script provides automated validation of your GitOps deployment.

#### Script Location

```
quickstarts/fusion-gitops/scripts/validate-gitops.sh
```

#### What It Checks

The validation script performs the following checks:

1. **Operator Status**
   - Verifies GitOps operator subscription is active
   - Checks operator CSV (ClusterServiceVersion) is installed
   - Validates operator pods are running

2. **ArgoCD Instance**
   - Confirms ArgoCD custom resource exists
   - Checks ArgoCD instance phase is "Available"
   - Validates all ArgoCD components are deployed

3. **Pod Health**
   - Verifies all pods are in Running state
   - Checks pod readiness status
   - Validates no pods are in error states

4. **Storage Provisioning** (if applicable)
   - Confirms PVCs are bound
   - Validates storage class availability
   - Checks storage capacity

5. **Network Connectivity**
   - Verifies routes/ingress are configured (OpenShift)
   - Checks service endpoints are available
   - Validates ArgoCD server accessibility

#### Running the Validation Script

Basic usage:

```bash
./scripts/validate-gitops.sh
```

With custom configuration:

```bash
./scripts/validate-gitops.sh \
  --namespace openshift-gitops \
  --argocd-name openshift-gitops
```

#### Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--namespace NS` | Namespace to validate | `openshift-gitops` |
| `--argocd-name NAME` | ArgoCD instance name | `openshift-gitops` |
| `--operator-namespace NS` | Operator namespace | `openshift-gitops-operator` |
| `-v, --verbose` | Enable verbose output | `false` |
| `-h, --help` | Show help message | - |


## Post-Deployment

### Accessing ArgoCD UI

#### On OpenShift

The script automatically creates a route. Access the UI using:

```bash
# Get the ArgoCD URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Open in browser
https://<route-host>
```

#### On Kubernetes

Use port-forwarding to access the UI:

```bash
kubectl port-forward svc/openshift-gitops-server -n openshift-gitops 8080:443

# Open in browser
https://localhost:8080
```

### Retrieving Credentials

The deployment script displays credentials automatically. To retrieve them later:

```bash
# Get admin password
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d

# Username is always: admin
```

## Cleanup Guide

### Script Location

```
quickstarts/fusion-gitops/scripts/cleanup-gitops.sh
```

The `cleanup-gitops.sh` script provides safe, ordered cleanup of Red Hat GitOps resources.

### Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--release-name NAME` | Helm release name | `fusion-gitops` |
| `--namespace NAMESPACE` | Helm release namespace | `fusion-gitops` |
| `--argocd-name NAME` | ArgoCD instance name | `openshift-gitops` |
| `--argocd-namespace NS` | ArgoCD namespace | `openshift-gitops` |
| `--operator-namespace NS` | Operator namespace | `openshift-gitops-operator` |
| `--keep-operator` | Keep operator installed (remove instances only) | `false` |
| `--keep-namespace` | Don't delete namespaces | `false` |
| `--force` | Skip confirmation prompts | `false` |
| `--dry-run` | Show what would be done without doing it | `false` |
| `-h, --help` | Show help message | - |

### Cleanup Process

The script follows a specific order to ensure safe cleanup:

#### Step 1: Remove Helm Release

Removes the Helm release and associated resources:

```text
# What gets removed:
- Helm release metadata
- Chart-managed resources
- ConfigMaps and Secrets created by Helm
```

#### Step 2: Clean Up GitOps Service CR and ArgoCD Instance

Removes the ArgoCD instance and GitOps Service custom resources:

```text
# What gets removed:
- GitOpsService CR (if exists)
- ArgoCD instance (openshift-gitops)
- HorizontalPodAutoscalers (HPAs)
- Associated pods and services
```

The script handles stuck resources by:
- Removing finalizers
- Force deleting if necessary
- Waiting for deletion confirmation

#### Step 3: Clean Up Operator Subscription and CSV

Removes the operator (unless `--keep-operator` is specified):

```text
# What gets removed:
- Operator subscription
- ClusterServiceVersion (CSV)
- Operator deployment
```

#### Step 4: Remove Namespaces

Deletes namespaces (unless `--keep-namespace` is specified):

```text
# What gets removed:
- Release namespace (if different from ArgoCD namespace)
- ArgoCD namespace (openshift-gitops)
- Operator namespace (openshift-gitops-operator)
```

### Cleanup Examples

#### 1. Basic Cleanup (Complete Removal)

Remove everything including operator and namespaces:

```bash
./scripts/cleanup-gitops.sh
```

This removes:
- ✓ Helm release
- ✓ ArgoCD instance
- ✓ GitOps operator
- ✓ All namespaces

#### 2. Keep Operator, Remove Instances Only

Useful when you want to redeploy with different settings:

```bash
./scripts/cleanup-gitops.sh --keep-operator
```

This removes:
- ✓ Helm release
- ✓ ArgoCD instance
- ✗ GitOps operator (kept)
- ✓ Namespaces

#### 3. Keep Namespaces

Preserve namespaces for troubleshooting or manual cleanup:

```bash
./scripts/cleanup-gitops.sh --keep-namespace
```

This removes:
- ✓ Helm release
- ✓ ArgoCD instance
- ✓ GitOps operator
- ✗ Namespaces (kept)

#### 4. Dry Run

Preview what would be removed without making changes:

```bash
./scripts/cleanup-gitops.sh --dry-run
```

#### 5. Custom Configuration

Clean up with custom names:

```bash
./scripts/cleanup-gitops.sh \
  --namespace openshift-gitops \
  --argocd-name my-argocd \
  --release-name my-gitops
```

#### 6. Automated Cleanup

Skip confirmation prompts:

```bash
./scripts/cleanup-gitops.sh --force
```

### What Gets Removed

The cleanup script removes the following resources:

#### Always Removed
- ✓ Helm release and metadata
- ✓ GitOpsService custom resource
- ✓ ArgoCD instance
- ✓ HorizontalPodAutoscalers (HPAs)
- ✓ Pods and services created by ArgoCD

#### Conditionally Removed
- ⚠️ Operator subscription and CSV (unless `--keep-operator`)
- ⚠️ Namespaces (unless `--keep-namespace`)

#### Never Removed (Manual cleanup required)
- ✗ PersistentVolumeClaims (PVCs) - Retained for data safety
- ✗ Custom applications deployed via ArgoCD
- ✗ Git repositories configured in ArgoCD
- ✗ Secrets created outside of Helm

### Manual PVC Cleanup

If you want to remove PVCs after cleanup:

```bash
# List PVCs
oc get pvc -n openshift-gitops

# Delete specific PVC
oc delete pvc <pvc-name> -n openshift-gitops

# Delete all PVCs in namespace
oc delete pvc --all -n openshift-gitops
```

> **Warning**: Deleting PVCs will permanently delete all data. Ensure you have backups if needed.

## Troubleshooting

### Common Issues and Solutions

#### Issue: Helm Chart Validation Failed

**Symptoms**:
```
[ERROR] Helm chart validation had warnings
```

**Solution**:
```bash
# Validate chart manually
helm lint helm/fusion-gitops

# Check for syntax errors in values files
helm template fusion-gitops helm/fusion-gitops -f <values-file>
```

#### Issue: Storage Class Not Found

**Symptoms**:
```
[ERROR] Storage class 'ocs-storagecluster-cephfs' not found
```

**Solution**:
```bash
# List available storage classes
oc get storageclass

# Deploy with a different storage class
./scripts/deploy-gitops.sh \
  --set storage.defaultStorageClass=<your-storage-class>

# Or use minimal profile (no persistent storage)
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-minimal.yaml
```

#### Issue: Insufficient Resources

**Symptoms**:
```
Pods stuck in Pending state
Events show "Insufficient cpu" or "Insufficient memory"
```

**Solution**:
```bash
# Check node resources
oc describe nodes | grep -A 5 "Allocated resources"

# Use minimal profile
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-minimal.yaml

# Or scale down resources in custom values file
```

#### Issue: ArgoCD Pods Not Starting

**Symptoms**:
```
Pods in CrashLoopBackOff or Error state
```

**Solution**:
```bash
# Check pod logs
oc logs -n openshift-gitops <pod-name>

# Check events
oc get events -n openshift-gitops --sort-by='.lastTimestamp'

# Restart pods
oc delete pod -n openshift-gitops -l app.kubernetes.io/part-of=argocd

# Check operator logs
oc logs -n openshift-gitops-operator \
  deployment/gitops-operator-controller-manager
```

#### Issue: Cannot Access ArgoCD UI

**Symptoms**:
```
Route not accessible or 404 error
```

**Solution**:
```bash
# Check route status
oc get route openshift-gitops-server -n openshift-gitops

# Check service
oc get svc openshift-gitops-server -n openshift-gitops

# Check server pod
oc get pods -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-server

# Use port-forward as alternative
oc port-forward svc/openshift-gitops-server -n openshift-gitops 8080:443
```

#### Issue: Cleanup Script Stuck

**Symptoms**:
```
Script hangs during resource deletion
Timeout waiting for resource deletion
```

**Solution**:
```bash
# Force delete stuck resources
oc delete argocd openshift-gitops -n openshift-gitops --force --grace-period=0

# Remove finalizers
oc patch argocd openshift-gitops -n openshift-gitops \
  -p '{"metadata":{"finalizers":[]}}' --type=merge

# Delete namespace forcefully
oc delete namespace openshift-gitops --force --grace-period=0
```

#### Issue: PVCs Not Binding

**Symptoms**:
```
PVCs stuck in Pending state
```

**Solution**:
```bash
# Check PVC status
oc describe pvc -n openshift-gitops

# Verify storage class exists and is default
oc get storageclass

# Check storage provisioner logs
oc logs -n openshift-storage <provisioner-pod>

# Use different storage class
./scripts/deploy-gitops.sh \
  --set storage.defaultStorageClass=<working-storage-class>
```

### Debug Mode

Enable debug output for detailed troubleshooting:

```bash
# Set DEBUG environment variable
export DEBUG=true
./scripts/deploy-gitops.sh -v

# Or use verbose flag
./scripts/deploy-gitops.sh -v
```

### Getting Help

If you encounter issues not covered here:

1. **Check Logs**:
   ```bash
   # Operator logs
   oc logs -n openshift-gitops-operator deployment/gitops-operator-controller-manager
   
   # ArgoCD server logs
   oc logs -n openshift-gitops deployment/openshift-gitops-server
   
   # Application controller logs
   oc logs -n openshift-gitops statefulset/openshift-gitops-application-controller
   ```

2. **Check Resource Status**:
   ```bash
   # All resources
   oc get all -n openshift-gitops
   
   # Custom resources
   oc get argocd,gitopsservice --all-namespaces
   
   # Events
   oc get events -n openshift-gitops --sort-by='.lastTimestamp'
   ```

3. **Helm Status**:
   ```bash
   # Check release status
   helm list -n <namespace>
   
   # Check release history
   helm history <release-name> -n <namespace>
   
   # Get release values
   helm get values <release-name> -n <namespace>
   ```

## Related Documentation

- **Red Hat GitOps Documentation**: [https://docs.openshift.com/gitops/](https://docs.openshift.com/gitops/)
- **ArgoCD Documentation**: [https://argo-cd.readthedocs.io/](https://argo-cd.readthedocs.io/)
- **Helm Documentation**: [https://helm.sh/docs/](https://helm.sh/docs/)
