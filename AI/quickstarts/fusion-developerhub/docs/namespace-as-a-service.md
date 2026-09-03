# Namespace as a Service (NaaS)

> **Prerequisite:** Developer Hub must already be deployed and accessible. Follow the **[Developer Hub Quickstart](../QUICKSTART.md)** first if it isn't.

## What is Namespace as a Service?

Platform teams are constantly fielding the same request: *"Can I get a namespace for my project?"* It sounds trivial, but provisioning a namespace correctly — with the right resource quotas, network isolation, RBAC roles, and GitOps wiring — takes time, tribal knowledge, and careful coordination between developers and cluster administrators.

**Namespace as a Service (NaaS)** turns that workflow into a self-service experience powered by Developer Hub. A developer opens a form in the browser, fills in their project name, environment tier, and team groups, and clicks **Create**. Once approved, a fully-configured, policy-compliant OpenShift namespace is live on the cluster, provisioned entirely through GitOps — with no manual `oc` commands and no waiting on a ticket queue.

This document covers:

1. **[Administrator Setup](#1-administrator-setup)** — how to configure and deploy the NaaS system for your cluster.
2. **[Developer Guide](#2-developer-guide)** — how to request, update, and delete namespaces as a developer.
3. **[Under the Hood](#3-under-the-hood)** — the end-to-end flow from form submit to running namespace.

## 1. Administrator Setup

This section is for **platform engineers and cluster administrators** who want to enable NaaS for their organisation. It covers the files you need to customise, the values that must match your deployment, and how to wire everything together.

### 1.1 Architecture at a Glance

The NaaS system has three interlocking parts:

```
┌──────────────────────────────────────────────────────────────────────┐
│  Developer Hub                                                       │
│                                                                      │
│   Software Templates  ──── fetch:template ────►  skeleton/ files     │
│   (template.yaml)          publish:github:pr  ──► GitOps repository  │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     │  Pull Request merged
                                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│  GitOps repository                                                   │
│                                                                      │
│   <namespacesPath>/                                                  │
│     <project>-<env>/                                                 │
│       namespace.yaml          ─── Namespace + labels                 │
│       resource-quota.yaml     ─── CPU / memory caps                  │
│       limit-range.yaml        ─── Per-container defaults             │
│       network-policy.yaml     ─── Ingress isolation rules            │
│       rbac-role.yaml          ─── Roles + RoleBindings + SA          │
│       catalog-info.yaml       ─── Backstage resource entity          │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     │  ArgoCD watches <namespacesPath>/
                                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│  ArgoCD                                                              │
│                                                                      │
│   Application: <release>-naas-controller                             │
│   ↳ Syncs, self-heals drift, prunes deleted resources                │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
                          OpenShift Cluster Namespace
```

### 1.2 GitHub Authentication Setup

NaaS requires GitHub authentication for three distinct purposes:

1. **Signing users in** — Developer Hub uses a GitHub OAuth App to authenticate users via "Sign in with GitHub". The signed-in session produces the `USER_OAUTH_TOKEN` that the scaffolder uses to act on the user's behalf.
2. **Raising PRs on behalf of users** — when a developer submits the NaaS template, the scaffolder calls the GitHub API to create a branch, commit files, open a Pull Request, and add labels. It does this using `USER_OAUTH_TOKEN` so the PR appears as authored by the developer themselves.
3. **Fetching the template itself** — Developer Hub's backend reads `template.yaml` and the `skeleton/` files from GitHub at runtime. This requires a server-side token (`GITHUB_TOKEN`) with at least `repo` read scope on the GitOps repository.

All three are satisfied by a single Kubernetes `Secret` named `github-auth-secret` in the Developer Hub namespace.

#### Step 1 — Create a GitHub OAuth App

The OAuth App provides the `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` used for user sign-in.

1. Go to **GitHub → Settings → Developer Settings → OAuth Apps → New OAuth App**
   (For GitHub Enterprise: `https://github.example.com/settings/developers`)
2. Fill in the registration form:

   | Field | Value |
   |---|---|
   | **Application name** | `Developer Hub` (or any name your users will recognise) |
   | **Homepage URL** | `https://rhdh.<your-apps-domain>` |
   | **Authorization callback URL** | `https://rhdh.<your-apps-domain>/api/auth/github/handler/frame` |

3. Click **Register application**. Copy the **Client ID** and generate a **Client Secret** — you will need both in the next step.

For **GitHub Enterprise**, the callback URL format is the same; only the base domain changes.

#### Step 2 — Create a GitHub Personal Access Token (PAT)

The PAT provides the `GITHUB_TOKEN` used for server-side template fetching and scaffolder API calls.

Create a [GitHub PAT](https://github.com/settings/tokens) (or a GitHub Enterprise equivalent at `https://github.example.com/settings/tokens`) with the following scopes:

| Scope | Why it's needed |
|---|---|
| `repo` | Read `template.yaml` and skeleton files |

#### Step 3 — Create the `github-auth-secret`

Create the secret in your Developer Hub namespace with all three values:

```bash
# Replace each placeholder with your actual values
# <namespace>       — your Developer Hub namespace (e.g. rhdh, developer-hub)
# <client-id>       — GitHub OAuth App Client ID
# <client-secret>   — GitHub OAuth App Client Secret
# <your-pat>        — GitHub Personal Access Token

oc create secret generic github-auth-secret \
  --from-literal=GITHUB_CLIENT_ID=<client-id> \
  --from-literal=GITHUB_CLIENT_SECRET=<client-secret> \
  --from-literal=GITHUB_TOKEN=<your-pat> \
  -n <namespace>
```

For **GitHub Enterprise**, the Client ID and Client Secret come from your GHE OAuth App and the PAT from your GHE token settings. The secret structure and field names are identical.

> **Note:** `github-auth-secret` is already referenced in the Helm chart's `extraEnvs.secrets` list, so Developer Hub automatically mounts all three values as environment variables once the secret exists. No additional Helm changes are required for the secret itself.

#### Step 4 — Enable GitHub OAuth in your values

Creating the secret is not enough on its own — you also need to enable GitHub OAuth in your Helm values so that Developer Hub shows the "Sign in with GitHub" button and establishes user sessions. **Without this, `USER_OAUTH_TOKEN` will never be populated and every NaaS template run will fail at the "Publish to GitOps Repository" step.**

In your environment values file, set:

```yaml
developerHub:
  auth:
    github:
      enabled: true
      # For GitHub Enterprise only — full URL including https://
      # enterpriseInstanceUrl: "https://github.example.com"
```

> **Important:** For NaaS to work, users must sign in with their **GitHub account** (not as a guest). Guest sessions do not produce a `USER_OAUTH_TOKEN` and cannot raise PRs.

#### How the tokens are used at runtime

| Token | Source | Used for |
|---|---|---|
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | OAuth App | "Sign in with GitHub" — authenticates the user and establishes their session |
| `USER_OAUTH_TOKEN` | User's live GitHub OAuth session | Scaffolder actions — creates branch, commits, opens PR, adds labels on behalf of the developer |
| `GITHUB_TOKEN` | PAT in `github-auth-secret` | Backend — reads `template.yaml` and `skeleton/` files from GitHub at runtime |

### 1.3 Enabling NaaS — Helm

NaaS is **disabled by default**. To enable it, set `developerHub.catalog.naas.enabled: true` in your values override and fill in the fields below. When `enabled` is `false`, neither the Software Template catalog entry nor the ArgoCD namespace-controller Application are deployed.

Open your environment values file (e.g. `deploy/helm/environments/dev/values.yaml`) and configure the following:

```yaml
developerHub:
  catalog:
    github:
      enterpriseHost: ""                           # Leave empty for public GitHub, or set your GHE hostname
                                                   # (e.g. github.example.com — hostname only, no https://)
      target: "https://github.com/your-org"        # Full org URL (no trailing slash)

    naas:
      enabled: true                                # ← flip to true to activate NaaS
      repoName: "your-gitops-repo"                 # ← repository name  ← CHANGE THIS
      templateBranch: "main"                       # ← branch holding template.yaml  ← CHANGE THIS
      templatePath: "quickstarts/fusion-developerhub/templates/naas/template.yaml"
      gitopsRepoURL: "https://github.com/your-org/your-gitops-repo.git"  # ← CHANGE THIS
      namespacesPath: "namespaces"                 # directory inside the repo where namespace manifests land
```

The Helm chart composes `github.enterpriseHost`, `github.target`, `naas.repoName`, `naas.templateBranch`, and `naas.templatePath` into the catalog location URL that points Developer Hub at your `template.yaml`:

```
https://<enterpriseHost or github.com>/<org>/<repoName>/blob/<templateBranch>/<templatePath>
```

**All configurable NaaS fields:**

| Values field | Description | Example |
|---|---|---|
| `catalog.github.enterpriseHost` | Hostname of your GitHub Enterprise instance (no `https://`). Leave empty for public GitHub. | `github.example.com` |
| `catalog.github.target` | Full org URL — used for catalog discovery and URL construction | `https://github.com/my-org` |
| `catalog.naas.enabled` | Feature toggle — set `true` to deploy the template and ArgoCD controller | `true` |
| `catalog.naas.repoName` | Repository name that contains `template.yaml` | `my-platform-repo` |
| `catalog.naas.templateBranch` | Branch that holds the template and `skeleton/` files | `main` |
| `catalog.naas.templatePath` | Relative path to `template.yaml` within the repo | `quickstarts/fusion-developerhub/templates/naas/template.yaml` |
| `catalog.naas.gitopsRepoURL` | Full Git clone URL watched by the ArgoCD namespace-controller | `https://github.com/my-org/my-repo.git` |
| `catalog.naas.namespacesPath` | Repo-relative directory where provisioned namespace manifests land | `namespaces` |

After updating, re-run your Helm upgrade:

```bash
helm upgrade <release> ./deploy/helm \
  -f deploy/helm/values.yaml \
  -f deploy/helm/environments/<env>/values.yaml \
  -n <namespace>
```

### 1.4 Enabling NaaS — GitOps (ArgoCD `valuesObject`)

If Developer Hub is deployed via an ArgoCD `Application` (e.g. using the example at [`deploy/gitops/environments/dev/application.yaml`](../deploy/gitops/environments/dev/application.yaml)), add the NaaS overrides directly to the `spec.source.helm.valuesObject` block. This avoids editing values files on disk — ArgoCD re-renders the Helm chart automatically when the Application manifest changes.

Open your `application.yaml` and add or update the following under `valuesObject`:

```yaml
# spec.source.helm.valuesObject in your ArgoCD Application manifest
developerHub:
  catalog:
    github:
      enterpriseHost: ""                 # Leave empty for public GitHub, or set your GHE hostname
                                         # (e.g. github.example.com — hostname only, no https://)
      target: "https://github.com/your-org"  # Full org URL (no trailing slash)

    naas:
      enabled: true                      # ← flip to true to activate NaaS
      repoName: "your-gitops-repo"       # ← repository name  ← CHANGE THIS
      templateBranch: "main"             # ← branch holding template.yaml  ← CHANGE THIS
      templatePath: "quickstarts/fusion-developerhub/templates/naas/template.yaml"
      gitopsRepoURL: "https://github.com/your-org/your-gitops-repo.git"  # ← CHANGE THIS
      namespacesPath: "namespaces"       # directory inside the repo where namespace manifests land

  auth:
    github:
      enabled: true                      # required — see section 1.2 Step 4
```

The same field semantics apply as in section 1.3 — the table there covers every configurable value. The key difference is that `valuesObject` is inlined directly in the ArgoCD `Application` manifest rather than in a separate values file, so there is nothing to install or upgrade manually.

After editing, apply the change:

```bash
# If the Application already exists, patch it in place:
oc apply -f deploy/gitops/environments/<env>/application.yaml -n openshift-gitops

# Or commit and push — ArgoCD will self-sync if automated sync is enabled:
git add deploy/gitops/environments/<env>/application.yaml
git commit -m "chore: enable NaaS"
git push
```

ArgoCD detects the updated Application spec, re-renders the Helm chart with the new `valuesObject`, and applies the diff — enabling NaaS without any manual Helm commands.

### 1.5 Customising the Template's Hidden Platform Fields

Inside [`templates/naas/template.yaml`](../templates/naas/template.yaml), each of the three templates (Provision, Update, Delete) contains a set of **hidden fields** — parameters that developers never see in the wizard UI but that drive the template's behaviour. Their `default:` values represent your deployment's live configuration.

> **Keep these in sync with your Helm values.** The hidden fields in `template.yaml` drive the scaffolder (which repo to open the PR against, which branch to target, where to write manifests). The Helm values drive the ArgoCD controller (which repo and branch to watch) and the catalog URL. They must point at the same repository, branch, and `namespacesPath` or PRs will be raised to a location ArgoCD is not watching.

Look for the block that starts with `# ── Platform settings (hidden — never shown in the UI or review step.)`:

```yaml
# ── Platform settings (hidden — never shown in the UI or review step.)
# Set these defaults to match your deployment before registering this template.
githubHost:
  type: string
  ui:widget: hidden
  default: ''                       # ← leave empty for public GitHub, or set your GHE hostname
                                    #   (e.g. github.example.com)

repoOrg:
  type: string
  ui:widget: hidden
  default: 'your-org'               # ← GitHub organisation that owns the GitOps repo

repoName:
  type: string
  ui:widget: hidden
  default: 'your-gitops-repo'       # ← Repository name

targetBranch:
  type: string
  ui:widget: hidden
  default: 'main'                   # ← Branch the PR should target

prReviewers:
  type: string
  ui:widget: hidden
  default: ''                       # ← Comma-separated GitHub usernames auto-added as PR reviewers
                                    #   (optional — leave empty to skip)

namespacesPath:
  type: string
  ui:widget: hidden
  default: 'namespaces'             # ← Repo-relative directory where namespace manifests are stored
                                    #   Must match catalog.naas.namespacesPath in values.yaml

argoCdInstance:
  type: string
  ui:widget: hidden
  default: 'openshift-gitops'       # ← Namespace of the ArgoCD instance managing this cluster

acmReplicate:
  type: string
  ui:widget: hidden
  default: 'false'                  # ← Set 'true' to replicate namespaces to ACM managed clusters

podSecurityStandard:
  type: string
  ui:widget: hidden
  default: 'baseline'               # ← 'privileged', 'baseline', or 'restricted'

catalogOwner:
  type: string
  ui:widget: hidden
  default: 'platform-team'          # ← Backstage group that owns catalog entries

catalogSystem:
  type: string
  ui:widget: hidden
  default: 'naas-platform'          # ← Backstage system the resource belongs to
```

> **Tip:** Developer Hub re-fetches `template.yaml` from GitHub on every template run. You only need to push the updated defaults to the configured branch — no redeployment of Developer Hub is required.

### 1.6 Customising the Skeleton Manifests

The `skeleton/` directory contains Nunjucks template files that the scaffolder renders into real Kubernetes manifests when a developer submits a request. Here's what each file does and where you might want to adjust it for your environment:

#### `skeleton/namespace.yaml` — The Namespace itself

```yaml
metadata:
  name: ${{ values.projectName }}-${{ values.environment }}
  labels:
    argocd.argoproj.io/managed-by: ${{ values.argoCdInstance }}
    apps.openclustermanagement.io/replicate: "${{ values.acmReplicate }}"
    business-unit: ${{ values.businessUnit }}
    pod-security.kubernetes.io/enforce: ${{ values.podSecurityStandard }}
```

**What to customise:** Add any additional labels your organisation requires for cost allocation, compliance tagging, or internal tooling. If your company has a specific label schema (e.g. `cost-center`, `data-classification`), add those as static labels here or promote them to template parameters.

#### `skeleton/resource-quota.yaml` — CPU, Memory, and Storage Caps

The quota is driven by the `size` parameter — `small`, `medium`, or `large`:

| Tier | CPU Requests | Memory Requests | CPU Limits | Memory Limits | Pods | Storage |
|------|-------------|-----------------|------------|---------------|------|---------|
| Small | 4 | 8 Gi | 8 | 16 Gi | 20 | 100 Gi |
| Medium | 8 | 16 Gi | 16 | 32 Gi | 40 | 200 Gi |
| Large | 16 | 32 Gi | 32 | 64 Gi | 100 | 500 Gi |

**What to customise:** Adjust the values inside the `{%- if values.size == "small" %}` blocks to match your cluster's capacity and cost targets. You can also add more tiers (e.g. `xlarge`) by extending the `enum` in the template parameters and adding a corresponding branch in the resource quota file.

#### `skeleton/limit-range.yaml` — Per-Container Defaults

LimitRange sets default CPU/memory requests and limits on every container that doesn't specify its own. This prevents unbounded pods from exhausting quota.

**What to customise:** Adjust the per-container defaults and maximums. A common pattern is to tighten these for `production` environments while keeping them relaxed for `development`.

#### `skeleton/network-policy.yaml` — Network Isolation

Four policies are applied by default:

1. **`default-deny-ingress`** — blocks all external ingress traffic to pods in the namespace.
2. **`allow-same-namespace`** — permits pod-to-pod traffic within the namespace.
3. **`allow-openshift-router`** — allows the OpenShift router to reach pods (required for Routes/Ingress).
4. **`allow-openshift-monitoring`** — allows Prometheus scraping from the `openshift-monitoring` namespace.

**What to customise:** If your platform has additional shared namespaces that need access (e.g. a centralised logging agent, a service mesh control plane), add `namespaceSelector` blocks to permit that ingress. To allow egress to specific services, add `Egress`-type policies.

#### `skeleton/rbac-role.yaml` — Roles and Bindings

Three roles are created inside every namespace:

- **`namespace-admin`** — full control (`*`), bound to the owner group and the CI/CD ServiceAccount.
- **`namespace-developer`** — day-to-day development permissions: deployments, pods, services, configmaps, jobs, and routes.
- **`namespace-viewer`** — read-only (`get`, `list`, `watch`) for all resources.

A dedicated CI/CD ServiceAccount (`<projectName>-cicd`) is also created and bound to `namespace-admin`. Pipelines authenticate with this SA's token.

**What to customise:** If your organisation has a tighter security posture, remove specific verbs from `namespace-developer` (e.g. remove `exec` on pods). If you run OpenShift Pipelines (Tekton), you may want to add a binding for the `pipeline` ServiceAccount.

### 1.7 Deploying the ArgoCD NaaS Controller

When `catalog.naas.enabled: true` is set in your Helm values, the chart automatically renders and deploys an ArgoCD `Application` named `<release>-naas-controller`. This Application watches the `namespacesPath` directory in your GitOps repository and applies every manifest it finds there to the cluster.

The controller is configured from your Helm values:

```yaml
source:
  repoURL: <catalog.naas.gitopsRepoURL>
  targetRevision: <catalog.naas.templateBranch>
  path: <catalog.naas.namespacesPath>
  directory:
    recurse: true
    exclude: '**/catalog-info.yaml'   # Backstage entity — not a K8s manifest
```

No manual `oc apply` is needed. Verify the Application is healthy after deployment:

```bash
oc get applications.argoproj.io -n openshift-gitops | grep naas-controller
```

The `syncPolicy` is set to `automated` with `selfHeal: true` and `prune: true`. This means:
- When a PR is merged adding a new `<namespacesPath>/<ns>/` directory, ArgoCD automatically applies those manifests to the cluster within the next sync cycle.
- When a PR is merged removing a directory (deletion request), ArgoCD removes all the corresponding Kubernetes resources including the namespace itself.
- If someone manually modifies a namespace label or quota outside of Git, ArgoCD will revert it back to the Git-declared state.

> **ArgoCD permissions:** The naas-controller Application creates `Namespace` resources and cluster-scoped RBAC objects, so ArgoCD must have cluster-admin (or equivalent) permissions on the target cluster. This is standard for ArgoCD deployments via the OpenShift GitOps operator. If the Application shows a `ComparisonError` or `SyncFailed` related to permissions, verify that the ArgoCD service account has the required cluster role.

### 1.8 Registering the Templates in Developer Hub

When `catalog.naas.enabled: true`, the Helm chart renders a ConfigMap named **`app-config-ai-templates`** in the Developer Hub namespace. Developer Hub mounts this ConfigMap as an additional `app-config` file, which adds the NaaS `template.yaml` as a catalog location at startup.

The catalog location URL is assembled by the chart from your values:

```
https://<catalog.github.enterpriseHost or github.com>/<org from catalog.github.target>/<catalog.naas.repoName>/blob/<catalog.naas.templateBranch>/<catalog.naas.templatePath>
```

For example, with the default values filled in:

```
https://github.com/your-org/your-gitops-repo/blob/main/quickstarts/fusion-developerhub/templates/naas/template.yaml
```

You can inspect the rendered ConfigMap on the cluster to confirm the URL is correct:

```bash
oc get configmap app-config-ai-templates -n <namespace> -o yaml
```

Check the `catalog.locations[].target` field in the output. If the URL looks wrong, the most common cause is a mismatch between `catalog.github.target` (which must be a full org URL, e.g. `https://github.com/your-org`) and `catalog.naas.repoName`.

### 1.9 Pre-flight Checklist for Administrators

Before handing over NaaS to your developers, verify the following:

- [ ] `github-auth-secret` exists in the Developer Hub namespace with `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, and `GITHUB_TOKEN`.
- [ ] `auth.github.enabled: true` is set in your values so users can sign in with GitHub.
- [ ] `catalog.naas.enabled: true` is set in your values (Helm or GitOps `valuesObject`).
- [ ] Helm values (`naas.repoName`, `naas.templateBranch`, `naas.gitopsRepoURL`, `naas.namespacesPath`) and `template.yaml` hidden fields (`repoOrg`, `repoName`, `targetBranch`, `namespacesPath`) point at the same repository, branch, and path.
- [ ] The `app-config-ai-templates` ConfigMap is present and the `catalog.locations[].target` URL resolves to your `template.yaml`: `oc get configmap app-config-ai-templates -n <namespace> -o yaml`.
- [ ] The `<release>-naas-controller` ArgoCD Application is in `Synced` / `Healthy` state: `oc get applications.argoproj.io -n openshift-gitops | grep naas-controller`.
- [ ] At least one test namespace can be created end-to-end (signed in as a GitHub user, not guest) before announcing to the wider team.
- [ ] The OpenShift groups referenced in the `ownerGroup` field exist in the cluster before developers submit requests.

## 2. Developer Guide

This section is for **developers and team leads** who want to request a namespace for their project. No `oc` commands, no YAML — just fill in a form.

### 2.1 Accessing the Templates

> **You must be signed in with your GitHub account to use NaaS templates.** Guest sessions cannot raise Pull Requests. If you see "Sign in with GitHub" on the Developer Hub homepage, click it before proceeding.

1. Open Developer Hub in your browser. Your platform team will have shared the URL (typically `https://rhdh.<apps-domain>/`).
2. Sign in with your GitHub account using the **Sign in with GitHub** button (top right or on the homepage).
3. Click **Create** in the left sidebar (or the **+** icon).
4. Use the search box or filter by the tag **`naas`** to find the three NaaS templates:
   - **Request OpenShift Namespace (NaaS)** — create a new namespace.
   - **Update OpenShift Namespace (NaaS)** — resize or change access for an existing namespace.
   - **Delete OpenShift Namespace (NaaS)** — permanently remove a namespace.

### 2.2 Requesting a New Namespace

Click **Request OpenShift Namespace (NaaS)** and walk through the three-step wizard:

#### Step 1 — Namespace Details

| Field | Description | Example |
|---|---|---|
| **Project Name** | A unique lowercase identifier for your project. The final namespace will be `<projectName>-<environment>`. | `payments-api` |
| **Environment** | Target environment tier: `Development`, `Staging`, or `Production`. | `Development` |
| **Business Unit / Cost Center** | Used for chargeback labels and resource attribution. | `Engineering` |

> **Naming rules:** Project names must start and end with a lowercase letter or digit, and may only contain lowercase letters, digits, and hyphens. For example, `payments-api` is valid; `PaymentsAPI` is not.

#### Step 2 — Resource Sizing

Choose a pre-configured size tier that matches your workload:

| Tier | CPU Requests | Memory | Max Pods | Storage |
|------|-------------|--------|----------|---------|
| **Small** | 4 cores | 8 Gi | 20 | 100 Gi |
| **Medium** | 8 cores | 16 Gi | 40 | 200 Gi |
| **Large** | 16 cores | 32 Gi | 100 | 500 Gi |

Start small — you can always upsize later using the **Update** template.

#### Step 3 — Access Control

| Field | Description |
|---|---|
| **Owner Group** *(required)* | An existing OpenShift group whose members get **full admin** rights in the namespace. Typically your team's group name (e.g. `team-backend`). |
| **Developer Group** *(optional)* | An existing OpenShift group whose members get **developer** rights — create/update deployments, pods, services, and routes, but cannot modify cluster-level resources or read secrets. |
| **Viewer Group** *(optional)* | An existing OpenShift group whose members get **read-only** access — useful for stakeholders and auditors. |

> **Important:** The groups must already exist in the cluster. If your group hasn't been created yet, ask your platform team to provision it before submitting the request.

#### Review and Submit

After completing the wizard, a **Review** step shows a summary of your selections (hidden platform fields are not displayed). Click **Create** to submit.

### 2.3 What Happens After You Submit

Immediately after clicking **Create**, the scaffolder runs through a sequence of automated steps — you can watch the progress in the output panel:

1. **Fetch Manifest Skeleton** — the scaffolder renders the six Kubernetes YAML files (namespace, resource quota, limit range, network policies, RBAC roles, and catalog entity) by substituting your wizard inputs into the skeleton templates. The rendered files are placed under `<namespacesPath>/<projectName>-<environment>/`.

2. **Publish to GitOps Repository** — the rendered files are pushed to a new branch named `naas-<projectName>-<environment>` in the GitOps repository, and a Pull Request is opened targeting the configured base branch. The PR description includes a formatted table of all your inputs. Configured reviewers (if any) are automatically added.

3. **Tag Pull Request Labels** — the PR is labelled with `NaaS - Provision`, `Project Name: <name>`, `Environment: <env>`, `Business Unit: <bu>`, and `Size: <size>` to make the PR easy to filter and audit.

4. **Register in Catalog** — a `Resource` entity for your new namespace is registered in the Developer Hub Software Catalog, so your team can discover it immediately without waiting for the PR to merge.

At the end of this sequence, the output panel shows two links:
- **View Pull Request** — takes you directly to the GitHub PR.
- **View Catalog Entry** — takes you to the namespace resource in the Developer Hub catalog.

> **Tip:** Before submitting, check that no namespace named `<projectName>-<environment>` already exists in the cluster. Because the template skips a live uniqueness check, a duplicate request will still create a PR — but ArgoCD will surface a sync error if the namespace already exists outside of its management.

### 2.4 Approval and Provisioning

The Pull Request is the **approval gate**. Your platform team reviews it. Once the PR is merged:

1. ArgoCD detects the new `<namespacesPath>/<projectName>-<environment>/` directory in the repository within its next sync cycle.
2. ArgoCD applies all six manifests to the cluster in dependency order.
3. The namespace is live, fully configured, and ready for workloads.

You'll know provisioning is complete when:
- `oc get namespace <projectName>-<environment>` returns `Active`.
- `oc get resourcequota,limitrange,networkpolicy,role,rolebinding -n <projectName>-<environment>` shows all the expected objects.

### 2.5 Updating an Existing Namespace

Need more resources? Changed your team structure? Use the **Update OpenShift Namespace (NaaS)** template.

The update flow is identical to the provision flow, but:
- The template **does not** check for namespace existence — it assumes the namespace you name already exists.
- The PR branch is named `naas-update-<projectName>-<environment>`.
- The PR is labelled `NaaS - Update`.
- ArgoCD applies the updated manifests over the existing ones, changing only what has changed (thanks to server-side apply).

**Common update scenarios:**

| Scenario | What to change |
|---|---|
| Workload is growing, hitting quota limits | Increase the **Size** tier from `small` to `medium` or `large` |
| A new team joined the project | Add their group to **Developer Group** or **Viewer Group** |
| Cost centre has changed | Update **Business Unit / Cost Center** |
| Transferring namespace ownership | Change the **Owner Group** to the new team's group |

> **Note:** Changing the **Project Name** or **Environment** fields in the Update template does not rename the namespace — it would create a new set of manifests at a different path. To rename a namespace, delete the old one and create a new one.

### 2.6 Deleting a Namespace

When a project is retired, use the **Delete OpenShift Namespace (NaaS)** template to cleanly deprovision everything.

#### What the deletion template does

The template opens a PR that **removes** the entire `<namespacesPath>/<projectName>-<environment>/` directory from the GitOps repository. When merged, ArgoCD detects the removed manifests and deprovisions all the Kubernetes objects — including the namespace itself — thanks to the `prune: true` setting on the ArgoCD Application.

#### Confirming the deletion

The deletion template includes a safety confirmation field:

> *Type the namespace name exactly as it will appear (`{projectName}-{environment}`) to confirm you intend to delete it.*

This is a deliberate friction point. Read it carefully before submitting. The PR is also labelled `NaaS - Delete` and is auto-assigned to configured reviewers.

> ⚠️ **Deletion is permanent.** Once the namespace is removed from Git and ArgoCD syncs, all workloads, persistent volume claims, and configuration inside the namespace are gone. Make sure you have backed up anything important before merging the deletion PR.

### 2.7 Viewing Your Namespaces in the Catalog

Every namespace provisioned through NaaS is registered as a `Resource` entity of type `openshift-namespace` in the Developer Hub Software Catalog. You can find your namespaces by:

1. Clicking **Catalog** in the left sidebar.
2. Filtering by **Kind: Resource** and searching for your project name.

This catalog entry is created at template submission time (before the PR is merged), so your team can discover the namespace immediately. The entity is kept in the catalog until the deletion PR is merged and the `catalog-info.yaml` file is removed from the repository.

## 3. Under the Hood

This section is for those who want to understand exactly how all the pieces fit together — useful for troubleshooting, extending the system, or satisfying curiosity.

### 3.1 The Three Software Templates

The `template.yaml` file defines three Backstage `Template` resources in a single YAML stream (separated by `---`):

| Template name | `metadata.name` | Purpose |
|---|---|---|
| Request OpenShift Namespace | `openshift-naas-template` | Renders and publishes skeleton manifests as a GitOps PR |
| Update OpenShift Namespace | `openshift-naas-update-template` | Overwrites existing manifests with new values |
| Delete OpenShift Namespace | `openshift-naas-delete-template` | Opens a PR that removes manifests; ArgoCD prunes on merge |

Each template follows the same structure:
- **`parameters`** — the wizard UI definition. Hidden fields carry platform configuration as `default:` values. Visible fields collect developer inputs.
- **`steps`** — the automation sequence run server-side by the Backstage scaffolder when the form is submitted.
- **`output`** — links shown to the developer after the run completes.

### 3.2 The Provision Template's Steps

The provision template (`openshift-naas-template`) runs four steps in sequence:

```
fetch:template  →  publish:github:pull-request  →  github:issues:label  →  catalog:register
```

1. **`fetch:template`** — renders the `skeleton/` directory using the wizard inputs and platform defaults, placing the output at `<namespacesPath>/<projectName>-<environment>/`.
2. **`publish:github:pull-request`** — commits the rendered files to a new branch and opens a PR against `targetBranch`.
3. **`github:issues:label`** — tags the PR with structured labels for easy filtering.
4. **`catalog:register`** — registers `catalog-info.yaml` as a Backstage `Resource` entity immediately, pointing at the PR branch URL.

> **No live cluster check:** The template does not probe the cluster API before creating the PR. It is the platform team's responsibility during PR review to confirm the namespace does not already exist. ArgoCD will surface a sync error if a namespace manifest targets a name that conflicts with an existing cluster resource it does not manage.

### 3.3 The Skeleton Rendering Pipeline

The `fetch:template` action processes every file in the `skeleton/` directory using Nunjucks templating syntax. The `${{ values.* }}` placeholders in skeleton files are replaced with the values collected from the developer's form inputs and the hidden platform defaults.

For example, `skeleton/namespace.yaml`:

```yaml
# Skeleton (template)                       # Rendered output (example)
name: ${{ values.projectName }}-            # name: payments-api-
      ${{ values.environment }}             #       development
labels:
  business-unit: ${{ values.businessUnit }} # business-unit: engineering
  argocd.argoproj.io/managed-by:           # argocd.argoproj.io/managed-by:
    ${{ values.argoCdInstance }}            #   openshift-gitops
```

Conditional blocks (using `{%- if %}` Nunjucks syntax) in `resource-quota.yaml`, `limit-range.yaml`, and `rbac-role.yaml` emit different content depending on the `size`, `developerGroup`, and `viewerGroup` values.

The rendered files are placed at `<namespacesPath>/<projectName>-<environment>/` relative to the repository root, ready to be pushed as a Pull Request.

### 3.4 The GitOps Pull Request Flow

The `publish:github:pull-request` action creates a branch (`naas-<projectName>-<environment>`) from the `targetBranch` configured in the hidden fields, commits all rendered manifests, and opens a PR. The PR description is a formatted Markdown table summarising the request.

The `github:issues:label` action then attaches metadata labels so the platform team can filter NaaS PRs at a glance.

Both public GitHub and GitHub Enterprise are supported. Set `githubHost` to your GHE hostname (e.g. `github.example.com`) to route the PR action to the correct GitHub instance. Leave it empty to use `github.com`.

### 3.5 ArgoCD Sync Mechanics

The `<release>-naas-controller` ArgoCD Application watches the `namespacesPath` directory (recursively) in the GitOps repository:

```yaml
source:
  path: namespaces          # configurable via catalog.naas.namespacesPath
  directory:
    recurse: true
    exclude: '**/catalog-info.yaml'   # ← Backstage entity, not a K8s manifest
```

`catalog-info.yaml` is excluded from ArgoCD's scope because it is a Backstage resource, not a Kubernetes resource — applying it to the cluster would fail.

ArgoCD `ServerSideApply=true` is used so that large or complex manifests don't hit client-side size limits, and so field managers are tracked correctly.

The `prune: true` flag is the key to deletion: when the manifests directory for a namespace is removed from Git, ArgoCD removes the corresponding Kubernetes objects — including the `Namespace` itself — on the next sync.

## Troubleshooting

### Template doesn't appear in Developer Hub

- Verify `catalog.naas.enabled: true` is set in your values (Helm or GitOps `valuesObject`).
- Verify `templateBranch` and `templatePath` in your values match the actual location of `template.yaml` in the repository.
- Check the Backstage catalog processing logs: `oc logs -n <rhdh-namespace> -l app.kubernetes.io/name=backstage --tail=200 | grep -i naas`.
- Confirm `github-auth-secret` exists and `GITHUB_TOKEN` has `repo` read access to the GitOps repository.

### Template submits but fails on "Publish to GitOps Repository"

- Confirm the user is signed in with a **GitHub account** (not guest). Guest sessions have no `USER_OAUTH_TOKEN`.
- Confirm `auth.github.enabled: true` is set in your values and Developer Hub was redeployed after the secret was created.
- Confirm the signed-in user's GitHub account has `write` access to the GitOps repository — the PR is raised using their OAuth token, so if their account lacks push permission to the repo, the API call will fail.
- For GitHub Enterprise, confirm `githubHost` in the template's hidden fields matches the GHE hostname exactly — no `https://`, no trailing slash.

### Pull Request is created but ArgoCD never syncs

- Confirm the naas-controller Application is running: `oc get applications.argoproj.io -n openshift-gitops | grep naas-controller`.
- Check that `repoURL` and `targetRevision` in the ArgoCD Application match the repository and branch where the PR was merged — these come from `naas.gitopsRepoURL` and `naas.templateBranch` in your values.
- Look at the ArgoCD Application events: `oc describe applications.argoproj.io <release>-naas-controller -n openshift-gitops`.
- Verify `namespacesPath` in the template hidden fields matches `naas.namespacesPath` in your values — a mismatch means ArgoCD is watching a different directory than where the PR committed the files.

### Namespace is created but pods fail to schedule

- Inspect the ResourceQuota: `oc describe resourcequota compute-quota -n <namespace>`. If limits are exhausted, use the **Update** template to upsize.
- Check LimitRange defaults: `oc describe limitrange default-limits -n <namespace>`. Pods without explicit resource requests inherit these defaults.

### ArgoCD reverts manual changes to namespace labels

This is expected behaviour — `selfHeal: true` ensures the cluster always matches Git. To make a permanent change, update the relevant manifest in Git via the **Update** template or a direct PR.
