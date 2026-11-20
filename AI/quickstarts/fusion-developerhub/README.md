# IBM Fusion Developer Hub

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenShift](https://img.shields.io/badge/OpenShift-4.12+-red.svg)](https://www.redhat.com/en/technologies/cloud-computing/openshift)
[![Red Hat](https://img.shields.io/badge/Red%20Hat-Certified-red.svg)](https://www.redhat.com/)

IBM Fusion Developer Hub is an enterprise developer portal for IBM Fusion, built on Red Hat Developer Hub (Backstage). It provides a single, centralized experience for discovering AI models, quickstarts, blueprints, self-service templates, documentation, and curated resources available across your environment.

The portal integrates with OpenShift AI for automatic model discovery and OpenShift GitOps (ArgoCD) for lifecycle management, while supporting enterprise authentication and role-based access control.

**Without a unified portal**, teams face scattered tools and documentation across multiple interfaces, no visibility into deployed AI models, manual resource discovery, and inconsistent application deployments. **Fusion Developer Hub** solves this with a single pane of glass for all AI development needs.

---

## Table of Contents

1. [What You Get](#1-what-you-get)
2. [Architecture](#2-architecture)
3. [What Gets Deployed](#3-what-gets-deployed)
4. [Repository Layout](#4-repository-layout)
5. [Prerequisites](#5-prerequisites)
6. [Deployment — Helm](#6-deployment--helm)
7. [Deployment — GitOps (ArgoCD)](#7-deployment--gitops-argocd)
8. [Verify & Access](#8-verify--access)
9. [Configure and Customize](#9-configure-and-customize)
   - [9.1 Customize Homepage](#91-customize-homepage)
   - [9.2 Customize the Catalog](#92-customize-the-catalog)
   - [9.3 Configure GitHub Integration](#93-configure-github-integration)
   - [9.4 Configure OIDC Authentication](#94-configure-oidc-authentication)
   - [9.5 OpenShift AI (RHOAI) Model Discovery](#95-openshift-ai-rhoai-model-discovery)
   - [9.6 Apply Your Changes](#96-apply-your-changes)
   - [9.7 Advanced Customizations](#97-advanced-customizations)
10. [Using Developer Hub](#10-using-developer-hub)
11. [IBM Fusion AI Service Discovery (CAS / DCS)](#11-ibm-fusion-ai-service-discovery-cas--dcs)
12. [Self-Service Software Templates](#12-self-service-software-templates)
13. [Console QuickStarts](#13-console-quickstarts)
14. [Upgrade](#14-upgrade)
15. [Troubleshooting](#15-troubleshooting)
16. [Additional Resources](#16-additional-resources)
17. [Support](#17-support)

---

## 1. What You Get

| Feature | Detail |
|---|---|
| **AI homepage** | Automatic OpenShift AI model discovery — KServe InferenceServices cataloged every 30 s |
| **Pre-built AI templates** | Chatbot, RAG, code generation, audio-to-text, object detection |
| **Software catalog** | Fusion components, NVIDIA blueprints (RAG, AIQ, VSS), custom services |
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

## 3. What Gets Deployed

**Operators (installed automatically):**
- Red Hat Developer Hub Operator — manages the Developer Hub lifecycle
- Crunchy PostgreSQL Operator — manages the PostgreSQL HA cluster

**Developer Hub (namespace: `fusion-developer-hub`):**

| Profile | Replicas | CPU (limit / request) | Memory (limit / request) | Network Policies |
|---|---|---|---|---|
| Development | 1 | 2000m / 500m | 4 Gi / 1 Gi | Disabled |
| Staging | 3 | 2000m / 1000m | 4 Gi / 2 Gi | Enabled |
| Production | 3 | 2000m / 1000m | 4 Gi / 2 Gi | Enabled |

- IBM Fusion AI homepage with OpenShift AI model connector
- Software catalog, self-service templates, TechDocs, Learning Paths
- RBAC, pod security standards, secret encryption

**PostgreSQL HA Cluster (namespace: `fusion-developer-hub`):**

| Profile | Instances | Backup | Network Policies |
|---|---|---|---|
| Development | 1 | Disabled | Disabled |
| Staging | 3 | Enabled (daily, ODF) | Enabled |
| Production | 3 | Enabled (daily, ODF, 30-day retention) | Enabled |

- 1 primary (read-write) + replicas (read-only)
- Automatic failover; backups to ODF via NooBaa S3

**High Availability & Security (Production):**
- 3 Developer Hub replicas + 3 PostgreSQL instances with automatic failover
- Daily automated backups with 30-day retention
- Prometheus metrics + Grafana dashboards enabled
- Network policies, RBAC, and pod security standards enforced

---

## 4. Repository Layout

```
quickstarts/fusion-developerhub/
├── deploy/
│   ├── helm/                                    # Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml                          # Default values (full schema reference)
│   │   ├── ARCHITECTURE.md                      # Helm chart architecture notes
│   │   ├── VERSION_MANAGEMENT.md                # Snapshot versioning guide
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
│   ├── clusters/cluster-template/               # Template for new cluster catalog-info
│   ├── k8s/
│   │   ├── sa-rbac.yaml                         # ServiceAccount RBAC for self-hosted clusters
│   │   └── secrets-template.yaml                # Secret template for cluster tokens
│   └── techdocs/
│       ├── cas/                                 # TechDocs for CAS API entity
│       ├── dcs/                                 # TechDocs for DCS API entity
│       └── fusion-ai-services/                  # TechDocs for Fusion AI Services guide
├── backstage/                                   # Catalog entries for Fusion quickstarts
│   ├── fusion-developerhub/catalog-info.yaml
│   ├── fusion-gitops/catalog-info.yaml
│   └── model-as-a-service/catalog-info.yaml
├── templates/                                   # Self-service RHDH Software Templates
│   ├── add-cas-cluster/template.yaml
│   ├── add-dcs-cluster/template.yaml
│   ├── add-fusion-cluster/template.yaml
│   ├── fusion-ai-template.yaml                  # AI application templates
│   └── naas/                                    # Namespace-as-a-Service templates
├── plugins/                                     # Custom RHDH plugins
│   └── namespace-validator/                     # Frontend + backend namespace validator
├── quickstarts/
│   └── console-quickstarts/
│       └── getting-started.yaml                 # OpenShift console interactive tutorial
├── docs/                                        # Supplemental reference documentation
│   ├── homepage-customization.md
│   ├── adding-fusion-services.md
│   ├── namespace-as-a-service.md
│   ├── getting-started/
│   │   ├── oidc-providers.md
│   │   └── rhoai-integration.md
│   └── troubleshooting/
│       ├── postgresql-troubleshooting.md
│       ├── postgresql-connection-fix.md
│       ├── homepage-404-fix.md
│       └── crd-installation-fix.md
├── examples/                                    # Sample values files for different profiles
├── scripts/                                     # Validation and diagnostic tools
└── assets/                                      # Screenshots, branding, learning-paths data
```

---

## 5. Prerequisites

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
| Red Hat OpenShift AI (RHOAI) | For automatic AI model discovery (can be disabled — see [Section 9.5](#95-openshift-ai-rhoai-model-discovery)) |
| OpenShift GitOps (ArgoCD) | Required for the GitOps deployment path only |

### Optional Kubernetes Secrets (not required for basic install)

Neither secret is needed for a basic deployment. Create them only when you enable the corresponding feature.

#### `fusion-cluster-tokens` — required only for `clusterType: self-hosted` clusters

Needed when registering a CAS/DCS cluster with `clusterType: self-hosted` under `fusionServices.clusters[]`. Proxy-only clusters require no token. See [Section 11](#11-ibm-fusion-ai-service-discovery-cas--dcs) and [RUNBOOK.md Phase 2](deploy/gitops/environments/prod/RUNBOOK.md#phase-2--create-serviceaccount-tokens-on-the-fusion-cluster) for full token creation steps.

```bash
oc create secret generic fusion-cluster-tokens \
  --from-literal=FUSION_<CLUSTER_ID_UPPER>_SA_TOKEN=<dcs-sa-token> \
  --from-literal=FUSION_<CLUSTER_ID_UPPER>_CAS_SA_TOKEN=<cas-sa-token> \
  -n <rhdh-namespace>
```

> `CLUSTER_ID_UPPER` = cluster name uppercased with hyphens replaced by underscores.
> Example: `my-cluster-01` → `MY_CLUSTER_01`

Then reference it in `values.yaml`:

```yaml
developerHub:
  extraEnvs:
    secrets:
      - name: fusion-cluster-tokens
```

#### `github-auth-secret` — required only when using GitHub OAuth or private catalog repos

Needed when `auth.github.enabled: true` or `catalog.github.enableToken: true`.

```bash
oc create secret generic github-auth-secret \
  --from-literal=GITHUB_TOKEN=<your-pat> \
  -n <rhdh-namespace>
# For GitHub OAuth also add:
#  --from-literal=GITHUB_CLIENT_ID=<id>
#  --from-literal=GITHUB_CLIENT_SECRET=<secret>
```

Then reference it in `values.yaml`:

```yaml
developerHub:
  extraEnvs:
    secrets:
      - name: github-auth-secret
```

### Resource Requirements

These are the namespace resource quotas enforced by the Helm chart:

| Profile | Namespace CPU quota | Namespace Memory quota | Min storage |
|---------|---------------------|------------------------|-------------|
| Development | 8 cores | 16 Gi | 25 Gi (5Gi hub PVC + 20Gi PG) |
| Staging | 32 cores | 64 Gi | 25 Gi |
| Production | 32 cores | 64 Gi | 25 Gi + backup storage (ODF) |

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

## 6. Deployment — Helm

Use Helm when you want a direct, one-command installation. All configuration is done locally in a values file before deploying.

> **Choose your deployment method:** Use Helm for direct one-command installs or quick evaluation. Use GitOps (Section 7) for production — it gives you a declarative, auditable, Git-driven deployment model where all changes are tracked and applied through ArgoCD.

### Step 1 — Clone the Repository

```bash
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/AI/quickstarts/fusion-developerhub
```

### Step 2 — Log in to OpenShift

```bash
oc login --server=https://api.your-cluster.com:6443
oc whoami   # verify
```

### Step 3 — Choose an Environment

Three pre-configured environments are available:

| Environment | Values file | Replicas (Hub / PG) | Auth | Best for |
|---|---|---|---|---|
| **Development** | `deploy/helm/environments/dev/values.yaml` | 1 / 1 | Guest + OIDC | Rapid testing |
| **Staging** | `deploy/helm/environments/staging/values.yaml` | 3 / 3 | OIDC | Pre-prod validation |
| **Production** | `deploy/helm/environments/prod/values.yaml` | 3 / 3 | OIDC (recommended) | Production workloads |

The following steps use **Production** as the example. Substitute `dev` or `staging` as needed.

### Step 4 — Configure the Values File

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

### Step 5 — Deploy

```bash
helm install fusion-developer-hub \
  ./deploy/helm \
  -n fusion-developer-hub \
  --create-namespace \
  -f deploy/helm/environments/prod/values.yaml \
  --timeout 20m
```

### Step 6 — Monitor Deployment

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

## 7. Deployment — GitOps (ArgoCD)

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

| Environment | Application CR | Target namespace | Branch | Sync policy |
|---|---|---|---|---|
| **Development** | `deploy/gitops/environments/dev/application.yaml` | `fusion-developer-hub-development` | `master` | Automated — auto-sync + self-heal |
| **Staging** | `deploy/gitops/environments/staging/application.yaml` | `fusion-developer-hub-staging` | `master` | **Manual** — must explicitly approve |
| **Production** | `deploy/gitops/environments/prod/application.yaml` | `fusion-developer-hub` | `master` | **Manual** — must explicitly approve |

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
    targetRevision: master   # must match the branch you push to
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
git push origin master   # must match targetRevision set above
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

**Development** (auto-sync enabled — ArgoCD picks up automatically):

```bash
# Trigger immediate sync if desired:
argocd app sync fusion-developer-hub-development    # dev
```

**Staging** (manual sync required — same as production):

```bash
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

## 8. Verify & Access

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

> **Production recommendation:** Guest access is enabled by default to simplify initial evaluation. Before going live, configure OIDC or GitHub OAuth and disable guest access (see [Section 9.3](#93-configure-github-integration) and [Section 9.4](#94-configure-oidc-authentication)).

### Run Validation Scripts

```bash
./scripts/check-deployment.sh
./scripts/check-homepage.sh
./scripts/validate-postgres-connection.sh
```

---

## 9. Configure and Customize

All customization is done by editing the values file for your chosen environment:

- **GitOps:** `deploy/helm/environments/{env}/values.yaml` → commit and push → ArgoCD auto-syncs
- **Helm:** same file → run `helm upgrade`

### 9.1 Customize Homepage

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

### 9.2 Customize the Catalog

The default catalog includes the following pre-configured entries:

**NVIDIA Blueprints:** RAG, AIQ, VSS

**IBM Fusion Quickstarts:** Developer Hub, GitOps, Model-as-a-Service

**Other:** NaaS (Namespace-as-a-Service) template, Storage Fusion repository

These are configured under `developerHub.catalog.blueprints.locations` in `deploy/helm/values.yaml` and rendered into the `app-config-fusion-blueprints` ConfigMap. To add custom catalog sources:

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

### 9.3 Configure GitHub Integration

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

**Key flags:**
- `enterpriseHost` — GitHub Enterprise hostname (enables enterprise API calls, no `https://`)
- `enterpriseInstanceUrl` — full URL for OAuth provider
- `enableToken: true` — enables token-based repo access
- `environment: "production"` — OAuth only, no guest access
- `environment: "development"` — OAuth + guest access both available

**Reference:** [Red Hat Developer Hub — GitHub Integration](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.9/html/integrating_red_hat_developer_hub_with_your_git_provider/integrate-with-github_integrating-rhdh-with-your-git-provider)

### 9.4 Configure OIDC Authentication

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

### 9.5 OpenShift AI (RHOAI) Model Discovery

The RHOAI connector is **enabled by default** in production and staging. It automatically discovers KServe InferenceServices every 30 seconds.

**Full configuration reference** (all options in one block):

```yaml
developerHub:
  fusion:
    ai:
      rhoaiConnector:
        enabled: true                              # set false to disable
        tokenSecretName: "rhdh-rhoai-connector-token"
        rbac:
          create: true                             # auto-creates ClusterRole + ClusterRoleBinding
          watchNamespaces:                         # empty = all namespaces
            - model-serving
            - maas-runtime
            - redhat-ods-applications
          modelRegistryNamespace: "rhoai-model-registries"   # or "odh-model-registries"
          modelRegistryRoleName: "registry-user-modelregistry-public"
  config:
    homepage:
      plugins:
        - name: openshift-ai-connector
          enabled: true
          config:
            discoveryInterval: 30s
            displayOptions:
              showMetrics: true
              showEndpoints: true
              showStatus: true
```

**Create the token secret:**

```bash
oc create secret generic rhdh-rhoai-connector-token \
  --from-literal=token=<YOUR_RHOAI_TOKEN> \
  -n fusion-developer-hub
```

**Verify connector is working:**

```bash
oc logs -n fusion-developer-hub \
  -l rhdh.redhat.com/app=backstage-developer-hub \
  -c rhoai-normalizer
```

**What gets disabled if you set `enabled: false`:** InferenceService discovery, model catalog integration, model endpoint/metadata display, RHOAI sidecars. Homepage, catalog, templates, and TechDocs remain functional.

> Deep-dive: [`docs/getting-started/rhoai-integration.md`](docs/getting-started/rhoai-integration.md)

### 9.6 Apply Your Changes

#### GitOps

```bash
git add deploy/helm/environments/prod/values.yaml
git commit -m "Customize Developer Hub homepage and catalog"
git push origin master   # push to the branch set in targetRevision

# For dev (auto-sync): ArgoCD picks up automatically
# For staging/prod (manual sync): trigger explicitly:
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

### 9.7 Advanced Customizations

- **Dynamic Plugins:** Add additional Backstage plugins — see [`deploy/helm/values.yaml`](deploy/helm/values.yaml)
- **TechDocs:** Configure documentation publishing — see `developerHub.techdocs` section in values
- **Resource Limits:** Adjust CPU/memory for Developer Hub and PostgreSQL
- **Monitoring:** Enable Prometheus metrics and Grafana dashboards
- **Backup Configuration:** Customize PostgreSQL backup schedules and retention

**Complete values reference:** [`deploy/helm/values.yaml`](deploy/helm/values.yaml)

---

## 10. Using Developer Hub

### 10.1 Authentication

By default, the quickstart enables **Guest Access** for easy evaluation:

- Click **Enter** on the homepage to log in immediately without credentials.
- If you see a GitHub login error, ignore it — use Guest access for testing.

> **Before production:** configure GitHub OAuth or OIDC and set `auth.environment: "production"` to require real credentials.

### 10.2 Homepage

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

### 10.3 Software Catalog

Navigate to **Catalog** in the left menu:

- **Automatic discovery** — OpenShift AI models appear automatically
- **Filter by Kind** — Component, API, System, Resource
- **Filter by Type** — model-server, service, blueprint, quickstart
- **Search** across all entries
- **Personal filters** — Owned and Starred items for quick access
- **Self-service** button to register new components

**Browse a blueprint:**
1. Go to Catalog → filter Type: `blueprint`
2. Click **NVIDIA RAG Blueprint**
3. View description, GitHub link, TechDocs, and related components

**View a deployed model:**
1. Go to Catalog → filter Type: `model-server`
2. Click any model to see name, version, lifecycle stage, tags, endpoints, and authentication requirements

### 10.4 Self-Service Templates

Click **Create** (or **Self-service** top-right) to access the available templates. What you see depends on which templates are registered in your catalog (see [Section 12](#12-self-service-software-templates)).

The IBM Fusion AI application template (`fusion-ai-template.yaml`) supports:

- Granite Code (Code Generation)
- Granite Chat (Conversational AI)
- watsonx models

The **`add-fusion-cluster`** template uses a 4-step wizard:
1. **Application Information** — cluster name, owner
2. **Repository Information** — Git repo details
3. **Deployment Information** — namespace, cluster URL
4. **Review** — verify and submit

This template commits a `catalog-info.yaml` to your repository via GitHub OAuth. Other templates (WXO, CAS, DCS) use different flows — see [Section 12](#12-self-service-software-templates) for details.

### 10.5 Deploy and Discover AI Models

To deploy AI models that will be automatically discovered by Developer Hub, follow the [Model Serving Guide](../../fusion-model-serving/README.md).

After deployment:
1. Models appear on the homepage **within 30 seconds** (no restart required)
2. Navigate to **Catalog → Filter Type: model-server** to browse models
3. Each model entry shows: name, version, status, API endpoints, and metrics

---

## 11. IBM Fusion AI Service Discovery (CAS / DCS)

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

## 12. Self-Service Software Templates

The `templates/` directory contains RHDH Software Templates for onboarding Fusion clusters via the Developer Hub UI.

### Available Templates

| Template | Purpose | Prerequisite |
|---|---|---|
| `add-wxo-instance` | Register a watsonx Orchestrate instance — generates `values.yaml` snippet, you commit and push | None — always visible |
| `add-cas-cluster` | Onboard a new CAS cluster to the catalog via the Hub UI | `fusionServices.enabled: true` |
| `add-dcs-cluster` | Onboard a new DCS cluster to the catalog via the Hub UI | `fusionServices.enabled: true` |
| `add-fusion-cluster` | Full cluster registration (skeleton-based) with guided wizard | GitHub OAuth token |
| `fusion-ai-template.yaml` | AI application template (chatbot, RAG, code gen, etc.) | None — always visible |

> `add-cas-cluster` and `add-dcs-cluster` are only rendered and mounted when `developerHub.fusionServices.enabled: true` is set in your `values.yaml`. They will not appear in the Hub UI otherwise.

### Add watsonx Orchestrate Instance

The **"Add watsonx Orchestrate Instance"** template is always available in the Hub (no extra prerequisites). It does **not** create entities automatically — it generates the exact `values.yaml` snippet you need, then you commit and push it yourself.

**Steps:**

1. Open Developer Hub → **Create** → find **"Add watsonx Orchestrate Instance"**
2. Fill in 4 fields: cluster name, WXO UI URL, OCP namespace, and optionally the version
3. Work through the **3 output tabs** in order:

**Tab 1 — Get the repo**

```bash
git clone https://github.com/<your-org>/storage-fusion.git
cd storage-fusion
git checkout <your-deployed-branch>
```

> Ask your platform engineer for the fork URL and deployed branch.

**Tab 2 — Edit values.yaml**

Open `AI/quickstarts/fusion-developerhub/deploy/helm/environments/<your-env>/values.yaml`. The template shows the exact snippet — paste it under `fusionServices.clusters:`.

For a **new** cluster entry:
```yaml
- name: <cluster-name>
  ocpApiUrl: ""
  clusterType: proxy-only
  services:
    wxo:
      enabled: true
      version: "<version>"
      namespace: <ocp-namespace>
      wxoUrl: "<wxo-ui-url>"
```

For an **existing** cluster entry, add only the `wxo:` block under its existing `services:` key.

**Tab 3 — Push and deploy**

```bash
git add AI/quickstarts/fusion-developerhub/deploy/helm/environments/<your-env>/values.yaml
git commit -m "feat(fusion): register WXO instance <cluster-name>"
git push origin <your-deployed-branch>
```

Then trigger an ArgoCD sync or `helm upgrade` — see [Section 9.6](#96-apply-your-changes). The WXO entry appears in the catalog after the sync completes.

### Using `add-fusion-cluster`

This template does a real Git commit (requires GitHub OAuth — see [Section 9.3](#93-configure-github-integration)):

1. Open Developer Hub → click **Create**
2. Find **"Add Fusion Cluster"** under the **IBM Fusion** section
3. Complete the 4-step wizard:
   - **Application Information** — cluster name, owner
   - **Repository Information** — your fork URL and branch
   - **Deployment Information** — namespace, cluster URL
   - **Review** — verify and submit
4. The template commits a `catalog-info.yaml` to your repository; RHDH ingests the entities automatically.

> For CAS and DCS cluster registration, use the `add-cas-cluster` / `add-dcs-cluster` templates or edit `values.yaml` directly (see [Section 11](#11-ibm-fusion-ai-service-discovery-cas--dcs)).

### Deploy Templates Manually

```bash
# Register a single template
oc apply -f templates/add-cas-cluster/template.yaml -n fusion-developer-hub

# Or let ArgoCD manage them (recommended — already included in the Helm chart)
```

---

## 13. Console QuickStarts

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

## 14. Upgrade

### Helm Upgrade

```bash
# Step 1: Archive current configuration
cp deploy/helm/environments/prod/values.yaml \
   deploy/helm/environments/prod/value-v1-$(date +%b%Y | tr '[:upper:]' '[:lower:]').yaml

# Step 2: Pull latest chart
git pull origin master

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
git pull origin master

# Step 3: Resolve any merge conflicts, then commit
git add deploy/helm/environments/prod/
git commit -m "chore: Archive v1 (June 2026) and apply upstream updates"
git push origin master

# Step 4: Deploy via ArgoCD
#   Dev: auto-syncs automatically
#   Staging/Production: review diff in ArgoCD UI → click Sync

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
git push origin master
# Dev: ArgoCD auto-syncs; Staging/Production: trigger sync manually in ArgoCD UI
```

---

## 15. Troubleshooting

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

## 16. Additional Resources

### Deployment and Configuration

| Resource | Link |
|---|---|
| Helm Quickstart Blog | [IBM Community — Fusion Developer Hub](https://community.ibm.com/community/user/blogs/anushka-jaiswal/2026/05/29/quickstart-developer-hub-on-ibm-fusion-with-redhat) |
| GitOps Quickstart Blog | [IBM Community — via GitOps](https://community.ibm.com/community/user/blogs/namita-singroha/2026/06/25/quickstart-fusion-developer-hub-via-gitops) |
| Version Management | [`deploy/helm/VERSION_MANAGEMENT.md`](deploy/helm/VERSION_MANAGEMENT.md) |
| Helm Architecture | [`deploy/helm/ARCHITECTURE.md`](deploy/helm/ARCHITECTURE.md) |
| Homepage customization reference | [`docs/homepage-customization.md`](docs/homepage-customization.md) |
| Adding Fusion services | [`docs/adding-fusion-services.md`](docs/adding-fusion-services.md) |
| Namespace-as-a-Service guide | [`docs/namespace-as-a-service.md`](docs/namespace-as-a-service.md) |
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
| Fusion GitOps Quickstart | [`../../fusion-gitops/README.md`](../fusion-gitops/README.md) |

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

## 17. Support

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
