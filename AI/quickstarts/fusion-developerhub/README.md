# IBM Fusion Developer Hub - Operator-Based Deployment

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenShift](https://img.shields.io/badge/OpenShift-4.12+-red.svg)](https://www.redhat.com/en/technologies/cloud-computing/openshift)
[![Red Hat](https://img.shields.io/badge/Red%20Hat-Certified-red.svg)](https://www.redhat.com/)

Production-ready Helm chart for deploying Red Hat Developer Hub with IBM Fusion AI components on IBM Fusion platform using Kubernetes operators.

> **Platform**: IBM Fusion on Red Hat OpenShift 4.12+
> This chart uses operator-based deployment for enterprise-grade reliability, high availability, and automated lifecycle management.

## 🎯 Purpose

Deploy Red Hat Developer Hub on IBM Fusion with:
- **Operator-Based Management** - Automated deployment, updates, and day-2 operations
- **IBM Fusion AI Integration** - WatsonX, Granite models, and modernization tools
- **High Availability** - Multi-instance PostgreSQL with automatic failover
- **Enterprise Security** - RBAC, network policies, and pod security standards

## ✨ Key Features

- 🎨 **Pre-configured Homepage** - IBM Fusion branding with AI capabilities
- 🔐 **OIDC Authentication** - Integrated with IBM Fusion identity providers
- 🤖 **AI-Powered Development** - WatsonX and Granite models for code generation
- 🔄 **Application Modernization** - Transformation Advisor and Mono2Micro
- 📦 **Software Catalog** - Discover and manage Fusion components
- 🚀 **Self-Service Templates** - Rapid application creation with AI
- 🔒 **Enterprise Security** - Production-grade security and compliance

## 🚀 Quick Start

### Prerequisites

- IBM Fusion platform on Red Hat OpenShift 4.12+
- Helm 3.8+
- `oc` CLI tools
- Cluster admin access for operator installation

### Deploy Developer Hub

```bash
# Clone repository
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/AI/quickstarts/fusion-developerhub

# Deploy with guest access (demos/testing)
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-guest-access-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-dev-hub \
  --create-namespace

# Wait for deployment
oc wait --for=condition=ready pod \
  -l app.kubernetes.io/name=backstage \
  -n fusion-dev-hub \
  --timeout=600s

# Get the route
oc get route -n fusion-dev-hub
```

Access Developer Hub at: `https://backstage-fusion-hub-fusion-dev-hub.apps.your-cluster.example.com`

## 📋 Deployment Examples

### 1. Guest Access (Demos & Testing)
**File**: `examples/operator-fusion-guest-access-values.yaml`

```bash
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-guest-access-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-dev-hub \
  --create-namespace
```

**Features**:
- No authentication required
- Single PostgreSQL instance
- Minimal resources
- Perfect for demos and quick testing

### 2. Development with OIDC
**File**: `examples/operator-fusion-development-values.yaml`

```bash
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-development-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-dev-hub \
  --create-namespace
```

**Features**:
- OIDC authentication enabled
- IBM Fusion AI components
- Single PostgreSQL instance
- Development-optimized resources

### 3. Production with High Availability
**File**: `examples/operator-fusion-production-values.yaml`

```bash
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-production-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-hub \
  --create-namespace
```

**Features**:
- OIDC authentication required
- 3-instance PostgreSQL cluster with automatic failover
- Automated backups to S3
- Production-grade resources and security
- Network policies and resource quotas

## 🏗️ Architecture

### Operator-Based Deployment

```
┌─────────────────────────────────────────────────────────┐
│                    IBM Fusion Platform                   │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────────┐      ┌──────────────────┐        │
│  │  RHDH Operator   │      │ Postgres Operator│        │
│  │  (AllNamespaces) │      │  (AllNamespaces) │        │
│  └────────┬─────────┘      └────────┬─────────┘        │
│           │                         │                    │
│           ▼                         ▼                    │
│  ┌──────────────────┐      ┌──────────────────┐        │
│  │   Backstage CR   │      │ PostgresCluster  │        │
│  │  (fusion-hub)    │◄────►│   (3 instances)  │        │
│  └──────────────────┘      └──────────────────┘        │
│           │                                              │
│           ▼                                              │
│  ┌──────────────────────────────────────────┐          │
│  │        Developer Hub Pods                 │          │
│  │  ┌────────┐  ┌────────┐  ┌────────┐     │          │
│  │  │ RHDH-1 │  │ RHDH-2 │  │ RHDH-3 │     │          │
│  │  └────────┘  └────────┘  └────────┘     │          │
│  └──────────────────────────────────────────┘          │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

### Components

- **Red Hat Developer Hub Operator** - Manages Backstage lifecycle
- **Crunchy PostgreSQL Operator** - Manages database cluster
- **Backstage CR** - Developer Hub instance configuration
- **PostgresCluster CR** - High-availability database

## 📚 Documentation

- **[Deployment Guide](docs/getting-started/operator-getting-started.md)** - Complete deployment instructions with all options
- **[Homepage Customization](docs/homepage-customization.md)** - Customize the homepage
- **[Adding Fusion Services](docs/adding-fusion-services.md)** - Integrate Fusion AI services
- **[OIDC Providers](docs/getting-started/oidc-providers.md)** - Configure authentication
- **[Troubleshooting](docs/troubleshooting/README.md)** - Common issues and solutions

## 🔧 Configuration

### Global Settings

```yaml
global:
  wildcardDomain: apps.your-cluster.example.com  # Required
  toolsImage: quay.io/openshift/origin-cli:latest
  modelsNamespace: maas-models
```

### Authentication

```yaml
developerHub:
  auth:
    guest:
      enabled: true  # For demos only
    oidc:
      enabled: true  # Production
      metadataUrl: "https://your-oidc-provider/.well-known/openid-configuration"
```

### Database

```yaml
developerHub:
  database:
    useOperator: true
    instances: 3  # High availability
    backup:
      enabled: true
      useODF: true  # IBM Fusion object storage
```

## 🛠️ Operations

### Check Deployment Status

```bash
# Check operators
oc get csv -n rhdh-operator
oc get csv -n postgres-operator

# Check Developer Hub
oc get backstage -n fusion-dev-hub
oc get pods -n fusion-dev-hub

# Check PostgreSQL
oc get postgrescluster -n fusion-dev-hub
```

### View Logs

```bash
# Developer Hub logs
oc logs -n fusion-dev-hub -l app.kubernetes.io/name=backstage -f

# PostgreSQL logs
oc logs -n fusion-dev-hub -l postgres-operator.crunchydata.com/cluster=fusion-postgres -f
```

### Upgrade

```bash
helm upgrade fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-production-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-hub
```

## 🔍 Troubleshooting

### Common Issues

**Operators not installing**
```bash
# Check operator subscriptions
oc get subscription -n rhdh-operator
oc get subscription -n postgres-operator
```

**PostgreSQL not ready**
```bash
# Check cluster status
oc describe postgrescluster -n fusion-dev-hub
```

**Developer Hub not starting**
```bash
# Check Backstage CR
oc describe backstage -n fusion-dev-hub
```

See [Troubleshooting Guide](docs/troubleshooting/README.md) for detailed solutions.

## 📊 Monitoring

The deployment includes:
- Operator metrics and health checks
- PostgreSQL cluster monitoring
- Developer Hub application metrics
- Integration with IBM Fusion monitoring stack

## 🔒 Security

- **Pod Security Standards** - Restricted profile enforced
- **Network Policies** - Controlled ingress/egress
- **RBAC** - Least privilege access
- **Secrets Management** - Operator-managed secrets
- **Resource Quotas** - Prevent resource exhaustion

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## 📄 License

Apache License 2.0 - See [LICENSE](LICENSE) for details

## 🆘 Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/IBM/storage-fusion/issues)
- **IBM Fusion Support**: Contact your IBM Fusion support team

---

**Made with Bob** 🤖 | **Powered by IBM Fusion AI**