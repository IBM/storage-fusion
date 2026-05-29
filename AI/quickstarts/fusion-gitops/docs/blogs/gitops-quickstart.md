# Quickstart: Red Hat OpenShift GitOps (ArgoCD) on IBM Fusion

## The Challenge: GitOps Setup Complexity

Picture this: Your team has just been tasked with deploying a new AI/ML pipeline on your Fusion HCI cluster. You need GitOps for continuous delivery, secure secret management for API keys and credentials, and automated secret synchronization across multiple environments. Simple enough, right?

Not quite. Setting up a production-ready GitOps platform traditionally involves:

- **Days of operator installations**: Manually configuring Red Hat OpenShift GitOps, HashiCorp Vault, and External Secrets Operator
- **Configuration maze**: Wrestling with operator subscriptions, waiting for CRDs to become available, and debugging RBAC issues
- **Storage headaches**: Setting up persistent storage with appropriate performance characteristics for each component
- **Integration challenges**: Ensuring all components communicate securely and work together seamlessly
- **Security concerns**: Configuring authentication, encryption, and access control across the entire stack
- **Validation uncertainty**: Manually verifying that everything actually works before deploying production workloads

What if you could skip all of this complexity and deploy a complete, enterprise-grade GitOps platform with centralized secret management in the time it takes to grab a coffee?

## The Solution: Fusion GitOps Quickstart

The Fusion GitOps Quickstart is a comprehensive automation toolkit designed specifically for IBM Fusion environments. It provides **one-command deployment** of a complete GitOps stack with production-ready defaults, eliminating weeks of configuration work and reducing the risk of misconfiguration.

Whether you're deploying AI/ML workloads, managing microservices, or orchestrating multi-cluster applications, this quickstart gets you from zero to GitOps in **minutes instead of days**.

## What You'll Deploy

This quickstart delivers three integrated components that work seamlessly together:

### 🚀 Red Hat OpenShift GitOps (ArgoCD)
Enterprise-grade continuous delivery with declarative GitOps workflows. Deploy applications, manage configurations, and maintain consistency across environments, all from Git.

**Key capabilities:**
- **Declarative Application Deployment**: Define your entire application stack in Git and let ArgoCD handle the rest
- **Automated Sync and Self-Healing**: Applications automatically reconcile to match Git state
- **RBAC Integration**: Seamless integration with OpenShift authentication for fine-grained access control
- **Multi-Environment Support**: Pre-configured values files for development, staging, and production
- **High Availability**: Production configurations with replica sets and persistent storage

### 🔐 HashiCorp Vault
Industry-standard secret storage with encryption at rest and in transit. Centralize secret management across your entire infrastructure with enterprise-grade security.

**Key capabilities:**
- **Encrypted Secret Storage**: All secrets encrypted with automatic unsealing for seamless operations
- **High Availability with Raft Consensus**: Multi-replica deployment ensures no single point of failure
- **Auto-Initialization**: Automated unsealing and root token management
- **Persistent Storage**: Configurable storage classes for data durability

### 🔄 External Secrets Operator
Automatic secret synchronization from external vaults to Kubernetes secrets. Bridge the gap between centralized secret management and Kubernetes-native applications.

**Key capabilities:**
- **Real-Time Secret Synchronization**: Secrets automatically sync from Vault to Kubernetes
- **GitOps-Friendly Secret References**: Define ExternalSecret resources in Git without exposing sensitive data

## Prerequisites

Before you begin, ensure you have:

### Required
- **Fusion HCI Cluster**: OpenShift 4.20+ or Kubernetes 1.27+ running on Fusion HCI
- **Cluster Access**: Cluster admin privileges for operator installation
- **CLI Tools**:
  - `oc` (OpenShift CLI) or `kubectl` configured and authenticated
  - `helm` 3.12+ for chart deployments
- **Storage**: At least one StorageClass available for persistent volumes
  - Recommended: `ocs-storagecluster-ceph-rbd` (OpenShift Data Foundation)
  - Minimum: 10Gi available storage per component

### Verify Your Environment

Run these commands to verify your environment is ready:

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

## Step-by-Step Deployment

Each component can be deployed independently or as part of a complete stack.

### Fork and Clone the Repository

Before deploying, fork the repository at `https://github.com/IBM/Fusion-AI` to your own GitHub account (click the Fork button on GitHub). This is essential for GitOps workflows as it allows you to customize configurations and track changes.

