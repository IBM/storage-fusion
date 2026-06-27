# Troubleshooting Fusion Developer Hub

Common issues and solutions for Fusion Developer Hub deployments on IBM Fusion platform.

## 📚 Troubleshooting Guides

### [CRD Installation Fix](./crd-installation-fix.md) ⭐ **NEW**
**Single-command Helm installation with CRD handling**

Common problems:
- "CRDs are not installed" error during Helm install
- "no matches for kind Backstage" error
- "no matches for kind PostgresCluster" error
- Operators not ready before resource creation

**Start here if**: You're getting CRD-related errors during installation

---

### [PostgreSQL Troubleshooting](./postgresql-troubleshooting.md)
**Database connection and configuration issues**

Common problems:
- Connection failures
- Authentication errors
- Performance issues
- Backup failures
- Replication problems

**Start here if**: You're having database-related problems

---

### [PostgreSQL Connection Fix](./postgresql-connection-fix.md)
**Detailed connection troubleshooting**

Topics covered:
- Connection string validation
- Network connectivity testing
- SSL/TLS configuration
- Firewall and network policies
- DNS resolution issues

**Start here if**: Backstage can't connect to PostgreSQL

---

### [Homepage 404 Fix](./homepage-404-fix.md)
**Homepage customization not working**

Common issues:
- 404 errors on custom homepage pages
- Homepage customization not appearing
- Custom links returning "Page Not Found"
- Welcome message not displaying

**Start here if**: Your homepage customization isn't working

---

## 🔍 Quick Diagnosis

### Check Overall Health

```bash
# Check all pods
oc get pods -n fusion-dev-hub

# Check Backstage status
oc get backstage -n fusion-dev-hub

# Check PostgreSQL status
oc get postgrescluster -n fusion-dev-hub

# Check operators
oc get csv -n rhdh-operator
oc get csv -n postgres-operator
```

### View Logs

```bash
# Backstage logs
oc logs -n fusion-dev-hub -l app.kubernetes.io/name=backstage -f

# PostgreSQL logs
oc logs -n fusion-dev-hub -l postgres-operator.crunchydata.com/cluster=fusion-postgres -f

# Operator logs
oc logs -n rhdh-operator -l app.kubernetes.io/name=rhdh-operator -f
```

---

## ⚡ Common Issues & Quick Fixes

### 1. CRD Installation Error (NEW!)

**Symptom**: Helm install fails with "CRDs are not installed" or "no matches for kind Backstage/PostgresCluster"

**Quick Fix**:
The Helm chart now handles this automatically! Simply run:
```bash
helm install fusion-developer-hub \
  ./helm-charts/fusion-developer-hub \
  -n fusion-developer-hub \
  --create-namespace \
  -f examples/quickstart-production-values.yaml \
  --timeout 20m
```

The chart will:
1. Install operators first
2. Wait for CRDs to be created
3. Then create the instances

**Full Guide**: [CRD Installation Fix](./crd-installation-fix.md)

---

### 2. Homepage 404 or Customization Not Working

**Symptom**: Homepage customization not appearing, 404 errors on custom pages

**Quick Fix**:
```bash
# Check ConfigMap
oc get configmap developerhub-app-config -n fusion-dev-hub -o yaml | grep -A 10 "homepage:"

# Restart pods
oc rollout restart deployment -n fusion-dev-hub -l app.kubernetes.io/name=backstage

# Clear browser cache and refresh
```

**Full Guide**: [Homepage 404 Fix](./homepage-404-fix.md)

---

### 3. Database Connection Refused

**Symptom**: Backstage can't reach PostgreSQL

**Quick Fix**:
```bash
# Check PostgreSQL is running
oc get pods -n fusion-dev-hub -l postgres-operator.crunchydata.com/cluster

# Check service exists
oc get svc -n fusion-dev-hub | grep postgres

# Test connection
oc exec -n fusion-dev-hub <backstage-pod> -- nc -zv <postgres-service> 5432
```

**Full Guide**: [PostgreSQL Connection Fix](./postgresql-connection-fix.md)

---

### 4. Operators Not Installing

**Symptom**: Operators stuck in "Installing" state

**Quick Fix**:
```bash
# Check operator status
oc get csv -n rhdh-operator
oc get csv -n postgres-operator

# Check subscriptions
oc get subscription -n rhdh-operator
oc get subscription -n postgres-operator

# Check install plans
oc get installplan -n rhdh-operator
oc get installplan -n postgres-operator
```

