# maas-runtime Helm Chart

Deploys the core MaaS runtime infrastructure on Red Hat OpenShift AI. The chart provisions the RHOAI Model Registry (CR + backing PostgreSQL + object storage secret) together with the monitoring stack, RBAC, and optional External Secrets Operator (ESO) integration so no credentials are ever committed to Git.

## Chart Location

```
AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-runtime/
├── Chart.yaml
├── values.yaml                          # Base defaults (all environments)
├── environments/
│   ├── dev/values.yaml                  # Development overrides
│   ├── staging/values.yaml              # Staging overrides
│   └── prod/values.yaml                 # Production overrides
└── templates/
    ├── _helpers.tpl                     # Shared template helpers
    ├── namespace.yaml                   # Namespace (optional creation)
    ├── rbac.yaml                        # RBAC for model service account
    ├── modelregistry.yaml               # ModelRegistry CR + Secret + PVC + Service + CronJob
    ├── model-registry-http-service.yaml # Optional HTTP service on port 8080
    ├── model-registry-objectstorage-externalsecret.yaml  # ESO ExternalSecret for object storage
    ├── model-registry-db-externalsecret.yaml             # ESO ExternalSecret for database
    └── argocd-externalsecret-rbac.yaml  # ClusterRole + RoleBinding for ArgoCD to manage ExternalSecrets
```

## How Values Are Applied

ArgoCD applies values in layers — later files override earlier ones. Each environment's `application.yaml` declares:

```yaml
helm:
  valueFiles:
    - values.yaml                        # base defaults
    - environments/<env>/values.yaml     # environment overrides
```

To add further customisation, create an additional values file and append it to `valueFiles` in the relevant `application.yaml`.

---

## Values Reference

### `global`

```yaml
global:
  wildcardDomain: apps.cluster.example.com   # OpenShift cluster wildcard domain
  wildcardCertName: ""                        # TLS cert secret name (empty = self-signed)
  modelsNamespace: maas-models                # Namespace for model deployments
  toolsImage: image-registry.openshift-image-registry.svc:5000/openshift/tools:latest
```

`wildcardDomain` is used to auto-generate Route hostnames. `toolsImage` must contain `oc`, `kubectl`, and `bash` — it is used by the object storage hook Job.

**Environment overrides:**

| Key | Dev | Staging | Prod |
|-----|-----|---------|------|
| `modelsNamespace` | `maas-dev` | `maas-staging` | `maas-prod` |

---

### `monitoring`

```yaml
monitoring:
  enabled: true

  clusterMonitoring:
    enabled: true           # enables OpenShift user-workload monitoring

  grafana:
    enabled: true
    namespace: grafana
    selectors:
      app: grafana           # labels used to match the Grafana CR
    consoleLink:
      enabled: true
      displayName: "MaaS Metrics Dashboard"
      section: "Observability"
    dashboards:
      maasOverview:
        enabled: true
      modelMetrics:
        enabled: true
      gpuUtilization:
        enabled: true
```

**Environment overrides:**

| Key | Dev | Staging | Prod |
|-----|-----|---------|------|
| `monitoring.grafana.enabled` | `false` | `true` | `true` |
| `monitoring.grafana.consoleLink.enabled` | `false` | `true` | `true` |

---

### `authentication`

```yaml
authentication:
  keycloak:
    enabled: false          # set true to deploy Keycloak OAuth integration
    namespace: keycloak
    realm:
      name: maas
      displayName: "MaaS Platform"
      admin:
        username: admin
        password: ""        # set via --set or secure method — never commit
      user:
        password: ""        # set via --set — never commit
        count: 5            # creates user1-user5
    removeKubeAdmin: false  # remove kubeadmin after Keycloak setup
    oauth:
      enabled: true
```

Keycloak is disabled by default across all environments. Enable only when OAuth integration is required.

---

### `rbac`

```yaml
rbac:
  enabled: true
  modelServiceAccount:
    name: maas-model-sa
    namespace: maas-models   # must match global.modelsNamespace
```

Creates a ServiceAccount used by model inference pods. `namespace` should always match `global.modelsNamespace` for the target environment.

**Environment overrides (`modelServiceAccount.namespace`):**

| Dev | Staging | Prod |
|-----|---------|------|
| `maas-dev` | `maas-staging` | `maas-prod` |

---

### `modelRegistry`

