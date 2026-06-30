# MaaS Platform - Environment-Specific Deployment Guide

> See [`../README.md`](../README.md) for the directory structure overview and quick-start commands.

This guide is the full operational runbook for deploying, syncing, monitoring, and troubleshooting the MaaS platform across all environments.

## Overview

The MaaS platform supports environment-specific deployments with separate configurations for:
- **Development (dev)**: Fast iteration, automated sync, aggressive self-healing
- **Staging**: Pre-production testing, manual sync, moderate controls
- **Production (prod)**: Strict controls, manual sync only, change windows

## Sync Policy Matrix

| Environment | Auto Sync | Prune | SelfHeal | Approval |
|-------------|-----------|-------|----------|----------|
| **Dev**     | ✅ Yes    | ✅ Yes | ✅ Yes  | Automatic |
| **Staging** | ❌ No     | ✅ Yes | ✅ Yes  | Manual |
| **Prod**    | ❌ No     | ❌ No  | ✅ Yes  | Manual + change window |

## Deployment Order

### Prerequisites — Bootstrap Cluster RBAC (one-time, required for all environments)

```bash
# Grant ArgoCD the cluster-wide permissions it needs to manage MaaS CRDs
oc apply -f argocd-cluster-rbac.yaml
```

### 1. Deploy Development Environment

Development is the first environment to deploy for testing and validation.

```bash
# Apply the AppProject first
oc apply -f environments/dev/appproject-dev.yaml

# Wait for AppProject to be ready
oc wait --for=condition=Ready appproject/fusion-maas-platform-dev -n openshift-gitops --timeout=60s

# Deploy the App-of-Apps
oc apply -f environments/dev/00-dev-app-of-apps.yaml

# Monitor deployment
oc get applications -n openshift-gitops -l environment=dev
argocd app list --project fusion-maas-platform-dev
```

**Dev Characteristics:**
- ✅ Automated sync enabled
- ✅ Self-healing enabled
- ✅ Prune enabled
- ⚡ Fast iteration
- 🔄 Continuous deployment

### 2. Deploy Staging Environment

After dev is stable, deploy to staging for pre-production testing.

```bash
# Apply the AppProject
oc apply -f environments/staging/appproject-staging.yaml

# Wait for AppProject to be ready
oc wait --for=condition=Ready appproject/fusion-maas-platform-staging -n openshift-gitops --timeout=60s

# Deploy the App-of-Apps
oc apply -f environments/staging/00-staging-app-of-apps.yaml

# Staging requires MANUAL sync in the ArgoCD UI
argocd app sync fusion-maas-platform-staging --project fusion-maas-platform-staging
```

**Staging Characteristics:**
- ⏸️ Manual sync required
- ✅ Self-healing enabled
- ✅ Prune enabled
- 🧪 Pre-production testing
- 📋 QA validation

### 3. Deploy Production Environment

Production deployment requires strict change management. Auto-sync is disabled — every sync must be triggered manually from the ArgoCD UI.

#### 3a. Apply AppProject and App-of-Apps

```bash
# Create the production AppProject
oc apply -f environments/prod/appproject-prod.yaml

# Wait for AppProject to be ready
oc wait --for=condition=Ready appproject/fusion-maas-platform-prod -n openshift-gitops --timeout=60s

# Deploy the App-of-Apps
oc apply -f environments/prod/00-prod-app-of-apps.yaml
```

#### 3b. Sync the App-of-Apps Orchestrator (Wave -10)

1. In the ArgoCD UI, navigate to the **Applications** page.
2. Open **`fusion-maas-platform-orchestrator-prod`** and click **Sync**.
3. Wait until the application status transitions to **Healthy**.

#### 3c. Sync Operators (Wave 0)

1. Open **`fusion-maas-operators-prod`** and click **Sync**.
2. ArgoCD creates the namespaces, OperatorGroups, and Subscriptions for RHOAI, Kuadrant, and Authorino.
3. Wait for the status to change from **Progressing → Healthy**.

#### 3d. Sync Platform Config (Wave 50)

