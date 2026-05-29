# IBM Fusion Developer Hub - Operator-Based Deployment

This Helm chart deploys Red Hat Developer Hub with IBM Fusion AI components and PostgreSQL database on OpenShift, using an operator-based deployment strategy.

## Overview

This chart provides a complete Developer Hub deployment with:
- **Red Hat Developer Hub Operator** - Manages Developer Hub instances
- **Cloud Native PostgreSQL Operator** - Provides highly available PostgreSQL clusters
- **IBM Fusion AI Components** - AI models, modernization tools, and custom templates
- **Pre-configured Homepage** - IBM Fusion branding with quick start guides and AI capabilities
- **OpenShift Console QuickStart** - Interactive getting started tutorial in OpenShift Console
- **IBM Fusion Object Storage Integration** - For backups and TechDocs storage (optional)
- **OpenShift Data Foundation (ODF)** - Automatic bucket provisioning (optional)
- **High Availability** - Multi-instance PostgreSQL with automated failover
- **Automated Backups** - PostgreSQL backups to object storage
- **Enterprise Security** - Network policies, pod security standards, RBAC

## ✨ What's Included Out-of-the-Box

The chart comes pre-configured with a personalized IBM Fusion homepage featuring:

- **Welcome Message** - Highlighting AI-powered development and modernization capabilities
- **8 Quick Access Links** - One-click access to common tasks (Create App, AI Assistant, Modernization, etc.)
- **6 Featured Content Sections** - Organized guides for AI Development, Modernization, Quick Start, Templates, Tools, and Analytics
- **Timezone Clocks** - UTC, NYC, London, Tokyo for distributed teams
- **IBM Fusion Branding** - Professional appearance ready for enterprise use

No additional configuration needed - just deploy and start using!

## Architecture

### Deployment Strategy

The chart follows an operator-based deployment pattern:

1. **Operator Installation**
   - Deploys Red Hat Developer Hub operator via OLM Subscription
   - Deploys Cloud Native PostgreSQL operator via OLM Subscription
   - Waits for operators to be ready before proceeding

2. **Database Provisioning**
   - Creates PostgreSQL Cluster CR using the PostgreSQL operator
   - Configures high availability with multiple instances
   - Sets up automated backups to object storage (optional)

3. **Developer Hub Instance**
   - Creates Backstage CR using the Developer Hub operator
   - Configures connection to PostgreSQL cluster
   - Sets up authentication, catalog, and TechDocs

4. **Storage Integration** (Optional)
   - Uses ObjectBucketClaim for automatic bucket creation
   - Configures PostgreSQL backups to object storage
   - Sets up TechDocs storage

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Red Hat Developer Hub Operator               │  │
│  │  (Namespace: rhdh-operator)                          │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          │ manages                           │
│                          ▼                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Developer Hub Instance                        │  │
│  │  (Namespace: developer-hub)                          │  │
│  │  - Backstage CR                                      │  │
│  │  - Frontend/Backend Pods                             │  │
│  │  - Route/Ingress                                     │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          │ connects to                       │
│                          ▼                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │    Cloud Native PostgreSQL Operator                  │  │
│  │  (Namespace: postgres-operator)                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          │ manages                           │
│                          ▼                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         PostgreSQL Cluster                           │  │
│  │  (Namespace: developer-hub)                          │  │
│  │  - Primary Instance                                  │  │
│  │  - Replica Instances (HA)                            │  │
│  │  - Automated Backups                                 │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          │ backs up to (optional)            │
│                          ▼                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │    Object Storage (ODF or External)                  │  │
│  │  - ObjectBucketClaim (optional)                      │  │
│  │  - PostgreSQL Backups                                │  │
│  │  - TechDocs Storage                                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required

- **OpenShift 4.12 or later**
- **Cluster admin access** (for operator installation)
- **OpenShift CLI (`oc`)** installed and logged in
- **Sufficient resources**:
  - Developer Hub: 2 CPU, 4Gi memory per replica
  - PostgreSQL: 1 CPU, 2Gi memory per instance
  - Storage: 20Gi for PostgreSQL data

### What Gets Installed Automatically

The chart **automatically handles all prerequisites** using Helm hooks:

✅ **Operator Namespaces** - Creates `rhdh-operator` and `postgres-operator` namespaces
✅ **OperatorGroups** - Configures operator scoping
✅ **Operator Subscriptions** - Installs RHDH and PostgreSQL operators from OLM
✅ **Operator Readiness Checks** - Waits for operators to be ready (Jobs with hooks)
✅ **Application Namespace** - Creates the Developer Hub instance namespace
✅ **PostgreSQL Database** - Deploys and configures the database cluster
✅ **Developer Hub Instance** - Creates the Backstage CR with full configuration

