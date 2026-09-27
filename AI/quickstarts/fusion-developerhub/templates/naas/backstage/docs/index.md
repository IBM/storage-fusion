# Quickstart: Fusion Namespace as a Service

If you run an OpenShift cluster for a team, you already know this story. A developer raises a ticket: "Can I get a namespace for my new project?" The platform team fields the request, remembers the right quotas, applies the RBAC, wires up GitOps, double-checks the network policies, and eventually the namespace is live, maybe a day later, maybe a week.

Multiply that by every project, every environment tier, and every team update, and you have a significant chunk of the platform team's week gone to repetitive provisioning work.

Namespace as a Service (NaaS) eliminates that queue. It turns namespace provisioning into a self-service form in Developer Hub. A developer fills in their project name, picks a size, names their team groups, and clicks Create. A GitOps Pull Request is opened automatically, and once a platform team approves it, ArgoCD provisions a fully configured, policy-compliant namespace, with no manual oc commands on either side.

## What Gets Provisioned?

Every namespace created through NaaS gets five Kubernetes manifests applied automatically:

| Manifest | What it does |
|---|---|
| `namespace.yaml` | Creates the namespace with cost, environment, ArgoCD management, and Pod Security Standards labels |
| `resource-quota.yaml` | Enforces CPU, memory, pod count, and storage caps, values vary by the Small / Medium / Large size tier chosen in the wizard |
| `limit-range.yaml` | Sets per-container and per-pod CPU/memory defaults and maximums, plus a per-PVC storage limit, so pods without explicit resource requests don't exhaust the quota |
| `network-policy.yaml` | Applies four policies: deny all ingress by default, allow intra-namespace pod traffic, allow the OpenShift router, and allow Prometheus scraping from openshift-monitoring |
| `rbac-role.yaml` | Creates three roles (namespace-admin, namespace-developer, namespace-viewer) with group bindings, plus a dedicated `<projectName>-cicd` ServiceAccount for pipelines |

Nothing is applied by hand. Every resource is declared in Git, owned by ArgoCD, and auditable.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  Developer Hub                                                       │
│                                                                      │
│  Software Templates  ──── fetch:template ────►  skeleton/ files      │
│  (template.yaml)         publish:github:pr  ──► GitOps repository    │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     │  Pull Request merged
                                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│  GitOps repository                                                   │
│                                                                      │
│  <namespacesPath>/                                                   │
│    <project>-<env>/                                                  │
│      namespace.yaml         ─── Namespace + labels                   │
│      resource-quota.yaml    ─── CPU / memory caps                    │
│      limit-range.yaml       ─── Per-container defaults               │
│      network-policy.yaml    ─── Ingress isolation rules              │
│      rbac-role.yaml         ─── Roles + RoleBindings + SA            │
│      catalog-info.yaml      ─── Backstage resource entity            │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     │  ArgoCD watches <namespacesPath>/
                                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│  ArgoCD                                                              │
│                                                                      │
│  Application: <release>-naas-controller                              │
│  ↳ Syncs, self-heals drift, prunes deleted resources                 │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
                          OpenShift Cluster Namespace
```

Three components work together:

1. **Developer Hub Software Templates** — the self-service forms that collect inputs and drive automation.
2. **Your GitOps repository** — the source of truth. Every namespace is a directory of YAML files under `<namespacesPath>/`.
3. **ArgoCD (`<release>-naas-controller`)** — watches `namespacesPath` recursively and reconciles the cluster to match Git. Sync is automated with `selfHeal: true` and `prune: true`.

---

## Part 1: Administrator Setup

### Prerequisites

Before you start, make sure you have:

- Developer Hub deployed and accessible (follow the Developer Hub Quickstart if you haven't already).
- OpenShift GitOps (ArgoCD) installed on the cluster (follow the GitOps (ArgoCD) Quickstart if you haven't already).
- A GitOps repository where namespace manifests will live.
- `oc` CLI access with cluster-admin permissions.
- Helm CLI installed (if deploying via Helm rather than ArgoCD GitOps).

### Step 1 — Set Up GitHub Authentication

NaaS uses GitHub in three distinct ways:

| Token | Source | Purpose |
|---|---|---|
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | GitHub OAuth App | "Sign in with GitHub" — authenticates users and establishes their session |
| `USER_OAUTH_TOKEN` | User's live GitHub OAuth session | Scaffolder actions — creates the branch, commits manifests, opens the PR, adds labels on behalf of the developer |
| `GITHUB_TOKEN` | Personal Access Token (PAT) | Backend — reads `template.yaml` and `skeleton/` files from GitHub at runtime |

All three are stored in a single Kubernetes Secret named `github-auth-secret`.

#### 1a. Create a GitHub OAuth App

Navigate to **GitHub → Settings → Developer Settings → OAuth Apps → New OAuth App**.

| Field | Value |
|---|---|
| Application name | Developer Hub (or any name users will recognise) |
| Homepage URL | `https://rhdh.<your-apps-domain>` |
| Authorization callback URL | `https://rhdh.<your-apps-domain>/api/auth/github/handler/frame` |

