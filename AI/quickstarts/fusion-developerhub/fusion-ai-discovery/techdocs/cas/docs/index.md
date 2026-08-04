# IBM Fusion Content Aware Storage (CAS)

IBM Fusion Content Aware Storage (CAS) is an AI-native storage service that transforms unstructured data into semantically searchable vector embeddings, enabling generative AI applications to retrieve relevant content at scale without requiring data movement or separate vector databases.

CAS automatically ingests files from IBM Storage Scale and other connected sources, generates dense vector embeddings using configurable AI models, and indexes them in a built-in vector store. Applications can perform semantic similarity searches across billions of stored vectors using the REST API or the MCP Server, returning ranked results with the original file content.

## Key Capabilities

| Capability | Description |
|---|---|
| **Vector Storage** | Petabyte-scale vector store for unstructured data |
| **Semantic Search** | AI-powered similarity search across vector stores |
| **AI Classification** | Automated content tagging and categorization |
| **MCP Server** | AI agent integration via Model Context Protocol |
| **REST API** | Full OpenAPI v3 spec at `/cas/api/v1/docs` |
| **Multi-Cluster** | Single Developer Hub, N Fusion clusters |

The MCP Server exposes 3 tools to AI agents and IDE assistants:
`list_vector_stores`, `search_vector_stores`, `get_vector_store_file_content`. All tools require `server_url` and `auth_token` as runtime arguments — no credentials are stored in Developer Hub.

---

## Connect to CAS MCP

CAS has two MCP transports — choose based on your client.

Find your cluster's exact endpoints in the Developer Hub catalog entry for that cluster (`fusion-cas-<cluster-id>`).

### 1. Standard transport (VS Code, watsonx Orchestrate, curl)

- Method: `POST /cas/api/v1/mcp`
- Headers: `Content-Type: application/json` · `Accept: application/json`
- Returns plain JSON response (no SSE)

**Direct:**
```
https://console-ibm-spectrum-fusion-ns.apps.<cluster-domain>/cas/api/v1/mcp
```

**Via RHDH Proxy** (no VPN, no cluster login):
```
/api/proxy/fusion-<cluster-id>-cas/cas/api/v1/mcp
```

### 2. Streamable transport (VS Code Copilot, streaming clients)

- Method: `POST /cas/api/v1/mcp-streamable/` ← **trailing slash required**
- Headers: `Content-Type: application/json` · `Accept: application/json, text/event-stream`

**Direct:**
```
https://console-ibm-spectrum-fusion-ns.apps.<cluster-domain>/cas/api/v1/mcp-streamable/
```

**Via RHDH Proxy:**
```
/api/proxy/fusion-<cluster-id>-cas/cas/api/v1/mcp-streamable/
```

---

## VS Code — `.vscode/mcp.json`

Streamable transport is recommended for VS Code:

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

## watsonx Orchestrate (standard transport)

```yaml
mcp_servers:
  - name: fusion-cas-<cluster-id>
    connection_type: http
    url: https://console-ibm-spectrum-fusion-ns.apps.<cluster-domain>/cas/api/v1/mcp
```

---

## Quick Checks

**Health check** (returns `["OK", 200]`):
```bash
curl -s https://console-ibm-spectrum-fusion-ns.apps.<cluster-domain>/cas/api/v1/health
```

**List available tools:**
```bash
curl -s -X POST \
  https://console-ibm-spectrum-fusion-ns.apps.<cluster-domain>/cas/api/v1/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | python3 -m json.tool
```

Replace `<cluster-domain>` with the OCP apps domain for your cluster (e.g. `apps.<cluster-id>.<domain>`).

---

## IBM Documentation

- [CAS Overview — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=services-content-aware-storage-cas)
- [CAS REST API Reference](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-content-aware-storage-apis)
- [CAS MCP Integration](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-integrating-model-context-protocol-mcp)
- [CAS + watsonx Orchestrate via MCP](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-integrating-watsonx-orchestrate-by-using-mcp)
- [IBM Research — 100B Vector Storage for AI](https://research.ibm.com/blog/cas-100-billion-vector-storage-ai)
