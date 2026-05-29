# Red Hat OpenShift AI (RHOAI) Integration

This guide explains how to integrate Red Hat Developer Hub with Red Hat OpenShift AI (RHOAI) to automatically discover and display deployed AI models.

## Overview

The RHOAI connector enables Developer Hub to:
- Automatically discover InferenceServices deployed in OpenShift AI
- Display model information in the Developer Hub catalog
- Provide quick access to model endpoints and documentation
- Track model deployment status and health

## Prerequisites

1. Red Hat OpenShift AI installed and configured
2. AI models deployed as InferenceServices
3. Service account with appropriate RBAC permissions (automatically configured)

## Configuration

### Basic Setup

Enable the RHOAI connector in your `values.yaml`:

```yaml
developerHub:
  fusion:
    ai:
      rhoaiConnector:
        enabled: true
        tokenSecretName: "rhdh-rhoai-connector-token"
        rbac:
          create: true  # Automatically creates required RBAC
          watchNamespaces: []  # Watch all namespaces
```

### RBAC Permissions

When `rbac.create: true`, the chart automatically creates:

1. **ClusterRole** (`rhoai-connector-reader`) with permissions to:
   - Read CustomResourceDefinitions (CRDs)
   - Read InferenceServices across namespaces
   - List and watch model deployments

2. **ClusterRoleBinding** that grants the ClusterRole to the Developer Hub service account

3. **ServiceAccount** (optional) - if `serviceAccount.create: true`

#### Required Permissions

The RHOAI connector needs cluster-level permissions because:
- CRDs are cluster-scoped resources
- InferenceServices may be deployed across multiple namespaces
- Model discovery requires cross-namespace visibility

#### Namespace-Scoped Watching

To limit the connector to specific namespaces:

```yaml
developerHub:
  fusion:
    ai:
      rhoaiConnector:
        enabled: true
        rbac:
          create: true
          watchNamespaces:
            - rhoai-models
            - ai-workloads
            - production-models
```

**Note**: Even with namespace restrictions, the connector still needs cluster-level CRD read permissions.

### Manual RBAC Configuration

If you prefer to manage RBAC manually, set `rbac.create: false`:

```yaml
developerHub:
  serviceAccount:
    create: true
    name: rhoai-connector-sa
  fusion:
    ai:
      rhoaiConnector:
        enabled: true
        rbac:
          create: false  # Manage RBAC manually
```