```bash
# Clone your fork (replace <YOUR_USERNAME> with your GitHub username)
git clone https://github.com/<YOUR_USERNAME>/Fusion-AI.git
cd Fusion-AI/

# Add the original repository as upstream remote
git remote add upstream https://github.com/IBM/Fusion-AI.git

# Verify remotes
git remote -v
```

All commands should be run from the `quickstarts/fusion-gitops` directory.

### Step 1: Deploy Red Hat OpenShift GitOps

Deploy ArgoCD as the foundation for your GitOps platform:

```bash
# Deploy with default configuration
./scripts/deploy-gitops.sh
```

**What happens during deployment:**
1. Creates `openshift-gitops-operator` namespace
2. Installs Red Hat OpenShift GitOps operator
3. Waits for operator to be ready
4. Deploys ArgoCD instance with production-ready defaults
5. Configures persistent storage for ArgoCD components
6. Sets up RBAC and authentication

#### Monitor the Deployment

Watch the pods come up:

```bash
# Watch pod status
oc get pods -n openshift-gitops -w
```

#### Access ArgoCD UI

Get the ArgoCD server URL and admin password:

```bash
# Get ArgoCD server URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' && echo

# Get admin password
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d && echo
```

**💡 Tip**: Save these credentials securely. You'll need them to access the ArgoCD web interface.

#### Environment-Specific Deployments

Choose the appropriate values file for your environment:

```bash
# Development/Testing (minimal resources)
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-minimal.yaml

# Production (HA with persistent storage)
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-production.yaml

# OpenShift Data Foundation storage
./scripts/deploy-gitops.sh -f helm/fusion-gitops/values-odf.yaml
```

#### Validate GitOps Deployment

Run the comprehensive validation script to verify your deployment:

```bash
# Run validation script
./scripts/validate-gitops.sh
```

**Troubleshooting**: If validation fails, run with verbose output:

```bash
./scripts/validate-gitops.sh --verbose
```

### Step 2: Deploy HashiCorp Vault (Optional)

Deploy Vault for centralized secret management:

```bash
# Deploy with default configuration (3 replicas, 10Gi storage)
./scripts/deploy-secret-manager.sh
```

**What happens during deployment:**
1. Creates `vault` namespace
2. Installs HashiCorp Vault operator
3. Deploys Vault StatefulSet with Raft storage backend
4. Initializes Vault and generates unseal keys
5. Automatically unseals all Vault replicas
6. Stores root token and unseal keys in Kubernetes secret

#### Monitor Vault Deployment

```bash
# Watch Vault pods
oc get pods -n vault -w
```

#### Retrieve Vault Credentials

```bash
# Get root token (store securely!)
oc get secret vault-unseal-keys -n vault \
  -o jsonpath='{.data.root-token}' | base64 -d && echo

# Get unseal keys (store securely!)
oc get secret vault-unseal-keys -n vault -o yaml
```

**⚠️ Critical Security Note**: The root token and unseal keys are stored in the `vault-unseal-keys` secret. Back them up securely and remove from the cluster in production:

```bash
# Export unseal keys and root token
oc get secret vault-unseal-keys -n vault -o yaml > vault-keys-backup.yaml

# Store in secure location (password manager, hardware security module, etc.)

# Optional: Remove from cluster after backing up (production only)
# oc delete secret vault-unseal-keys -n vault
```

#### Custom Vault Configurations

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

#### Validate Vault Deployment

Run the validation script to verify Vault is operational:

```bash
# Run validation script
./scripts/validate-secret-manager.sh
```

**Troubleshooting Multi-Replica Issues**: If followers aren't joining the Raft cluster:

```bash
# Run Raft diagnostics
./scripts/diagnose-vault-raft.sh -n vault

# Run with verbose output
./scripts/diagnose-vault-raft.sh -n vault --verbose
```

### Step 3: Deploy External Secrets Operator (Optional)

Deploy External Secrets Operator to synchronize secrets from Vault:

```bash
# Deploy operator only (no backend configuration)
./scripts/deploy-external-secrets.sh --standalone
```

**What happens during deployment:**
1. Creates `external-secrets-operator` namespace
2. Installs External Secrets Operator
3. Deploys operator, webhook, and cert-controller pods
4. Installs required CRDs (ClusterSecretStore, ExternalSecret, SecretStore)

#### Configure Vault Backend

After deploying the operator, configure Vault as the secret backend:

```bash
# Configure Vault as secret backend (requires Vault deployed)
./scripts/deploy-external-secrets.sh --backend vault
```