Click **Register application**. Note the Client ID and generate a Client Secret — you will need both in Step 1c.

> **GitHub Enterprise:** Navigate to `https://<your-ghe-hostname>/settings/developers`. The application name, Homepage URL, and Authorization callback URL fields are filled in exactly the same way. Only the GHE base domain differs.

#### 1b. Create a GitHub Personal Access Token

Go to `github.com/settings/tokens` and create a PAT with the `repo` scope. This token lets Developer Hub's backend read `template.yaml` and the `skeleton/` files from your GitOps repository at runtime.

> **GitHub Enterprise:** Create the token at `https://<your-ghe-hostname>/settings/tokens` instead. The `repo` scope requirement is identical.

#### 1c. Create the `github-auth-secret`

```bash
# Replace each placeholder with your actual values:
# <namespace>      — your Developer Hub namespace (e.g. rhdh, developer-hub)
# <client-id>      — GitHub OAuth App Client ID
# <client-secret>  — GitHub OAuth App Client Secret
# <your-pat>       — GitHub Personal Access Token with 'repo' scope

oc create secret generic github-auth-secret \
  --from-literal=GITHUB_CLIENT_ID=<client-id> \
  --from-literal=GITHUB_CLIENT_SECRET=<client-secret> \
  --from-literal=GITHUB_TOKEN=<your-pat> \
  -n <namespace>
```

### Step 2 — Enable NaaS in Your Helm Values

NaaS is disabled by default (`catalog.naas.enabled: false`). Open your environment values file (e.g. `deploy/helm/environments/dev/values.yaml`) and update the following block:

```yaml
argocd:
  enabled: true    # Required: allows the Helm chart to render the naas-controller ArgoCD Application
  rbac:
    enabled: true
    namespace: openshift-gitops

developerHub:
  auth:
    github:
      enabled: true    # Required: enables "Sign in with GitHub" and USER_OAUTH_TOKEN

  catalog:
    github:
      enterpriseHost: ""                        # Leave empty for public GitHub, or set your GHE hostname only
      target: "https://github.com/your-org"    # Full org URL, no trailing slash

    naas:
      enabled: true
      repoName: "your-gitops-repo"
      templateBranch: "main"
      templatePath: "quickstarts/fusion-developerhub/templates/naas/template.yaml"
      gitopsRepoURL: "https://github.com/your-org/your-gitops-repo.git"
      namespacesPath: "namespaces"
```

| Field | Description |
|---|---|
| `argocd.enabled` | Must be `true` for the Helm chart to render the `naas-controller` ArgoCD Application resource |
| `auth.github.enabled` | Enables "Sign in with GitHub" and the `USER_OAUTH_TOKEN` used to open PRs — without this every template run fails |
| `catalog.github.enterpriseHost` | GHE hostname only, no `https://`. Leave empty for public GitHub |
| `catalog.github.target` | Full org URL, used to construct the catalog location URL for `template.yaml` |
| `catalog.naas.repoName` | Repository name that holds `template.yaml` |
| `catalog.naas.templateBranch` | Branch the template is read from; also the branch ArgoCD tracks |
| `catalog.naas.templatePath` | Repo-relative path to `template.yaml` |
| `catalog.naas.gitopsRepoURL` | Full `.git` clone URL that the ArgoCD `naas-controller` Application watches |
| `catalog.naas.namespacesPath` | Subdirectory inside the repo where provisioned manifests land (default: `namespaces`) |

Apply the Helm upgrade:

