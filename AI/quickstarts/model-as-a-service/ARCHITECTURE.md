# MaaS Architecture & Component Relationships

This document outlines the system architecture, component interactions, network flows, and wave-based deployment sequencing for the Model as a Service (MaaS) platform.

---

## 1. High-Level System Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              IBM Storage Fusion — MaaS Platform                        │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│   CLIENT ACCESS LAYER                                                                  │
│   ┌───────────────────────────┐    ┌───────────────────────────┐                       │
│   │   Enterprise Applications │    │   Agents / SDKs / Bifrost │                       │
│   └─────────────┬─────────────┘    └─────────────┬─────────────┘                       │
│                 │                                │                                     │
│                 ▼                                ▼                                     │
│   INGRESS & GOVERNANCE LAYER (Kuadrant + Envoy Gateway)                                │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ OpenShift Route (Re-encrypt TLS) → Gateway: maas-default-gateway (Port 443)    │   │
│   │ Authorino (API key / OIDC)   │ Limitador (Rate Limiting)   │ EnvoyFilter       │   │
│   │ MaaSSubscription             │ MaaSAuthPolicy              │ Groups RBAC       │   │
│   └──────────────────────────────────────┬─────────────────────────────────────────┘   │
│                                          │ HTTP / gRPC                                 │
│                                          ▼                                             │
│   MODEL INFERENCE RUNTIME (RHOAI 3.5+ + KServe LLMInferenceService / vLLM)            │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │  Namespace: deploy-models-rhoai / per-model namespaces                         │   │
│   │  ┌───────────────────────┐  ┌───────────────────────┐  ┌──────────────────────┐│   │
│   │  │ Granite 4.1 (8B)      │  │ Qwen 2.5 / 3 (FP8)    │  │ GPT-OSS (20B)        ││   │
│   │  │ LLMInferenceService   │  │ LLMInferenceService   │  │ LLMInferenceService  ││   │
│   │  │ Accelerator: NVIDIA   │  │ Accelerator: NVIDIA   │  │ Accelerator: CPU/GPU ││   │
│   │  └───────────────────────┘  └───────────────────────┘  └──────────────────────┘│   │
│   └──────────────────────────────────────┬─────────────────────────────────────────┘   │
│                                          │ RWX / RWO Mounts & S3 Buckets               │
│                                          ▼                                             │
│   STORAGE & REGISTRY INFRASTRUCTURE (IBM Fusion Data Foundation & PostgreSQL)          │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │  • Model Registry Service (REST API + PostgreSQL Backend)                      │   │
│   │  • CephFS RWX PVCs (Model weights >50GB, Multi-GPU Tensor Parallelism)         │   │
│   │  • Ceph-RBD RWO PVCs (Single-node weights)                                     │   │
│   │  • NooBaa S3 ObjectBuckets (Staging & Fast artifact loading)                  │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Logical Repositories & Responsibilities

```mermaid
graph TD
    subgraph Org ["GitHub Org / Organization Root"]
        Runtime["repo: runtime<br/>(Operators, DSC, Gateway, Registry)"]
        Models["repo: models<br/>(Catalog, Serving Charts, Values)"]
        Gov["repo: governance<br/>(MaaSSubscription, AuthPolicy, RBAC)"]
        Docs["repo: docs<br/>(Platform Guides)"]
    end

    Runtime -->|Provides Gateway & Registry| Models
    Runtime -->|Enforces Policies via Kuadrant| Gov
    Gov -->|References Models / Routes| Models
    Models -->|Registers Catalog| Runtime
```

---

## 3. Wave-Based Deployment Sequencing

Deployments follow an ordered wave model using Helm or ArgoCD sync waves:

| Wave | Stage | Target Namespace | Chart / Component | Key Resources Created |
|---|---|---|---|---|
| **Wave 1** | Operators | `openshift-operators`, `redhat-ods-operator` | `runtime/charts/maas-operators` | Subscriptions: RHOAI, Kuadrant, Authorino, Limitador, LeaderWorkerSet |
| **Wave 2** | Platform Infrastructure | `redhat-ods-applications`, `maas-model-registry-db` | `runtime/charts/maas-platform` | DataScienceCluster (`default-dsc`), PostgreSQL StatefulSet, SecretStore |
| **Wave 3** | Runtime Services | `openshift-ingress`, `redhat-ai-gateway-infra`, `rhoai-model-registries` | `runtime/charts/maas-runtime`, `runtime/charts/maas-model-registry` | Gateway (`maas-default-gateway`), Authorino TLS Config, OpenShift Route, Model Registry REST Service |
| **Wave 4** | Model Serving Instances | `deploy-models-rhoai` (or custom) | `models/charts/maas-model-service` / `maas-model-deploy` | `LLMInferenceService`, `MaaSModelRef`, HTTPRoute, vLLM Pods |
| **Wave 5** | Governance & Access Control | `redhat-ai-gateway-infra` | `governance/charts/maas-config` | `MaaSSubscription`, `MaaSAuthPolicy`, User Groups |

---

## 4. Request Flow & Auth Verification

```mermaid
sequenceDiagram
    autonumber
    actor Client as Client / Application
    participant Route as OpenShift Route
    participant Gateway as Envoy Gateway
    participant Authorino as Authorino (ExtAuth)
    participant Model as LLMInferenceService (vLLM)

    Client->>Route: HTTPS POST /deploy-models-rhoai/<model>/v1/chat/completions (Bearer Token / API Key)
    Route->>Gateway: Forward (Re-encrypt TLS)
    Gateway->>Authorino: CheckExtAuth (gRPC / Port 50051)
    Note over Authorino: Evaluates MaaSAuthPolicy & MaaSSubscription
    alt Auth Valid & Within Rate Limit
        Authorino-->>Gateway: HTTP 200 OK (Allowed)
        Gateway->>Model: Forward to vLLM Container
        Model-->>Gateway: Streaming Token / Response
        Gateway-->>Client: HTTP 200 (Inference Payload)
    else Invalid Auth or Quota Exceeded
        Authorino-->>Gateway: HTTP 401 / 429
        Gateway-->>Client: Error Response
    end
```