1. Open **`fusion-maas-platform-config-prod`** and click **Sync**.
2. ArgoCD creates `DataScienceCluster`, Authorino, and Kuadrant instances.
3. Verify the `DataScienceCluster` CR reaches **Ready** state before continuing:
   ```bash
   oc get datasciencecluster default-dsc
   ```
4. Wait for the application status to reach **Healthy**.

#### 3e. Sync Runtime (Wave 100)

1. Open **`fusion-maas-runtime-prod`** and click **Sync**.
2. ArgoCD creates the Gateway, ModelRegistry, RBAC resources, and object storage claims.
3. Wait for the application status to reach **Healthy**.

**Verify all three child applications are Healthy:**

```bash
oc get applications -n openshift-gitops \
  fusion-maas-operators-prod \
  fusion-maas-platform-config-prod \
  fusion-maas-runtime-prod
```

**Production Characteristics:**
- 🛑 Manual sync ONLY
- ✅ Self-healing enabled
- ❌ Prune disabled (manual cleanup)
- 🔒 Strict RBAC
- 📅 Change windows enforced
- 🚨 Alert notifications (Slack: `maas-prod-alerts`)

## Environment-Specific Configuration

### Development (dev)

**Namespace:** `maas-dev`

**Sync Policy:**
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

**Use Cases:**
- Feature development
- Bug fixes
- Integration testing
- Rapid iteration

**Access:**
- Developers: Full access
- Admins: Full access

### Staging

**Namespace:** `maas-staging`

**Sync Policy:**
```yaml
syncPolicy:
  automated: null  # Manual sync
  syncOptions:
    - CreateNamespace=true
```

**Use Cases:**
- Pre-production validation
- QA testing
- Performance testing
- Release candidate validation

**Access:**
- Developers: Read + Sync
- QA: Read-only
- Admins: Full access

### Production

**Namespace:** `maas-prod`

**Sync Policy:**
```yaml
syncPolicy:
  automated: null  # Manual sync ONLY
  prune: false     # No automatic cleanup
```

**Sync Windows:**
- **Allowed:** Sunday 2 AM - 6 AM
- **Denied:** Weekdays 9 AM - 5 PM

**Use Cases:**
- Live production workloads
- Customer-facing services
- Mission-critical operations

**Access:**
- Platform Admins: Sync only
- Operators: Sync only
- Developers: Read-only
- QA: Read-only

## Customization

### Modifying Environment Configuration

Each environment has a `values.yaml` file with environment-specific overrides:

```bash
# Edit dev configuration
vi environments/dev/values.yaml

# Edit staging configuration
vi environments/staging/values.yaml

# Edit production configuration
vi environments/prod/values.yaml
```

### Key Configuration Areas

1. **Operator Versions**
   ```yaml
   operators:
     rhoai:
       channel: fast  # dev: fast, staging: fast, prod: stable
       version: v2.18.0
   ```

2. **Resource Quotas**
   ```yaml
   resourceQuotas:
     limits:
       cpu: "200"      # dev: 200, staging: 100, prod: 500
       memory: "1Ti"   # dev: 1Ti, staging: 500Gi, prod: 2Ti
       nvidia.com/gpu: "32"  # dev: 32, staging: 16, prod: 64
   ```

3. **Rate Limiting**
   ```yaml
   rateLimiting:
     limits:
       - limit: 50     # dev: 50, staging: 100, prod: 1000
         duration: 60
   ```

4. **High Availability**
   ```yaml
   highAvailability:
     enabled: true     # dev: false, staging: false, prod: true
     replicas: 3       # prod only
   ```

## Monitoring Deployments

### Check Application Status

```bash
# All environments
oc get applications -n openshift-gitops

# Specific environment
oc get applications -n openshift-gitops -l environment=dev
oc get applications -n openshift-gitops -l environment=staging
oc get applications -n openshift-gitops -l environment=prod

# Using ArgoCD CLI
argocd app list --project fusion-maas-platform-dev
argocd app list --project fusion-maas-platform-staging
argocd app list --project fusion-maas-platform-prod
```

