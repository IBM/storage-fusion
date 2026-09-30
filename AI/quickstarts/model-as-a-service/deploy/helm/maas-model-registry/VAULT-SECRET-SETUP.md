# Vault Secret Setup for maas-model-registry ESO Integration

<!-- vault-radar-ignore: documentation file — all values are placeholders, not real credentials -->

This guide covers every step a user must perform **before the first ArgoCD
sync** when using External Secrets Operator (ESO) to manage `maas-model-registry`
secrets. No credentials ever touch Git when this path is followed.

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

`maas-model-registry` uses ESO to manage up to two Kubernetes Secrets depending
on which credential modes are active. Each secret has an independent flag — they
can be enabled individually or together.

| Secret | Namespace | Consumed by | ESO active when |
|--------|-----------|-------------|-----------------|
| `git-credentials` | `.Values.namespace` (e.g. `fusion-model-registry-gitops`) | BuildConfig `sourceSecret` (image build) + `model-sync` CronJob (volume at `/git-credentials`) | `buildConfig.gitCredentials.enabled: true` AND `buildConfig.gitCredentials.externalSecret.enabled: true` |
| `huggingface-token` | `modelRegistry.namespace` (e.g. `rhoai-model-registries`) | Reconciler `_load_hf_token()` — authenticates to Hugging Face Hub for gated model downloads | `huggingface.enabled: true` AND `huggingface.externalSecret.enabled: true` |

### Credential mode summary

| Secret | Mode | ESO flag | Who creates the Secret |
|--------|------|----------|------------------------|
| Git credentials | **Manual** (default) | `externalSecret.enabled: false` | User runs `oc create secret` — pre-created before deploy |
| Git credentials | **ESO / Vault** | `externalSecret.enabled: true` | ESO reads fields from Vault — **no credentials in Git** ✅ |
| Hugging Face token | **Manual** (default) | `externalSecret.enabled: false` | User runs `oc create secret` — pre-created before deploy |
| Hugging Face token | **ESO / Vault** | `externalSecret.enabled: true` | ESO reads token from Vault — **no credentials in Git** ✅ |

> **Important namespace difference:** `git-credentials` lives in the reconciler
> namespace (`.Values.namespace`) because the BuildConfig and CronJob run there.
> `huggingface-token` lives in `modelRegistry.namespace` because the reconciler
> reads it via the Kubernetes API using `self.target_namespace` — it must be
> co-located with the Model Registry.

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

## Scenario A — Git Credentials (BuildConfig + CronJob)

Use this when `buildConfig.gitCredentials.externalSecret.enabled: true`. ESO
reads the Git credentials from Vault and writes them as a Kubernetes Secret
into the reconciler namespace. Both the OpenShift BuildConfig (for building the
reconciler image) and the `model-sync` CronJob (for cloning the model catalog
repo) read the Secret by name.

### Step 1 — Store Git credentials in Vault

Choose the authentication method your Git host requires and store **only the
fields you use**. The ESO template uses `errorPolicy: Ignore` for optional
fields (`token`, `password`, `ssh-privatekey`) so missing fields are silently
skipped rather than causing an error. Only `username` is always required.

**Option 1 — Personal Access Token (most common)**

```bash
vault kv put secret/maas/model-registry-gitops/git-credentials \
  username="<your-git-username>" \
  token="<your-personal-access-token>"
```

**Option 2 — Password authentication**

```bash
vault kv put secret/maas/model-registry-gitops/git-credentials \
  username="<your-git-username>" \
  password="<your-password>"
```

**Option 3 — SSH key authentication**

```bash
vault kv put secret/maas/model-registry-gitops/git-credentials \
  username="<your-git-username>" \
  ssh-privatekey="$(cat ~/.ssh/id_rsa)"
```

> **Field names are fixed.** The ESO template and the CronJob script reference
> exactly these keys: `username`, `token`, `password`, `ssh-privatekey`.
> Do not rename them.

Verify the data was stored:

