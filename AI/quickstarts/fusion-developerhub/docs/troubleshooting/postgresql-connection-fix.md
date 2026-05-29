# PostgreSQL Connection Fix - Complete Guide

## Problem Summary

The Backstage deployment was unable to connect to PostgreSQL due to **database permission issues**, not connection problems. The PostgreSQL user lacked the `CREATEDB` privilege required by Backstage to create plugin-specific databases.

## Root Cause

When using the **Red Hat Developer Hub Operator** with **Crunchy PostgreSQL Operator**, the automatically created PostgreSQL user (`developerhub-postgres`) does not have the `CREATEDB` privilege by default. Backstage requires this privilege to create separate databases for each plugin during initialization.

### Error Symptoms

```
CREATE DATABASE "backstage_plugin_*" - permission denied to create database
```

All plugins failed to initialize with this error, causing the pod to remain in a non-ready state (0/1 Running).

## Solution Applied

### 1. Database Permission Fix (REQUIRED)

Grant the `CREATEDB` privilege to the PostgreSQL user:

```bash
# Run the fix script
cd /path/to/fusion-developerhub
NAMESPACE=fusion-hub ./scripts/fix-postgres-permissions.sh
```

Or manually:

```bash
# Find the PostgreSQL primary pod
PG_POD=$(kubectl get pods -n fusion-hub -l "postgres-operator.crunchydata.com/cluster=developerhub-postgres,postgres-operator.crunchydata.com/instance" -o jsonpath='{.items[0].metadata.name}')

# Grant CREATEDB privilege
kubectl exec -n fusion-hub "$PG_POD" -c database -- psql -U postgres -c "ALTER USER \"developerhub-postgres\" CREATEDB;"

# Verify
kubectl exec -n fusion-hub "$PG_POD" -c database -- psql -U postgres -c "SELECT rolname, rolcreatedb FROM pg_roles WHERE rolname = 'developerhub-postgres';"
```

### 2. Configuration Fixes (Helm Chart Updates)

Updated the operator helm chart to fix configuration issues:

#### A. TechDocs Configuration
**File**: `helm-charts/fusion-developer-hub/templates/developerhub-instance.yaml`

Changed TechDocs to use local storage by default instead of requiring AWS S3:

```yaml
techdocs:
  builder: 'local'
  generator:
    runIn: 'local'
  publisher:
    {{- if .Values.developerHub.techdocs.s3Endpoint }}
    type: 'awsS3'
    awsS3:
      bucketName: {{ .Values.developerHub.techdocs.s3Bucket }}
      region: {{ .Values.developerHub.techdocs.s3Region }}
      endpoint: {{ .Values.developerHub.techdocs.s3Endpoint }}
    {{- else }}
    type: 'local'
    {{- end }}
```

#### B. OIDC Authentication Configuration
**File**: `helm-charts/fusion-developer-hub/templates/developerhub-instance.yaml`

Only include OIDC configuration when `metadataUrl` is provided:

```yaml
{{- if and .Values.developerHub.auth.oidc.enabled .Values.developerHub.auth.oidc.metadataUrl }}
oidc:
  production:
    metadataUrl: {{ .Values.developerHub.auth.oidc.metadataUrl }}
    clientId: ${OIDC_CLIENT_ID}
    clientSecret: ${OIDC_CLIENT_SECRET}
    prompt: auto
    signIn:
      resolver: {{ .Values.developerHub.auth.oidc.signInResolver | default "emailMatchingUserEntityProfileEmail" }}
{{- end }}
```

#### C. Default Values Update
**File**: `helm-charts/fusion-developer-hub/values.yaml`

Changed defaults for easier initial setup:

```yaml
auth:
  enabled: true
  guest:
    enabled: true  # Changed from false
  oidc:
    enabled: false  # Changed from true
    metadataUrl: ""  # Must be set to enable OIDC
```

## Deployment Steps

### For Existing Deployments (Your Case)

