# Vault Secret Setup for maas-platform ESO Integration

<!-- vault-radar-ignore: documentation file — all values are placeholders, not real credentials -->

This guide covers every step a user must perform **before the first ArgoCD
sync** when using External Secrets Operator (ESO) to manage `maas-platform`
secrets. No credentials ever touch Git when this path is followed.

> **Prerequisite reading:** Ensure the External Secrets Operator is already
> installed and a `ClusterSecretStore` named `vault-backend` exists and is
> `Ready`. See
> [`docs/deploying-external-secrets-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md)
> for installation steps.

---

## Overview — Which Secrets ESO Manages

`maas-platform` uses ESO to manage two Kubernetes Secrets:

| Secret | Namespace | Consumed by | Vault path |
|--------|-----------|-------------|------------|
| `maas-db-config` | `redhat-ods-applications` | `maas-api` (DB connection URL at startup) | depends on scenario — see below |
| `maas-postgres-creds` | `redhat-ods-applications` | `maas-postgres` Deployment (in-cluster PG only) | `secret/maas/postgres` |

The Vault path required depends on which **database scenario** you are using:

| Scenario | `maasDatabase.external` | Vault paths needed |
|----------|-------------------------|--------------------|
| **A — In-cluster PostgreSQL** | `false` | `secret/maas/postgres` only (single source of truth) |
| **B — External managed database** | `true` | `secret/maas/database` only |

---

## Scenario A — In-cluster PostgreSQL (single Vault path)

Use this when `maasDatabase.external: false` (the default). ESO reads
`username`, `password`, `database`, and `sslMode` from a single Vault path
and uses them to:

1. Create `maas-postgres-creds` — injected into the Postgres Deployment as env vars.
2. Assemble and create `maas-db-config` — the connection URL `maas-api` reads at startup.

**Changing the password in Vault once automatically updates both secrets** on
the next ESO refresh interval.

### Step 1 — Port-forward to Vault (if running in-cluster)

```bash
oc port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(oc get secret vault-unseal-keys -n vault \
  -o jsonpath='{.data.root-token}' | base64 -d)
```

### Step 2 — Store credentials in Vault

```bash
vault kv put secret/maas/postgres \
  username="maas" \
  password="<your-strong-password>" \
  database="maas" \
  sslMode="disable"
```

> **Field names are fixed** — the ESO template references exactly these four
> keys: `username`, `password`, `database`, `sslMode`. Do not rename them.

Verify the data was stored:

```bash
vault kv get secret/maas/postgres
```

Expected output:
```
====== Data ======
Key        Value
---        -----
database   maas
password   <your-strong-password>
sslMode    disable
username   maas
```

### Step 3 — Update values (prod environment overlay)

Edit `environments/prod/values.yaml` and set:

```yaml
maasDatabase:
  enabled: false                  # Helm will NOT create maas-db-config
  external: false
  secretNamespace: redhat-ods-applications

  externalSecret:
    enabled: true                 # ESO will create maas-db-config
    refreshInterval: 1h
    secretStoreRef:
      name: vault-backend         # must match your ClusterSecretStore name
      kind: ClusterSecretStore
    remoteRef:
      key: maas/postgres          # same path as internal.externalSecret below
      property: connection-url    # not used in internal mode — template assembles URL

  internal:
    enabled: true                 # still deploy the Postgres Deployment + Service
    namespace: redhat-ods-applications
    purpose: poc
    username: ""                  # CLEAR — no plaintext credentials in Git
    password: ""                   # CLEAR — set via ESO, not committed to Git
    database: maas
    sslMode: disable

    externalSecret:
      enabled: true               # ESO will create maas-postgres-creds
      refreshInterval: 24h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      targetName: ""              # empty = "maas-postgres-creds" (production name)
      remoteRef:
        key: maas/postgres        # same single Vault path used by both ExternalSecrets
```

> **Why `username: ""` and `password: ""`?** The chart has a guard that fails
> the Helm render if `internal.externalSecret.enabled: true` but `username` is
> still set — this prevents accidentally committing credentials to Git.

### Step 4 — Sync the ArgoCD Application

```bash
# Trigger a sync (or click Sync in the ArgoCD UI)
argocd app sync fusion-maas-platform-config-prod
```

ArgoCD will deploy resources in this wave order:

```
Wave 0  ClusterRole + RoleBinding          ArgoCD RBAC for ExternalSecret objects
Wave 1  ExternalSecret maas-db-config      ESO assembles DB_CONNECTION_URL from Vault
Wave 1  ExternalSecret maas-postgres-creds        ESO reads Vault fields into Postgres Secret
Wave 1  Postgres Deployment + Service      reads Postgres Secret via secretKeyRef
Wave 10 DataScienceCluster                 enables maas-api which reads maas-db-config
```

### Step 5 — Verify

```bash
# 1. Check ExternalSecret status (both should show Ready=True)
oc get externalsecret -n redhat-ods-applications

# 2. Verify ESO created the Secrets
oc get secret maas-db-config -n redhat-ods-applications
oc get secret maas-postgres-creds -n redhat-ods-applications

# 3. Decode and confirm DB_CONNECTION_URL was assembled correctly
oc get secret maas-db-config -n redhat-ods-applications \
  -o jsonpath='{.data.DB_CONNECTION_URL}' | base64 -d && echo
# Expected:
# postgresql://maas:CHANGEME@maas-postgres.redhat-ods-applications.svc.cluster.local:5432/maas?sslmode=disable

# 4. Confirm the Postgres Secret has all three keys
oc get secret maas-postgres-creds -n redhat-ods-applications \
  -o jsonpath='{.data}' | python3 -c \
  "import sys,json,base64; d=json.load(sys.stdin); [print(k,'=',base64.b64decode(v).decode()) for k,v in d.items()]"
# Expected:
# POSTGRES_DB    = maas
# POSTGRES_DB    = maas
# POSTGRES_PASSWORD  = <value set in Vault>
# POSTGRES_USER  = maas
```

---

## Scenario B — External managed database (RDS, CloudSQL, Crunchy, etc.)

> **When to use:** This is the recommended path for **production go-live** once
> you are ready to move off the in-cluster POC PostgreSQL instance.
> See also `POST_SYNC_MANUAL_STEPS.md` Step 5.

Use this when `maasDatabase.external: true`. Only `maas-db-config` is managed
by ESO — there is no in-cluster Postgres to configure, so `maas-postgres-creds`
is not created.

### Step 1 — Port-forward to Vault (if running in-cluster)

```bash
oc port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(oc get secret vault-unseal-keys -n vault \
  -o jsonpath='{.data.root-token}' | base64 -d)
```

### Step 2 — Store the full connection URL in Vault

Construct your connection string using the format below, then store it as a
single field. Replace each placeholder with real values from your managed
database provider:

```
postgresql://DB_USER:DB_PASS@DB_HOST:5432/DB_NAME?sslmode=require
```

```bash
vault kv put secret/maas/database connection-url="<your-assembled-connection-string>"
```

> Use `sslmode=require` for any database reachable over the network.
> The field name `connection-url` is fixed — the ESO template references it by
> this exact name.

Verify the value was stored (Vault masks the actual string):

```bash
vault kv get secret/maas/database
```

Expected output:
```
======= Data =======
Key              Value
---              -----
connection-url   postgresql://***
```

### Step 3 — Update values (prod environment overlay)

```yaml
maasDatabase:
  enabled: false                  # Helm will NOT create maas-db-config
  external: true                  # no in-cluster Postgres
  secretNamespace: redhat-ods-applications

  externalSecret:
    enabled: true                 # ESO will create maas-db-config
    refreshInterval: 1h
    secretStoreRef:
      name: vault-backend
      kind: ClusterSecretStore
    targetName: ""                # empty = "maas-db-config"
    remoteRef:
      key: maas/database          # Vault KV path
      property: connection-url    # field name inside that path

  internal:
    enabled: false                # no in-cluster Postgres Deployment/Service
```

### Step 4 — Sync the ArgoCD Application

```bash
argocd app sync fusion-maas-platform-config-prod
```

### Step 5 — Verify

```bash
# 1. Check ExternalSecret status
oc get externalsecret maas-db-config -n redhat-ods-applications

# 2. Decode and confirm the URL
oc get secret maas-db-config -n redhat-ods-applications \
  -o jsonpath='{.data.DB_CONNECTION_URL}' | base64 -d && echo
```

---

## Testing ESO Without Touching Live Secrets

Before cutting over from the Helm-managed secret to ESO, test with a safe
target name so the live `maas-db-config` is not touched:

```yaml
maasDatabase:
  enabled: true                   # keep Helm managing live maas-db-config
  externalSecret:
    enabled: true                 # ALSO enable ESO with a test target name
    targetName: maas-db-config-eso-test   # writes to this name only
    ...
  internal:
    enabled: true
    externalSecret:
      enabled: true
      targetName: maas-postgres-creds-eso-test
      ...
```

> **Note:** `maasDatabase.enabled: true` and `externalSecret.enabled: true`
> together is only allowed when `targetName` differs from `maas-db-config`.
> If both are `true` and `targetName` is empty, the chart emits a hard error.

Verify the test secrets:

```bash
oc get secret maas-db-config-eso-test maas-postgres-creds-eso-test \
  -n redhat-ods-applications

oc get secret maas-db-config-eso-test -n redhat-ods-applications \
  -o jsonpath='{.data.DB_CONNECTION_URL}' | base64 -d && echo

# Once confirmed correct — clean up test secrets
oc delete externalsecret maas-db-config-eso-test \
  maas-postgres-creds-eso-test -n redhat-ods-applications
```

---

## Password Rotation

With ESO in place, rotating the database password requires only two steps — no
Git commit, no ArgoCD sync.

### Scenario A (in-cluster PostgreSQL)

```bash
# 1. Update the single Vault path
vault kv patch secret/maas/postgres password="<new-strong-password>"

# 2. Wait for ESO refresh interval (default 1h for maas-db-config, 24h for maas-postgres-creds)
#    Or force immediate refresh by annotating the ExternalSecret:
oc annotate externalsecret maas-db-config \
  -n redhat-ods-applications \
  force-sync=$(date +%s) --overwrite
oc annotate externalsecret maas-postgres-creds \
  -n redhat-ods-applications \
  force-sync=$(date +%s) --overwrite

# 3. Restart maas-api and postgres to pick up new credentials
oc rollout restart deployment/maas-postgres deployment/maas-api \
  -n redhat-ods-applications
```

### Scenario B (external managed database)

```bash
# 1. Update the connection URL in Vault (with new password)
vault kv patch secret/maas/database \
  connection-url="postgresql://<user>:<new-password>@<host>:5432/<db>?sslmode=require"

# 2. Force ESO refresh
oc annotate externalsecret maas-db-config \
  -n redhat-ods-applications \
  force-sync=$(date +%s) --overwrite

# 3. Restart maas-api
oc rollout restart deployment/maas-api -n redhat-ods-applications
```

---

## Troubleshooting

### ExternalSecret shows `SecretSyncedError` or `NotReady`

```bash
# Inspect the ExternalSecret conditions
oc describe externalsecret maas-db-config -n redhat-ods-applications

# Common causes:
# - ClusterSecretStore not Ready → check ESO operator pods
oc get clustersecretstore vault-backend
oc get pods -n external-secrets-operator

# - Vault path does not exist
vault kv get secret/maas/postgres   # or secret/maas/database

# - Vault token expired / auth role missing
vault token lookup
```

### `SyncFailed` in ArgoCD — forbidden on ExternalSecret resource

```bash
# The RBAC template (argocd-externalsecret-rbac.yaml) should handle this.
# Verify the RoleBinding exists:
oc get rolebinding argocd-externalsecret-manager -n redhat-ods-applications

# If missing, the ESO flag may be false — confirm values are applied:
helm template t ./helm/maas-platform \
  --values helm/maas-platform/values.yaml \
  --values helm/maas-platform/environments/prod/values.yaml \
  --show-only templates/argocd-externalsecret-rbac.yaml
```

### Helm render fails with "mutually exclusive" error

```
maasDatabase.enabled and maasDatabase.externalSecret.enabled are mutually exclusive.
```

Set `maasDatabase.enabled: false` when `externalSecret.enabled: true`. These
two flags cannot both be `true` unless `targetName` is set to a non-default
test value.

### `maas-api` not reading updated secret after rotation

`maas-api` reads `maas-db-config` at startup only. After ESO updates the
Secret, restart the deployment:

```bash
oc rollout restart deployment/maas-api -n redhat-ods-applications
```

---

## Related Documents

- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-runtime/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-runtime` (object storage + database)
- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-model-registry` (git credentials + Hugging Face token)
- [`POST_SYNC_MANUAL_STEPS.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/POST_SYNC_MANUAL_STEPS.md) — post-sync checklist including credential go-live steps
- [`VERIFICATION.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VERIFICATION.md) — full deployment verification checklist
- [`docs/deploying-external-secrets-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — ESO operator installation
- [`docs/deploying-vault-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — Vault operator installation
- [`models-as-a-service/docs/content/install/maas-setup.md`](../../../../models-as-a-service/docs/content/install/maas-setup.md) — upstream MaaS install guide