**No manual operator installation required!** The chart uses Helm hooks to ensure proper installation sequencing and avoid CRD timing issues.

### Optional Components

- **OpenShift Data Foundation (ODF)** - For PostgreSQL backups and TechDocs storage
- **Keycloak** - For OIDC authentication (can use external provider)

## Installation

### 🚀 Single-Command Installation

The chart handles everything automatically:

```bash
# Clone the repository
git clone <repository-url>
cd quickstarts/fusion-developerhub

# Install with guest access (fastest for demos/testing)
helm install fusion-hub-guest ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-guest-access-values.yaml \
  --create-namespace

# Monitor installation progress
oc get csv -n rhdh-operator -w  # Watch operator installation
oc get pods -n fusion-hub-guest -w  # Watch Developer Hub deployment
```

⚠️ **Warning**: Guest access allows anyone to access Developer Hub without authentication. Not recommended for production.

### Installation Timeline

The chart uses **Helm hooks** to ensure proper sequencing:

**Phase 1: Operator Installation** (2-3 minutes)
- Pre-install hooks create operator namespaces, OperatorGroups, and Subscriptions
- Operators are installed via OpenShift OLM

**Phase 2: Operator Readiness** (1-2 minutes)
- Post-install hook (Job) waits for operators to reach "Succeeded" status
- CRDs are registered and become available

**Phase 3: Resource Creation** (5-10 minutes)
- PostgreSQL Cluster is created (hook weight 5)
- Developer Hub Instance is created (hook weight 10)
- All resources become ready

**Total Time**: ~10-15 minutes for complete deployment

### Hook Execution Order

```
Pre-Install Hooks (weight -10 to -8):
├── -10: Create operator namespaces
├── -9:  Create OperatorGroups
└── -8:  Create Operator Subscriptions

Post-Install Hooks:
├── 1:   Wait for operators to be ready (Jobs)
├── 5:   Create PostgreSQL Cluster
└── 10:  Create Developer Hub Instance
```

**No CRD errors!** The hooks ensure operators are fully installed before creating Custom Resources.

### Quick Start (Minimal Configuration)

```bash
# Install with minimal Fusion AI configuration
helm install fusion-hub ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-minimal-values.yaml

# Or with inline configuration
helm install fusion-hub ./helm-charts/fusion-developer-hub \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --set developerHub.enabled=true \
  --set developerHub.fusion.enabled=true \
  --set operators.developerHub.enabled=true \
  --set operators.postgres.enabled=true
```

### Development Environment

```bash
# Install with development configuration
helm install fusion-dev-hub ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-development-values.yaml
```

### Production Environment

```bash
# Install with production configuration (HA, backups, security)
helm install fusion-hub-prod ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-production-values.yaml \
  --create-namespace
```

### With Keycloak Authentication

```bash
# Install with Keycloak integration
helm install fusion-hub-keycloak ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-keycloak-values.yaml \
  --create-namespace

# Keycloak is deployed automatically with the chart
```


### With IBM Fusion AI Features

```yaml
global:
  wildcardDomain: apps.your-cluster.example.com

# Enable operators
operators:
  enabled: true
  developerHub:
    enabled: true
  postgres:
    enabled: true

# Developer Hub with Fusion AI
developerHub:
  enabled: true
  replicas: 2
  
  config:
    title: "IBM Fusion Developer Hub"
    organizationName: "IBM Fusion"
  
  # IBM Fusion AI Configuration
  fusion:
    enabled: true
    api:
      baseUrl: "https://fusion-api.example.com"
    
    ai:
      enabled: true
      models:
        - name: watsonx
          type: llm
          endpoint: "https://watsonx-api.example.com"
        - name: granite-code
          type: code-assistant
          endpoint: "https://granite-code-api.example.com"
    
    modernization:
      enabled: true
      tools:
        - name: transformation-advisor
          enabled: true
        - name: mono2micro
          enabled: true
        - name: app-navigator
          enabled: true
  
  # Security Configuration
  security:
    networkPolicy:
      enabled: true
    podSecurityStandards:
      enabled: true
  
  # PostgreSQL with HA
  database:
    useOperator: true
    instances: 3
    storageSize: 50Gi
    backup:
      enabled: true
      useODF: true
  
  # Authentication
  auth:
    enabled: true
    oidc:
      enabled: true

### Operator Version Control

You can control which operator versions are installed:

```yaml
operators:
  developerHub:
    channel: fast  # or 'stable'
    startingCSV: "rhdh-operator.v1.2.0"  # Pin to specific version
    installPlanApproval: Manual  # Require manual approval for upgrades
  
  postgres:
    channel: stable
    startingCSV: "cloudnative-pg.v1.22.0"  # Pin to specific version
    installPlanApproval: Manual
