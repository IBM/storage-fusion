# Agentic Chat Assistant Sample Application

A reference implementation demonstrating end-to-end GitOps deployment patterns with automatic secret management and rotation on Fusion HCI.
## Table of Contents

- [Overview](#overview)
- [What This Sample Demonstrates](#what-this-sample-demonstrates)
- [Application Architecture](#application-architecture)
- [Application Description](#application-description)
- [Running Locally](#running-locally)
- [Building and Deploying the Container Image](#building-and-deploying-the-container-image)
- [Prerequisites](#prerequisites-1)
- [End-to-End Deployment Flow](#end-to-end-deployment-flow)
  - [Step 1: Deploy ArgoCD](#step-1-deploy-argocd)
  - [Step 2: Deploy Vault](#step-2-deploy-vault)
  - [Step 3: Deploy External Secrets Operator](#step-3-deploy-external-secrets-operator)
  - [Step 4: Configure Vault with Application Secrets](#step-4-configure-vault-with-application-secrets)
  - [Step 5: Deploy the Sample Application via ArgoCD](#step-5-deploy-the-sample-application-via-argocd)
  - [Step 6: Verify Deployment and Test Secret Rotation](#step-6-verify-deployment-and-test-secret-rotation)
- [GitOps Structure](#gitops-structure)
- [Secret Rotation Workflow](#secret-rotation-workflow)
- [Accessing the Application](#accessing-the-application)
- [Next Steps](#next-steps)
- [Related Documentation](#related-documentation)
  - [Quickstart Guides](#quickstart-guides)
  - [External Resources](#external-resources)


## Overview

This sample application showcases production-ready deployment patterns using ArgoCD, HashiCorp Vault, and External Secrets Operator. It serves as a practical example of how to deploy AI/ML applications with secure secret management and zero-downtime updates on Fusion HCI.

## What This Sample Demonstrates

This reference implementation showcases:

✅ **GitOps Continuous Delivery** - Declarative application deployment using ArgoCD  
✅ **Automated Secret Management** - Vault integration with External Secrets Operator  
✅ **Zero-Downtime Secret Rotation** - Automatic pod restarts using Stakater Reloader  
✅ **Sync Wave Orchestration** - Ordered deployment of dependencies

## Application Architecture

This sample application consists of:

- **Model Gateway Integration** - Unified LLM API gateway with Bearer authentication for accessing multiple AI models
- **CAS MCP Integration** - Content-Aware Storage integration for intelligent document retrieval and RAG workflows
- **Streamlit UI** - Interactive chat interface with real-time progress tracking and source attribution

The application demonstrates a complete RAG (Retrieval-Augmented Generation) pipeline with enterprise-grade secret management.

## Application Description

This is an **Agentic Chat Assistant** - an AI-powered chat application that combines retrieval-augmented generation (RAG) with intelligent document search capabilities. The application provides:

### Core Features

- **Interactive Chat Interface** - Built with Streamlit, providing a modern, responsive web UI for natural language conversations
- **RAG Pipeline** - Retrieves relevant context from enterprise documents using CAS (Content-Aware Storage) before generating responses
- **Real-time Progress Tracking** - Visual feedback showing each stage of query processing (retrieval, context building, generation)
- **Source Attribution** - Displays cited sources with relevance scores, and content snippets for transparency
- **Multi-Model Support** - Connects to Model Gateway for flexible LLM selection (Qwen, Granite, Mistral, etc.)
- **Vector Store Management** - Dynamic selection and management of multiple vector stores for document collections
- **MCP Protocol Support** - Optional Model Context Protocol integration for advanced CAS interactions

### Technical Stack

- **Frontend**: Streamlit (Python web framework)
- **LLM Integration**: Model Gateway with Bearer token authentication
- **Document Retrieval**: CAS MCP/REST API for vector search

### Use Cases

- Enterprise knowledge base querying
- Document Q&A with source verification
- Technical documentation assistance
- Compliance and audit trail with source attribution

## Running Locally

This section describes how to run the chat application on your local machine for development and testing.

### Prerequisites

- **Python 3.11+** (required for optimal compatibility)
- **pip** package manager
- **Access to required services**:
  - Model Gateway endpoint with API key
  - CAS (Content-Aware Storage) endpoint with API key
  - At least one vector store configured in CAS

### Local Setup Instructions

#### 1. Clone the Repository
Clone this repository to your local machine and then:
```bash
cd AI/fusion-gitops-sample-app
```

#### 2. Create Virtual Environment

```bash
# Create virtual environment
python3 -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate

# On Windows:
.venv\Scripts\activate
```

#### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

#### 4. Configure Environment Variables

Copy the example environment file and configure your credentials:

```bash
cp env.example .env
```

Edit `.env` file with your actual values:

```bash
# CAS Configuration
CAS_ENDPOINT=https://your-cas-endpoint.com
CAS_API_KEY=your-cas-api-key
CAS_VECTOR_STORE_ID=your-vector-store-id
CAS_USE_MCP=false  # Set to 'true' for MCP protocol, 'false' for REST API

# Model Gateway Configuration
MODEL_GATEWAY_ENDPOINT=https://your-model-gateway.com
MODEL_GATEWAY_API_KEY=your-bearer-token
MODEL_NAME=qwen2-5-72b-instruct  # Or: granite, mistral, etc.

# Optional: Search Configuration
DEFAULT_TOP_K=5  # Number of documents to retrieve
```

**Required Configuration**:
- `CAS_ENDPOINT` - Your CAS service URL
- `CAS_API_KEY` - Authentication key for CAS
- `MODEL_GATEWAY_ENDPOINT` - Your Model Gateway URL
- `MODEL_GATEWAY_API_KEY` - Bearer token for Model Gateway authentication
- `CAS_VECTOR_STORE_ID` - ID of the vector store to query (required for REST API mode)

#### 5. Start the Application

```bash
# Run the Streamlit application
streamlit run chat_app.py

# Or use Python directly
python -m streamlit run chat_app.py
```

#### 6. Access the Application

Once started, the application will be available at:

```
http://localhost:8501
```

### Using the Application Locally

1. **Initialize Components** - In the sidebar, expand "Gateway & API Connections" and enter your endpoints and API keys, then click "Initialize Components"
2. **Select Vector Store** - Choose a vector store from the dropdown or enter a store ID manually
3. **Start Chatting** - Type your question in the chat input at the bottom of the page
4. **View Results** - See the AI response with cited sources

## Building and Deploying the Container Image

Before deploying to Kubernetes/OpenShift, you need to build and push the container image to your own container registry.

### Prerequisites for Container Build

- **Podman** or **Docker** installed
- Access to a container registry (Docker Hub, Quay.io, private registry, etc.)
- Registry credentials configured (`podman login` or `docker login`)

### Build the Container Image

```bash
# Navigate to the application directory
cd fusion-gitops-sample-app

# Build the image (using podman)
podman build --platform linux/amd64 -f Dockerfile.chat-app -t your-registry.example.com/your-namespace/chat-app:latest .

# Or using docker
docker build --platform linux/amd64 -f Dockerfile.chat-app -t your-registry.example.com/your-namespace/chat-app:latest .
```

**Replace** `your-registry.example.com/your-namespace` with your actual registry details.

### Push the Image to Your Registry

```bash
# Push the image (using podman)
podman push your-registry.example.com/your-namespace/chat-app:latest

# Or using docker
docker push your-registry.example.com/your-namespace/chat-app:latest
```

### Update the Deployment Configuration

After building and pushing your image, update the deployment manifest:

1. **Edit the deployment file**: `gitops/applications/chat-app-deployment.yaml`
2. **Update line 25** with your image reference:
   ```yaml
   image: your-registry.example.com/your-namespace/chat-app:latest
   ```
3. **Commit and push** your changes to your forked repository

The ArgoCD application will automatically sync and deploy your custom image.

## Prerequisites

Before deploying this sample application, you must complete the following quickstart guides:

1. **[Deploy ArgoCD](../quickstarts/fusion-gitops/docs/deploying-gitops-guide.md)** - GitOps platform for continuous delivery
2. **[Deploy Vault](../quickstarts/fusion-gitops/docs/deploying-vault-guide.md)** - Secret storage and encryption
3. **[Deploy External Secrets Operator](../quickstarts/fusion-gitops/docs/deploying-external-secrets-guide.md)** - Secret synchronization

### Quick Links to Quickstart Guides

| Component | Guide | Purpose |
|-----------|-------|---------|
| **ArgoCD** | [Deploying GitOps Guide](../quickstarts/fusion-gitops/docs/deploying-gitops-guide.md) | Continuous delivery platform |
| **Vault** | [Deploying Vault Guide](../quickstarts/fusion-gitops/docs/deploying-vault-guide.md) | Secret management backend |
| **External Secrets** | [Deploying External Secrets Guide](../quickstarts/fusion-gitops/docs/deploying-external-secrets-guide.md) | Secret synchronization |

### Additional Requirements

- OpenShift 4.20+ or Kubernetes 1.27+ on Fusion HCI
- Cluster admin access
- `oc` or `kubectl` CLI configured
- Model Gateway (for LLM serving)
- CAS endpoint accessible (for document retrieval)

## End-to-End Deployment Flow

Follow these steps to deploy the sample application from scratch:

### Step 1: Deploy ArgoCD

Deploy the GitOps platform that will manage all subsequent deployments:

```bash
cd AI/quickstarts/fusion-gitops

# Deploy with default configuration
./scripts/deploy-gitops.sh

# Or use production profile for HA
./scripts/deploy-gitops.sh -f helm/fusion-gitops/environments/prod/values.yaml

# Verify deployment
./scripts/validate-gitops.sh
```

**What this provides**:
- ArgoCD server for GitOps workflows
- Application lifecycle management
- Automated sync and self-healing

📖 **Detailed guide**: [Deploying GitOps Guide](../quickstarts/fusion-gitops/docs/deploying-gitops-guide.md)

### Step 2: Deploy Vault

Deploy HashiCorp Vault for secure secret storage:

```bash
cd AI/quickstarts/fusion-gitops

# Deploy with default configuration (Shamir seal)
./scripts/deploy-secret-manager.sh

# Or deploy with AWS KMS auto-unseal (recommended for production)
./scripts/deploy-secret-manager.sh \
  --seal-type awskms \
  --kms-region us-east-1 \
  --kms-key-id alias/vault-unseal

# Verify deployment
./scripts/validate-secret-manager.sh
```

**What this provides**:
- Encrypted secret storage
- High availability (multi-replica)
- Automatic unsealing (with AWS KMS)

📖 **Detailed guide**: [Deploying Vault Guide](../quickstarts/fusion-gitops/docs/deploying-vault-guide.md)

### Step 3: Deploy External Secrets Operator

Deploy the operator that synchronizes secrets from Vault to Kubernetes:

```bash
cd AI/quickstarts/fusion-gitops

# Deploy operator with Vault backend
./scripts/deploy-external-secrets.sh --backend vault

# Verify deployment
./scripts/validate-external-secrets.sh
```

**What this provides**:
- Automatic secret synchronization from Vault
- ClusterSecretStore for centralized configuration
- Real-time secret updates

📖 **Detailed guide**: [Deploying External Secrets Guide](../quickstarts/fusion-gitops/docs/deploying-external-secrets-guide.md)

### Step 4: Configure Vault with Application Secrets

Store the application secrets in Vault:

```bash
# Get Vault root token
export VAULT_TOKEN=$(oc get secret vault-unseal-keys -n vault \
  -o jsonpath='{.data.root-token}' | base64 -d)

# Port-forward to Vault (if not using route)
oc port-forward -n vault svc/vault 8200:8200 &

# Set Vault address
export VAULT_ADDR=http://localhost:8200

# Create secrets in Vault
vault kv put secret/llmops-platform/secrets \
  cas_api_key="your-cas-api-key" \
  model_gateway_api_key="your-model-gateway-bearer-token"

# Verify secrets are stored
vault kv get llmops-platform/secrets
```

**Required secrets**:
- `cas_api_key` - CAS API key for document retrieval
- `model_gateway_api_key` - Model Gateway Bearer token for LLM access

### Step 5: Deploy the Sample Application via ArgoCD

Deploy the application using GitOps:

```bash
# Update the repository URL in the ArgoCD application manifest
# Edit: fusion-gitops-sample-app/gitops/llmops-with-reloader.yaml
# Change repoURL to your forked repository

# Apply the ArgoCD application
oc apply -f fusion-gitops-sample-app/gitops/llmops-with-reloader.yaml

# Watch the deployment
oc get applications.argoproj.io -n openshift-gitops -w

# Check application status
argocd app get llmops-platform --refresh
```

**What gets deployed**:
1. **Reloader** - Automatic pod restart on secret changes
2. **ExternalSecret** - Secret synchronization from Vault
3. **Application** - Chat application with Model Gateway integration

### Step 6: Verify Deployment and Test Secret Rotation

Verify the deployment is successful:

```bash
# Check all pods are running
oc get pods -n llmops-platform

# Check ExternalSecret status
oc get externalsecret llmops-secrets -n llmops-platform

# Verify secret was created
oc get secret llmops-secrets -n llmops-platform
```

**Test automatic secret rotation**:

```bash
# Update secret in Vault
vault kv put secret/llmops-platform/secrets \
  cas_api_key="new-cas-api-key" \
  model_gateway_api_key="new-model-gateway-token"

# Watch for automatic sync and pod restart
oc get externalsecret llmops-secrets -n llmops-platform -w
oc get pods -n llmops-platform -w

# Verify new secret values (after sync)
oc get secret llmops-secrets -n llmops-platform -o yaml
```

The deployment will automatically restart with new secrets within 5 minutes (default refresh interval).

## GitOps Structure

The sample application uses ArgoCD sync waves to orchestrate deployment order:

### Sync Wave Strategy

```
Wave 0: Access Control
└── RBAC configuration

Wave 1: Configuration
└── ConfigMap

Wave 2: Secret Management
└── ExternalSecret resource

Wave 3: Application Deployment
├── Chat application deployment
├── Service
└── Route
```

### Deployment Manifests

```
fusion-gitops-sample-app/gitops/
├── llmops-with-reloader.yaml          # ArgoCD Application
└── applications/
    ├── chat-app-deployment.yaml       # Application deployment
    ├── externalsecret-llmops.yaml     # ExternalSecret
    ├── configmap.yaml                 # Configuration
    └── rbac.yaml                      # RBAC resources
```

### Key Annotations

The deployment uses these critical annotations:

```yaml
# Automatic restart on secret changes
secret.reloader.stakater.com/reload: "llmops-secrets"
```

## Secret Rotation Workflow

The sample demonstrates production-ready automatic secret rotation:

```
┌─────────────────────────────────────────────────────────────┐
│                    Secret Rotation Flow                     │
└─────────────────────────────────────────────────────────────┘

1. Update Secret in Vault
   │
   │  vault kv put secret/llmops-platform/secrets \
   │    cas_api_key="new-key" \
   │    model_gateway_api_key="new-token"
   │
   ▼
2. External Secrets Operator Detects Change
   │  (refreshInterval: 5m)
   │
   ▼
3. Kubernetes Secret Updated
   │  (llmops-secrets in llmops-platform namespace)
   │
   ▼
4. Stakater Reloader Detects Secret Change
   │  (watches annotation: secret.reloader.stakater.com/reload)
   │
   ▼
5. Reloader Updates Deployment Annotation
   │  (triggers rolling restart)
   │
   ▼
6. Kubernetes Performs Rolling Restart
   │  (zero downtime)
   │
   ▼
7. New Pods Start with Updated Secrets
   │  (application automatically uses new credentials)
   │
   ▼
8. Old Pods Terminated
   └─> ✅ Secret Rotation Complete
```

### Configuration

**ExternalSecret refresh interval**:
```yaml
spec:
  refreshInterval: 5m  # Check Vault every 5 minutes
```

**Reloader annotation**:
```yaml
metadata:
  annotations:
    secret.reloader.stakater.com/reload: "llmops-secrets"
```

## Accessing the Application

### Get the Application URL

```bash
# Get the route URL
oc get route llmops-chat-app -n llmops-platform \
  -o jsonpath='{.spec.host}' && echo

# Open in browser
https://<route-host>
```

### Access via Port-Forward (Alternative)

```bash
# Port-forward to the service
oc port-forward -n llmops-platform svc/llmops-chat-app 8501:8501

# Open in browser
http://localhost:8501
```

### Default Configuration

The application is configured with:
- **Model Gateway endpoint** - From ConfigMap
- **CAS integration** - Using secrets from Vault
- **Model name** - Configurable via ConfigMap

## Next Steps

### Customize the Deployment

1. **Fork the repository** to your own Git account
2. **Update the ArgoCD application** to point to your fork:
   ```yaml
   # Edit: fusion-gitops-sample-app/gitops/llmops-with-reloader.yaml
   spec:
     source:
       repoURL: https://github.com/<your-org>/storage-fusion.git
   ```
3. **Modify configurations** in your fork
4. **Commit and push** - ArgoCD will automatically sync changes

### Extend the Pattern

Use this sample as a template for your own applications:

- **Add more applications** using the same GitOps pattern
- **Implement multi-environment** deployments (dev, staging, prod)
- **Add monitoring** with Prometheus and Grafana
- **Integrate CI/CD** pipelines for automated builds
- **Implement progressive delivery** with Argo Rollouts

## Related Documentation

### Quickstart Guides
- [Deploying GitOps Guide](../quickstarts/fusion-gitops/docs/deploying-gitops-guide.md)
- [Deploying Vault Guide](../quickstarts/fusion-gitops/docs/deploying-vault-guide.md)
- [Deploying External Secrets Guide](../quickstarts/fusion-gitops/docs/deploying-external-secrets-guide.md)
- [GitOps Quickstart Overview](../quickstarts/fusion-gitops/README.md)

### External Resources
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [External Secrets Operator](https://external-secrets.io/)
- [Stakater Reloader](https://github.com/stakater/Reloader)