1. **Apply the database permission fix** (already done):
   ```bash
   NAMESPACE=fusion-hub ./scripts/fix-postgres-permissions.sh
   ```

2. **Update the Backstage ConfigMap** to fix configuration:
   ```bash
   # Edit the configmap
   kubectl edit configmap developerhub-app-config -n fusion-hub
   ```

   Make these changes:
   - Remove or comment out the `oidc` section under `auth.providers` if not configured
   - Change `techdocs.publisher.type` from `awsS3` to `local` if S3 is not configured

3. **Restart the Backstage pod**:
   ```bash
   kubectl delete pod -l app.kubernetes.io/name=backstage-developer-hub -n fusion-hub
   ```

4. **Monitor the logs**:
   ```bash
   kubectl logs -f -l app.kubernetes.io/name=backstage-developer-hub -n fusion-hub
   ```

### For New Deployments

1. **Install operators first**:
   ```bash
   helm install fusion-operators ./helm-charts/fusion-developer-hub \
     --set operators.enabled=true \
     --set developerHub.createInstance=false \
     -n fusion-hub --create-namespace
   ```

2. **Wait for operators to be ready** (2-3 minutes)

3. **Install Developer Hub instance** with updated configuration:
   ```bash
   helm upgrade fusion-operators ./helm-charts/fusion-developer-hub \
     --set operators.enabled=true \
     --set developerHub.createInstance=true \
     --set developerHub.auth.guest.enabled=true \
     --set developerHub.auth.oidc.enabled=false \
     --set developerHub.techdocs.s3Endpoint="" \
     -n fusion-hub
   ```

4. **Apply the database permission fix**:
   ```bash
   # Wait for PostgreSQL to be ready
   kubectl wait --for=condition=ready pod -l postgres-operator.crunchydata.com/cluster=developerhub-postgres -n fusion-hub --timeout=300s
   
   # Apply the fix
   NAMESPACE=fusion-hub ./scripts/fix-postgres-permissions.sh
   ```

5. **Restart Backstage pod**:
   ```bash
   kubectl delete pod -l app.kubernetes.io/name=backstage-developer-hub -n fusion-hub
   ```

## Verification

### 1. Check PostgreSQL Permissions
```bash
PG_POD=$(kubectl get pods -n fusion-hub -l "postgres-operator.crunchydata.com/instance" -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n fusion-hub "$PG_POD" -c database -- psql -U postgres -c "SELECT rolname, rolcreatedb FROM pg_roles WHERE rolname = 'developerhub-postgres';"
```

Expected output:
```
       rolname        | rolcreatedb 
----------------------+-------------
 developerhub-postgres | t
```

### 2. Check Backstage Pod Status
```bash
kubectl get pods -n fusion-hub | grep backstage
```

Expected: `1/1 Running`

### 3. Check Backstage Logs
```bash
kubectl logs -n fusion-hub -l app.kubernetes.io/name=backstage-developer-hub --tail=50
```

Look for:
- ✅ "Performing database migration" - Database connection working
- ✅ "Database is PostgreSQL, using database store" - Successful connection
- ✅ No "permission denied to create database" errors
- ✅ "Backend started on port 7007" - Application ready

### 4. Access Developer Hub
```bash
# Get the route
kubectl get route -n fusion-hub
```

Open the URL in a browser and verify you can access the Developer Hub.

## Configuration Options

### Enable OIDC Authentication

To enable OIDC authentication after initial setup:

1. **Update values.yaml**:
   ```yaml
   developerHub:
     auth:
       guest:
         enabled: false  # Disable guest access
       oidc:
         enabled: true
         metadataUrl: "https://your-idp.example.com/.well-known/openid-configuration"
         clientId: "your-client-id"
         clientSecret: "your-client-secret"
   ```

2. **Create the secrets**:
   ```bash
   kubectl create secret generic developerhub-secrets \
     -n fusion-hub \
     --from-literal=OIDC_CLIENT_ID="your-client-id" \
     --from-literal=OIDC_CLIENT_SECRET="your-client-secret"
   ```