```bash
helm upgrade <release> ./deploy/helm \
  -f deploy/helm/values.yaml \
  -f deploy/helm/environments/<env>/values.yaml \
  -n <namespace>
```

### Step 3 — Configure the Template's Hidden Platform Fields

Inside `templates/naas/template.yaml`, all three templates (Provision, Update, Delete) contain a set of hidden parameters. Find the block that begins with `# ── Platform settings (hidden — never shown in the UI or review step.)` and update every `default:` value:

```yaml
githubHost:
  default: ''                    # Leave empty for public GitHub, or set your GHE hostname
repoOrg:
  default: 'your-org'           # GitHub organisation that owns the GitOps repository
repoName:
  default: 'your-gitops-repo'   # Repository name
targetBranch:
  default: 'main'               # Branch the PR targets
prReviewers:
  default: ''                   # Comma-separated GitHub usernames auto-added as PR reviewers (optional)
namespacesPath:
  default: 'namespaces'         # Must exactly match catalog.naas.namespacesPath in values.yaml
argoCdInstance:
  default: 'openshift-gitops'   # Namespace of your ArgoCD instance
acmReplicate:
  default: 'false'              # Set 'true' to replicate namespaces to ACM managed clusters
podSecurityStandard:
  default: 'baseline'           # 'privileged', 'baseline', or 'restricted'
catalogOwner:
  default: 'platform-team'      # Backstage group that owns the catalog entries
catalogSystem:
  default: 'naas-platform'      # Backstage system the resource belongs to
```

> Keep `namespacesPath`, `repoOrg`, `repoName`, and `targetBranch` in sync with your Helm values. A mismatch means PRs are raised to a location ArgoCD is not monitoring — namespaces will never be provisioned.

Developer Hub re-fetches `template.yaml` from GitHub on every template run. Once you push the updated defaults to the configured branch, the change takes effect immediately — no redeployment of Developer Hub is required. You must update all three templates (Provision, Update, Delete) in the same file.

### Step 4 — Verify the ArgoCD NaaS Controller

```bash
oc get applications.argoproj.io -n openshift-gitops | grep naas-controller
```

You should see `Synced` and `Healthy`. What the sync policy means for day-to-day operations:

- **New `<namespacesPath>/<ns>/` directory merged** → ArgoCD provisions the namespace and all its resources within the next sync cycle.
- **Directory removed from Git (deletion PR merged)** → ArgoCD prunes all Kubernetes objects, including the Namespace itself.
- **Someone manually edits a namespace label or quota** → ArgoCD reverts it back to the Git-declared state on the next sync. This is intentional.

### Step 5 — Verify Template Registration

Inspect the rendered ConfigMap to confirm the catalog location URL is correct:

```bash
oc get configmap app-config-ai-templates -n <namespace> -o yaml
```

Check the `catalog.locations[].target` field. For a default configuration it should look like:

```
https://github.com/your-org/your-gitops-repo/blob/main/quickstarts/fusion-developerhub/templates/naas/template.yaml
```

---

## Part 2: Developer Guide

> **You must be signed in with your GitHub account.** Guest sessions do not produce a `USER_OAUTH_TOKEN` and cannot raise Pull Requests. If you see "Sign in with GitHub" on the Developer Hub homepage, click it before proceeding.

### Requesting a New Namespace

1. Open Developer Hub and sign in with your GitHub account.
2. Click **Create** in the left sidebar (or the **+** icon).
3. Search for `naas` or filter by the `naas` tag. You will see three templates:
   - **Request OpenShift Namespace (NaaS)** — create a new namespace
   - **Update OpenShift Namespace (NaaS)** — resize or change access on an existing namespace
   - **Delete OpenShift Namespace (NaaS)** — permanently remove a namespace
4. Click **Request OpenShift Namespace (NaaS)** and walk through the three-step wizard.

#### Step 1 — Namespace Details

| Field | Description | Example | Notes |
|---|---|---|---|
| Project Name | Unique lowercase identifier. The namespace will be named `<projectName>-<environment>`. | `payments-api` | Must match `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`, no uppercase, no underscores |
| Environment | Target tier. | `development` | Options: `development`, `staging`, `production` |
| Business Unit / Cost Center | Applied as a chargeback label on the namespace. | `engineering` | Options: `engineering`, `marketing`, `finance`, `retail` |

