# MaaS Config — GitOps

ArgoCD manifests for managing MaaS governance resources on the IBM Fusion MaaS platform via the [`maas-config`](../../helm/maas-config) Helm chart.

Each environment has **one `AppProject` and one `Application`** that govern all models in that environment. Resources managed:

- `MaaSSubscription` — grants token quota for model access to specified groups
- `MaaSAuthPolicy` — grants API gateway access to model endpoints
- `Group` — manages OpenShift group membership declaratively (declared in the `groups` block of each values file)

> **Both `MaaSSubscription` and `MaaSAuthPolicy` must exist.** Without a subscription: `429 Too Many Requests`. Without an auth policy: `403 Forbidden`.

> **Important:** Subscriptions and authorization policies are independent resources. If you modify a subscription to add or remove groups or models, you must manually update the corresponding authorization policy to keep them synchronized.

---

## Directory Structure

```
maas-config/
├── README.md
└── environments/
    ├── dev/
    │   ├── appproject-dev.yaml                       # ArgoCD project + RBAC
    │   └── application-governance-dev.yaml           # Automated sync
    ├── staging/
    │   ├── appproject-staging.yaml
    │   └── application-governance-staging.yaml       # Manual sync
    └── prod/
        ├── appproject-prod.yaml
        └── application-governance-prod.yaml          # Manual sync, no prune
```

---

## Sync Policy

| Environment | Application name | Auto Sync | Prune | Sync Wave | Namespace |
|---|---|---|---|---|---|
| **Dev** | `fusion-maas-governance-config-dev` | Yes (self-heal) | Yes | 300 | `models-as-a-service` |
| **Staging** | `fusion-maas-governance-config-staging` | No (manual) | Yes | 300 | `models-as-a-service` |
| **Prod** | `fusion-maas-governance-config-prod` | No (manual) | No | 300 | `models-as-a-service` |

Sync wave `300` runs **after** `maas-model-deploy` (wave `200`) so that `MaaSModelRef` resources exist before the subscription and auth policy reference them.

---

## Single-Application Design

One `AppProject` and one `Application` per environment governs all models through a single values file:

```
appproject-prod.yaml   (name: fusion-maas-governance-config-prod)
    └── application-governance-prod.yaml
            └── environments/prod/values-prod.yaml
                    ├── MaaSSubscription  maas-prod-subscription
                    │     modelRefs: [gpt-oss-20b-100, tiny-llama-test]
                    └── MaaSAuthPolicy    maas-prod-auth-policy
                          modelRefs: [gpt-oss-20b-100, tiny-llama-test]
```

To add a new model: append one `modelRefs` entry to both `subscriptions[0].modelRefs` and `authPolicies[0].modelRefs` in the environment values file, then sync.

---

## Prerequisites

1. **MaaS model deploy is healthy** — the `MaaSModelRef` must already exist in the model namespace before applying config resources:
   ```bash
   oc get maasmodelref -n deploy-models
   ```
2. **ArgoCD is running:**
   ```bash
   oc get pods -n openshift-gitops
   ```

---

## Quick Start

### Updating `repoURL` and `targetRevision`

Every Application manifest contains a `source` block that tells ArgoCD where to fetch the Helm chart from. Two fields you are most likely to change before applying:

| Field | Purpose | Default |
|---|---|---|
| `repoURL` | Git repository containing the Helm chart | `https://github.com/IBM/storage-fusion.git` |
| `targetRevision` | Branch, tag, or commit SHA ArgoCD tracks | `main` (all environments) |

#### Files to update

| Environment | File |
|---|---|
| Dev | [`environments/dev/application-governance-dev.yaml`](environments/dev/application-governance-dev.yaml) |
| Staging | [`environments/staging/application-governance-staging.yaml`](environments/staging/application-governance-staging.yaml) |
| Prod | [`environments/prod/application-governance-prod.yaml`](environments/prod/application-governance-prod.yaml) |

The `source` block looks like this in every file:

```yaml
source:
  repoURL: https://github.com/IBM/storage-fusion.git   # change this
  targetRevision: master                                           # change this
  path: AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config
```

**Bulk update across all environments at once:**
```bash
find environments -name '*.yaml' | xargs sed -i \
  's|repoURL: https://github.com/IBM/storage-fusion.git|repoURL: https://github.com/my-org/storage-fusion.git|g'

find environments -name '*.yaml' | xargs sed -i \
  's|targetRevision: master|targetRevision: v1.2.0|g'
```

