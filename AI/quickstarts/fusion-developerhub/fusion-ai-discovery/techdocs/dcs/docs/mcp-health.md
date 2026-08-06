# DCS MCP Server Health Check

## Quick Health Check

Copy the MCP HTTP endpoint from the catalog entry for your cluster (Links tab),
then run:

```bash
curl -s -X POST \
  https://dcs-mcp-route-ibm-data-cataloging.apps.<domain>/mcp/http \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | python3 -m json.tool
```

Replace `<domain>` with your cluster's OCP apps domain.

## Interpreting Results

| Status | Meaning |
|---|---|
| HTTP 200 + `tools` array | ✅ MCP server healthy |
| HTTP 401/403 | Authentication required — check `x-auth-token` |
| HTTP 502/503 | Proxy misconfigured or DCS pods not running |
| Connection timeout | Proxy target URL incorrect or DCS Route unreachable |

## IBM Documentation

- [Is Your MCP Server Healthy?](https://community.ibm.com/community/user/blogs/paul-llamas-virgen/2026/03/06/is-your-mcp-server-healthy-to-explore-your-catalog)
