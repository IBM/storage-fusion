# Model Registry GitOps

GitOps pipeline for managing AI model registration in the OpenShift AI Model Registry. Git is the single source of truth — commit a model YAML, and it is automatically registered in the RHOAI Model Registry without any manual API calls.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Git Repository  (models/**/*.yaml)                  │
└────────────────────────┬────────────────────────────┘
                         │ ArgoCD syncs
                         ▼
┌─────────────────────────────────────────────────────┐
│  ConfigMap: model-definitions                        │
│  (namespace: fusion-model-registry-gitops-{env})     │
└────────────────────────┬────────────────────────────┘
                         │ Reconciler watches
                         ▼
┌─────────────────────────────────────────────────────┐
│  Model Reconciler Deployment                         │
│  Calls Model Registry REST API                       │
└────────────────────────┬────────────────────────────┘
                         │ Registers models
                         ▼
┌─────────────────────────────────────────────────────┐
│  Model Registry API  (rhoai-model-registries)        │
│  → RHOAI UI Model Catalog                            │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

- OpenShift cluster with OpenShift GitOps (ArgoCD) installed
- Red Hat OpenShift AI with Model Registry enabled
- For **private repositories**: Git credentials required (see below)

## Directory Structure

```
model-registry-gitops/
├── README.md                              # This file
├── models/                                # Model definition YAML files (source of truth)
│   ├── ADDING_A_MODEL.md                  # How to register a new model
│   ├── schema.yaml                        # YAML validation schema
│   ├── granite/                           # IBM Granite models
│   ├── qwen/                              # Qwen models
│   ├── chatgpt/                           # OpenAI-based models
│   ├── gpt-oss/                           # GPT OSS models
│   └── test-model/                        # Lightweight test models
├── argocd/
│   └── environments/
│       ├── DEPLOYMENT_GUIDE.md            # Deploy/sync/troubleshoot per environment
│       ├── dev/                           # Dev AppProject + Application
│       ├── staging/                       # Staging AppProject + Application
│       └── prod/                          # Prod AppProject + Application
└── docs/
    ├── QUICKSTART.md                      # End-to-end setup guide
    └── VERIFICATION_GUIDE.md              # Post-deploy verification commands
```

## Quick Start

### 1. Configure Git Credentials (private repositories only)

> **Create this secret BEFORE deploying the ArgoCD application.**

```bash
# Option A: kubectl (development)
kubectl create secret generic git-credentials \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_TOKEN \
  --namespace=fusion-model-registry-gitops-dev

# Option B: Sealed Secrets (production recommended)
kubectl create secret generic git-credentials \
  --from-literal=username=YOUR_USERNAME \
  --from-literal=password=YOUR_TOKEN \
  --namespace=fusion-model-registry-gitops-prod \
  --dry-run=client -o yaml \
  | kubeseal -w argocd/environments/prod/git-credentials-sealed.yaml
```

### 2. Deploy to an environment

```bash
# Development (auto-sync enabled)
oc apply -f argocd/environments/dev/appproject-dev.yaml
oc apply -f argocd/environments/dev/application.yaml

# Staging / Production (manual sync)
oc apply -f argocd/environments/staging/appproject-staging.yaml
oc apply -f argocd/environments/staging/application.yaml
```

See [`argocd/environments/DEPLOYMENT_GUIDE.md`](argocd/environments/DEPLOYMENT_GUIDE.md) for the full per-environment runbook.

### 3. Add a model

Create a YAML file under `models/<your-org>/your-model.yaml`:

```yaml
apiVersion: v1
kind: ModelVersion
metadata:
  name: my-model          # lowercase, hyphens only
  labels:
    model-type: public
    source: huggingface
    governance-status: approved
spec:
  modelName: "My Model"
  version: "1.0.0"
  description: "What this model does."
  storage:
    uri: "hf://my-org/my-model"
    type: huggingface
    format: safetensors
  tags:
    - llm
    - approved
```

Commit, push, and ArgoCD does the rest. See [`models/ADDING_A_MODEL.md`](models/ADDING_A_MODEL.md) for the full field reference.

## Configuration

The reconciler reads these environment variables (set in the Helm chart values):

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `fusion-model-registry-gitops` | Namespace to watch for ConfigMaps |
| `TARGET_NAMESPACE` | `rhoai-model-registries` | Namespace where Model Registry is deployed |
| `REGISTRY_HOST` | — | Model Registry API endpoint |
| `RECONCILE_INTERVAL` | `300` | Seconds between full reconciliation cycles |
| `LOG_LEVEL` | `INFO` | Logging verbosity |

## Security Best Practices

1. **Never commit plain-text credentials** to Git
2. **Use Sealed Secrets** or an external secrets operator for production
3. **Rotate tokens regularly** (every 90 days recommended)
4. **Use least-privilege tokens** — only the `repo` scope for private repos
5. **Review RBAC permissions** in the AppProject manifests regularly

## Documentation

| Document | Purpose |
|----------|---------|
| [`models/ADDING_A_MODEL.md`](models/ADDING_A_MODEL.md) | Full field reference and step-by-step model registration |
| [`argocd/environments/DEPLOYMENT_GUIDE.md`](argocd/environments/DEPLOYMENT_GUIDE.md) | Per-environment deploy, sync, monitor, and rollback |
| [`docs/QUICKSTART.md`](docs/QUICKSTART.md) | End-to-end setup from zero to first registered model |
| [`docs/VERIFICATION_GUIDE.md`](docs/VERIFICATION_GUIDE.md) | Post-deploy health checks and troubleshooting |