Top-level switch for all Model Registry resources.

```yaml
modelRegistry:
  enabled: true
  namespace: rhoai-model-registries   # pre-existing namespace (created by DataScienceCluster)
  createNamespace: false              # set true only if namespace does not exist
  name: model-registry                # ModelRegistry CR name
  exposeHttpPort: true                # create model-registry-http Service on port 8080
```

> `namespace` must already exist. It is created by the RHOAI `DataScienceCluster` operator, not this chart. Set `createNamespace: true` only in isolated test environments.

---

### `modelRegistry.objectStorage`

Controls how the `model-registry-object-storage` Kubernetes Secret is created. Three mutually-exclusive credential modes are available:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Mode                         autoCreateBucket  externalSecret.enabled      │
│  ───────────────────────────  ───────────────   ──────────────────────────  │
│  OBC (default)                true              false                        │
│  Manual (not recommended)     false             false                        │
│  ESO (production recommended) false             true                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **Mutual exclusion:** `autoCreateBucket: true` and `externalSecret.enabled: true` cannot both be set. The OBC hook Job would overwrite the ESO-managed Secret. The chart emits a hard error if both are `true`.

#### Mode 1 — OBC (default, dev/staging)

```yaml
objectStorage:
  enabled: true
  autoCreateBucket: true              # ODF ObjectBucketClaim is created automatically
  odfStorageClass: openshift-storage.noobaa.io
  bucketClass: noobaa-default-bucket-class
  bucketRetentionPolicy: false
  maxObjects: ""                      # optional quota — leave empty for unlimited
  maxSize: ""                         # optional size quota, e.g. "100Gi"
  bucket: model-registry-artifacts    # base name; OBC appends a random suffix
  region: us-south
  endpoint: ""                        # auto-populated from OBC — leave empty
  accessKeyId: ""                     # auto-populated from OBC — leave empty
  secretAccessKey: ""                 # auto-populated from OBC — leave empty
  verifySSL: true
  storageClass: STANDARD
  externalSecret:
    enabled: false
```

A post-install hook Job reads the OBC-generated Secret and patches `model-registry-object-storage` at runtime. No credentials in Git or Vault.

#### Mode 2 — Manual (not recommended)

```yaml
objectStorage:
  autoCreateBucket: false
  endpoint: "https://s3.example.com"
  accessKeyId: "AKIAIOSFODNN7EXAMPLE"    # ⚠ credentials end up in Git
  secretAccessKey: "wJalrXUtnFEMI..."    # ⚠ not recommended for production
  externalSecret:
    enabled: false
```

Helm writes the Secret directly from values. Avoid this in production — credentials end up in Git history.

#### Mode 3 — ESO (production recommended)

```yaml
objectStorage:
  autoCreateBucket: false             # OBC disabled — ESO owns the Secret
  endpoint: ""                        # CLEAR — ESO reads from Vault
  accessKeyId: ""                     # CLEAR — ESO reads from Vault
  secretAccessKey: ""                 # CLEAR — ESO reads from Vault
  bucket: ""                          # CLEAR — ESO reads bucket name from Vault
  verifySSL: true
  storageClass: STANDARD
  region: us-south
  externalSecret:
    enabled: true
    refreshInterval: 24h
    secretStoreRef:
      name: vault-backend             # must match your ClusterSecretStore name
      kind: ClusterSecretStore
    targetName: ""                    # empty = live "model-registry-object-storage"
    remoteRef:
      key: maas/model-registry/object-storage   # Vault KV path
```

Helm creates an `ExternalSecret` CR; ESO resolves it and writes `model-registry-object-storage` into `modelRegistry.namespace`. Non-sensitive fields (`verifySSL`, `storageClass`, `region`) remain in values — only the four sensitive fields are fetched from Vault.

**Required Vault fields at `remoteRef.key`:**

| Vault field | Secret key written |
|---|---|
| `access-key-id` | `AWS_ACCESS_KEY_ID` |
| `secret-access-key` | `AWS_SECRET_ACCESS_KEY` |
| `endpoint` | `AWS_S3_ENDPOINT` |
| `bucket` | `AWS_S3_BUCKET` |

```bash
vault kv put secret/maas/model-registry/object-storage \
  access-key-id="<key>" \
  secret-access-key="<secret>" \
  endpoint="https://s3.example.com" \
  bucket="model-registry-artifacts-p-c35fd54c-f447-4959-92d8-120718bbb1a5"
```

