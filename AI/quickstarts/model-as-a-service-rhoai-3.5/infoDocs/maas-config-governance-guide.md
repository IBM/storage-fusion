# Configuring Subscription-Based Governance for AI Models on IBM Fusion

Organizations running AI workloads on IBM Fusion face a recurring operational challenge: once models are deployed and serving, there is no automatic mechanism controlling who can call them, how much they can consume, or how those boundaries are enforced as teams and usage grow. Without governance, a single team can exhaust shared GPU capacity, cost attribution becomes impossible, and access control reverts to manual processes that do not scale.

The Model-as-a-Service (MaaS) platform on IBM Fusion solves this through subscription-based governance, a declarative layer that sits between users and the model serving infrastructure running on the cluster. With MaaS, platform engineers define subscriptions that grant groups token-rate-limited access to specific models, enforce those limits through the API gateway, and version-control the entire governance configuration in Git.

This guide covers the `maas-config` component: the Helm chart and ArgoCD manifests that manage MaaS governance resources on IBM Fusion. It is written for platform engineers and AI infrastructure teams who already have models running on the cluster and need to put access control and quota management in place. By the end, you will have `MaaSSubscription` and `MaaSAuthPolicy` resources deployed, understand the multi-environment GitOps pattern used in the IBM Fusion MaaS platform, and be able to extend governance to new models as they are onboarded.

---

## Prerequisites

Before you begin, verify that the IBM Fusion cluster and supporting components satisfy the requirements below.

### Tested With

This guide has been tested and validated with the following software versions:

| Component | Version |
|---|---|
| Red Hat OpenShift AI | `3.5.0-ea.2` (beta channel) |
| Operator package | `rhods-operator.3.5.0-ea.2` |
| OLM channel | `beta` |

> **Note:** This guide uses a pre-release (early access) build of Red Hat OpenShift AI. Behaviour, API fields, and CLI outputs may differ on earlier GA releases. The minimum supported version for the subscription-based governance model described here is Red Hat OpenShift AI 3.4.

### Before You Begin

If you need to deploy the IBM Fusion MaaS platform from scratch or get your first model running, follow [Quickstart: IBM Fusion Model-as-a-Service Platform - GitOps Deployment and Customization](./gitops-deployment-guide_updated%20(2).md) first. That guide covers the full platform bootstrap: operators, storage, model registry, and model deployment on IBM Fusion. Return here once your models are running and their `MaaSModelRef` resources are `Ready`.

### Platform and Access

