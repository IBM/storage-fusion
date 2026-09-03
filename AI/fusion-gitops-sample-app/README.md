# Agentic Chat Assistant — Sample Application

A production-ready chat application for the IBM Fusion AI / LLMOps platform that unifies
RAG (remote gateway models) and CPU (KServe InferenceServices) behind a single model
dropdown with optional Auto Detect.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Repository Layout](#repository-layout)
4. [Running Locally](#running-locally)
5. [Deploying to a Cluster](#deploying-to-a-cluster)
6. [API Reference](#api-reference)

---

## Overview

The application exposes a **unified model dropdown** and an **Auto Detect toggle** in the
sidebar. The backend resolves which runtime to use (Model Gateway or KServe) transparently —
the user only sees model names.

### Unified model selection

| Model type | Backed by | Selected when… |
|---|---|---|
| Gateway / large models | Model Gateway (GPU, remote cluster) | General chat, RAG, or any task the CPU models don't cover |
| `qwen2-5-1-5b-cpu` | KServe InferenceService (CPU) | Auto Detect → `chat` task |
| `qwen2-5-coder-1-5b-cpu` | KServe InferenceService (CPU) | Auto Detect → `code` task |
| `smollm2-1-7b-cpu` | KServe InferenceService (CPU) | Auto Detect → `summarize` task |

### Auto Detect

When **Auto Detect** is ON the backend classifies the prompt by keyword signals and routes
to the best-matching model based on declared capabilities. When OFF the user picks any model
from the dropdown explicitly.

### CAS / RAG

CAS (Content-Aware Storage) vector search runs for **any model** when a vector store is
selected — it is not restricted to gateway models.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│   React UI  (port 8000, /)                                   │
│   Vite + TypeScript + Tailwind                               │
│   served as static files by FastAPI's StaticFiles mount      │
└──────────────────────┬───────────────────────────────────────┘
                       │  fetch /api/*
┌──────────────────────▼───────────────────────────────────────┐
│   FastAPI backend  (port 8000)   backend/main.py             │
│                                                              │
│   GET  /api/config                                           │
│   GET  /api/vector-stores                                    │
│   GET  /api/models          ◄── unified model list           │
│   POST /api/chat            ◄── unified chat (all models)    │
│   GET  /healthz                                              │
└──────────────┬───────────────────────┬───────────────────────┘
               │  gateway path         │  CPU path
     ┌─────────▼─────────┐   ┌────────▼────────────────────────┐
     │  src/rag_flow      │   │  _handle_cpu_chat()             │
     └─────────┬─────────┘   │  MODEL_URL_CHAT / CODE /        │
     ┌─────────┴────────────┐ │  SUMMARIZE (env vars)           │
     │  src/cas_client      │ └────────┬────────────────────────┘
     │  src/model_gateway   │          │ KServe /v1/chat/completions
     │       _client        │   ┌──────▼──────────────────────────────┐
     └──────────────────────┘   │  namespace: deploy-models-cpu│
                                │  qwen2-5-1-5b-cpu   (chat)          │
                                │  qwen2-5-coder-1-5b-cpu (code)      │
                                │  smollm2-1-7b-cpu   (summarize)     │
                                └──────────────────────────────────────┘
```

Container image is a **two-stage build**:
- Stage 1 — `node:20-alpine` compiles the React app to static files
- Stage 2 — `python:3.11-slim` runs FastAPI + serves the compiled UI

---

## Repository Layout

```
fusion-gitops-sample-app/
├── frontend/                   # React UI (Vite + TypeScript + Tailwind)
│   ├── src/
│   │   ├── App.tsx             # Main application shell
│   │   ├── api.ts              # Typed fetch wrappers for /api/*
│   │   ├── types.ts            # Shared TypeScript interfaces
│   │   └── components/
│   │       ├── Sidebar.tsx     # Vector store / model selectors + Auto Detect toggle
│   │       ├── ChatMessage.tsx # User + assistant bubbles (react-markdown)
│   │       ├── MetricsAndSources.tsx  # Timing cards + source expander
│   │       ├── WelcomeScreen.tsx
│   │       └── Select.tsx
│   ├── package.json
│   └── vite.config.ts
│
├── backend/                    # FastAPI application
│   ├── main.py                 # All API routes + unified model registry
│   └── requirements.txt
│
├── src/                        # Core RAG logic
│   ├── cas_client.py
│   ├── model_gateway_client.py
│   └── rag_flow.py
│
├── chart/                      # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml             # All configurable values live here
│   ├── VALUES.md               # Field-by-field reference for values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── configmap.yaml      # Rendered from values.yaml
│       ├── deployment.yaml     # Deployment + Service + Route (port 8000)
│       ├── rbac.yaml
│       └── secrets.yaml        # ExternalSecret OR hardcoded (toggle in values)
│
├── gitops/
│   └── llmops-with-reloader.yaml   # ArgoCD Application manifests (apply once)
│
├── scripts/
│   ├── build_and_push_chat_app.sh  # Build and push the container image
│   └── verify_deployment.sh        # Post-deploy health check
│
├── Dockerfile.chat-app         # Multi-stage: Node 20 → Python 3.11-slim
├── DEPLOYMENT.md               # ← Full deployment guide (read this next)
└── env.example                 # Environment variable reference for local dev
```

---

## Running Locally

### Prerequisites

- Python 3.11+
- Node.js 20+
- Access to a CAS endpoint and a Model Gateway endpoint

### 1. Clone & configure environment

```bash
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/fusion-gitops-sample-app

cp env.example .env
# Edit .env:
#   CAS_ENDPOINT=https://your-cas.example.com
#   CAS_API_KEY=your-cas-key
#   CAS_VECTOR_STORE_ID=optional-store-id
#   MODEL_GATEWAY_ENDPOINT=https://your-gateway.example.com
#   MODEL_GATEWAY_API_KEY=your-bearer-token
#   MODEL_NAME=granite
```

### 2. Start the FastAPI backend

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r backend/requirements.txt
uvicorn backend.main:app --reload --port 8000
```

The API is now at `http://localhost:8000`.
Health check: `curl http://localhost:8000/healthz`

### 3. Start the React dev server (with hot-reload)

In a second terminal:

```bash
cd frontend
npm install
npm run dev          # http://localhost:5173
```

The Vite dev server proxies `/api/*` → `http://localhost:8000` automatically.
Open `http://localhost:5173` in your browser.

---

## Deploying to a Cluster

> **→ See [DEPLOYMENT.md](./DEPLOYMENT.md) for the full guide.**

It covers, in order:

| Step | What it covers |
|---|---|
| Prerequisites | Cluster operators, local tooling, platform services checklist |
| Build & push | Container image build with `podman`, Apple Silicon notes |
| Configure | Every `chart/values.yaml` field — image, CAS, Model Gateway, CPU models, secrets |
| Vault setup | Storing all 5 secrets (CAS key, gateway key, 3 CPU SA tokens) |
| ArgoCD deploy | Applying the Application manifests, sync wave ordering |
| Verify | Running `scripts/verify_deployment.sh` and reading its output |
| Day-2 ops | Image updates, API key rotation, model swaps, scaling |
| Troubleshooting | Pod failures, ExternalSecret errors, ArgoCD OutOfSync, 502/504 errors |

For the Helm values field-by-field reference see [`chart/VALUES.md`](./chart/VALUES.md).

---

## API Reference

All endpoints are served on port `8000` alongside the React UI.

| Endpoint | Method | Description |
|---|---|---|
| `/healthz` | GET | Liveness / readiness probe |
| `/api/config` | GET | Active endpoint configuration (no secrets) |
| `/api/vector-stores` | GET | Available CAS vector stores |
| `/api/models` | GET | All models — gateway + CPU, with capabilities |
| `/api/chat` | POST | Unified chat — gateway or CPU, with optional RAG |
| `/api/rag/chat` | POST | Legacy RAG-only endpoint (backward compat) |
| `/api/cpu/models` | GET | Legacy CPU task → model mapping |
| `/api/cpu/chat` | POST | Legacy CPU-only endpoint (backward compat) |

### `POST /api/chat` request

```json
{
  "query": "Write a Python function that reverses a linked list",
  "vector_store_id": "my-store",
  "model_id": "qwen2-5-1-5b-cpu",
  "auto_detect": false,
  "max_tokens": 512,
  "temperature": 0.7,
  "history": [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}]
}
```

- `model_id` — any ID from `GET /api/models`; empty = use default model
- `auto_detect` — `true` classifies the prompt and picks the best-matching model
- `vector_store_id` — optional; triggers CAS RAG for any model when set
- `history` — multi-turn conversation context

### `POST /api/chat` response

```json
{
  "response": "def reverse_linked_list(head): ...",
  "model_id": "qwen2-5-1-5b-cpu",
  "sources": [],
  "metrics": {"processing_time": 1.2, "sources_count": 0, "cas_search_count": 0},
  "usage": {"prompt_tokens": 18, "completion_tokens": 87, "total_tokens": 105}
}
```

- `sources` and `metrics` are populated when CAS search ran
- `usage` is populated when a CPU/KServe model answered