**Environment overrides (`objectStorage`):**

| Key | Dev | Staging | Prod |
|-----|-----|---------|------|
| `autoCreateBucket` | `true` | `true` | `false` (ESO) |
| `bucket` | `model-registry-artifacts-dev` | `model-registry-artifacts-staging` | `""` (from Vault) |
| `externalSecret.enabled` | `false` | `false` | `true` |

---

### `modelRegistry.database`

Controls how the `model-registry-db-credentials` Secret and the backing PostgreSQL are provisioned. Two topology modes and two credential modes combine:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Topology         external  Deployment created  PVC created                  │
│  ───────────────  ────────  ─────────────────   ────────                    │
│  In-cluster PG    false     yes                 yes                          │
│  External DB      true      no                  no                           │
│                                                                               │
│  Credential mode  externalSecret.enabled  Secret owner                       │
│  ───────────────  ──────────────────────  ────────────                       │
│  Helm             false                   Helm (randAlphaNum for in-cluster) │
│  ESO              true                    External Secrets Operator           │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### In-cluster PostgreSQL (dev/staging)

```yaml
database:
  type: postgres
  external: false                     # deploy Deployment + PVC + Service
  externalSecret:
    enabled: false                    # Helm generates password via randAlphaNum
  internalDatabase:
    storageSize: 10Gi
    storageClassName: ""              # empty = cluster default StorageClass
    resources:
      limits:
        cpu: "1"
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 1Gi
```

When `external: false`, the chart deploys a PostgreSQL Deployment, PVC, and Service inside `modelRegistry.namespace`. The password is generated with `randAlphaNum 32` on first install and preserved on subsequent upgrades by a `lookup` guard — it is never written to Git.

#### External database (production)

```yaml
database:
  type: postgres
  external: true                      # no Deployment or PVC created
  externalDatabase:
    host: ""                          # managed DB hostname (RDS, Crunchy, etc.)
    port: 5432
    database: modelregistry
    username: modelregistry
    password: ""                      # CLEAR when externalSecret.enabled: true
    sslMode: require                  # use "disable" only for in-cluster PG
  externalSecret:
    enabled: false                    # set true to switch to ESO mode below
```

When `external: true`, the chart skips the Deployment and PVC and instead writes `model-registry-db-credentials` from `externalDatabase.*` values (or delegates to ESO if `externalSecret.enabled: true`).

#### ESO mode for database credentials (production recommended)

Only active when `external: true`. Helm creates an `ExternalSecret` CR; ESO resolves it into `model-registry-db-credentials`.

```yaml
database:
  external: true
  externalDatabase:
    host: "<managed-db-host>"         # non-sensitive, stays in values
    port: 5432
    database: modelregistry
    username: modelregistry
    password: ""                      # CLEAR — ESO reads password from Vault
    sslMode: require
  externalSecret:
    enabled: true
    refreshInterval: 1h
    secretStoreRef:
      name: vault-backend
      kind: ClusterSecretStore
    targetName: ""                    # empty = live "model-registry-db-credentials"
    remoteRef:
      key: maas/model-registry/database   # Vault KV path
      property: password                  # field name inside that KV secret
```

Only the password is fetched from Vault. The remaining non-sensitive fields (`host`, `port`, `database`, `username`, `sslMode`) are stamped directly from `externalDatabase.*` via ESO `target.template`. The Secret produced contains:

| Secret key | Source |
|---|---|
| `DB_HOST` | `externalDatabase.host` |
| `DB_PORT` | `externalDatabase.port` |
| `DB_NAME` | `externalDatabase.database` |
| `DB_USER` | `externalDatabase.username` |
| `DB_SSLMODE` | `externalDatabase.sslMode` |
| `DB_PASSWORD` | Vault `password` field |

```bash
vault kv put secret/maas/model-registry/database password="<strong-password>"
```

**Environment overrides (`database`):**

| Key | Dev | Staging | Prod |
|-----|-----|---------|------|
| `external` | `false` | `false` | `true` |
| `internalDatabase.storageSize` | `5Gi` | `10Gi` | `50Gi` |
| `externalSecret.enabled` | `false` | `false` | `true` |
| `externalDatabase.host` | — | — | managed DB host |
| `externalDatabase.sslMode` | — | — | `require` |