```

**Finding Available Versions:**

```bash
# List available RHDH operator versions
oc get packagemanifest rhdh -n openshift-marketplace -o yaml

# List available PostgreSQL operator versions
oc get packagemanifest cloudnative-pg -n openshift-marketplace -o yaml

# Or use this command to see versions in a channel
oc get packagemanifest rhdh -n openshift-marketplace \
  -o jsonpath='{.status.channels[?(@.name=="fast")].currentCSV}'
```

**Version Pinning Strategies:**

1. **Latest (Default)**
   ```yaml
   startingCSV: ""  # Empty = latest in channel
   installPlanApproval: Automatic
   ```
   - **Pros**: Always up-to-date, automatic security patches
   - **Cons**: Unexpected changes, potential breaking updates
   - **Use**: Development, testing environments

2. **Pinned with Automatic Upgrades**
   ```yaml
   startingCSV: "rhdh-operator.v1.2.0"  # Start with specific version
   installPlanApproval: Automatic  # But allow automatic upgrades
   ```
   - **Pros**: Controlled starting point, automatic patches
   - **Cons**: Still allows automatic upgrades
   - **Use**: Staging environments

3. **Fully Pinned (Recommended for Production)**
   ```yaml
   startingCSV: "rhdh-operator.v1.2.0"  # Specific version
   installPlanApproval: Manual  # Require approval for upgrades
   ```
   - **Pros**: Full control, predictable behavior, tested upgrades
   - **Cons**: Manual upgrade process required
   - **Use**: Production environments

**Upgrading Operators:**

When using manual approval:

```bash
# List pending install plans
oc get installplan -n rhdh-operator

# Review install plan details
oc describe installplan <install-plan-name> -n rhdh-operator

# Approve upgrade
oc patch installplan <install-plan-name> \
  -n rhdh-operator \
  --type merge \
  -p '{"spec":{"approved":true}}'
```

      metadataUrl: "https://your-oidc-provider/.well-known/openid-configuration"
```

### Custom Configuration

Create a `values-developerhub.yaml` file:

```yaml
global:
  wildcardDomain: apps.your-cluster.example.com

# Enable operators
operators:
  enabled: true
  developerHub:
    enabled: true
    channel: fast
    namespace: rhdh-operator
  postgres:
    enabled: true
    channel: stable
    namespace: postgres-operator

# Developer Hub configuration
developerHub:
  enabled: true
  instanceName: developer-hub
  namespace: developer-hub
  replicas: 2
  
  config:
    title: "My Developer Hub"
    hostname: "devhub.apps.your-cluster.example.com"
  
  # PostgreSQL with HA
  database:
    useOperator: true
    clusterName: developerhub-postgres
    instances: 3  # High availability
    storageSize: 50Gi
    
    backup:
      enabled: true
      useODF: true  # Set to false if not using ODF
      retentionPolicy: "30d"
  
  # Authentication
  auth:
    enabled: true
    oidc:
      enabled: true
      metadataUrl: "https://your-oidc-provider/.well-known/openid-configuration"
  
  # Catalog
  catalog:
    enabled: true
    github:
      enabled: true
      target: https://github.com/your-org
```

Install with custom values:

```bash
helm install developer-hub ./fusion-developerhub/charts/fusion-developer-hub \
  -f values-developerhub.yaml
```

## Configuration

### Operator Configuration

#### Red Hat Developer Hub Operator

```yaml
operators:
  developerHub:
    enabled: true
    channel: fast              # Operator channel
    startingCSV: ""            # Leave empty for latest
    namespace: rhdh-operator   # Operator namespace
    watchAllNamespaces: false  # Watch all namespaces or just operator namespace
    installPlanApproval: Automatic
```

#### PostgreSQL Operator

```yaml
operators:
  postgres:
    enabled: true
    channel: stable                    # Operator channel
    startingCSV: ""                    # Leave empty for latest
    namespace: postgres-operator       # Operator namespace
    source: certified-operators        # Operator catalog source
    watchAllNamespaces: true           # Watch all namespaces
    installPlanApproval: Automatic
```

