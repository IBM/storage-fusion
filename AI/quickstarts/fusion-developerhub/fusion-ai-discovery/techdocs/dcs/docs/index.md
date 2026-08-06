# IBM Fusion Data Catalog Service (DCS)

IBM Fusion Data Cataloging Service (DCS) — powered by IBM Spectrum Discover — provides automated metadata scanning, AI-powered classification, and policy-driven data lifecycle management across IBM Storage Scale, S3, and file-based data sources.

DCS automatically scans and indexes data across heterogeneous storage environments to build a unified, searchable metadata catalog at petabyte scale. It applies AI-based tagging and classification to unstructured data, enabling policy-driven lifecycle management, compliance enforcement, and intelligent tiering without requiring data movement.

## Key Capabilities

| Capability | Description |
|---|---|
| **Metadata Scanning** | Automated discovery across petabytes of data |
| **AI Classification** | ML-based content tagging and categorization |
| **Policy Engine** | Data lifecycle and retention policies |
| **MCP Server** | AI agent integration via Model Context Protocol |
| **REST API** | Full programmatic access to catalog data |
| **Multi-Cluster** | Single Developer Hub, N Fusion clusters |

The MCP Server exposes 9 tools to AI agents and IDE assistants:
`dcs_file_search`, `dcs_get_registered_tags`, `dcs_get_recommend_tags`, `dcs_create_tag`, `dcs_create_policy`, `dcs_create_deepinspect_policy`, `dcs_create_tiering_policy`, `dcs_get_policies`, `dcs_set_credentials`.

---

## Connect to DCS MCP

DCS has a **dedicated MCP Route** (`dcs-mcp-route-*`) separate from the DCS console Route.

Find your cluster's exact endpoints in the Developer Hub catalog entry for that cluster (`fusion-dcs-<cluster-id>`).

> **Important:** Every POST to DCS MCP requires `Accept: application/json, text/event-stream`. Responses are SSE-wrapped even for synchronous calls — parse the `data:` line.

### HTTP transport (synchronous — VS Code, watsonx Orchestrate, curl)

- Method: `POST /mcp/http`
- Headers: `Content-Type: application/json` · `Accept: application/json, text/event-stream`

**Direct:**
```
https://dcs-mcp-route-ibm-data-cataloging.apps.<cluster-domain>/mcp/http
```

**Via RHDH Proxy** (no VPN, no cluster login):
```
/api/proxy/fusion-<cluster-id>-dcs-mcp/mcp/http
```

### SSE transport (streaming — Server-Sent Events)

**Direct:**
```
https://dcs-mcp-route-ibm-data-cataloging.apps.<cluster-domain>/mcp
```

**Via RHDH Proxy:**
```
/api/proxy/fusion-<cluster-id>-dcs-mcp/mcp
```

---

## VS Code — `.vscode/mcp.json`

```json
{
  "mcpServers": {
    "fusion-dcs-<cluster-id>": {
      "url": "https://dcs-mcp-route-ibm-data-cataloging.apps.<cluster-domain>/mcp/http",
      "transport": "http"
    }
  }
}
```

## watsonx Orchestrate (HTTP transport)

```yaml
mcp_servers:
  - name: fusion-dcs-<cluster-id>
    connection_type: http
    url: https://dcs-mcp-route-ibm-data-cataloging.apps.<cluster-domain>/mcp/http
```

---

## Quick Checks

**Initialize session, then list tools:**
```bash
# Step 1 — initialize (required before any other call, returns Mcp-Session-Id header)
SESSION=$(curl -si -X POST \
  https://dcs-mcp-route-ibm-data-cataloging.apps.<cluster-domain>/mcp/http \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
  | grep -i 'mcp-session-id' | awk '{print $2}' | tr -d '\r')

# Step 2 — list tools
curl -s -X POST \
  https://dcs-mcp-route-ibm-data-cataloging.apps.<cluster-domain>/mcp/http \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H "Mcp-Session-Id: $SESSION" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | python3 -m json.tool
```

Replace `<cluster-domain>` with the OCP apps domain for your cluster (e.g. `apps.<cluster-id>.<domain>`).

---

## IBM Documentation

- [Data Cataloging — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=services-data-cataloging)
- [DCS MCP Server — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=capabilities-data-cataloging-mcp-server)
- [Blog — Exploring Your Catalog with NLP](https://community.ibm.com/community/user/blogs/paul-llamas-virgen/2026/03/06/exploring-your-fusion-data-catalog-with-nlp)
- [Blog — AI Agents on watsonx Orchestrate](https://community.ibm.com/community/user/blogs/paul-llamas-virgen/2026/03/06/create-your-ai-agents-on-wx-orch-for-data-catalog)