---

### `modelRegistry.service`

```yaml
service:
  type: ClusterIP
  restPort: 8080     # REST API port
  grpcPort: 9090     # gRPC port
```

---

### `modelRegistry.ingress`

```yaml
ingress:
  enabled: true
  hostname: ""          # empty = auto-generated from wildcardDomain
  tls:
    enabled: true
    secretName: ""      # empty = auto-generated cert
```

---

### `modelRegistry.versioning`

```yaml
versioning:
  enabled: true
  format: semantic      # semantic (1.0.0) or timestamp (20240101-120000)
  autoIncrement: true   # auto-bump version on model update
```

Written into a `model-registry-config` ConfigMap consumed by the reconciler.

---

### `modelRegistry.metadata`

```yaml
metadata:
  requiredFields:
    - name
    - description
    - framework
    - version
  customFields: []
  # Example custom fields:
  # - field: use-case
  #   type: string
  #   required: false
```

Defines which metadata fields are required when registering a model. Written into the `model-registry-config` ConfigMap.

---

### `modelRegistry.catalogIntegration`

```yaml
catalogIntegration:
  enabled: true
  autoRegister: true
  syncSchedule: "0 3 * * *"   # daily at 3 AM
```

When `enabled: true`, a CronJob is created that syncs model definitions from the catalog into the Model Registry on `syncSchedule`.

---

### `networkPolicies`

```yaml
networkPolicies:
  enabled: false
  allowFrom:
    - openshift-ingress
    - openshift-monitoring
```

When `enabled: true`, creates `NetworkPolicy` objects restricting ingress to the listed namespace selectors. Disabled by default in dev/staging; **enabled in prod**.

**Environment overrides:**

| Env | `enabled` |
|-----|-----------|
| dev | `false` |
| staging | `false` |
| prod | `true` |

---

### `commonLabels` / `commonAnnotations`

```yaml
commonLabels: {}
  # environment: production
  # team: ai-platform

commonAnnotations: {}
  # managed-by: helm
```

Additional labels and annotations applied to every resource rendered by the chart.

**Environment overrides:**

| Env | `commonLabels` | `commonAnnotations` |
|-----|----------------|---------------------|
| dev | `environment: dev` | `{}` |
| staging | `environment: staging` | `{}` |
| prod | `environment: prod`, `criticality: high` | `managed-by: gitops`, `change-management: required` |

---

## Credential Mode Decision Tree

```
Are you using on-cluster ODF/NooBaa for object storage?
  YES → autoCreateBucket: true, externalSecret.enabled: false  (OBC mode)
  NO  → Is ESO + Vault available?
          YES → autoCreateBucket: false, externalSecret.enabled: true  (ESO mode — recommended)
          NO  → autoCreateBucket: false, externalSecret.enabled: false  (manual — not recommended)

Are you using an external managed database (RDS, Crunchy, etc.)?
  NO  → external: false  (in-cluster PG with auto-generated password)
  YES → external: true; Is ESO + Vault available?
          YES → externalSecret.enabled: true  (ESO mode — recommended)
          NO  → externalSecret.enabled: false  (password in values — not recommended)
```

---

## ESO Testing Pattern

Before cutting over from a Helm-managed Secret to ESO, always test with a safe `targetName` so the live Secret is never touched:

```yaml
# In environments/prod/values.yaml — test phase
objectStorage:
  autoCreateBucket: false
  externalSecret:
    enabled: true
    targetName: model-registry-object-storage-eso-test   # safe test name

database:
  external: true
  externalSecret:
    enabled: true
    targetName: model-registry-db-credentials-eso-test   # safe test name
```

Verify the test Secrets match the live Secrets, then clean up:

```bash
oc delete externalsecret model-registry-object-storage-eso-test \
  model-registry-db-credentials-eso-test -n rhoai-model-registries
```

Then go live by setting `targetName: ""` (or removing it) and syncing ArgoCD. See [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-runtime/VAULT-SECRET-SETUP.md) for the full runbook.

---

## ArgoCD Sync Waves

When ESO is enabled, resources are deployed in this wave order to avoid race conditions:

