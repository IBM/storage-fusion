# External Secrets Operator Deployment Guide

This guide provides comprehensive instructions for deploying and managing External Secrets Operator on OpenShift/Kubernetes clusters using the provided automation scripts.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Deployment Guide](#deployment-guide)
- [Validation](#validation)
- [Cleanup Guide](#cleanup-guide)
- [Troubleshooting](#troubleshooting)
- [Related Documentation](#related-documentation)

## Introduction

The External Secrets Operator deployment automation consists of two main scripts:

- **`deploy-external-secrets.sh`**: Deploys External Secrets Operator with support for multiple secret backends
- **`cleanup-external-secrets.sh`**: Safely removes External Secrets Operator and associated resources

These scripts provide a streamlined way to deploy External Secrets Operator for synchronizing secrets from external secret management systems into Kubernetes secrets. The deployment includes:

- Red Hat certified External Secrets Operator installation
- Multiple backend support: HashiCorp Vault, AWS Secrets Manager, IBM Cloud Secrets Manager
- Two-phase deployment process for reliable CRD initialization
- Automatic validation and health checks
- Configurable SecretStore resources

### What is External Secrets Operator?

External Secrets Operator synchronizes secrets from external secret management systems into Kubernetes secrets. This enables:

- **Centralized Secret Management**: Store secrets in enterprise-grade secret management systems
- **GitOps-Friendly**: Manage secret references in Git without exposing values
- **Audit and Compliance**: Leverage backend audit logs and access controls
- **Multi-Cloud Support**: Use AWS, IBM Cloud, or on-premises Vault solutions

## Prerequisites

### Required Tools

| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| **Helm** | 3.x | Package manager for Kubernetes | [Install Helm](https://helm.sh/docs/intro/install/) |
| **oc/kubectl** | Latest | Kubernetes/OpenShift CLI | [Install kubectl](https://kubernetes.io/docs/tasks/tools/) or [Install oc](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html) |

### Cluster Requirements

- **Cluster Access**: Admin or sufficient permissions to:
  - Create namespaces
  - Deploy operators via OLM (Operator Lifecycle Manager)
  - Create custom resources (SecretStores, ClusterSecretStores)
  - Manage RBAC resources

- **Cluster Type**: 
  - OpenShift 4.12 or later
  - Kubernetes 1.24 or later

### Backend Requirements (Optional)

External Secrets Operator can be deployed in **standalone mode** (operator only) or with a configured backend.

## Deployment Guide

### Script Location

```
quickstarts/fusion-gitops/scripts/deploy-external-secrets.sh
```

### Basic Usage

```bash
# Show help
./scripts/deploy-external-secrets.sh --help

# Deploy standalone (operator only)
./scripts/deploy-external-secrets.sh --standalone

# Deploy with Vault backend
./scripts/deploy-external-secrets.sh --backend vault

# Deploy with AWS Secrets Manager
./scripts/deploy-external-secrets.sh --backend aws

# Deploy with IBM Cloud Secrets Manager
./scripts/deploy-external-secrets.sh --backend ibmcloud
```

### Available Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--namespace` | `-n` | Operator namespace | `external-secrets-operator` |
| `--backend` | `-b` | Secret backend: standalone, vault, aws, ibmcloud | Required |
| `--values-file` | `-f` | Custom values file | Auto-selected based on backend |
| `--release-name` | | Helm release name | `external-secrets-operator` |
| `--standalone` | | Deploy operator only (no backend) | `false` |
| `--dry-run` | | Preview deployment without applying | `false` |
| `--help` | `-h` | Show help message | - |

### Supported Backends

| Backend | Description | Use Case |
|---------|-------------|----------|
| **standalone** | Operator only, no external vault | Testing, development, learning |
| **vault** | HashiCorp Vault integration | On-premises enterprise secret management |
| **aws** | AWS Secrets Manager integration | AWS cloud-native deployments |
| **ibmcloud** | IBM Cloud Secrets Manager integration | IBM Cloud deployments |

### Deployment Examples

#### Example 1: Standalone Deployment (Testing)

Perfect for testing the operator before configuring a backend:

```bash
./scripts/deploy-external-secrets.sh --standalone
```

**What you get**:
- External Secrets Operator installed
- No external vault integration
- Ready to add backend later
- Ideal for learning and testing

**Next steps after standalone**:
1. Verify operator installation
2. Test operator functionality
3. When ready, redeploy with a backend:
   ```bash
   ./scripts/deploy-external-secrets.sh --backend vault
   ```

#### Example 2: Deploy with HashiCorp Vault

Deploy with Vault backend integration:

```bash
./scripts/deploy-external-secrets.sh --backend vault
```

**Prerequisites**:
- Vault instance running and accessible
- Kubernetes authentication configured in Vault
- Vault policies created for secret access

**What gets deployed**:
- External Secrets Operator
- ClusterSecretStore configured for Vault
- Kubernetes service account for Vault authentication

#### Example 3: Deploy with AWS Secrets Manager

Deploy with AWS Secrets Manager backend:

```bash
./scripts/deploy-external-secrets.sh --backend aws
```

**Prerequisites**:
- AWS account with Secrets Manager enabled
- AWS credentials (Access Key ID and Secret Access Key) or IRSA configured
- Appropriate IAM permissions for secret access

**What gets deployed**:
- External Secrets Operator
- ClusterSecretStore configured for AWS Secrets Manager
- Network policies for AWS API access

**Required credentials**:
```bash
# Create AWS credentials secret
oc create secret generic aws-credentials \
  -n external-secrets-operator \
  --from-literal=access-key-id=YOUR_ACCESS_KEY_ID \
  --from-literal=secret-access-key=YOUR_SECRET_ACCESS_KEY
```

#### Example 4: Deploy with IBM Cloud Secrets Manager

Deploy with IBM Cloud Secrets Manager backend:

```bash
./scripts/deploy-external-secrets.sh --backend ibmcloud
```

**Prerequisites**:
- IBM Cloud account with Secrets Manager instance
- IBM Cloud API key with access to Secrets Manager
- Secrets Manager instance URL

**What gets deployed**:
- External Secrets Operator
- ClusterSecretStore configured for IBM Cloud Secrets Manager
- Network policies for IBM Cloud API access

**Required credentials**:
```bash
# Create IBM Cloud credentials secret
oc create secret generic ibm-cloud-credentials \
  -n external-secrets-operator \
  --from-literal=api-key=YOUR_IBM_CLOUD_API_KEY
```

#### Example 5: Custom Namespace

Deploy to a specific namespace:

```bash
./scripts/deploy-external-secrets.sh \
  --backend vault \
  --namespace my-secrets-namespace
```

#### Example 6: Custom Values File

Deploy with custom configuration:

```bash
./scripts/deploy-external-secrets.sh \
  --backend vault \
  --values-file my-custom-values.yaml
```

#### Example 7: Dry Run (Preview)

Preview what would be deployed without making changes:

```bash
./scripts/deploy-external-secrets.sh --backend vault --dry-run
```

### Two-Phase Deployment Process

The deployment script uses a two-phase approach to ensure reliable CRD initialization:

#### Phase 1: Operator Deployment

**What happens**:
1. Deploys External Secrets Operator via OLM
2. Creates operator subscription and namespace
3. Waits for CSV (ClusterServiceVersion) to reach "Succeeded" phase
4. Waits for operator pods to be ready
5. Waits for CRDs to be established
6. Verifies API server has registered the resource types
7. Performs final validation before Phase 2

**Why this matters**: CRDs must be fully registered in the API server before SecretStore resources can be created. The script includes multiple validation steps and a 45-second wait to ensure the API server cache is fully refreshed.

#### Phase 2: SecretStore Deployment

**What happens**:
1. Deploys ClusterSecretStore resources (if backend is configured)
2. Configures backend-specific authentication
3. Validates SecretStore creation
4. Includes retry mechanism (up to 3 attempts)

**Why this matters**: SecretStores define how to connect to external secret backends. They must be created after the operator is fully ready to avoid API errors.

### Deployment Process Flow

When you run the deployment script, the following steps occur:

1. **Environment Detection**
   - Detects whether you're using OpenShift (`oc`) or Kubernetes (`kubectl`)
   - Validates Helm installation
   - Checks for required tools

2. **Configuration Validation**
   - Validates backend selection
   - Checks for values file
   - Verifies namespace doesn't conflict

3. **Namespace Creation**
   - Creates target namespace if it doesn't exist
   - Sets up proper labels and annotations

4. **Backend-Specific Instructions**
   - Displays backend-specific requirements
   - Shows credential setup commands (if needed)
   - Provides configuration guidance

5. **Confirmation Prompt**
   - Shows deployment configuration
   - Requests user confirmation (unless `--dry-run`)

6. **Phase 1: Operator Deployment**
   - Deploys operator via Helm (SecretStores disabled)
   - Waits for CSV to reach "Succeeded" phase (up to 3 minutes)
   - Waits for operator pods to be ready (up to 2 minutes)
   - Waits for CRDs to be established (up to 1 minute)
   - Verifies API server registration (up to 1.5 minutes)
   - Performs final validation (up to 30 seconds)
   - Waits 45 seconds for API server cache refresh

7. **Phase 2: SecretStore Deployment**
   - Deploys SecretStore resources (if backend configured)
   - Retries up to 3 times if needed
   - Validates successful creation

8. **Post-Deployment Information**
   - Displays verification commands
   - Shows next steps
   - Provides documentation links

## Validation

After deployment, validate the External Secrets Operator installation using the provided validation script.

### Automated Validation

The deployment includes an automated validation script that checks all critical components:

```bash
# Run validation script
./scripts/validate-external-secrets.sh

# Validate specific namespace
./scripts/validate-external-secrets.sh --namespace external-secrets-operator
```

The validation script checks:
- ✓ Operator CSV status (must be "Succeeded")
- ✓ Operator pod health (must be "Running")
- ✓ CRD installation and readiness
- ✓ ClusterSecretStore status (if backend configured)
- ✓ API server registration

### Manual Verification

#### Verify Operator Installation

```bash
# Check CSV (ClusterServiceVersion) status
oc get csv -n external-secrets-operator
# or
kubectl get csv -n external-secrets-operator

# Expected output:
# NAME                                    DISPLAY                              VERSION   REPLACES   PHASE
# external-secrets-operator.v1.1.0        External Secrets Operator            1.1.0                Succeeded
```

#### Verify Operator Pods

```bash
# Check operator pods
oc get pods -n external-secrets-operator -l app=external-secrets-operator
# or
kubectl get pods -n external-secrets-operator -l app=external-secrets-operator

# Expected output:
# NAME                                                READY   STATUS    RESTARTS   AGE
# external-secrets-operator-xxxxx-xxxxx               1/1     Running   0          5m
```

#### Verify CRDs

```bash
# Check if CRDs are installed
oc get crd | grep external-secrets

# Expected output:
# clustersecretstores.external-secrets.io
# externalsecrets.external-secrets.io
# secretstores.external-secrets.io
# clusterexternalsecrets.external-secrets.io
# pushsecrets.external-secrets.io
```

#### Verify ClusterSecretStore (If Backend Configured)

```bash
# Check ClusterSecretStore
oc get clustersecretstore

# Expected output (for Vault backend):
# NAME                    AGE   STATUS   CAPABILITIES   READY
# vault-backend           5m    Valid    ReadWrite      True

# Get detailed status
oc describe clustersecretstore vault-backend
```

#### Verify Operator Logs

```bash
# Check operator logs for errors
oc logs -n external-secrets-operator -l app=external-secrets-operator
# or
kubectl logs -n external-secrets-operator -l app=external-secrets-operator

# Look for:
# - "controller started" messages
# - No error messages
# - Successful reconciliation logs
```

## Cleanup Guide

### Script Location

```
quickstarts/fusion-gitops/scripts/cleanup-external-secrets.sh
```

### Basic Usage

```bash
# Full cleanup (removes everything)
./scripts/cleanup-external-secrets.sh

# Show help
./scripts/cleanup-external-secrets.sh --help
```

### Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `-n, --namespace` | Operator namespace | `external-secrets-operator` |
| `--release-name` | Helm release name | `external-secrets-operator` |
| `--keep-namespace` | Keep namespace after cleanup | `false` |
| `--force` | Skip confirmation prompts | `false` |
| `-h, --help` | Show help message | - |

### Cleanup Examples

#### Example 1: Full Cleanup

Remove everything including namespace:

```bash
./scripts/cleanup-external-secrets.sh
```

**What gets removed**:
- ✓ ExternalSecrets in namespace
- ✓ ClusterSecretStores (all)
- ✓ SecretStores in namespace
- ✓ Helm release
- ✓ Operator subscription and CSV
- ✓ OperatorGroup
- ✓ Namespace

#### Example 2: Cleanup Specific Namespace

Clean up a custom namespace:

```bash
./scripts/cleanup-external-secrets.sh --namespace my-secrets-namespace
```

#### Example 3: Keep Namespace

Remove resources but preserve the namespace:

```bash
./scripts/cleanup-external-secrets.sh --keep-namespace
```

**What gets removed**:
- ✓ ExternalSecrets in namespace
- ✓ ClusterSecretStores (all)
- ✓ SecretStores in namespace
- ✓ Helm release
- ✓ Operator subscription and CSV
- ✓ OperatorGroup
- ✗ Namespace (kept)

#### Example 4: Force Cleanup (No Confirmation)

Skip confirmation prompts for automation:

```bash
./scripts/cleanup-external-secrets.sh --force
```

#### Example 5: Cleanup Specific Release

Clean up a custom release:

```bash
./scripts/cleanup-external-secrets.sh \
  --release-name my-eso \
  --namespace my-namespace
```

### What Gets Removed

The cleanup script removes resources in the following order:

#### Step 1: Remove ExternalSecrets
- All ExternalSecret resources in the namespace
- Prevents orphaned secret sync operations

#### Step 2: Remove ClusterSecretStores
- All ClusterSecretStore resources (cluster-wide)
- Removes backend connection configurations

#### Step 3: Remove SecretStores
- All SecretStore resources in the namespace
- Removes namespace-scoped backend connections

#### Step 4: Uninstall Helm Release
- Helm release metadata
- Chart-managed resources

#### Step 5: Remove Operator Subscription
- Operator subscription
- Stops operator updates

#### Step 6: Remove CSV
- ClusterServiceVersion
- Removes operator deployment

#### Step 7: Remove OperatorGroup
- OperatorGroup resources
- Cleans up OLM configuration

#### Step 8: Wait for Pod Termination
- Waits up to 60 seconds for pods to terminate
- Ensures clean shutdown

#### Step 9: Remove Namespace (Optional)
- Deletes namespace if `--keep-namespace` not specified
- Removes all remaining resources

### CRD Cleanup Considerations

⚠️ **Important**: The cleanup script does NOT remove CRDs by default to prevent data loss.

**CRDs that remain**:
- `externalsecrets.external-secrets.io`
- `secretstores.external-secrets.io`
- `clustersecretstores.external-secrets.io`
- `clusterexternalsecrets.external-secrets.io`
- `pushsecrets.external-secrets.io`

**To manually remove CRDs** (only if no other instances exist):
```bash
oc delete crd externalsecrets.external-secrets.io
oc delete crd secretstores.external-secrets.io
oc delete crd clustersecretstores.external-secrets.io
oc delete crd clusterexternalsecrets.external-secrets.io
oc delete crd pushsecrets.external-secrets.io
```

> **Warning**: Removing CRDs will delete ALL ExternalSecret and SecretStore resources cluster-wide, even in other namespaces!

### Safety Warnings

⚠️ **CRITICAL WARNINGS:**

1. **Data Loss**: Cleanup removes all ExternalSecret and SecretStore configurations
2. **Cluster-Wide Impact**: ClusterSecretStores are removed cluster-wide
3. **No Recovery**: This action cannot be undone
4. **Confirmation Required**: The script requires typing "yes" to proceed (unless `--force`)

**Before cleanup:**
- Document all ExternalSecret configurations
- Backup SecretStore configurations
- Verify no critical applications depend on synced secrets
- Notify team members of the planned cleanup


## Troubleshooting

### Common Issues

#### Issue: CSV Not Reaching "Succeeded" Phase

**Symptoms**:
```
Error: Timeout waiting for CSV to reach Succeeded phase
```

**Solution**:
```bash
# Check CSV status
oc get csv -n external-secrets-operator

# Check CSV details
oc describe csv -n external-secrets-operator

# Check operator pod logs
oc logs -n external-secrets-operator deployment/external-secrets-operator

# Check OLM operator logs
oc logs -n openshift-operator-lifecycle-manager deployment/olm-operator
```

#### Issue: Operator Pods Not Starting

**Symptoms**:
```
Error: Timeout waiting for operator pods to be ready
Pods stuck in Pending or CrashLoopBackOff
```

**Solution**:
```bash
# Check pod status
oc get pods -n external-secrets-operator

# Check pod events
oc describe pod -n external-secrets-operator <pod-name>

# Check pod logs
oc logs -n external-secrets-operator <pod-name>

# Check resource constraints
oc describe node | grep -A 5 "Allocated resources"
```

#### Issue: CRDs Not Established

**Symptoms**:
```
Error: Timeout waiting for CRDs to be established
CRD exists but is not ready to accept resources
```

**Solution**:
```bash
# Check CRD status
oc get crd clustersecretstores.external-secrets.io -o yaml

# Check CRD conditions
oc get crd clustersecretstores.external-secrets.io \
  -o jsonpath='{.status.conditions}'

# Wait longer and retry
# The script includes a 45-second wait, but some clusters may need more time

# Manually verify API server registration
oc api-resources --api-group=external-secrets.io
```

#### Issue: Phase 2 Deployment Failed

**Symptoms**:
```
Error: Phase 2 deployment failed after 3 attempts
```

**Solution**:
```bash
# Check if CRDs are fully ready
oc get crd clustersecretstores.external-secrets.io

# Verify API server can accept resources
oc get clustersecretstores.external-secrets.io --all-namespaces

# Check operator logs for errors
oc logs -n external-secrets-operator -l app=external-secrets-operator

# Manually retry Phase 2
helm upgrade external-secrets-operator ./helm/external-secrets-operator \
  --namespace external-secrets-operator \
  --values <your-values-file>
```

#### Issue: ClusterSecretStore Not Ready

**Symptoms**:
```
ClusterSecretStore shows STATUS: Invalid or READY: False
```

**Solution**:
```bash
# Check ClusterSecretStore status
oc describe clustersecretstore <name>

# Common issues:
# 1. Backend not accessible
# 2. Authentication credentials incorrect
# 3. Network policies blocking access

# For Vault backend:
# - Verify Vault is accessible
oc exec -n external-secrets-operator <operator-pod> -- \
  curl -v http://vault.vault.svc.cluster.local:8200/v1/sys/health

# - Check Vault authentication
oc logs -n external-secrets-operator -l app=external-secrets-operator | grep vault

# For AWS backend:
# - Verify AWS credentials are correct
oc get secret aws-credentials -n external-secrets-operator -o yaml

# - Test AWS connectivity
oc exec -n external-secrets-operator <operator-pod> -- \
  curl -v https://secretsmanager.${AWS_REGION}.amazonaws.com

# - Check AWS authentication
oc logs -n external-secrets-operator -l app=external-secrets-operator | grep -i aws

# For IBM Cloud backend:
# - Verify IBM Cloud API key is correct
oc get secret ibm-cloud-credentials -n external-secrets-operator -o yaml

# - Test IBM Cloud connectivity
oc exec -n external-secrets-operator <operator-pod> -- \
  curl -v https://${IBM_INSTANCE_ID}.${IBM_REGION}.secrets-manager.appdomain.cloud

# - Check IBM Cloud authentication
oc logs -n external-secrets-operator -l app=external-secrets-operator | grep -i ibm
```

#### Issue: ExternalSecret Not Syncing

**Symptoms**:
```
ExternalSecret created but Kubernetes secret not created
ExternalSecret shows errors in status
```

**Solution**:
```bash
# Check ExternalSecret status
oc describe externalsecret <name> -n <namespace>

# Check operator logs
oc logs -n external-secrets-operator -l app=external-secrets-operator

# Common issues:
# 1. Secret path doesn't exist in backend
# 2. Insufficient permissions
# 3. Invalid secret key mapping

# Verify secret exists in backend

# Vault example:
vault kv get secret/data/your-secret

# AWS example:
aws secretsmanager get-secret-value \
  --secret-id prod/myapp/database \
  --region ${AWS_REGION}

# IBM Cloud example:
ibmcloud secrets-manager secret --secret-id myapp-database-credentials

# Check SecretStore reference is correct
oc get externalsecret <name> -n <namespace> -o yaml
```

#### Issue: Cleanup Script Stuck

**Symptoms**:
```
Script hangs during resource deletion
Timeout waiting for pods to terminate
```

**Solution**:
```bash
# Force delete stuck resources
oc delete externalsecret --all -n external-secrets-operator --force --grace-period=0

# Remove finalizers from ClusterSecretStores
oc patch clustersecretstore <name> \
  -p '{"metadata":{"finalizers":[]}}' --type=merge

# Force delete namespace
oc delete namespace external-secrets-operator --force --grace-period=0

# If namespace is stuck in Terminating state
oc get namespace external-secrets-operator -o json | \
  jq '.spec.finalizers = []' | \
  oc replace --raw "/api/v1/namespaces/external-secrets-operator/finalize" -f -
```

### Debug Mode

Enable verbose output for detailed troubleshooting:

```bash
# Run deployment with verbose output
bash -x ./scripts/deploy-external-secrets.sh --backend vault

# Check all resources in namespace
oc get all -n external-secrets-operator

# Check all custom resources
oc get externalsecret,secretstore,clustersecretstore --all-namespaces

# Check events
oc get events -n external-secrets-operator --sort-by='.lastTimestamp'
```

### Getting Help

If you encounter issues not covered here:

1. **Check Operator Logs**:
   ```bash
   oc logs -n external-secrets-operator -l app=external-secrets-operator --tail=100
   ```

2. **Check Resource Status**:
   ```bash
   oc get all -n external-secrets-operator
   oc get externalsecret,secretstore,clustersecretstore --all-namespaces
   ```

3. **Check Events**:
   ```bash
   oc get events -n external-secrets-operator --sort-by='.lastTimestamp'
   ```

## Related Documentation

### External Resources

#### External Secrets Operator
- [External Secrets Operator Documentation](https://external-secrets.io/)
- [External Secrets API Reference](https://external-secrets.io/latest/api/externalsecret/)
- [Provider Documentation](https://external-secrets.io/latest/provider/aws-secrets-manager/)

#### HashiCorp Vault
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [HashiCorp Vault Kubernetes Auth](https://www.vaultproject.io/docs/auth/kubernetes)
- [Vault KV Secrets Engine](https://www.vaultproject.io/docs/secrets/kv)

#### AWS Secrets Manager
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [AWS Secrets Manager API Reference](https://docs.aws.amazon.com/secretsmanager/latest/apireference/)
- [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

#### IBM Cloud Secrets Manager
- [IBM Cloud Secrets Manager Documentation](https://cloud.ibm.com/docs/secrets-manager)
- [IBM Cloud Secrets Manager API Reference](https://cloud.ibm.com/apidocs/secrets-manager)
- [IBM Cloud IAM Documentation](https://cloud.ibm.com/docs/account?topic=account-iamoverview)