Then create the RBAC resources manually:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: rhoai-connector-reader
rules:
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list"]
  - apiGroups: ["serving.kserve.io"]
    resources: ["inferenceservices"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rhoai-connector-reader-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: rhoai-connector-reader
subjects:
  - kind: ServiceAccount
    name: rhoai-connector-sa
    namespace: fusion-dev-hub
```

## Authentication Token

Create a secret with the RHOAI access token:

```bash
# Create the token secret
kubectl create secret generic rhdh-rhoai-connector-token \
  --from-literal=token=YOUR_RHOAI_TOKEN \
  --namespace fusion-dev-hub
```

To obtain the token:

1. Log in to OpenShift AI
2. Navigate to Settings → Access Tokens
3. Create a new token with read permissions
4. Copy the token value

## Deployment

Deploy with RHOAI connector enabled:

```bash
helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \
  -f examples/operator-fusion-guest-access-values.yaml \
  --set global.wildcardDomain=apps.cluster.example.com \
  --set developerHub.fusion.ai.rhoaiConnector.enabled=true \
  --namespace fusion-dev-hub
```

## Verification

### Check RBAC Resources

```bash
# Verify ClusterRole
kubectl get clusterrole rhoai-connector-reader

# Verify ClusterRoleBinding
kubectl get clusterrolebinding rhoai-connector-reader-binding

# Check service account permissions
kubectl auth can-i get customresourcedefinitions \
  --as=system:serviceaccount:fusion-dev-hub:default
```

### Check Connector Status

```bash
# View connector logs
kubectl logs -n fusion-dev-hub \
  -l app.kubernetes.io/component=backstage \
  -c backstage-backend | grep -i rhoai

# Check for discovered models
kubectl logs -n fusion-dev-hub \
  -l app.kubernetes.io/component=backstage \
  -c backstage-backend | grep -i inferenceservice
```

### Expected Log Output

Successful connection:
```
[RHOAI Connector] Initializing RHOAI model discovery
[RHOAI Connector] Found 5 InferenceServices across 2 namespaces
[RHOAI Connector] Successfully registered models in catalog
```

Permission errors (if RBAC not configured):
```
[RHOAI Connector] Error: customresourcedefinitions.apiextensions.k8s.io is forbidden
[RHOAI Connector] User "system:serviceaccount:fusion-dev-hub:default" cannot get resource "customresourcedefinitions"
```

## Troubleshooting

### Permission Denied Errors

**Symptom**: Logs show "forbidden" or "cannot get resource" errors

**Solution**:
1. Verify RBAC resources exist:
   ```bash
   kubectl get clusterrole rhoai-connector-reader
   kubectl get clusterrolebinding rhoai-connector-reader-binding
   ```

2. Check if RBAC creation is enabled:
   ```bash
   helm get values fusion-hub -n fusion-dev-hub | grep -A 5 rbac
   ```

3. Manually verify permissions:
   ```bash
   kubectl auth can-i get customresourcedefinitions \
     --as=system:serviceaccount:fusion-dev-hub:default
   ```

### No Models Discovered

**Symptom**: Connector runs but finds no models

**Possible causes**:
1. No InferenceServices deployed in watched namespaces
2. Namespace restrictions too narrow
3. Token lacks read permissions

**Solution**:
1. List InferenceServices:
   ```bash
   kubectl get inferenceservices --all-namespaces
   ```

2. Check namespace configuration:
   ```yaml
   watchNamespaces: []  # Empty = all namespaces
   ```

3. Verify token permissions in RHOAI console

### Connector Not Starting

**Symptom**: No RHOAI connector logs appear

**Solution**:
1. Verify connector is enabled:
   ```bash
   helm get values fusion-hub -n fusion-dev-hub | grep -A 3 rhoaiConnector
   ```

2. Check token secret exists:
   ```bash
   kubectl get secret rhdh-rhoai-connector-token -n fusion-dev-hub
   ```

3. Restart Developer Hub pods:
   ```bash
   kubectl rollout restart deployment/developer-hub -n fusion-dev-hub
   ```

## Security Considerations

### Principle of Least Privilege

The RHOAI connector follows security best practices:

1. **Read-Only Access**: Only `get`, `list`, and `watch` verbs
2. **Specific Resources**: Limited to CRDs and InferenceServices
3. **No Write Permissions**: Cannot modify or delete resources
4. **Namespace Scoping**: Optional restriction to specific namespaces

### Token Management

Best practices for RHOAI tokens:

1. **Rotation**: Rotate tokens regularly (every 90 days)
2. **Scope**: Use tokens with minimal required permissions
3. **Storage**: Store tokens in Kubernetes secrets, never in values files
4. **Monitoring**: Monitor token usage and audit logs

### Network Policies

If using network policies, ensure Developer Hub can reach:
- OpenShift AI API server
- InferenceService endpoints (for health checks)

## Advanced Configuration

### Custom Service Account

Use a dedicated service account with custom annotations:

```yaml
developerHub:
  serviceAccount:
    create: true
    name: rhoai-connector
    annotations:
      description: "Service account for RHOAI model discovery"
  fusion:
    ai:
      rhoaiConnector:
        enabled: true
        rbac:
          create: true
```

### Multi-Cluster Setup

For multi-cluster RHOAI deployments:

1. Deploy Developer Hub in the hub cluster
2. Configure RHOAI connector for each spoke cluster
3. Use separate token secrets per cluster
4. Aggregate model information in the catalog

## Related Documentation

- [RHOAI Official Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai)
- [KServe InferenceService API](https://kserve.github.io/website/latest/reference/api/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Developer Hub Catalog](../reference/catalog-integration.md)

## Support

For issues with RHOAI integration:

1. Check the [Troubleshooting Guide](../troubleshooting/README.md)
2. Review connector logs for specific errors
3. Verify RBAC permissions are correctly configured
4. Ensure RHOAI is accessible from Developer Hub namespace