#### Step 2 — Resource Sizing

| Tier | CPU Requests | CPU Limits | Memory Requests | Memory Limits | Max Pods | Storage |
|---|---|---|---|---|---|---|
| Small | 4 cores | 8 cores | 8 Gi | 16 Gi | 20 | 100 Gi |
| Medium | 8 cores | 16 cores | 16 Gi | 32 Gi | 40 | 200 Gi |
| Large | 16 cores | 32 cores | 32 Gi | 64 Gi | 100 | 500 Gi |

#### Step 3 — Access Control

| Field | Role bound | Permissions | Required? |
|---|---|---|---|
| Owner Group | `namespace-admin` | Full control (`*` on all resources) — for team leads and namespace owners | Yes |
| Developer Group | `namespace-developer` | Create/update Deployments, StatefulSets, Pods, Services, ConfigMaps, Jobs, Routes; read Secrets | No |
| Viewer Group | `namespace-viewer` | Read-only (`get`, `list`, `watch`) on all resources — for stakeholders and auditors | No |

A `<projectName>-cicd` ServiceAccount is also automatically created and bound to `namespace-admin` for pipeline use — no manual action required.

> The groups must already exist in the cluster. If your group hasn't been created yet, ask your platform team before submitting.

### What Happens After You Click Create

The scaffolder runs four automated steps in sequence:

1. **Fetch Manifest Skeleton (`fetch:template`)** — Your wizard inputs and the hidden platform defaults are substituted into the skeleton YAML templates. The rendered files are placed at `<namespacesPath>/<projectName>-<environment>/`.
2. **Publish to GitOps Repository (`publish:github:pull-request`)** — The rendered files are pushed to a new branch named `naas-<projectName>-<environment>` using your `USER_OAUTH_TOKEN`, and a Pull Request is opened against the configured base branch.
3. **Tag Pull Request Labels (`github:issues:label`)** — The PR is labelled with `NaaS - Provision`, `Project Name: <name>`, `Environment: <env>`, `Business Unit: <bu>`, and `Size: <size>`.
4. **Register in Catalog (`catalog:register`)** — The `catalog-info.yaml` from the PR branch is registered as a Backstage Resource entity immediately — before the PR is even merged.

### Approval and Provisioning

The Pull Request is the approval gate. Once your platform team reviews and merges it, ArgoCD provisions all manifests within its next sync cycle. Verify:

```bash
# Namespace is Active
oc get namespace <projectName>-<environment>

# All resources are present
oc get resourcequota,limitrange,networkpolicy,role,rolebinding \
  -n <projectName>-<environment>
```

### Updating an Existing Namespace

Use the **Update OpenShift Namespace (NaaS)** template to resize quota or change team access. ArgoCD applies the updated manifests over the existing ones using server-side apply. Common scenarios:

| Scenario | What to change |
|---|---|
| Workload hitting quota limits | Increase the Size tier |
| A new team member joined | Add their group to Developer Group |
| Cost centre changed | Update Business Unit / Cost Center |
| Transferring ownership | Change Owner Group to the new team's group |

### Deleting a Namespace

Use the **Delete OpenShift Namespace (NaaS)** template when a project is retired. The template opens a PR that removes the entire `<namespacesPath>/<projectName>-<environment>/` directory. When merged, ArgoCD deprovisions all Kubernetes objects, including the Namespace itself.

> ⚠️ **Deletion is permanent.** All workloads, PVCs, and configuration inside the namespace are gone once the PR is merged and ArgoCD syncs. Back up anything important before merging the deletion PR.

### Viewing Your Namespaces in the Catalog

Every namespace provisioned through NaaS appears in the Developer Hub Software Catalog as a Resource entity of type `openshift-namespace`, tagged with `namespace`, `openshift`, `naas`, and the environment name.

1. Click **Catalog** in the left sidebar.
2. Filter by **Kind: Resource** and search for your project name.

The entry is created at submission time, so your team can discover it immediately — even before the PR is approved.

---

## Additional Resources

- [IBM Tech Exchange Blog — Quickstart: Fusion Namespace as a Service](https://community.ibm.com/community/user/blogs/christo-abraham2/2026/08/31/quick-start-fusion-namespace-as-a-service)
- [Fusion Tech Community](https://ibm.github.io/storage-fusion/fusion-ai/resources/)