### Developer Hub Instance Configuration

#### Basic Settings

```yaml
developerHub:
  enabled: true
  instanceName: developer-hub
  namespace: developer-hub
  replicas: 2
  
  config:
    title: "Red Hat Developer Hub"
    hostname: ""  # Auto-generated if empty
```

#### PostgreSQL Database

```yaml
developerHub:
  database:
    useOperator: true
    clusterName: developerhub-postgres
    instances: 3  # Number of PostgreSQL instances for HA
    
    # PostgreSQL tuning
    maxConnections: "200"
    sharedBuffers: "256MB"
    effectiveCacheSize: "1GB"
    workMem: "16MB"
    
    # Storage
    storageSize: 20Gi
    storageClassName: ""  # Use default
    
    # Resources
    resources:
      limits:
        cpu: "2"
        memory: 4Gi
      requests:
        cpu: "1"
        memory: 2Gi
    
    # Backups (optional)
    backup:
      enabled: true
      useODF: true  # Use OpenShift Data Foundation
      odfStorageClass: openshift-storage.noobaa.io
      destinationPath: s3://developerhub-postgres-backup
      retentionPolicy: "30d"
```

#### Authentication

```yaml
developerHub:
  auth:
    enabled: true
    
    # GitHub OAuth
    github:
      enabled: true
      # Set GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET in secrets
    
    # OIDC (OpenShift, Keycloak, etc.)
    oidc:
      enabled: true
      metadataUrl: "https://your-oidc-provider/.well-known/openid-configuration"
      # Set OIDC_CLIENT_ID and OIDC_CLIENT_SECRET in secrets
```

Create authentication secrets:

```bash
# GitHub OAuth
oc create secret generic developerhub-secrets \
  -n developer-hub \
  --from-literal=GITHUB_CLIENT_ID=your-client-id \
  --from-literal=GITHUB_CLIENT_SECRET=your-client-secret

# OIDC
oc create secret generic developerhub-secrets \
  -n developer-hub \
  --from-literal=OIDC_CLIENT_ID=your-client-id \

## IBM Fusion AI Features

### AI Models

The chart integrates IBM Fusion AI models for enhanced development capabilities:

```yaml
developerHub:
  fusion:
    enabled: true
    ai:
      enabled: true
      models:
        - name: watsonx
          type: llm
          endpoint: "https://watsonx-api.example.com"
        - name: granite-code
          type: code-assistant
          endpoint: "https://granite-code-api.example.com"
        - name: granite-chat
          type: conversational
          endpoint: "https://granite-chat-api.example.com"
```

**Available Models:**
- **WatsonX**: General-purpose large language model for various AI tasks
- **Granite Code**: Specialized for code generation and assistance
- **Granite Chat**: Conversational AI for developer support

### Modernization Tools

Application modernization tools integrated into Developer Hub:

```yaml
developerHub:
  fusion:
    modernization:
      enabled: true
      tools:
        - name: transformation-advisor
          enabled: true
        - name: mono2micro
          enabled: true
        - name: app-navigator
          enabled: true
```

**Tools:**
- **Transformation Advisor**: Analyze Java applications for cloud migration
- **Mono2Micro**: Break monolithic applications into microservices
- **App Navigator**: Visualize application dependencies and architecture

### Fusion Templates

The chart includes IBM Fusion AI application templates:

- **Fusion AI Application**: Create AI-powered applications with WatsonX/Granite
- **Modernization Project**: Start application modernization initiatives
- **Microservices Application**: Generate cloud-native microservices
- **API Service**: Create RESTful APIs with AI assistance

Templates are automatically registered in the Developer Hub catalog.

## Security Configuration

### Network Policies

Network policies are enabled by default to control traffic:

```yaml
developerHub:
  security:
    networkPolicy:
      enabled: true
```

**Default Rules:**
- Allow ingress from OpenShift router
- Allow ingress from same namespace
- Allow egress to PostgreSQL
- Allow egress to Kubernetes API
- Allow egress for HTTPS (integrations)
- Allow DNS resolution

### Pod Security Standards

Pod security standards enforce security best practices:

```yaml
developerHub:
  security:
    podSecurityStandards:
      enabled: true
    
    # OpenShift SCC compliant
    podSecurityContext:
      runAsNonRoot: true
      runAsUser: null  # Let OpenShift assign

## Example Configurations

The chart includes five example configurations for different use cases:

### 1. Guest Access (`examples/operator-fusion-guest-access-values.yaml`)

