# Namespace as a Service (NaaS)

> **Prerequisite:** Developer Hub must already be deployed and accessible. Follow the **[Developer Hub Quickstart](../QUICKSTART.md)** first if it isn't.

## What is Namespace as a Service?

Platform teams are constantly fielding the same request: *"Can I get a namespace for my project?"* It sounds trivial, but provisioning a namespace correctly, with the right resource quotas, network isolation, RBAC roles, and GitOps wiring, takes time, tribal knowledge, and careful coordination between developers and cluster administrators.

**Namespace as a Service (NaaS)** turns that workflow into a self-service experience powered by Developer Hub. A developer opens a form in the browser, fills in their project name, environment tier, and team groups, and clicks **Create**. Once approved, a fully-configured, policy-compliant OpenShift namespace is live on the cluster, provisioned entirely through GitOps, with no manual `oc` commands and no waiting on a ticket queue.

## Table of Contents

1. [Administrator Setup](#1-administrator-setup)
   1. [Architecture at a Glance](#11-architecture-at-a-glance)
   2. [GitHub Authentication Setup](#12-github-authentication-setup)
   3. [Namespace Validator Plugin](#13-namespace-validator-plugin)
   4. [Enabling NaaS - Helm](#14-enabling-naas--helm)
   5. [Enabling NaaS - GitOps (ArgoCD `valuesObject`)](#15-enabling-naas--gitops-argocd-valuesobject)
   6. [Customizing the Template's Hidden Platform Fields](#16-customizing-the-templates-hidden-platform-fields)
   7. [Deploying the ArgoCD NaaS Controller](#17-deploying-the-argocd-naas-controller)
   8. [Customizing the Skeleton Manifests](#18-customizing-the-skeleton-manifests)
   9. [Registering the Templates in Developer Hub](#19-registering-the-templates-in-developer-hub)
   10. [Pre-flight Checklist for Administrators](#110-pre-flight-checklist-for-administrators)
2. [Developer Guide](#2-developer-guide)
   1. [Accessing the Templates](#21-accessing-the-templates)
   2. [Requesting a New Namespace](#22-requesting-a-new-namespace)
   3. [What Happens After You Submit](#23-what-happens-after-you-submit)
   4. [Approval and Provisioning](#24-approval-and-provisioning)
   5. [Updating an Existing Namespace](#25-updating-an-existing-namespace)
   6. [Deleting a Namespace](#26-deleting-a-namespace)
   7. [Viewing Your Namespaces in the Catalog](#27-viewing-your-namespaces-in-the-catalog)
3. [Under the Hood](#3-under-the-hood)
   1. [The Three Software Templates](#31-the-three-software-templates)
   2. [The Provision Template's Steps](#32-the-provision-templates-steps)
   3. [The Skeleton Rendering Pipeline](#33-the-skeleton-rendering-pipeline)
   4. [The GitOps Pull Request Flow](#34-the-gitops-pull-request-flow)
   5. [ArgoCD Sync Mechanics](#35-argocd-sync-mechanics)

## 1. Administrator Setup

This section is for **platform engineers and cluster administrators** who want to enable NaaS for their organization. It covers the files you need to customize, the values that must match your deployment, and how to wire everything together.

### 1.1 Architecture at a Glance

The NaaS system has three interlocking parts:

```
┌──────────────────────────────────────────────────────────────────────┐
│  Developer Hub                                                       │
│                                                                      │
│   Software Templates   ──► fetch:template     ──►  skeleton/ files   │
│   (3 × template.yaml)      publish:github:pr  ──► GitOps repository  │
│                                                                      │
│   Namespace Validator Plugin                                         │
│   ↳ naas:namespace:available  ─── pre-flight check before PR         │
│   ↳ NamespaceName field       ─── live availability indicator        │
│   ↳ OcGroupField              ─── live OpenShift group picker        │
│   ↳ NaaSProjectField          ─── pre-populated update selector      │
│   ↳ NaaSDeleteField           ─── pre-populated delete selector      │
│   ↳ ArgoAppField              ─── pre-populated ArgoCD wiring form   │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     │  Pull Request
                                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│  GitOps repository                                                   │
│                                                                      │
│   <namespacesPath>/                                                  │
│     <project>-<env>/                                                 │
│       namespace.yaml          ─── Namespace + labels + annotations   │
│       resource-quota.yaml     ─── CPU / memory caps                  │
│       limit-range.yaml        ─── Per-container defaults             │
│       network-policy.yaml     ─── Ingress isolation rules            │
│       rbac-role.yaml          ─── Roles + RoleBindings + SA          │
│       catalog-info.yaml       ─── Backstage resource entity          │
│       argocd-application.yaml ─── ArgoCD Application (optional)      │
└──────────────────────────────────────────────────────────────────────┘
                                     │
                                     │  Pull Request Merged
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

1. **Signing users in** - Developer Hub uses a GitHub OAuth App to authenticate users via "Sign in with GitHub". The signed-in session produces the `USER_OAUTH_TOKEN` that the scaffolder uses to act on the user's behalf.
2. **Raising PRs on behalf of users** - when a developer submits a NaaS template, the scaffolder calls the GitHub API to create a branch, commit files, open a Pull Request, and add labels. It does this using `USER_OAUTH_TOKEN` so the PR appears as authored by the developer themselves.
3. **Fetching the templates** - Developer Hub's backend reads the three template YAML files and the `skeleton/` files from GitHub at runtime. This requires a server-side token (`GITHUB_TOKEN`) with at least `repo` read scope on the GitOps repository.

All three are satisfied by a single Kubernetes `Secret` named `github-auth-secret` in the Developer Hub namespace.

#### Step 1 - Create a GitHub OAuth App

The OAuth App provides the `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` used for user sign-in.

1. Go to **GitHub → Settings → Developer Settings → OAuth Apps → New OAuth App**
   (For GitHub Enterprise: `https://<your-ghe-host>/settings/developers`)
2. Fill in the registration form:

   | Field | Value |
   |---|---|
   | **Application name** | `Developer Hub` (or any name your users will recognize) |
   | **Homepage URL** | `<your-developer-hub-base-url>` |
   | **Authorization callback URL** | `<your-developer-hub-base-url>/api/auth/github/handler/frame` |

3. Click **Register application**. Copy the **Client ID** and generate a **Client Secret** - you will need both in the next step.

For **GitHub Enterprise**, the callback URL format is the same; only the base domain changes.

#### Step 2 - Create a GitHub Personal Access Token (PAT)

The PAT provides the `GITHUB_TOKEN` used for server-side template fetching and scaffolder API calls.

Create a [GitHub PAT](https://github.com/settings/tokens) (or a GitHub Enterprise equivalent at `https://<your-ghe-host>/settings/tokens`) with the `repo` scope, which grants read access to template and skeleton files as well as the ability to create branches and pull requests.

#### Step 3 - Create the `github-auth-secret`

Create the secret in your Developer Hub namespace with all three values:

```bash
# Replace each placeholder with your actual values
# <namespace>      - your Developer Hub namespace (e.g. rhdh)
# <client-id>      - GitHub OAuth App Client ID
# <client-secret>  - GitHub OAuth App Client Secret
# <your-pat>       - GitHub Personal Access Token

oc create secret generic github-auth-secret \
  --from-literal=GITHUB_CLIENT_ID=<client-id> \
  --from-literal=GITHUB_CLIENT_SECRET=<client-secret> \
  --from-literal=GITHUB_TOKEN=<your-pat> \
  -n <namespace>
```

For **GitHub Enterprise**, the Client ID and Client Secret come from your GHE OAuth App and the PAT from your GHE token settings. The secret structure and field names are identical.

> **Note:** `github-auth-secret` is already listed in the Helm chart's `extraEnvs.secrets` configuration, so Developer Hub automatically mounts all three values as environment variables once the secret exists. No additional Helm changes are required for the secret itself.

#### Step 4 - Enable GitHub OAuth in your values

Creating the secret is not enough on its own - you also need to enable GitHub OAuth in your Helm values so that Developer Hub shows the "Sign in with GitHub" button and establishes user sessions. **Without this, `USER_OAUTH_TOKEN` will never be populated and every NaaS template run will fail at the "Publish to GitOps Repository" step.**

In your environment values file, set:

```yaml
developerHub:
  auth:
    github:
      enabled: true
      # For GitHub Enterprise only - full URL including https://
      # enterpriseInstanceUrl: "https://github.example.com"
      allowSignInWithoutCatalog: true   # permit users not yet in the catalog
```

> **Important:** For NaaS to work, users must sign in with their **GitHub account** (not as a guest). Guest sessions do not produce a `USER_OAUTH_TOKEN` and cannot raise PRs.

#### How the tokens are used at runtime

| Token | Source | Used for |
|---|---|---|
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | OAuth App | "Sign in with GitHub" - authenticates the user and establishes their session |
| `USER_OAUTH_TOKEN` | User's live GitHub OAuth session | Scaffolder actions - creates branch, commits, opens PR, adds labels on behalf of the developer |
| `GITHUB_TOKEN` | PAT in `github-auth-secret` | Backend - reads the three template YAML files and `skeleton/` files from GitHub at runtime |

### 1.3 Namespace Validator Plugin

The `namespace-validator` plugin is a **required component** of NaaS. When `naas.enabled: true`, the Helm chart unconditionally loads both the frontend and backend plugin packages using the OCI coordinates in the `namespaceValidator` block. The `namespaceValidator` block must therefore be present and populated whenever NaaS is enabled.

The plugin provides six custom fields and a scaffolder action used by all three templates:

| Component | Type | What it does |
|---|---|---|
| `naas:namespace:available` | Scaffolder action | Fails the provision template before any PR is created when the requested namespace already exists in the cluster |
| `NamespaceName` | Frontend field extension | Combines `projectName` + `environment` into a live availability indicator shown while the developer types |
| `OcGroupField` | Frontend field extension | Populates group pickers (Owner / Developer / Viewer) with live OpenShift group names from the cluster |
| `NaaSProjectField` | Frontend field extension | Fetches all NaaS-managed namespaces and pre-populates the Update template with the selected namespace's existing configuration |
| `NaaSDeleteField` | Frontend field extension | Fetches all NaaS-managed namespaces and renders the Delete template's selection and confirmation fields |
| `ArgoAppField` | Frontend field extension | Renders the ArgoCD Application wiring fields in both the Request and Update templates; pre-fills from stored namespace annotations when updating |

The plugin backend calls the OpenShift/Kubernetes API from within the cluster using the Developer Hub workload's service account. It requires the following least-privilege RBAC permissions:

```yaml
# Minimum cluster permissions required for the RHDH service account
# Namespace listing (all three templates)
apiGroups: [""]
resources: ["namespaces"]
verbs: ["get", "list"]

# OpenShift group listing (OcGroupField)
apiGroups: ["user.openshift.io"]
resources: ["groups"]
verbs: ["get", "list"]
```

#### Building and publishing the plugin OCI artifacts

Both plugin packages must be built from source, packaged as OCI images, and pushed to your private registry before NaaS can be enabled. The source for both packages lives under [`plugins/namespace-validator/`](../plugins/namespace-validator/).

**Prerequisites**

- Node.js ≥ 20 and npm installed on the build machine.
- `podman` (or equivalent OCI CLI) authenticated to your target registry.

**Step 1 - Update the `package-oci` script in each `package.json`**

The `package-oci` script in each plugin's `package.json` controls the OCI image reference that the build tool produces. Before building, update it to point at your registry and desired tag.

For the backend plugin (`plugins/namespace-validator/backend/package.json`):

```json
"package-oci": "npx --yes @red-hat-developer-hub/cli@latest plugin package --tag <your-registry>/<your-org>/namespace-validator-backend:<tag>"
```

For the frontend plugin (`plugins/namespace-validator/frontend/package.json`):

```json
"package-oci": "npx --yes @red-hat-developer-hub/cli@latest plugin package --tag <your-registry>/<your-org>/namespace-validator-frontend:<tag>"
```

Replace `<your-registry>`, `<your-org>`, and `<tag>` with your actual registry host, organization, and desired version tag (e.g. `1.0.0`).

**Step 2 - Build and push the backend plugin**

```bash
cd plugins/namespace-validator/backend

npm install
npm run build
npm run export-dynamic

# Packages the built plugin into an OCI image using the tag set in package-oci above
npm run package-oci

# Push the image to your registry
podman push <your-registry>/<your-org>/namespace-validator-backend:<tag>
```

**Step 3 - Build and push the frontend plugin**

```bash
cd plugins/namespace-validator/frontend

npm install
npm run build
npm run export-dynamic

# Packages the built plugin into an OCI image using the tag set in package-oci above
npm run package-oci

# Push the image to your registry
podman push <your-registry>/<your-org>/namespace-validator-frontend:<tag>
```

**Step 4 - Update the `namespaceValidator` values block**

Once both images are in the registry, set the matching coordinates in your Helm values:

```yaml
developerHub:
  catalog:
    naas:
      enabled: true
      namespaceValidator:
        ociRepository: "<your-registry>/<your-org>"   # registry prefix - no trailing slash
        frontendPackage: "namespace-validator-frontend"
        backendPackage: "namespace-validator-backend"
        version: "<tag>"                              # must match the tag used above
```

The Helm chart concatenates these fields into the OCI package references loaded by Developer Hub:

```
oci://<ociRepository>/<backendPackage>:<version>!namespace-validator-backend
oci://<ociRepository>/<frontendPackage>:<version>!namespace-validator-frontend
```

> **Missing OCI artifacts:** If the OCI images referenced in `namespaceValidator` cannot be pulled, Developer Hub will fail to load the dynamic plugins and the NaaS templates will not be usable. Ensure both artifacts are published and accessible from the cluster before enabling NaaS.

### 1.4 Enabling NaaS - Helm

NaaS is **disabled by default**. To enable it, set `developerHub.catalog.naas.enabled: true` in your values override and fill in the fields below. When `enabled` is `false`, neither the Software Template catalog entries nor the ArgoCD namespace-controller Application are deployed.

Open your environment values file (e.g. `deploy/helm/environments/<env>/values.yaml`) and configure the following:

```yaml
developerHub:
  catalog:
    github:
      enterpriseHost: ""                           # Leave empty for public GitHub, or set your GHE hostname
                                                   # (e.g. github.example.com - hostname only, no https://)
      target: "https://github.com/your-org"        # Full org URL (no trailing slash)

    naas:
      enabled: true
      repoName: "your-gitops-repo"                 # Repository name
      templateBranch: "main"                       # Branch holding the templates
      requestTemplatePath: "AI/quickstarts/fusion-developerhub/templates/naas/naas-request-template.yaml"
      updateTemplatePath: "AI/quickstarts/fusion-developerhub/templates/naas/naas-update-template.yaml"
      deleteTemplatePath: "AI/quickstarts/fusion-developerhub/templates/naas/naas-delete-template.yaml"
      gitopsRepoURL: "https://github.com/your-org/your-gitops-repo.git"
      namespacesPath: "namespaces"                 # Directory inside the repo where namespace manifests land

      # Namespace validator plugin - required when naas.enabled is true.
      # OCI coordinates for the built plugin artifacts.
      namespaceValidator:
        ociRepository: "your-registry.example.com/your-org"   # OCI registry prefix
        frontendPackage: "namespace-validator-frontend"        # OCI image name
        backendPackage: "namespace-validator-backend"          # OCI image name
        version: "latest"                                      # Image tag
```

The Helm chart assembles `github.enterpriseHost`, `github.target`, `naas.repoName`, `naas.templateBranch`, and each `naas.*TemplatePath` into three catalog location URLs - one for each template - that point Developer Hub at the correct YAML files in GitHub:

```
https://<enterpriseHost or github.com>/<org>/<repoName>/blob/<templateBranch>/<requestTemplatePath>
https://<enterpriseHost or github.com>/<org>/<repoName>/blob/<templateBranch>/<updateTemplatePath>
https://<enterpriseHost or github.com>/<org>/<repoName>/blob/<templateBranch>/<deleteTemplatePath>
```

**All configurable NaaS fields:**

| Values field | Description | Example |
|---|---|---|
| `catalog.github.enterpriseHost` | Hostname of your GitHub Enterprise instance (no `https://`). Leave empty for public GitHub. | `github.example.com` |
| `catalog.github.target` | Full org URL - used for catalog discovery and URL construction | `https://github.com/my-org` |
| `catalog.naas.enabled` | Feature toggle - set `true` to deploy the templates and ArgoCD controller | `true` |
| `catalog.naas.repoName` | Repository name that contains the template files | `my-platform-repo` |
| `catalog.naas.templateBranch` | Branch that holds the templates and `skeleton/` files | `main` |
| `catalog.naas.requestTemplatePath` | Relative path to the Request (Provision) template within the repo | `AI/quickstarts/fusion-developerhub/templates/naas/naas-request-template.yaml` |
| `catalog.naas.updateTemplatePath` | Relative path to the Update template within the repo | `AI/quickstarts/fusion-developerhub/templates/naas/naas-update-template.yaml` |
| `catalog.naas.deleteTemplatePath` | Relative path to the Delete template within the repo | `AI/quickstarts/fusion-developerhub/templates/naas/naas-delete-template.yaml` |
| `catalog.naas.gitopsRepoURL` | Full Git clone URL watched by the ArgoCD namespace-controller | `https://github.com/my-org/my-repo.git` |
| `catalog.naas.namespacesPath` | Repo-relative directory where provisioned namespace manifests land | `namespaces` |
| `catalog.naas.namespaceValidator.ociRepository` | OCI registry prefix for the validator plugin artifacts | `your-registry.example.com/your-org` |
| `catalog.naas.namespaceValidator.frontendPackage` | OCI image name for the frontend plugin | `namespace-validator-frontend` |
| `catalog.naas.namespaceValidator.backendPackage` | OCI image name for the backend plugin | `namespace-validator-backend` |
| `catalog.naas.namespaceValidator.version` | Image tag to pull | `latest` |

After updating, re-run your Helm upgrade (replace `<release>` with your Helm release name, and `<namespace>` with your Developer Hub namespace):

```bash
helm upgrade <release> ./deploy/helm \
  -f deploy/helm/values.yaml \
  -f deploy/helm/environments/<env>/values.yaml \
  -n <namespace>
```

### 1.5 Enabling NaaS - GitOps (ArgoCD `valuesObject`)

If Developer Hub is deployed via an ArgoCD `Application` (e.g. using the examples at [`deploy/gitops/environments/`](../deploy/gitops/environments/)), add the NaaS overrides directly to the `spec.source.helm.valuesObject` block. This avoids editing values files on disk - ArgoCD re-renders the Helm chart automatically when the Application manifest changes.

Open your `application.yaml` and add or update the following under `valuesObject`:

```yaml
# spec.source.helm.valuesObject in your ArgoCD Application manifest
developerHub:
  catalog:
    naas:
      enabled: true
      repoName: "your-gitops-repo"
      templateBranch: "main"
      gitopsRepoURL: "https://github.com/your-org/your-gitops-repo.git"
      namespaceValidator:
        ociRepository: "your-registry.example.com/your-org"  # REQUIRED, must point to your registry
        frontendPackage: "namespace-validator-frontend"
        backendPackage: "namespace-validator-backend"
        version: "latest"

argocd:
  enabled: true
  rbac:
    enabled: true
```

> **Minimal override:** The `valuesObject` block only needs to include the fields you are changing from the base `values.yaml` and the environment values file. The three `*TemplatePath` and `namespacesPath` fields default to the correct values for this repository and do not need to be repeated unless you have forked the templates to a different location. **`namespaceValidator.ociRepository` must always be set**, without it, Developer Hub cannot pull the plugin images and NaaS will not be usable. GitHub OAuth (`auth.github`) is configured in the environment values file and only needs to be added here if you are overriding it at the Application level (see section 1.2 Step 4).

The same field semantics apply as in section 1.4 - the table there covers every configurable value. The key difference is that `valuesObject` is inlined directly in the ArgoCD `Application` manifest rather than in a separate values file, so there is nothing to install or upgrade manually.

After editing, apply the change:

```bash
# If the Application already exists, patch it in place:
oc apply -f deploy/gitops/environments/<env>/application.yaml -n openshift-gitops

# Or commit and push - ArgoCD will self-sync if automated sync is enabled:
git add deploy/gitops/environments/<env>/application.yaml
git commit -m "chore: enable NaaS"
git push
```

ArgoCD detects the updated Application spec, re-renders the Helm chart with the new `valuesObject`, and applies the diff - enabling NaaS without any manual Helm commands.

### 1.6 Customizing the Template's Hidden Platform Fields

Inside each of the three template files (`naas-request-template.yaml`, `naas-update-template.yaml`, `naas-delete-template.yaml`), there is a set of **hidden fields** - parameters that developers never see in the wizard UI but that drive the template's behavior. Their `default:` values represent your deployment's live configuration.

> **Keep these in sync with your Helm values.** The hidden fields in each template drive the scaffolder (which repo to open the PR against, which branch to target, where to write manifests). The Helm values drive the ArgoCD controller (which repo and branch to watch) and the catalog URLs. They must point at the same repository, branch, and `namespacesPath`, or PRs will be raised to a location ArgoCD is not watching.

Look for the block that starts with `# Platform settings`:

```yaml
# Platform settings
# Set these defaults to match your deployment before registering this template.
githubHost:
  type: string
  ui:widget: hidden
  default: ''                       # Leave empty for public GitHub, or set your GHE hostname
                                    # (e.g. github.example.com)

repoOrg:
  type: string
  ui:widget: hidden
  default: 'your-org'               # GitHub organization that owns the GitOps repo

repoName:
  type: string
  ui:widget: hidden
  default: 'your-gitops-repo'       # Repository name

targetBranch:
  type: string
  ui:widget: hidden
  default: 'main'                   # Branch the PR should target

prReviewers:
  type: string
  ui:widget: hidden
  default: ''                       # Comma-separated GitHub usernames auto-added as PR reviewers
                                    # (optional - leave empty to skip)

namespacesPath:
  type: string
  ui:widget: hidden
  default: 'namespaces'             # Repo-relative directory where namespace manifests are stored
                                    # Must match catalog.naas.namespacesPath in values.yaml

argoCdInstance:
  type: string
  ui:widget: hidden
  default: 'openshift-gitops'       # Namespace of the ArgoCD instance managing this cluster

acmReplicate:
  type: string
  ui:widget: hidden
  default: 'false'                  # Set 'true' to replicate namespaces to ACM managed clusters

podSecurityStandard:
  type: string
  ui:widget: hidden
  default: 'baseline'               # 'privileged', 'baseline', or 'restricted'

catalogOwner:
  type: string
  ui:widget: hidden
  default: 'platform-team'          # Backstage group that owns catalog entries

catalogSystem:
  type: string
  ui:widget: hidden
  default: 'naas-platform'          # Backstage system the resource belongs to

consoleBaseUrl:
  type: string
  ui:widget: hidden
  default: 'https://console-openshift-console.apps.<cluster-domain>'  # OpenShift web console URL
                                    # Used in catalog-info.yaml for quick-access links

argocdBaseUrl:
  type: string
  ui:widget: hidden
  default: 'https://openshift-gitops-server-openshift-gitops.apps.<cluster-domain>'  # ArgoCD UI URL
                                    # Used in catalog-info.yaml for ArgoCD Application links
```

> **Tip:** Developer Hub re-fetches each template file from GitHub on every template run. You only need to push updated defaults to the configured branch - no redeployment of Developer Hub is required.

### 1.7 Deploying the ArgoCD NaaS Controller

When `catalog.naas.enabled: true` is set in your Helm values and `argocd.enabled: true` is also set, the chart renders and deploys an ArgoCD `Application` named `<release>-naas-controller`. This Application watches the `namespacesPath` directory in your GitOps repository and applies every manifest it finds there to the cluster.

The controller Application is deployed into the ArgoCD namespace specified by `argocd.rbac.namespace` (defaulting to `openshift-gitops`) and is configured from your Helm values:

```yaml
source:
  repoURL: <catalog.naas.gitopsRepoURL>
  targetRevision: <catalog.naas.templateBranch>
  path: <catalog.naas.namespacesPath>
  directory:
    recurse: true
    exclude: '**/catalog-info.yaml'   # Backstage entity - not a K8s manifest
destination:
  server: 'https://kubernetes.default.svc'
  namespace: <argocd.rbac.namespace>  # openshift-gitops by default
```

No manual `oc apply` is needed. Verify the Application is healthy after deployment:

```bash
oc get applications.argoproj.io -n openshift-gitops | grep naas-controller
```

The `syncPolicy` is set to `automated` with `selfHeal: true` and `prune: true`. This means:
- When a PR is merged adding a new `<namespacesPath>/<ns>/` directory, ArgoCD automatically applies those manifests to the cluster within the next sync cycle (with up to 5 retries using exponential backoff from 5s to 3m).
- When a PR is merged removing a directory (deletion request), ArgoCD removes all the corresponding Kubernetes resources including the namespace itself.
- If someone manually modifies a namespace label or quota outside of Git, ArgoCD will revert it to the Git-declared state.

`ServerSideApply=true` is enabled so that field managers are tracked correctly and large manifests don't hit client-side size limits.

The controller's `ignoreDifferences` configuration suppresses drift detection on `Namespace.status` and `ResourceQuota.status` fields, which are managed by the Kubernetes control plane and should not be treated as configuration drift.

> **ArgoCD permissions:** The naas-controller Application creates `Namespace` resources and cluster-scoped RBAC objects, so ArgoCD must have cluster-admin (or equivalent) permissions on the target cluster. This is standard for ArgoCD deployments via the OpenShift GitOps operator. If the Application shows a `ComparisonError` or `SyncFailed` related to permissions, verify that the ArgoCD service account has the required cluster role.

### 1.8 Customizing the Skeleton Manifests

The `skeleton/` directory contains Nunjucks template files that the scaffolder renders into real Kubernetes manifests when a developer submits a request. Here's what each file does and where you might want to adjust it for your environment:

#### `skeleton/namespace.yaml` - The Namespace itself

```yaml
metadata:
  name: ${{ values.projectName }}-${{ values.environment }}
  labels:
    naas.fusion.ibm.com/provisioned-by: namespace-as-a-service
    argocd.argoproj.io/managed-by: ${{ values.argoCdInstance }}
    apps.openclustermanagement.io/replicate: "${{ values.acmReplicate }}"
    business-unit: ${{ values.businessUnit }}
    environment: ${{ values.environment }}
    project: ${{ values.projectName }}
    naas.fusion.ibm.com/size: ${{ values.size }}
    naas.fusion.ibm.com/owner-group: ${{ values.ownerGroup }}
    pod-security.kubernetes.io/enforce: ${{ values.podSecurityStandard }}
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
  # annotations (rendered only when an ArgoCD Application is wired up at provision time):
  #   naas.fusion.ibm.com/argo-app-name: ...
  #   naas.fusion.ibm.com/argo-repo-url: ...
  #   naas.fusion.ibm.com/argo-target-revision: ...
  #   naas.fusion.ibm.com/argo-path: ...
  #   naas.fusion.ibm.com/argo-source-type: ...
```

The `naas.fusion.ibm.com/provisioned-by: namespace-as-a-service` label is the ownership marker. The namespace validator plugin filters on this label to populate the Update and Delete template selectors - only namespaces carrying this label are surfaced. **Do not remove it.**

Size and group information are stored as labels (`naas.fusion.ibm.com/size`, `naas.fusion.ibm.com/owner-group`, etc.) so the Update template can pre-populate its form without consulting any external database.

When an ArgoCD Application is wired up during provisioning, the Application details are stored as namespace annotations (`naas.fusion.ibm.com/argo-*`). The `ArgoAppField` plugin extension reads these annotations to pre-fill the ArgoCD step in the Update template.

Pod Security Standards admission labels (`pod-security.kubernetes.io/enforce`, `enforce-version`, `warn`, `warn-version`) are set at provision time from the `podSecurityStandard` hidden field. The `warn` label is always set to `restricted` to surface any workloads that would violate a stricter policy before enforcement is upgraded.

**What to customize:** Add any additional labels your organization requires for cost allocation, compliance tagging, or internal tooling. If your company has a specific label schema (e.g. `cost-center`, `data-classification`), add those here or promote them to template parameters.

#### `skeleton/resource-quota.yaml` - CPU, Memory, and Storage Caps

The quota is driven by the `size` parameter - `small`, `medium`, or `large`:

| Tier | CPU Requests | Memory Requests | CPU Limits | Memory Limits | Pods | Services | Storage | PVCs |
|------|-------------|-----------------|------------|---------------|------|----------|---------|------|
| Small | 4 | 8 Gi | 8 | 16 Gi | 20 | 10 | 100 Gi | 10 |
| Medium | 8 | 16 Gi | 16 | 32 Gi | 40 | 20 | 200 Gi | 20 |
| Large | 16 | 32 Gi | 32 | 64 Gi | 100 | 50 | 500 Gi | 50 |

**What to customize:** Adjust the values inside the `{%- if values.size == "small" %}` blocks to match your cluster's capacity and cost targets. You can also add more tiers (e.g. `xlarge`) by extending the `enum` in the template parameters and adding a corresponding branch in the resource quota file.

#### `skeleton/limit-range.yaml` - Per-Container Defaults

LimitRange sets default CPU/memory requests and limits on every container that doesn't specify its own. This prevents unbounded pods from exhausting quota. Defaults are scaled with the size tier:

| Tier | Container Default CPU | Container Default Memory | Container Max CPU | Container Max Memory | PVC Max Storage |
|------|-----------------------|--------------------------|-------------------|----------------------|-----------------|
| Small | 1 | 2 Gi | 4 | 8 Gi | 50 Gi |
| Medium | 2 | 4 Gi | 8 | 16 Gi | 100 Gi |
| Large | 4 | 8 Gi | 16 | 32 Gi | 200 Gi |

**What to customize:** Adjust the per-container defaults and maximums. A common pattern is to tighten these for `production` environments while keeping them relaxed for `development`.

#### `skeleton/network-policy.yaml` - Network Isolation

Four policies are applied by default:

1. **`default-deny-ingress`** - blocks all external ingress traffic to pods in the namespace.
2. **`allow-same-namespace`** - permits pod-to-pod traffic within the namespace.
3. **`allow-openshift-router`** - allows the OpenShift router to reach pods (required for Routes/Ingress).
4. **`allow-openshift-monitoring`** - allows Prometheus scraping from the `openshift-monitoring` namespace.

**What to customize:** If your platform has additional shared namespaces that need access (e.g. a centralized logging agent, a service mesh control plane), add `namespaceSelector` blocks to permit that ingress. To allow egress to specific services, add `Egress`-type policies.

#### `skeleton/rbac-role.yaml` - Roles and Bindings

Three roles are created inside every namespace:

- **`namespace-admin`** - full control (`*`), bound to the owner group and the CI/CD ServiceAccount.
- **`namespace-developer`** - day-to-day development permissions: deployments, pods, services, configmaps, jobs, and routes. Secrets are read-only.
- **`namespace-viewer`** - read-only (`get`, `list`, `watch`) for all resources.

A dedicated CI/CD ServiceAccount (`<projectName>-cicd`) is also created and bound to `namespace-admin`. Pipelines authenticate with this SA's token.

RoleBindings for the developer and viewer groups are emitted only when those groups are provided - if `developerGroup` or `viewerGroup` is left blank, the corresponding RoleBinding is omitted from the rendered output.

**What to customize:** If your organization has a tighter security posture, remove specific verbs from `namespace-developer` (e.g. remove `exec` on pods). If you run OpenShift Pipelines (Tekton), you may want to add a binding for the `pipeline` ServiceAccount.

#### `argocd/argocd-application.yaml` - ArgoCD Application (Optional)

This file is rendered only when the developer enables the **Create an ArgoCD Application?** toggle on the Request or Update template's fourth step. It produces an ArgoCD `Application` resource that targets the provisioned namespace:

```yaml
metadata:
  name: <applicationName>-<environment>
  namespace: <argoCdInstance>
  annotations:
    argocd.argoproj.io/sync-wave: "1"    # deploys after namespace infrastructure (wave 0)
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    namespace: <projectName>-<environment>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false           # namespace already exists from wave 0
```

**What to customize:** Add `ignoreDifferences` entries for resources ArgoCD cannot fully manage, or adjust the `syncPolicy` for manual-sync workflows.

### 1.9 Registering the Templates in Developer Hub

When `catalog.naas.enabled: true`, the Helm chart adds all three NaaS template URLs as catalog locations inside the **`app-config-catalog-locations`** ConfigMap — the single source of truth for all `catalog.locations` entries. Developer Hub loads this ConfigMap last, ensuring the NaaS locations are registered at startup.

The three catalog location URLs are assembled by the chart from your values:

```
https://<catalog.github.enterpriseHost or github.com>/<org>/<catalog.naas.repoName>/blob/<catalog.naas.templateBranch>/<catalog.naas.requestTemplatePath>
https://<catalog.github.enterpriseHost or github.com>/<org>/<catalog.naas.repoName>/blob/<catalog.naas.templateBranch>/<catalog.naas.updateTemplatePath>
https://<catalog.github.enterpriseHost or github.com>/<org>/<catalog.naas.repoName>/blob/<catalog.naas.templateBranch>/<catalog.naas.deleteTemplatePath>
```

The `<org>` segment is derived by stripping `https://<host>/` from `catalog.github.target`. Therefore, `catalog.github.target` must start with `https://` and include the correct host and organization prefix.

You can inspect the rendered ConfigMap on the cluster to confirm the URLs are correct:

```bash
oc get configmap app-config-catalog-locations -n <namespace> -o yaml
```

Check the `catalog.locations[].target` fields in the output. If a URL looks wrong, the most common cause is a mismatch between `catalog.github.target` (which must be a full org URL, e.g. `https://github.com/your-org`) and `catalog.naas.repoName`.

### 1.10 Pre-flight Checklist for Administrators

Before handing over NaaS to your developers, verify the following:

- [ ] `github-auth-secret` exists in the Developer Hub namespace with `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, and `GITHUB_TOKEN`.
- [ ] `auth.github.enabled: true` is set in your values so users can sign in with GitHub.
- [ ] `catalog.naas.enabled: true` is set in your values (Helm or GitOps `valuesObject`).
- [ ] `argocd.enabled: true` and `argocd.rbac.enabled: true` are set so the naas-controller Application is rendered.
- [ ] Both namespace-validator OCI artifacts are built, tagged, and pushed to the registry referenced in `namespaceValidator.ociRepository`.
- [ ] Helm values (`naas.repoName`, `naas.templateBranch`, `naas.gitopsRepoURL`, `naas.namespacesPath`) and the hidden fields in each template (`repoOrg`, `repoName`, `targetBranch`, `namespacesPath`) point at the same repository, branch, and path.
- [ ] The `app-config-catalog-locations` ConfigMap is present and the `catalog.locations[].target` URLs resolve to the three template files: `oc get configmap app-config-catalog-locations -n <namespace> -o yaml`.
- [ ] The `<release>-naas-controller` ArgoCD Application is in `Synced` / `Healthy` state: `oc get applications.argoproj.io -n openshift-gitops | grep naas-controller`.
- [ ] The Developer Hub service account has `get`/`list` on `namespaces` and `user.openshift.io/groups` in the cluster.
- [ ] At least one test namespace can be created end-to-end (signed in as a GitHub user, not guest) before announcing to the wider team.
- [ ] The OpenShift groups referenced in the `ownerGroup` field exist in the cluster before developers submit requests.

## 2. Developer Guide

This section is for **developers and team leads** who want to request a namespace for their project. No `oc` commands, no YAML - just fill in a form.

### 2.1 Accessing the Templates

> **You must be signed in with your GitHub account to use NaaS templates.** Guest sessions cannot raise Pull Requests. If you see "Sign in with GitHub" on the Developer Hub homepage, click it before proceeding.

1. Open Developer Hub in your browser. Your platform team will have shared the URL.
2. Sign in with your GitHub account using the **Sign in with GitHub** button (top right or on the homepage).
3. Click **Create** in the left sidebar (or the **+** icon).
4. Use the search box or filter by the tag **`naas`** to find the three NaaS templates:
   - **Request OpenShift Namespace (NaaS)** - create a new namespace.
   - **Update OpenShift Namespace (NaaS)** - resize or change access for an existing namespace.
   - **Delete OpenShift Namespace (NaaS)** - permanently remove a namespace.

### 2.2 Requesting a New Namespace

Click **Request OpenShift Namespace (NaaS)** and walk through the four-step wizard:

#### Step 1 - Namespace Details

| Field | Description | Example |
|---|---|---|
| **Project Name** | A unique lowercase identifier for your project. The final namespace will be `<projectName>-<environment>`. The field shows a live availability indicator as you type. | `payments-api` |
| **Environment** | Target environment tier: `Development`, `Staging`, or `Production`. | `Development` |
| **Business Unit / Cost Center** | Used for chargeback labels and resource attribution. | `Engineering` |

> **Naming rules:** Project names must start and end with a lowercase letter or digit, and may only contain lowercase letters, digits, and hyphens. The combined name `<projectName>-<environment>` must not already exist in the cluster and must be at most 63 characters.

#### Step 2 - Resource Sizing

Choose a pre-configured size tier that matches your workload:

| Tier | CPU Requests | Memory | Max Pods | Storage |
|------|-------------|--------|----------|---------|
| **Small** | 4 cores | 8 Gi | 20 | 100 Gi |
| **Medium** | 8 cores | 16 Gi | 40 | 200 Gi |
| **Large** | 16 cores | 32 Gi | 100 | 500 Gi |

Start small - you can always upsize later using the **Update** template.

#### Step 3 - Access Control

The group fields are populated from live OpenShift group names in the cluster via the namespace-validator plugin.

| Field | Description |
|---|---|
| **Owner Group** *(required)* | An existing OpenShift group whose members get **full admin** rights in the namespace. Typically your team's group name (e.g. `team-backend`). |
| **Developer Group** *(optional)* | An existing OpenShift group whose members get **developer** rights - create/update deployments, pods, services, and routes, but cannot modify cluster-level resources or write secrets. |
| **Viewer Group** *(optional)* | An existing OpenShift group whose members get **read-only** access - useful for stakeholders and auditors. |

> **Important:** The groups must already exist in the cluster. If your group hasn't been created yet, ask your platform team to provision it before submitting the request.

#### Step 4 - ArgoCD Application (Optional)

This step lets you wire an ArgoCD Application to the namespace at provision time. Set the toggle to **Yes** and fill in the repository details to have ArgoCD automatically deploy your application manifests into the new namespace.

| Field | Description | Example |
|---|---|---|
| **Create an ArgoCD Application?** | Toggle to `Yes` to reveal the ArgoCD fields. | `No` (default) |
| **Repository URL** | HTTPS URL of the application repository (required when toggle is Yes). | `https://github.com/my-org/my-app` |
| **Application Name** | Short name used as the ArgoCD Application name (lowercase, alphanumeric, hyphens). | `my-app` |
| **Target Revision** | Branch, tag, or commit SHA to track. | `main` |
| **Path** | Path within the repository where manifests or Helm chart live. Use `.` for the repo root. | `deploy/overlays/dev` |
| **Source Type** | How ArgoCD interprets the path: `Directory` (raw YAML/Kustomize) or `Helm chart`. | `Directory` |

Leave the toggle as **No** to skip ArgoCD wiring - you can add it later using the **Update** template.

#### Review and Submit

After you enter a valid **Project Name** and select an **Environment**, the wizard checks whether `<projectName>-<environment>` already exists in the cluster. You cannot continue while the namespace exists or its availability cannot be confirmed. A **Review** step then shows a summary of your selections (hidden platform fields are not displayed). Click **Create** to submit.

### 2.3 What Happens After You Submit

Immediately after clicking **Create**, the scaffolder runs through a sequence of automated steps - you can watch the progress in the output panel:

1. **Validate Namespace Availability** - the scaffolder checks `<projectName>-<environment>` directly with the cluster before generating files. The request fails before a PR is opened when the namespace exists or its availability cannot be determined.

2. **Fetch Manifest Skeleton** - the scaffolder renders the six core Kubernetes YAML files (namespace, resource quota, limit range, network policies, RBAC roles, and catalog entity) by substituting your wizard inputs into the skeleton templates. The rendered files are placed under `<namespacesPath>/<projectName>-<environment>/`.

3. **Fetch ArgoCD Application Skeleton** - if you opted in to ArgoCD wiring in Step 4, the scaffolder also renders `argocd-application.yaml` and places it alongside the other manifests. *(Conditional - skipped when the toggle is No.)*

4. **Publish to GitOps Repository** - the rendered files are pushed to a new branch named `naas-<projectName>-<environment>` in the GitOps repository, and a Pull Request is opened targeting the configured base branch. The PR description includes a formatted table of all your inputs. Configured reviewers (if any) are automatically added.

5. **Tag Pull Request Labels** - the PR is labelled with `NaaS - Provision`, `Project Name: <name>`, `Environment: <env>`, `Business Unit: <bu>`, and `Size: <size>` to make the PR easy to filter and audit.

6. **Register in Catalog** - a `Resource` entity for your new namespace is registered in the Developer Hub Software Catalog, so your team can discover it immediately without waiting for the PR to merge.

At the end of this sequence, the output panel shows two links:
- **View Pull Request** - takes you directly to the GitHub PR.
- **View Catalog Entry** - takes you to the namespace resource in the Developer Hub catalog.

> **Note:** The browser and scaffolder checks fail closed when cluster availability cannot be determined. They reduce duplicate requests, but they do not eliminate the time-of-check/time-of-use gap: a namespace can be created after validation and before ArgoCD applies the manifests. Cluster admission and ownership controls remain authoritative where strict global uniqueness is required.

### 2.4 Approval and Provisioning

The Pull Request is the **approval gate**. Your platform team reviews it. Once the PR is merged:

1. ArgoCD detects the new `<namespacesPath>/<projectName>-<environment>/` directory in the repository within its next sync cycle.
2. ArgoCD applies all manifests to the cluster. Namespace infrastructure (quota, limits, network policies, RBAC) syncs at wave 0; the ArgoCD Application (if wired) syncs at wave 1, after the namespace exists.
3. The namespace is live, fully configured, and ready for workloads.

You'll know provisioning is complete when:
- `oc get namespace <projectName>-<environment>` returns `Active`.
- `oc get resourcequota,limitrange,networkpolicy,role,rolebinding -n <projectName>-<environment>` shows all the expected objects.

### 2.5 Updating an Existing Namespace

Need more resources? Changed your team structure? Use the **Update OpenShift Namespace (NaaS)** template.

The first step presents a **Namespace Selection** compound field (`NaaSProjectField`) that:
1. Lists all NaaS-managed namespaces from the cluster (filtered by the `naas.fusion.ibm.com/provisioned-by=namespace-as-a-service` label).
2. Pre-populates Business Unit, Size, Owner Group, Developer Group, and Viewer Group from the selected namespace's stored labels.
3. Lets you edit any of those values before submitting.

The second step (ArgoCD Application) pre-fills from the namespace's stored `naas.fusion.ibm.com/argo-*` annotations when an ArgoCD Application was previously configured.

The update flow is otherwise identical to the provision flow:
- The PR branch is named `naas-update-<projectName>-<environment>`.
- The PR is labelled `NaaS - Update`.
- ArgoCD applies the updated manifests over the existing ones, changing only what has changed (thanks to `ServerSideApply`).

**Common update scenarios:**

| Scenario | What to change |
|---|---|
| Workload is growing, hitting quota limits | Increase the **Size** tier from `small` to `medium` or `large` |
| A new team joined the project | Add their group to **Developer Group** or **Viewer Group** |
| Cost center has changed | Update **Business Unit / Cost Center** |
| Transferring namespace ownership | Change the **Owner Group** to the new team's group |
| Adding GitOps deployment wiring | Enable the ArgoCD Application toggle and fill in the details |

> **Note:** Changing the **Project Name** or **Environment** fields in the Update template does not rename the namespace - it would create a new set of manifests at a different path. To rename a namespace, delete the old one and create a new one.

### 2.6 Deleting a Namespace

When a project is retired, use the **Delete OpenShift Namespace (NaaS)** template to cleanly deprovision everything.

#### What the deletion template does

The deletion template presents a **Namespace Selection** compound field (`NaaSDeleteField`) that lists only NaaS-managed namespaces. The template opens a PR that **removes** the following files from the GitOps repository for the selected namespace:

- `namespace.yaml`
- `resource-quota.yaml`
- `limit-range.yaml`
- `network-policy.yaml`
- `rbac-role.yaml`
- `catalog-info.yaml`
- `argocd-application.yaml` (if present)

When merged, ArgoCD detects the removed manifests and deprovisions all the Kubernetes objects - including the namespace itself - thanks to the `prune: true` setting on the ArgoCD Application.

#### Confirming the deletion

The deletion template includes a safety confirmation field (part of `NaaSDeleteField`):

> *Type the namespace name exactly as it will appear (`{projectName}-{environment}`) to confirm you intend to delete it.*

This is a deliberate friction point. Read it carefully before submitting. The PR is also labelled `NaaS - Delete` and is auto-assigned to configured reviewers.

> ⚠️ **Deletion is permanent.** Once the namespace is removed from Git and ArgoCD syncs, all workloads, persistent volume claims, and configuration inside the namespace are gone. Make sure you have backed up anything important before merging the deletion PR.

### 2.7 Viewing Your Namespaces in the Catalog

Every namespace provisioned through NaaS is registered as a `Resource` entity of type `openshift-namespace` in the Developer Hub Software Catalog. You can find your namespaces by:

1. Clicking **Catalog** in the left sidebar.
2. Filtering by **Kind: Resource** and searching for your project name.

This catalog entry is created at template submission time (before the PR is merged), so your team can discover the namespace immediately. The entity is kept in the catalog until the deletion PR is merged and the `catalog-info.yaml` file is removed from the repository.

## 3. Under the Hood

This section is for those who want to understand exactly how all the pieces fit together - useful for troubleshooting, extending the system, or satisfying curiosity.

### 3.1 The Three Software Templates

The NaaS system uses three separate Backstage `Template` YAML files, each registered as an independent catalog location:

| Template file | `metadata.name` | Purpose |
|---|---|---|
| `naas-request-template.yaml` | `openshift-naas-template` | Renders and publishes skeleton manifests as a GitOps PR |
| `naas-update-template.yaml` | `openshift-naas-update-template` | Overwrites existing manifests with new values; pre-populates from live cluster state |
| `naas-delete-template.yaml` | `openshift-naas-delete-template` | Opens a PR that removes manifests; ArgoCD prunes on merge |

Each template follows the same structure:
- **`parameters`** - the wizard UI definition. Hidden fields carry platform configuration as `default:` values. Visible fields collect developer inputs.
- **`steps`** - the automation sequence run server-side by the Backstage scaffolder when the form is submitted.
- **`output`** - links shown to the developer after the run completes.

### 3.2 The Provision Template's Steps

The provision template (`openshift-naas-template`) runs up to six steps in sequence:

```
naas:namespace:available  →  fetch:template  →  fetch:template (ArgoCD, conditional)
  →  publish:github:pull-request  →  github:issues:label  →  catalog:register
```

1. **`naas:namespace:available`** - checks the requested namespace through the in-cluster Kubernetes API and stops the workflow if it already exists or cannot be checked.
2. **`fetch:template` (skeleton)** - renders the `skeleton/` directory using the wizard inputs and platform defaults, placing the output at `<namespacesPath>/<projectName>-<environment>/`.
3. **`fetch:template` (ArgoCD)** *(conditional: `if: ${{ parameters.createArgoApp }}`)*  - renders `argocd/argocd-application.yaml` when the developer opted in to ArgoCD wiring, placing it alongside the other manifests.
4. **`publish:github:pull-request`** - commits the rendered files to a new branch and opens a PR against `targetBranch`. The `USER_OAUTH_TOKEN` from the developer's live GitHub session is used so the PR is authored by that developer.
5. **`github:issues:label`** - tags the PR with structured labels for easy filtering.
6. **`catalog:register`** - registers `catalog-info.yaml` as a Backstage `Resource` entity immediately, pointing at the `targetBranch` URL so the entity is discoverable before the PR is merged.

The availability check fails closed if the cluster API cannot determine whether the namespace exists. It does not remove the time-of-check/time-of-use gap before ArgoCD applies the namespace; cluster admission and ownership controls remain authoritative for strict global uniqueness.

### 3.3 The Skeleton Rendering Pipeline

The `fetch:template` action processes every file in the `skeleton/` directory using Nunjucks templating syntax. The `${{ values.* }}` placeholders in skeleton files are replaced with the values collected from the developer's form inputs and the hidden platform defaults.

For example, `skeleton/namespace.yaml`:

```yaml
# Skeleton (template)                           # Rendered output (example)
name: ${{ values.projectName }}-               # name: payments-api-
      ${{ values.environment }}                #       development
labels:
  naas.fusion.ibm.com/provisioned-by:          # naas.fusion.ibm.com/provisioned-by:
    namespace-as-a-service                     #   namespace-as-a-service
  business-unit: ${{ values.businessUnit }}    # business-unit: engineering
  argocd.argoproj.io/managed-by:              # argocd.argoproj.io/managed-by:
    ${{ values.argoCdInstance }}               #   openshift-gitops
  pod-security.kubernetes.io/enforce:          # pod-security.kubernetes.io/enforce:
    ${{ values.podSecurityStandard }}          #   baseline
```

Conditional blocks (using `{%- if %}` Nunjucks syntax) in `resource-quota.yaml`, `limit-range.yaml`, and `rbac-role.yaml` emit different content depending on the `size`, `developerGroup`, and `viewerGroup` values. The `namespace.yaml` annotations block is rendered only when `applicationName` is non-empty.

The rendered files are placed at `<namespacesPath>/<projectName>-<environment>/` relative to the repository root, ready to be pushed as a Pull Request.

### 3.4 The GitOps Pull Request Flow

The `publish:github:pull-request` action creates a branch (`naas-<projectName>-<environment>`) from the `targetBranch` configured in the hidden fields, commits all rendered manifests, and opens a PR. The PR description is a formatted Markdown table summarising the request.

The `github:issues:label` action then attaches metadata labels so the platform team can filter NaaS PRs at a glance:

| Template | Labels applied |
|---|---|
| Request | `NaaS - Provision`, `Project Name: <name>`, `Environment: <env>`, `Business Unit: <bu>`, `Size: <size>` |
| Update | `NaaS - Update`, `Project Name: <name>`, `Environment: <env>`, `Business Unit: <bu>`, `Size: <size>` |
| Delete | `NaaS - Delete`, `Project Name: <name>`, `Environment: <env>` |

Both public GitHub and GitHub Enterprise are supported. Set `githubHost` in the template's hidden fields to your GHE hostname (e.g. `github.example.com`) to route the PR action to the correct GitHub instance. Leave it empty to use `github.com`.

### 3.5 ArgoCD Sync Mechanics

The `<release>-naas-controller` ArgoCD Application watches the `namespacesPath` directory (recursively) in the GitOps repository:

```yaml
source:
  path: namespaces          # configurable via catalog.naas.namespacesPath
  directory:
    recurse: true
    exclude: '**/catalog-info.yaml'   # Backstage entity, not a K8s manifest
```

`catalog-info.yaml` is excluded from ArgoCD's scope because it is a Backstage resource, not a Kubernetes resource - applying it to the cluster would fail.

ArgoCD `ServerSideApply=true` is used so that large or complex manifests don't hit client-side size limits, and so field managers are tracked correctly.

The `prune: true` flag is the key to deletion: when the manifests directory for a namespace is removed from Git, ArgoCD removes the corresponding Kubernetes objects - including the `Namespace` itself - on the next sync.

The `ignoreDifferences` configuration on the naas-controller Application suppresses drift detection on `Namespace.status` and `ResourceQuota.status` fields, which are managed by the Kubernetes control plane and should not be treated as configuration drift.
