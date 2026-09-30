# Vault Secret Setup for maas-runtime ESO Integration

<!-- vault-radar-ignore: documentation file — all values are placeholders, not real credentials -->

This guide covers every step a user must perform **before creating the ArgoCD
Application** (and therefore before the first sync) when using External Secrets
Operator (ESO) to manage `maas-runtime` secrets.

> ⚠️ **Vault secrets must exist before ArgoCD syncs the Application.**
> ESO resolves `ExternalSecret` CRs at sync time. If the Vault paths are empty
> or missing when ArgoCD first applies the resources, the ExternalSecrets will
> enter `SecretSyncedError` and the workloads that depend on them will fail to
> start. Populate Vault, verify, then create or sync the ArgoCD Application.

> **Prerequisite reading:** Ensure the External Secrets Operator is already
> installed and a `ClusterSecretStore` named `vault-backend` exists and is
> `Ready`. See
> [`docs/deploying-external-secrets-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md)
> for installation steps.

---

## Overview — Which Secrets ESO Manages

`maas-runtime` uses ESO to manage up to two Kubernetes Secrets depending on
which credential mode is active. The mode is determined entirely by values flags
— choose one path per secret.

| Secret | Namespace | Consumed by | ESO active when |
|--------|-----------|-------------|-----------------|
| `model-registry-object-storage` | `rhoai-model-registries` | `model-registry-catalog-sync` CronJob (volume mount) | `objectStorage.autoCreateBucket: false` AND `objectStorage.externalSecret.enabled: true` |
| `model-registry-db-credentials` | `rhoai-model-registries` | `ModelRegistry` CR (`spec.postgres.passwordSecret`) | `database.external: true` AND `database.externalSecret.enabled: true` |

### Credential mode summary

| Secret | Mode | `autoCreateBucket` | `externalSecret.enabled` | Who creates the Secret |
|--------|------|---|---|---|
| Object Storage | OBC / ODF (default) | `true` | `false` | Hook Job patches at runtime — **no Vault needed** |
| Object Storage | Manual Helm | `false` | `false` | Helm writes keys from values — credentials in Git ⚠️ |
| Object Storage | **ESO / Vault** | `false` | `true` | ESO reads 3 fields from Vault — **no credentials in Git** ✅ |
| Database | Internal PG (default) | n/a | `false` | Helm generates `randAlphaNum 32` — **no Vault needed** ✅ |
| Database | External Helm | `external: true` | `false` | Helm writes `DB_PASSWORD` from values — credentials in Git ⚠️ |
| Database | **ESO / Vault** | `external: true` | `true` | ESO reads password from Vault — **no credentials in Git** ✅ |

> **Mutual exclusion:** `autoCreateBucket: true` and
> `objectStorage.externalSecret.enabled: true` cannot both be set — the chart
> emits a hard render error. The OBC hook Job would overwrite the ESO-managed
> Secret.

---

## Step 0 — Connect to Vault

Run these commands once before any of the scenario steps below. Skip if you
already have `VAULT_ADDR` and `VAULT_TOKEN` set in your shell.

```bash
# If Vault is running in-cluster, port-forward first
oc port-forward -n vault svc/vault 8200:8200 &

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(oc get secret vault-unseal-keys -n vault \
  -o jsonpath='{.data.root-token}' | base64 -d)

# Confirm connectivity
vault status
```

Expected output:
```
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
...
```

---

## Scenario A — External Object Storage (IBM COS / AWS S3)

Use this when `objectStorage.autoCreateBucket: false`. ESO reads three
sensitive fields from Vault and assembles the full `model-registry-object-storage`
Secret. Non-sensitive fields (`bucket`, `region`, `storageClass`, `verifySSL`)
remain in `values.yaml`.

### Step 1 — Store object storage credentials in Vault

Replace each placeholder with your real IBM Cloud Object Storage or AWS S3
values before running this command. **All four fields are required** — the
bucket name is stored in Vault alongside the credentials so a single path
is the complete source of truth for object storage configuration.

```bash
vault kv put secret/maas/model-registry/object-storage \
  access-key-id="<your-access-key-id>" \
  secret-access-key="<your-secret-access-key>" \
  endpoint="https://s3.<region>.cloud-object-storage.appdomain.cloud" \
  bucket="<your-exact-bucket-name>"
```

> **Field names are fixed.** The ESO template references exactly these four
> keys: `access-key-id`, `secret-access-key`, `endpoint`, `bucket`.
> Do not rename them.
>
> **Why bucket in Vault?** When `autoCreateBucket: false` the bucket was
> created out-of-band (OBC-generated suffix, IBM COS console, AWS S3, etc.)
> and its exact name is only known after provisioning. Storing it in Vault
> alongside the credentials means a single `vault kv put` captures the
> complete object-storage configuration — no Git commit needed to update the
> bucket name.

Verify the data was stored:

```bash
vault kv get secret/maas/model-registry/object-storage
```

Expected output:
```
======= Data =======
Key               Value
---               -----
access-key-id     <your-access-key-id>
bucket            <your-exact-bucket-name>
endpoint          https://s3.<region>.cloud-object-storage.appdomain.cloud
secret-access-key *** (masked)
```

### Step 2 — Update values (prod environment overlay)

Edit `environments/prod/values.yaml` and set:

```yaml
modelRegistry:
  objectStorage:
    autoCreateBucket: false         # switch off OBC — using external S3 / IBM COS
    bucket: ""                      # CLEAR — ESO reads bucket name from Vault
    region: us-south
    endpoint: ""                    # CLEAR — ESO reads this from Vault
    accessKeyId: ""                 # CLEAR — ESO reads this from Vault
    secretAccessKey: ""             # CLEAR — ESO reads this from Vault
    verifySSL: true
    storageClass: STANDARD
    externalSecret:
      enabled: true                 # ESO will create model-registry-object-storage
      refreshInterval: 24h
      secretStoreRef:
        name: vault-backend         # must match your ClusterSecretStore name
        kind: ClusterSecretStore
      targetName: ""                # empty = "model-registry-object-storage"
      remoteRef:
        key: maas/model-registry/object-storage
```

### Step 3 — Create or sync the ArgoCD Application

> ⚠️ **Do not create the ArgoCD Application before completing Steps 1–2.**
> ESO will attempt to resolve the ExternalSecret immediately on first sync.
> If the Vault path does not exist at that moment, the Secret will not be
> created and the `model-registry-catalog-sync` CronJob will fail to start.

```bash
# If the Application already exists, trigger a sync
argocd app sync fusion-maas-runtime-prod

# If creating for the first time, the Application will auto-sync on creation
# (assuming syncPolicy.automated is set)
```

### Step 4 — Verify

```bash
# 1. Check ExternalSecret status — should show Ready=True
oc get externalsecret model-registry-object-storage -n rhoai-model-registries

# 2. Confirm ESO created the Secret with all expected keys
oc get secret model-registry-object-storage -n rhoai-model-registries \
  -o jsonpath='{.data}' | python3 -c \
  "import sys,json,base64; d=json.load(sys.stdin); [print(k) for k in sorted(d)]"
# Expected keys:
# AWS_ACCESS_KEY_ID
# AWS_DEFAULT_REGION
# AWS_S3_BUCKET
# AWS_S3_ENDPOINT
# AWS_STORAGE_CLASS
# VERIFY_SSL

# 3. Decode and confirm all fields were populated correctly
oc get secret model-registry-object-storage -n rhoai-model-registries \
  -o jsonpath='{.data}' | python3 -c \
  "import sys,json,base64; d=json.load(sys.stdin); [print(k,'=',base64.b64decode(v).decode()) for k,v in sorted(d.items())]"
# Expected: all seven keys with values — AWS_S3_BUCKET and AWS_S3_ENDPOINT
# must match exactly what was stored in Vault.
```

---

## Scenario B — External Managed Database (RDS, CloudSQL, Crunchy, etc.)

Use this when `database.external: true`. ESO reads **only the password** from
Vault. The remaining non-sensitive fields (`host`, `port`, `database`,
`username`, `sslMode`) remain in `values.yaml` — only one field in Vault to
manage.

### Step 1 — Store the database password in Vault

```bash
vault kv put secret/maas/model-registry/database \
  password="<your-strong-database-password>"
```

> **Field name is fixed.** The ESO template references exactly the key
> `password`. Do not rename it.

Verify the data was stored:

```bash
vault kv get secret/maas/model-registry/database
```

Expected output:
```
====== Data ======
Key        Value
---        -----
password   *** (masked)
```

### Step 2 — Update values (prod environment overlay)

Edit `environments/prod/values.yaml` and set:

```yaml
modelRegistry:
  database:
    external: true                  # use managed database — no in-cluster PG Deployment
    externalSecret:
      enabled: true                 # ESO will create model-registry-db-credentials
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend         # must match your ClusterSecretStore name
        kind: ClusterSecretStore
      targetName: ""                # empty = "model-registry-db-credentials"
      remoteRef:
        key: maas/model-registry/database
        property: password          # only this field is read from Vault
    externalDatabase:
      host: "mydb.rds.amazonaws.com"   # REPLACE with your managed DB host
      port: 5432
      database: modelregistry
      username: modelregistry
      password: ""                  # CLEAR — ESO reads this from Vault
      sslMode: require              # require for any network-reachable DB
```

> **Why only the password in Vault?** Host, port, username, and database name
> are non-sensitive configuration. Storing only the password keeps the Vault
> path minimal — one field to rotate, one field to audit. The ESO
> `target.template` assembles all six `DB_*` keys in the final Secret from
> both Vault and values.

### Step 3 — Create or sync the ArgoCD Application

> ⚠️ **Do not create the ArgoCD Application before completing Steps 1–2.**
> The `ModelRegistry` CR reads `DB_PASSWORD` from `model-registry-db-credentials`
> at startup. If ESO has not yet resolved the ExternalSecret when the
> `ModelRegistry` operator reconciles, the model registry will fail to connect
> to the database.

```bash
argocd app sync fusion-maas-runtime-prod
```

### Step 4 — Verify

```bash
# 1. Check ExternalSecret status — should show Ready=True
oc get externalsecret model-registry-db-credentials -n rhoai-model-registries

# 2. Confirm ESO created the Secret with all expected keys
oc get secret model-registry-db-credentials -n rhoai-model-registries \
  -o jsonpath='{.data}' | python3 -c \
  "import sys,json,base64; d=json.load(sys.stdin); [print(k) for k in sorted(d)]"
# Expected keys:
# DB_HOST
# DB_NAME
# DB_PASSWORD
# DB_PORT
# DB_SSLMODE
# DB_USER

# 3. Confirm the password key is populated (do NOT print the value in production)
oc get secret model-registry-db-credentials -n rhoai-model-registries \
  -o jsonpath='{.data.DB_HOST}' | base64 -d && echo
# Expected: your managed DB host from values

# 4. Confirm the ModelRegistry CR is using the correct secret reference
oc get modelregistry model-registry -n rhoai-model-registries \
  -o jsonpath='{.spec.postgres.passwordSecret}' && echo
# Expected: {"key":"DB_PASSWORD","name":"model-registry-db-credentials"}
```

---

## Scenario C — Both Secrets via ESO (full production setup)

When using an external managed database **and** external object storage,
complete Scenario A and Scenario B in sequence before syncing the Application.

### Vault paths required

```bash
# Object storage credentials (all four fields)
vault kv put secret/maas/model-registry/object-storage \
  access-key-id="<key>" \
  secret-access-key="<secret>" \
  endpoint="https://s3.<region>.cloud-object-storage.appdomain.cloud" \
  bucket="<exact-bucket-name>"

# Database password
vault kv put secret/maas/model-registry/database \
  password="<strong-password>"
```

### prod values overlay (both ESO enabled)

```yaml
modelRegistry:
  objectStorage:
    autoCreateBucket: false
    bucket: ""                      # CLEAR — ESO reads bucket name from Vault
    region: us-south
    endpoint: ""                    # CLEAR — ESO reads this from Vault
    accessKeyId: ""                 # CLEAR — ESO reads this from Vault
    secretAccessKey: ""             # CLEAR — ESO reads this from Vault
    verifySSL: true
    storageClass: STANDARD
    externalSecret:
      enabled: true
      refreshInterval: 24h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      targetName: ""
      remoteRef:
        key: maas/model-registry/object-storage

  database:
    external: true
    externalSecret:
      enabled: true
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      targetName: ""
      remoteRef:
        key: maas/model-registry/database
        property: password
    externalDatabase:
      host: "mydb.rds.amazonaws.com"
      port: 5432
      database: modelregistry
      username: modelregistry
      password: ""                  # CLEAR
      sslMode: require
```

Then sync:

```bash
argocd app sync fusion-maas-runtime-prod
```

---

## Testing ESO Without Touching Live Secrets

Before cutting over in production, test ESO with a safe `targetName` so the
live secrets are not touched. Both ESO and Helm can run in parallel when
`targetName` differs from the default name.

```yaml
modelRegistry:
  objectStorage:
    autoCreateBucket: false
    externalSecret:
      enabled: true
      targetName: model-registry-object-storage-eso-test   # writes here only

  database:
    external: true
    externalSecret:
      enabled: true
      targetName: model-registry-db-credentials-eso-test   # writes here only
    externalDatabase:
      host: "mydb.rds.amazonaws.com"
      password: ""
```

Verify the test secrets:

```bash
# Confirm ESO created the test secrets
oc get secret model-registry-object-storage-eso-test \
               model-registry-db-credentials-eso-test \
  -n rhoai-model-registries

# Spot-check object storage endpoint
oc get secret model-registry-object-storage-eso-test -n rhoai-model-registries \
  -o jsonpath='{.data.AWS_S3_ENDPOINT}' | base64 -d && echo

# Spot-check DB host (non-sensitive)
oc get secret model-registry-db-credentials-eso-test -n rhoai-model-registries \
  -o jsonpath='{.data.DB_HOST}' | base64 -d && echo

# Clean up test secrets once confirmed correct
oc delete externalsecret \
  model-registry-object-storage-eso-test \
  model-registry-db-credentials-eso-test \
  -n rhoai-model-registries
```

---

## Credential Rotation

With ESO in place, rotating credentials requires **no Git commit and no ArgoCD
sync**.

### Rotate object storage key (Scenario A)

```bash
# 1. Update the Vault path with the new key
vault kv patch secret/maas/model-registry/object-storage \
  access-key-id="<new-key>" \
  secret-access-key="<new-secret>"

# 2. Force immediate ESO refresh (default interval is 24h)
oc annotate externalsecret model-registry-object-storage \
  -n rhoai-model-registries \
  force-sync=$(date +%s) --overwrite

# 3. Restart the CronJob's next run — or force a manual Job if needed
# (CronJob reads the Secret at pod start; the next scheduled run picks up new creds)
```

### Rotate database password (Scenario B)

```bash
# 1. Change the password in the managed database first, then update Vault
vault kv patch secret/maas/model-registry/database \
  password="<new-strong-password>"

# 2. Force immediate ESO refresh (default interval is 1h)
oc annotate externalsecret model-registry-db-credentials \
  -n rhoai-model-registries \
  force-sync=$(date +%s) --overwrite

# 3. The ModelRegistry operator re-reads the Secret automatically on the next
#    reconcile cycle. Force an immediate reconcile by annotating the CR:
oc annotate modelregistry model-registry \
  -n rhoai-model-registries \
  reconcile=$(date +%s) --overwrite
```

---

## Troubleshooting

### ExternalSecret shows `SecretSyncedError` or status is not `Ready`

```bash
# Inspect conditions on the failing ExternalSecret
oc describe externalsecret model-registry-object-storage -n rhoai-model-registries
oc describe externalsecret model-registry-db-credentials -n rhoai-model-registries

# Common causes:

# 1. ClusterSecretStore not Ready
oc get clustersecretstore vault-backend
oc get pods -n external-secrets-operator

# 2. Vault path does not exist
vault kv get secret/maas/model-registry/object-storage
vault kv get secret/maas/model-registry/database

# 3. Wrong field name in Vault
#    Object storage requires: access-key-id, secret-access-key, endpoint
#    Database requires:       password
vault kv get -format=json secret/maas/model-registry/object-storage | jq '.data.data | keys'
vault kv get -format=json secret/maas/model-registry/database       | jq '.data.data | keys'

# 4. Vault token expired or auth role missing
vault token lookup
```

### ArgoCD sync fails — `forbidden` on ExternalSecret resource

The ArgoCD application-controller ServiceAccount does not have permission to
manage `external-secrets.io` CRs in `rhoai-model-registries` by default.
The chart creates a `ClusterRole + RoleBinding` automatically at sync-wave 0
when either ESO flag is enabled (`templates/argocd-externalsecret-rbac.yaml`).

```bash
# Verify the ClusterRole and RoleBinding were created (sync-wave 0)
oc get clusterrole argocd-externalsecret-manager-model-registry
oc get rolebinding argocd-externalsecret-manager-model-registry \
  -n rhoai-model-registries
```

If either is missing, confirm the ESO flag is enabled in your values and
verify the template renders:

```bash
helm template test ./helm/maas-runtime \
  --values helm/maas-runtime/values.yaml \
  --values helm/maas-runtime/environments/prod/values.yaml \
  --show-only templates/argocd-externalsecret-rbac.yaml
```

If the output is empty, neither `database.externalSecret.enabled` nor
`objectStorage.externalSecret.enabled` is `true` — the RoleBinding is
intentionally absent when ESO is not in use.

### Helm render fails — `mutually exclusive` error

```
modelRegistry.objectStorage.autoCreateBucket: true and
objectStorage.externalSecret.enabled: true are mutually exclusive.
```

Set `objectStorage.autoCreateBucket: false` when
`objectStorage.externalSecret.enabled: true`. The OBC hook Job would
overwrite the ESO-managed Secret if both were active simultaneously.

### `model-registry-catalog-sync` CronJob fails to start

The CronJob mounts `model-registry-object-storage` and
`model-registry-db-credentials` as volumes. If either Secret does not exist
at pod-start time the pod will be stuck in `CreateContainerConfigError`.

```bash
# Check whether both Secrets exist
oc get secret model-registry-object-storage \
               model-registry-db-credentials \
  -n rhoai-model-registries

# If missing, check ExternalSecret status
oc get externalsecret -n rhoai-model-registries

# Once Secrets are present, delete the failed pod — CronJob will recreate it
oc delete pod -n rhoai-model-registries -l app.kubernetes.io/component=catalog-sync
```

### ModelRegistry CR not connecting to the database after rotation

The `ModelRegistry` operator re-reads the password Secret on its reconcile
cycle (typically a few minutes). Force an immediate reconcile:

```bash
oc annotate modelregistry model-registry \
  -n rhoai-model-registries \
  reconcile=$(date +%s) --overwrite
```

---

## Related Documents

- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-platform` secrets
- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-model-registry` (git credentials + Hugging Face token)
- [`docs/deploying-external-secrets-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — ESO operator installation
- [`docs/deploying-vault-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — Vault operator installation
- [`models-as-a-service/docs/content/install/maas-setup.md`](../../../../models-as-a-service/docs/content/install/maas-setup.md) — upstream MaaS install guide
