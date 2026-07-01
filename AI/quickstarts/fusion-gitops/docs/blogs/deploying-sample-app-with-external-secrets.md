# Using the Fusion GitOps Quickstart to Deploy an AI Application with Secure Secret Management

A production-ready tutorial demonstrating GitOps continuous delivery, automated secret management, and zero-downtime secret rotation on Fusion HCI.

## Introduction

Deploying AI applications in production requires more than just running containers—it demands robust secret management, automated deployment workflows, and zero-downtime updates. This tutorial demonstrates how to deploy a complete AI chat application using the Fusion GitOps Quickstart, showcasing enterprise-grade patterns for secret management and continuous delivery.

**What makes this different**: Instead of building a GitOps platform from scratch, you'll consume a pre-built platform layer (ArgoCD, Vault, External Secrets Operator) and focus on deploying your application. This separation of concerns mirrors real-world enterprise environments where platform teams provide infrastructure and application teams consume it.

## What You'll Build

This tutorial has two distinct layers:

### Platform Layer (GitOps Quickstart)
The foundation provided by the [Fusion GitOps Quickstart](gitops-quickstart.md):
- **ArgoCD**: GitOps continuous delivery engine
- **HashiCorp Vault**: Encrypted secret storage with Kubernetes authentication
- **External Secrets Operator**: Automatic secret synchronization from Vault to Kubernetes

### Application Layer (AI Chat Application)
An agentic chat assistant demonstrating production patterns:
- **Streamlit UI**: Interactive chat interface
- **Model Gateway Integration**: For LLM inference
- **CAS Integration**: Content-Aware Storage for RAG workflows
- **GitOps Deployment**: Declarative configuration with sync wave orchestration

## Architecture Overview

The deployment follows this flow:

```
┌─────────────────────────────────────────────────────────────┐
│                    Deployment Flow                          │
└─────────────────────────────────────────────────────────────┘

1. Store Secrets in Vault
   │  vault kv put secret/llmops-platform/secrets \
   │    cas_api_key="..." model_gateway_api_key="..."
   │
   ▼
2. ArgoCD Syncs Application (Sync Waves)
   │  Wave 0: RBAC → Wave 1: ConfigMap → Wave 2: ExternalSecret → Wave 3: Application
   │
   ▼
3. External Secrets Operator Syncs from Vault
   │  Polls Vault every 5 minutes, creates Kubernetes Secret
   │
   ▼
4. Reloader Watches for Secret Changes
   │  Triggers rolling restart when secrets update
   │
   ▼
5. Application Runs with Secrets
   │  Pods consume secrets as environment variables
   │
   ▼
6. Continuous Sync (Automated)
   │  ArgoCD: 3-minute sync interval
   │  External Secrets: 5-minute refresh interval
   └─> Zero-downtime updates on secret rotation
```

**Key Components**:
- **Vault**: Stores secrets encrypted at rest, uses Kubernetes auth method for secure access
- **ExternalSecret**: Defines which secrets to sync and how to map them
- **Reloader**: Observes secret changes, not part of sync waves
- **ArgoCD Sync Waves**: Ensures dependencies deploy in correct order

## Prerequisites

Complete these requirements before starting the tutorial.

### Platform Components (Deploy First)

Deploy these components using the [Fusion GitOps Quickstart](gitops-quickstart.md):

1. **ArgoCD** - [Deploying GitOps Guide](../deploying-gitops-guide.md)
2. **Vault** - [Deploying Vault Guide](../deploying-vault-guide.md)  
3. **External Secrets Operator** - [Deploying External Secrets Guide](../deploying-external-secrets-guide.md)

> **Note**: The Fusion GitOps Quickstart provides automated scripts for rapid deployment. Complete deploying all three components before proceeding.

### Fork and Clone Repository

```bash
# Fork the repository on GitHub
# Navigate to: https://github.com/IBM/storage-fusion
# Click "Fork" button

# Clone your fork
git clone https://github.com/<YOUR_USERNAME>/storage-fusion.git
cd storage-fusion/AI
```

### Application Requirements

- **Model Gateway**: Accessible endpoint with Bearer token authentication
- **CAS Endpoint**: Content-Aware Storage instance with API key
- **Container Registry**: Access to push custom images (Docker Hub, Quay.io, etc.)

## External Secrets Backend: HashiCorp Vault

This tutorial uses **HashiCorp Vault** as the secret management backend. The Fusion GitOps Quickstart also supports AWS Secrets Manager and IBM Cloud Secrets Manager—see the [External Secrets Guide](../deploying-external-secrets-guide.md) for configuration details.

