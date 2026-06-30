# GitOps Deployment for Fusion HCI

Deploy a complete GitOps platform on Fusion HCI with OpenShift GitOps (ArgoCD), HashiCorp Vault for secret management, and External Secrets Operator for seamless secret synchronization across multiple backends.

## Table of Contents

- [Forking the Repository](#forking-the-repository)
- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [1. Deploy GitOps](#1-deploy-gitops)
  - [2. Deploy Vault (optional)](#2-deploy-vault)
  - [3. Deploy External Secrets (optional)](#3-deploy-external-secrets)
- [Sample Application](#sample-application)
- [Cleanup](#cleanup)
- [Detailed Guides](#detailed-guides)
- [Project Structure](#project-structure)

## Forking the Repository

Before deploying the GitOps platform, fork this repository to your own GitHub account. This is essential for GitOps workflows as it allows you to:

- **Customize configurations**: Modify Helm values, scripts, and manifests for your environment
- **Track changes**: Maintain version control of your infrastructure configurations
- **Enable GitOps**: Point ArgoCD to your forked repository for continuous deployment
- **Preserve upstream updates**: Easily sync improvements and fixes from the original repository

### Fork and Clone

1. **Fork the repository** on GitHub:
   - Navigate to the repository: `https://github.com/IBM/storage-fusion`
   - Click the "Fork" button in the top-right corner
   - Select your account or organization as the destination

2. **Clone your forked repository**:

```bash
# Clone your fork (replace <YOUR_USERNAME> with your GitHub username)
git clone https://github.com/<YOUR_USERNAME>/storage-fusion.git
cd storage-fusion/

# Add the original repository as upstream remote
git remote add upstream https://github.com/IBM/storage-fusion.git

# Verify remotes
git remote -v
```

3. **Create a working branch** (optional, but recommended):

```bash
# Create and switch to a new branch for your customizations
git checkout -b fusion-gitops-config

# Make your changes, then commit
git add .
git commit -m "Configure GitOps for my environment"
git push origin fusion-gitops-config
```

### Keep Your Fork Synchronized

Periodically sync your fork with the upstream repository to receive updates:

```bash
# Fetch upstream changes
git fetch upstream

# Merge upstream changes into your main branch
git checkout main
git merge upstream/main

# Push updates to your fork
git push origin main
```

## Overview

This quickstart provides a production-ready GitOps platform optimized for Fusion HCI environments. It offers multiple deployment methods to suit different use cases:

- **Scripts** (`scripts/`): Fast, automated deployment for quick starts and CI/CD pipelines
- **Helm Charts** (`helm/`): Flexible, customizable deployments with values files for different environments
- **Ansible Playbooks** (`ansible/`): Enterprise-grade automation with validation and rollback capabilities

All components are designed to work together seamlessly while remaining independently deployable and configurable.

## Key Features

### GitOps Platform
- **OpenShift GitOps (ArgoCD)**: Enterprise-grade continuous delivery with declarative GitOps workflows
- **Multi-environment support**: Pre-configured values files for development, staging, and production
- **High availability**: Production configurations with replica sets and persistent storage
- **RBAC integration**: OpenShift authentication and authorization out of the box

### Secret Management
- **HashiCorp Vault**: Industry-standard secret storage with encryption at rest and in transit
- **Auto-initialization**: Automated root token management
- **Persistent storage**: Configurable storage classes for data durability
- **HA deployment**: Multi-replica configurations for production workloads

### External Secrets Integration
- **Multi-backend support**: Seamless integration with multiple secret management systems
  - **HashiCorp Vault**: On-premises enterprise secret management
  - **AWS Secrets Manager**: Cloud-native secret management for AWS deployments
  - **IBM Cloud Secrets Manager**: Enterprise secret management for IBM Cloud
- **Automatic synchronization**: Real-time secret updates from external sources
- **ClusterSecretStore**: Centralized secret store configuration

### Deployment Flexibility
- **Script-based deployment**: One-command installation for rapid setup
- **Helm charts**: Customizable deployments with environment-specific values
- **Ansible automation**: Idempotent playbooks with pre-flight checks and validation

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   Fusion HCI Cluster                     │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │             OpenShift GitOps (ArgoCD)              │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  • Continuous Delivery                             │  │
│  │  • Application Lifecycle Management                │  │
│  └────────────────────────────────────────────────────┘  │
│                           │                              │
│                           ▼                              │
│  ┌────────────────────────────────────────────────────┐  │
│  │                 HashiCorp Vault                    │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  • Secret Storage & Encryption                     │  │
│  │  • High Availability (Raft)                        │  │
│  └────────────────────────────────────────────────────┘  │
│                           │                              │
│                           ▼                              │
│  ┌────────────────────────────────────────────────────┐  │
│  │             External Secrets Operator              │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  • Automatic Secret Synchronization                │  │
│  └────────────────────────────────────────────────────┘  │
│                           │                              │
│                           ▼                              │
│  ┌────────────────────────────────────────────────────┐  │
│  │              Application Workloads                 │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  • AI/ML Pipelines                                 │  │
│  │  • Microservices                                   │  │
│  │  • Data Processing                                 │  │
│  │  • Multi-Tenant Applications                       │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required
- **Fusion HCI Cluster**: OpenShift 4.20+ or Kubernetes 1.27+ running on Fusion HCI
- **Cluster Access**: Cluster admin privileges for operator installation
- **CLI Tools**:
  - `oc` (OpenShift CLI) or `kubectl` configured and authenticated
  - `helm` 3.12+ for chart deployments
- **Storage**: At least one StorageClass available for persistent volumes
  - Recommended: `ocs-storagecluster-ceph-rbd` (OpenShift Data Foundation)
  - Minimum: 10Gi available storage per component

### Optional
- **Ansible**: Version 2.15+ (or ansible-core 2.15+) for playbook-based automation
- **Git**: For GitOps repository management
- **jq**: For JSON parsing in scripts (auto-installed if missing)

### Verification

Verify your environment before deployment:

```bash
# Check cluster access
oc whoami
oc version

# Verify Helm installation
helm version

# List available storage classes
oc get storageclass

# Check available storage
oc get pv
```

## Getting Started

All commands should be run from the `quickstarts/fusion-gitops` directory. Each component can be deployed independently or as part of a complete stack.

### Deployment Order

1. **GitOps** (required): Core platform for continuous delivery
2. **Vault** (optional): Secret management backend
3. **External Secrets** (optional): Secret synchronization layer

### 1. Deploy GitOps

Deploy OpenShift GitOps (ArgoCD) as the foundation for your GitOps platform:

```bash
# Navigate to the quickstart directory
cd quickstarts/fusion-gitops

# Verify prerequisites
oc whoami
helm version
oc get storageclass

# Deploy with default configuration
./scripts/deploy-gitops.sh

# Wait for deployment to complete
oc get pods -n openshift-gitops -w

# Get ArgoCD server URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' && echo

# Get admin password
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d && echo
```

#### Environment-Specific Deployments

Choose the appropriate values file for your environment:

```bash
# Development/Testing (minimal resources)
./scripts/deploy-gitops.sh -f helm/fusion-gitops/environments/dev/values.yaml

# Staging (moderate resources for pre-production testing)
./scripts/deploy-gitops.sh -f helm/fusion-gitops/environments/stage/values.yaml

# Production (HA with persistent storage)
./scripts/deploy-gitops.sh -f helm/fusion-gitops/environments/prod/values.yaml

# OpenShift Data Foundation storage
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-odf.yaml
```

#### Validation

Run the comprehensive validation script to verify your GitOps deployment:

```bash
# Run validation script
./scripts/validate-gitops.sh

# Run with verbose output for detailed diagnostics
./scripts/validate-gitops.sh --verbose

# Specify custom namespace
./scripts/validate-gitops.sh --namespace my-gitops
```

The validation script performs 12 comprehensive checks:

1. **GitOps Operator Subscription**: Verifies operator is subscribed and at latest version
2. **Operator ClusterServiceVersion**: Confirms CSV is in "Succeeded" phase
3. **Operator Pods**: Validates operator controller manager is running
4. **ArgoCD Instance**: Checks ArgoCD CR exists and is "Available"
5. **ArgoCD Pods**: Validates all components (server, repo-server, application-controller, redis-ha, dex-server, applicationset-controller)
6. **ArgoCD Services**: Verifies key services are created and accessible
7. **ArgoCD Route/Ingress**: Confirms external access is configured
8. **ArgoCD Server Health**: Tests server health endpoint
9. **ArgoCD Applications**: Lists deployed applications and their sync status
10. **ArgoCD AppProjects**: Shows configured AppProjects with source repos and destinations
11. **ArgoCD Cluster Connections**: Lists external clusters connected to ArgoCD
12. **Pod Logs**: Scans for critical errors in server logs

**Manual Verification** (if needed):

```bash
# Check operator status
oc get csv -n openshift-gitops-operator

# Verify ArgoCD instance
oc get argocd -n openshift-gitops

# Check pod status
oc get pods -n openshift-gitops

# Get ArgoCD route
oc get route openshift-gitops-server -n openshift-gitops
```

📖 **Detailed guide**: [docs/deploying-gitops-guide.md](docs/deploying-gitops-guide.md)

### 2. Deploy Vault

Deploy HashiCorp Vault for centralized secret management (optional, but recommended):

```bash
# Navigate to the quickstart directory
cd quickstarts/fusion-gitops

# Verify prerequisites
oc whoami
helm version
oc get storageclass

# Deploy with default configuration (3 replicas, 10Gi storage)
./scripts/deploy-secret-manager.sh

# Wait for Vault to initialize
oc get pods -n vault -w

# Get root token (store securely)
oc get secret vault-unseal-keys -n vault \
  -o jsonpath='{.data.root-token}' | base64 -d && echo

# Get unseal keys (store securely)
oc get secret vault-unseal-keys -n vault -o yaml
```

#### Custom Configurations

```bash
# Use specific storage class
./scripts/deploy-secret-manager.sh --storage-class ocs-storagecluster-ceph-rbd

# Production deployment with HA
./scripts/deploy-secret-manager.sh --namespace vault-prod --replicas 5 --size 20Gi

# Custom namespace with specific storage
./scripts/deploy-secret-manager.sh \
  --namespace vault-staging \
  --storage-class thin \
  --size 15Gi
```

#### Validation

Run the comprehensive validation script to verify your Vault deployment:

```bash
# Run validation script
./scripts/validate-secret-manager.sh

# Run with verbose output for detailed diagnostics
./scripts/validate-secret-manager.sh --verbose

# Specify custom namespace
./scripts/validate-secret-manager.sh --namespace vault-prod
```

The validation script performs 12 comprehensive checks:

1. **StatefulSet Status**: Verifies Vault StatefulSet exists and is configured correctly
2. **Pod Health**: Checks all Vault pods are running and ready
3. **Service Availability**: Validates internal and external services are accessible
4. **Initialization Status**: Confirms Vault is initialized
5. **Seal Status**: Verifies Vault is unsealed and operational
6. **Unseal Keys Secret**: Ensures unseal keys are stored securely
7. **Storage**: Validates persistent volume claims are bound
8. **Route/Ingress**: Checks external access configuration
9. **Pod Logs**: Scans for RBAC errors, service registration issues, and other problems
10. **Vault Configuration**: Validates vault.hcl configuration (node_id, cluster_address, retry_join)
11. **Raft Cluster Status**: Checks Raft peer count, node IDs, and leader election
12. **Init Container Status**: Verifies config-init container completed successfully

**Manual Verification** (if needed):

```bash
# Check Vault operator
oc get csv -n vault

# Check pod status
oc get pods -n vault

# Test Vault connectivity
oc exec -n vault vault-0 -- vault status

# Get Vault route (if exposed)
oc get route -n vault
```

#### Troubleshooting Multi-Replica Deployments

If you encounter issues with multi-replica Vault deployments (followers not joining Raft cluster), use the diagnostic script:

```bash
# Run Raft diagnostics
./scripts/diagnose-vault-raft.sh -n vault

# Run with verbose output
./scripts/diagnose-vault-raft.sh -n vault --verbose
```

The diagnostic script checks:
- Pod status and health
- Leader (vault-0) initialization and seal status
- Vault configuration (retry_join, node_id)
- DNS resolution from follower pods
- HTTP connectivity to leader
- PVC status and Raft data directories
- Recent logs for error patterns

#### Important Security Notes

⚠️ **Critical**: The root token and unseal keys are stored in the `vault-unseal-keys` secret. Back them up securely and remove from the cluster in production:

```bash
# Export unseal keys and root token
oc get secret vault-unseal-keys -n vault -o yaml > vault-keys-backup.yaml

# Store in secure location (password manager, hardware security module, etc.)

# Optional: Remove from cluster after backing up (production only)
# oc delete secret vault-unseal-keys -n vault
```

📖 **Detailed guide**: [docs/deploying-vault-guide.md](docs/deploying-vault-guide.md)

### 3. Deploy External Secrets

Deploy External Secrets Operator to synchronize secrets from external backends (optional):

```bash
# Navigate to the quickstart directory
cd quickstarts/fusion-gitops

# Verify prerequisites
oc whoami
helm version

# Deploy operator only (no backend configuration)
./scripts/deploy-external-secrets.sh --standalone

# Wait for operator to be ready
oc get csv -n external-secrets-operator -w

# Verify operator installation
oc get csv -n external-secrets-operator
oc get pods -n external-secrets-operator
```

#### Backend Configuration

You can also deploy it with a secret backend. External Secrets Operator supports multiple secret management systems:

##### HashiCorp Vault Backend

Integrate with HashiCorp Vault for on-premises or self-hosted secret management:

```bash
# Configure Vault as secret backend (requires Vault deployed)
./scripts/deploy-external-secrets.sh --backend vault

# Verify ClusterSecretStore
oc get clustersecretstore vault-backend

# Check backend status
oc describe clustersecretstore vault-backend
```

**Prerequisites**:
- Vault instance deployed and accessible
- Kubernetes authentication enabled in Vault
- Vault policies configured for secret access

**Use Cases**:
- On-premises deployments
- Existing Vault infrastructure

##### AWS Secrets Manager Backend

Integrate with AWS Secrets Manager for cloud-native AWS deployments:

```bash
# Prerequisites: Create AWS credentials secret
kubectl create secret generic aws-credentials \
  -n external-secrets-operator \
  --from-literal=access-key-id=YOUR_ACCESS_KEY \
  --from-literal=secret-access-key=YOUR_SECRET_KEY

# Deploy with AWS Secrets Manager backend
./scripts/deploy-external-secrets.sh --backend aws

# Verify ClusterSecretStore
oc get clustersecretstore aws-secrets-manager

# Check backend status
oc describe clustersecretstore aws-secrets-manager
```

**Prerequisites**:
- AWS account with Secrets Manager enabled
- IAM user or role with permissions:
  - `secretsmanager:GetSecretValue`
  - `secretsmanager:DescribeSecret`
  - `secretsmanager:ListSecrets`

**Use Cases**:
- AWS-native deployments
- EKS clusters
- Multi-region AWS applications
- Integration with AWS services

##### IBM Cloud Secrets Manager Backend

Integrate with IBM Cloud Secrets Manager for IBM Cloud deployments:

```bash
# Prerequisites: Create IBM Cloud API key secret
kubectl create secret generic ibm-cloud-credentials \
  -n external-secrets-operator \
  --from-literal=api-key=YOUR_IBM_CLOUD_API_KEY

# Deploy with IBM Cloud Secrets Manager backend
./scripts/deploy-external-secrets.sh --backend ibmcloud

# Verify ClusterSecretStore
oc get clustersecretstore ibm-secrets-manager

# Check backend status
oc describe clustersecretstore ibm-secrets-manager
```

**Prerequisites**:
- IBM Cloud account with Secrets Manager instance
- IBM Cloud API key with access to Secrets Manager
- Secrets Manager instance URL and region

**Use Cases**:
- IBM Cloud deployments
- OpenShift on IBM Cloud
- Hybrid cloud with IBM infrastructure
- Integration with IBM Cloud services

#### Creating ExternalSecrets

After configuring a backend, create ExternalSecret resources to sync secrets:

```bash
# Example: Sync a secret from Vault
cat <<EOF | oc apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-app-secrets
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: secret/data/prod/myapp/database
        property: password
    - secretKey: api-key
      remoteRef:
        key: secret/data/prod/myapp/api
        property: key
EOF

# Verify secret synchronization
oc get externalsecret my-app-secrets
oc get secret my-app-secrets
```

#### Validation

Run the comprehensive validation script to verify your External Secrets Operator deployment:

```bash
# Run validation script
./scripts/validate-external-secrets.sh

# Run with verbose output for detailed diagnostics
./scripts/validate-external-secrets.sh --verbose

# Specify custom namespace
./scripts/validate-external-secrets.sh --namespace my-external-secrets

# Validate with backend connectivity check
./scripts/validate-external-secrets.sh --backend vault
```

The validation script performs 14 comprehensive checks:

1. **Namespace**: Verifies operator namespace exists
2. **Operator Subscription**: Checks subscription is created and active
3. **ClusterServiceVersion (CSV)**: Confirms CSV is in "Succeeded" phase
4. **Operator Pods**: Validates operator pods are running and ready
5. **Webhook Pods**: Checks webhook pods are operational
6. **Cert Controller Pods**: Verifies cert-controller pods are running
7. **CRDs Installed**: Ensures all required CRDs are established (ClusterSecretStore, ExternalSecret, SecretStore, ClusterExternalSecret)
8. **ClusterSecretStores**: Lists configured ClusterSecretStores and their status
9. **SecretStores**: Shows namespace-scoped SecretStores
10. **Configured Secret Backends**: Automatically detects and displays details of configured HashiCorp Vault backend including server URL, authentication method, and connection status
11. **ExternalSecrets**: Validates ExternalSecret resources and sync status
12. **Service Account**: Confirms operator service account exists
13. **RBAC Configuration**: Checks ClusterRole and ClusterRoleBinding
14. **Backend Connectivity** (optional): Tests connectivity to HashiCorp Vault backend when --backend flag is used

**Manual Verification** (if needed):

```bash
# Check operator status
oc get csv -n external-secrets-operator

# List all secret stores
oc get clustersecretstore

# Check operator logs
oc logs -n external-secrets-operator -l app=external-secrets-operator --tail=50
```

📖 **Detailed guide**: [docs/deploying-external-secrets-guide.md](docs/deploying-external-secrets-guide.md)

## Sample Application

Once you have deployed the GitOps platform components (ArgoCD, Vault, and External Secrets Operator), you can deploy a complete end-to-end sample application that demonstrates the entire workflow in action.

**📦 Agentic Chat Assistant Sample Application**

This reference implementation showcases production-ready deployment patterns with:
- ✅ GitOps continuous delivery using ArgoCD
- ✅ Automated secret management with Vault and External Secrets Operator
- ✅ Zero-downtime secret rotation using Stakater Reloader
- ✅ Complete RAG (Retrieval-Augmented Generation) pipeline

The sample application provides a practical example of deploying AI/ML workloads with secure secret management on Fusion HCI.

📖 **Get started**: [fusion-gitops-sample-app/README.md](../../fusion-gitops-sample-app/README.md)

## Cleanup

Remove deployed components safely using the provided cleanup scripts. Always clean up in reverse order of deployment.

### Cleanup Order

1. External Secrets Operator (if deployed)
2. Vault (if deployed)
3. GitOps (if no longer needed)

### Cleanup External Secrets

```bash
cd quickstarts/fusion-gitops

# Interactive cleanup (prompts for confirmation)
./scripts/cleanup-external-secrets.sh

# Force cleanup without prompts
./scripts/cleanup-external-secrets.sh --force

# Keep namespace after cleanup
./scripts/cleanup-external-secrets.sh --keep-namespace

# Custom namespace
./scripts/cleanup-external-secrets.sh --namespace my-external-secrets
```

**Options**:
- `--namespace <name>`: Specify operator namespace (default: `external-secrets-operator`)
- `--keep-namespace`: Keep the namespace after cleanup
- `--force`: Skip confirmation prompts
- `--help`: Show usage information

### Cleanup Vault

⚠️ **Warning**: This will delete all secrets stored in Vault. Ensure you have backups!

```bash
cd quickstarts/fusion-gitops

# Interactive cleanup (prompts for confirmation)
./scripts/cleanup-secret-manager.sh

# Force cleanup without prompts
./scripts/cleanup-secret-manager.sh --force

# Keep operator installed
./scripts/cleanup-secret-manager.sh --keep-operator

# Keep namespace after cleanup
./scripts/cleanup-secret-manager.sh --keep-namespace

# Custom namespace
./scripts/cleanup-secret-manager.sh --namespace vault-prod
```

**Options**:
- `--namespace <name>`: Specify Vault namespace (default: `vault`)
- `--keep-operator`: Keep the Vault operator installed
- `--keep-namespace`: Keep the namespace after cleanup
- `--force`: Skip confirmation prompts
- `--help`: Show usage information

### Cleanup GitOps

⚠️ **Warning**: This will remove ArgoCD and all managed applications!

```bash
cd quickstarts/fusion-gitops

# Interactive cleanup (prompts for confirmation)
./scripts/cleanup-gitops.sh

# Dry run (show what would be deleted)
./scripts/cleanup-gitops.sh --dry-run

# Force cleanup without prompts
./scripts/cleanup-gitops.sh --force

# Keep operator, remove instances only
./scripts/cleanup-gitops.sh --keep-operator

# Keep namespace after cleanup
./scripts/cleanup-gitops.sh --keep-namespace
```

**Options**:
- `--keep-operator`: Keep operator installed, remove instances only
- `--keep-namespace`: Don't delete namespaces
- `--force`: Skip confirmation prompts
- `--dry-run`: Show what would be done without doing it
- `--help`: Show usage information

### Complete Cleanup

Remove all components in the correct order:

```bash
cd quickstarts/fusion-gitops

# Clean up everything (with prompts)
./scripts/cleanup-external-secrets.sh
./scripts/cleanup-secret-manager.sh
./scripts/cleanup-gitops.sh

# Force cleanup of everything
./scripts/cleanup-external-secrets.sh --force
./scripts/cleanup-secret-manager.sh --force
./scripts/cleanup-gitops.sh --force
```

## Detailed Guides

For in-depth information, architecture details, troubleshooting, and advanced configurations, refer to the detailed guides:

### Component Guides
- [**GitOps Deployment Guide**](docs/deploying-gitops-guide.md)
  - Advanced configuration options
  - Troubleshooting common issues

- [**HashiCorp Vault Deployment Guide**](docs/deploying-vault-guide.md)
  - High availability configuration
  - Security best practices

- [**External Secrets Deployment Guide**](docs/deploying-external-secrets-guide.md)
  - Backend configuration
  - Troubleshooting sync issues
  - Security considerations

## Project Structure

```text
quickstarts/fusion-gitops/
├── README.md                               # Main documentation and quickstart guide
├── ansible/                                # Ansible automation for deployment workflows
│   ├── ansible.cfg                         # Ansible configuration settings
│   ├── requirements.yml                    # Ansible Galaxy collection dependencies
│   ├── inventory/
│   │   └── localhost                       # Local inventory for Ansible execution
│   ├── playbooks/
│   │   ├── deploy.yml                      # Main deployment playbook for all components
│   │   └── initialize-vault.yml            # Vault initialization and unsealing playbook
│   └── roles/
│       ├── configuration/                  # Configuration management role
│       ├── helm-deploy/                    # Helm chart deployment automation role
│       ├── preflight/                      # Pre-deployment validation checks role
│       └── validation/                     # Post-deployment validation role
├── docs/
│   ├── deploying-gitops-guide.md           # Detailed GitOps deployment guide with architecture
│   ├── deploying-vault-guide.md            # Detailed Vault deployment and configuration guide
│   └── deploying-external-secrets-guide.md # Detailed External Secrets Operator deployment guide
├── helm/
│   ├── fusion-gitops/
│   │   ├── Chart.yaml                      # Helm chart metadata for GitOps deployment
│   │   ├── values.yaml                     # Default values for GitOps chart
│   │   ├── values-odf.yaml                 # OpenShift Data Foundation storage configuration
│   │   ├── environments/                   # Environment-specific configurations
│   │   │   ├── dev/
│   │   │   │   └── values.yaml             # Development environment (minimal resources)
│   │   │   ├── stage/
│   │   │   │   └── values.yaml             # Staging environment (moderate resources)
│   │   │   └── prod/
│   │   │       └── values.yaml             # Production environment (HA with persistent storage)
│   │   └── templates/                      # Kubernetes resource templates for GitOps
│   ├── vault-operator/
│   │   ├── Chart.yaml                      # Helm chart metadata for Vault deployment
│   │   ├── values.yaml                     # Default values for Vault chart
│   │   ├── values-standalone-example.yaml  # Example standalone Vault configuration
│   │   └── templates/                      # Kubernetes resource templates for Vault
│   └── external-secrets-operator/
│       ├── Chart.yaml                      # Helm chart metadata for External Secrets
│       ├── values.yaml                     # Default values for External Secrets chart
│       ├── values-standalone.yaml          # Standalone operator deployment configuration
│       ├── examples/                       # Example configurations for different backends
│       └── templates/                      # Kubernetes resource templates for External Secrets
└── scripts/
    ├── deploy-gitops.sh                    # Script to deploy OpenShift GitOps
    ├── deploy-secret-manager.sh            # Script to deploy HashiCorp Vault
    ├── deploy-external-secrets.sh          # Script to deploy External Secrets Operator
    ├── validate-gitops.sh                  # Comprehensive GitOps deployment validation script
    ├── validate-secret-manager.sh          # Comprehensive Vault deployment validation script
    ├── validate-external-secrets.sh        # Comprehensive External Secrets validation script
    ├── diagnose-vault-raft.sh              # Deep troubleshooting tool for Vault Raft cluster issues
    ├── unseal-secret-manager.sh            # Script to unseal Vault instances
    ├── cleanup-gitops.sh                   # Script to remove GitOps components
    ├── cleanup-secret-manager.sh           # Script to remove Vault components
    ├── cleanup-external-secrets.sh         # Script to remove External Secrets components
    └── lib/
        └── common.sh                       # Shared utility functions for all scripts
```