**Full Guide**: [Operator Getting Started](../getting-started/operator-getting-started.md#troubleshooting)

---

### 5. Pods Stuck in Init or CrashLoopBackOff

**Symptom**: Pods not starting properly

**Quick Fix**:
```bash
# Check pod events
oc describe pod -n fusion-dev-hub <pod-name>

# Check init container logs
oc logs -n fusion-dev-hub <pod-name> -c <init-container-name>

# Check main container logs
oc logs -n fusion-dev-hub <pod-name>
```

---

### 6. Authentication Not Working

**Symptom**: Users can't log in with OIDC

**Quick Fix**:
```bash
# Check OIDC configuration
oc get configmap developerhub-app-config -n fusion-dev-hub -o yaml | grep -A 10 "oidc:"

# Check secrets exist
oc get secret -n fusion-dev-hub | grep oidc

# Check Backstage logs for auth errors
oc logs -n fusion-dev-hub -l app.kubernetes.io/name=backstage | grep -i auth
```

**Full Guide**: [OIDC Providers](../getting-started/oidc-providers.md#troubleshooting)

---

## 🛠️ Diagnostic Tools

### Helper Scripts

```bash
# Validate deployment
./scripts/check-deployment.sh

# Check homepage
./scripts/check-homepage.sh

# Diagnose pod issues
./scripts/diagnose-pods.sh

# Validate PostgreSQL connection
./scripts/validate-postgres-connection.sh
```

### Collect Diagnostic Information

```bash
# Get all resources
oc get all -n fusion-dev-hub

# Get custom resources
oc get backstage,postgrescluster -n fusion-dev-hub -o yaml

# Get recent events
oc get events -n fusion-dev-hub --sort-by='.lastTimestamp' | tail -20

# Get pod logs
oc logs -n fusion-dev-hub -l app.kubernetes.io/name=backstage --tail=100 > backstage.log
oc logs -n fusion-dev-hub -l postgres-operator.crunchydata.com/cluster --tail=100 > postgres.log
```

---

## 🔄 Recovery Procedures

### Restart Backstage

```bash
# Restart deployment
oc rollout restart deployment -n fusion-dev-hub -l app.kubernetes.io/name=backstage

# Watch rollout
oc rollout status deployment -n fusion-dev-hub -l app.kubernetes.io/name=backstage
```

### Restart PostgreSQL

```bash
# Delete pod (will be recreated by operator)
oc delete pod -n fusion-dev-hub <postgres-pod>

# Watch recovery
oc get pods -n fusion-dev-hub -w
```

### Reinstall Operators

```bash
# Delete and reinstall RHDH operator
oc delete subscription rhdh-operator -n rhdh-operator
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-production-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.example.com \
  --namespace fusion-hub
```

---

## 📊 Performance Issues

### Slow Database Queries

```bash
# Check PostgreSQL performance
oc exec -n fusion-dev-hub <postgres-pod> -c database -- \
  psql -U postgres -c "SELECT * FROM pg_stat_activity;"

# Check connection count
oc exec -n fusion-dev-hub <postgres-pod> -c database -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"
```

### High Memory Usage

```bash
# Check pod resource usage
oc top pods -n fusion-dev-hub

# Check resource limits
oc describe pod -n fusion-dev-hub <pod-name> | grep -A 5 "Limits:"
```

### Slow Catalog Sync

```bash
# Check catalog logs
oc logs -n fusion-dev-hub -l app.kubernetes.io/name=backstage | grep -i catalog

# Check for rate limiting
oc logs -n fusion-dev-hub -l app.kubernetes.io/name=backstage | grep -i "rate limit"
```

---

## 🆘 Getting Help

### Information to Collect

When reporting issues, gather:

1. **Environment**:
   ```bash
   oc version
   helm version
   ```

2. **Resource Status**:
   ```bash
   oc get backstage,postgrescluster -n fusion-dev-hub -o yaml
   ```

3. **Logs**:
   ```bash
   oc logs -n fusion-dev-hub -l app.kubernetes.io/name=backstage --tail=200
   oc logs -n fusion-dev-hub -l postgres-operator.crunchydata.com/cluster --tail=200
   ```

4. **Events**:
   ```bash
   oc get events -n fusion-dev-hub --sort-by='.lastTimestamp'
   ```

5. **Configuration**:
   ```bash
   helm get values fusion-hub -n fusion-dev-hub
   ```

### Support Channels

- **Documentation**: [Fusion Developer Hub Docs](../README.md)
- **GitHub Issues**: [Report Issues](https://github.com/ProjectAbell/Fusion-AI/issues)
- **IBM Fusion Support**: Contact your IBM Fusion support team
- **Red Hat Support**: [Red Hat Customer Portal](https://access.redhat.com/support)

---

## 📖 Related Documentation

- [Getting Started](../getting-started/) - Initial deployment guides
- [Deployment Guide](../DEPLOYMENT-GUIDE.md) - Complete deployment documentation
- [Homepage Customization](../homepage-customization.md) - Customize your homepage

---

[← Back to Documentation Home](../README.md)