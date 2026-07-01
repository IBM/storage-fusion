# Model Registry GitOps — Environment Deployment Guide

> See [`../../README.md`](../../README.md) for the full architecture overview and prerequisites.

This is the operational runbook for deploying, syncing, monitoring, and troubleshooting the Model Registry GitOps pipeline across all three environments.

## Overview

Each environment has its own ArgoCD `AppProject` and `Application` manifest. The Application sources the Helm chart from the same Git repository, using environment-specific `values.yaml` overrides.

```
argocd/environments/
├── dev/
│   ├── appproject-dev.yaml      # ArgoCD project + RBAC
│   └── application.yaml         # ArgoCD application (automated sync)
├── staging/
│   ├── appproject-staging.yaml  # ArgoCD project + RBAC (restricted)
│   └── application.yaml         # ArgoCD application (manual sync)
└── prod/
    ├── appproject-prod.yaml     # ArgoCD project + RBAC (strictest)
    └── application.yaml         # ArgoCD application (manual sync)
```

## Sync Policy Matrix

| Environment | Auto Sync | Prune | Self-Heal | Branch | Namespace |
|-------------|-----------|-------|-----------|--------|-----------|
| **Dev**     | ✅ Yes    | ✅ Yes | ✅ Yes   | `main` | `fusion-model-registry-gitops-dev` |
| **Staging** | ❌ No     | ✅ Yes | ✅ Yes   | `main`        | `fusion-model-registry-gitops-staging` |
| **Prod**    | ❌ No     | ✅ Yes | ✅ Yes   | `main` | `fusion-model-registry-gitops-prod` |

## RBAC Roles per Environment

| Role | Dev | Staging | Prod |
|------|-----|---------|------|
| `admin` | Full access | Full access | Full access |
| `developer` | get, sync, update | — | — |
| `deployer` | — | get, sync | get, sync |
| `viewer` | get | get | get |

---

## Deployment Steps

### Prerequisites (all environments)

```bash
# Verify you are logged in to OpenShift
oc whoami

# Verify ArgoCD is running
oc get pods -n openshift-gitops
```

---

### 1. Deploy Development Environment

Development is the first environment to deploy. Auto-sync is enabled — any push to `main` triggers an automatic reconciliation.

```bash
# 1. Apply the AppProject (creates project + RBAC)
oc apply -f argocd/environments/dev/appproject-dev.yaml

# 2. Apply the Application
oc apply -f argocd/environments/dev/application.yaml

# 3. Monitor sync — ArgoCD will sync automatically
oc get application fusion-model-registry-gitops-dev -n openshift-gitops
argocd app get fusion-model-registry-gitops-dev
```

**Dev characteristics:**
- ✅ Automated sync on every Git push to `main`
- ✅ Prune enabled — removed resources are cleaned up automatically
- ✅ Self-heal — drift is corrected automatically
- ✅ Namespace auto-created (`fusion-model-registry-gitops-dev`)
- ✅ All resource kinds allowed (`namespaceResourceWhitelist: *`)
- ⚡ Retry: up to 5 attempts with exponential back-off (5s → 3m max)

---

### 2. Deploy Staging Environment

After dev is stable, deploy to staging for pre-production validation. **Sync must be triggered manually.**

```bash
# 1. Apply the AppProject
oc apply -f argocd/environments/staging/appproject-staging.yaml

# 2. Apply the Application
oc apply -f argocd/environments/staging/application.yaml

# 3. Trigger the first sync manually
argocd app sync fusion-model-registry-gitops-staging

# 4. Monitor
oc get application fusion-model-registry-gitops-staging -n openshift-gitops
```

**Staging characteristics:**
- ⏸️ Manual sync required — no automated sync
- ✅ Prune enabled
- ✅ Self-heal enabled
- 🔒 Restricted `namespaceResourceWhitelist` — only specific resource kinds are allowed (ConfigMap, Secret, Service, ServiceAccount, Deployment, Job, CronJob, Role, RoleBinding, BuildConfig, ImageStream, NetworkPolicy)
- 🌿 Tracks `main` branch (stable, merged code only)

