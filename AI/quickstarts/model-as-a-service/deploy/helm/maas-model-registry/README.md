# maas-model-registry Helm Chart

Deploys the Model Registry GitOps reconciler on OpenShift. The reconciler watches a `model-definitions` ConfigMap and automatically registers models from the `models/` directory into the RHOAI Model Registry.

## Chart Location

```
AI/quickstarts/model-as-a-service/deploy/helm/maas-model-registry/
├── Chart.yaml
├── values.yaml                      # Base defaults (all environments)
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

To add further customisation, create an additional file and append it to `valueFiles` in the relevant `application.yaml`. See the [ArgoCD Deployment Guide](../../gitops/model-registry-gitops/argocd/environments/DEPLOYMENT_GUIDE.md) for details.

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
    size: 200Gi               # PVC size for model download cache
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

```yaml
huggingface:
  enabled: false              # set true if you have gated models (Llama, Gemma, Mistral)
  secretName: huggingface-token   # Kubernetes Secret with key `token`
```

To enable:

```bash
# Create the secret first
oc create secret generic huggingface-token \
  --from-literal=token="hf_your_token_here" \
  -n rhoai-model-registries
```

Then in your env `values.yaml` or custom values file:

```yaml
huggingface:
  enabled: true
  secretName: huggingface-token
```

---

### `buildConfig`

Controls the OpenShift `BuildConfig` that builds the reconciler container image from source.

```yaml
buildConfig:
  enabled: true

  git:
    uri: https://github.com/IBM/storage-fusion.git
    ref: master                  # branch / tag / commit
    contextDir: AI/quickstarts/model-as-a-service/deploy/helm/maas-model-registry/reconciler

  gitCredentials:
    enabled: true
    secretName: git-credentials         # Secret with username + password/token

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
| staging | `master` |
| prod | `master` |

---

### `cronJob`

Periodically syncs model definitions from Git into the `model-definitions` ConfigMap.

```yaml
cronJob:
  enabled: true
  schedule: "*/5 * * * *"    # cron expression

  git:
    repo: https://github.com/IBM/storage-fusion.git
    branch: master
    host: github.com

  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"
```

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

Creates a `RoleBinding` that grants the ArgoCD application controller permission to manage resources in the reconciler namespace.

---

### `networkPolicy`

```yaml
networkPolicy:
  enabled: true
```

Creates a `NetworkPolicy` that allows the reconciler to reach the Model Registry service in `rhoai-model-registries`.

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
