# maas-model-registry Helm Chart

Deploys the Model Registry GitOps reconciler on OpenShift. The reconciler watches a `model-definitions` ConfigMap and automatically registers models from the `models/` directory into the RHOAI Model Registry.

## Chart Location

```
AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/
├── Chart.yaml
├── values.yaml                      # Base defaults (all environments)
├── VAULT-SECRET-SETUP.md            # Step-by-step Vault + ESO setup guide
├── environments/
│   ├── dev/values.yaml              # Development overrides
│   ├── staging/values.yaml          # Staging overrides
│   └── prod/values.yaml             # Production overrides
├── reconciler/
│   ├── reconciler.py                # Reconciler application code
│   ├── Dockerfile
│   └── requirements.txt
└── templates/                       # Kubernetes/OpenShift manifests
    ├── namespace.yaml
    ├── serviceaccount.yaml
    ├── rbac.yaml
    ├── deployment.yaml
    ├── buildconfig.yaml
    ├── cronjob.yaml
    ├── argocd-rbac.yaml
    ├── argocd-externalsecret-rbac.yaml   # ArgoCD RBAC for ESO CRs (conditional)
    ├── git-credentials-externalsecret.yaml    # ExternalSecret for git-credentials (conditional)
    ├── huggingface-externalsecret.yaml        # ExternalSecret for huggingface-token (conditional)
    └── networkpolicy.yaml
```

## How Values Are Applied

ArgoCD applies values in layers — later files override earlier ones. Each environment's `application.yaml` declares:

```yaml
helm:
  valueFiles:
    - values.yaml                        # base defaults
    - environments/<env>/values.yaml     # environment overrides
```

To add further customisation, create an additional file and append it to `valueFiles` in the relevant `application.yaml`. See the [ArgoCD Deployment Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/argocd/environments/DEPLOYMENT_GUIDE.md) for details.

---

## Values Reference

### `namespace`

```yaml
namespace: fusion-model-registry-gitops   # base default
```

The Kubernetes namespace where the reconciler Deployment, ServiceAccount, RBAC, and CronJob are created. Each environment override sets this to a unique value (`-dev`, `-staging`, `-prod`).

---

### `modelRegistry`

```yaml
modelRegistry:
  namespace: rhoai-model-registries       # where Model Registry is deployed
  obcName: model-registry-artifacts       # ObjectBucketClaim name for S3 storage
  serviceName: model-registry-http        # Model Registry Service name
  servicePort: 8080                       # Service port (8080 HTTP, 8443 HTTPS)
  secure: false                           # use HTTPS to connect to registry
  exposeHttpPort: true                    # create model-registry-http Service
```

**Environment overrides** (`obcName` is the most commonly changed key):

| Key | Dev | Staging | Prod |
|-----|-----|---------|------|
| `obcName` | `model-registry-artifacts-dev` | `model-registry-artifacts-staging` | `model-registry-artifacts-prod` |
| `serviceName` | `model-registry` | `model-registry` | `model-registry-http` |

---

### `reconciler`

```yaml
reconciler:
  replicaCount: 1

  image:
    repository: image-registry.openshift-image-registry.svc:5000/fusion-model-registry-gitops/model-reconciler
    tag: latest
    pullPolicy: Always

  serviceAccountName: model-reconciler

  resources:
    requests:
      memory: "2Gi"
      cpu: "1000m"
    limits:
      memory: "8Gi"
      cpu: "4000m"

  config:
    reconcileInterval: 300    # seconds between full reconciliation cycles
    sequentialDelay: 30       # seconds between processing each model
    cleanupAfterUpload: true  # delete local model files after S3 upload
    logLevel: INFO            # DEBUG | INFO | WARNING | ERROR

  cache:
    size: 200Gi               # emptyDir size limit for model download cache
```

**Environment overrides:**

| Key | Dev | Staging | Prod |
|-----|-----|---------|------|
| `reconciler.config.reconcileInterval` | `180` | `300` | `600` |
| `reconciler.config.logLevel` | `DEBUG` | `INFO` | `WARNING` |
| `reconciler.resources.limits.memory` | `8Gi` (base) | `8Gi` (base) | `16Gi` |
| `reconciler.resources.requests.cpu` | `1000m` (base) | `1000m` (base) | `2000m` |