No authentication required - fastest setup:
- Single replica Developer Hub
- Single PostgreSQL instance
- All Fusion AI features enabled
- Guest access (no authentication)
- Network policies disabled
- Minimal resources

**Use for**: Demos, quick testing, proof of concepts, training

⚠️ **Warning**: Allows anyone to access without authentication. Not for production!

```bash
helm install fusion-hub-guest ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-guest-access-values.yaml
```

### 2. Minimal Configuration (`examples/operator-fusion-minimal-values.yaml`)

Quick start with essential Fusion AI features:
- Single replica Developer Hub
- Single PostgreSQL instance
- Basic Fusion AI integration

## Keycloak Integration

The operator-based chart can integrate with Keycloak for self-contained authentication. Since the operator chart focuses on operator-managed components, Keycloak should be deployed separately.

### Deployment Strategy

1. **Deploy Developer Hub with Operator** (this chart)
2. **Deploy Keycloak separately** (using rhdh-fusion chart or manually)
3. **Configure Keycloak realm and client**
4. **Update Developer Hub with Keycloak OIDC settings**

### Step-by-Step Setup

#### Step 1: Deploy Developer Hub with Keycloak Configuration

```bash
# Deploy using Keycloak example
helm install fusion-hub-keycloak ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-keycloak-values.yaml
```

#### Step 2: Deploy Keycloak

Option A: Using rhdh-fusion chart (recommended):

```bash
# Deploy only Keycloak from rhdh-fusion chart
helm install keycloak ./helm-charts/rhdh-fusion \
  --namespace fusion-hub-keycloak \
  --set developerHub.enabled=false \
  --set postgresql.enabled=false \
  --set keycloak.enabled=true \
  --set keycloak.database.host=fusion-keycloak-postgres-rw \
  --set keycloak.database.port=5432 \
  --set keycloak.database.database=keycloak \
  --set keycloak.database.username=app \
  --set keycloak.route.host=keycloak-fusion-hub-keycloak.apps.your-cluster.example.com \
  --set global.clusterRouterBase=apps.your-cluster.example.com
```

Option B: Manual Keycloak deployment (see Keycloak documentation)

#### Step 3: Configure Keycloak

1. **Access Keycloak Admin Console**:
   ```bash
   # Get Keycloak URL

### 4. Keycloak Integration (`examples/operator-fusion-keycloak-values.yaml`)

Self-contained authentication with Keycloak:
- 2 replicas Developer Hub
- 2 PostgreSQL instances (shared by Developer Hub and Keycloak)
- All Fusion AI models and tools enabled
- Keycloak OIDC authentication
- Automated backups enabled
- Full security features

**Use for**: Organizations wanting self-contained authentication, no external OIDC dependency

```bash
helm install fusion-hub-keycloak ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-keycloak-values.yaml

# Then deploy Keycloak separately (see Keycloak Integration section)
```

   oc get route keycloak -n fusion-hub-keycloak
   
   # Get admin credentials
   oc get secret keycloak-secret -n fusion-hub-keycloak -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' | base64 -d
   ```

2. **Create Realm**:
   - Name: `fusion`
   - Display Name: `IBM Fusion Developer Hub`

3. **Create Client**:
   - Client ID: `backstage`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Valid Redirect URIs: `https://fusion-hub-keycloak-fusion-hub-keycloak.apps.your-cluster.example.com/*`
   - Web Origins: `https://fusion-hub-keycloak-fusion-hub-keycloak.apps.your-cluster.example.com`

4. **Get Client Secret**:
   - Navigate to Clients → backstage → Credentials
   - Copy the Secret value

#### Step 4: Create Authentication Secrets

```bash
# Create secret with Keycloak credentials
oc create secret generic fusion-hub-keycloak-secrets \
  -n fusion-hub-keycloak \
  --from-literal=OIDC_CLIENT_ID="backstage" \
  --from-literal=OIDC_CLIENT_SECRET="<keycloak-client-secret>"
```

#### Step 5: Restart Developer Hub

```bash
# Restart Developer Hub to pick up new secrets
oc rollout restart deployment -l app.kubernetes.io/component=developerhub -n fusion-hub-keycloak
```

### Keycloak Database Configuration

The example uses the same PostgreSQL cluster for both Developer Hub and Keycloak:

```yaml
database:
  clusterName: fusion-keycloak-postgres
  instances: 2  # Shared by Developer Hub and Keycloak
```

