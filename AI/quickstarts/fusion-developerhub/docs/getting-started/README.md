# Getting Started with Fusion Developer Hub

Quick start guides for deploying Red Hat Developer Hub on IBM Fusion platform.

## 📚 Guides in This Section

### [Operator Getting Started](./operator-getting-started.md)
**Complete deployment guide using Kubernetes operators**

Learn how to:
- Install Red Hat Developer Hub operator
- Deploy Crunchy PostgreSQL operator
- Create a Developer Hub instance
- Configure authentication
- Verify the deployment

**Start here if**: You're deploying for the first time

---

### [OIDC Providers](./oidc-providers.md)
**Configure OIDC authentication with IBM Fusion**

Learn how to:
- Connect to IBM Fusion identity providers
- Configure OpenShift OAuth
- Set up external OIDC providers
- Test authentication flow
- Troubleshoot OIDC issues

**Start here if**: You need to configure authentication

---

### [RHOAI Integration](./rhoai-integration.md)
**Integrate with Red Hat OpenShift AI**

Learn how to:
- Enable automatic AI model discovery
- Configure RBAC permissions for RHOAI connector
- Set up authentication tokens
- Monitor model deployments
- Troubleshoot integration issues

**Start here if**: You want to discover and display RHOAI models

---

## 🚀 Quick Start

### 1. Deploy with Guest Access (Fastest)

Perfect for demos and testing:

```bash
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-guest-access-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-dev-hub \
  --create-namespace
```

### 2. Deploy with OIDC Authentication

For development environments:

```bash
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-development-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-dev-hub \
  --create-namespace
```

### 3. Deploy for Production

With high availability:

```bash
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-production-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-hub \
  --create-namespace
```

---

## ✅ Prerequisites

Before starting, ensure you have:

- ✅ **IBM Fusion platform** on Red Hat OpenShift 4.12+
- ✅ **Cluster admin access** for operator installation
- ✅ **Helm 3.8+** installed locally
- ✅ **`oc` CLI** configured and logged in
- ✅ **Wildcard domain** for your cluster (e.g., `apps.your-cluster.example.com`)

### Resource Requirements

**Minimal (Guest Access)**:
- 2 CPU cores
- 4 GB RAM
- 20 GB storage

**Production (HA)**:
- 12 CPU cores
- 24 GB RAM
- 150 GB storage

---

## 📋 Deployment Steps

### Step 1: Clone Repository

```bash
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/AI/quickstarts/fusion-developerhub
```

### Step 2: Choose Your Configuration

Select the appropriate example file:

| File | Use Case | Auth | Database |
|------|----------|------|----------|
| `operator-fusion-guest-access-values.yaml` | Demos, testing | Guest | Single |
| `operator-fusion-development-values.yaml` | Development | OIDC | Single |
| `operator-fusion-production-values.yaml` | Production | OIDC | HA (3) |

### Step 3: Deploy

```bash
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/<your-chosen-file>.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-dev-hub \
  --create-namespace
```

### Step 4: Wait for Deployment

```bash
# Watch operators install
oc get csv -n rhdh-operator -w
oc get csv -n postgres-operator -w

# Watch Developer Hub deploy
oc get backstage -n fusion-dev-hub -w
oc get pods -n fusion-dev-hub -w
```

### Step 5: Access Developer Hub

```bash
# Get the route URL
oc get route -n fusion-dev-hub

# Access at:
# https://backstage-fusion-hub-fusion-dev-hub.apps.your-cluster.example.com
```

---

## 🔍 Verification

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

### Run Validation Scripts

```bash
# Validate deployment
./scripts/check-deployment.sh

# Check homepage
./scripts/check-homepage.sh

# Diagnose issues
./scripts/diagnose-pods.sh
```

---

## 🎯 Next Steps

After successful deployment:

1. **Configure Authentication**: See [OIDC Providers](./oidc-providers.md)
2. **Customize Homepage**: See [Homepage Customization](../homepage-customization.md)
3. **Add Services**: See [Adding Fusion Services](../adding-fusion-services.md)
4. **Explore Templates**: Check the `/create` page in Developer Hub

---

## ⚠️ Common Issues

### Operators Not Installing

**Symptom**: CSV stuck in "Installing" state

**Solution**:
```bash
# Check subscription
oc get subscription -n rhdh-operator
oc describe subscription rhdh-operator -n rhdh-operator

# Check install plan
oc get installplan -n rhdh-operator
```

See: [Operator Getting Started - Troubleshooting](./operator-getting-started.md#troubleshooting)

---

### Database Connection Errors

**Symptom**: Backstage pods failing with database errors

**Solution**:
```bash
# Check PostgreSQL cluster
oc get postgrescluster -n fusion-dev-hub
oc describe postgrescluster -n fusion-dev-hub

# Check CREATEDB job
oc get jobs -n fusion-dev-hub | grep createdb
```

See: [PostgreSQL Troubleshooting](../troubleshooting/postgresql-troubleshooting.md)

---

### Authentication Not Working

**Symptom**: Can't log in with OIDC

**Solution**:
```bash
# Check OIDC configuration
oc get configmap developerhub-app-config -n fusion-dev-hub -o yaml | grep -A 10 "oidc:"

# Check secrets
oc get secret -n fusion-dev-hub | grep oidc
```

See: [OIDC Providers - Troubleshooting](./oidc-providers.md#troubleshooting)

---

## 📖 Related Documentation

- [Deployment Guide](../DEPLOYMENT-GUIDE.md) - Comprehensive deployment documentation
- [Troubleshooting](../troubleshooting/) - Problem-solving guides
- [Homepage Customization](../homepage-customization.md) - Customize your homepage

---

[← Back to Documentation Home](../README.md)