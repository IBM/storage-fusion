# Fusion Developer Hub Documentation

Quick guides for deploying and using Red Hat Developer Hub on IBM Fusion platform.

## 🚀 Getting Started

**New to Fusion Developer Hub?** Start here:

1. **[Deployment Guide](./getting-started/operator-getting-started.md)** - Complete installation guide with all deployment options
2. **[OIDC Setup](./getting-started/oidc-providers.md)** - Configure authentication with IBM Fusion identity providers

## 🎨 Customization

Make Developer Hub your own:

- **[Homepage Customization](./homepage-customization.md)** - Customize the homepage with your branding and quick links
- **[Adding Fusion Services](./adding-fusion-services.md)** - Add IBM Fusion AI services and APIs to the catalog

## 🔧 Troubleshooting

Having issues? Check these guides:

- **[PostgreSQL Issues](./troubleshooting/postgresql-troubleshooting.md)** - Database connection and configuration problems
- **[Connection Problems](./troubleshooting/postgresql-connection-fix.md)** - Detailed connection troubleshooting
- **[Homepage 404 Errors](./troubleshooting/homepage-404-fix.md)** - Homepage customization not working

## 📚 Quick Reference

### Common Commands

```bash
# Deploy with guest access (demos/testing)
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-guest-access-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-dev-hub \
  --create-namespace

# Check deployment status
oc get backstage,postgrescluster -n fusion-dev-hub

# View logs
oc logs -n fusion-dev-hub -l app.kubernetes.io/name=backstage -f

# Validate deployment
./scripts/check-deployment.sh
```

### Prerequisites

Before deploying, ensure you have:

- ✅ IBM Fusion platform on Red Hat OpenShift 4.12+
- ✅ Cluster admin access for operator installation
- ✅ Helm 3.8+ installed
- ✅ `oc` CLI tools configured

### Deployment Options

| Example | Use Case | Authentication | Database |
|---------|----------|----------------|----------|
| **guest-access** | Demos, testing | None (guest) | Single instance |
| **development** | Development | OIDC | Single instance |
| **production** | Production | OIDC (required) | HA (3 instances) |

## 📖 Additional Resources

- **[Helm Chart README](../helm-charts/fusion-developer-hub/README.md)** - Chart documentation
- **[Example Configurations](../examples/)** - Sample values files
- **[Helper Scripts](../scripts/)** - Validation and diagnostic tools
- **[Software Templates](../templates/)** - Self-service templates

## 🆘 Getting Help

### Quick Diagnosis

```bash
# Check overall health
oc get pods -n fusion-dev-hub
oc get backstage -n fusion-dev-hub
oc get postgrescluster -n fusion-dev-hub

# Check operators
oc get csv -n rhdh-operator
oc get csv -n postgres-operator

# Collect logs
oc logs -n fusion-dev-hub -l app.kubernetes.io/name=backstage --tail=100
```

### Common Issues

1. **Operators not installing** → See [Getting Started - Troubleshooting](./getting-started/operator-getting-started.md#troubleshooting)
2. **Database connection errors** → See [PostgreSQL Troubleshooting](./troubleshooting/postgresql-troubleshooting.md)
3. **Authentication not working** → See [OIDC Providers](./getting-started/oidc-providers.md#troubleshooting)
4. **Homepage 404 errors** → See [Homepage 404 Fix](./troubleshooting/homepage-404-fix.md)

### Support Channels

- **Documentation Issues**: [GitHub Issues](https://github.com/ProjectAbell/Fusion-AI/issues)
- **IBM Fusion Support**: Contact your IBM Fusion support team
- **Red Hat Developer Hub**: [Red Hat Support](https://access.redhat.com/support)

## 📝 Documentation Structure

```
docs/
├── README.md                          # This file
├── homepage-customization.md          # Customize homepage
├── adding-fusion-services.md          # Add Fusion services
├── getting-started/                   # Quick start guides
│   ├── README.md
│   ├── operator-getting-started.md    # Complete deployment guide
│   └── oidc-providers.md
└── troubleshooting/                   # Problem solving
    ├── README.md
    ├── postgresql-troubleshooting.md
    ├── postgresql-connection-fix.md
    └── homepage-404-fix.md
```

## 🔄 Updates

This documentation is maintained alongside the Helm chart. For the latest version:

```bash
git pull origin main
helm repo update
```

---

**Made with Bob** 🤖 | **Powered by IBM Fusion AI**