Keycloak will use a separate database within the same PostgreSQL cluster:
- Developer Hub database: `app` (default)
- Keycloak database: `keycloak`

### Verification

```bash
# Check all pods are running
oc get pods -n fusion-hub-keycloak

# Expected pods:
# - fusion-hub-keycloak-backstage-xxxxx (Developer Hub)
# - fusion-keycloak-postgres-1 (PostgreSQL primary)
# - fusion-keycloak-postgres-2 (PostgreSQL replica)
# - keycloak-xxxxx (Keycloak)

# Test authentication
# 1. Open Developer Hub URL
# 2. Click "Sign In"
# 3. Should redirect to Keycloak
# 4. Login with Keycloak credentials
# 5. Should redirect back to Developer Hub
```

### Troubleshooting Keycloak Integration

**Issue**: Redirect loop after login

**Solution**: Check redirect URIs in Keycloak client configuration
```bash
# Verify Developer Hub URL
oc get route -n fusion-hub-keycloak

# Ensure Keycloak client has correct redirect URI
```

**Issue**: "Invalid client credentials"

**Solution**: Verify client secret
```bash
# Check secret exists
oc get secret fusion-hub-keycloak-secrets -n fusion-hub-keycloak

# Verify secret value matches Keycloak
oc get secret fusion-hub-keycloak-secrets -n fusion-hub-keycloak \
  -o jsonpath='{.data.OIDC_CLIENT_SECRET}' | base64 -d
```

**Issue**: Keycloak can't connect to PostgreSQL

**Solution**: Verify database configuration
```bash
# Check PostgreSQL service
oc get svc fusion-keycloak-postgres-rw -n fusion-hub-keycloak

# Test connection from Keycloak pod
oc exec -it deployment/keycloak -n fusion-hub-keycloak -- \
  psql -h fusion-keycloak-postgres-rw -U app -d keycloak
```

For complete Keycloak setup guide, see: [Keycloak Setup Guide](../../docs/keycloak-setup.md)

- Network policies enabled
- Minimal resource requirements

**Use for**: Quick testing, demos, proof of concepts

```bash
helm install fusion-hub ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-minimal-values.yaml
```

### 2. Development Configuration (`examples/operator-fusion-development-values.yaml`)

Development environment with full Fusion AI features:
- Single replica Developer Hub
- Single PostgreSQL instance
- All Fusion AI models and tools enabled
- Relaxed security (network policies disabled)
- Development-sized resources
- OIDC authentication

**Use for**: Development environments, testing integrations

```bash
helm install fusion-dev-hub ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-development-values.yaml
```

### 3. Production Configuration (`examples/operator-fusion-production-values.yaml`)

Production-ready with high availability:
- 3 replicas Developer Hub
- 3 PostgreSQL instances (HA with automatic failover)
- All Fusion AI models and tools enabled
- Full security features (network policies, pod security standards)
- Automated backups to object storage
- Production-sized resources
- OIDC authentication
- Resource quotas and limits

**Use for**: Production deployments, enterprise environments

```bash
helm install fusion-hub ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-production-values.yaml
```

### Customizing Examples

You can customize any example by creating your own values file:

```bash
# Copy an example
cp examples/operator-fusion-production-values.yaml my-values.yaml

# Edit your values
vi my-values.yaml

# Install with your custom values
helm install fusion-hub ./helm-charts/fusion-developer-hub \
  --values my-values.yaml
```

Or override specific values:

```bash
helm install fusion-hub ./helm-charts/fusion-developer-hub \
  --values examples/operator-fusion-production-values.yaml \
  --set global.wildcardDomain=apps.my-cluster.example.com \
  --set developerHub.replicas=5
```

      fsGroup: null    # Let OpenShift assign
      seccompProfile:
        type: RuntimeDefault
    
    containerSecurityContext:
      allowPrivilegeEscalation: false
      runAsUser: null
      capabilities:
        drop:
          - ALL
      readOnlyRootFilesystem: false
```

**Security Features:**
- Non-root containers
- Dropped Linux capabilities
- Seccomp profiles
- OpenShift SCC compliance
- Resource limits and quotas

### Resource Quotas

Control resource consumption per namespace:

```yaml
developerHub:
  security:
    resourceQuota:
      cpu: "16"
      memory: "32Gi"
      cpuLimit: "32"
      memoryLimit: "64Gi"
      pvc: "10"
```

  --from-literal=OIDC_CLIENT_SECRET=your-client-secret
```

#### Catalog Integration