### Vault Configuration

The External Secrets Operator connects to Vault using:
- **Authentication**: Kubernetes auth method (service account token)
- **Path**: `llmops-platform/secrets` (in a KV v2 secrets engine named `secret`)
- **Refresh Interval**: 5 minutes (configurable)

The ClusterSecretStore is configured with Kubernetes authentication enabled.

> **Note on Vault Paths**: Vault CLI commands use the full mount path (e.g., `secret/llmops-platform/secrets`), while the ExternalSecret resource uses only the relative path (`llmops-platform/secrets`) because the ClusterSecretStore already defines the mount path as `secret` in its configuration.

## Deployment Steps

Follow these steps to deploy the AI chat application using GitOps.

### Step 1: Build and Push Container Image

Build the application container and push to your registry:

```bash
cd fusion-gitops-sample-app

# Build the image (using podman or docker)
# Fusion HCI runs on x86, so we explicitly build for linux/amd64 even on ARM environments
podman build --platform linux/amd64 \
  -f Dockerfile.chat-app \
  -t your-registry.example.com/your-namespace/chat-app:latest .

# Push to your registry
podman push your-registry.example.com/your-namespace/chat-app:latest
```

**What this does**: Creates a containerized version of the Streamlit chat application with all dependencies.

### Step 2: Update Deployment Configuration

Update the deployment manifest with your image reference:

```bash
# Edit the deployment file
vi gitops/applications/chat-app-deployment.yaml
```

Update the following line with your image:
```yaml
image: your-registry.example.com/your-namespace/chat-app:latest
```

**What this demonstrates**: GitOps principle—all configuration is declarative and version-controlled.

### Step 3: Configure Application Settings

Update the ConfigMap with your endpoints:

```bash
# Edit the ConfigMap
vi gitops/applications/configmap.yaml
```

Update the configuration values:
```yaml
data:
  cas-endpoint: "https://your-cas-endpoint.com"
  cas-vector-store-id: "your-vector-store-id"
  cas-use-mcp: "false"
  model-gateway-endpoint: "https://your-model-gateway.com"
  model-name: "model-name"
  default-top-k: "5"
```

**What this demonstrates**: Separation of configuration (ConfigMap) from secrets (Vault), enabling GitOps-friendly configuration management.

### Step 4: Store Secrets in Vault

Store sensitive credentials in Vault:

```bash
# Get Vault root token
export VAULT_TOKEN=$(oc get secret vault-unseal-keys -n vault \
  -o jsonpath='{.data.root-token}' | base64 -d)

# Port-forward to Vault
oc port-forward -n vault svc/vault 8200:8200 &

# Set Vault address
export VAULT_ADDR=http://localhost:8200

# Create secrets in Vault (using the existing KV v2 engine mounted at `secret`)
vault kv put secret/llmops-platform/secrets \
  cas_api_key="your-cas-api-key" \
  model_gateway_api_key="your-model-gateway-bearer-token"

# Verify secrets are stored
vault kv get secret/llmops-platform/secrets
```

**What this demonstrates**: Centralized secret management—secrets are stored once in Vault and automatically synchronized to Kubernetes.

### Step 5: Commit and Push Changes

Commit your configuration changes:

```bash
# Ensure you're in the fusion-gitops-sample-app directory
cd fusion-gitops-sample-app

# Add changes
git add gitops/applications/chat-app-deployment.yaml
git add gitops/applications/configmap.yaml

# Commit
git commit -m "Configure chat app for my environment"

# Push to your fork
git push origin main
```

**What this demonstrates**: GitOps workflow—Git is the single source of truth for all configuration.

### Step 6: Update ArgoCD Application

Update the ArgoCD application to point to your fork:

```bash
# Edit the ArgoCD application manifest
vi gitops/llmops-with-reloader.yaml
```

Update the `repoURL` line with your repository URL:
```yaml
repoURL: https://github.com/<YOUR_USERNAME>/storage-fusion.git
```

**What this demonstrates**: ArgoCD watches your Git repository for changes and automatically syncs them to the cluster.

### Step 7: Deploy via ArgoCD

Apply the ArgoCD application:

```bash
# Apply the ArgoCD application
oc apply -f gitops/llmops-with-reloader.yaml

# Watch the deployment
oc get applications.argoproj.io -n openshift-gitops -w
```

**What happens**: ArgoCD creates two applications:
1. **Reloader**: Cluster-wide secret watcher
2. **LLMOps Platform**: Your chat application with all dependencies