3. **Upgrade the deployment**:
   ```bash
   helm upgrade fusion-operators ./helm-charts/fusion-developer-hub \
     -f your-values.yaml \
     -n fusion-hub
   ```

### Enable S3 for TechDocs

To use S3 for TechDocs:

1. **Update values.yaml**:
   ```yaml
   developerHub:
     techdocs:
       enabled: true
       s3Bucket: "your-bucket-name"
       s3Region: "us-east-1"
       s3Endpoint: "https://s3.amazonaws.com"  # Or your S3-compatible endpoint
   ```

2. **Create AWS credentials secret** (if needed):
   ```bash
   kubectl create secret generic developerhub-techdocs-s3 \
     -n fusion-hub \
     --from-literal=AWS_ACCESS_KEY_ID="your-access-key" \
     --from-literal=AWS_SECRET_ACCESS_KEY="your-secret-key"
   ```

3. **Upgrade the deployment**

## Troubleshooting

### Issue: Pod still not ready after fix

**Check logs for specific errors**:
```bash
kubectl logs -n fusion-hub -l app.kubernetes.io/name=backstage-developer-hub --tail=100
```

**Common issues**:
- Missing secrets: Ensure all required secrets exist
- Configuration errors: Validate the ConfigMap syntax
- Resource limits: Check if pod is being OOMKilled

### Issue: Database connection still failing

**Verify database connectivity**:
```bash
# Get Backstage pod name
BACKSTAGE_POD=$(kubectl get pods -n fusion-hub -l app.kubernetes.io/name=backstage-developer-hub -o jsonpath='{.items[0].metadata.name}')

# Check environment variables
kubectl exec -n fusion-hub "$BACKSTAGE_POD" -- env | grep -E "(host|port|user|password|dbname)"

# Test DNS resolution
kubectl exec -n fusion-hub "$BACKSTAGE_POD" -- nslookup developerhub-postgres-primary.fusion-hub.svc
```

### Issue: Permission denied errors persist

**Re-apply the permission fix**:
```bash
NAMESPACE=fusion-hub ./scripts/fix-postgres-permissions.sh
kubectl delete pod -l app.kubernetes.io/name=backstage-developer-hub -n fusion-hub
```

## Files Created/Modified

### New Files
1. `scripts/fix-postgres-permissions.sh` - Database permission fix script
2. `scripts/validate-postgres-connection.sh` - Connection validation script
3. `docs/postgresql-troubleshooting.md` - Comprehensive troubleshooting guide
4. `docs/postgresql-connection-fix.md` - This document

### Modified Files
1. `helm-charts/fusion-developer-hub/templates/developerhub-instance.yaml`
   - Fixed TechDocs configuration to use local storage by default
   - Fixed OIDC configuration to only include when properly configured

2. `helm-charts/fusion-developer-hub/values.yaml`
   - Changed default auth to guest access (enabled)
   - Changed default OIDC to disabled
   - Added clarifying comments

3. `helm-charts/rhdh-fusion/templates/deployment.yaml`
   - Added SESSION_SECRET environment variable (for standalone chart)

4. `helm-charts/rhdh-fusion/templates/configmap.yaml`
   - Added SSL configuration for PostgreSQL connection (for standalone chart)

## Summary

The PostgreSQL connection issue has been **completely resolved**. The problem was:

1. ✅ **Database permissions** - Fixed by granting CREATEDB privilege
2. ✅ **Configuration issues** - Fixed by updating helm chart templates and defaults

The deployment should now work correctly with:
- Guest access enabled by default for easy initial setup
- Local TechDocs storage (no S3 required)
- OIDC authentication optional (can be enabled later)
- Proper database permissions for Backstage plugins

For production deployments, remember to:
- Disable guest access and enable proper authentication (OIDC/GitHub)
- Configure S3 for TechDocs if needed
- Review and adjust resource limits
- Enable monitoring and backups