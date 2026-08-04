# DCS Troubleshooting

## MCP Server Not Responding

**Symptom**: MCP health check returns non-200 or timeout.

**Check**:
1. Verify DCS pods are running: `oc get pods -n ibm-data-cataloging -l app=isd`
2. Verify MCP Route exists: `oc get route dcs-mcp-route -n ibm-data-cataloging`
3. Check proxy config: `/fusion-<id>-dcs-mcp` target matches the MCP Route hostname

## Kubernetes Tab Shows No Resources

**Symptom**: K8s tab in catalog is empty or shows errors.

**Check**:
1. SA token is valid: `oc whoami --token=<sa-token> --server=<api-url>`
2. `backstage.io/kubernetes-cluster` annotation matches `name:` in `app-config.yaml`
3. `backstage.io/kubernetes-namespace` is set to `ibm-data-cataloging`
4. SA has `get/list/watch` on pods, deployments, routes, CRDs

## Catalog Entity Not Appearing

**Check**:
1. `clusters/<id>/catalog-info.yaml` path is listed in `catalog/locations.yaml`
2. `GIT_CATALOG_ROOT_URL` in app-config points to the correct `locations.yaml`
3. All YAML is valid (no tabs, correct indentation)
4. Force refresh: Developer Hub → Catalog entity → three-dot menu → Refresh

## Proxy Returns 502/503

**Check**:
1. Target URL in proxy config is reachable from RHDH pod
2. `secure: false` is set if the cluster uses self-signed TLS
3. `changeOrigin: true` is set