```bash
vault kv get secret/maas/model-registry-gitops/git-credentials
```

Expected output (token example):
```
====== Data ======
Key        Value
---        -----
token      *** (masked)
username   your-git-username
```

### Step 2 — Update values (environment overlay)

Edit `environments/prod/values.yaml` (or the appropriate environment overlay)
and set:

```yaml
buildConfig:
  gitCredentials:
    enabled: true
    secretName: git-credentials     # keep as-is — CronJob and BuildConfig expect this name
    externalSecret:
      enabled: true                 # ESO will create git-credentials
      refreshInterval: 24h
      secretStoreRef:
        name: vault-backend         # must match your ClusterSecretStore name
        kind: ClusterSecretStore
      targetName: ""                # empty = "git-credentials"
      remoteRef:
        key: maas/model-registry-gitops/git-credentials
```

### Step 3 — Create or sync the ArgoCD Application

> ⚠️ **Do not create the ArgoCD Application before completing Steps 1–2.**
> The `model-sync` CronJob volume mounts `git-credentials` as `optional: true`
> so the CronJob pod will start, but git clone will fail silently without the
> credentials. The BuildConfig will also fail to pull the private repository
> if the secret is missing.

```bash
# If the Application already exists, trigger a sync
argocd app sync fusion-maas-model-registry-prod

# If creating for the first time, the Application will auto-sync on creation
# (assuming syncPolicy.automated is set)
```

ArgoCD will deploy resources in this wave order:

```
Wave 0  ClusterRole + RoleBinding (reconciler ns)   ArgoCD RBAC for ExternalSecret objects
Wave 1  ExternalSecret git-credentials               ESO writes Secret into reconciler namespace
Wave 1  BuildConfig model-reconciler                 uses git-credentials as sourceSecret
Wave 1  CronJob model-sync                           mounts git-credentials at /git-credentials
```

### Step 4 — Verify

```bash
# 1. Check ExternalSecret status — should show Ready=True
oc get externalsecret git-credentials -n fusion-model-registry-gitops

# 2. Confirm ESO created the Secret with the expected keys
oc get secret git-credentials -n fusion-model-registry-gitops \
  -o jsonpath='{.data}' | python3 -c \
  "import sys,json,base64; d=json.load(sys.stdin); [print(k) for k in sorted(d)]"
# Expected keys (only those present in Vault will appear):
# token        (if stored)
# username
# password     (if stored)
# ssh-privatekey (if stored)

# 3. Confirm the username is populated (non-sensitive spot check)
oc get secret git-credentials -n fusion-model-registry-gitops \
  -o jsonpath='{.data.username}' | base64 -d && echo

# 4. Trigger a BuildConfig run to confirm the credentials work
oc start-build model-reconciler -n fusion-model-registry-gitops --follow
```

---

## Scenario B — Hugging Face Token (Reconciler)

Use this when `huggingface.externalSecret.enabled: true`. ESO reads the
Hugging Face access token from Vault and writes it as a Kubernetes Secret
into `modelRegistry.namespace`. The reconciler's `_load_hf_token()` method
reads key `token` from that Secret using the Kubernetes API — required for
downloading gated models (Llama, Mistral, Falcon, etc.).

> **Public models only?** If you only use publicly available Hugging Face
> models, you do not need a token. Leave `huggingface.enabled: false`.

### Step 1 — Store the Hugging Face token in Vault

```bash
vault kv put secret/maas/model-registry-gitops/huggingface \
  token="hf_xxxxxxxxxxxxxxxxxxxx"
```