**What this demonstrates**: Platform consumption—you're using ArgoCD (platform layer) to deploy your application (application layer).

### Step 8: Monitor Sync Waves

Watch ArgoCD deploy resources in order:

```bash
# Check application status
oc get applications.argoproj.io llmops-platform -n openshift-gitops

# Watch pods being created
oc get pods -n llmops-platform -w
```

**Sync wave order** (defined in annotations):
1. **Wave 0**: RBAC resources
2. **Wave 1**: Application configuration
3. **Wave 2**: ExternalSecret resource
4. **Wave 3**: Application deployment

**What this demonstrates**: Dependency management—ArgoCD ensures prerequisites are ready before deploying dependent resources.

## Verification

Verify the deployment is successful:

```bash
# Check application pods
oc get pods -n llmops-platform

# Expected output:
# NAME                                READY   STATUS    RESTARTS   AGE
# llmops-chat-app-xxxxxxxxxx-xxxxx    1/1     Running   0          2m

# Check reloader pod (deployed in separate namespace)
oc get pods -n reloader

# Check ExternalSecret status
oc get externalsecret llmops-secrets -n llmops-platform

# Expected output:
# NAME              STORE           REFRESH INTERVAL   STATUS         READY
# llmops-secrets    vault-backend   5m                 SecretSynced   True

# Verify secret was created
oc get secret llmops-secrets -n llmops-platform

# Get application URL
oc get route llmops-chat-app -n llmops-platform \
  -o jsonpath='{.spec.host}' && echo
```

**What to verify**:
- ✓ Pods are running
- ✓ ExternalSecret shows "SecretSynced" status
- ✓ Kubernetes secret exists with correct keys
- ✓ Route is accessible

## What Just Happened: The Automated Workflow

Understanding the automation that occurred:

### 1. ArgoCD Sync Waves Orchestration

ArgoCD deployed resources in dependency order:

```yaml
# Wave 0: RBAC (rbac.yaml)
argocd.argoproj.io/sync-wave: "0"
# Creates Role and RoleBinding for ArgoCD to manage resources

# Wave 1: ConfigMap (configmap.yaml)
argocd.argoproj.io/sync-wave: "1"
# Deploys application configuration (endpoints, model names)

# Wave 2: ExternalSecret (externalsecret-llmops.yaml)
argocd.argoproj.io/sync-wave: "2"
# Creates ExternalSecret resource that syncs from Vault

# Wave 3: Application (chat-app-deployment.yaml)
argocd.argoproj.io/sync-wave: "3"
# Deploys the chat application with secrets mounted
```

**Why this matters**: Each wave completes before the next begins, ensuring dependencies are satisfied.

### 2. External Secrets Operator Synchronization

The ExternalSecret resource (`externalsecret-llmops.yaml`) triggered:

```yaml
spec:
  refreshInterval: 5m  # Poll Vault every 5 minutes
  secretStoreRef:
    name: vault-backend  # Use ClusterSecretStore
    kind: ClusterSecretStore
  target:
    name: llmops-secrets  # Create this Kubernetes secret
  dataFrom:
    - extract:
        key: llmops-platform/secrets  # From this Vault path
```

**What happened**:
1. ESO authenticated to Vault using Kubernetes service account
2. Retrieved secrets from `llmops-platform/secrets` path
3. Created Kubernetes secret `llmops-secrets` with keys: `cas_api_key`, `model_gateway_api_key`
4. Set up 5-minute polling for automatic updates

### 3. Reloader Observation

Reloader watches for changes:

```yaml
# Annotation in chat-app-deployment.yaml
secret.reloader.stakater.com/reload: "llmops-secrets"
```

**How it works**:
- Reloader is a **cluster-wide observer**, not part of sync waves
- Watches all secrets/configmaps across namespaces (except excluded ones)
- When `llmops-secrets` changes, Reloader updates the deployment annotation
- Kubernetes triggers a rolling restart with zero downtime

### 4. Continuous Synchronization

Two automated sync loops are now active:

**ArgoCD Sync** (every 3 minutes):
- Compares Git repository state with cluster state
- Automatically applies any configuration changes
- Self-heals if resources are manually modified

**External Secrets Sync** (every 5 minutes):
- Polls Vault for secret changes
- Updates Kubernetes secret if values differ
- Triggers Reloader when secrets change

**Result**: Fully automated secret rotation with zero downtime.

## Key Features Demonstrated

This deployment showcases production-ready patterns:

