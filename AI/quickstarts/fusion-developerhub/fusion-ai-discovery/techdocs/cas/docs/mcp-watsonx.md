# CAS + watsonx Orchestrate Integration

Connect IBM Fusion CAS to IBM watsonx Orchestrate for AI-powered semantic search and vector store
exploration. Once connected, watsonx agents can list vector stores, run semantic searches, and
retrieve file content using natural language — all via the CAS MCP Server.

!!! tip "Also works with Bob"
    IBM Bob (the AI assistant built into RHDH) connects to CAS MCP using the same streamable endpoint.
    See [Bob meets CAS MCP](mcp-bob.md) for the Bob-specific configuration and example conversations.

## Overview

| Item | Value |
|---|---|
| MCP transport for watsonx | Standard HTTP (JSON-RPC 2.0) |
| MCP endpoint path | `/cas/api/v1/mcp` |
| MCP streamable path | `/cas/api/v1/mcp-streamable/` _(trailing slash required)_ |
| Auth | Bearer token (passed at call time) |
| Tools exposed | `list_vector_stores`, `search_vector_stores`, `get_vector_store_file_content` |

> **Tip:** Find your cluster's exact MCP URL on the **Links** tab of the catalog entry for
> `fusion-cas-<cluster-id>` in Developer Hub.

## Configure watsonx Orchestrate

Get the **MCP Standard** endpoint from the Developer Hub catalog entry for your cluster (Links tab),
then add it to your watsonx Orchestrate MCP server configuration:

```yaml
mcp_servers:
  - name: fusion-cas-<cluster-id>
    connection_type: http
    url: https://console-ibm-spectrum-fusion-ns.apps.<cluster-domain>/cas/api/v1/mcp
    headers:
      Accept: "application/json"
      Content-Type: "application/json"
```

Replace `<cluster-id>` with the catalog entity name and `<cluster-domain>` with the cluster's OCP apps domain.

### Via RHDH Proxy (no VPN, no cluster login)

If watsonx Orchestrate can reach Developer Hub but not the Fusion cluster directly, use the RHDH proxy URL:

```yaml
mcp_servers:
  - name: fusion-cas-<cluster-id>
    connection_type: http
    url: https://<rhdh-host>/api/proxy/fusion-<cluster-id>-cas/cas/api/v1/mcp
    headers:
      Accept: "application/json"
      Content-Type: "application/json"
```

## Example Prompts for watsonx Agents

After connecting, try these queries in watsonx Orchestrate:

- `"List all vector stores in my CAS instance"`
- `"Search for documents related to regulatory compliance"`
- `"Find technical specifications in the engineering vector store"`
- `"Show me files about GDPR data retention policies"`
- `"Search the contracts dataset for supplier agreements from 2024"`

## Streamable Transport (VS Code / Bob / streaming clients)

For VS Code Copilot, Bob, or other streaming-capable clients, use the MCP Streamable endpoint instead.
**Note the trailing slash — it is required:**

**VS Code `.vscode/mcp.json`:**

```json
{
  "mcpServers": {
    "fusion-cas-<cluster-id>": {
      "url": "https://console-ibm-spectrum-fusion-ns.apps.<cluster-domain>/cas/api/v1/mcp-streamable/",
      "transport": "http"
    }
  }
}
```

**Bob (`app-config.yaml` in RHDH):**

```yaml
bob:
  mcp:
    servers:
      - name: fusion-cas-<cluster-id>
        url: /api/proxy/fusion-<cluster-id>-cas/cas/api/v1/mcp-streamable/
        transport: http
```

## Verify the Connection

Before configuring watsonx Orchestrate, confirm the MCP endpoint is reachable:

```bash
curl -s -X POST \
  https://console-ibm-spectrum-fusion-ns.apps.<cluster-domain>/cas/api/v1/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | python3 -m json.tool
```

Expected response includes a `tools` array with `list_vector_stores`, `search_vector_stores`,
and `get_vector_store_file_content`.

## Blog & Community Resources

- [Bob meets IBM CAS MCP — IBM Community Blog](https://community.ibm.com/community/user/blogs/namita-singroha/2026/03/24/bob-meets-ibm-cas-mcp)
- [IBM Bob meets CAS MCP — Everything You Need to Get Started (Medium)](https://medium.com/@singrohanamita/ibm-bob-meets-cas-mcp-everything-you-need-to-get-started-95d7e01b7f20)
- [CAS for the Generative AI Era (Medium)](https://medium.com/@mukherjeetiyasa1998/ibm-content-aware-storage-cas-rethinking-enterprise-data-for-the-generative-ai-era-635d959d2f0b)

## IBM Documentation

- [CAS + watsonx Orchestrate via MCP](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-integrating-watsonx-orchestrate-by-using-mcp)
- [CAS MCP Integration](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-integrating-model-context-protocol-mcp)
- [CAS Overview — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=services-content-aware-storage-cas)