> **Field name is fixed.** The ESO template and reconciler both reference
> exactly the key `token`. Do not rename it.
>
> **How to get a Hugging Face token:** Log in to [huggingface.co](https://huggingface.co),
> go to **Settings → Access Tokens**, and create a token with `read` scope.
> Accept the model licence agreements for any gated models you intend to use.

Verify the token was stored (Vault masks the actual value):

```bash
vault kv get secret/maas/model-registry-gitops/huggingface
```

Expected output:
```
====== Data ======
Key     Value
---     -----
token   *** (masked)
```

### Step 2 — Update values (environment overlay)

Edit `environments/prod/values.yaml` (or the appropriate environment overlay)
and set:

```yaml
huggingface:
  enabled: true                     # enable HF token injection
  secretName: huggingface-token     # keep as-is — reconciler expects this name
  externalSecret:
    enabled: true                   # ESO will create huggingface-token
    refreshInterval: 24h
    secretStoreRef:
      name: vault-backend           # must match your ClusterSecretStore name
      kind: ClusterSecretStore
    targetName: ""                  # empty = "huggingface-token"
    remoteRef:
      key: maas/model-registry-gitops/huggingface
      property: token               # exact field name in Vault
```

> **Namespace note:** The `huggingface-token` Secret is created in
> `modelRegistry.namespace` (e.g. `rhoai-model-registries`), not the reconciler
> namespace. This matches where the reconciler looks for it. The chart creates
> a separate `RoleBinding` scoped to `modelRegistry.namespace` for the ArgoCD
> application-controller to manage this ExternalSecret.

### Step 3 — Create or sync the ArgoCD Application

> ⚠️ **Do not create the ArgoCD Application before completing Steps 1–2.**
> The reconciler reads the token at startup. If the Secret does not exist when
> the reconciler pod starts, it will log:
> `"No Hugging Face token found (only public models will work)"` and continue
> without authentication — gated model downloads will fail with a 401 error
> from Hugging Face.

```bash
argocd app sync fusion-maas-model-registry-prod
```

ArgoCD will deploy resources in this wave order:

```
Wave 0  ClusterRole                                   ArgoCD RBAC for ExternalSecret objects
Wave 0  RoleBinding (modelRegistry.namespace)         scoped to rhoai-model-registries
Wave 1  ExternalSecret huggingface-token              ESO writes Secret into rhoai-model-registries
Wave 1  Deployment model-reconciler                   reconciler reads token via _load_hf_token()
```

### Step 4 — Verify

```bash
# 1. Check ExternalSecret status — should show Ready=True
oc get externalsecret huggingface-token -n rhoai-model-registries

# 2. Confirm ESO created the Secret with the expected key
oc get secret huggingface-token -n rhoai-model-registries \
  -o jsonpath='{.data}' | python3 -c \
  "import sys,json,base64; d=json.load(sys.stdin); [print(k) for k in sorted(d)]"
# Expected:
# token

# 3. Confirm the token length looks correct (do NOT print the full value in production)
oc get secret huggingface-token -n rhoai-model-registries \
  -o jsonpath='{.data.token}' | base64 -d | wc -c
# A valid HF token is typically 37+ characters

# 4. Restart the reconciler to pick up the new token immediately
oc rollout restart deployment/model-reconciler -n fusion-model-registry-gitops
```

---

## Scenario C — Both Secrets via ESO (full production setup)

When using private Git repositories **and** gated Hugging Face models, complete
Scenario A and Scenario B in sequence before syncing the Application.

### Vault paths required

```bash
# Git credentials
vault kv put secret/maas/model-registry-gitops/git-credentials \
  username="<your-git-username>" \
  token="<your-personal-access-token>"

# Hugging Face token
vault kv put secret/maas/model-registry-gitops/huggingface \
  token="hf_xxxxxxxxxxxxxxxxxxxx"
```

### prod values overlay (both ESO enabled)

```yaml
buildConfig:
  gitCredentials:
    enabled: true
    secretName: git-credentials
    externalSecret:
      enabled: true
      refreshInterval: 24h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      targetName: ""
      remoteRef:
        key: maas/model-registry-gitops/git-credentials

huggingface:
  enabled: true
  secretName: huggingface-token
  externalSecret:
    enabled: true
    refreshInterval: 24h
    secretStoreRef:
      name: vault-backend
      kind: ClusterSecretStore
    targetName: ""
    remoteRef:
      key: maas/model-registry-gitops/huggingface
      property: token
```

When both flags are true, the chart renders:

- `ExternalSecret git-credentials` in `.Values.namespace`
- `ExternalSecret huggingface-token` in `modelRegistry.namespace`
- One shared `ClusterRole` with two namespaced `RoleBindings` (one per namespace)

Then sync:

```bash
argocd app sync fusion-maas-model-registry-prod
```

---

## Testing ESO Without Touching Live Secrets

Before cutting over from manual secrets to ESO, test with safe `targetName`
values so the live secrets are not touched. Both manual and ESO can coexist
when `targetName` is set to a non-default name.

```yaml
buildConfig:
  gitCredentials:
    enabled: true
    externalSecret:
      enabled: true
      targetName: git-credentials-eso-test    # writes here only — safe test

huggingface:
  enabled: true
  externalSecret:
    enabled: true
    targetName: huggingface-token-eso-test    # writes here only — safe test
```

Verify the test secrets:

```bash
# Confirm ESO created the test secrets
oc get secret git-credentials-eso-test -n fusion-model-registry-gitops
oc get secret huggingface-token-eso-test   -n rhoai-model-registries

# Spot-check username (non-sensitive)
oc get secret git-credentials-eso-test -n fusion-model-registry-gitops \
  -o jsonpath='{.data.username}' | base64 -d && echo

# Spot-check token length (do not print full value)
oc get secret huggingface-token-eso-test -n rhoai-model-registries \
  -o jsonpath='{.data.token}' | base64 -d | wc -c

# Once confirmed correct — clean up test secrets by deleting the ExternalSecrets
# (ESO will GC the owned Secrets automatically because creationPolicy: Owner)
oc delete externalsecret git-credentials-eso-test \
  -n fusion-model-registry-gitops
oc delete externalsecret huggingface-token-eso-test \
  -n rhoai-model-registries
```

---

## Credential Rotation

With ESO in place, rotating credentials requires **no Git commit and no ArgoCD
sync**.

### Rotate Git credentials (Scenario A)

```bash
# 1. Update the Vault path with the new token
vault kv patch secret/maas/model-registry-gitops/git-credentials \
  token="<new-personal-access-token>"

# 2. Force immediate ESO refresh (default interval is 24h)
oc annotate externalsecret git-credentials \
  -n fusion-model-registry-gitops \
  force-sync=$(date +%s) --overwrite

# 3. The CronJob and BuildConfig pick up the new Secret on their next run —
#    no pod restart needed (both read the Secret at pod start time).
#    To force an immediate test, trigger a manual build:
oc start-build model-reconciler -n fusion-model-registry-gitops
```

### Rotate Hugging Face token (Scenario B)

```bash
# 1. Generate a new token at huggingface.co/settings/tokens, then update Vault
vault kv patch secret/maas/model-registry-gitops/huggingface \
  token="hf_xxxxxxxxxxxxxxxxxxxx_new"

# 2. Force immediate ESO refresh (default interval is 24h)
oc annotate externalsecret huggingface-token \
  -n rhoai-model-registries \
  force-sync=$(date +%s) --overwrite

# 3. Restart the reconciler to pick up the updated token
oc rollout restart deployment/model-reconciler \
  -n fusion-model-registry-gitops
```

---

## Troubleshooting

### ExternalSecret shows `SecretSyncedError` or status is not `Ready`

```bash
# Inspect the failing ExternalSecret's conditions
oc describe externalsecret git-credentials    -n fusion-model-registry-gitops
oc describe externalsecret huggingface-token  -n rhoai-model-registries

# Common causes:

# 1. ClusterSecretStore not Ready — check ESO operator pods
oc get clustersecretstore vault-backend
oc get pods -n external-secrets-operator

# 2. Vault path does not exist
vault kv get secret/maas/model-registry-gitops/git-credentials
vault kv get secret/maas/model-registry-gitops/huggingface

# 3. Wrong field name in Vault — inspect what keys are present
vault kv get -format=json secret/maas/model-registry-gitops/git-credentials \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d['data']['data'].keys()))"
vault kv get -format=json secret/maas/model-registry-gitops/huggingface \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d['data']['data'].keys()))"

# 4. Vault token expired or auth role missing
vault token lookup
```

### ArgoCD sync fails — `forbidden` on ExternalSecret resource

The ArgoCD application-controller ServiceAccount does not have permission to
manage `external-secrets.io` CRs by default. The chart creates a `ClusterRole`
with namespaced `RoleBinding`(s) automatically at sync-wave 0 when either ESO
flag is enabled (`templates/argocd-externalsecret-rbac.yaml`).

```bash
# Verify the ClusterRole was created
oc get clusterrole argocd-externalsecret-manager-model-registry-gitops

# Verify the RoleBinding(s) were created in the correct namespaces
# For git-credentials ESO:
oc get rolebinding argocd-externalsecret-manager-model-registry-gitops \
  -n fusion-model-registry-gitops

# For huggingface-token ESO:
oc get rolebinding argocd-externalsecret-manager-model-registry-gitops-hf \
  -n rhoai-model-registries
```

If any are missing, confirm the ESO flag is enabled in your values and
verify the template renders:

```bash
helm template test \
  storage-fusion/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-model-registry \
  --values environments/prod/values.yaml \
  --show-only templates/argocd-externalsecret-rbac.yaml
```

If the output is empty, neither `buildConfig.gitCredentials.externalSecret.enabled`
nor `huggingface.externalSecret.enabled` is `true` — the RBAC resources are
intentionally absent when ESO is not in use.

### Git clone fails in the CronJob even after ESO is enabled

The CronJob mounts `git-credentials` with `optional: true`, meaning the pod
starts even if the Secret is absent. Confirm the Secret actually exists:

```bash
oc get secret git-credentials -n fusion-model-registry-gitops
```

If missing, check the ExternalSecret status and conditions:

```bash
oc get externalsecret git-credentials -n fusion-model-registry-gitops
oc describe externalsecret git-credentials -n fusion-model-registry-gitops
```

Once the Secret is present, the next scheduled CronJob run will pick it up.
To test immediately without waiting for the schedule:

```bash
oc create job --from=cronjob/model-sync manual-test-$(date +%s) \
  -n fusion-model-registry-gitops
```

### Reconciler logs `No Hugging Face token found` after enabling ESO

The reconciler reads the token at pod startup. If the pod was already running
when ESO created the Secret, it will not pick up the new token automatically.
Restart the Deployment:

```bash
oc rollout restart deployment/model-reconciler -n fusion-model-registry-gitops
```

Then confirm the reconciler logs no longer show the warning:

```bash
oc logs -n fusion-model-registry-gitops \
  -l app=model-registry-gitops,component=reconciler --tail=30
```

### BuildConfig fails with `authentication required` even after ESO is enabled

The `sourceSecret` reference in the BuildConfig is set at chart render time
(`buildConfig.gitCredentials.secretName`). Confirm the Secret name in the
BuildConfig matches the name ESO created:

```bash
# Check what name BuildConfig expects
oc get buildconfig model-reconciler -n fusion-model-registry-gitops \
  -o jsonpath='{.spec.source.sourceSecret.name}' && echo

# Check what ESO created
oc get secret -n fusion-model-registry-gitops | grep git-credentials
```

If they differ, set `externalSecret.targetName` to match `gitCredentials.secretName`.

---

## Related Documents

- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-runtime/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-runtime` (object storage + database)
- [`VAULT-SECRET-SETUP.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — equivalent guide for `maas-platform` (Postgres + DB config)
- [`docs/deploying-external-secrets-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — ESO operator installation
- [`docs/deploying-vault-guide.md`](https://github.com/IBM/storage-fusion/blob/master/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-platform/VAULT-SECRET-SETUP.md) — Vault operator installation
- [`models-as-a-service/docs/content/install/maas-setup.md`](../../../../models-as-a-service/docs/content/install/maas-setup.md) — upstream MaaS install guide
