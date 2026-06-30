# MaaS Model Deploy — GitOps

ArgoCD manifests for deploying LLM models on Red Hat OpenShift AI via the [`maas-model-deploy`](../../helm/maas-model-deploy) Helm chart.

Each environment has one `AppProject` and one `Application` manifest **per model**. For values file conventions, naming rules, and add/remove procedures see [`../../helm/maas-model-deploy/environments/CHANGELOG.md`](../../helm/maas-model-deploy/environments/CHANGELOG.md).

---

## Directory Structure

```
maas-model-deploy/
├── README.md
└── environments/
    ├── dev/
    │   ├── appproject-dev.yaml                  # ArgoCD project + RBAC
    │   └── application.yaml                     # Automated sync
    ├── staging/
    │   ├── appproject-staging.yaml
    │   └── application.yaml                     # Manual sync
    └── prod/
        ├── appproject-prod.yaml                 # Shared by all prod Applications
        ├── application-tiny-llama.yaml          # tiny-llama model
        └── application-gpt-oss-20b.yaml         # gpt-oss-20b model
```

---

## Sync Policy

| Environment | Auto Sync | Prune | Namespace |
|---|---|---|---|
| **Dev** | ✅ Automated | ✅ Yes | `deploy-models-dev` |
| **Staging** | ❌ Manual | ✅ Yes | `deploy-models-staging` |
| **Prod** | ❌ Manual | ❌ No | `deploy-models` |

---

## Multi-Model Design (Production)

One `AppProject` is shared; each model has its own `Application` pointing to its own values file:

```
appproject-prod.yaml
    ├── application-tiny-llama.yaml   →  values.yaml + environments/prod/values-tiny-llama.yaml
    └── application-gpt-oss-20b.yaml  →  values.yaml + environments/prod/values-gpt-oss-20b.yaml
```

Shared resources (Namespace, connection Secret, ServiceAccount, `storage-config`) are created by whichever Application syncs first. All carry `helm.sh/resource-policy: keep`. Both Applications include `ignoreDifferences` rules that suppress `ServerSideApply` label drift on those shared resources — **do not remove that block when adding a new Application**.

---

## Prerequisites

1. **MaaS runtime is healthy:**
   ```bash
   oc get application fusion-maas-runtime-prod -n openshift-gitops
   ```
2. **S3 credentials** are set in the model's env values file or injected via Argo CD Helm parameters.
3. **ArgoCD is running:**
   ```bash
   oc get pods -n openshift-gitops
   ```

---

## Quick Start

### Updating `repoURL` and `targetRevision`

Every Application manifest contains a `source` block that tells ArgoCD where to fetch the Helm chart from. Two fields you are most likely to change before applying any manifest:

| Field | Purpose | Default |
|---|---|---|
| `repoURL` | Git repository that contains the Helm chart | `https://github.com/IBM/storage-fusion.git` |
| `targetRevision` | Branch, tag, or commit SHA ArgoCD tracks | `master` |

#### Files to update

| Environment | File |
|---|---|
| Dev | [`environments/dev/application.yaml`](environments/dev/application.yaml) |
| Staging | [`environments/staging/application.yaml`](environments/staging/application.yaml) |
| Prod – tiny-llama | [`environments/prod/application-tiny-llama.yaml`](environments/prod/application-tiny-llama.yaml) |
| Prod – gpt-oss-20b | [`environments/prod/application-gpt-oss-20b.yaml`](environments/prod/application-gpt-oss-20b.yaml) |

The `source` block looks like this in every file:

```yaml
source:
  repoURL: https://github.com/IBM/storage-fusion.git   # change this
  targetRevision: master                                # change this
  path: AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy
```

**1. Decide the new values before editing any file.**

- `repoURL` — full HTTPS clone URL of your fork or mirror, e.g. `https://github.com/my-org/storage-fusion.git`.
- `targetRevision` — branch name (`feature/my-branch`), semver tag (`v1.2.0`), or a full 40-character commit SHA for a pinned, immutable deploy.