#### Validate External Secrets Deployment

Run the validation script:

```bash
# Run validation script
./scripts/validate-external-secrets.sh

# Validate with backend connectivity check
./scripts/validate-external-secrets.sh --backend vault
```

## Architecture Overview

The Fusion GitOps Quickstart creates a layered architecture optimized for Fusion HCI:

```
┌──────────────────────────────────────────────────────────┐
│                   Fusion HCI Cluster                     │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │         Red Hat OpenShift GitOps (ArgoCD)          │  │
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

**How It Works:**

1. **GitOps Layer**: ArgoCD monitors Git repositories and automatically deploys applications to the cluster
2. **Secret Management Layer**: Vault stores all sensitive data with encryption and access control
3. **Synchronization Layer**: External Secrets Operator bridges Vault and Kubernetes, automatically syncing secrets
4. **Application Layer**: Your workloads consume secrets as native Kubernetes resources, unaware of the underlying complexity

This architecture provides separation of concerns while maintaining seamless integration. Each layer can be managed independently, yet they work together to provide a cohesive platform.

## What Makes This Unique

Unlike generic GitOps tutorials or basic operator installations, the Fusion GitOps Quickstart provides:

- **IBM Fusion HCI Optimization**: Configurations tuned for IBM Fusion HCI's storage and networking capabilities
- **End-to-End Integration**: All components pre-configured to work together seamlessly
- **Production-Ready Defaults**: HA configurations, persistent storage, and security settings based on real-world deployments
- **Comprehensive Automation**: From operator installation to validation, everything is automated
- **Battle-Tested**: Configurations refined through actual enterprise deployments
- **Extensible Foundation**: Easy to customize and extend for specific requirements

## Cleanup

Remove deployed components safely using the provided cleanup scripts. Always clean up in reverse order of deployment.

### Cleanup Order

1. External Secrets Operator (if deployed)
2. Vault (if deployed)
3. GitOps (if no longer needed)

```bash
# Clean up External Secrets
./scripts/cleanup-external-secrets.sh

# Clean up Vault (⚠️ Warning: This will delete all secrets!)
./scripts/cleanup-secret-manager.sh

# Clean up GitOps (⚠️ Warning: This will remove ArgoCD and all managed applications!)
./scripts/cleanup-gitops.sh
```

**Force cleanup without prompts:**

```bash
./scripts/cleanup-external-secrets.sh --force
./scripts/cleanup-secret-manager.sh --force
./scripts/cleanup-gitops.sh --force
```

## Conclusion

The Fusion GitOps Quickstart transforms what used to be a multi-day configuration project into a quick automated deployment. By combining Red Hat OpenShift GitOps, HashiCorp Vault, and External Secrets Operator with production-ready defaults and comprehensive automation, it eliminates the complexity of GitOps platform setup.

**What you've accomplished:**
- Deployed enterprise-grade GitOps platform in minutes
- Configured centralized secret management with encryption
- Set up automatic secret synchronization
- Validated all components with comprehensive health checks
- Established a foundation for production workloads

Whether you're deploying AI/ML workloads, managing microservices, orchestrating multi-cluster applications, or building multi-tenant SaaS platforms, this quickstart provides the foundation you need, with the security, reliability, and flexibility required for production environments.

## Ready to Get Started?

### Quick Start Commands

```bash
cd Fusion-AI/quickstarts/fusion-gitops

# Deploy complete stack
./scripts/deploy-gitops.sh
./scripts/deploy-secret-manager.sh
./scripts/deploy-external-secrets.sh --backend vault

# Validate deployments
./scripts/validate-gitops.sh
./scripts/validate-secret-manager.sh
./scripts/validate-external-secrets.sh --backend vault
```

### Additional Resources

**Detailed Guides:**
- [GitOps Deployment Guide](../deploying-gitops-guide.md) - Advanced configuration and troubleshooting
- [Vault Deployment Guide](../deploying-vault-guide.md) - High availability and security best practices
- [External Secrets Guide](../deploying-external-secrets-guide.md) - Backend configuration and sync troubleshooting

**Main Documentation:**
- [Complete Installation Guide](../../README.md) - Comprehensive documentation with all deployment options

**What you'll find in the guides:**
- Prerequisites and environment setup
- Advanced configuration options
- Troubleshooting common issues
- Security best practices
- Multi-environment deployment strategies
- Integration with existing infrastructure

Your production-ready GitOps platform is just minutes away. Get started today!
