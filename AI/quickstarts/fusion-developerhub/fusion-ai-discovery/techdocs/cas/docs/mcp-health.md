# CAS MCP Server Health Check

## Quick Health Check

Copy the MCP Standard endpoint from the catalog entry for your cluster (Links tab),
then run:

```bash
curl -s -X POST \
  https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | python3 -m json.tool
```

Replace `<domain>` with your cluster's OCP apps domain.

## Interpreting Results

| Status | Meaning |
|---|---|
| HTTP 200 + `tools` array | ✅ MCP server healthy |
| HTTP 401/403 | Authentication required — check auth token |
| HTTP 502/503 | Proxy misconfigured or CAS pods not running |
| Connection timeout | Proxy target URL incorrect or CAS Route unreachable |

## IBM Documentation

- [Is Your MCP Server Healthy?](https://community.ibm.com/community/user/blogs/paul-llamas-virgen/2026/03/06/is-your-mcp-server-healthy-to-explore-your-catalog)
- [Bob meets IBM CAS MCP — IBM Community Blog](https://community.ibm.com/community/user/blogs/namita-singroha/2026/03/24/bob-meets-ibm-cas-mcp)
- [IBM Bob meets CAS MCP — Everything You Need to Get Started (Medium)](https://medium.com/@singrohanamita/ibm-bob-meets-cas-mcp-everything-you-need-to-get-started-95d7e01b7f20)
- [CAS MCP Integration — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-integrating-model-context-protocol-mcp)