### 1. GitOps Continuous Delivery

**Pattern**: Declarative configuration in Git, automated synchronization to cluster

**Implementation**:
- All resources defined in `gitops/applications/`
- ArgoCD watches Git repository for changes
- Automatic sync with self-healing enabled (`llmops-with-reloader.yaml`)

**Benefits**:
- Audit trail of all changes
- Easy rollback via Git revert
- Consistent deployments across environments

### 2. Automated Secret Management

**Pattern**: Secrets stored in Vault, automatically synchronized to Kubernetes

**Implementation**:
- Vault stores encrypted secrets with Kubernetes authentication
- ExternalSecret defines sync configuration
- External Secrets Operator creates and maintains Kubernetes secret

**Benefits**:
- Centralized secret management
- No secrets in Git
- Automatic rotation support

### 3. Zero-Downtime Secret Rotation

**Pattern**: Automatic pod restart when secrets change, with rolling updates

**Implementation**:
- Reloader watches for secret changes
- Triggers rolling restart via deployment annotation update
- Kubernetes performs zero-downtime rolling update

**Test it**:
```bash
# Update secret in Vault
vault kv put secret/llmops-platform/secrets \
  cas_api_key="new-cas-api-key" \
  model_gateway_api_key="new-model-gateway-token"

# Watch automatic sync and restart (within 5 minutes)
oc get externalsecret llmops-secrets -n llmops-platform -w
oc get pods -n llmops-platform -w
```

**Benefits**:
- No manual intervention required
- Zero downtime during updates
- Consistent secret rotation process

### 4. Sync Wave Orchestration

**Pattern**: Ordered deployment of dependencies using ArgoCD sync waves

**Implementation**:
- Wave 0: RBAC permissions
- Wave 1: Configuration (ConfigMap)
- Wave 2: Secret management (ExternalSecret)
- Wave 3: Application (Deployment, Service, Route)

**Benefits**:
- Prevents race conditions
- Ensures dependencies are ready
- Predictable deployment order

### 5. Separation of Concerns

**Pattern**: Platform layer provides infrastructure, application layer consumes it

**Implementation**:
- **Platform Team**: Deploys ArgoCD, Vault, ESO (one-time setup)
- **Application Team**: Deploys applications using platform services

**Benefits**:
- Clear ownership boundaries
- Reusable platform components
- Faster application deployment

## Conclusion

You've successfully deployed an AI chat application using enterprise-grade GitOps patterns on Fusion HCI. This tutorial demonstrated:

**Platform Consumption**: Using pre-built GitOps infrastructure (ArgoCD, Vault, ESO)  
**Automated Secret Management**: Vault integration with automatic Kubernetes synchronization  
**Zero-Downtime Updates**: Automatic pod restarts on secret rotation  
**Sync Wave Orchestration**: Ordered deployment of dependencies  
**Production Patterns**: Separation of configuration and secrets, declarative GitOps workflows

### What You Achieved

- **Deployed** a complete AI application with RAG capabilities
- **Configured** automated secret synchronization from Vault
- **Enabled** zero-downtime secret rotation with Reloader
- **Implemented** GitOps continuous delivery with ArgoCD
- **Demonstrated** production-ready deployment patterns

### Next Steps

**Extend the Pattern**:
- Deploy additional applications using the same GitOps workflow
- Implement multi-environment deployments (dev, staging, prod)
- Add monitoring with Prometheus and Grafana
- Integrate CI/CD pipelines for automated builds

**Customize for Your Environment**:
- Fork the repository and modify configurations
- Add your own AI models and endpoints
- Implement custom secret rotation policies
- Configure additional secret backends (AWS, IBM Cloud)

### Related Documentation

- [Fusion GitOps Quickstart](../../README.md) - Complete platform documentation
- [Deploying GitOps Guide](../deploying-gitops-guide.md) - ArgoCD deployment details
- [Deploying Vault Guide](../deploying-vault-guide.md) - Vault configuration and HA setup
- [Deploying External Secrets Guide](../deploying-external-secrets-guide.md) - Multi-backend secret management
- [Sample Application README](../../../../fusion-gitops-sample-app/README.md) - Application architecture and local development

### External Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/) - GitOps continuous delivery
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs) - Secret management
- [External Secrets Operator](https://external-secrets.io/) - Secret synchronization
- [Stakater Reloader](https://github.com/stakater/Reloader) - Automatic pod restarts

---

**Tutorial Complete**: You now have a production-ready AI application deployed with automated secret management and continuous delivery on Fusion HCI.