---

### `huggingface`

Controls authentication to Hugging Face Hub. Required only for **gated models** (Llama, Mistral, Falcon, Gemma, etc.). Public models work without a token.

The reconciler reads key `token` from the Secret named by `secretName` in **`modelRegistry.namespace`** (`rhoai-model-registries`) — not in the reconciler namespace.

Two credential modes are supported:

#### Manual mode (default)

Create the Secret before deploying, then set `enabled: true`:

```bash
oc create secret generic huggingface-token \
  -n rhoai-model-registries \
  --from-literal=token="hf_xxxxxxxxxxxxxxxxxxxx"
```

```yaml
# environments/prod/values.yaml
huggingface:
  enabled: true
  secretName: huggingface-token   # name the reconciler expects
```

#### ESO mode — Vault manages the token

Set `externalSecret.enabled: true`. Helm creates an `ExternalSecret` CR; ESO
reads the token from Vault and writes the Secret into `modelRegistry.namespace`.

```yaml
# environments/prod/values.yaml
huggingface:
  enabled: true
  secretName: huggingface-token

  externalSecret:
    enabled: true                  # ESO will create huggingface-token
    refreshInterval: 24h
    secretStoreRef:
      name: vault-backend          # must match ClusterSecretStore name
      kind: ClusterSecretStore
    targetName: ""                 # empty = use secretName ("huggingface-token")
    remoteRef:
      key: maas/model-registry-gitops/huggingface
      property: token
```

Pre-populate Vault **before** the first ArgoCD sync:

```bash
vault kv put secret/maas/model-registry-gitops/huggingface \
  token="hf_xxxxxxxxxxxxxxxxxxxx"
```