---

### 3. Deploy Production Environment

Production deployment requires strict change management. **Auto-sync is disabled — every sync must be triggered manually.**

```bash
# 1. Apply the AppProject
oc apply -f argocd/environments/prod/appproject-prod.yaml

# 2. Apply the Application
oc apply -f argocd/environments/prod/application.yaml

# 3. In the ArgoCD UI:
#    - Open application: fusion-model-registry-gitops-prod
#    - Review the diff carefully
#    - Click Sync only during an approved change window
```

Or via CLI (requires appropriate role):

```bash
argocd app sync fusion-model-registry-gitops-prod
```

**Production characteristics:**
- 🛑 Manual sync ONLY — no automated sync
- ✅ Prune enabled
- ✅ Self-heal enabled
- 🔒 Same restricted `namespaceResourceWhitelist` as staging
- 🔒 Stricter RBAC — `deployer` and `viewer` roles, no `developer` role
- 🌿 Tracks `main` branch
- 🧹 Orphaned resources: warns on all, ignores `kube-root-ca.crt` ConfigMap

---

## Environment Namespaces

Each environment creates and manages resources across three namespaces:

| Namespace | Purpose |
|-----------|---------|
| `fusion-model-registry-gitops-{env}` | Reconciler deployment, ConfigMaps, RBAC |
| `maas-{env}` | MaaS platform resources |
| `rhoai-model-registries` | Shared — Model Registry API (all environments point here) |

---

## Monitoring

### Check application status

```bash
# All environments at once
oc get applications -n openshift-gitops -l app=fusion-model-registry-gitops

# Per environment
oc get application fusion-model-registry-gitops-dev     -n openshift-gitops
oc get application fusion-model-registry-gitops-staging -n openshift-gitops
oc get application fusion-model-registry-gitops-prod    -n openshift-gitops
```

### Check reconciler logs (after sync)

```bash
# Dev
oc logs -f deployment/model-reconciler -n fusion-model-registry-gitops-dev

# Staging
oc logs -f deployment/model-reconciler -n fusion-model-registry-gitops-staging

# Prod
oc logs -f deployment/model-reconciler -n fusion-model-registry-gitops-prod
```

### Check registered models in the registry

```bash
oc exec -n rhoai-model-registries deployment/model-registry -- \
  curl -s http://localhost:8080/api/model_registry/v1alpha3/registered_models | jq
```

---

## Triggering a Manual Sync

For staging and prod, use one of:

```bash
# ArgoCD CLI
argocd app sync fusion-model-registry-gitops-staging
argocd app sync fusion-model-registry-gitops-prod

# kubectl patch (no ArgoCD CLI available)
oc patch application fusion-model-registry-gitops-prod -n openshift-gitops \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

---

## Troubleshooting

### Application not syncing

```bash
# Check full application status
argocd app get fusion-model-registry-gitops-dev

# Check ArgoCD controller logs
oc logs -n openshift-gitops deployment/argocd-application-controller --tail=50

# Check for sync window blocks (if configured)
argocd proj get fusion-model-registry-gitops-prod
```

### Application degraded / OutOfSync

```bash
# View detailed diff
argocd app diff fusion-model-registry-gitops-staging

# Describe the Application resource
oc describe application fusion-model-registry-gitops-staging -n openshift-gitops

# Check events in the target namespace
oc get events -n fusion-model-registry-gitops-staging --sort-by='.lastTimestamp'
```

### RBAC / permission errors

```bash
# Check what the AppProject allows
oc get appproject fusion-model-registry-gitops-dev -n openshift-gitops -o yaml

# Check ArgoCD RBAC config
oc get configmap argocd-rbac-cm -n openshift-gitops -o yaml

# Test access
argocd app list --project fusion-model-registry-gitops-dev
```

### Rollback

```bash
# View deployment history
argocd app history fusion-model-registry-gitops-prod

