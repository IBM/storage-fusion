# Bob meets CAS MCP

IBM Bob — the AI-powered Developer Hub assistant — connects directly to the CAS MCP Server,
giving developers natural language access to vector stores and semantic search without leaving
the Developer Hub UI.

## What is Bob?

Bob is the AI agent built into IBM Fusion Developer Hub (RHDH). It uses the Model Context Protocol (MCP)
to call tools on registered services. Once you point Bob at a CAS MCP endpoint, it can:

- **List** all vector stores on the cluster
- **Search** vector stores with natural language queries
- **Retrieve** file content from any vector store

No curl commands. No token juggling in the terminal. Just ask Bob.

## Connect Bob to CAS MCP

Bob is configured via the **MCP server list** in your Developer Hub `app-config`. Find your cluster's
MCP endpoint on the **Links** tab of the catalog entry for `fusion-cas-<cluster-id>`.

Add the CAS MCP endpoint to Bob's MCP configuration:

```yaml
# app-config.yaml (RHDH)
bob:
  mcp:
    servers:
      - name: fusion-cas-<cluster-id>
        url: https://console-ibm-spectrum-fusion-ns.apps.<cluster-domain>/cas/api/v1/mcp-streamable/
        transport: http
```

Or via the RHDH proxy (recommended — no VPN, no cluster login required):

```yaml
bob:
  mcp:
    servers:
      - name: fusion-cas-<cluster-id>
        url: /api/proxy/fusion-<cluster-id>-cas/cas/api/v1/mcp-streamable/
        transport: http
```

Replace `<cluster-id>` with the catalog entity name and `<cluster-domain>` with the OCP apps domain.

## Example Conversations with Bob

Once connected, ask Bob directly in the Developer Hub chat:

```
"List all vector stores in the CAS cluster prod-east"
```
```
"Search for documents about regulatory compliance in the finance vector store"
```
```
"Find technical specifications related to GPU memory in the engineering dataset"
```
```
"What files were recently indexed in the contracts vector store?"
```

Bob translates each question into the appropriate MCP tool call
(`list_vector_stores`, `search_vector_stores`, or `get_vector_store_file_content`)
and returns a formatted answer — all without leaving Developer Hub.

## MCP Tools Bob Uses

| Tool | What Bob Does |
|---|---|
| `list_vector_stores` | Shows all vector stores available on the CAS cluster |
| `search_vector_stores` | Runs semantic similarity search across vector store content |
| `get_vector_store_file_content` | Fetches the full file content from a vector store entry |

All tools require `server_url` and `auth_token` as runtime arguments —
no credentials are stored in Developer Hub or Bob's configuration.

## Troubleshooting Bob + CAS

| Symptom | Fix |
|---|---|
| Bob returns "no tools found" | Check the MCP endpoint URL — trailing slash required for streamable transport |
| Bob returns 401 | Provide a valid CAS auth token in the tool call |
| Bob returns 502 | Proxy target URL misconfigured — verify `/fusion-<id>-cas` proxy entry |
| Streamable endpoint times out | Try the standard (non-SSE) endpoint `/cas/api/v1/mcp` instead |

## Blog & Community Resources

- [Bob meets IBM CAS MCP — IBM Community Blog](https://community.ibm.com/community/user/blogs/namita-singroha/2026/03/24/bob-meets-ibm-cas-mcp)
- [IBM Bob meets CAS MCP — Everything You Need to Get Started (Medium)](https://medium.com/@singrohanamita/ibm-bob-meets-cas-mcp-everything-you-need-to-get-started-95d7e01b7f20)
- [Is Your MCP Server Healthy?](https://community.ibm.com/community/user/blogs/paul-llamas-virgen/2026/03/06/is-your-mcp-server-healthy-to-explore-your-catalog)

## IBM Documentation

- [CAS MCP Integration — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-integrating-model-context-protocol-mcp)
- [CAS Overview — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=services-content-aware-storage-cas)
