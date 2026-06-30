# MaaS GitOps Deployment

Environment-specific GitOps deployment structure for the Model-as-a-Service (MaaS) Platform.

> 📖 For the full operational runbook — step-by-step sync, troubleshooting, RBAC, security, and migration — see **[`environments/DEPLOYMENT_GUIDE.md`](environments/DEPLOYMENT_GUIDE.md)**.

## Directory Structure

```
maas-gitops-deployment/
├── README.md                              # This file
├── argocd-cluster-rbac.yaml               # ClusterRole/ClusterRoleBinding for ArgoCD
├── environments/                          # Environment-specific deployments
│   ├── DEPLOYMENT_GUIDE.md               # Full operational runbook
│   ├── dev/                              # Development environment
│   │   ├── 00-dev-app-of-apps.yaml
│   │   ├── appproject-dev.yaml
│   │   └── applications/
│   │       ├── 01-maas-operators-dev.yaml
│   │       ├── 02-maas-platform-dev.yaml
│   │       └── 03-maas-runtime-dev.yaml
│   ├── staging/                          # Staging environment
│   │   ├── 00-staging-app-of-apps.yaml
│   │   ├── appproject-staging.yaml
│   │   └── applications/
│   │       ├── 01-maas-operators-staging.yaml
│   │       ├── 02-maas-platform-staging.yaml
│   │       └── 03-maas-runtime-staging.yaml
│   └── prod/                             # Production environment
│       ├── 00-prod-app-of-apps.yaml
│       ├── appproject-prod.yaml
│       └── applications/
│           ├── 01-maas-operators-prod.yaml
│           ├── 02-maas-platform-prod.yaml
│           └── 03-maas-runtime-prod.yaml

```

## Quick Start

### Step 0 — Bootstrap Cluster RBAC (one-time, required for all environments)

```bash
# Grant ArgoCD the cluster-wide permissions it needs to manage MaaS CRDs
oc apply -f argocd-cluster-rbac.yaml
```

### Deploy to Development

```bash
# 1. Create the AppProject
oc apply -f environments/dev/appproject-dev.yaml

# 2. Deploy the App-of-Apps (automated sync — ArgoCD will deploy child apps automatically)
oc apply -f environments/dev/00-dev-app-of-apps.yaml
```

### Deploy to Staging

```bash
# 1. Create the AppProject
oc apply -f environments/staging/appproject-staging.yaml

# 2. Deploy the App-of-Apps
oc apply -f environments/staging/00-staging-app-of-apps.yaml

# 3. Manually trigger sync in the ArgoCD UI (auto-sync is disabled for staging)
```

### Deploy to Production

```bash
# 1. Create the AppProject
oc apply -f environments/prod/appproject-prod.yaml

# 2. Deploy the App-of-Apps
oc apply -f environments/prod/00-prod-app-of-apps.yaml

# 3. Manually trigger each sync wave in the ArgoCD UI (auto-sync is disabled for prod)
```

> For the full production sync walkthrough (waves, health checks, verification commands), see the [Deployment Guide](environments/DEPLOYMENT_GUIDE.md).

## Environment Structure

Each environment directory follows the same layout:

```
{env}/
├── 00-{env}-app-of-apps.yaml         # App-of-Apps orchestrator
├── appproject-{env}.yaml              # Environment-specific AppProject
└── applications/                      # ArgoCD child Applications
    ├── 01-maas-operators-{env}.yaml
    ├── 02-maas-platform-{env}.yaml
    └── 03-maas-runtime-{env}.yaml
```

## Sync Wave Summary

Applications are deployed in ordered sync waves across all environments:

| Wave | Resource | Application |
|------|----------|-------------|
| -10  | App-of-Apps orchestrator | `fusion-maas-platform-orchestrator-{env}` |
| 0    | Operators (RHOAI, Kuadrant, Authorino) | `fusion-maas-operators-{env}` |
| 50   | Platform config (DataScienceCluster, Kuadrant/Authorino instances) | `fusion-maas-platform-config-{env}` |
| 100  | Runtime (Gateway, ModelRegistry, RBAC, Storage) | `fusion-maas-runtime-{env}` |

## Environment Differences

| Feature | Dev | Staging | Prod |
|---------|-----|---------|------|
| Sync Policy | Automated | Manual | Manual |
| Grafana | Disabled | Enabled | Enabled |
| Resource Limits | Lower | Medium | Higher |
| Monitoring | Basic | Enhanced | Full |

## Documentation

- **Full Deployment Runbook**: [`environments/DEPLOYMENT_GUIDE.md`](environments/DEPLOYMENT_GUIDE.md)
- **Helm Values**: `../../helm/*/environments/{env}/values.yaml`
