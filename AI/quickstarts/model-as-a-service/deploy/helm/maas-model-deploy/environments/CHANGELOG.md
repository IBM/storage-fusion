# Changelog - MaaS Model Deploy

Tracks file-naming conventions, add/remove procedures, and version history for environment values files.
For key definitions, update guidance, and troubleshooting see [`../README.md`](../README.md).

---

## Naming Convention

| Environment | File pattern | Notes |
|---|---|---|
| `dev/`, `staging/` | `values.yaml` | One file — single model per environment |
| `prod/` | `values-<model-name>.yaml` | One file per model |

Current prod files:

| File | Model |
|---|---|
| `prod/values-tiny-llama.yaml` | `tiny-llama-test` |
| `prod/values-gpt-oss-20b.yaml` | `gpt-oss-20b` |

Each prod values file is referenced by its own ArgoCD Application in
[`gitops/maas-model-deploy/environments/prod/`](../../../gitops/maas-model-deploy/environments/prod/)
via `spec.source.helm.valueFiles`.

---

## GPU Assignments (quick reference)

| Model | GPU resource set in env values file |
|---|---|
| `tiny-llama-test` | `nvidia.com/gpu: "1"` |
| `gpt-oss-20b` | `nvidia.com/gpu: "1"` |

For the rule on why GPU keys must not be in the base `values.yaml` and how to change them,
see [`../README.md` › Change the GPU resource](../README.md#change-the-gpu-resource).

---

## Add a New Model to Production

1. Copy an existing prod values file:
   ```bash
   cp prod/values-tiny-llama.yaml prod/values-<new-model>.yaml
   ```
2. Update `model.name`, `model.displayName`, `s3.modelPath`, `resources` (GPU), and `inference.replicas`.
3. Create a matching ArgoCD Application:
   ```
   gitops/maas-model-deploy/environments/prod/application-<new-model>.yaml
   ```
   Copy an existing Application, set a unique `metadata.name`, update `helm.valueFiles`.
   **Keep the `ignoreDifferences` block unchanged.**
4. Commit both files together.

## Remove a Model from Production

1. Set `inference.replicas: 0`, sync, wait for the pod to terminate.
2. Delete the ArgoCD Application:
   ```bash
   oc delete application fusion-maas-model-deploy-prod-<model-name> -n openshift-gitops
   ```
3. Delete the values file from this directory.
4. Manually remove the `LLMInferenceService` (prune is disabled in prod):
   ```bash
   oc delete llminferenceservice <model-name> -n deploy-models
   ```

---

## Version History

### v2 (June 2026) - CURRENT
**Date:** 2026-06-30

#### Changed
- Production environment split into per-model values files (`values-tiny-llama.yaml`, `values-gpt-oss-20b.yaml`).
- Removed `nvidia.com/gpu` from the base `values.yaml` to prevent Helm shallow-merge from
  combining GPU resource keys across layered values files.
- GPU resource keys are now set exclusively in each model's environment values file.

#### Added
- `values-gpt-oss-20b.yaml` — production values for the `gpt-oss-20b` model
  (`modelPath: gpt-oss-20b-hf/1.0.0`, `nvidia.com/gpu: "1"`).
- `values-tiny-llama.yaml` — production values for the `tiny-llama-test` model
  (`modelPath: tiny-llama-test/1.0.0`, `nvidia.com/gpu: "1"`).

#### Removed
- `environments/prod/values.yaml` — replaced by the per-model files above.

---

### v1 (June 2026) - BASELINE
**Date:** 2026-06-24

#### Initial Release
- Environment-specific values structure (dev / staging / prod).
- Single `environments/prod/values.yaml` deploying the `tiny-llama-test` model.
- S3 connection to internal ODF/NooBaa (`s3.openshift-storage.svc:443`).
- GPU resource `nvidia.com/gpu: "1"` for all environments.

---

## Rollback

```bash
# Rollback a single model's values to the previous commit
git checkout HEAD~1 -- environments/prod/values-tiny-llama.yaml

# Rollback both prod values files
git checkout HEAD~1 -- environments/prod/
```
