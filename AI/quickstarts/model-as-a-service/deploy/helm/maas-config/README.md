# maas-config

Helm chart for managing **MaaS governance resources** — `MaaSSubscription`, `MaaSAuthPolicy`, and OpenShift `Group` custom resources that govern model access through the MaaS gateway.

---

## Why this chart exists

Models deployed to the MaaS gateway via `maas-model-deploy` are registered with the MaaS controller by a `MaaSModelRef` CR. To make those models consumable by users, two governance resources are required **per environment**:

| Resource | API Group | Namespace | What it does |
|---|---|---|---|
| `MaaSSubscription` | `maas.opendatahub.io/v1alpha1` | `models-as-a-service` | Grants token quota for model access to specified groups / users |
| `MaaSAuthPolicy` | `maas.opendatahub.io/v1alpha1` | `models-as-a-service` | Grants API gateway access to model endpoints |
| `Group` | `user.openshift.io/v1` | cluster-scoped | Creates the Group if it does not exist; reconciles its `users` list if it does |

**Both `MaaSSubscription` and `MaaSAuthPolicy` must exist.** Without a subscription → users get `429 Too Many Requests`. Without an auth policy → users get `403 Forbidden`.

This chart is managed via the ArgoCD Application `fusion-maas-governance-config-<env>` in each environment.

> **Group creation vs update:** the `groups` template renders a standard `user.openshift.io/v1 Group` manifest for every entry in `.Values.groups`. Kubernetes will **create** the Group if it does not exist. If it already exists (e.g. pre-created by OpenShift AI), ArgoCD's `ServerSideApply=true` means only the `users` field owned by this chart is reconciled — all other fields managed by other controllers are left untouched.

---

## Chart structure

```
maas-config/
├── Chart.yaml
├── values.yaml                              # schema + empty defaults (all lists empty)
├── templates/
│   ├── _helpers.tpl                         # label/annotation helpers
│   ├── maassubscription.yaml               # iterates .Values.subscriptions[]
│   ├── maasauthpolicy.yaml                 # iterates .Values.authPolicies[]
│   └── groups.yaml                         # iterates .Values.groups[]
└── environments/
    ├── CHANGELOG.md
    ├── dev/
    │   └── values.yaml                     # dev overrides (single model, 5,000 tokens/hr)
    ├── staging/
    │   └── values.yaml                     # staging overrides (single model, 8,000 tokens/hr)
    └── prod/
        └── values-prod.yaml                # prod overrides (all models, 10,000 tokens/hr each)
```

---

## Sync-wave dependency order

```
wave -10  AppProject        (fusion-maas-governance-config-<env>)
wave 200  maas-model-deploy (MaaSModelRef must exist before governance resources reference it)
wave 300  maas-config       (this chart — MaaSSubscription + MaaSAuthPolicy + Group)
```

Always deploy `maas-model-deploy` before syncing this chart. The `MaaSModelRef` named in `modelRefs` must already exist on the cluster.

---

## Environment overrides

### Production — `environments/prod/values-prod.yaml`

A **single subscription and single auth policy** govern all production models. To add a new model, append a `modelRefs` entry to both `subscriptions[0].modelRefs` and `authPolicies[0].modelRefs`.

```
MaaSSubscription  maas-prod-subscription        models-as-a-service
  groups          rhods-admins
  models          gpt-oss-20b-100  (deploy-models)   10,000 tokens/hr
                  tiny-llama-test  (deploy-models)   10,000 tokens/hr

MaaSAuthPolicy    maas-prod-auth-policy          models-as-a-service
  groups          rhods-admins
  models          gpt-oss-20b-100  (deploy-models)
                  tiny-llama-test  (deploy-models)

Groups            rhods-admins         → dev_user1, dev_user2, prod_user1
                  model-registry-users → (empty)
```

### Staging — `environments/staging/values.yaml`

```
MaaSSubscription  gpt-model-subscription         models-as-a-service
  groups          rhods-admins
  model           gpt-oss-20b-100  (deploy-models)   8,000 tokens/hr

MaaSAuthPolicy    gpt-model-subscription-policy   models-as-a-service
  groups          rhods-admins
  model           gpt-oss-20b-100  (deploy-models)
```

### Development — `environments/dev/values.yaml`

```
MaaSSubscription  gpt-model-subscription         models-as-a-service
  groups          rhods-admins
  model           gpt-oss-20b-100  (deploy-models)   5,000 tokens/hr

MaaSAuthPolicy    gpt-model-subscription-policy   models-as-a-service
  groups          rhods-admins
  model           gpt-oss-20b-100  (deploy-models)
```

---

## ArgoCD Applications

Each environment has one ArgoCD Application under `deploy/gitops/maas-config/environments/<env>/`:

