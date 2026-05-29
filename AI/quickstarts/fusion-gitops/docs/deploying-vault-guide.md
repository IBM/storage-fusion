# HashiCorp Vault Deployment Guide

This guide provides comprehensive instructions for deploying and managing HashiCorp Vault as a secret manager on OpenShift/Kubernetes clusters using the provided automation scripts.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Deployment Guide](#deployment-guide)
- [Validation](#validation)
- [Accessing Vault](#accessing-vault)
- [Cleanup Guide](#cleanup-guide)
- [Important Notes](#important-notes)
- [Troubleshooting](#troubleshooting)
- [Related Documentation](#related-documentation)

## Introduction

The Vault deployment automation consists of two main scripts:

- **`deploy-secret-manager.sh`**: Deploys HashiCorp Vault operator and instance with automated initialization
- **`cleanup-secret-manager.sh`**: Safely removes Vault deployment and associated resources

These scripts provide a streamlined way to deploy Vault for secure secret management in your Kubernetes/OpenShift environment. The deployment includes:

- Vault Secrets Operator installation
- Vault instance with configurable replicas
- Persistent storage configuration
- Automated initialization and unsealing (via Ansible playbook)
- Storage of unseal keys in Kubernetes secrets

## Prerequisites

### Required Tools

| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| **Helm** | 3.x | Package manager for Kubernetes | [Install Helm](https://helm.sh/docs/intro/install/) |
| **oc/kubectl** | Latest | Kubernetes/OpenShift CLI | [Install kubectl](https://kubernetes.io/docs/tasks/tools/) or [Install oc](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html) |
| **ansible-playbook** | 2.9+ | Optional: For automated Vault initialization | `pip install ansible` |

### Cluster Requirements

- **Cluster Access**: Admin or sufficient permissions to:
  - Create namespaces
  - Deploy operators
  - Create StatefulSets, Services, and PVCs
  - Manage RBAC resources

- **Cluster Type**: 
  - OpenShift 4.x or later
  - Kubernetes 1.19 or later

### Storage Requirements

- **Storage Class**: A valid StorageClass must be available in your cluster
  - Default: `ocs-storagecluster-ceph-rbd` (OpenShift Data Foundation)
  - Alternatives: Any block storage class (e.g., `fusion-block-storage`)
  - Minimum: 10Gi per Vault replica (configurable)

To check available storage classes:
```bash
kubectl get storageclass
# or
oc get storageclass
```

## Deployment Guide

### Script Location

```
quickstarts/fusion-gitops/scripts/deploy-secret-manager.sh
```

### Basic Usage

```bash
# Deploy with defaults
./scripts/deploy-secret-manager.sh

# Show help
./scripts/deploy-secret-manager.sh --help
```

### Available Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--namespace` | `-n` | Vault namespace | Current context namespace or `vault` |
| `--storage-class` | `-s` | Storage class name | `ocs-storagecluster-ceph-rbd` |
| `--size` | `-z` | Storage size per replica | `10Gi` |
| `--replicas` | `-r` | Number of Vault replicas | `3` |
| `--values-file` | `-f` | Custom Helm values file | None |
| `--release-name` | | Helm release name | `vault-operator` |
| `--dry-run` | | Preview deployment without applying | `false` |
| `--help` | `-h` | Show help message | - |

### Usage Examples

#### Example 1: Deploy with Defaults
```bash
./scripts/deploy-secret-manager.sh
```
This deploys Vault with:
- Namespace: Current context or `vault`
- Storage: `ocs-storagecluster-ceph-rbd`
- Size: 10Gi
- Replicas: 3

#### Example 2: Custom Storage Class
```bash
./scripts/deploy-secret-manager.sh --storage-class fusion-block-storage
```

#### Example 3: Production Deployment (Multi-Replica)
```bash
./scripts/deploy-secret-manager.sh \
  -n vault-prod \
  -r 5 \
  -z 20Gi \
  --storage-class fusion-block-storage
```
This creates a production-ready deployment with:
- 5 Vault replicas for high availability
- 20Gi storage per replica
- Custom namespace `vault-prod`

**Note:** Multi-replica deployments use a **two-phase approach**:
1. **Phase 1**: Deploy with 1 replica, initialize and unseal vault-0
2. **Phase 2**: Scale to desired replicas (3, 5, etc.) using Helm upgrade, then unseal each replica

#### Example 4: Using Custom Values File
```bash
./scripts/deploy-secret-manager.sh -f my-custom-values.yaml
```

#### Example 5: Dry Run (Preview)
```bash
./scripts/deploy-secret-manager.sh --dry-run
```
Shows what would be deployed without making any changes.

#### Example 6: Multiple Custom Options
```bash
./scripts/deploy-secret-manager.sh \
  -n vault-dev \
  -s fusion-block-storage \
  -z 15Gi \
  -r 3 \
  --release-name my-vault
```

### Deployment Process

When you run the deployment script, the following steps occur:

1. **Environment Detection**
   - Detects whether you're using OpenShift (`oc`) or Kubernetes (`kubectl`)
   - Determines the target namespace

2. **Prerequisites Check**
   - Verifies Helm 3.x is installed
   - Validates the specified storage class exists
   - Checks for the Helm chart location

3. **Namespace Creation**
   - Creates the target namespace if it doesn't exist

4. **Configuration Display**
   - Shows deployment configuration for review
   - Prompts for confirmation (unless `--dry-run`)

5. **Helm Deployment**
   - Installs Vault operator via Helm
   - Deploys Vault instance with specified configuration
   - Creates necessary RBAC resources

6. **Vault Pod Startup**
   - Waits for Vault pods to reach Running state (up to 5 minutes)
   - Waits additional 30 seconds for Vault process initialization

7. **Post-Deployment Initialization**
   - After deployment completes, proceed to the Validation and Post-Deployment Configuration sections

## Validation

After deployment, use the validation script to verify your Vault installation is healthy and operational.

### Script Location

```
quickstarts/fusion-gitops/scripts/validate-secret-manager.sh
```

### Basic Usage

```bash
# Run comprehensive validation
./scripts/validate-secret-manager.sh

# Show help
./scripts/validate-secret-manager.sh --help
```

### Available Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--namespace` | `-n` | Vault namespace to validate | Current context namespace or `vault` |
| `--verbose` | `-v` | Show detailed output and diagnostics | `false` |
| `--help` | `-h` | Show help message | - |

### Usage Examples

#### Example 1: Validate Default Namespace
```bash
./scripts/validate-secret-manager.sh
```
Validates Vault in the current context namespace or `vault`.

#### Example 2: Verbose Output
```bash
./scripts/validate-secret-manager.sh --verbose
```
Shows detailed diagnostics including sample error messages and additional context.

#### Example 3: Validate Specific Namespace
```bash
./scripts/validate-secret-manager.sh --namespace vault-prod
```
Validates Vault deployment in the `vault-prod` namespace.

### Validation Checks

The script performs 9 comprehensive checks:

| Check | Description | What It Validates |
|-------|-------------|-------------------|
| 1. StatefulSet | Verifies Vault StatefulSet exists | Deployment configuration |
| 2. Pod Health | Checks all pods are Running and Ready | Pod status and readiness |
| 3. Services | Validates internal/external services | Network connectivity |
| 4. Initialization | Confirms Vault is initialized | Vault setup completion |
| 5. Seal Status | Verifies Vault is unsealed | Operational readiness |
| 6. Unseal Keys | Ensures keys are stored securely | Secret management |
| 7. Storage | Validates PVCs are bound | Persistent storage |
| 8. Route/Ingress | Checks external access | Accessibility |
| 9. Pod Logs | Scans for errors and issues | Runtime health |

### Common Validation Issues

#### Issue: Vault Sealed
```
[ERROR] ✗ vault-0: SEALED
```

**Solution:** Unseal Vault using the stored keys:
```bash
# Run initialization playbook to unseal
ansible-playbook ansible/playbooks/initialize-vault.yml -e vault_namespace=vault -e vault_init=false

# Or manually unseal
kubectl exec -n vault vault-0 -- vault operator unseal <key1>
kubectl exec -n vault vault-0 -- vault operator unseal <key2>
kubectl exec -n vault vault-0 -- vault operator unseal <key3>
```

#### Issue: RBAC Permission Errors
```
[ERROR] ✗ vault-0: Found RBAC permission errors (403)
```

**Solution:** This indicates the Vault ServiceAccount lacks proper permissions. The Helm chart should configure this automatically, but if you see this error:
```bash
# Verify RBAC configuration
kubectl get role vault -n vault -o yaml
kubectl get rolebinding vault -n vault -o yaml

# Redeploy with updated RBAC (if needed)
helm upgrade vault-operator ./helm/vault-operator --namespace vault --reuse-values
```

#### Issue: Pod Not Ready
```
[WARNING] ⚠ vault-0: Running but not Ready
```

**Solution:** Wait for initialization to complete or check pod logs:
```bash
# Check pod status
kubectl describe pod vault-0 -n vault

# Check logs
kubectl logs vault-0 -n vault --tail=50

# Check readiness probe
kubectl get pod vault-0 -n vault -o jsonpath='{.status.conditions[?(@.type=="Ready")]}'
```

## Accessing Vault

### Retrieve Root Token

```bash
# Get root token from Kubernetes secret
kubectl get secret vault-unseal-keys -n vault -o jsonpath='{.data.root-token}' | base64 -d
# or
oc get secret vault-unseal-keys -n vault -o jsonpath='{.data.root-token}' | base64 -d
```

### Access Vault UI

#### Option 1: Via Route (OpenShift)
```bash
# Get the route URL
oc get route vault -n vault -o jsonpath='{.spec.host}'

# Open in browser
# https://<route-host>
```

#### Option 2: Via Port Forward
```bash
# Forward local port to Vault service
kubectl port-forward -n vault svc/vault 8200:8200
# or
oc port-forward -n vault svc/vault 8200:8200

# Open in browser
# http://localhost:8200
```

## Cleanup Guide

### Script Location

```
quickstarts/fusion-gitops/scripts/cleanup-secret-manager.sh
```

### Basic Usage

```bash
# Full cleanup (removes everything)
./scripts/cleanup-secret-manager.sh

# Show help
./scripts/cleanup-secret-manager.sh --help
```

### Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `-n, --namespace` | Target namespace | `vault` |
| `--release-name` | Helm release name | `vault-operator` |
| `--keep-operator` | Keep Vault operator installed | `false` |
| `--keep-namespace` | Keep namespace (don't delete) | `false` |
| `--force` | Skip confirmation prompts | `false` |
| `-h, --help` | Show help message | - |

### Usage Examples

#### Example 1: Full Cleanup
```bash
./scripts/cleanup-secret-manager.sh
```
Removes everything: Vault instances, operator, namespace, and all data.

#### Example 2: Keep Operator
```bash
./scripts/cleanup-secret-manager.sh --keep-operator
```
Removes Vault instances but keeps the operator for future deployments.

#### Example 3: Cleanup Specific Namespace
```bash
./scripts/cleanup-secret-manager.sh -n vault-prod
```

#### Example 4: Force Cleanup (No Confirmation)
```bash
./scripts/cleanup-secret-manager.sh --force
```

#### Example 5: Keep Namespace
```bash
./scripts/cleanup-secret-manager.sh --keep-namespace
```
Removes Vault resources but preserves the namespace.

#### Example 6: Minimal Cleanup
```bash
./scripts/cleanup-secret-manager.sh --keep-operator --keep-namespace
```
Only removes Vault instances, keeping operator and namespace.

### What Gets Removed

The cleanup script removes the following resources:

#### Always Removed:
- ✓ Helm release
- ✓ Vault StatefulSets
- ✓ Vault Services
- ✓ Vault ConfigMaps
- ✓ Vault ServiceAccounts
- ✓ Vault RBAC resources (Roles, RoleBindings)
- ✓ Vault Routes (OpenShift only)
- ✓ **Vault PVCs and all data**
- ✓ **Vault unseal keys secret**
- ✓ Vault Pods

#### Conditionally Removed:
- ✓ Vault Secrets Operator (unless `--keep-operator`)
- ✓ Operator Subscription and CSV (unless `--keep-operator`)
- ✓ OperatorGroup (unless `--keep-operator`)
- ✓ Namespace (unless `--keep-namespace`)

### Safety Warnings

⚠️ **CRITICAL WARNINGS:**

1. **Data Loss**: Cleanup permanently deletes all Vault data and PVCs
2. **Unseal Keys**: The `vault-unseal-keys` secret is deleted - ensure you have backups!
3. **No Recovery**: This action cannot be undone
4. **Confirmation Required**: The script requires typing "yes" to proceed (unless `--force`)

**Before cleanup:**
- Backup all critical secrets stored in Vault
- Save unseal keys and root token to a secure location
- Document any Vault policies and configurations
- Notify team members of the planned cleanup

## Important Notes

### Backup Recommendations

🔐 **Critical: Backup Unseal Keys and Root Token**

After deployment, immediately backup:

```bash
# Export unseal keys and root token
kubectl get secret vault-unseal-keys -n vault -o yaml > vault-keys-backup.yaml

# Store in a secure location:
# - Password manager
# - Hardware security module (HSM)
# - Encrypted storage
# - Multiple secure locations (recommended)
```

**Why this matters:**
- You need 3 of 5 unseal keys to unseal Vault after any restart
- Without unseal keys, Vault data becomes permanently inaccessible
- Root token provides full administrative access

### Security Considerations

1. **Unseal Keys Storage**
   - Never commit unseal keys to version control
   - Store keys in separate secure locations
   - Limit access to keys to authorized personnel only
   - Consider using Vault auto-unseal with cloud KMS for production

2. **Root Token Usage**
   - Use root token only for initial setup
   - Create separate tokens with limited policies for applications
   - Rotate root token regularly
   - Revoke root token when not needed

3. **Network Security**
   - Use TLS for Vault communication in production
   - Restrict network access to Vault pods
   - Use NetworkPolicies to limit pod-to-pod communication
   - Enable audit logging

4. **High Availability**
   - Use 3 or 5 replicas for production deployments
   - Ensure replicas are distributed across availability zones
   - Configure proper resource requests and limits
   - Monitor Vault health and performance

5. **Backup Strategy**
   - Regular snapshots of Vault data
   - Test restore procedures
   - Document recovery processes
   - Store backups in secure, separate locations

### Production Recommendations

For production deployments:

```bash
./scripts/deploy-secret-manager.sh \
  -n vault-prod \
  -r 5 \
  -z 50Gi \
  --storage-class premium-storage \
  -f production-values.yaml
```

**Production values should include:**
- TLS configuration
- Resource limits and requests
- Anti-affinity rules
- Monitoring and alerting
- Backup configurations
- Auto-unseal configuration (recommended)

## Troubleshooting

### First Step: Run Validation

Before diving into specific issues, run the validation script to get a comprehensive health check:

```bash
./scripts/validate-secret-manager.sh --verbose
```

This will identify most common issues automatically. For specific problems, see below:

### Common Issues

#### Issue: Storage Class Not Found
```
Error: Storage class 'ocs-storagecluster-ceph-rbd' not found
```

**Solution:**
```bash
# List available storage classes
kubectl get storageclass

# Use an available storage class
./scripts/deploy-secret-manager.sh --storage-class <available-class>
```

#### Issue: Vault Pods Not Starting
```
Error: Timeout waiting for Vault pods to start
```

**Solution:**
```bash
# Check pod status
kubectl get pods -n vault

# Check pod logs
kubectl logs -n vault vault-0

# Check events
kubectl get events -n vault --sort-by='.lastTimestamp'
```

#### Issue: Vault Initialization Failed
```
Error: Vault initialization failed
```

**Solution:**
```bash
# Check if Vault is already initialized
kubectl exec -n vault vault-0 -- vault status

# Manually initialize if needed
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR='http://127.0.0.1:8200'
vault operator init -key-shares=5 -key-threshold=3
```

#### Issue: Vault Sealed After Restart
```
Error: Vault is sealed
```

**Solution:**
```bash
# Get unseal keys
kubectl get secret vault-unseal-keys -n vault -o jsonpath='{.data.unseal-key-1}' | base64 -d

# Unseal Vault (repeat with 3 different keys)
kubectl exec -n vault vault-0 -- vault operator unseal <key1>
kubectl exec -n vault vault-0 -- vault operator unseal <key2>
kubectl exec -n vault vault-0 -- vault operator unseal <key3>
```

### Getting Help

If you encounter issues:

1. **Run validation script**: `./scripts/validate-secret-manager.sh --verbose`
2. Check the script output for error messages
3. Review pod logs: `kubectl logs -n vault <pod-name>`
4. Check Vault status: `kubectl exec -n vault vault-0 -- vault status`
5. Review Kubernetes events: `kubectl get events -n vault`

## Related Documentation

### External Resources
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault on Kubernetes](https://www.vaultproject.io/docs/platform/k8s)
- [Vault Secrets Operator](https://github.com/hashicorp/vault-secrets-operator)
- [Helm Documentation](https://helm.sh/docs/)
- [OpenShift Documentation](https://docs.openshift.com/)
