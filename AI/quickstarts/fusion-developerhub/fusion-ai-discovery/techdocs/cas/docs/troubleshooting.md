# CAS Troubleshooting

## MCP Returns Error or Timeout

**Check**:
1. Verify CAS pods: `oc get pods -n ibm-cas -l app.kubernetes.io/name=cas.isf.ibm.com`
2. Verify console Route: `oc get route -n ibm-cas`
3. Check proxy target matches the console route hostname exactly (no trailing slash on target URL)

## MCP Streamable Returns 404

**Cause**: Missing trailing slash on the path.

**Fix**: Path must end with `/`:
```
POST /cas/api/v1/mcp-streamable/    ✅
POST /cas/api/v1/mcp-streamable     ❌
```

## Swagger UI Not Loading via Proxy

**Check**:
1. Proxy entry for `/fusion-<id>-cas` target matches the CAS console Route hostname
2. `changeOrigin: true` is set
3. Try direct URL first to confirm CAS is running

## Kubernetes Tab Empty

**Check**:
1. `backstage.io/kubernetes-cluster` annotation matches `name:` in `app-config.yaml`
2. SA token is valid and has the correct RBAC permissions
3. `backstage.io/kubernetes-namespace` is `ibm-cas`
4. Pod label selector `app.kubernetes.io/name=cas.isf.ibm.com` is correct

## IBM Documentation

- [CAS APIs — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-content-aware-storage-apis)
