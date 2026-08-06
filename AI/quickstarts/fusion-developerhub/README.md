# IBM Fusion Developer Hub

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenShift](https://img.shields.io/badge/OpenShift-4.12+-red.svg)](https://www.redhat.com/en/technologies/cloud-computing/openshift)
[![Red Hat](https://img.shields.io/badge/Red%20Hat-Certified-red.svg)](https://www.redhat.com/)

IBM Fusion Developer Hub is an enterprise developer portal for IBM Fusion, built on Red Hat Developer Hub (Backstage). It provides a centralized experience for discovering AI models, quickstarts, blueprints, templates, documentation, and other curated resources available across your environment.

The portal integrates with OpenShift AI for automatic model discovery and OpenShift GitOps (ArgoCD) for lifecycle management, while supporting enterprise authentication and role-based access control.

---

## Table of Contents

1. [What You Get](#1-what-you-get)
2. [Architecture](#2-architecture)
3. [Repository Layout](#3-repository-layout)
4. [Prerequisites](#4-prerequisites)
5. [Deployment — Helm](#5-deployment--helm)
6. [Deployment — GitOps (ArgoCD)](#6-deployment--gitops-argocd)
7. [Verify & Access](#7-verify--access)
8. [Configure and Customize](#8-configure-and-customize)
   - [8.1 Customize Homepage](#81-customize-homepage)
   - [8.2 Customize the Catalog](#82-customize-the-catalog)
   - [8.3 Configure GitHub Integration](#83-configure-github-integration)
   - [8.4 Configure OIDC Authentication](#84-configure-oidc-authentication)
   - [8.5 OpenShift AI (RHOAI) Model Discovery](#85-openshift-ai-rhoai-model-discovery)
   - [8.6 Apply Your Changes](#86-apply-your-changes)
9. [Using Developer Hub](#9-using-developer-hub)
10. [IBM Fusion AI Service Discovery (CAS / DCS)](#10-ibm-fusion-ai-service-discovery-cas--dcs)
11. [Self-Service Software Templates](#11-self-service-software-templates)
12. [Console QuickStarts](#12-console-quickstarts)
13. [Upgrade](#13-upgrade)
14. [Troubleshooting](#14-troubleshooting)
15. [Additional Resources](#15-additional-resources)
16. [Support](#16-support)

---

## 1. What You Get

| Feature | Detail |
|---|---|
| **AI homepage** | Automatic OpenShift AI model discovery — KServe InferenceServices cataloged every 30 s |
| **Pre-built AI templates** | Chatbot, RAG, code generation, audio-to-text, object detection |
| **Software catalog** | Fusion components, NVIDIA blueprints, custom services |
| **GitHub integration** | GitHub.com and GitHub Enterprise |
| **OIDC authentication** | IBM ID, Okta, Auth0, Keycloak, Azure AD, Google Workspace, or any OIDC-compliant provider |
| **HA PostgreSQL** | 3-instance Crunchy cluster, automatic failover, daily backups to ODF (30-day retention) |
| **Enterprise security** | RBAC, network policies, pod security standards, secret encryption |
| **GitOps ready** | ArgoCD Application CRs with sync-wave ordering included |
| **CAS / DCS discovery** | IBM Fusion Content Aware Storage and Data Cataloging Service surfaced as catalog entities with MCP endpoints |

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Red Hat Developer Hub Operator  (namespace: rhdh-operator)  │
└──────────────────────┬──────────────────────────────────────┘
                       │ manages
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Developer Hub Instance  (namespace: fusion-developer-hub)   │
│  • 3 replicas (production)                                   │
│  • OpenShift AI Model Connector — discovers models every 30s │
└──────────────────────┬──────────────────────────────────────┘
                       │ connects to
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Crunchy PostgreSQL Operator  (namespace: postgres-operator)  │
│  • 3-instance HA cluster                                     │
│  • Primary (read-write) + 2 replicas                         │
│  • Automated daily backups to ODF                            │
└─────────────────────────────────────────────────────────────┘
                       │ queries (optional)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Red Hat OpenShift AI                                        │
│  • KServe InferenceServices auto-discovered                  │
│  • Model endpoints, metrics, and metadata surfaced in Hub    │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Repository Layout

```
quickstarts/fusion-developerhub/
├── deploy/
│   ├── helm/                                    # Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml                          # Default values
│   │   ├── templates/                           # Kubernetes resource templates
│   │   └── environments/
│   │       ├── dev/values.yaml                  # Development values
│   │       ├── staging/values.yaml              # Staging values
│   │       └── prod/values.yaml                 # Production values
│   └── gitops/
│       └── environments/
│           ├── dev/application.yaml             # ArgoCD Application CR — dev
│           ├── staging/application.yaml         # ArgoCD Application CR — staging
│           └── prod/application.yaml            # ArgoCD Application CR — production
├── fusion-ai-discovery/                         # CAS & DCS catalog entities
│   ├── catalog/
│   │   ├── locations.yaml                       # Catalog root index
│   │   └── platform-entities.yaml              # Domain, System, Group entities
│   ├── clusters/cluster-template/catalog-info.yaml
│   └── techdocs/
│       ├── cas/                                 # TechDocs for CAS API entity
│       └── dcs/                                 # TechDocs for DCS API entity
├── templates/                                   # Self-service RHDH Software Templates
│   ├── add-cas-cluster/template.yaml
│   ├── add-dcs-cluster/template.yaml
│   └── add-fusion-cluster/template.yaml
├── quickstarts/
│   └── console-quickstarts/
│       └── getting-started.yaml                 # OpenShift console interactive tutorial
├── docs/                                        # Supplemental reference documentation
│   ├── homepage-customization.md
│   ├── adding-fusion-services.md
│   ├── getting-started/
│   │   ├── oidc-providers.md
│   │   └── rhoai-integration.md
│   └── troubleshooting/
│       ├── postgresql-troubleshooting.md
│       ├── postgresql-connection-fix.md
│       ├── homepage-404-fix.md
│       └── crd-installation-fix.md
├── examples/                                    # Sample values files
├── scripts/                                     # Validation and diagnostic tools
└── assets/                                      # Screenshots and branding
```

---

## 4. Prerequisites

### Required

| Requirement | Details |
|---|---|
| Red Hat OpenShift | 4.12+ on IBM Fusion HCI (4.15+ for GitOps path) |
| Cluster admin access | Required for operator installation |
| `oc` CLI | Installed and logged in |
| Helm | 3.8+ ([install guide](https://helm.sh/docs/intro/install/)) |
| Storage | 100 GB available; RWX-capable storage class for Developer Hub |

### Optional but Recommended

| Requirement | Details |
|---|---|
| Red Hat OpenShift AI (RHOAI) | For automatic AI model discovery (can be disabled — see [Section 8.5](#85-openshift-ai-rhoai-model-discovery)) |
| OpenShift GitOps (ArgoCD) | Required for the GitOps deployment path only |

### Resource Requirements

| Profile | CPU | Memory | Storage |
|---------|-----|--------|---------|
| Guest / Dev (testing) | 2 cores | 4 GB | 20 GB |
| Production (HA) | 12 cores | 24 GB | 150 GB |

### Verify Prerequisites

```bash
# Confirm OpenShift version
oc version

# Confirm Helm version
helm version

# Find your cluster wildcard domain (you will need this value)
oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}'

# List available storage classes
oc get storageclass

# Check RHOAI installation (if using model discovery)
oc get dsc -n redhat-ods-operator
```

---

## 5. Deployment — Helm

Use Helm when you want a direct, one-command installation. All configuration is done locally in a values file before deploying.

### Step 1 — Clone the Repository

```bash
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/AI/quickstarts/fusion-developerhub
```

### Step 2 — Choose an Environment

Three pre-configured environments are available:

| Environment | Values file | Replicas (Hub / PG) | Auth | Best for |
|---|---|---|---|---|
| **Development** | `deploy/helm/environments/dev/values.yaml` | 1 / 1 | Guest + OIDC | Rapid testing |
| **Staging** | `deploy/helm/environments/staging/values.yaml` | 2 / 2 | OIDC | Pre-prod validation |
| **Production** | `deploy/helm/environments/prod/values.yaml` | 3 / 3 | OIDC (recommended) | Production workloads |

The following steps use **Production** as the example. Substitute `dev` or `staging` as needed.

### Step 3 — Configure the Values File

Open `deploy/helm/environments/prod/values.yaml` and make the two required changes below.

#### Required Change 1 — Cluster Domain

```bash
# Find your wildcard domain
oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}'
```

```yaml
# deploy/helm/environments/prod/values.yaml  (around line 6)
global:
  wildcardDomain: apps.<your-cluster-domain>.com   # ← replace with your domain
```

**Example:** if the command returns `apps.mycluster.example.com`, set:
```yaml
wildcardDomain: apps.mycluster.example.com
```

#### Required Change 2 — Storage Class

Developer Hub requires **ReadWriteMany (RWX)** storage. PostgreSQL uses ReadWriteOnce (RWO).

```bash
# List storage classes
oc get storageclass
```

```yaml
developerHub:
  storage:
    storageClassName: "ocs-storagecluster-cephfs"   # RWX — ODF CephFS example
    size: 5Gi

postgresql:
  storage:
    size: 20Gi
    storageClassName: "ocs-storagecluster-ceph-rbd"  # RWO — ODF RBD example
```

| Storage backend | RWX class (Hub) | RWO class (PostgreSQL) |
|---|---|---|
| OpenShift Data Foundation | `ocs-storagecluster-cephfs` | `ocs-storagecluster-ceph-rbd` |
| NFS | `nfs-client` (or your class) | `""` (cluster default) |
| Other | Your RWX class | `""` (cluster default) |

> Leave `storageClassName: ""` to use the cluster default.

### Step 4 — Deploy

```bash
helm install fusion-developer-hub \
  ./deploy/helm \
  -n fusion-developer-hub \
  --create-namespace \
  -f deploy/helm/environments/prod/values.yaml \
  --timeout 20m
```

**What happens during deployment:**

| Time | Action |
|---|---|
| ~2 min | Red Hat Developer Hub Operator installed |
| ~2 min | Crunchy PostgreSQL Operator installed |
| ~2 min | CRDs registered (`Backstage`, `PostgresCluster`) |
| ~5 min | PostgreSQL HA cluster provisioned (3 instances in prod) |
| ~5 min | Developer Hub deployed (3 replicas in prod) |
| ~1 min | OpenShift AI model connector configured |

### Step 5 — Monitor Deployment

```bash
# Watch operators reach Succeeded phase
watch oc get csv -n rhdh-operator
watch oc get csv -n postgres-operator

# Watch PostgreSQL cluster become Ready
watch oc get postgrescluster -n fusion-developer-hub

# Watch Developer Hub become Ready
watch oc get backstage -n fusion-developer-hub
```

**Expected output:**

```
# Operators
NAME                        PHASE
rhdh-operator.v1.x.x       Succeeded
crunchy-postgres-operator   Succeeded

# PostgreSQL
NAME                    STATUS   AGE
developerhub-postgres   Ready    5m

# Backstage
NAME             STATUS   AGE
developer-hub    Ready    8m
```

---

## 6. Deployment — GitOps (ArgoCD)

Use GitOps when you want all configuration tracked in Git and applied declaratively through ArgoCD. This is the recommended approach for production.

### Step 1 — Fork and Clone

GitOps requires your own fork so ArgoCD monitors your customizations.

1. Navigate to https://github.com/IBM/storage-fusion
2. Click **Fork** → select your account/organization
3. Clone your fork:

```bash
git clone https://github.com/<YOUR-USERNAME>/storage-fusion.git
cd storage-fusion/AI/quickstarts/fusion-developerhub
```

### Step 2 — Verify ArgoCD is Installed

```bash
oc get argocd -n openshift-gitops
```

If ArgoCD is not installed, follow the [Fusion GitOps quickstart guide](../../fusion-gitops-argocd/README.md).

### Step 3 — Choose an Environment

| Environment | Application CR | Sync policy |
|---|---|---|
| **Development** | `deploy/gitops/environments/dev/application.yaml` | Automated — auto-sync + self-heal |
| **Staging** | `deploy/gitops/environments/staging/application.yaml` | Automated — auto-sync + self-heal |
| **Production** | `deploy/gitops/environments/prod/application.yaml` | **Manual** — must explicitly approve |

The following steps use **Production**. Navigate to the file:

```bash
cd deploy/gitops/environments/prod
vim application.yaml
```

### Step 4 — Make the Three Required Changes

#### Required Change 1 — Repository URL

```yaml
spec:
  source:
    repoURL: https://github.com/<YOUR-USERNAME>/storage-fusion.git  # ← your fork
    targetRevision: main     # branch ArgoCD watches — must match what you push to
```

#### Required Change 2 — Cluster Domain

```bash
oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}'
```

```yaml
spec:
  source:
    helm:
      valuesObject:
        global:
          wildcardDomain: apps.<your-cluster-domain>.com   # ← replace
```

#### Required Change 3 — Storage Class (RWX)

```yaml
spec:
  source:
    helm:
      valuesObject:
        developerHub:
          storage:
            storageClassName: "ocs-storagecluster-cephfs"   # ← your RWX class
```

> `ocs-storagecluster-ceph-rbd` (RBD) only supports ReadWriteOnce — **it will not work here**.

### Step 5 — Commit and Push

```bash
git add deploy/gitops/environments/prod/application.yaml
git commit -m "Configure Fusion Developer Hub for production cluster"
git push origin main    # push to the branch set in targetRevision
```

### Step 6 — Apply the ArgoCD Application

```bash
# Log in to your cluster
oc login --server=https://api.your-cluster.com:6443

# Apply the Application CR
oc apply -f deploy/gitops/environments/prod/application.yaml

# Verify it was created
oc get application -n openshift-gitops
```

Expected initial output (normal):
```
NAME                     SYNC STATUS   HEALTH STATUS
fusion-developer-hub     OutOfSync     Missing
```

### Step 7 — Trigger the First Sync

**Production** (manual sync required):

```bash
# Option A — ArgoCD CLI
argocd app sync fusion-developer-hub --prune

# Option B — ArgoCD UI
# 1. Get ArgoCD URL:
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
# 2. Open in browser, find 'fusion-developer-hub', click Sync → Synchronize
```

**Development / Staging** (auto-sync enabled — ArgoCD picks up within 3 minutes):

```bash
# Trigger immediate sync if you don't want to wait:
argocd app sync fusion-developer-hub-development    # dev
argocd app sync fusion-developer-hub-staging        # staging
```

### Step 8 — Monitor GitOps Deployment

ArgoCD deploys resources in sync-wave order:

| Sync wave | Resources deployed |
|---|---|
| −10 | RBAC foundation |
| 0 | Namespaces |
| 10 | Pre-install jobs |
| 20 | OperatorGroups |
| 30 | Subscriptions (RHDH + PostgreSQL operators) |
| 40 | Operator validation |
| 50 | ConfigMaps, Secrets, Routes |
| 60 | PostgresCluster |
| 70 | Backstage (Developer Hub) |

```bash
# Watch application status
watch oc get application fusion-developer-hub -n openshift-gitops

# Watch resource creation
oc get all -n fusion-developer-hub -w
```

Expected healthy state:
```yaml
status:
  health:
    status: Healthy
  sync:
    status: Synced
  operationState:
    phase: Succeeded
```

---

## 7. Verify & Access

### Verify All Resources

```bash
NS=fusion-developer-hub

# Pods — expect 3 Hub + 3 PostgreSQL (production)
oc get pods -n $NS

# Operators
oc get csv -n rhdh-operator -o custom-columns=NAME:.metadata.name,PHASE:.status.phase
oc get csv -n postgres-operator -o custom-columns=NAME:.metadata.name,PHASE:.status.phase

# Custom resources
oc get backstage -n $NS
oc get postgrescluster -n $NS
```

**Expected pods (production):**
- 3 × `backstage-developer-hub-*` — Running
- 3 × `developerhub-postgres-instance*` — Running
- 1 × PostgreSQL backup pod — Completed

### Get the Developer Hub URL

```bash
DEVHUB_URL=$(oc get route -n fusion-developer-hub -o jsonpath='{.items[0].spec.host}')
echo "Open: https://$DEVHUB_URL"
```

### Verify Homepage Features

Open the URL in your browser. Log in with **Guest** access (click **Enter**) for initial verification:

- ✅ IBM Fusion AI homepage loads with branding
- ✅ Quick Access section visible (Blueprints, Docs, Models, Community)
- ✅ Catalog page lists components
- ✅ Guest login works (click **Enter**)
- ✅ AI models appear if OpenShift AI models are deployed

> **Production recommendation:** Guest access is enabled by default to simplify initial evaluation. Before going live, configure OIDC or GitHub OAuth and disable guest access (see [Section 8.3](#83-configure-github-integration) and [Section 8.4](#84-configure-oidc-authentication)).

### Run Validation Scripts

```bash
./scripts/check-deployment.sh
./scripts/check-homepage.sh
./scripts/validate-postgres-connection.sh
```

---

## 8. Configure and Customize

All customization is done by editing the values file for your chosen environment:

- **GitOps:** `deploy/helm/environments/{env}/values.yaml` → commit and push → ArgoCD auto-syncs
- **Helm:** same file → run `helm upgrade`

### 8.1 Customize Homepage

Edit `deploy/helm/environments/prod/values.yaml`:

```yaml
developerHub:
  config:
    title: "Acme Corp Developer Hub"
    organizationName: "Acme Corporation"

    homepage:
      enabled: true
      welcomeTitle: "Welcome to Acme Developer Hub"
      welcomeMessage: |
        Accelerate innovation with AI-powered development tools:
        • Generate code with IBM watsonx and Granite models
        • Modernize legacy applications automatically
        • Discover and integrate APIs intelligently

      # Company branding (leave empty "" to keep default Fusion branding)
      companyLogo: "https://cdn.acme.com/logo.png"     # 200x50 px, SVG/PNG, <50 KB
      companyLogoIcon: "https://cdn.acme.com/icon.png" # 32x32 px

      # Override the default quick access links
      # When set, these REPLACE the default links entirely.
      quickLinks:
        - title: "Create New Application"
          description: "Start with AI-powered templates"
          url: "/create"
          icon: "add"
        - title: "Browse Catalog"
          description: "Discover components and services"
          url: "/catalog"
          icon: "catalog"
        - title: "View Documentation"
          description: "Access technical docs"
          url: "/docs"
          icon: "docs"
```

**Default quick link URLs** (include these if you want to keep the defaults alongside custom links):
- NVIDIA Blueprints: `/catalog?filters%5Bkind%5D=component&filters%5Btype%5D=blueprint&limit=20`
- Quickstarts: `/catalog?filters%5Bkind%5D=component&filters%5Btype%5D=quickstart&limit=20`
- Deployed Models: `/catalog?filters%5Bkind%5D=component&filters%5Btype%5D=model-server&limit=20`

**Logo tips:**
- Use SVG for crisp display at any resolution
- Must be publicly accessible (or use `data:image/svg+xml;base64,...` inline)
- Test on dark backgrounds — Developer Hub uses a dark theme

### 8.2 Customize the Catalog

The default catalog includes NVIDIA blueprints (RAG, AIQ, VSS) and IBM Fusion quickstarts. To add custom catalog sources:

```yaml
developerHub:
  config:
    catalog:
      enabled: true
      blueprints:
        enabled: true
        locations:
          # Your sources — COMPLETELY replaces the default Fusion blueprints
          - type: url
            target: https://github.com/your-org/your-repo/blob/main/catalog-info.yaml
            rules:
              - allow: [Component, API, System]
```

> **Important:** configuring `blueprints.locations` **completely overrides** the default NVIDIA blueprints. Copy the default entries from `deploy/helm/values.yaml` under `developerHub.catalog.blueprints.locations` if you want to keep them.

End users can also register catalog entries through the self-service templates at `/create` — no values file change required.

### 8.3 Configure GitHub Integration

#### GitHub.com (Public GitHub)

1. Create an OAuth App in GitHub: **Settings → Developer settings → OAuth Apps**
   - **Callback URL:** `https://<your-hub-url>/api/auth/github/handler/frame`
   - Save **Client ID** and **Client Secret**

2. Update `values.yaml`:

```yaml
developerHub:
  auth:
    environment: "production"   # disables guest access
    github:
      enabled: true
      clientId: "your-client-id"
      clientSecret: "your-client-secret"
```

#### GitHub Enterprise

1. Create OAuth App in your GitHub Enterprise instance:
   - **Homepage URL:** `https://<your-hub-url>`
   - **Callback URL:** `https://<your-hub-url>/api/auth/github/handler/frame`

2. Create a Kubernetes secret:

```bash
oc create secret generic github-auth-secret \
  -n fusion-developer-hub \
  --from-literal=GITHUB_CLIENT_ID='your-client-id' \
  --from-literal=GITHUB_CLIENT_SECRET='your-client-secret' \
  --from-literal=GITHUB_TOKEN='your-personal-access-token'   # repo scope
```

3. Update `values.yaml`:

```yaml
developerHub:
  auth:
    environment: "production"
    github:
      enabled: true
      enterpriseInstanceUrl: "https://github.company.com"
      allowSignInWithoutCatalog: false

  catalog:
    github:
      enabled: true
      target: https://github.company.com/your-org
      enterpriseHost: "github.company.com"   # no https://
      enableToken: true

  extraEnvs:
    secrets:
      - github-auth-secret
```

### 8.4 Configure OIDC Authentication

The chart supports any OIDC-compliant provider via the generic `oidc` configuration:

```yaml
developerHub:
  auth:
    environment: "production"   # disables guest access when set to production
    providers:
      oidc:
        enabled: true
        providerName: "Your Provider Name"
        clientId: "your-client-id"
        clientSecret: "your-client-secret"
        issuer: "https://your-provider.com"
        signIn:
          resolver: "emailMatchingUserEntityProfileEmail"
```

**Provider-specific issuer URLs:**

| Provider | Issuer URL |
|---|---|
| IBM ID | `https://login.ibm.com/oidc/endpoint/default` |
| Okta | `https://your-domain.okta.com` |
| Auth0 | `https://your-tenant.auth0.com` |
| Keycloak | `https://keycloak.example.com/realms/your-realm` |
| Azure AD | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| Google | `https://accounts.google.com` |

**Redirect URI to register in your provider:**
```
https://<your-developer-hub-url>/api/auth/oidc/handler/frame
```

**Sign-in resolvers:**

| Resolver | When to use |
|---|---|
| `emailMatchingUserEntityProfileEmail` | Match OIDC email to user entity profile email (default) |
| `emailLocalPartMatchingUserEntityName` | Use local part of email (before @) as entity name |
| `preferredUsernameMatchingUserEntityName` | Use `preferred_username` claim |

**Verify OIDC discovery endpoint:**
```bash
curl https://your-provider.com/.well-known/openid-configuration
```

### 8.5 OpenShift AI (RHOAI) Model Discovery

The RHOAI connector is **enabled by default** in production and staging. It automatically discovers KServe InferenceServices every 30 seconds.

#### Enable / Disable

```yaml
developerHub:
  fusion:
    ai:
      rhoaiConnector:
        enabled: true   # set false to disable model discovery
        tokenSecretName: "rhdh-rhoai-connector-token"
        rbac:
          create: true    # auto-creates ClusterRole + ClusterRoleBinding
          watchNamespaces: []   # empty = watch all namespaces
```

#### Namespace Scoping

```yaml
rbac:
  create: true
  watchNamespaces:
    - model-serving
    - maas-runtime
    - redhat-ods-applications
    - your-custom-namespace
```

#### Create the Token Secret

```bash
# Get your RHOAI access token from OpenShift AI → Settings → Access Tokens
oc create secret generic rhdh-rhoai-connector-token \
  --from-literal=token=<YOUR_RHOAI_TOKEN> \
  -n fusion-developer-hub
```

#### Verify Model Connector

```bash
# Check connector logs
oc logs -n fusion-developer-hub \
  -l rhdh.redhat.com/app=backstage-developer-hub \
  -c rhoai-normalizer

# Verify the container is running
oc get pods -n fusion-developer-hub \
  -l rhdh.redhat.com/app=backstage-developer-hub \
  -o jsonpath='{.items[0].spec.containers[*].name}'
```

Expected log output when working:
```
[RHOAI Connector] Found 5 InferenceServices across 2 namespaces
[RHOAI Connector] Successfully registered models in catalog
```

#### What Gets Disabled (if you turn it off)

- Automatic InferenceService discovery
- Model catalog integration with RHOAI
- Model endpoint and metadata display
- RHOAI-specific sidecars

The custom homepage, quick access links, Fusion AI templates, software catalog, and TechDocs **remain fully functional** regardless.

### 8.6 Apply Your Changes

#### GitOps

```bash
git add deploy/helm/environments/prod/values.yaml
git commit -m "Customize Developer Hub homepage and catalog"
git push origin main        # push to the branch set in targetRevision

# ArgoCD auto-syncs within 3 minutes, or trigger immediately:
argocd app sync fusion-developer-hub

# Verify
argocd app get fusion-developer-hub
```

#### Helm

```bash
helm upgrade fusion-developer-hub \
  ./deploy/helm \
  -n fusion-developer-hub \
  -f deploy/helm/environments/prod/values.yaml

oc rollout status deployment/backstage-developer-hub -n fusion-developer-hub
```

---

## 9. Using Developer Hub

### 9.1 Authentication

By default, the quickstart enables **Guest Access** for easy evaluation:

- Click **Enter** on the homepage to log in immediately without credentials.
- If you see a GitHub login error, ignore it — use Guest access for testing.

> **Before production:** configure GitHub OAuth or OIDC and set `auth.environment: "production"` to require real credentials.

### 9.2 Homepage

The homepage is your central hub. It has four quick-access sections:

**1. Blueprints & Quickstarts**
- Fusion Quickstarts — IBM Fusion AI quickstart guides
- NVIDIA Blueprints — RAG, AIQ, VSS blueprints

**2. Documentation**
- [IBM Fusion HCI Documentation](https://www.ibm.com/docs/en/fusion-hci-systems/2.13.0)
- [IBM Fusion SDS Documentation](https://www.ibm.com/docs/en/fusion-software/2.13.0)

**3. Deployed AI Models**
- All models discovered automatically from OpenShift AI Model Registry
- Click any model to see endpoints, metrics, and authentication requirements

**4. Resources & Community**
- [Fusion Tech Community](https://ibm.github.io/storage-fusion/fusion-ai/overview/) — articles, architecture patterns, best practices
- [IBM Tech Exchange](https://community.ibm.com/community/user/groups/community-home/recent-community-blogs?communitykey=e596ba82-cd57-4fae-8042-163e59279ff3) — blogs, use cases, Q&A

### 9.3 Software Catalog

Navigate to **Catalog** in the left menu:

- **Automatic discovery** — OpenShift AI models appear automatically
- **Filter by Kind** — Component, API, System, Resource
- **Filter by Type** — model-server, service, blueprint, quickstart
- **Search** across all entries

**Browse a blueprint:**
1. Go to Catalog → filter Type: `blueprint`
2. Click **NVIDIA RAG Blueprint**
3. View description, GitHub link, TechDocs, and related components

### 9.4 Self-Service Templates

Click **Create** (or **Self-service** top-right) to access AI application templates:

| Template | Description |
|---|---|
| **Audio to Text Application** | AI-enabled audio transcription using whisper |
| **Chatbot Application** | LLM-enabled chat with llamacpp/vLLM |
| **Code Generation Application** | Generate code from natural language |
| **Model Server, No Application** | Deploy granite-3.1 8b with vLLM |
| **Object Detection Application** | Identify objects in images using DETR |
| **RAG Chatbot Application** | Chatbot with Retrieval-Augmented Generation |

**4-step creation wizard:**

1. **Application Information** — Name, owner, ArgoCD configuration
2. **Repository Information** — Git repository settings
3. **Deployment Information** — Deployment configuration
4. **Review** — Review and create

The wizard automatically creates a GitOps-managed deployment via ArgoCD.

### 9.5 Deploy and Discover AI Models

To deploy AI models that will be automatically discovered by Developer Hub, follow the [Model Serving Guide](../../fusion-model-serving/README.md).

After deployment:
1. Models appear on the homepage **within 30 seconds** (no restart required)
2. Navigate to **Catalog → Filter Type: model-server** to browse models
3. Each model entry shows: name, version, status, API endpoints, and metrics

---

## 10. IBM Fusion AI Service Discovery (CAS / DCS)

Surface IBM Fusion **CAS** (Content Aware Storage) and **DCS** (Data Cataloging Service) as discoverable catalog entries inside Developer Hub — with MCP endpoints, Swagger docs, TechDocs, and health checks — no VPN or cluster access required.

### How It Works

**Single source of truth: `values.yaml`.**

```
Edit: deploy/helm/environments/prod/values.yaml
  └─ developerHub.fusionServices.clusters[ ]

git push
  │
  ▼
ArgoCD syncs → Helm rerenders fusion-ai-clusters ConfigMap
  │
  ▼  (Kubernetes refreshes directory mount ~60 s, no pod restart)
  │
  ▼
RHDH catalog reads /opt/app-root/src/fusion-clusters/
  │
  ▼
5 entities appear in RHDH (~2 min total):
  System    fusion-<cluster-id>
  Component fusion-dcs-<cluster-id>    + MCP links
  API       fusion-dcs-mcp-api-<cluster-id>
  Component fusion-cas-<cluster-id>    + Swagger + health
  API       fusion-cas-mcp-api-<cluster-id>
```

Helm strips `https://api.` and `:6443` from `ocpApiUrl` to derive `<domain>`, then builds every URL automatically. **You never enter individual service URLs.**

### Add a Cluster — Self-hosted (ServiceAccount token access)

**Step 1** — Create ServiceAccount tokens on the Fusion cluster and add them to the `fusion-cluster-tokens` Secret on the RHDH cluster. See [deploy/gitops/environments/prod/RUNBOOK.md — Phase 1](deploy/gitops/environments/prod/RUNBOOK.md#phase-1--create-service-account-tokens-on-the-fusion-cluster).

**Step 2** — Add the cluster entry to `deploy/helm/environments/prod/values.yaml`:

```yaml
developerHub:
  fusionServices:
    clusters:
      - name: <cluster-id>                              # lowercase, no spaces
        ocpApiUrl: https://api.<cluster-domain>:6443   # from: oc login output
        clusterType: self-hosted
        services:
          dcs:
            enabled: true
            version: "<DCS_VERSION>"
            namespace: <DCS_NAMESPACE>
            k8s:
              tokenEnvVar: FUSION_<CLUSTER_ID_UPPER>_SA_TOKEN
              labelSelector: "app=isd,component=discover"
          cas:
            enabled: true
            version: "<CAS_VERSION>"
            namespace: <CAS_NAMESPACE>
            k8s:
              tokenEnvVar: FUSION_<CLUSTER_ID_UPPER>_CAS_SA_TOKEN
              labelSelector: "app.kubernetes.io/name=cas.isf.ibm.com"
```

> `CLUSTER_ID_UPPER` = cluster name uppercased, hyphens → underscores.
> Example: `my-cluster-01` → `MY_CLUSTER_01`

**Step 3** — Commit and push. ArgoCD syncs in ~30 s; entities appear ~30 s later.

### Add a Cluster — Proxy-only (no token access)

No secrets needed. Omit the `k8s:` block:

```yaml
developerHub:
  fusionServices:
    clusters:
      - name: <cluster-id>
        ocpApiUrl: https://api.<cluster-domain>:6443
        clusterType: proxy-only
        services:
          dcs:
            enabled: true
            version: "<DCS_VERSION>"
            namespace: <DCS_NAMESPACE>
          cas:
            enabled: true
            version: "<CAS_VERSION>"
            namespace: <CAS_NAMESPACE>
```

### Optional Fields

```yaml
clusters:
  - name: <cluster-id>
    ocpApiUrl: https://api.<cluster-domain>:6443
    clusterType: proxy-only          # proxy-only | self-hosted (enables K8s tab)
    services:
      dcs:
        enabled: true                # default: true
        version: "2.5.x"             # shown in entity description
      cas:
        enabled: true
        version: "2.13.x"
```

### Remove a Cluster

```yaml
# Collapse to empty list
clusters: []
```

```bash
git add deploy/helm/environments/prod/values.yaml
git commit -m "chore: remove <cluster-id> from Fusion AI discovery"
git push
```

Entities disappear on the next RHDH refresh. No `oc apply`. No pod restart.

### Auto-Derived URLs

| Service | URL pattern |
|---|---|
| DCS Console | `https://console-ibm-data-cataloging.apps.<domain>` |
| DCS MCP HTTP | `https://dcs-mcp-route-ibm-data-cataloging.apps.<domain>/mcp/http` |
| DCS MCP SSE | `https://dcs-mcp-route-ibm-data-cataloging.apps.<domain>/mcp` |
| CAS Console | `https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/overview` |
| CAS MCP | `https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/mcp` |
| CAS Swagger | `https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/docs` |
| CAS Health | `https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/health` |

### Diagnose CAS/DCS Catalog Issues

Run these four checks in order after a push:

```bash
NS=fusion-developer-hub

# 1. ConfigMap key present?
oc get cm fusion-ai-clusters -n $NS \
  -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}'

# 2. File mounted in the pod?
oc exec -n $NS deploy/backstage-developer-hub -c backstage-backend -- \
  ls /opt/app-root/src/fusion-clusters/

# 3. Catalog location registered?
oc get cm app-config-fusion-services -n $NS \
  -o jsonpath='{.data.app-config-fusion-services\.yaml}' | grep fusion-clusters

# 4. Entity ingestion logs
oc logs -n $NS deploy/backstage-developer-hub -c backstage-backend \
  | grep -i "fusion-\|catalog error" | tail -20
```

| Check | Expected | If wrong |
|---|---|---|
| 1 | `fusion-<cluster-id>-catalog-info.yaml` listed | Entry missing from `values.yaml` or ArgoCD not synced |
| 2 | Same file listed | ConfigMap not rendered — resolve check 1 first |
| 3 | `target: /opt/app-root/src/fusion-clusters` | `app-config-fusion-services` stale — force ArgoCD sync |
| 4 | No `catalog error` lines for your cluster | Entity YAML invalid — inspect the ConfigMap key |

### Force an ArgoCD Sync

```bash
oc patch application.argoproj.io fusion-developer-hub -n openshift-gitops \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"cli"},"sync":{"prune":true}}}'

oc get application.argoproj.io fusion-developer-hub -n openshift-gitops \
  -o jsonpath='Sync: {.status.sync.status}  Health: {.status.health.status}{"\n"}'
```

### When to Restart the Backstage Pod

ConfigMap directory mounts refresh automatically (~60 s). Only restart when `app-config` itself changes:

| Change | Restart needed? |
|---|---|
| Add/remove cluster in `values.yaml` | **No** — directory mount auto-refreshes |
| Change `backend.reading.allow` | **Yes** |
| Change `integrations.github` | **Yes** |
| Change proxy endpoints | **Yes** |
| Change catalog locations | **Yes** |

```bash
NS=fusion-developer-hub
oc rollout restart deployment/backstage-developer-hub -n $NS
oc rollout status  deployment/backstage-developer-hub -n $NS
```

---

## 11. Self-Service Software Templates

The `templates/` directory contains RHDH Software Templates for onboarding Fusion clusters via the Developer Hub UI.

### Available Templates

| Template | Purpose |
|---|---|
| `add-cas-cluster` | Onboard a new CAS cluster to the catalog via the Hub UI |
| `add-dcs-cluster` | Onboard a new DCS cluster to the catalog via the Hub UI |
| `add-fusion-cluster` | Full cluster registration (skeleton-based) with guided wizard |
| `fusion-ai-template.yaml` | AI application template (chatbot, RAG, code gen, etc.) |

### Using the Templates

1. Open Developer Hub → click **Create** in the left navigation
2. Find the template under the **IBM Fusion** section
3. Click **Choose** and complete the 4-step wizard:
   - **Application Information** — cluster name, owner
   - **Repository Information** — your Git repo details
   - **Deployment Information** — namespace, cluster URL
   - **Review** — verify and submit

The template generates a `catalog-info.yaml` and commits it to your repository. ArgoCD picks up the change and RHDH ingests the new entities automatically.

> **Note:** The Software Template is a convenience GUI alternative to editing `values.yaml` directly. The authoritative cluster registration always remains the `fusionServices.clusters[]` entry in `values.yaml`.

### Deploy Templates Manually

```bash
# Register a single template
oc apply -f templates/add-cas-cluster/template.yaml -n fusion-developer-hub

# Or let ArgoCD manage them (recommended — already included in the Helm chart)
```

### Version Update Scenarios

#### Scenario A — Self-hosted cluster (GitOps / Helm)

```bash
# Step 1: Detect installed version
oc get pods -n <dcs-namespace> \
  -o jsonpath='{.items[0].spec.containers[0].image}' | grep -oP '\d+\.\d+\.\d+'

# Step 2: Update values.yaml
#   services.dcs.version: "2.5.x"   # ← new version
#   services.cas.version: "2.13.x"

# Step 3: Commit and push
git add deploy/helm/environments/prod/values.yaml
git commit -m "feat: update DCS to 2.5.x on <cluster-id>"
git push

# ArgoCD auto-syncs in ~30 s — no pod restart needed
```

#### Scenario B — Proxy-only cluster

Follow the same `values.yaml` edit as Scenario A. Entities are auto-refreshed via ConfigMap mount — no additional steps.

#### Scenario C — Template-registered cluster (re-run from UI)

1. Go to Developer Hub → **Create**
2. Run the same **Add IBM Fusion Cluster** template with the updated version
3. The template overwrites the existing `catalog-info.yaml` and commits

---

## 12. Console QuickStarts

Interactive guided tutorials that appear directly in the OpenShift web console.

### Available QuickStart

**Getting Started with IBM Fusion Developer Hub**
- **File:** `quickstarts/console-quickstarts/getting-started.yaml`
- **Duration:** ~15 minutes
- **Level:** Beginner

**What you'll learn:**
1. Navigate the Developer Hub interface
2. Create an AI-powered application using software templates
3. Use modernization tools
4. Deploy an application to OpenShift

### Deploy the QuickStart

```bash
# Deploy to your cluster
oc apply -f quickstarts/console-quickstarts/getting-started.yaml

# Verify
oc get consolequickstart fusion-getting-started
```

### Access in the OpenShift Console

1. Open your OpenShift web console
2. Click the **?** (help) icon — top-right corner
3. Select **Quick Starts** from the dropdown
4. Find **"Getting Started with IBM Fusion Developer Hub"**
5. Click **Start**

### Create a Custom QuickStart

```yaml
apiVersion: console.openshift.io/v1
kind: ConsoleQuickStart
metadata:
  name: my-custom-quickstart
spec:
  displayName: My Custom QuickStart
  durationMinutes: 10
  description: Guided tutorial for your feature
  introduction: |
    What this tutorial covers...
  tasks:
    - title: First Task
      description: |
        Step-by-step instructions...
      review:
        instructions: Did you complete the task?
        failedTaskHelp: |
          Troubleshooting guidance...
  conclusion: |
    Summary and next steps.
```

```bash
# Generate base64 icon for your QuickStart
base64 -i icon.svg | tr -d '\n'

# Validate before deploying
oc apply --dry-run=client -f my-quickstart.yaml

# Deploy
oc apply -f my-quickstart.yaml
```

---

## 13. Upgrade

### Helm Upgrade

```bash
# Step 1: Archive current configuration
cp deploy/helm/environments/prod/values.yaml \
   deploy/helm/environments/prod/value-v1-$(date +%b%Y | tr '[:upper:]' '[:lower:]').yaml

# Step 2: Pull latest chart
git pull origin main

# Step 3: Preview changes (optional, requires helm-diff plugin)
helm diff upgrade fusion-developer-hub \
  ./deploy/helm \
  -n fusion-developer-hub \
  -f deploy/helm/environments/prod/values.yaml

# Step 4: Upgrade
helm upgrade fusion-developer-hub \
  ./deploy/helm \
  -n fusion-developer-hub \
  -f deploy/helm/environments/prod/values.yaml \
  --timeout 20m

# Step 5: Verify
oc get pods -n fusion-developer-hub
oc get route -n fusion-developer-hub
```

### GitOps Upgrade (Snapshot-based)

The active configuration is always named `values.yaml`. Archive first, then update.

```
deploy/helm/environments/prod/
├── values.yaml                  ← CURRENT/ACTIVE config
├── value-v0-may2026.yaml        ← May 2026 snapshot
└── value-v1-june2026.yaml       ← June 2026 snapshot
```

```bash
# Step 1: Archive current config
cd storage-fusion/AI/quickstarts/fusion-developerhub/deploy/helm/environments/prod
cp values.yaml value-v1-june2026.yaml

# Step 2: Pull latest changes from IBM upstream
cd storage-fusion/AI/quickstarts/fusion-developerhub
git pull origin main

# Step 3: Resolve any merge conflicts, then commit
git add deploy/helm/environments/prod/
git commit -m "chore: Archive v1 (June 2026) and apply upstream updates"
git push origin main

# Step 4: Deploy via ArgoCD
#   Dev/Staging: auto-syncs within 3 minutes
#   Production:  review diff in ArgoCD UI → click Sync

# Step 5: Verify
oc get pods -n fusion-developer-hub
```

**Benefits of snapshot versioning:**
- No ArgoCD Application CR changes required
- Complete version history preserved
- Easy rollback — just copy a snapshot back to `values.yaml`
- Clear audit trail

### Rollback

#### Helm

```bash
helm history fusion-developer-hub -n fusion-developer-hub
helm rollback fusion-developer-hub <revision-number> -n fusion-developer-hub
```

#### GitOps

```bash
# Restore from a snapshot
cp deploy/helm/environments/prod/value-v0-may2026.yaml \
   deploy/helm/environments/prod/values.yaml

git add deploy/helm/environments/prod/values.yaml
git commit -m "rollback: Restore v0 (May 2026) configuration"
git push origin main
# ArgoCD auto-syncs or trigger manually
```

---

## 14. Troubleshooting

### Quick Health Check

```bash
NS=fusion-developer-hub

# Overall status
oc get pods,backstage,postgrescluster -n $NS

# Operators
oc get csv -n rhdh-operator
oc get csv -n postgres-operator

# Recent events
oc get events -n $NS --sort-by='.lastTimestamp' | tail -20

# Backstage logs
oc logs -n $NS -l rhdh.redhat.com/app=backstage-developer-hub --tail=100

# PostgreSQL logs
oc logs -n $NS \
  -l postgres-operator.crunchydata.com/cluster=developerhub-postgres --tail=50
```

---

### Problem: "CRDs are not installed" during Helm install

**Symptom:**
```
Error: no matches for kind "Backstage" in version "rhdh.redhat.com/v1alpha5"
Error: no matches for kind "PostgresCluster" in version "postgres-operator.crunchydata.com/v1beta1"
```

**Cause:** Helm validates all resources before install, but the CRDs only exist after operators are running.

**Fix:** The chart uses Helm hooks to handle this automatically. The install sequence is:

1. Pre-install: operator namespaces + subscriptions
2. Post-install weight 1: wait for operators to be `Succeeded`
3. Post-install weight 2: wait for CRDs (`Backstage`, `PostgresCluster`)
4. Post-install weight 5: create `PostgresCluster`
5. Post-install weight 10: create `Backstage`

Simply run the install command with `--timeout 20m` and it will handle the ordering. If it still hangs:

```bash
# Check operator status
oc get csv -n rhdh-operator
oc get csv -n postgres-operator

# View CRD waiter logs
oc logs -n fusion-developer-hub job/wait-for-crds

# Check install plans (manual approval may be required)
oc get installplan -n rhdh-operator
oc patch installplan <name> -n rhdh-operator \
  --type merge -p '{"spec":{"approved":true}}'
```

---

### Problem: PostgreSQL cluster not ready

```bash
# Get cluster details
oc describe postgrescluster developerhub-postgres -n fusion-developer-hub

# Check PostgreSQL pods
oc get pods -n fusion-developer-hub \
  -l postgres-operator.crunchydata.com/cluster=developerhub-postgres

# View primary logs
oc logs -n fusion-developer-hub \
  -l postgres-operator.crunchydata.com/role=master
```

**CREATEDB permission error** (`permission denied to create database`):

```bash
# Find the primary pod
PG_POD=$(oc get pods -n fusion-developer-hub \
  -l "postgres-operator.crunchydata.com/cluster=developerhub-postgres,postgres-operator.crunchydata.com/instance" \
  -o jsonpath='{.items[0].metadata.name}')

# Grant CREATEDB privilege
oc exec -n fusion-developer-hub "$PG_POD" -c database -- \
  psql -U postgres -c "ALTER USER \"developerhub-postgres\" CREATEDB;"

# Verify
oc exec -n fusion-developer-hub "$PG_POD" -c database -- \
  psql -U postgres -c "SELECT rolname, rolcreatedb FROM pg_roles WHERE rolname = 'developerhub-postgres';"
```

Expected:
```
       rolname        | rolcreatedb
----------------------+-------------
 developerhub-postgres | t
```

---

### Problem: Developer Hub pods not starting (CrashLoopBackOff)

```bash
# Get details
oc describe backstage developer-hub -n fusion-developer-hub

# Check pods with correct label
oc get pods -n fusion-developer-hub \
  -l rhdh.redhat.com/app=backstage-developer-hub

# View logs
oc logs -n fusion-developer-hub \
  -l rhdh.redhat.com/app=backstage-developer-hub --tail=100

# Check events for the pod
oc describe pod -n fusion-developer-hub <pod-name>
```

---

### Problem: Homepage shows 404

**Cause:** The `@backstage/plugin-home` dynamic plugin is not enabled.

```bash
# Check dynamic plugins ConfigMap
oc get configmap developerhub-dynamic-plugins -n fusion-developer-hub -o yaml

# Check app-config
oc get configmap developerhub-app-config -n fusion-developer-hub \
  -o jsonpath='{.data.app-config\.yaml}' | grep -A 5 "home:"

# Validate YAML (syntax errors cause blank homepage)
oc get configmap developerhub-app-config -n fusion-developer-hub \
  -o jsonpath='{.data.app-config\.yaml}' > /tmp/app-config.yaml
python3 -c "import yaml; yaml.safe_load(open('/tmp/app-config.yaml'))"

# Force pod restart to reload app-config
oc rollout restart deployment/backstage-developer-hub -n fusion-developer-hub
oc rollout status deployment/backstage-developer-hub -n fusion-developer-hub
```

**Quick link returns 404:** Ensure you're using relative URLs for internal pages:

```yaml
quickLinks:
  - title: "Create App"
    url: "/create"        # ✅ relative — built-in page
  # url: "/ai-assistant"  # ❌ may not exist
  - title: "IBM Docs"
    url: "https://www.ibm.com/docs"  # ✅ full URL for external links
```

---

### Problem: AI models not appearing on homepage

```bash
# Check rhoai-normalizer sidecar logs
oc logs -n fusion-developer-hub \
  -l rhdh.redhat.com/app=backstage-developer-hub \
  -c rhoai-normalizer

# Verify sidecar is present
oc get pods -n fusion-developer-hub \
  -l rhdh.redhat.com/app=backstage-developer-hub \
  -o jsonpath='{.items[0].spec.containers[*].name}'

# List InferenceServices across all namespaces
oc get inferenceservices --all-namespaces

# Check token secret exists
oc get secret rhdh-rhoai-connector-token -n fusion-developer-hub

# Check RBAC
oc get clusterrole rhoai-connector-reader
oc get clusterrolebinding rhoai-connector-reader-binding
```

---

### Problem: OIDC authentication not working

```bash
# Verify OIDC discovery endpoint is reachable
curl https://your-provider.com/.well-known/openid-configuration

# Check configuration in RHDH
oc get configmap developerhub-app-config -n fusion-developer-hub \
  -o yaml | grep -A 10 "oidc:"

# Check secrets
oc get secret -n fusion-developer-hub | grep oidc

# Check auth logs
oc logs -n fusion-developer-hub \
  -l rhdh.redhat.com/app=backstage-developer-hub | grep -i auth
```

**Common OIDC errors:**

| Error | Cause | Fix |
|---|---|---|
| `Invalid redirect URI` | Callback URL mismatch | Verify `https://<hub-url>/api/auth/oidc/handler/frame` in your provider |
| `Invalid client credentials` | Wrong Client ID or Secret | Recheck provider credentials |
| `Discovery endpoint not found` | Wrong issuer URL | Set `discoveryUrl` explicitly if provider uses non-standard path |
| `User not found after login` | Sign-in resolver mismatch | Check resolver config; verify user entities exist in catalog |

---

### Problem: Operators not installing

```bash
# Check subscriptions
oc get subscription -n rhdh-operator
oc get subscription -n postgres-operator

# Check install plans
oc get installplan -n rhdh-operator
oc get installplan -n postgres-operator

# Approve if manual approval is required
oc patch installplan <name> -n rhdh-operator \
  --type merge -p '{"spec":{"approved":true}}'
```

---

### Clean Up and Redeploy

```bash
# Uninstall Helm release
helm uninstall fusion-developer-hub -n fusion-developer-hub

# Remove namespace (deletes all resources)
oc delete namespace fusion-developer-hub

# Redeploy
helm install fusion-developer-hub \
  ./deploy/helm \
  -n fusion-developer-hub \
  --create-namespace \
  -f deploy/helm/environments/prod/values.yaml \
  --timeout 20m
```

### Collect Diagnostic Information

```bash
NS=fusion-developer-hub

# Full resource dump
oc get all -n $NS
oc get backstage,postgrescluster -n $NS -o yaml > resources.yaml

# Logs
oc logs -n $NS -l rhdh.redhat.com/app=backstage-developer-hub \
  --tail=200 > backstage.log
oc logs -n $NS \
  -l postgres-operator.crunchydata.com/cluster=developerhub-postgres \
  --tail=200 > postgres.log

# Helm values (if Helm deployment)
helm get values fusion-developer-hub -n $NS

# Environment info
oc version
helm version
```

---

## 15. Additional Resources

### Deployment and Configuration

| Resource | Link |
|---|---|
| Helm Quickstart Blog | [IBM Community — Fusion Developer Hub](https://community.ibm.com/community/user/blogs/anushka-jaiswal/2026/05/29/quickstart-developer-hub-on-ibm-fusion-with-redhat) |
| GitOps Quickstart Blog | [IBM Community — via GitOps](https://community.ibm.com/community/user/blogs/namita-singroha/2026/06/25/quickstart-fusion-developer-hub-via-gitops) |
| Version Management | [`deploy/helm/VERSION_MANAGEMENT.md`](deploy/helm/VERSION_MANAGEMENT.md) |
| Helm Architecture | [`deploy/helm/ARCHITECTURE.md`](deploy/helm/ARCHITECTURE.md) |
| Homepage customization reference | [`docs/homepage-customization.md`](docs/homepage-customization.md) |
| Adding Fusion services | [`docs/adding-fusion-services.md`](docs/adding-fusion-services.md) |
| OIDC provider reference | [`docs/getting-started/oidc-providers.md`](docs/getting-started/oidc-providers.md) |
| RHOAI integration deep-dive | [`docs/getting-started/rhoai-integration.md`](docs/getting-started/rhoai-integration.md) |

### IBM Fusion Docs

| Topic | Link |
|---|---|
| CAS | [Content Aware Storage](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=services-content-aware-storage-cas) |
| DCS | [Data Cataloging Service](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=services-data-cataloging) |
| Fusion HCI | [IBM Fusion HCI Documentation](https://www.ibm.com/docs/en/fusion-hci-systems/2.13.0) |
| Fusion SDS | [IBM Fusion SDS Documentation](https://www.ibm.com/docs/en/fusion-software/2.13.0) |

### AI Platform Components

| Component | Link |
|---|---|
| RHOAI Installation | [`../../fusion-openshift-ai/docs/01-RHOAI-Installation-Guide.md`](../../fusion-openshift-ai/docs/01-RHOAI-Installation-Guide.md) |
| Model Serving Guide | [`../../fusion-model-serving/README.md`](../../fusion-model-serving/README.md) |
| GitOps with ArgoCD | [`../../fusion-gitops-argocd/README.md`](../../fusion-gitops-argocd/README.md) |

### Troubleshooting References

| Guide | File |
|---|---|
| PostgreSQL connection issues | [`docs/troubleshooting/postgresql-troubleshooting.md`](docs/troubleshooting/postgresql-troubleshooting.md) |
| PostgreSQL CREATEDB fix | [`docs/troubleshooting/postgresql-connection-fix.md`](docs/troubleshooting/postgresql-connection-fix.md) |
| Homepage 404 fix | [`docs/troubleshooting/homepage-404-fix.md`](docs/troubleshooting/homepage-404-fix.md) |
| CRD installation fix | [`docs/troubleshooting/crd-installation-fix.md`](docs/troubleshooting/crd-installation-fix.md) |

### External Documentation

| Topic | Link |
|---|---|
| Red Hat Developer Hub Docs | [access.redhat.com](https://access.redhat.com/documentation/en-us/red_hat_developer_hub) |
| Backstage Docs | [backstage.io/docs](https://backstage.io/docs) |
| OpenShift QuickStarts Guide | [docs.openshift.com](https://docs.openshift.com/container-platform/latest/web_console/creating-quick-start-tutorials.html) |

---

## 16. Support

- **GitHub Issues:** [github.com/IBM/storage-fusion/issues](https://github.com/IBM/storage-fusion/issues)
- **IBM Fusion Support:** Contact your IBM Fusion support team
- **Red Hat Support:** [access.redhat.com/support](https://access.redhat.com/support)

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Commit your changes (`git commit -m "feat: describe the change"`)
4. Push and open a pull request

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