# Roll back to a specific revision
argocd app rollback fusion-model-registry-gitops-prod <revision>
```

---

## Environment Promotion Workflow

Always promote changes through environments in order:

```
dev (auto-sync) → staging (manual sync + QA) → prod (manual sync + change window)
```

1. Merge model YAML changes to `main` → dev syncs automatically
2. Validate in dev: check reconciler logs, verify models registered
3. Merge to `main` → manually sync staging
4. QA validation in staging
5. During approved change window → manually sync prod
6. Verify models in prod registry UI

---

## Best Practices

- **Never enable auto-sync on prod** — all production syncs must be intentional
- **Review the diff before syncing staging/prod** — use `argocd app diff` or the ArgoCD UI
- **Use the `viewer` role for read-only access** — avoid granting `admin` to developers in staging/prod
- **Pin the prod branch** — prod tracks `main`; only merge tested, approved commits there

---

## Helm Values Configuration

Each ArgoCD `Application` deploys the [`maas-model-registry`](../../../../deploy/helm/maas-model-registry) Helm chart. Values are applied in layers — later files override earlier ones:

```yaml
# argocd/environments/prod/application.yaml
helm:
  valueFiles:
    - values.yaml                      # Base defaults (chart root)
    - environments/prod/values.yaml    # Production overrides
```

The resolved value chain per environment:

| Layer | File | Purpose |
|-------|------|---------|
| 1 — Base | `values.yaml` | Shared defaults for all environments |
| 2 — Override | `environments/dev/values.yaml` | Dev-specific overrides |
| 2 — Override | `environments/staging/values.yaml` | Staging-specific overrides |
| 2 — Override | `environments/prod/values.yaml` | Production-specific overrides |

All three files live inside the Helm chart path (`AI/quickstarts/model-as-a-service/deploy/helm/maas-model-registry/`), so ArgoCD resolves them relative to that path automatically.

### Adding a custom values file

To inject additional configuration without editing the base files, add a third entry to `valueFiles`:

```yaml
# argocd/environments/prod/application.yaml
helm:
  valueFiles:
    - values.yaml
    - environments/prod/values.yaml
    - environments/prod/values-custom.yaml   # ← add your file here
```

Then create `AI/quickstarts/model-as-a-service/deploy/helm/maas-model-registry/environments/prod/values-custom.yaml` with only the keys you want to override:

```yaml
# environments/prod/values-custom.yaml — only override what you need
reconciler:
  config:
    logLevel: DEBUG          # temporarily enable debug logging
    reconcileInterval: 120   # reconcile every 2 minutes instead of 10

huggingface:
  enabled: true              # enable HuggingFace token injection
  secretName: hf-token-prod
```

> **Note:** Commit `values-custom.yaml` to Git — ArgoCD reads all `valueFiles` from the repository, not the local filesystem.

### Key values to customise per environment

See [`../../../../deploy/helm/maas-model-registry/README.md`](../../../../deploy/helm/maas-model-registry/README.md) for the full values reference. The most commonly changed keys per environment are:

| Key | Dev | Staging | Prod |
|-----|-----|---------|------|
| `namespace` | `fusion-model-registry-gitops-dev` | `fusion-model-registry-gitops-staging` | `fusion-model-registry-gitops-prod` |
| `modelRegistry.obcName` | `model-registry-artifacts-dev` | `model-registry-artifacts-staging` | `model-registry-artifacts-prod` |
| `reconciler.config.reconcileInterval` | `180` | `300` | `600` |
| `reconciler.config.logLevel` | `DEBUG` | `INFO` | `WARNING` |
| `reconciler.resources.limits.memory` | `8Gi` | `8Gi` | `16Gi` |
| `cronJob.schedule` | `*/3 * * * *` | `*/5 * * * *` | `*/10 * * * *` |
| `buildConfig.git.ref` | `develop` | `main` | `main` |

