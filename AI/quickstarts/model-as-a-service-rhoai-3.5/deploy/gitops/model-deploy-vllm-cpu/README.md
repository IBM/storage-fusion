# vLLM CPU Model Deploy — GitOps

ArgoCD manifests for deploying CPU-based LLM models on Red Hat OpenShift AI via the [`model-deploy-vllm-cpu`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/model-deploy-vllm-cpu) Helm chart.

Each environment has one `AppProject` and one `Application` manifest **per model**. Models run on CPU (x86) using the vLLM CPU `ServingRuntime` for KServe. For chart internals, values reference, and `helm install` instructions see [`../../helm/model-deploy-vllm-cpu/README.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/model-deploy-vllm-cpu/README.md).

---

## Directory Structure

```
model-deploy-vllm-cpu/
├── README.md
└── environments/
    ├── dev/
    │   ├── appproject-dev.yaml                          # ArgoCD project + RBAC (sync-wave -10)
    │   ├── application-qwen2-5-1-5b-cpu.yaml            # Automated sync — prune + selfHeal (wave 200)
    │   ├── application-qwen2-5-coder-1-5b-cpu.yaml      # Automated sync — prune + selfHeal (wave 200)
    │   └── application-smollm2-1-7b-cpu.yaml            # Automated sync — prune + selfHeal (wave 200)
    ├── staging/
    │   ├── appproject-staging.yaml
    │   ├── application-qwen2-5-1-5b-cpu.yaml            # Automated sync — selfHeal only, no prune (wave 200)
    │   ├── application-qwen2-5-coder-1-5b-cpu.yaml      # Automated sync — selfHeal only, no prune (wave 200)
    │   └── application-smollm2-1-7b-cpu.yaml            # Automated sync — selfHeal only, no prune (wave 200)
    └── prod/
        ├── appproject-prod.yaml                         # Shared by all prod Applications
        ├── application-qwen2-5-1-5b-cpu.yaml            # Manual sync only, no prune (wave 200)
        ├── application-qwen2-5-coder-1-5b-cpu.yaml      # Manual sync only, no prune (wave 200)
        └── application-smollm2-1-7b-cpu.yaml            # Manual sync only, no prune (wave 200)
```

---

## Deployed Models

| Model | Display Name | ArgoCD Application (Prod) | S3 Path | Namespace |
|---|---|---|---|---|
| `qwen2-5-1-5b-cpu` | Qwen2.5-1.5B Instruct (CPU) | `fusion-vllm-cpu-model-deploy-prod-qwen2-5-1-5b` | `qwen2-5-1-5b-instruct-hf/1.0.0` | `deploy-models-cpu` |
| `qwen2-5-coder-1-5b-cpu` | Qwen2.5-Coder-1.5B Instruct (CPU) | `fusion-vllm-cpu-model-deploy-prod-qwen2-5-coder-1-5b` | `qwen2-5-coder-1-5b-instruct-hf/1.0.0` | `deploy-models-cpu` |
| `smollm2-1-7b-cpu` | SmolLM2-1.7B Instruct (CPU) | `fusion-vllm-cpu-model-deploy-prod-smollm2-1-7b` | `smollm2-1-7b-instruct-hf/1.0.0` | `deploy-models-cpu` |

> S3 paths use **hyphens**, not dots (e.g. `qwen2-5-1-5b-instruct-hf/1.0.0`). For resource sizing, `VLLM_CPU_KVCACHE_SPACE` tuning, and ESO/Vault credential setup, see the [Helm chart README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/model-deploy-vllm-cpu/README.md).

---

## Sync Policy

| Environment | App name pattern | Auto Sync | Prune | SelfHeal | Target namespace |
|---|---|---|---|---|---|
| **Dev** | `fusion-vllm-cpu-model-deploy-dev` | ✅ Automated | ✅ Yes | ✅ Yes | `deploy-models-cpu-dev` |
| **Staging** | `fusion-vllm-cpu-model-deploy-staging` | ✅ Automated | ❌ No | ✅ Yes | `deploy-models-cpu-staging` |
| **Prod** | `fusion-vllm-cpu-model-deploy-prod-<model>` | ❌ Manual | ❌ No | — | `deploy-models-cpu` |

> **Note:** Dev and staging Application names do not carry a per-model suffix. Prod Applications include the model name (e.g. `-qwen2-5-1-5b`) and carry a `model:` label, enabling `oc get` filtering with `-l model=<name>`.

Additional `syncOptions` differences by environment:

| Option | Dev | Staging | Prod |
|---|---|---|---|
| `CreateNamespace=true` | ✅ | ✅ | ✅ |
| `ServerSideApply=true` | ✅ | ✅ | ✅ |
| `RespectIgnoreDifferences=true` | ✅ | ✅ | ✅ |
| `PrunePropagationPolicy=foreground` | ❌ | ❌ | ✅ |
| `ignoreDifferences` on `InferenceService`/`ServingRuntime` status | ✅ active | ✅ active | commented out |

---

## Multi-Model Design

One `AppProject` is shared per environment; each model has its own `Application` pointing to its own values file in the Helm chart:

```
appproject-prod.yaml
    ├── application-qwen2-5-1-5b-cpu.yaml     →  values.yaml + environments/prod/values-qwen2-5-1-5b-cpu.yaml
    ├── application-qwen2-5-coder-1-5b-cpu.yaml →  values.yaml + environments/prod/values-qwen2-5-coder-1-5b-cpu.yaml
    └── application-smollm2-1-7b-cpu.yaml     →  values.yaml + environments/prod/values-smollm2-1-7b-cpu.yaml
```

**Shared resources** (Namespace, connection Secret, ServiceAccount, `storage-config`, `argocd-manager-vllm-cpu` ClusterRole/RoleBinding) are created by whichever Application syncs first. All carry `helm.sh/resource-policy: keep` so subsequent Applications and future prune operations leave them intact.

**Per-model resources** (ServingRuntime, InferenceService, bearer-token SA, token Secret, `ClusterRoleBinding → system:auth-delegator`, inferenceservice-viewer Role/RoleBinding, OpenShift Route) are owned by each model's Application exclusively.

Every Application includes an `ignoreDifferences` block that suppresses `ServerSideApply` label drift on shared resources — **do not remove or trim this block when adding a new Application**.

---

## Prerequisites

### 1. RHOAI and Model Registry

Complete **Steps 1–4** of the [MaaS Quickstart README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/README.md) to clone the repository, configure storage credentials, install RHOAI, and register models in the Model Registry before proceeding.

> **Already installed?** If `oc get datasciencecluster default-dsc` shows `Ready` and your models are registered, skip directly to [Quick Start](#quick-start) below.

### 2. ArgoCD is running

```bash
oc get pods -n openshift-gitops
```

---

## Quick Start

> All commands below assume you are in the `deploy/gitops/model-deploy-vllm-cpu/` directory:
> ```bash
> cd storage-fusion/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-deploy-vllm-cpu
> ```

### Step 1: Update `repoURL` and `targetRevision`

Every Application manifest has a `source` block pointing to the Helm chart. Update these two fields to match your fork before applying anything:

| Field | Purpose | Default |
|---|---|---|
| `repoURL` | Git repository containing the Helm chart | `https://github.com/IBM/storage-fusion.git` |
| `targetRevision` | Branch, tag, or commit SHA ArgoCD tracks | `master` (all environments) |

**Bulk update across all environments at once** (run from the `model-deploy-vllm-cpu/` directory):

```bash
# Replace repoURL with your fork
find environments -name '*.yaml' | xargs sed -i '' \
  's|repoURL: https://github.com/IBM/storage-fusion.git|repoURL: https://github.com/<your-org>/storage-fusion.git|g'

# Replace targetRevision with your branch
find environments -name '*.yaml' | xargs sed -i '' \
  's|targetRevision: master|targetRevision: <your-branch>|g'
```

> If `appproject-*.yaml` has an explicit `sourceRepos` list (not a wildcard `*`), add your new `repoURL` there too — ArgoCD rejects syncs from unlisted repos.

---

### Step 2: Deploy

Run the commands for your target environment. The AppProject is shared across all models and only needs to be applied once.

#### Production

Production uses **manual sync** — every deployment is explicit and auditable.

```bash
# 1. Apply the shared AppProject (once for all prod models)
oc apply -f environments/prod/appproject-prod.yaml

# 2. Verify the AppProject was created
oc get appproject fusion-vllm-cpu-model-deploy-prod -n openshift-gitops

# 3. Register all three model Applications with ArgoCD
oc apply -f environments/prod/application-qwen2-5-1-5b-cpu.yaml
oc apply -f environments/prod/application-qwen2-5-coder-1-5b-cpu.yaml
oc apply -f environments/prod/application-smollm2-1-7b-cpu.yaml

# 4. Verify all three are registered (expect Synced + Healthy after sync)
oc get applications.argoproj.io -n openshift-gitops \
  -l component=model-deploy-cpu,environment=prod \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# 5. Sync — use the ArgoCD UI during an approved change window, or via CLI:
argocd app sync fusion-vllm-cpu-model-deploy-prod-qwen2-5-1-5b
argocd app sync fusion-vllm-cpu-model-deploy-prod-qwen2-5-coder-1-5b
argocd app sync fusion-vllm-cpu-model-deploy-prod-smollm2-1-7b

# 6. Verify model workloads
oc get inferenceservice,servingruntime -n deploy-models-cpu
```

#### Development

Dev Applications **auto-sync** with prune and self-heal enabled. Resources are created automatically once the Applications are registered.

```bash
oc apply -f environments/dev/appproject-dev.yaml
oc apply -f environments/dev/application-qwen2-5-1-5b-cpu.yaml
oc apply -f environments/dev/application-qwen2-5-coder-1-5b-cpu.yaml
oc apply -f environments/dev/application-smollm2-1-7b-cpu.yaml

# Watch convergence — dev syncs automatically within seconds
oc get applications.argoproj.io -n openshift-gitops \
  -l component=model-deploy-cpu,environment=dev -w

# Verify model workloads
oc get inferenceservice,servingruntime -n deploy-models-cpu-dev
```

#### Staging

Staging Applications **auto-sync with self-heal** but do **not** prune on delete.

```bash
oc apply -f environments/staging/appproject-staging.yaml
oc apply -f environments/staging/application-qwen2-5-1-5b-cpu.yaml
oc apply -f environments/staging/application-qwen2-5-coder-1-5b-cpu.yaml
oc apply -f environments/staging/application-smollm2-1-7b-cpu.yaml

# Watch convergence
oc get applications.argoproj.io -n openshift-gitops \
  -l component=model-deploy-cpu,environment=staging -w

# Verify model workloads
oc get inferenceservice,servingruntime -n deploy-models-cpu-staging
```

---

## Troubleshooting

### ExternalSecrets `OutOfSync` / `Missing` after sync

The most common cause is the `InferenceService` admission webhook blocking the sync before the `ExternalSecret` CRs are applied. Check the per-resource sync status in the ArgoCD UI or via CLI:

```bash
oc get applications.argoproj.io fusion-vllm-cpu-model-deploy-prod-qwen2-5-1-5b \
  -n openshift-gitops \
  -o jsonpath='{.status.operationState.message}'
```

If the error is `admission webhook "connection-isvc.opendatahub.io" denied the request`, the `InferenceService` template is missing `argocd.argoproj.io/sync-wave: "2"`. See the [Helm chart README](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/model-deploy-vllm-cpu/README.md#externalsecret-syncfailed--admission-webhook-denied-inferenceservice) for the fix.

### ExternalSecret `SyncFailed` — validation error on `conversionStrategy`

If the error is `spec.dataFrom[0].extract.conversionStrategy: Unsupported value: "None"`, the live `ExternalSecret` object was created by an older chart version with invalid field values. ArgoCD patches these out on the next sync with `ServerSideApply=true`. If the patch does not apply automatically, force-refresh:

```bash
oc annotate externalsecret deploy-models-cpu-connection \
  force-sync=$(date +%s) --overwrite -n deploy-models-cpu
oc annotate externalsecret storage-config \
  force-sync=$(date +%s) --overwrite -n deploy-models-cpu
```

### Multiple Applications `OutOfSync` on shared ExternalSecrets

When all three prod Applications target the same namespace, `ServerSideApply` stamps model-specific labels onto the shared `deploy-models-cpu-connection` and `storage-config` ExternalSecrets. Every Application that did not sync last sees label drift and reports `OutOfSync`.

This is suppressed by the `ignoreDifferences` entries for `group: external-secrets.io / kind: ExternalSecret` in each Application manifest. Verify they are present:

```bash
oc get applications.argoproj.io fusion-vllm-cpu-model-deploy-prod-qwen2-5-1-5b \
  -n openshift-gitops \
  -o jsonpath='{.spec.ignoreDifferences}' | python3 -m json.tool | grep -A3 'ExternalSecret'
```

### S3 credentials — Vault path and required keys

All three prod models read S3 credentials from a single shared Vault path:

```
secret/maas/model-registry/object-storage
```

All five keys must be present:

```bash
# Verify
vault kv get secret/maas/model-registry/object-storage
# Must show: access_key_id, secret_access_key, endpoint, region, bucket

# Write / rotate
vault kv put secret/maas/model-registry/object-storage \
  access_key_id="<key>" \
  secret_access_key="<secret>" \
  endpoint="https://s3.openshift-storage.svc:443" \
  region="us-south" \
  bucket="<bucket-name>"
```

ESO refreshes automatically at the configured `refreshInterval` (default `1h`). Check current status:

```bash
oc get externalsecret -n deploy-models-cpu \
  -o custom-columns='NAME:.metadata.name,READY:.status.conditions[0].status,REASON:.status.conditions[0].reason'
```

### External route returns `403 Forbidden` with a valid SA token

The bearer-token SA is missing the RBAC bindings required by `kube-rbac-proxy`. These are created automatically by `templates/external-access-sa.yaml` when `externalAccess.enabled: true`:
- `ClusterRoleBinding → system:auth-delegator` (TokenReview)
- Namespace-scoped `Role` + `RoleBinding` for `get inferenceservices/<model>` (SAR check)

Re-sync the Application to create the missing bindings.

### Application OutOfSync on Namespace / Secret / ServiceAccount / ClusterRole

`ServerSideApply` stamps instance-specific labels onto shared resources on every sync. Every Application manifest contains `ignoreDifferences` entries to suppress this. Verify `RespectIgnoreDifferences=true` is in `syncOptions`:

```bash
oc get applications.argoproj.io fusion-vllm-cpu-model-deploy-prod-qwen2-5-1-5b \
  -n openshift-gitops \
  -o jsonpath='{.spec.syncPolicy.syncOptions}'
```

### Pod-level issues (`OOMKilled`, `ImagePullBackOff`, `Pending`, `Init`, `ServingRuntime not found`)

These originate in Helm chart rendering or pod scheduling, not the ArgoCD manifests. See the [Helm chart README troubleshooting section](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/model-deploy-vllm-cpu/README.md#troubleshooting) for root causes and fixes.

### Check Application and model status

```bash
# All environments
oc get applications.argoproj.io -n openshift-gitops -l component=model-deploy-cpu

# One environment
oc get applications.argoproj.io -n openshift-gitops \
  -l component=model-deploy-cpu,environment=prod \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'

# Model workloads (prod)
oc get inferenceservice,servingruntime,pods -n deploy-models-cpu
oc get events -n deploy-models-cpu --sort-by='.lastTimestamp' | tail -20
```

---

## Related

| Resource | Location |
|---|---|
| Helm chart README | [`../../helm/model-deploy-vllm-cpu/README.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/model-deploy-vllm-cpu/README.md) |
| Helm chart values reference | [`../../helm/model-deploy-vllm-cpu/VALUES.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/model-deploy-vllm-cpu/VALUES.md) |
| Environment values changelog | [`../../helm/model-deploy-vllm-cpu/environments/CHANGELOG.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/model-deploy-vllm-cpu/environments/CHANGELOG.md) |
| CPU deployment blog | [`../../infoDocs/gitops-cpu-deployment-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/infoDocs/gitops-cpu-deployment-guide.md) |
| CPU vs MaaS capability matrix | [`../../infoDocs/maas-cpu-vs-gpu-capabilities.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/infoDocs/maas-cpu-vs-gpu-capabilities.md) |
| GPU model deploy GitOps | [`../maas-model-deploy/`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy) |
| Platform GitOps | [`../maas-gitops-deployment/`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-gitops-deployment) |