**2. Edit each Application file** that needs the change — update only the two fields, leave `path` and `helm` untouched:

```yaml
source:
  repoURL: https://github.com/my-org/storage-fusion.git
  targetRevision: v1.2.0
  path: AI/quickstarts/model-as-a-service/deploy/helm/maas-model-deploy
```

> **Tip — bulk update across all environments at once:**
> ```bash
> find environments -name '*.yaml' | xargs sed -i \
>   's|repoURL: https://github.com/IBM/storage-fusion.git|repoURL: https://github.com/my-org/storage-fusion.git|g'
>
> find environments -name '*.yaml' | xargs sed -i \
>   's|targetRevision: master|targetRevision: v1.2.0|g'
> ```

**3. Update `sourceRepos` in the AppProject if it is not a wildcard.**

If `appproject-*.yaml` has an explicit allowlist (not `['*']`), add the new `repoURL` there too — ArgoCD will reject syncs from an unlisted repo:

```yaml
# appproject-prod.yaml (excerpt)
spec:
  sourceRepos:
    - https://github.com/IBM/storage-fusion.git           # existing
    - https://github.com/my-org/storage-fusion.git        # add new URL
```

**4. Continue with the environment-specific steps below**, then verify:

```bash
# Inspect the live source fields on any Application
oc get application fusion-maas-model-deploy-prod-tiny-llama \
  -n openshift-gitops \
  -o jsonpath='{.spec.source}{"\n"}'

# Confirm all Applications reach Synced / Healthy
oc get applications.argoproj.io -n openshift-gitops -l component=model-deploy
```

---


### Production

```bash
# Apply the AppProject once (shared by all prod model Applications)
oc apply -f environments/prod/appproject-prod.yaml

# Apply each model's Application
oc apply -f environments/prod/application-tiny-llama.yaml
oc apply -f environments/prod/application-gpt-oss-20b.yaml

# Sync via CLI (or use the ArgoCD UI during an approved change window)
argocd app sync fusion-maas-model-deploy-prod-tiny-llama
argocd app sync fusion-maas-model-deploy-prod-gpt-oss-20b
```

### Development

```bash
oc apply -f environments/dev/appproject-dev.yaml
oc apply -f environments/dev/application.yaml
oc get application fusion-maas-model-deploy-dev -n openshift-gitops -w
```

### Staging

```bash
oc apply -f environments/staging/appproject-staging.yaml
oc apply -f environments/staging/application.yaml
argocd app sync fusion-maas-model-deploy-staging
```

---

## Troubleshooting

### Application OutOfSync on Namespace / Secret / ServiceAccount

`ServerSideApply` stamps instance-specific labels onto shared resources on every sync. Both Application manifests contain `ignoreDifferences` entries (matched by `kind`, not `name`) to suppress this. If you still see OutOfSync, verify `RespectIgnoreDifferences=true` is in `syncOptions` and the `ignoreDifferences` block is intact.

### `s3.accessKeyId is required` / GPU / Pod issues

See the Helm chart [`README.md`](../../helm/maas-model-deploy/README.md#troubleshooting).

### Check Application and model status

```bash
oc get applications.argoproj.io -n openshift-gitops -l component=model-deploy
oc get llminferenceservice,pods -n deploy-models
oc get events -n deploy-models --sort-by='.lastTimestamp'
```

---

## Related

| Resource | Location |
|---|---|
| **Testing guide** | [`TEST_MODELS.md`](TEST_MODELS.md) |
| Helm chart README | [`../../helm/maas-model-deploy/README.md`](../../helm/maas-model-deploy/README.md) |
| Helm chart | [`../../helm/maas-model-deploy/`](../../helm/maas-model-deploy/) |
| Values file conventions | [`../../helm/maas-model-deploy/environments/CHANGELOG.md`](../../helm/maas-model-deploy/environments/CHANGELOG.md) |