### View Application Details

```bash
# Get application details
argocd app get fusion-maas-operators-dev
argocd app get fusion-maas-platform-staging
argocd app get fusion-maas-runtime-prod

# View sync status
argocd app sync-status fusion-maas-operators-dev
```

### Check Health

```bash
# Check all resources in an environment
oc get all -n maas-dev
oc get all -n maas-staging
oc get all -n maas-prod

# Check specific resources
oc get datasciencecluster -A
oc get modelregistry -A
oc get gateway -A
```

## Troubleshooting

### Application Not Syncing

**Dev Environment:**
```bash
# Check sync status
argocd app get fusion-maas-platform-dev

# Force sync if needed
argocd app sync fusion-maas-platform-dev --force
```

**Staging/Production:**
```bash
# Manual sync required
argocd app sync fusion-maas-platform-staging
argocd app sync fusion-maas-platform-prod

# Check for sync windows (prod only)
argocd proj get fusion-maas-platform-prod
```

### Application Degraded

```bash
# Check application health
argocd app get fusion-maas-runtime-dev

# View detailed status
oc describe application fusion-maas-runtime-dev -n openshift-gitops

# Check underlying resources
oc get all -n maas-dev
```

### RBAC Issues

```bash
# Check AppProject permissions
oc get appproject fusion-maas-platform-dev -n openshift-gitops -o yaml

# Verify RBAC ConfigMap
oc get configmap argocd-rbac-cm -n openshift-gitops -o yaml

# Test access
argocd app list --project fusion-maas-platform-dev
```

## Best Practices

### 1. Environment Promotion

Always promote changes through environments:
```
dev → staging → prod
```

### 2. Version Pinning

- **Dev:** Use `fast` channel for latest features
- **Staging:** Use tested versions from dev
- **Prod:** Use stable, pinned versions

### 3. Change Management

**Production Changes:**
1. Test in dev
2. Validate in staging
3. Create change request
4. Deploy during change window
5. Monitor and validate

### 4. Rollback Strategy

```bash
# View application history
argocd app history fusion-maas-platform-prod

# Rollback to previous version
argocd app rollback fusion-maas-platform-prod <revision>
```

### 5. Backup and Recovery

**Production:**
- Database backups: Daily at 2 AM
- Retention: 30 days
- Test restores monthly

## Security Considerations

### 1. Secrets Management

- Use external secrets operator
- Rotate secrets regularly
- Never commit secrets to Git

### 2. RBAC

- Principle of least privilege
- Separate roles per environment
- Regular access reviews

### 3. Network Policies

- Enabled in production
- Restrict inter-namespace communication
- Allow only required traffic

### 4. Pod Security

- Enforce restricted standards in prod
- Use security contexts
- Scan images regularly

## Migration from Legacy Structure

If migrating from the old single-environment structure:

```bash
# 1. Backup existing applications
oc get applications -n openshift-gitops -o yaml > backup-applications.yaml

# 2. Delete old applications
oc delete application maas-operators -n openshift-gitops
oc delete application maas-platform -n openshift-gitops
oc delete application maas-runtime -n openshift-gitops

# 3. Deploy new environment-specific structure
oc apply -f environments/dev/appproject-dev.yaml
oc apply -f environments/dev/00-dev-app-of-apps.yaml

# 4. Verify deployment
oc get applications -n openshift-gitops -l environment=dev
```

## Support and Documentation

- **Main Documentation:** `../../../docs/GETTING_STARTED.md`
- **Operators Guide:** `../../../docs/01-setup/MAAS_OPERATORS_GUIDE.md`
- **Platform Guide:** `../../../docs/01-setup/MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md`
- **Runtime Guide:** `../../../docs/01-setup/MAAS_RUNTIME_CUSTOMIZATION_GUIDE.md`

## Next Steps

1. Deploy development environment
2. Validate all components are healthy
3. Test model deployment in dev
4. Promote to staging
5. Perform QA validation
6. Plan production deployment
7. Execute production deployment during change window