# Homepage Customization 404 Fix Guide

## Problem Description

When deploying Developer Hub, you may encounter:
- 404 errors on the homepage (/)
- Homepage not loading or showing blank page
- "Page Not Found" error when accessing the root URL

## Root Cause

Red Hat Developer Hub (RHDH) requires the `@backstage/plugin-home` dynamic plugin to be enabled for the homepage to work. By default, RHDH may not have this plugin enabled, causing 404 errors when accessing the root URL.

## Solution

The fix involves enabling the home plugin through RHDH's dynamic plugins configuration.

### What Was Fixed

1. **Added Dynamic Plugins ConfigMap** - Enables the `@backstage/plugin-home` plugin
2. **Removed incorrect app-config approach** - Homepage customization in RHDH uses dynamic plugins, not app-config
3. **Simplified configuration** - Homepage now works out-of-the-box

**Important:** The homepage configuration in values.yaml is for future customization. The basic homepage functionality is now enabled by default through the dynamic plugins system.

## Solution

### Step 1: Update Your Deployment

Upgrade your deployment to enable the home plugin:

```bash
# Upgrade existing installation
helm upgrade fusion-hub ./helm-charts/fusion-developer-hub \
  -n fusion-hub \
  -f your-values.yaml \
  --set global.wildcardDomain=apps.your-cluster.com
```

### Step 2: Verify Dynamic Plugins ConfigMap

Check that the dynamic plugins ConfigMap was created:

```bash
# Check if dynamic plugins ConfigMap exists
kubectl get configmap developerhub-dynamic-plugins -n fusion-hub

# View the dynamic plugins configuration
kubectl get configmap developerhub-dynamic-plugins -n fusion-hub -o yaml
```

Expected output:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: developerhub-dynamic-plugins
data:
  dynamic-plugins.yaml: |
    includes:
      - dynamic-plugins.default.yaml
    plugins:
      - package: '@backstage/plugin-home@^1.0.0'
        disabled: false
```

### Step 3: Force Pod Restart

After updating the ConfigMap, restart the Developer Hub pods:

```bash
# Get the Backstage instance name
kubectl get backstage -n fusion-hub

# Restart the deployment
kubectl rollout restart deployment/developer-hub -n fusion-hub

# Wait for pods to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=backstage \
  -n fusion-hub \
  --timeout=300s
```

### Step 4: Clear Browser Cache

After pods restart:
1. Clear your browser cache (Ctrl+Shift+Delete or Cmd+Shift+Delete)
2. Do a hard refresh (Ctrl+F5 or Cmd+Shift+R)
3. Or open in incognito/private mode

### Step 5: Verify Homepage

Visit your Developer Hub URL and verify:
- ✅ Welcome message displays correctly
- ✅ Quick links are visible and functional
- ✅ Featured content sections appear
- ✅ No 404 errors on custom pages

## Common Issues and Fixes

### Issue 1: ConfigMap Not Updated

**Symptom:** Old configuration still showing after upgrade

**Fix:**
```bash
# Manually delete the ConfigMap to force recreation
kubectl delete configmap developerhub-app-config -n fusion-hub

# Upgrade again
helm upgrade fusion-hub ./helm-charts/fusion-developer-hub \
  -n fusion-hub \
  -f examples/operator-fusion-homepage-customized.yaml
```

### Issue 2: Pods Not Restarting

**Symptom:** Changes not appearing even after upgrade

**Fix:**
```bash
# Delete pods to force restart
kubectl delete pods -l app.kubernetes.io/name=backstage -n fusion-hub