```yaml
developerHub:
  catalog:
    enabled: true
    
    github:
      enabled: true
      target: https://github.com/your-org
    
    gitlab:
      enabled: true
      target: https://gitlab.com/your-org
```

#### TechDocs

```yaml
developerHub:
  techdocs:
    enabled: true
    s3Bucket: developerhub-techdocs
    s3Region: us-south
    s3Endpoint: ""  # Set to object storage endpoint or leave empty for ODF
```

## Deployment Workflow

### 1. Operator Installation Phase

The chart first deploys the operators:

```yaml
# Red Hat Developer Hub Operator
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhdh-operator
  namespace: rhdh-operator
spec:
  channel: fast
  name: rhdh
  source: redhat-operators
```

```yaml
# PostgreSQL Operator
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cloud-native-postgresql
  namespace: postgres-operator
spec:
  channel: stable
  name: cloud-native-postgresql
  source: certified-operators
```

Jobs wait for operators to be ready before proceeding.

### 2. Database Provisioning Phase

Creates PostgreSQL cluster with HA:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: developerhub-postgres
  namespace: developer-hub
spec:
  instances: 3  # High availability
  
  storage:
    size: 20Gi
  
  backup:
    barmanObjectStore:
      destinationPath: s3://developerhub-postgres-backup
      # Credentials from ObjectBucketClaim or external config
```

### 3. Storage Setup Phase (Optional)

If using ODF, creates ObjectBucketClaim for backups:

```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: developerhub-postgres-backup
  namespace: developer-hub
spec:
  generateBucketName: developerhub-postgres-backup
  storageClassName: openshift-storage.noobaa.io
```

Job extracts credentials and configures PostgreSQL backup.

### 4. Developer Hub Instance Phase

Creates Developer Hub instance:

```yaml
apiVersion: rhdh.redhat.com/v1alpha1
kind: Backstage
metadata:
  name: developer-hub
  namespace: developer-hub
spec:
  application:
    replicas: 2
    appConfig:
      configMaps:
        - name: developerhub-app-config
  
  database:
    enableLocalDb: false  # Use PostgreSQL operator
  
  route:
    enabled: true
    host: devhub.apps.cluster.example.com
```

## High Availability

### PostgreSQL HA

The PostgreSQL operator provides:
- **Multiple instances**: Primary + replicas for failover
- **Automatic failover**: Promotes replica to primary on failure
- **Streaming replication**: Synchronous or asynchronous
- **Connection pooling**: Built-in PgBouncer support

```yaml
database:
  instances: 3  # 1 primary + 2 replicas
```

### Developer Hub HA

```yaml
developerHub:
  replicas: 2  # Multiple frontend/backend pods
```

## Backup and Recovery

### Automated Backups

PostgreSQL backups are automatically configured when enabled:

```yaml
database:
  backup:
    enabled: true
    useODF: true  # or configure external S3-compatible storage
    retentionPolicy: "30d"
```

### Manual Backup

```bash
# Trigger manual backup
oc annotate cluster developerhub-postgres \
  -n developer-hub \
  cnpg.io/immediateBackup="$(date +%Y%m%d-%H%M%S)"
```

### Recovery

```bash
# Restore from backup
oc apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: developerhub-postgres-restored
  namespace: developer-hub
spec:
  instances: 3
  bootstrap:
    recovery:
      source: developerhub-postgres
      recoveryTarget:
        targetTime: "2024-01-01 12:00:00"
  externalClusters:
    - name: developerhub-postgres
      barmanObjectStore:
        destinationPath: s3://developerhub-postgres-backup
        s3Credentials:
          accessKeyId:
            name: developerhub-postgres-backup-s3
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: developerhub-postgres-backup-s3
            key: ACCESS_SECRET_KEY
EOF
```

## Monitoring

### PostgreSQL Monitoring

The PostgreSQL operator exposes Prometheus metrics:

```yaml
database:
  monitoring:
    enablePodMonitor: true
```

Metrics available:
- Connection pool status
- Replication lag
- Query performance
- Backup status

### Developer Hub Monitoring

Developer Hub exposes metrics at `/metrics` endpoint.

## Troubleshooting

### Check Operator Status

```bash
# Developer Hub operator
oc get csv -n rhdh-operator

# PostgreSQL operator
oc get csv -n postgres-operator
```

### Check PostgreSQL Cluster

```bash
# Cluster status
oc get cluster -n developer-hub

# Pod status
oc get pods -n developer-hub -l cnpg.io/cluster=developerhub-postgres

