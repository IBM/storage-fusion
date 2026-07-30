# Vault Secret Setup for maas-model-deploy ESO Integration

<!-- vault-radar-ignore: documentation file — all values are placeholders, not real credentials -->

This guide covers every step a user must perform **before the first ArgoCD sync**
when using External Secrets Operator (ESO) to manage `maas-model-deploy` secrets.
No credentials ever touch Git when this path is followed.

> ⚠️ **Vault secrets must exist before ArgoCD syncs the Application.**
> ESO resolves `ExternalSecret` CRs at sync time. If the Vault path is empty or
> missing when ArgoCD first applies the resources, the ExternalSecrets will enter
> `SecretSyncedError` and the `LLMInferenceService` pod will fail to start because
> the KServe storage-initializer cannot authenticate to S3. Populate Vault, verify,
> then create or sync the ArgoCD Application.

> **Prerequisite reading:** Ensure the External Secrets Operator is already installed
> and a `ClusterSecretStore` named `vault-backend` exists and is `Ready`. See
> [`docs/deploying-external-secrets-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md)
> for installation steps.

---

## Overview — Which Secrets ESO Manages

`maas-model-deploy` uses ESO to manage **two Kubernetes Secrets** from a single
Vault KV path. Both secrets are controlled by one flag — enabling ESO activates
management of both simultaneously.

| Secret | Namespace | Consumed by | ESO active when |
|--------|-----------|-------------|-----------------|
| `<model.namespace>-connection` | `model.namespace` (e.g. `deploy-models`) | `LLMInferenceService` + `ServiceAccount` — KServe storage-initializer authenticates to S3 using this secret | `s3.externalSecret.enabled: true` |
| `storage-config` | `model.namespace` (e.g. `deploy-models`) | KServe storage-initializer init-container — reads the JSON blob to locate and authenticate to the S3 bucket | `s3.externalSecret.enabled: true` |

Both secrets are sourced from the **same single Vault KV path** — all five S3
fields (`access_key_id`, `secret_access_key`, `endpoint`, `region`, `bucket`)
are stored together and fetched once.

### Credential mode summary

| Mode | ESO flag | Who creates the Secrets |
|------|----------|-------------------------|
| **Manual** (default) | `s3.externalSecret.enabled: false` | Supply `s3.accessKeyId` and `s3.secretAccessKey` via `--set` flags or environment overlay — all five fields come from `values.yaml` |
| **ESO / Vault** | `s3.externalSecret.enabled: true` | ESO reads all five fields from Vault and writes both Secrets — **no credentials in Git** ✅ |

> **What stays in `values.yaml` in both modes:** `s3.modelPath` (used to build
> the model URI `s3://<bucket>/<modelPath>`) and `s3.verifySSL` are
> non-sensitive and always come from values. All other S3 fields are ignored
> when ESO is enabled.

---

## Step 0 — Connect to Vault

Run these commands once before any of the steps below. Skip if you already have
`VAULT_ADDR` and `VAULT_TOKEN` set in your shell.

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

## Step 1 — Store S3 Credentials in Vault

All five S3 fields must be stored at a single Vault KV path. The path convention
is `secret/maas/model-deploy/<model-name>/s3` — use the same value as
`model.name` in your environment values file.

```bash
vault kv put secret/maas/model-deploy/<model-name>/s3 \
  access_key_id="<your-s3-access-key-id>" \
  secret_access_key="<your-s3-secret-access-key>" \
  endpoint="https://s3.openshift-storage.svc:443" \
  region="us-east-1" \
  bucket="<your-bucket-name>"
```

> **Field names are fixed.** The ESO templates reference exactly these keys:
> `access_key_id`, `secret_access_key`, `endpoint`, `region`, `bucket`.
> Do not rename them.

**Examples by model:**

```bash
# gpt-oss-20b
vault kv put secret/maas/model-deploy/gpt-oss-20b/s3 \
  access_key_id="<key>" \
  secret_access_key="<secret>" \
  endpoint="https://s3.openshift-storage.svc:443" \
  region="us-east-1" \
  bucket="model-registry-artifacts-p-ccc9b6a9-897a-4971-9161-9c0d25448836"

# tiny-llama-test
vault kv put secret/maas/model-deploy/tiny-llama-test/s3 \
  access_key_id="<key>" \
  secret_access_key="<secret>" \
  endpoint="https://s3.openshift-storage.svc:443" \
  region="us-east-1" \
  bucket="model-registry-artifacts-p-c35fd54c-f447-4959-92d8-120718bbb1a5"
```

Verify the data was stored (Vault masks sensitive values):

```bash
vault kv get secret/maas/model-deploy/<model-name>/s3
```

Expected output:
```
========== Data ==========
Key                Value
---                -----
access_key_id      *** (masked)
bucket             model-registry-artifacts-p-...
endpoint           https://s3.openshift-storage.svc:443
region             us-east-1
secret_access_key  *** (masked)
```

---

## Step 2 — Update Values (Environment Overlay)

Edit the appropriate environment overlay (e.g. `environments/prod/values-gpt-oss-20b.yaml`)
and set the ESO stanza. Leave `s3.accessKeyId`, `s3.secretAccessKey`, `s3.endpoint`,
`s3.region`, and `s3.bucket` empty or commented out — they are ignored in ESO mode.

```yaml
model:
  name: gpt-oss-20b
  namespace: deploy-models

s3:
  modelPath: "gpt-oss-20b-hf/1.0.0"    # still required — used for the model URI
  verifySSL: "0"                          # still required — not stored in Vault
  # accessKeyId, secretAccessKey, endpoint, region, bucket are ignored in ESO mode

  externalSecret:
    enabled: true
    refreshInterval: 1h
    secretStoreRef:
      name: vault-backend           # must match your ClusterSecretStore name
      kind: ClusterSecretStore
    remoteRef:
      key: maas/model-deploy/gpt-oss-20b/s3   # must match the path used in Step 1
```

> **One path per model.** Each model deployment should have its own Vault path
> (`maas/model-deploy/<model-name>/s3`) so credentials can be rotated
> independently without affecting other models sharing the same namespace.

---

## Step 3 — Create or Sync the ArgoCD Application

> ⚠️ **Do not create the ArgoCD Application before completing Steps 1–2.**
> The KServe storage-initializer runs as an init-container and reads the S3
> credentials at pod start time. If either Secret is missing, the init-container
> will fail and the `LLMInferenceService` pod will remain in `Init:Error` state.

```bash
# If the Application already exists, trigger a sync
argocd app sync fusion-maas-model-deploy-prod

# If creating for the first time, the Application will auto-sync on creation
# (assuming syncPolicy.automated is set)
```

ArgoCD deploys resources in this wave order:

```
Wave 0  ClusterRole                              ArgoCD RBAC for ExternalSecret objects
Wave 0  RoleBinding (model namespace)            scoped to deploy-models
Wave 1  ExternalSecret <model>-connection        ESO writes S3 connection Secret
Wave 1  ExternalSecret storage-config            ESO writes KServe storage-config Secret
Wave 2  ServiceAccount                           binds the connection Secret
Wave 2  LLMInferenceService                      KServe init-container pulls model from S3
```

---

## Step 4 — Verify

```bash
# 1. Check both ExternalSecrets — both should show Ready=True
oc get externalsecret -n deploy-models

# 2. Confirm ESO created the S3 connection Secret with the expected keys
oc get secret deploy-models-connection -n deploy-models \
  -o jsonpath='{.data}' | python3 -c \
  "import sys,json; d=json.load(sys.stdin); [print(k) for k in sorted(d)]"
# Expected keys:
# AWS_ACCESS_KEY_ID
# AWS_DEFAULT_REGION
# AWS_S3_BUCKET
# AWS_S3_ENDPOINT
# AWS_SECRET_ACCESS_KEY

# 3. Confirm ESO created the storage-config Secret
oc get secret storage-config -n deploy-models

# 4. Confirm the KServe annotations were stamped correctly on the connection Secret
oc get secret deploy-models-connection -n deploy-models \
  -o jsonpath='{.metadata.annotations}' | python3 -c \
  "import sys,json; d=json.load(sys.stdin); [print(k,'=',v) for k,v in sorted(d.items()) if 'kserve' in k]"
# Expected:
# serving.kserve.io/s3-endpoint = https://s3.openshift-storage.svc:443
# serving.kserve.io/s3-region   = us-east-1
# serving.kserve.io/s3-usehttps = 1

# 5. Confirm the LLMInferenceService pod started successfully (init-container passed)
oc get pods -n deploy-models
```

---

## Testing ESO Without Touching Live Secrets

Before cutting over from manual mode to ESO in production, validate with a
test deployment pointing at the same Vault path. Use a separate environment
overlay or a temporary values file:

```yaml
model:
  name: gpt-oss-20b-eso-test          # safe test name — creates separate resources
  namespace: deploy-models-test       # use a non-production namespace

s3:
  modelPath: "gpt-oss-20b-hf/1.0.0"
  verifySSL: "0"
  externalSecret:
    enabled: true
    refreshInterval: 1h
    secretStoreRef:
      name: vault-backend
      kind: ClusterSecretStore
    remoteRef:
      key: maas/model-deploy/gpt-oss-20b/s3    # reuse the same Vault path
```

Verify the test secrets:

```bash
# Confirm both ExternalSecrets were created
oc get externalsecret -n deploy-models-test

# Spot-check the endpoint annotation (non-sensitive)
oc get secret deploy-models-test-connection -n deploy-models-test \
  -o jsonpath='{.metadata.annotations.serving\.kserve\.io/s3-endpoint}'

# Confirm access_key_id length (do NOT print full value)
oc get secret deploy-models-test-connection -n deploy-models-test \
  -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d | wc -c

# Once confirmed correct — clean up by deleting the ExternalSecrets
# (ESO GCs the owned Secrets automatically because creationPolicy: Owner)
oc delete externalsecret deploy-models-test-connection -n deploy-models-test
oc delete externalsecret storage-config -n deploy-models-test
```

---

## Credential Rotation

With ESO in place, rotating S3 credentials requires **no Git commit and no
ArgoCD sync**.

```bash
# 1. Update the Vault path with the new credentials
vault kv patch secret/maas/model-deploy/<model-name>/s3 \
  access_key_id="<new-access-key-id>" \
  secret_access_key="<new-secret-access-key>"

# 2. Force immediate ESO refresh on the S3 connection ExternalSecret
oc annotate externalsecret deploy-models-connection \
  -n deploy-models \
  force-sync=$(date +%s) --overwrite

# 3. Force immediate ESO refresh on the storage-config ExternalSecret
oc annotate externalsecret storage-config \
  -n deploy-models \
  force-sync=$(date +%s) --overwrite

# 4. The LLMInferenceService picks up the new credentials when the next
#    pod is scheduled. To force an immediate restart:
oc rollout restart llminferenceservice/<model-name> -n deploy-models
```

> **Rotating endpoint, region, or bucket:** Use the same `vault kv patch` command
> for those fields. Because the `serving.kserve.io/s3-endpoint` and
> `serving.kserve.io/s3-region` annotations are stamped by ESO's template engine
> from Vault fields, they will also be updated on the next refresh.

---

## Troubleshooting

### ExternalSecret shows `SecretSyncedError` or status is not `Ready`

```bash
# Inspect conditions on both ExternalSecrets
oc describe externalsecret deploy-models-connection -n deploy-models
oc describe externalsecret storage-config           -n deploy-models

# Common causes:

# 1. ClusterSecretStore not Ready — check ESO operator pods
oc get clustersecretstore vault-backend
oc get pods -n external-secrets-operator

# 2. Vault path does not exist or has wrong name
vault kv get secret/maas/model-deploy/<model-name>/s3

# 3. Wrong field names in Vault — inspect keys actually present
vault kv get -format=json secret/maas/model-deploy/<model-name>/s3 \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d['data']['data'].keys()))"
# Expected: ['access_key_id', 'bucket', 'endpoint', 'region', 'secret_access_key']

# 4. Vault token expired or auth role missing
vault token lookup
```

### ArgoCD sync fails — `forbidden` on ExternalSecret resource

The ArgoCD application-controller ServiceAccount does not have permission to
manage `external-secrets.io` CRs by default. When `s3.externalSecret.enabled: true`,
the chart automatically creates a `ClusterRole` with a namespaced `RoleBinding`
at sync-wave 0 (`templates/argocd-externalsecret-rbac.yaml`).

```bash
# Verify the ClusterRole was created
oc get clusterrole argocd-externalsecret-manager-model-deploy

# Verify the RoleBinding was created in the model namespace
oc get rolebinding argocd-externalsecret-manager-model-deploy \
  -n deploy-models
```

If either is missing, confirm the ESO flag is enabled and the template renders:

```bash
helm template test \
  storage-fusion/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-deploy \
  --values environments/prod/values-gpt-oss-20b.yaml \
  --show-only templates/argocd-externalsecret-rbac.yaml
```

If the output is empty, `s3.externalSecret.enabled` is not `true` in the
values — the RBAC resources are intentionally absent when ESO is not in use.

### LLMInferenceService pod stuck in `Init:Error` after ESO enabled

The KServe storage-initializer init-container reads the `storage-config` Secret
at pod start time. Confirm both Secrets actually exist before the pod is scheduled:

```bash
oc get secret deploy-models-connection -n deploy-models
oc get secret storage-config           -n deploy-models
```

If missing, check the ExternalSecret status:

```bash
oc get externalsecret -n deploy-models
oc describe externalsecret storage-config -n deploy-models
```

Once both Secrets exist, restart the pod:

```bash
oc rollout restart llminferenceservice/<model-name> -n deploy-models
```

### KServe init-container authenticates but downloads from the wrong bucket or endpoint

The `storage-config` Secret contains the KServe JSON blob assembled from Vault
fields. Inspect it to confirm the correct values were pulled:

```bash
oc get secret storage-config -n deploy-models \
  -o jsonpath='{.data.deploy-models-connection}' | base64 -d | python3 -m json.tool
```

Expected output:
```json
{
  "type": "s3",
  "access_key_id":      "...",
  "secret_access_key":  "...",
  "endpoint_url":       "https://s3.openshift-storage.svc:443",
  "region":             "us-east-1",
  "bucket":             "<your-bucket>",
  "cabundle_configmap": "odh-kserve-custom-ca-bundle"
}
```

If any field is wrong, update the Vault path (`vault kv patch ...`) and force
an ESO refresh (see [Credential Rotation](#credential-rotation)).

### `serving.kserve.io/s3-endpoint` annotation on the connection Secret is wrong

The connection Secret's annotations are stamped by ESO's template engine from
the `endpoint` field in Vault — not from `s3.endpoint` in values.yaml (which is
ignored in ESO mode). Inspect the annotation:

```bash
oc get secret deploy-models-connection -n deploy-models \
  -o jsonpath='{.metadata.annotations.serving\.kserve\.io/s3-endpoint}'
```

If it shows an incorrect value, the `endpoint` field in Vault is wrong. Patch
and force a refresh:

```bash
vault kv patch secret/maas/model-deploy/<model-name>/s3 \
  endpoint="https://s3.openshift-storage.svc:443"

oc annotate externalsecret deploy-models-connection \
  -n deploy-models \
  force-sync=$(date +%s) --overwrite
```

---

## Related Documents

- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-model-registry` (Git credentials + Hugging Face token)
- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-platform` (Postgres + DB config)
- [`docs/deploying-external-secrets-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — ESO operator installation
- [`docs/deploying-vault-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — Vault operator installation
- [`models-as-a-service/docs/content/install/maas-setup.md`](../../../../models-as-a-service/docs/content/install/maas-setup.md) — upstream MaaS install guide