> **Full walkthrough:** See [VAULT-SECRET-SETUP.md — Scenario B](./VAULT-SECRET-SETUP.md#scenario-b--hugging-face-token-reconciler).

#### Full `huggingface` schema

| Key | Default | Description |
|-----|---------|-------------|
| `huggingface.enabled` | `false` | Enable HF authentication. Set `true` for gated models. |
| `huggingface.secretName` | `huggingface-token` | Name of the Kubernetes Secret (key `token`) in `modelRegistry.namespace`. |
| `huggingface.externalSecret.enabled` | `false` | `true` = ESO creates the Secret from Vault. `false` = create manually. |
| `huggingface.externalSecret.refreshInterval` | `24h` | How often ESO re-reads the token from Vault. |
| `huggingface.externalSecret.secretStoreRef.name` | `vault-backend` | Name of the `ClusterSecretStore` or `SecretStore`. |
| `huggingface.externalSecret.secretStoreRef.kind` | `ClusterSecretStore` | `ClusterSecretStore` (cluster-wide) or `SecretStore` (namespaced). |
| `huggingface.externalSecret.targetName` | `""` | Override the target Secret name. Empty = use `secretName`. Useful for testing. |
| `huggingface.externalSecret.remoteRef.key` | `maas/model-registry-gitops/huggingface` | Vault KV path. |
| `huggingface.externalSecret.remoteRef.property` | `token` | Field name inside the Vault KV secret. |

---

### `buildConfig`

Controls the OpenShift `BuildConfig` that builds the reconciler container image from source.

```yaml
buildConfig:
  enabled: true

  git:
    uri: https://github.com/IBM/storage-fusion.git
    ref: main                    # branch / tag / commit
    contextDir: AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/reconciler

  gitCredentials:
    enabled: true
    secretName: git-credentials  # Secret referenced by BuildConfig + CronJob

  resources:
    limits:
      memory: 2Gi
      cpu: "1"
    requests:
      memory: 1Gi
      cpu: 500m
```

**Environment overrides (`git.ref`):**

| Env | `buildConfig.git.ref` |
|-----|-----------------------|
| dev | `develop` |
| staging | `main` |
| prod | `main` |

#### `buildConfig.gitCredentials` — credential modes

The `git-credentials` Secret is used by two resources:

- **BuildConfig `sourceSecret`** — clones the private repo during image builds.
- **`model-sync` CronJob volume** — mounted at `/git-credentials`; the sync script reads `username` + `token`/`password`/`ssh-privatekey` from there.

Two modes are supported:

##### Manual mode (default)

Create the Secret before deploying:

```bash
# Token / PAT authentication (most common)
oc create secret generic git-credentials \
  -n fusion-model-registry-gitops \
  --from-literal=username="<git-user>" \
  --from-literal=token="<personal-access-token>"

# Or SSH key authentication
oc create secret generic git-credentials \
  -n fusion-model-registry-gitops \
  --from-literal=username="<git-user>" \
  --from-file=ssh-privatekey=~/.ssh/id_rsa
```

No values change required — `gitCredentials.enabled: true` with `externalSecret.enabled: false` (the default) expects the Secret to be pre-created.

##### ESO mode — Vault manages the credentials

Set `externalSecret.enabled: true`. Helm creates an `ExternalSecret` CR; ESO
reads the fields from Vault and writes the `git-credentials` Secret into
`.Values.namespace`.

```yaml
# environments/prod/values.yaml
buildConfig:
  gitCredentials:
    enabled: true
    secretName: git-credentials

    externalSecret:
      enabled: true                  # ESO will create git-credentials
      refreshInterval: 24h
      secretStoreRef:
        name: vault-backend          # must match ClusterSecretStore name
        kind: ClusterSecretStore
      targetName: ""                 # empty = use secretName ("git-credentials")
      remoteRef:
        key: maas/model-registry-gitops/git-credentials
```

Pre-populate Vault **before** the first ArgoCD sync:

```bash
vault kv put secret/maas/model-registry-gitops/git-credentials \
  username="<git-user>" \
  token="<personal-access-token>"
```

The ESO template fetches `username` (required) plus `token`, `password`, and
`ssh-privatekey` with `errorPolicy: Ignore` — missing optional fields are
silently skipped rather than causing an error. Store only the fields your Git
host requires.

> **Full walkthrough:** See [VAULT-SECRET-SETUP.md — Scenario A](./VAULT-SECRET-SETUP.md#scenario-a--git-credentials-buildconfig--cronjob).

#### Full `buildConfig.gitCredentials.externalSecret` schema

| Key | Default | Description |
|-----|---------|-------------|
| `externalSecret.enabled` | `false` | `true` = ESO creates the Secret from Vault. `false` = create manually. |
| `externalSecret.refreshInterval` | `24h` | How often ESO re-reads credentials from Vault. |
| `externalSecret.secretStoreRef.name` | `vault-backend` | Name of the `ClusterSecretStore` or `SecretStore`. |
| `externalSecret.secretStoreRef.kind` | `ClusterSecretStore` | `ClusterSecretStore` (cluster-wide) or `SecretStore` (namespaced). |
| `externalSecret.targetName` | `""` | Override the target Secret name. Empty = use `secretName`. Useful for testing. |
| `externalSecret.remoteRef.key` | `maas/model-registry-gitops/git-credentials` | Vault KV path. |

---

### `cronJob`

Periodically syncs model definitions from Git into the `model-definitions` ConfigMap.

```yaml
cronJob:
  enabled: true
  schedule: "*/5 * * * *"    # cron expression

  git:
    repo: https://github.com/IBM/storage-fusion.git
    branch: main
    host: github.ibm.com

  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"
```

The CronJob mounts the `git-credentials` Secret (named by `buildConfig.gitCredentials.secretName`)
as a volume at `/git-credentials` with `optional: true`. If the Secret does not
exist the pod will start but git clone will fail silently — ensure the Secret
is created (manually or via ESO) before the first scheduled run.

**Environment overrides:**

| Env | `schedule` | `git.branch` |
|-----|-----------|--------------|
| dev | `*/3 * * * *` | `develop` |
| staging | `*/5 * * * *` | `main` |
| prod | `*/10 * * * *` | `main` |

---

### `argocd`

```yaml
argocd:
  enabled: true
  namespace: openshift-gitops
  serviceAccountName: openshift-gitops-argocd-application-controller
```

Creates a `RoleBinding` that grants the ArgoCD application controller `admin`
permission to manage resources in the reconciler namespace.

When either ESO flag is enabled (`buildConfig.gitCredentials.externalSecret.enabled`
or `huggingface.externalSecret.enabled`), the chart additionally renders
`argocd-externalsecret-rbac.yaml`, which creates a least-privilege
`ClusterRole` + namespaced `RoleBinding`(s) at sync-wave 0 scoped to exactly
the namespace(s) where ExternalSecret CRs are created. These are automatically
removed when both ESO flags are false.

---

### `networkPolicy`

```yaml
networkPolicy:
  enabled: true
```

Creates a `NetworkPolicy` that allows the reconciler to reach the Model Registry service in `rhoai-model-registries`.

---

## External Secrets Operator (ESO) Integration

The chart supports ESO for managing two secrets that must not be committed to Git.

### At a glance

| Secret | Namespace | Consumers | ESO flag |
|--------|-----------|-----------|----------|
| `git-credentials` | `.Values.namespace` | BuildConfig `sourceSecret` + `model-sync` CronJob volume | `buildConfig.gitCredentials.externalSecret.enabled` |
| `huggingface-token` | `modelRegistry.namespace` | Reconciler `_load_hf_token()` | `huggingface.externalSecret.enabled` |

### Prerequisites

1. External Secrets Operator installed (via `external-secrets-operator` Helm chart or OLM).
2. A `ClusterSecretStore` named `vault-backend` (or the name set in `secretStoreRef.name`) exists and is `Ready`.
3. Vault paths populated **before** the first ArgoCD sync — see [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md).

### Templates rendered when ESO is enabled

| Template | Renders when |
|----------|-------------|
| `git-credentials-externalsecret.yaml` | `buildConfig.gitCredentials.enabled: true` AND `externalSecret.enabled: true` |
| `huggingface-externalsecret.yaml` | `huggingface.enabled: true` AND `externalSecret.enabled: true` |
| `argocd-externalsecret-rbac.yaml` | Either (or both) of the above ESO flags is `true` |

### Sync-wave order

```
Wave 0  ClusterRole + RoleBinding(s)    ArgoCD RBAC — must exist before ESO CRs
Wave 1  ExternalSecret CRs              ESO resolves Secrets from Vault
Wave 1  BuildConfig / CronJob / Deployment  workloads that consume the Secrets
```

### Testing without touching live secrets

Use `targetName` to write ESO output to a safe test name:

```yaml
buildConfig:
  gitCredentials:
    externalSecret:
      enabled: true
      targetName: git-credentials-eso-test

huggingface:
  externalSecret:
    enabled: true
    targetName: huggingface-token-eso-test
```

Clean up after testing:

```bash
oc delete externalsecret git-credentials-eso-test   -n fusion-model-registry-gitops
oc delete externalsecret huggingface-token-eso-test -n rhoai-model-registries
```

---

## Common Customisations

### Change reconciliation frequency

```yaml
# environments/prod/values.yaml
reconciler:
  config:
    reconcileInterval: 300   # every 5 minutes instead of 10
cronJob:
  schedule: "*/5 * * * *"
```

### Increase resources for large models

```yaml
reconciler:
  resources:
    requests:
      memory: "8Gi"
      cpu: "4000m"
    limits:
      memory: "32Gi"
      cpu: "8000m"
  cache:
    size: 500Gi
```

### Enable debug logging temporarily

```yaml
# environments/prod/values-debug.yaml  (add to valueFiles, revert after debugging)
reconciler:
  config:
    logLevel: DEBUG
    reconcileInterval: 60
```

### Use a different OBC / bucket

```yaml
modelRegistry:
  obcName: my-custom-obc-name
```

---

## Environment Variables Set by Helm

These are passed directly to the reconciler container by the `deployment.yaml` template:

| Variable | Source | Description |
|----------|--------|-------------|
| `NAMESPACE` | `namespace` | Namespace the reconciler runs in |
| `TARGET_NAMESPACE` | `modelRegistry.namespace` | Namespace of the Model Registry |
| `OBC_NAME` | `modelRegistry.obcName` | ObjectBucketClaim for S3 storage |
| `REGISTRY_HOST` | auto-generated from `modelRegistry.*` | Full URL of the Model Registry API |
| `RECONCILE_INTERVAL` | `reconciler.config.reconcileInterval` | Seconds between reconciliation cycles |
| `SEQUENTIAL_DELAY` | `reconciler.config.sequentialDelay` | Seconds between processing models |
| `CLEANUP_AFTER_UPLOAD` | `reconciler.config.cleanupAfterUpload` | Delete local files after S3 upload |
| `LOG_LEVEL` | `reconciler.config.logLevel` | Logging verbosity |

---

## Troubleshooting

### Check what values Helm resolved

```bash
# Render templates locally without deploying
helm template fusion-model-registry-gitops . \
  -f values.yaml \
  -f environments/prod/values.yaml

# Confirm which ESO templates render
helm template fusion-model-registry-gitops . \
  -f values.yaml \
  -f environments/prod/values.yaml \
  --show-only templates/git-credentials-externalsecret.yaml \
  --show-only templates/huggingface-externalsecret.yaml \
  --show-only templates/argocd-externalsecret-rbac.yaml

# Check environment variables on the running deployment
oc set env deployment/model-reconciler --list \
  -n fusion-model-registry-gitops-prod
```

### Verify BuildConfig and image

```bash
# Check build status
oc get builds -n fusion-model-registry-gitops-prod

# View build logs
oc logs -n fusion-model-registry-gitops-prod bc/model-reconciler -f

# Trigger a new build manually
oc start-build model-reconciler -n fusion-model-registry-gitops-prod
```

### Check OBC exists

```bash
oc get objectbucketclaim -n rhoai-model-registries
```

### Check Model Registry service

```bash
oc get svc -n rhoai-model-registries | grep model-registry
```

### Check ESO secret status

```bash
# git-credentials ExternalSecret (in reconciler namespace)
oc get externalsecret git-credentials \
  -n fusion-model-registry-gitops

# huggingface-token ExternalSecret (in modelRegistry namespace)
oc get externalsecret huggingface-token \
  -n rhoai-model-registries

# Inspect conditions on a failing ExternalSecret
oc describe externalsecret git-credentials \
  -n fusion-model-registry-gitops
```

### Force immediate ESO refresh without waiting for the interval

```bash
oc annotate externalsecret git-credentials \
  -n fusion-model-registry-gitops \
  force-sync=$(date +%s) --overwrite

oc annotate externalsecret huggingface-token \
  -n rhoai-model-registries \
  force-sync=$(date +%s) --overwrite
```

### Reconciler logs `No Hugging Face token found`

The reconciler reads the token at pod startup. Restart the Deployment after
ESO has resolved the Secret:

```bash
oc rollout restart deployment/model-reconciler \
  -n fusion-model-registry-gitops-prod
```

### CronJob git clone fails silently

The CronJob volume mounts `git-credentials` with `optional: true` — the pod
starts even if the Secret is absent. Verify the Secret exists:

```bash
oc get secret git-credentials -n fusion-model-registry-gitops-prod
```

If missing, check the ExternalSecret status above. Once the Secret is present,
trigger a manual CronJob run to confirm:

```bash
oc create job --from=cronjob/model-sync manual-test-$(date +%s) \
  -n fusion-model-registry-gitops-prod
```

---

## Related Documents

- [VAULT-SECRET-SETUP.md](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) — step-by-step guide for populating Vault and enabling ESO for this chart
- [VAULT-SECRET-SETUP.md (maas-runtime)](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-runtime/VAULT-SECRET-SETUP.md) — equivalent guide for object storage + database secrets
- [VAULT-SECRET-SETUP.md (maas-platform)](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — equivalent guide for maas-platform secrets
- [ArgoCD Deployment Guide](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/model-registry-gitops/argocd/environments/DEPLOYMENT_GUIDE.md) — how to create and manage ArgoCD Applications for this chart