| Wave | Resource | Template |
|------|----------|----------|
| 0 | `ClusterRole` + `RoleBinding` for ArgoCD ExternalSecret RBAC | `argocd-externalsecret-rbac.yaml` |
| 1 | `ExternalSecret` for object storage | `model-registry-objectstorage-externalsecret.yaml` |
| 1 | `ExternalSecret` for database credentials | `model-registry-db-externalsecret.yaml` |
| 1 | `ModelRegistry` CR | `modelregistry.yaml` |

The RBAC must exist at wave 0 — if ArgoCD lacks permission to create `ExternalSecret` objects at sync time, all subsequent waves fail with a `forbidden` error.

---

## Common Customisations

### Switch to ESO for object storage

```yaml
# environments/prod/values.yaml
modelRegistry:
  objectStorage:
    autoCreateBucket: false
    endpoint: ""
    accessKeyId: ""
    secretAccessKey: ""
    bucket: ""
    externalSecret:
      enabled: true
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      targetName: ""
      remoteRef:
        key: maas/model-registry/object-storage
```

Pre-populate Vault before syncing:

```bash
vault kv put secret/maas/model-registry/object-storage \
  access-key-id="<key>" \
  secret-access-key="<secret>" \
  endpoint="https://s3.example.com" \
  bucket="<bucket-name>"
```

### Switch to an external managed database

```yaml
modelRegistry:
  database:
    external: true
    externalDatabase:
      host: "mydb.rds.amazonaws.com"
      port: 5432
      database: modelregistry
      username: modelregistry
      password: ""
      sslMode: require
    externalSecret:
      enabled: true
      remoteRef:
        key: maas/model-registry/database
        property: password
```

### Increase storage for production

```yaml
modelRegistry:
  database:
    internalDatabase:
      storageSize: 100Gi
      resources:
        limits:
          cpu: "4"
          memory: 8Gi
        requests:
          cpu: "2"
          memory: 4Gi
```

### Disable catalog sync CronJob

```yaml
modelRegistry:
  catalogIntegration:
    enabled: false
```

---

## Troubleshooting

### Check what values Helm resolved

```bash
# Render templates locally without deploying
helm template maas-runtime . \
  -f values.yaml \
  -f environments/prod/values.yaml

# Show only ESO templates
helm template maas-runtime . \
  -f values.yaml \
  -f environments/prod/values.yaml \
  --show-only templates/model-registry-objectstorage-externalsecret.yaml \
  --show-only templates/model-registry-db-externalsecret.yaml
```

### ExternalSecret not Ready

```bash
# Check status conditions
oc describe externalsecret model-registry-object-storage -n rhoai-model-registries
oc describe externalsecret model-registry-db-credentials -n rhoai-model-registries

# Verify ClusterSecretStore is Ready
oc get clustersecretstore vault-backend

# Check ESO operator pods
oc get pods -n external-secrets-operator

# Verify the Vault path exists
vault kv get secret/maas/model-registry/object-storage
vault kv get secret/maas/model-registry/database
```

### ArgoCD sync fails — `forbidden` on ExternalSecret

```bash
# Verify the RBAC RoleBinding was created
oc get rolebinding argocd-externalsecret-manager-model-registry \
  -n rhoai-model-registries

# If missing, confirm ESO is enabled in values
helm template maas-runtime . \
  -f values.yaml \
  -f environments/prod/values.yaml \
  --show-only templates/argocd-externalsecret-rbac.yaml
```

### ModelRegistry CR not connecting after database rotation

The `ModelRegistry` CR reads `DB_PASSWORD` from the Secret at startup. After ESO refreshes the Secret, restart the Model Registry pod:

```bash
oc rollout restart deployment/model-registry -n rhoai-model-registries
```

### Helm render fails — `mutually exclusive` error

```
Error: autoCreateBucket and objectStorage.externalSecret.enabled are mutually exclusive.
```

Set `autoCreateBucket: false` when using ESO. Both cannot be `true` simultaneously.

### OBC hook Job failing

```bash
# Check the hook Job logs
oc get jobs -n rhoai-model-registries
oc logs job/<hook-job-name> -n rhoai-model-registries
```

---

## Related Documents

- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-runtime/VAULT-SECRET-SETUP.md) — complete Vault setup runbook (Scenarios A, B, C + testing + rotation)
- [`maas-platform/README.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-runtime/README.md) — platform chart documentation
- [`docs/deploying-external-secrets-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — ESO operator installation
- [`docs/deploying-vault-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — Vault operator installation
