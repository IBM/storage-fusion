# CAS Architecture

## Overview

```
Developer (browser / AI agent / VS Code)
       │
       ▼
Developer Hub (RHDH)
       │
       ├── Proxy ──────────────────────────── CAS console Route
       │   /fusion-<cluster-id>-cas           console-ibm-spectrum-fusion-ns.apps.<domain>
       │                                           ├── /cas/overview           (UI)
       │                                           ├── /cas/api/v1/docs        (Swagger UI)
       │                                           ├── /cas/api/v1/health      (health check)
       │                                           ├── /cas/api/v1/datasets    (list vector stores)
       │                                           ├── /cas/api/v1/search      (semantic search)
       │                                           ├── /cas/api/v1/mcp         (MCP standard)
       │                                           └── /cas/api/v1/mcp-streamable/ (MCP streamable)
       │
       └── Kubernetes Plugin (self-hosted clusters only)
             └── OpenShift Cluster (ibm-cas namespace)
                   ├── ContentStorage CR
                   ├── FusionServiceInstance CR
                   └── CAS pods
```

## Key Design Point

**CAS has ONE Route** that serves all endpoints — UI, REST API, Swagger, MCP standard, and MCP streamable.  
A single proxy entry `/fusion-<cluster-id>-cas` pointing to the console Route hostname covers everything.

This differs from DCS, which has a separate `dcs-mcp-route-*` Route for its MCP server (requiring two proxy entries per DCS cluster).

## CAS Namespace Layout

CAS runs in the `ibm-cas` namespace on every Fusion HCI cluster.

```
ibm-cas
├── ContentStorage CR
├── FusionServiceInstance CR
├── Deployments + Pods  (label: app.kubernetes.io/name=ibm-cas)
└── Route: console-ibm-spectrum-fusion-ns.apps.<domain>
    ├── /cas/overview                   (CAS UI)
    ├── /cas/api/v1/docs                (Swagger UI)
    ├── /cas/api/v1/health              (health check — no auth)
    ├── /cas/api/v1/version             (version info — no auth)
    ├── /cas/api/v1/datasets            (list vector stores — Bearer auth)
    ├── /cas/api/v1/search              (semantic search — Bearer auth)
    ├── /cas/api/v1/mcp                 (MCP standard, JSON-RPC 2.0)
    └── /cas/api/v1/mcp-streamable/     (MCP streamable, SSE — trailing slash required)
```

> **Note:** The Route hostname prefix (`console-ibm-spectrum-fusion-ns`) is the OpenShift Route
> name — it is not the namespace. The namespace where CAS pods and the SA live is `ibm-cas`.

## How Developers Access CAS

Developers access CAS through RHDH without any cluster login or VPN:

```
Developer
    │
    ▼  POST /api/proxy/fusion-<cluster-id>-cas/cas/api/v1/mcp
RHDH Proxy
    │
    ▼  POST https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/mcp
CAS MCP Server
```

The proxy strips the `/api/proxy/fusion-<cluster-id>-cas` prefix before forwarding.
Authorization headers are passed through unchanged — the developer's own token reaches CAS directly.

## Cluster Types

| Type | K8s Plugin Tab | SA Token needed | Who configures |
|---|---|---|---|
| **self-hosted** | ✅ Shows pods, routes, CRs | ✅ Yes | Platform engineer |
| **proxy-only** (template-registered) | ❌ Not shown | ❌ No | Developer (template wizard) |
