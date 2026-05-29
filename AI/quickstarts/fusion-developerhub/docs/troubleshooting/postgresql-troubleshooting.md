# PostgreSQL Connection Troubleshooting Guide

This guide helps troubleshoot Backstage to PostgreSQL connection issues in the Fusion Developer Hub deployment.

## Recent Fixes Applied

### 1. Missing SESSION_SECRET Environment Variable
**Issue**: The `app-config.yaml` referenced `${SESSION_SECRET}` but it wasn't passed to the Backstage container.

**Fix**: Added SESSION_SECRET environment variable to the deployment:
```yaml
- name: SESSION_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "rhdh-fusion.fullname" . }}-auth
      key: session-secret
```

### 2. SSL Connection Configuration
**Issue**: PostgreSQL connections may require SSL configuration, even for internal cluster connections.

**Fix**: Added SSL configuration to the database connection:
```yaml
ssl:
  rejectUnauthorized: false
```

## Verification Steps

### 1. Check PostgreSQL Pod Status
```bash
kubectl get pods -l app.kubernetes.io/component=postgresql -n <namespace>
```

Expected output: Pod should be in `Running` state with `1/1` ready.

### 2. Check PostgreSQL Service
```bash
kubectl get svc -l app.kubernetes.io/component=postgresql -n <namespace>
```

Expected output: Service should exist with ClusterIP and port 5432.

### 3. Verify PostgreSQL Secret
```bash
kubectl get secret <release-name>-rhdh-fusion-postgresql -n <namespace> -o yaml
```

Should contain:
- POSTGRESQL_USER
- POSTGRESQL_PASSWORD
- POSTGRESQL_DATABASE
- POSTGRESQL_ADMIN_PASSWORD

### 4. Check Backstage Pod Logs
```bash
kubectl logs -l app.kubernetes.io/name=rhdh-fusion -n <namespace> --tail=100
```

Look for:
- Database connection errors
- Authentication failures
- SSL/TLS errors

### 5. Test Database Connection from Backstage Pod
```bash
# Get the Backstage pod name
BACKSTAGE_POD=$(kubectl get pods -l app.kubernetes.io/name=rhdh-fusion -n <namespace> -o jsonpath='{.items[0].metadata.name}')

# Test connection using environment variables
kubectl exec -it $BACKSTAGE_POD -n <namespace> -- bash -c '
  echo "Testing PostgreSQL connection..."
  echo "Host: $POSTGRES_HOST"
  echo "Port: $POSTGRES_PORT"
  echo "User: $POSTGRES_USER"
  echo "Database: backstage"
'
```

### 6. Direct PostgreSQL Connection Test
```bash
# Get PostgreSQL pod name
PG_POD=$(kubectl get pods -l app.kubernetes.io/component=postgresql -n <namespace> -o jsonpath='{.items[0].metadata.name}')

# Connect to PostgreSQL
kubectl exec -it $PG_POD -n <namespace> -- bash -c '
  psql -U $POSTGRESQL_USER -d $POSTGRESQL_DATABASE -c "\l"
'
```

## Common Issues and Solutions

### Issue 1: "Connection refused" or "Could not connect to server"

**Possible Causes**:
- PostgreSQL pod not running
- Service not created
- Wrong service name

**Solutions**:
```bash
# Check if PostgreSQL is running
kubectl get pods -l app.kubernetes.io/component=postgresql -n <namespace>

# Check service
kubectl get svc -l app.kubernetes.io/component=postgresql -n <namespace>

# Verify the service name matches the helper template
# Should be: <release-name>-rhdh-fusion-postgresql
```

### Issue 2: "Authentication failed for user"

**Possible Causes**:
- Wrong credentials in secret
- Secret not mounted correctly
- Environment variables not set

**Solutions**:
```bash
# Check secret exists and has correct keys
kubectl get secret <release-name>-rhdh-fusion-postgresql -n <namespace> -o jsonpath='{.data}' | jq

# Verify environment variables in Backstage pod
kubectl exec <backstage-pod> -n <namespace> -- env | grep POSTGRES
```

### Issue 3: "SSL connection required"

**Possible Causes**:
- PostgreSQL requires SSL but Backstage not configured
- SSL certificate issues