- **IBM Fusion cluster** with the MaaS platform deployed. Operators, platform, and runtime layers must be healthy before applying governance configuration.
- **Red Hat OpenShift 4.19.9 or later** with cluster-admin access
- **Red Hat OpenShift AI 3.4 or later.** MaaS uses subscription-based governance (replacing the tier-based model from 3.3); API keys with `sk-oai-` prefix are required for model access.
- **OpenShift CLI (`oc`)** - [Install oc](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)
- **ArgoCD CLI (`argocd`) v2.9+** - [Install argocd](https://argo-cd.readthedocs.io/en/stable/cli_installation/)

### MaaS Platform Requirements

- **MaaS enabled** in the `DataScienceCluster` resource:
  ```yaml
  spec:
    components:
      kserve:
        modelsAsService:
          managementState: Managed
  ```
- **Red Hat Connectivity Link Operator v1.2 or later** installed in `openshift-operators` with a `Kuadrant` CR in `kuadrant-system` at `Ready` status
- **Red Hat OpenShift GitOps (ArgoCD)** running in the `openshift-gitops` namespace
- **PostgreSQL database v14 or later** reachable from the cluster network, with a `maas-db-config` secret in `redhat-ods-applications`. Required for API key lifecycle management:
  ```bash
  oc create secret generic maas-db-config \
    -n redhat-ods-applications \
    --from-literal=DB_CONNECTION_URL=postgresql://<user>:<password>@<host>:5432/<db>?sslmode=require
  ```

### Model Requirements

- At least one AI model deployed and serving via `LLMInferenceService` (llm-d distributed inference) or a vLLM runtime, with its `MaaSModelRef` in a `Ready` state
- The model must have been published to MaaS (the `MaaSModelRef` CR must exist in the model's namespace)

### Repository Access

- **GitHub account with write access** to a fork of the [storage-fusion](https://github.com/IBM/storage-fusion) repository. You must push values file and manifest changes before ArgoCD can apply them; read-only access is not sufficient.
- The `maas-config` manifests live at `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/` within the repository

### Verify Your Environment

```bash
# Check OpenShift version
oc version
```

```bash
# Verify cluster-admin access
oc auth can-i '*' '*' --all-namespaces
```

Check MaaS is enabled in the DataScienceCluster
```bash
oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.kserve.modelsAsService.managementState}'
```

**Expected output:**

```text
Managed
```
Check Kuadrant is ready
```bash
oc get kuadrant -n kuadrant-system
```

**Expected output:**

```text
NAME       MTLS AUTHORINO   MTLS LIMITADOR   AGE
kuadrant   false            false            21d
```
Check OpenShift GitOps is running
```bash
oc get pods -n openshift-gitops | grep Running
```
Verify ArgoCD CLI is configured
```bash
argocd version
```
Check that MaaSModelRef resources exist and are Ready
```bash
oc get maasmodelref --all-namespaces
```

---

## The Two Required Custom Resources

MaaS governance is built from exactly two Kubernetes custom resources. Every request a user makes to a model endpoint must pass through both:

1. **`MaaSAuthPolicy`** — the gateway decides whether this user is allowed to call this model at all.
2. **`MaaSSubscription`** — the gateway enforces how many tokens this user can consume per time window.

Both resources live in the `models-as-a-service` namespace and reference the same model by its `MaaSModelRef` name and namespace. They are independent: creating one does not automatically create the other. The [Why Both Are Required](#why-both-are-required) table below shows the exact error each missing resource produces.

The sections below describe each resource, its fields, and the failure modes that result when they are misconfigured or missing.

### MaaSSubscription

A `MaaSSubscription` grants one or more OpenShift groups (or individual users) a configured token rate limit for one or more models. The MaaS controller reconciles this into a `TokenRateLimitPolicy` on the gateway for each referenced model.

```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: maas-prod-subscription
  namespace: models-as-a-service
spec:
  priority: 100           # Higher number = higher precedence when a user belongs to multiple subscriptions
  owner:
    groups:
      - name: rhods-admins
    users: []
  modelRefs:
    - name: gpt-oss-20b-100          # The MaaSModelRef resource name
      namespace: deploy-models       # The namespace where the MaaSModelRef lives
      tokenRateLimits:
        - limit: 10000               # Maximum tokens
          window: "1h"               # Per time window
    - name: tiny-llama-test
      namespace: deploy-models
      tokenRateLimits:
        - limit: 10000
          window: "1h"
```

**Priority** determines which subscription takes precedence when a user belongs to multiple groups with different subscriptions. The recommended scheme:

| Workload type | Priority |
|---|---|
| Production | 100 |
| Staging / pre-production | 50 |
| Development / experimentation | 0 |
| Personal sandbox | -10 |

When a user creates an API key without specifying a subscription, the subscription with the highest priority is selected automatically. Specifying a subscription explicitly bypasses priority selection.

**Token rate limit windows** accept `s` (seconds), `m` (minutes), and `h` (hours). The `d` (days) unit is **not** supported. Use `24h` for one day, `168h` for one week.

Multiple limits can be stacked on a single model reference, for example a per-minute burst limit combined with a per-hour sustained limit:

```yaml
tokenRateLimits:
  - limit: 500
    window: "1m"
  - limit: 10000
    window: "1h"
```

### MaaSAuthPolicy

A `MaaSAuthPolicy` controls gateway-level access. It is the authentication gate that a request must pass before rate limiting is applied. It maps groups (or users) to specific model endpoints.

```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: maas-prod-auth-policy
  namespace: models-as-a-service
spec:
  subjects:
    groups:
      - name: rhods-admins
    users: []
  modelRefs:
    - name: gpt-oss-20b-100
      namespace: deploy-models
    - name: tiny-llama-test
      namespace: deploy-models
  # Optional: billing attribution metadata for cost allocation and showback reporting
  # meteringMetadata:
  #   organizationId: "my-org"
  #   costCenter: "ai-platform"
  #   labels:
  #     team: platform
```

The access logic is **OR**: any matching group or user grants access to **all** listed models in the policy.

The optional `meteringMetadata` block attaches billing attribution data. When present, token consumption metrics are tagged with the specified `organizationId`, `costCenter`, and arbitrary `labels`, enabling cost allocation and showback reporting to finance teams.

### Why Both Are Required

| Scenario | Result |
|---|---|
| `MaaSSubscription` exists, `MaaSAuthPolicy` missing | `403 Forbidden`: gateway blocks the request before rate limiting |
| `MaaSAuthPolicy` exists, `MaaSSubscription` missing | `429 Too Many Requests`: gateway permits the request but no token quota is defined |
| Both exist, groups mismatch | Either `403` or unmetered access depending on which resource is missing the group |
| Both exist and aligned | `200 OK` |

---

## The maas-config Helm Chart

The `maas-config` Helm chart encodes `MaaSSubscription`, `MaaSAuthPolicy`, and `OpenShift Group` resources as Helm templates driven by values files. This makes the entire governance configuration version-controlled, auditable, and deployable through ArgoCD. The chart is the only file you edit when adding models, changing token limits, or updating group membership.

### Chart Structure

```
deploy/helm/maas-config/
├── Chart.yaml
├── values.yaml                                    # Schema + empty list defaults
├── templates/
│   ├── _helpers.tpl                               # Shared label/annotation helpers
│   ├── maassubscription.yaml                      # Iterates .Values.subscriptions[]
│   ├── maasauthpolicy.yaml                        # Iterates .Values.authPolicies[]
│   └── groups.yaml                                # Iterates .Values.groups[]
└── environments/
    ├── CHANGELOG.md
    ├── dev/
    │   └── values.yaml                            # Dev overrides (5,000 tokens/hr)
    ├── staging/
    │   └── values.yaml                            # Staging overrides (8,000 tokens/hr)
    └── prod/
        └── values-prod.yaml                       # Prod overrides: all models (10,000 tokens/hr each)
```

The base `values.yaml` contains only empty list defaults:

```yaml
subscriptions: []
authPolicies: []
groups: []
```

All real configuration lives in environment-specific override files. ArgoCD passes both the base `values.yaml` and the environment override to Helm when rendering the chart.

### values.yaml Schema Reference

The annotated blocks below cover every supported field. For worked examples across all three environments (dev, staging, prod), dry-run render commands, and guidance on adding models or subscriptions, see the [maas-config Helm chart README](../deploy/helm/maas-config/README.md).

#### Subscription

```yaml
subscriptions:
  - name: <subscription-resource-name>        # Kubernetes resource name: lowercase, hyphens
    displayName: "<human-readable label>"
    description: "<optional description>"
    priority: 100                              # Integer; higher = higher precedence
    groups:                                    # OpenShift Group names (or OIDC group names)
      - <group-name>
    users: []                                  # Individual OpenShift usernames (optional)
    modelRefs:
      - name: <MaaSModelRef-resource-name>     # Name of the MaaSModelRef CR
        namespace: <model-namespace>           # Namespace where the MaaSModelRef lives
        tokenRateLimits:
          - limit: 10000                       # Token count
            window: "1h"                       # s / m / h only; 'd' is NOT supported
```

#### Authorization Policy

```yaml
authPolicies:
  - name: <policy-resource-name>
    description: "<optional description>"
    groups:
      - <group-name>
    users: []
    modelRefs:
      - name: <MaaSModelRef-resource-name>
        namespace: <model-namespace>
    meteringMetadata:                          # Optional; omit block if not needed
      organizationId: ""
      costCenter: ""
      labels: {}
```

#### OpenShift Group

The `groups` template renders a full `user.openshift.io/v1 Group` manifest for each entry. Behaviour depends on whether the Group already exists on the cluster:

- **New group** (not yet on the cluster): Kubernetes creates it with the specified `users` list. Use this to create custom groups alongside the OpenShift AI defaults.
- **Existing group** (e.g. `rhods-admins` pre-created by OpenShift AI): ArgoCD applies via `ServerSideApply`, reconciling **only** the `users` field owned by this chart. All other fields managed by other controllers are left untouched.

```yaml
groups:
  # Pre-existing group (OpenShift AI): only users list is patched via ServerSideApply
  - name: rhods-admins
    description: "OpenShift AI administrators"
    users:
      - alice                                 # OpenShift usernames (oc whoami / oc get users)
      - bob
  - name: model-registry-users
    description: "Users with Model Registry access"
    users: []
  # New custom group: created by this chart on first sync if it does not exist
  - name: my-team-group
    description: "Custom group for my team's model access"
    users:
      - carol
```


## Deployment Steps

**All steps in this guide target the `prod` environment.** All paths, filenames, and ArgoCD application names are prod-specific. For `dev` or `staging`, replace `prod` accordingly. Full dev and staging values file examples are in the [MaaS Config Helm chart README](../deploy/helm/maas-config/README.md).

**Production sync policy:** Production uses **manual sync with no automated prune**. Governance resources are only removed from production during a deliberate manual sync in an approved change window. ArgoCD will never silently delete a subscription or auth policy on its own.

### Sync Wave Context

`maas-config` runs in ArgoCD sync **wave 300**, after the model deploy layer in wave 200. The `MaaSModelRef` resources created by `maas-model-deploy` must be `Ready` before this layer reconciles. If you apply `maas-config` before the models are healthy, the subscriptions and auth policies will fail to activate.

```
Wave 200  →  maas-model-deploy   (LLMInferenceService + MaaSModelRef per model)
                  ↓  MaaSModelRef must be Ready
Wave 300  →  maas-config         (MaaSSubscription + MaaSAuthPolicy for all models)
```

| Environment | Application name | Auto Sync | Prune | Namespace |
|---|---|---|---|---|
| **Dev** | `fusion-maas-governance-config-dev` | Automated with self-heal | Yes | `models-as-a-service` |
| **Staging** | `fusion-maas-governance-config-staging` | Manual | Yes | `models-as-a-service` |
| **Prod** | `fusion-maas-governance-config-prod` | Manual | No | `models-as-a-service` |

---

### Step 1: Fork and Clone the Repository

The `maas-config` manifests and Helm chart live in the [storage-fusion](https://github.com/IBM/storage-fusion) repository under `AI/AI/quickstarts/model-as-a-service-rhoai-3.5`.

**Fork the repository:**

Fork [https://github.com/IBM/storage-fusion](https://github.com/IBM/storage-fusion) to your GitHub account or organization.

**Clone your fork:**

```bash
git clone git@github.com:<your-username>/storage-fusion.git
cd storage-fusion/AI/quickstarts/model-as-a-service
```

The `maas-config` files are located at:
- Helm chart: `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/`
- GitOps manifests: `AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-config/`

---

### Step 2: Verify Prerequisites

Before applying any manifests, confirm the model deploy layer is healthy and the `MaaSModelRef` resources exist for every model you intend to govern:

```bash
# Verify MaaSModelRef resources are Ready
oc get maasmodelref -n deploy-models
```

**Expected output:**

```text
NAME              PHASE   ENDPOINT                                                                                                         HTTPROUTE                        GATEWAY                AGE
gpt-oss-20b-100   Ready   https://maas-default-gateway-openshift-default.openshift-ingress.svc.cluster.local/deploy-models/gpt-oss-20b-100   gpt-oss-20b-100-kserve-route   maas-default-gateway   10m
tiny-llama-test   Ready   https://maas-default-gateway-openshift-default.openshift-ingress.svc.cluster.local/deploy-models/tiny-llama-test   tiny-llama-test-kserve-route   maas-default-gateway   10m
```

```bash
# Verify ArgoCD is running
oc get pods -n openshift-gitops | grep Running
```

If any `MaaSModelRef` is missing, see [Adding Governance for a New Model](#adding-governance-for-a-new-model).

---

### Step 3: Configure the Values File

The production governance pattern uses **one ArgoCD Application governing all models** through a single shared values file:

```
appproject-prod.yaml
  └── application-governance-prod.yaml    →  environments/prod/values-prod.yaml
                                                ├── MaaSSubscription  maas-prod-subscription
                                                │     modelRefs: [gpt-oss-20b-100, tiny-llama-test]
                                                └── MaaSAuthPolicy    maas-prod-auth-policy
                                                      modelRefs: [gpt-oss-20b-100, tiny-llama-test]
```

Edit `deploy/helm/maas-config/environments/prod/values-prod.yaml` with your model names, namespaces, groups, and token limits. For dev and staging override examples and a full field reference, see the [maas-config Helm chart README](../deploy/helm/maas-config/README.md).

```yaml
maasNamespace: models-as-a-service

subscriptions:
  - name: maas-prod-subscription
    displayName: "MaaS Production Subscription"
    description: "Production subscription covering all MaaS-governed models"
    priority: 100
    groups:
      - rhods-admins
    users: []
    modelRefs:
      - name: gpt-oss-20b-100           # MaaSModelRef name in deploy-models namespace
        namespace: deploy-models
        tokenRateLimits:
          - limit: 10000
            window: "1h"
      - name: tiny-llama-test           # MaaSModelRef name in deploy-models namespace
        namespace: deploy-models
        tokenRateLimits:
          - limit: 10000
            window: "1h"

authPolicies:
  - name: maas-prod-auth-policy
    description: "Auth policy granting rhods-admins access to all production MaaS models"
    groups:
      - rhods-admins
    users: []
    modelRefs:
      - name: gpt-oss-20b-100
        namespace: deploy-models
      - name: tiny-llama-test
        namespace: deploy-models

# Group membership: declare ALL groups, including ones you are not changing
groups:
  - name: rhods-admins
    description: "OpenShift AI administrators"
    users:
      - dev_user1
      - dev_user2
      - prod_user1
  - name: model-registry-users
    description: "Users with Model Registry access"
    users: []

labels:
  environment: prod
```

Key fields to confirm or change:

| Field | What to set |
|---|---|
| `subscriptions[].groups` | Your OpenShift group names |
| `subscriptions[].modelRefs[].name` | Output of `oc get maasmodelref -n <namespace>` |
| `subscriptions[].modelRefs[].namespace` | Namespace where the `MaaSModelRef` lives |
| `subscriptions[].modelRefs[].tokenRateLimits[].limit` | Token quota per window |
| `authPolicies[].groups` | Must match `subscriptions[].groups` exactly |
| `authPolicies[].modelRefs` | Must match `subscriptions[].modelRefs` (name + namespace) |
| `groups[].users` | OpenShift usernames for group membership |

**Render locally to confirm the output before committing:**

```bash
helm template maas-config \
  AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config \
  -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/values.yaml \
  -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/environments/prod/values-prod.yaml
```

---

### Step 4: Update Application Manifests

The single ArgoCD Application manifest is at `deploy/gitops/maas-config/environments/prod/application-governance-prod.yaml`. Update the `repoURL` and `targetRevision` in the `source` block to reference your fork:

```yaml
# In application-governance-prod.yaml
spec:
  source:
    repoURL: https://github.com/<your-username>/storage-fusion.git       # update
    targetRevision: master                                                  # update if needed
    path: AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config
    helm:
      valueFiles:
        - values.yaml
        - environments/prod/values-prod.yaml
```

**File to update:**

| File | Application name |
|---|---|
| `environments/prod/application-governance-prod.yaml` | `fusion-maas-governance-config-prod` |

**If `appproject-prod.yaml` has an explicit `sourceRepos` allowlist** (not a wildcard), add your fork URL there too. ArgoCD will reject syncs from an unlisted repo:

```yaml
# environments/prod/appproject-prod.yaml (excerpt)
spec:
  sourceRepos:
    - https://github.com/IBM/storage-fusion.git          # existing
    - https://github.com/<your-username>/storage-fusion.git  # add your fork
```

---

### Step 5: Commit and Push

Since this is a GitOps deployment, ArgoCD pulls configuration from your Git repository. Commit and push all changes before applying:

```bash
git add AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-config/environments/prod/
git add AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/environments/prod/
git commit -m "Configure maas-config governance for production: all models"
git push
```

> ArgoCD reads the Helm chart and values files directly from Git. Changes that are not pushed will not be applied to the cluster.

---

### Step 6: Deploy the AppProject

Apply the `AppProject` that governs RBAC for the production `maas-config` Application. This only needs to be applied once per cluster:

```bash
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-config/environments/prod/appproject-prod.yaml
```

This creates the `fusion-maas-governance-config-prod` AppProject which defines:
- Source repository allowlist
- Destination namespace permissions
- RBAC roles for `maas-admins` (full access) and `maas-viewers` (read-only)

**Verify:**

```bash
oc get appproject fusion-maas-governance-config-prod -n openshift-gitops
```

**Expected output:**

```text
NAME                                 AGE
fusion-maas-governance-config-prod   1m
```

---

### Step 7: Register the Application with ArgoCD

Apply the governance Application manifest to register it with ArgoCD. This does not sync resources to the cluster yet. It only tells ArgoCD that the Application exists and where to find its configuration:

```bash
oc apply -f AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-config/environments/prod/application-governance-prod.yaml
```

**Verify ArgoCD has registered the Application:**

```bash
oc get applications.argoproj.io -n openshift-gitops | grep fusion-maas-governance
```

**Expected output:**

```text
fusion-maas-governance-config-prod    OutOfSync   Healthy
```

`OutOfSync` is expected at this point. The `MaaSSubscription`, `MaaSAuthPolicy`, and `Group` resources do not yet exist on the cluster.

---

### Step 8: Sync the Application

Production uses **manual sync** for change control. Sync the Application during your approved change window:

```bash
argocd app sync fusion-maas-governance-config-prod
```

Alternatively, sync through the **OpenShift GitOps UI**:
1. Open the ArgoCD console
2. Locate `fusion-maas-governance-config-prod`
3. Click **Diff** to review the resources that will be created
4. Click **Sync → Synchronize**

**Wait for the Application to reach `Synced / Healthy`:**

```bash
# Watch sync progress
oc get applications.argoproj.io fusion-maas-governance-config-prod \
  -n openshift-gitops -w
```

**Expected output once sync completes:**

```text
fusion-maas-governance-config-prod    Synced   Healthy
```

> The `--prune` flag removes cluster resources that are no longer present in Git. **Do not use `--prune` on the first sync** or in production without verifying the Git state is complete and correct.

---

### Step 9: Verify Governance Resources

Confirm the `MaaSSubscription`, `MaaSAuthPolicy`, and `Group` resources were created and are active:

```bash
# List all subscriptions
oc get maassubscription -n models-as-a-service

# List all auth policies
oc get maasauthpolicy -n models-as-a-service
```

**Expected output:**

```text
NAME                     PHASE    PRIORITY   AGE
maas-prod-subscription   Active   100        2m

NAME                    PHASE    AGE
maas-prod-auth-policy   Active   2m
```

```bash
# Verify both resources reference the same models
oc get maassubscription maas-prod-subscription -n models-as-a-service \
  -o jsonpath='{.spec.modelRefs[*].name}'

oc get maasauthpolicy maas-prod-auth-policy -n models-as-a-service \
  -o jsonpath='{.spec.modelRefs[*].name}'
```

**Expected output (both):**

```text
gpt-oss-20b-100 tiny-llama-test
```

```bash
# Verify the same groups are referenced in both resources
oc get maassubscription maas-prod-subscription -n models-as-a-service \
  -o jsonpath='{.spec.owner.groups[*].name}'

oc get maasauthpolicy maas-prod-auth-policy -n models-as-a-service \
  -o jsonpath='{.spec.subjects.groups[*].name}'
```

**Expected output (both):**

```text
rhods-admins
```

```bash
# Verify group membership
oc get group rhods-admins -o jsonpath='{.users}'
```

**Expected output:**

```text
["dev_user1","dev_user2","prod_user1"]
```

```bash
# Confirm the TokenRateLimitPolicies were created by the MaaS controller (one per model)
oc get tokenratelimitpolicy -n deploy-models
```

**Expected output:**

```text
NAME                          AGE
maas-trlp-gpt-oss-20b-100    2m
maas-trlp-tiny-llama-test     2m
```

```bash
# Confirm the MaaS Tenant is healthy (overall platform status)
oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

**Expected output:**

```text
True
```

If any resource is missing or the status shows `False`, see the [Troubleshooting](#troubleshooting) section.

---

### Step 10: Create and Verify API Keys

Platform engineers configure governance resources (Steps 1–9). End users create their own API keys to authenticate inference requests. Administrators can also create keys on behalf of users. API keys carry the `sk-oai-` prefix, are bound to a specific subscription at creation time, and cannot be retrieved after the creation response — save them immediately.

#### Resolve the MaaS gateway URL

All API key and inference operations share the same base gateway URL.

**Cluster administrators** (who have permission to read cluster-scoped resources) can resolve it dynamically:

```bash
MAAS_HOST="maas.$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')"
echo "Gateway: https://${MAAS_HOST}"
```

**Expected output:**

```text
Gateway: https://maas.apps.f55l020.fusion.tadn.ibm.com
```

> **Note:** Regular users (non-admin) do not have permission to read `ingresses.config.openshift.io`. Your platform engineer must provide the gateway hostname. Export it before running any of the following commands:
>
> ```bash
> export MAAS_HOST="maas.apps.f55l020.fusion.tadn.ibm.com"
> ```

#### Option A: Dashboard (recommended for OpenShift-authenticated users)

1. Log in to the OpenShift AI dashboard.
2. Click **Gen AI Studio → API keys**.
3. Click **Create API key**.
4. Fill in:
   - **Name**: descriptive identifier (e.g. `prod-chatbot`, `notebook-testing`)
   - **Subscription**: select from the dropdown; the Models section shows which models and token limits apply
   - **Expiration**: 1-365 days, or **Never**; default is 30 days (max is set by the Tenant CR, default 90 days)
5. Click **Create**.
6. **Copy the key immediately.** It is displayed only once and cannot be retrieved later.

> **Important:** Group membership is captured at key creation time. If a user's group changes after key creation, revoke the old key and create a new one to reflect the updated membership.

#### Option B: CLI / REST API (for external OIDC users or automation)

```bash
# Step 1: Obtain an authentication token
AUTH_TOKEN=$(oc whoami -t)

# Step 1 (alternative): External OIDC users
# AUTH_TOKEN=$(curl -X POST "<oidc-token-endpoint>" \
#   -d "client_id=<id>" -d "client_secret=<secret>" \
#   -d "grant_type=client_credentials" | jq -r .access_token)
```

```bash
# Step 2: List available subscriptions (choose the one to bind the key to)
curl -s -X GET "https://${MAAS_HOST}/maas-api/v1/subscriptions" \
  -H "Authorization: Bearer ${AUTH_TOKEN}"
```

**Expected output:**

```json
[
  {
    "subscription_id_header": "maas-prod-subscription",
    "display_name": "MaaS Production Subscription",
    "subscription_description": "Production subscription covering all MaaS-governed models",
    "priority": 100,
    "model_refs": [
      {
        "name": "gpt-oss-20b-100",
        "namespace": "deploy-models",
        "token_rate_limits": [{ "limit": 10000, "window": "1h" }]
      },
      {
        "name": "tiny-llama-test",
        "namespace": "deploy-models",
        "token_rate_limits": [{ "limit": 10000, "window": "1h" }]
      }
    ]
  }
]
```

> **Note:** The subscriptions endpoint returns only subscriptions whose groups include the authenticated user. `kube:admin` is not a member of `rhods-admins` and will see an empty list `[]`. Log in as a user who belongs to the subscription group (e.g. `dev_user1`) to see the subscription.

```bash
# Step 3: Create an API key bound to a subscription
curl -s -X POST "https://${MAAS_HOST}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-prod-key",
    "subscription": "maas-prod-subscription",
    "expiresIn": "30d"
  }'
# Copy the "key" field from the response. It is shown only once.
```

**Expected output (HTTP 201):**

```json
{
  "key": "sk-oai-xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "keyPrefix": "sk-oai-xxxxxxxxx...",
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "name": "my-prod-key",
  "subscription": "maas-prod-subscription",
  "createdAt": "2026-07-30T09:00:00Z",
  "expiresAt": "2026-08-29T09:00:00Z",
  "ephemeral": false
}
```

> **`expiresIn`** accepts duration strings: `30d`, `90d`, `1h`, `24h`. Omit for the default (subject to the Tenant CR `maxExpirationDays` limit, default 90 days).

#### List, inspect, and revoke keys

```bash
# List your API keys with search (filter by status: active, revoked, expired)
curl -s -X POST "https://${MAAS_HOST}/maas-api/v1/api-keys/search" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "filters": {"status": ["active"]},
    "sort": {"by": "created_at", "order": "desc"},
    "pagination": {"limit": 20, "offset": 0}
  }'
```

**Expected output (HTTP 200):**

```json
{
  "object": "list",
  "data": [
    {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "my-prod-key",
      "username": "dev_user1",
      "subscription": "maas-prod-subscription",
      "creationDate": "2026-07-30T09:00:00Z",
      "expirationDate": "2026-08-29T09:00:00Z",
      "status": "active",
      "lastUsedAt": "2026-07-30T09:05:00Z",
      "ephemeral": false
    }
  ],
  "has_more": false
}
```

```bash
# Inspect a specific key by ID
curl -s "https://${MAAS_HOST}/maas-api/v1/api-keys/<key-id>" \
  -H "Authorization: Bearer ${AUTH_TOKEN}"
```

**Expected output (HTTP 200):**

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "name": "my-prod-key",
  "username": "dev_user1",
  "subscription": "maas-prod-subscription",
  "creationDate": "2026-07-30T09:00:00Z",
  "expirationDate": "2026-08-29T09:00:00Z",
  "status": "active",
  "ephemeral": false
}
```

```bash
# Revoke a specific key by ID
curl -s -X DELETE "https://${MAAS_HOST}/maas-api/v1/api-keys/<key-id>" \
  -H "Authorization: Bearer ${AUTH_TOKEN}"
```

**Expected output (HTTP 200):** The full key object is returned with `"status": "revoked"`:

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "name": "my-prod-key",
  "username": "dev_user1",
  "subscription": "maas-prod-subscription",
  "creationDate": "2026-07-30T09:00:00Z",
  "expirationDate": "2026-08-29T09:00:00Z",
  "status": "revoked",
  "ephemeral": false
}
```

```bash
# Verify the revoked key is rejected at the gateway
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer <revoked-sk-oai-key>" \
  "https://${MAAS_HOST}/maas-api/v1/models"
```

**Expected output:**

```text
403
```

> **Note:** A revoked key returns `403 Forbidden` (not `401`) because the gateway validates the key at the authorization policy layer after the request reaches MaaS.

#### Verify the key grants model access

```bash
# Export the key created above
export MAAS_API_KEY="<your-sk-oai-...key>"

# List models accessible through the subscription bound to this key
curl -s -H "Authorization: Bearer ${MAAS_API_KEY}" \
  "https://${MAAS_HOST}/maas-api/v1/models" | jq '.data[].id'
```

**Expected output:**

```text
"gpt-oss-20b-100"
"tiny-llama-test"
```

**Expected key status values:**

| Status | Meaning |
|---|---|
| `active` | Key is valid and can authenticate requests |
| `expired` | Key has passed its expiration date. Create a new one. |
| `revoked` | Key was manually revoked. Create a new one. Returns `403` on use. |

---

### Step 11: Test Model Access

With an active API key, confirm inference works end-to-end:

> **Inference path format:** The MaaS gateway routes inference requests using the pattern `/<model-namespace>/<model-name>/v1/...`. Obtain the exact URL from `GET /maas-api/v1/models` → `data[].url`, or construct it as `https://${MAAS_HOST}/deploy-models/<model-name>/v1/...` for models deployed in the `deploy-models` namespace.

```bash
# Confirm the exact inference URL for each model (MAAS_HOST and MAAS_API_KEY set in Step 10)
curl -s -H "Authorization: Bearer ${MAAS_API_KEY}" \
  "https://${MAAS_HOST}/maas-api/v1/models" | jq '.data[] | {id, url, ready}'
```

**Expected output:**

```json
{
  "id": "gpt-oss-20b-100",
  "url": "https://maas-default-gateway-openshift-default.openshift-ingress.svc.cluster.local/deploy-models/gpt-oss-20b-100",
  "ready": true
}
{
  "id": "tiny-llama-test",
  "url": "https://maas-default-gateway-openshift-default.openshift-ingress.svc.cluster.local/deploy-models/tiny-llama-test",
  "ready": true
}
```

> **Note:** The `url` field shows the internal cluster service URL. Use the external gateway host (`$MAAS_HOST`) with the path `/deploy-models/<model-name>/v1/...` for all inference requests.

```bash
# Send an inference request to tiny-llama-test
curl -s \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  "https://${MAAS_HOST}/deploy-models/tiny-llama-test/v1/chat/completions" \
  -d '{
    "model": "tiny-llama-test",
    "messages": [{"role": "user", "content": "Hello, what can you do?"}],
    "max_tokens": 100
  }'
```

**Expected output (HTTP 200):**

```json
{
  "id": "chatcmpl-8c9234cd-974b-45b0-8657-077c5b074723",
  "object": "chat.completion",
  "created": 1785407514,
  "model": "tiny-llama-test",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "I can answer your questions, help you understand topics, assist with writing, summarise content, and more."
      },
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 22,
    "completion_tokens": 100,
    "total_tokens": 122
  }
}
```

```bash
# Send an inference request to gpt-oss-20b-100
curl -s \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  "https://${MAAS_HOST}/deploy-models/gpt-oss-20b-100/v1/chat/completions" \
  -d '{
    "model": "gpt-oss-20b-100",
    "messages": [{"role": "user", "content": "Hello, what can you do?"}],
    "max_tokens": 100
  }'
```

**Expected output (HTTP 200):** Same response structure as above with `"model": "gpt-oss-20b-100"`.

**Expected responses:**

| HTTP Status | Meaning |
|---|---|
| `200 OK` | Both `MaaSSubscription` and `MaaSAuthPolicy` are active and aligned |
| `403 Forbidden` | API key is revoked, or `MaaSAuthPolicy` is missing / does not include the user's group |
| `404 Not Found` | Inference path is wrong — check the model namespace in the URL |
| `429 Too Many Requests` | `MaaSSubscription` is missing or token quota is exhausted |

**Verify rate limiting is enforced** with a burst test:

```bash
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -H "Authorization: Bearer ${MAAS_API_KEY}" \
    -H "Content-Type: application/json" \
    "https://${MAAS_HOST}/deploy-models/tiny-llama-test/v1/chat/completions" \
    -d '{"model":"tiny-llama-test","messages":[{"role":"user","content":"test"}],"max_tokens":50}'
done | sort | uniq -c
```

**Expected output:**

```text
     18 200
      2 429
```

A mix of `200` and `429` responses confirms the `TokenRateLimitPolicy` is active and enforced by the gateway. The exact split depends on token consumption per request relative to the 10,000 token/hr quota.

---

## Adding Governance for a New Model

When you onboard a new model to the IBM Fusion MaaS platform and want to expose it through the gateway, the production governance pattern requires only a single-file change: append a `modelRefs` entry to both lists in `values-prod.yaml` and sync.

**Step 1: Confirm the MaaSModelRef is Ready**

The `MaaSModelRef` is created automatically when you publish a model to MaaS (either via the IBM Fusion AI dashboard wizard or by deploying through the `maas-model-deploy` chart with `maasModelRef.enabled: true`). Verify it exists before creating governance resources:

```bash
oc get maasmodelref -n <model-namespace>
```

**Expected output:**

```text
NAME                READY   AGE
my-new-model-ref    True    2m
```

If the `MaaSModelRef` is not present, the model has not been published to MaaS yet. In the dashboard, under **Advanced settings → Model availability**, select **Publish as MaaS** when deploying the model.

**Step 2: Add the model to `values-prod.yaml`**

Append a new entry to `modelRefs` under both `subscriptions[0]` and `authPolicies[0]` in `environments/prod/values-prod.yaml`:

```yaml
subscriptions:
  - name: maas-prod-subscription
    # ... existing fields ...
    modelRefs:
      - name: gpt-oss-20b-100
        namespace: deploy-models
        tokenRateLimits:
          - limit: 10000
            window: "1h"
      - name: tiny-llama-test
        namespace: deploy-models
        tokenRateLimits:
          - limit: 10000
            window: "1h"
      # add new model here
      - name: <maasmodelref-resource-name>   # From: oc get maasmodelref -n <namespace>
        namespace: <model-namespace>
        tokenRateLimits:
          - limit: 10000
            window: "1h"

authPolicies:
  - name: maas-prod-auth-policy
    # ... existing fields ...
    modelRefs:
      - name: gpt-oss-20b-100
        namespace: deploy-models
      - name: tiny-llama-test
        namespace: deploy-models
      # add new model here
      - name: <maasmodelref-resource-name>
        namespace: <model-namespace>
```

**Step 3: Commit, push, and sync**

```bash
# Commit the updated values file
git add AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/environments/prod/values-prod.yaml
git commit -m "Add governance for <model-name> to maas-prod-subscription and maas-prod-auth-policy"
git push

# Sync during your approved change window
argocd app sync fusion-maas-governance-config-prod
```

**Step 4: Verify**

```bash
# Confirm the subscription now references the new model
oc get maassubscription maas-prod-subscription -n models-as-a-service \
  -o jsonpath='{.spec.modelRefs[*].name}'
```

**Expected output** (showing all models including the newly added one):

```text
gpt-oss-20b-100 tiny-llama-test <new-model-name>
```

```bash
# Confirm the auth policy now references the new model
oc get maasauthpolicy maas-prod-auth-policy -n models-as-a-service \
  -o jsonpath='{.spec.modelRefs[*].name}'
```

**Expected output:**

```text
gpt-oss-20b-100 tiny-llama-test <new-model-name>
```

---

## Troubleshooting

### Application is OutOfSync on MaaSSubscription or MaaSAuthPolicy

The MaaS controller writes status fields back to these resources after creation. Without the `ignoreDifferences` block, ArgoCD treats these controller-managed fields as drift and continuously marks the application as `OutOfSync`.

Verify the `ignoreDifferences` block is present in the Application manifest and that `RespectIgnoreDifferences=true` is in `syncOptions`:

```bash
oc get applications.argoproj.io fusion-maas-governance-config-prod \
  -n openshift-gitops -o jsonpath='{.spec.ignoreDifferences}'
```

**Expected output:**

```json
[
  {"group":"maas.opendatahub.io","jsonPointers":["/status"],"kind":"MaaSSubscription"},
  {"group":"maas.opendatahub.io","jsonPointers":["/status"],"kind":"MaaSAuthPolicy"},
  {"group":"user.openshift.io","jsonPointers":["/status","/metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration"],"kind":"Group"}
]
```

If the block is missing, re-apply the corrected Application manifest.

### Subscription or AuthPolicy fails to activate: MaaSModelRef not found

The governance resources reference a `MaaSModelRef` by name and namespace. If the `MaaSModelRef` does not exist, the subscription and auth policy will not become active.

```bash
# Check the model ref exists
oc get maasmodelref -n deploy-models

# Check MaaS controller logs for reconciliation errors
oc logs -n redhat-ods-applications -l app=maas-controller --tail=50
```

**Expected output (both models healthy):**

```text
NAME              PHASE   ENDPOINT                                                                                                         HTTPROUTE                        GATEWAY                AGE
gpt-oss-20b-100   Ready   https://maas-default-gateway-openshift-default.openshift-ingress.svc.cluster.local/deploy-models/gpt-oss-20b-100   gpt-oss-20b-100-kserve-route   maas-default-gateway   10m
tiny-llama-test   Ready   https://maas-default-gateway-openshift-default.openshift-ingress.svc.cluster.local/deploy-models/tiny-llama-test   tiny-llama-test-kserve-route   maas-default-gateway   10m
```

If the `MaaSModelRef` is missing, the model has not been published to MaaS. Re-deploy the model with the MaaS publish option enabled or ensure `maasModelRef.enabled: true` is set in the `maas-model-deploy` chart values.

### Users get 403 Forbidden

The `MaaSAuthPolicy` is either missing or does not include the user's group.

```bash
# Check the policy exists and which groups it covers
oc get maasauthpolicy -n models-as-a-service
oc get maasauthpolicy maas-prod-auth-policy -n models-as-a-service \
  -o jsonpath='{.spec.subjects.groups[*].name}'

# Check the user's group membership
oc get group rhods-admins -o jsonpath='{.users}'
```

**Expected output:**

```text
NAME                    PHASE    AGE
maas-prod-auth-policy   Active   10m

rhods-admins

["dev_user1","dev_user2","prod_user1"]
```

If the user's group is absent from the auth policy, add it to the `authPolicies[].groups` list in `values-prod.yaml` and re-sync.

### Users get 429 Too Many Requests

The `MaaSSubscription` is missing, the configured token limit is exhausted, or the user's group is not in the subscription.

```bash
# Check the subscription exists, which groups it covers, and that the TRLP was created
oc get maassubscription -n models-as-a-service
oc get maassubscription maas-prod-subscription -n models-as-a-service \
  -o jsonpath='{.spec.owner.groups[*].name}'
oc get tokenratelimitpolicy -n deploy-models
```

**Expected output:**

```text
NAME                     PHASE    PRIORITY   AGE
maas-prod-subscription   Active   100        10m

rhods-admins

NAME                          AGE
maas-trlp-gpt-oss-20b-100    10m
maas-trlp-tiny-llama-test     10m
```

If the token limit has been legitimately exhausted, adjust the `limit` value in `values-prod.yaml`, commit, and re-sync. If the subscription is missing the user's group, add it to `subscriptions[].groups`.

### Subscription and auth policy are out of sync

After editing a subscription to add or remove groups or models, the corresponding auth policy must be updated manually to match.

```bash
# Compare groups in both resources — outputs must be identical
oc get maassubscription maas-prod-subscription -n models-as-a-service \
  -o jsonpath='{.spec.owner.groups[*].name}'
oc get maasauthpolicy maas-prod-auth-policy -n models-as-a-service \
  -o jsonpath='{.spec.subjects.groups[*].name}'
```

Update `values-prod.yaml` so that both `subscriptions[].groups` and `authPolicies[].groups` are identical, then re-sync the Application.

---

## Summary

MaaS governance on the IBM Fusion MaaS platform is built from two Kubernetes custom resources, `MaaSSubscription` and `MaaSAuthPolicy`, that must both exist and reference the same groups and models for users to access a model endpoint.

The `maas-config` Helm chart manages these resources declaratively. Each environment (dev, staging, prod) has its own values file. In production, a single ArgoCD Application (`fusion-maas-governance-config-prod`) governs all models through one values file: one subscription and one auth policy, each containing a `modelRefs` list covering all models. Adding a new model requires only appending a `modelRefs` entry to both lists and syncing.

Key points to carry forward:

- **Both `MaaSSubscription` and `MaaSAuthPolicy` are required.** Missing either one results in a `403` or `429` for all users of that model.
- **They are independent resources.** Adding a group or model to one does not automatically update the other. Keep them synchronized manually through the values file.
- **Sync wave 300 runs after wave 200.** The `MaaSModelRef` created by the model deploy layer must be `Ready` before the governance layer can activate.
- **Production uses no automated prune.** Governance resources are only removed from production during a deliberate manual sync in an approved change window.
- **The `groups` template creates as well as updates.** New groups are created on first sync; existing groups (e.g. OpenShift AI defaults) have only their `users` list patched via `ServerSideApply`.
- **Group membership is version-controlled.** Declare all groups in your values file. Helm replaces lists entirely, so any group not listed in the override will be removed on the next sync.

---

## Related Resources

| Resource | Link |
|---|---|
| storage-fusion repository | [github.com/IBM/storage-fusion](https://github.com/IBM/storage-fusion) |
| Helm chart - maas-config | [`AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/`](../deploy/helm/maas-config/) |
| Helm chart README | [`AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/README.md`](../deploy/helm/maas-config/README.md) |
| GitOps manifests - maas-config | [`AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-config/`](../deploy/gitops/maas-config/) |
| Model deploy GitOps | [`AI/AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/gitops/maas-model-deploy/`](../deploy/gitops/maas-model-deploy/) |
