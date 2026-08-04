# DCS Architecture

## Overview

```
Developer (browser / AI agent / VS Code)
       │
       ▼
Developer Hub (RHDH)
       │
       ├── Proxy ──────────────────────────── ibm-data-cataloging namespace
       │   /fusion-<cluster-id>-dcs           console-ibm-data-cataloging.apps.<domain>
       │   /fusion-<cluster-id>-dcs-mcp       dcs-mcp-route-ibm-data-cataloging.apps.<domain>
       │
       └── Kubernetes Plugin (self-hosted clusters only)
             └── OpenShift Cluster (ibm-data-cataloging namespace)
                   ├── SpectrumDiscover CR
                   ├── DCS pods (app=isd)
                   ├── DCS console Route
                   └── DCS MCP Route (dcs-mcp-route-*)
```

## Key Design Points

1. **DCS MCP has its own Route** — `dcs-mcp-route-ibm-data-cataloging.apps.<domain>` — separate from the DCS console Route. Two proxy entries per cluster are required.

2. **Authentication** — DCS REST API uses `x-auth-token` (obtained via `/auth/v1/token` with Basic credentials). The MCP Server does not require auth for the `initialize` / `tools/list` handshake.

3. **Developer access is proxy-only** — developers never need cluster credentials. The proxy forwards the `x-auth-token` header to DCS unchanged.

## DCS Namespace Layout

```
ibm-data-cataloging
├── SpectrumDiscover CR (data-cataloging-service-instance)
├── FusionServiceInstance CR
├── Deployments/StatefulSets + Pods (app=isd)
├── Services
└── Routes
    ├── console-ibm-data-cataloging     (DCS REST API + UI)
    └── dcs-mcp-route-ibm-data-cataloging  (MCP Server — separate Route)
```

## How Developers Access DCS

```
Developer
    │
    ├── REST API: GET /api/proxy/fusion-<cluster-id>-dcs/connmgr/v1/connections
    │                              └─ forwards to console-ibm-data-cataloging.apps.<domain>
    │
    └── MCP:      POST /api/proxy/fusion-<cluster-id>-dcs-mcp/mcp/http
                               └─ forwards to dcs-mcp-route-ibm-data-cataloging.apps.<domain>
```

## Cluster Types

| Type | K8s Plugin Tab | SA Token needed | Who configures |
|---|---|---|---|
| **self-hosted** | ✅ Shows pods, routes, CRs | ✅ Yes | Platform engineer |
| **proxy-only** (template-registered) | ❌ Not shown | ❌ No | Developer (template wizard) |