**If `appproject-*.yaml` has an explicit `sourceRepos` allowlist** (not a wildcard), add the new `repoURL` there too — ArgoCD will reject syncs from an unlisted repo:

```yaml
# appproject-prod.yaml (excerpt)
spec:
  sourceRepos:
    - https://github.com/IBM/storage-fusion.git   # existing
    - https://github.com/my-org/storage-fusion.git             # add new URL
```

---

### Production

```bash
# Apply the AppProject (once per cluster)
oc apply -f environments/prod/appproject-prod.yaml

# Register the Application with ArgoCD
oc apply -f environments/prod/application-governance-prod.yaml

# Sync during an approved change window (manual only in prod)
argocd app sync fusion-maas-governance-config-prod

# Confirm sync status
oc get applications.argoproj.io fusion-maas-governance-config-prod -n openshift-gitops
```

### Development

Development uses **automated sync with self-healing** — changes pushed to the tracked branch are applied without manual intervention. Token limits are lower than production.

```bash
oc apply -f environments/dev/appproject-dev.yaml
oc apply -f environments/dev/application-governance-dev.yaml

# Dev auto-syncs — watch it converge
oc get application fusion-maas-governance-config-dev -n openshift-gitops -w
```

### Staging

Staging uses **manual sync** and mirrors production values as closely as possible. Unlike production, pruning is enabled — resources removed from the values file are deleted from the cluster on the next sync.

```bash
oc apply -f environments/staging/appproject-staging.yaml
oc apply -f environments/staging/application-governance-staging.yaml

# Sync after QA approval
argocd app sync fusion-maas-governance-config-staging
```

---

## Adding a New Model to Production Governance

Append to both `modelRefs` lists in [`../../helm/maas-config/environments/prod/values-prod.yaml`](../../helm/maas-config/environments/prod/values-prod.yaml):

```yaml
subscriptions:
  - name: maas-prod-subscription
    modelRefs:
      # ... existing models ...
      - name: my-new-model          # oc get maasmodelref -n deploy-models
        namespace: deploy-models
        tokenRateLimits:
          - limit: 10000
            window: "1h"

authPolicies:
  - name: maas-prod-auth-policy
    modelRefs:
      # ... existing models ...
      - name: my-new-model
        namespace: deploy-models
```

Then commit, push, and sync:
```bash
git add AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/environments/prod/values-prod.yaml
git commit -m "Add governance for my-new-model to maas-prod-subscription and maas-prod-auth-policy"
git push
argocd app sync fusion-maas-governance-config-prod
```

---

## Troubleshooting

### Application OutOfSync on MaaSSubscription / MaaSAuthPolicy

The MaaS controller writes `.status` back to these resources after creation. The `ignoreDifferences` block in each Application suppresses this drift. Verify `RespectIgnoreDifferences=true` is in `syncOptions` and the `ignoreDifferences` block is intact:

```bash
oc get application fusion-maas-governance-config-prod \
  -n openshift-gitops -o jsonpath='{.spec.ignoreDifferences}'
```

### MaaSModelRef not found

If a subscription or auth policy fails to become `Active`, verify the referenced `MaaSModelRef` exists:

```bash
oc get maasmodelref -n deploy-models
```

The `MaaSModelRef` is created by the `maas-model-deploy` chart (wave `200`) and must be `Ready` before this chart (wave `300`) reconciles. Re-sync `maas-model-deploy` first if the resource is missing.

### Check resource status

```bash
oc get maassubscription -n models-as-a-service
oc get maasauthpolicy -n models-as-a-service
oc get applications.argoproj.io -n openshift-gitops -l component=maas-config
oc get events -n models-as-a-service --sort-by='.lastTimestamp'
```

---

## Related

| Resource | Location |
|---|---|
| Helm chart | [`../../helm/maas-config/`](../../helm/maas-config/) |
| Helm chart README | [`../../helm/maas-config/README.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/README.md) |
| Values file changelog | [`../../helm/maas-config/environments/CHANGELOG.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/environments/CHANGELOG.md) |
| Model deploy GitOps | [`../maas-model-deploy/`](../maas-model-deploy/) |
| Platform GitOps | [`../maas-gitops-deployment/`](../maas-gitops-deployment/) |
