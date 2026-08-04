# CAS REST API Reference

## Swagger UI

Interactive API documentation — open from the catalog entry **Links** tab, or directly at:
```
https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/docs
```

Via RHDH proxy (no VPN — use `<cluster-id>` from the catalog entity name):
```
/api/proxy/fusion-<cluster-id>-cas/cas/api/v1/docs
```

## Authentication

CAS uses Bearer token authentication:
```bash
-H "Authorization: Bearer <token>"
```

## Core Endpoints

| Path | Method | Auth | Description |
|---|---|---|---|
| `/cas/api/v1/health` | GET | None | Service health |
| `/cas/api/v1/version` | GET | None | Version info |
| `/cas/api/v1/datasets` | GET | Bearer | List datasets (vector stores) |
| `/cas/api/v1/search` | POST | Bearer | Semantic / vector search |
| `/cas/api/v1/mcp` | POST | None | MCP standard endpoint |
| `/cas/api/v1/mcp-streamable/` | POST | None | MCP streamable endpoint (SSE — trailing slash required) |

## Semantic Search

```bash
curl -s -X POST \
  https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/search \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{"query": "regulatory compliance documents", "top_k": 10}'
```

Replace `<domain>` with your cluster's OCP apps domain (visible in the catalog entry Links tab).

## IBM Documentation

- [CAS REST API Reference](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-content-aware-storage-apis)
