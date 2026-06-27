# Fusion Developer Hub GitOps Deployment

Environment-specific GitOps deployment structure for IBM Fusion Developer Hub.

## Directory Structure

```
deploy/gitops/
├── README.md                          # This file
└── environments/                      # Environment-specific deployments
    ├── dev/                          # Development environment
    ├── staging/                      # Staging environment
    └── prod/                         # Production environment
```

## Quick Start

### Deploy to Development Environment

```bash
# Apply the development ArgoCD Application
kubectl apply -f environments/dev/application.yaml
```

### Deploy to Staging Environment

```bash
# Apply the staging ArgoCD Application
kubectl apply -f environments/staging/application.yaml
```

### Deploy to Production Environment

```bash
# Apply the production ArgoCD Application
kubectl apply -f environments/prod/application.yaml
```

## Environment Structure

Each environment directory contains:

```
{env}/
└── application.yaml                   # ArgoCD Application manifest
```

The Application references:
- **Helm Chart**: `../helm/` (shared across environments)
- **Values File**: `../helm/environments/{env}/values.yaml`
- **Inline Values**: Environment-specific overrides in `valuesObject`

## Environment Differences

| Feature | Dev | Staging | Prod |
|---------|-----|---------|------|
| Sync Policy | Automated | Automated | Manual |
| Self-Heal | Enabled | Enabled | Disabled |
| Namespace | fusion-developer-hub-development | fusion-developer-hub-staging | fusion-developer-hub |
| Resources | Lower | Medium | Higher |

## Configuration

### Required Changes

Before deploying, update each `application.yaml`:

1. **Repository URL**: Replace `https://github.com/your-org/your-repo.git`
2. **Target Revision**: Set your branch/tag (default: `main`)
3. **Cluster Domain**: Update `wildcardDomain` in `valuesObject`
4. **Storage Class**: Set `storageClassName` for RWX storage

### Values Hierarchy

Values are merged in this order (last wins):

1. Base Helm values: `../helm/values.yaml`
2. Environment values: `../helm/environments/{env}/values.yaml`
3. Inline values: `valuesObject` in `application.yaml`

## Documentation

- **Main Quickstart**: `../../QUICKSTART.md`
- **Helm Chart**: `../helm/README.md`
- **Environment Values**: `../helm/environments/`
- **Version Management**: `../helm/VERSION_MANAGEMENT.md`

## Prerequisites

- OpenShift 4.15+
- ArgoCD/OpenShift GitOps installed
- RWX-capable storage class
- Cluster admin access