**Solutions**:
The fix has been applied to set `ssl.rejectUnauthorized: false` in the connection config.

If you need proper SSL:
```yaml
backend:
  database:
    connection:
      ssl:
        ca: ${POSTGRES_CA_CERT}
        rejectUnauthorized: true
```

### Issue 4: "Database does not exist"

**Possible Causes**:
- Database not created during PostgreSQL initialization
- Wrong database name in configuration

**Solutions**:
```bash
# Check if database exists
kubectl exec <pg-pod> -n <namespace> -- psql -U postgres -c "\l"

# Create database if missing
kubectl exec <pg-pod> -n <namespace> -- psql -U postgres -c "CREATE DATABASE backstage;"
```

### Issue 5: "Connection timeout"

**Possible Causes**:
- Network policies blocking traffic
- PostgreSQL not ready
- DNS resolution issues

**Solutions**:
```bash
# Check network policies
kubectl get networkpolicies -n <namespace>

# Test DNS resolution from Backstage pod
kubectl exec <backstage-pod> -n <namespace> -- nslookup <release-name>-rhdh-fusion-postgresql

# Check PostgreSQL readiness
kubectl get pods -l app.kubernetes.io/component=postgresql -n <namespace> -o wide
```

## Configuration Checklist

- [ ] PostgreSQL pod is running and ready
- [ ] PostgreSQL service exists and is accessible
- [ ] PostgreSQL secret contains all required credentials
- [ ] Backstage deployment has POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_PASSWORD env vars
- [ ] Backstage deployment has SESSION_SECRET env var
- [ ] Database name matches in both PostgreSQL and Backstage config
- [ ] SSL configuration is set (rejectUnauthorized: false for internal connections)
- [ ] Network policies allow traffic between Backstage and PostgreSQL

## Advanced Debugging

### Enable PostgreSQL Query Logging
Add to PostgreSQL extraEnvVars in values.yaml:
```yaml
postgresql:
  extraEnvVars:
    - name: POSTGRESQL_LOG_STATEMENT
      value: "all"
    - name: POSTGRESQL_LOG_CONNECTIONS
      value: "on"
```

### Enable Backstage Debug Logging
Add to Backstage environment:
```yaml
- name: LOG_LEVEL
  value: debug
```

### Port Forward for Direct Testing
```bash
# Port forward PostgreSQL
kubectl port-forward svc/<release-name>-rhdh-fusion-postgresql 5432:5432 -n <namespace>

# Connect with psql from local machine
psql -h localhost -p 5432 -U backstage -d backstage
```

## Helm Upgrade Command

After making configuration changes, upgrade the deployment:
```bash
helm upgrade <release-name> ./helm-charts/rhdh-fusion \
  -n <namespace> \
  -f your-values.yaml \
  --wait \
  --timeout 10m
```

## Quick Fix Script

```bash
#!/bin/bash
NAMESPACE="your-namespace"
RELEASE="your-release"

echo "=== PostgreSQL Status ==="
kubectl get pods -l app.kubernetes.io/component=postgresql -n $NAMESPACE

echo -e "\n=== PostgreSQL Service ==="
kubectl get svc -l app.kubernetes.io/component=postgresql -n $NAMESPACE

echo -e "\n=== Backstage Status ==="
kubectl get pods -l app.kubernetes.io/name=rhdh-fusion -n $NAMESPACE

echo -e "\n=== Backstage Logs (last 20 lines) ==="
kubectl logs -l app.kubernetes.io/name=rhdh-fusion -n $NAMESPACE --tail=20

echo -e "\n=== Environment Variables Check ==="
BACKSTAGE_POD=$(kubectl get pods -l app.kubernetes.io/name=rhdh-fusion -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
kubectl exec $BACKSTAGE_POD -n $NAMESPACE -- env | grep -E "(POSTGRES|SESSION)"
```

## Contact and Support

If issues persist after following this guide:
1. Check the Backstage logs for specific error messages
2. Verify all secrets are correctly populated
3. Ensure network connectivity between pods
4. Review the values.yaml configuration

For more information, see:
- [PostgreSQL Migration Guide](./postgresql-migration.md)
- [Crunchy PostgreSQL Documentation](./crunchy-postgresql.md)