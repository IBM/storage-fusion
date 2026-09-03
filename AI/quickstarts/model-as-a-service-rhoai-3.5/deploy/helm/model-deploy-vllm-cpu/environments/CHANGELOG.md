# Changelog — model-deploy-vllm-cpu Environments

All notable changes to CPU model environment values are documented here.

## Configuration Structure

```
model-deploy-vllm-cpu/
├── values.yaml                                        # Base defaults (required)
└── environments/
    ├── dev/
    │   ├── values-qwen2-5-1-5b-cpu.yaml              # Qwen2.5-1.5B dev overrides
    │   ├── values-qwen2-5-coder-1-5b-cpu.yaml        # Qwen2.5-Coder-1.5B dev overrides
    │   └── values-smollm2-1-7b-cpu.yaml              # SmolLM2-1.7B dev overrides
    ├── staging/
    │   ├── values-qwen2-5-1-5b-cpu.yaml              # Qwen2.5-1.5B staging overrides
    │   ├── values-qwen2-5-coder-1-5b-cpu.yaml        # Qwen2.5-Coder-1.5B staging overrides
    │   └── values-smollm2-1-7b-cpu.yaml              # SmolLM2-1.7B staging overrides
    └── prod/
        ├── values-qwen2-5-1-5b-cpu.yaml              # Qwen2.5-1.5B prod overrides
        ├── values-qwen2-5-coder-1-5b-cpu.yaml        # Qwen2.5-Coder-1.5B prod overrides
        └── values-smollm2-1-7b-cpu.yaml              # SmolLM2-1.7B prod overrides
```

**How it works:**
- Base `values.yaml` contains defaults shared across all models and environments
- Each environment file overrides only the fields that differ from the base:
  `model.name`, `model.displayName`, `s3.*`, `resources`, `servingRuntime.image`,
  `servingRuntime.extraEnv`, `externalAccess`, `labels`
- ArgoCD merges base + environment values at sync time:
  `helm.valueFiles: [values.yaml, environments/<env>/values-<model>.yaml]`
- **One file per model per environment** — never share a values file across models

---

## How to Update Values

### Change a setting for all models in all environments
Edit `../values.yaml`.

### Change a setting for all models in one environment
Edit every `environments/<env>/values-*.yaml` file for that environment.

### Change a setting for one model in one environment
Edit `environments/<env>/values-<model-name>.yaml` directly.

### Add a new CPU model
1. Copy the closest prod reference file and rename:
   ```bash
   cp environments/prod/values-qwen2-5-1-5b-cpu.yaml \
      environments/prod/values-<model-name>.yaml
   ```
2. Update `model.name`, `model.displayName`, `s3.modelPath`, and `resources`.
3. Repeat for `dev/` and `staging/` environments.
4. Create a matching ArgoCD Application manifest in
   `../../gitops/model-deploy-vllm-cpu/environments/<env>/application-<model-name>.yaml`.
5. Record the change in this file under a new `[Unreleased]` entry.

### Rotate S3 credentials

**Manual mode:** update `s3.accessKeyId` and `s3.secretAccessKey` in the affected environment values file and re-sync the ArgoCD Application.

**ESO mode (production default):** update the Vault secret at the path referenced by `s3.externalSecret.remoteRef.key` — all prod models share `maas/model-registry/object-storage`:

```bash
vault kv put secret/maas/model-registry/object-storage \
  access_key_id="<new-key>" \
  secret_access_key="<new-secret>" \
  endpoint="https://s3.openshift-storage.svc:443" \
  region="us-south" \
  bucket="<bucket-name>"
```

ESO picks up the change automatically at the next `refreshInterval` (default `1h`). To force an immediate refresh:

```bash
oc annotate externalsecret deploy-models-cpu-connection \
  force-sync=$(date +%s) --overwrite -n deploy-models-cpu
oc annotate externalsecret storage-config \
  force-sync=$(date +%s) --overwrite -n deploy-models-cpu
```

---

## Version History

### v2 (August 2026) — CURRENT
**Date:** 2026-08-26

#### Added
- `prod/values-qwen2-5-coder-1-5b-cpu.yaml` — production values for
  `Qwen2.5-Coder-1.5B-Instruct`. S3 `bucket`, `accessKeyId`, and `secretAccessKey`
  populated to match the shared ODF prod bucket.
- `prod/values-smollm2-1-7b-cpu.yaml` — production values for `SmolLM2-1.7B-Instruct`.
  S3 credentials aligned with prod bucket.

#### Changed
- `prod/values-qwen2-5-1-5b-cpu.yaml` — `s3.region` updated from `us-east-1` to
  `us-south`; `s3.bucket`, `s3.accessKeyId`, `s3.secretAccessKey` populated with
  prod ODF credentials.

#### Fixed
- `templates/external-access-sa.yaml` — added `ClusterRoleBinding` →
  `system:auth-delegator` and namespace-scoped `Role` + `RoleBinding` per bearer-token
  SA when `externalAccess.enabled: true`. Required by `kube-rbac-proxy` (injected by
  RHOAI) for TokenReview and SubjectAccessReview. Without these bindings, all external
  requests returned `403 Forbidden`.

---

### v1 (June 2026) — BASELINE
**Date:** 2026-06-01

#### Added
- `dev/values-qwen2-5-1-5b-cpu.yaml` — dev environment, namespace
  `deploy-models-cpu-dev`, resources 8 CPU / 16 GiB, `VLLM_CPU_KVCACHE_SPACE: 6`.
- `dev/values-qwen2-5-coder-1-5b-cpu.yaml` — dev values for Qwen2.5-Coder-1.5B.
- `dev/values-smollm2-1-7b-cpu.yaml` — dev values for SmolLM2-1.7B.
- `staging/values-qwen2-5-1-5b-cpu.yaml` — staging environment, namespace
  `deploy-models-cpu-staging`, resources 12 CPU / 24 GiB, `VLLM_CPU_KVCACHE_SPACE: 10`.
- `staging/values-qwen2-5-coder-1-5b-cpu.yaml` — staging values for Qwen2.5-Coder-1.5B.
- `staging/values-smollm2-1-7b-cpu.yaml` — staging values for SmolLM2-1.7B.
- `prod/values-qwen2-5-1-5b-cpu.yaml` — production reference file for
  `Qwen2.5-1.5B-Instruct`, namespace `deploy-models-cpu`, resources 4 CPU / 12 GiB,
  `VLLM_CPU_KVCACHE_SPACE: 6`. Used as the copy-rename template for new prod models.

---

## Rollback

```bash
# Roll back a single environment file to its previous committed state
git checkout HEAD~1 -- environments/prod/values-qwen2-5-1-5b-cpu.yaml

# Roll back all prod values files to a specific commit
git checkout <commit-sha> -- environments/prod/

# Roll back all environments to a tagged release
git checkout v1 -- environments/
```

To redeploy after rollback, re-sync the affected ArgoCD Application:
```bash
argocd app sync fusion-vllm-cpu-model-deploy-prod-qwen2-5-1-5b
```