# Or scale down and up
kubectl scale deployment developer-hub -n fusion-hub --replicas=0
kubectl scale deployment developer-hub -n fusion-hub --replicas=2
```

### Issue 3: Links Still Return 404

**Symptom:** Custom links work but return 404

**Cause:** Links point to pages that don't exist in your Backstage instance

**Fix:**
Update your values file to use valid URLs:

```yaml
homepage:
  quickLinks:
    # Use relative URLs for internal pages
    - title: "Create Application"
      url: "/create"  # ✅ Correct - built-in page
    
    # Don't link to non-existent pages
    - title: "AI Assistant"
      url: "/ai-assistant"  # ❌ May not exist
    
    # Use external URLs for external resources
    - title: "Documentation"
      url: "https://docs.example.com"  # ✅ Correct for external
```

### Issue 4: Welcome Message Not Showing

**Symptom:** Homepage loads but welcome message is blank

**Fix:**
Check the ConfigMap for proper YAML formatting:

```bash
# Extract and validate the app-config
kubectl get configmap developerhub-app-config -n fusion-hub \
  -o jsonpath='{.data.app-config\.yaml}' > /tmp/app-config.yaml

# Check for YAML syntax errors
python3 -c "import yaml; yaml.safe_load(open('/tmp/app-config.yaml'))"
```

If there are YAML errors, fix your values file and redeploy.

## Verification Checklist

After applying the fix, verify:

- [ ] ConfigMap contains `home:` section (not `homepage:`)
- [ ] Pods have restarted and are running
- [ ] Browser cache is cleared
- [ ] Welcome message displays on homepage
- [ ] Quick links are visible
- [ ] Quick links navigate correctly (no 404s)
- [ ] Featured content sections appear
- [ ] Company logo displays (if configured)

## Testing Commands

```bash
# 1. Check ConfigMap structure
kubectl get configmap developerhub-app-config -n fusion-hub -o yaml | grep -A 5 "home:"

# 2. Check pod status
kubectl get pods -n fusion-hub -l app.kubernetes.io/name=backstage

# 3. Check pod logs for errors
kubectl logs -n fusion-hub -l app.kubernetes.io/name=backstage --tail=50

# 4. Get Developer Hub URL
kubectl get route -n fusion-hub -o jsonpath='{.items[0].spec.host}'

# 5. Test homepage endpoint
DEVHUB_URL=$(kubectl get route -n fusion-hub -o jsonpath='{.items[0].spec.host}')
curl -k https://$DEVHUB_URL/ -I
```

## Prevention

To avoid this issue in future deployments:

1. **Always use the latest chart version** with the fix
2. **Test in a dev environment first** before production
3. **Use the provided examples** as templates
4. **Validate your values file** before deployment:
   ```bash
   helm template fusion-hub ./helm-charts/fusion-developer-hub \
     -f your-values.yaml \
     --debug > /tmp/rendered.yaml
   
   # Check for 'home:' in the output
   grep -A 10 "home:" /tmp/rendered.yaml
   ```

## Related Documentation

- [Homepage Customization Guide](../homepage-customization.md)
- [IBM Fusion Homepage Setup](../IBM-FUSION-HOMEPAGE-SETUP.md)
- [Deployment Guide](../getting-started/operator-getting-started.md)
- [General Troubleshooting](./README.md)

## Still Having Issues?

If the problem persists after following this guide:

1. **Check Backstage logs:**
   ```bash
   kubectl logs -n fusion-hub -l app.kubernetes.io/name=backstage --tail=100
   ```

2. **Verify Backstage CRD version:**
   ```bash
   kubectl get crd backstages.rhdh.redhat.com -o yaml | grep version
   ```

3. **Check operator status:**
   ```bash
   kubectl get csv -n rhdh-operator
   kubectl logs -n rhdh-operator -l app=rhdh-operator
   ```

4. **Review the complete configuration:**
   ```bash
   kubectl get backstage developer-hub -n fusion-hub -o yaml
   ```

## Support

For additional help:
- Review [Backstage documentation](https://backstage.io/docs/features/software-catalog/descriptor-format)
- Check [Red Hat Developer Hub documentation](https://access.redhat.com/documentation/en-us/red_hat_developer_hub)
- Contact your platform team