| Environment | Application name | Sync mode | Values file |
|---|---|---|---|
| dev | `fusion-maas-governance-config-dev` | Auto (prune + self-heal) | `environments/dev/values.yaml` |
| staging | `fusion-maas-governance-config-staging` | Manual | `environments/staging/values.yaml` |
| prod | `fusion-maas-governance-config-prod` | Manual, no prune | `environments/prod/values-prod.yaml` |

All applications use `ServerSideApply=true` so that only the `users` field of pre-existing OpenShift Groups is reconciled — fields owned by OpenShift AI controllers are left untouched.

---

## Usage

### Render locally (dry-run)

**Production:**
```bash
helm template maas-config \
  AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/values.yaml \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/environments/prod/values-prod.yaml
```

**Dev / Staging** (replace `dev` with `staging` as needed):
```bash
helm template maas-config \
  AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/values.yaml \
  -f AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config/environments/dev/values.yaml
```

### Apply with ArgoCD

Point an ArgoCD Application at this chart with:
```yaml
source:
  path: AI/quickstarts/model-as-a-service-rhoai-3.5/deploy/helm/maas-config
  helm:
    valueFiles:
      - values.yaml
      - environments/prod/values-prod.yaml   # or dev/values.yaml, staging/values.yaml
```

---

## Adding a new model to production governance

Append to both `modelRefs` lists in [`environments/prod/values-prod.yaml`](environments/prod/values-prod.yaml):

```yaml
subscriptions:
  - name: maas-prod-subscription
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
      # ── add new model here ──
      - name: my-new-model
        namespace: deploy-models
        tokenRateLimits:
          - limit: 10000
            window: "1h"

authPolicies:
  - name: maas-prod-auth-policy
    modelRefs:
      - name: gpt-oss-20b-100
        namespace: deploy-models
      - name: tiny-llama-test
        namespace: deploy-models
      # ── add new model here ──
      - name: my-new-model
        namespace: deploy-models
```

Then trigger a manual sync of `fusion-maas-governance-config-prod` in ArgoCD.

---

## Adding a new subscription / policy (advanced)

To create a completely separate subscription (e.g. for a different group with different quotas), add a new entry to the `subscriptions` and `authPolicies` lists:

```yaml
subscriptions:
  - name: my-team-subscription
    displayName: "My Team Subscription"
    priority: 50
    groups:
      - my-team-group
    modelRefs:
      - name: my-model-ref
        namespace: deploy-models
        tokenRateLimits:
          - limit: 50000
            window: "1h"

authPolicies:
  - name: my-team-auth-policy
    groups:
      - my-team-group
    modelRefs:
      - name: my-model-ref
        namespace: deploy-models
```

---

## Managing OpenShift Group membership

The `groups` list renders a full `user.openshift.io/v1 Group` manifest for each entry. This means:

- **New group** (not on the cluster): Kubernetes creates it with the specified `users` list.
- **Existing group** (e.g. `rhods-admins` pre-created by OpenShift AI): ArgoCD applies via `ServerSideApply`, reconciling **only** the `users` field owned by this chart — all other fields managed by other controllers are left untouched.

```yaml
groups:
  # Pre-existing group managed by OpenShift AI — only users list is patched
  - name: rhods-admins
    description: "OpenShift AI administrators"
    users:
      - alice       # oc whoami to find usernames
      - bob
  - name: model-registry-users
    description: "Users with access to the OpenShift AI Model Registry"
    users: []
  # New custom group — created fresh by this chart if it doesn't exist
  - name: my-team-group
    description: "Custom group for my team's model access"
    users:
      - carol
      - dave
```

> **Helm list merge behaviour:** Helm replaces lists entirely when a values file overrides them.
> Always declare **all** groups in your environment override — both pre-existing ones you manage
> and any new ones you are creating — or omitted groups will be dropped from the rendered output.

To find a user's OpenShift username: `oc get users`

---

## Notes

- `MaaSSubscription` and `MaaSAuthPolicy` are always created in `models-as-a-service` regardless of the model's project namespace.
- The `MaaSModelRef` for a model lives in the **model's project namespace** (e.g. `deploy-models`) and is managed by the `maas-model-deploy` chart with `maasModelRef.enabled: true`.
- Token rate limit `window` accepts `s` (seconds), `m` (minutes), `h` (hours). The `d` (days) unit is **not** supported — use `24h` for one day, `168h` for one week.
- `MaaSSubscription.spec.priority` controls precedence when a user belongs to multiple groups. Recommended scheme: `production=100`, `staging=50`, `dev=0`, `sandbox=-10`.
- `MaaSAuthPolicy` access logic is **OR** — any matching group **or** user grants access to **all** listed models in that policy.
- Prod syncs are **manual only** — no automated prune. Always review the ArgoCD diff before syncing in production.