# Logs
oc logs -n developer-hub developerhub-postgres-1
```

### Check Developer Hub Instance

```bash
# Backstage CR status
oc get backstage -n developer-hub

# Pod status
oc get pods -n developer-hub -l app.kubernetes.io/component=developerhub

# Logs
oc logs -n developer-hub -l app.kubernetes.io/component=developerhub
```

### Common Issues

#### Operator Not Ready

```bash
# Check subscription
oc get subscription -n rhdh-operator

# Check install plan
oc get installplan -n rhdh-operator

# Approve manual install plan if needed
oc patch installplan <install-plan-name> \
  -n rhdh-operator \
  --type merge \
  -p '{"spec":{"approved":true}}'
```

#### PostgreSQL Cluster Not Starting

```bash
# Check cluster events
oc describe cluster developerhub-postgres -n developer-hub

# Check PVC
oc get pvc -n developer-hub

# Check storage class
oc get storageclass
```

#### Backup Failures

```bash
# Check ObjectBucketClaim (if using ODF)
oc get obc -n developer-hub

# Check backup credentials
oc get secret developerhub-postgres-backup-s3 -n developer-hub

# Check backup status
oc get backup -n developer-hub
```

#### Database Connection Issues

**Symptom**: Backstage pods fail to start with "permission denied to create database" errors

```bash
# Check Backstage logs for database errors
oc logs -n developer-hub -l app.kubernetes.io/name=backstage | grep -i "permission denied"
```

**Cause**: The PostgreSQL user lacks CREATEDB privilege required for Backstage's plugin-per-database architecture.

**Solution**: The chart automatically grants CREATEDB privilege via a job. Verify the job completed:

```bash
# Check CREATEDB grant job status
oc get jobs -n developer-hub | grep createdb

# View job logs
oc logs -n developer-hub job/<createdb-job-name>

# Verify the privilege was granted
oc exec -n developer-hub <postgres-pod> -- psql -U postgres -c "\du <username>"
```

**Manual Fix** (if job failed):

```bash
# Connect to PostgreSQL
oc exec -it -n developer-hub <postgres-pod> -- psql -U postgres

# Grant CREATEDB privilege
ALTER USER <username> CREATEDB;

# Verify
\du <username>
```

**Documentation**: See [Database Plugin Division Mode](../../docs/database-plugin-division-mode.md) for detailed information about Backstage's database architecture and the `pluginDivisionMode` configuration.

## Upgrading

### Upgrade Operators

Operators are upgraded automatically if `installPlanApproval: Automatic`.

For manual upgrades:

```bash
# List available updates
oc get installplan -n rhdh-operator

# Approve update
oc patch installplan <install-plan-name> \
  -n rhdh-operator \
  --type merge \
  -p '{"spec":{"approved":true}}'
```

### Upgrade Developer Hub Instance

```bash
# Update chart
helm upgrade developer-hub ./fusion-developerhub/charts/fusion-developer-hub \
  -f values-developerhub.yaml
```

### Upgrade PostgreSQL

PostgreSQL minor version upgrades are automatic. For major version upgrades:

```bash
# Update cluster spec
oc patch cluster developerhub-postgres \
  -n developer-hub \
  --type merge \
  -p '{"spec":{"imageName":"ghcr.io/cloudnative-pg/postgresql:16"}}'
```

## Uninstallation

```bash
# Uninstall chart
helm uninstall developer-hub

# Remove operators (optional)
oc delete subscription rhdh-operator -n rhdh-operator
oc delete subscription cloud-native-postgresql -n postgres-operator

# Remove namespaces (optional)
oc delete namespace developer-hub
oc delete namespace rhdh-operator
oc delete namespace postgres-operator
```

## Best Practices

1. **High Availability**: Use at least 3 PostgreSQL instances for production
2. **Backups**: Enable automated backups with appropriate retention
3. **Resources**: Size PostgreSQL based on expected load
4. **Monitoring**: Enable monitoring and set up alerts
5. **Authentication**: Use OIDC for enterprise authentication
6. **Storage**: Use fast storage (SSD) for PostgreSQL
7. **Networking**: Configure network policies for security
8. **Updates**: Keep operators and instances up to date

## Support

For issues and questions:
- Red Hat Developer Hub: https://developers.redhat.com/rhdh
- Cloud Native PostgreSQL: https://cloudnative-pg.io

## License

This chart follows the licensing of the underlying components:
- Red Hat Developer Hub: Red Hat subscription required
- Cloud Native PostgreSQL: Apache 2.0
- Chart templates: MIT

---

Made with Bob