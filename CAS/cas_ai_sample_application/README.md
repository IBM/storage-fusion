# CASA - CAS AI Sample Application
# Authors: Vitaliy Kornev & Priyas Ojha
A sample RAG-powered chat application for querying documents stored in an **IBM Fusion Content Aware Storage (CAS)** vector store. You log in with your CAS credentials, choose a vector store, and ask questions in plain English — the app retrieves the most relevant document chunks and passes them to an LLM to generate a grounded answer.

This repo is a **starting point**. It is meant to be cloned, run as-is to verify your CAS + LLM setup, and then adapted for your own use case.

---

## How it works

```
Browser → React frontend → FastAPI backend → CAS (retrieval) + LLM (generation)
```

1. You enter your CAS endpoint and API token in the login screen.
2. The backend searches CAS for document chunks relevant to your question (RAG).
3. Those chunks are sent to an LLM alongside your question.
4. The LLM's response streams back to the browser token by token.

### How CAS is called — MCP vs REST

The backend talks to CAS using the **MCP (Model Context Protocol) streamable-HTTP transport** by default. Each search is a JSON-RPC `tools/call` request sent to the `/mcp-streamable/` endpoint on your CAS host, and the response arrives as a Server-Sent Events (SSE) stream.

> **Why MCP?** CAS exposes a standard MCP tool surface (`search_vector_stores`, `list_vector_stores`). Using MCP means the retrieval loop can route queries to *any* registered tool — CAS, a second MCP server, or a plain Python callable — without changing the loop logic. The LLM signals which tool it wants by emitting `[CHUNK:<tool_name>] <refined query>` in its response.

The REST API path (`/cas/api/v1/`) is used only to build the MCP endpoint URL — the actual chunk retrieval always goes through MCP. If you need to bypass MCP and call a plain REST search endpoint instead, you can register a custom tool callable; see **[docs/adding-an-mcp.md](docs/adding-an-mcp.md)**.

#### Retrieval loop at a glance

```
User query
    │
    ▼
_resolve_query_from_block()   ← rewrites follow-ups using session history
    │
    ▼
_run_retrieval_loop()
    ├─ call tool (default: "cas" via MCP)  ← CASClient._search_vector_store()
    ├─ LLM reads chunks
    │   ├─ FULL_ANSWER: <text> [SOURCE: N]  → answer returned, loop exits
    │   └─ [CHUNK:<tool>] <query>           → refetch with named tool, loop repeats
    └─ max iterations reached              → forced synthesis from all chunks
```

Adding a second data source (another MCP server, a database, an API) requires only registering a new tool — the loop, prompt assembly, and session handling are unchanged. See **[docs/adding-an-mcp.md](docs/adding-an-mcp.md)** for a step-by-step guide.

### Handling multiple questions

You can submit multiple questions at once — the app will answer each one separately. Questions are split on `?`, so the simplest way to ask several things is to end each one with a question mark.

> **Fair warning:** this is a sample application, not a production NLP pipeline. The splitter covers the common case (explicit question lists) but does not attempt to handle every edge case — for example, a single compound sentence with no `?` separating two distinct asks will be treated as one question.

### Session handling (conversation history)

By default the backend keeps an in-memory conversation history per browser session. This lets you ask follow-up questions without repeating context — the backend rewrites each new question against the prior turns before querying CAS.

- **Toggling on/off** — click the vector-store pill in the header, then flip the **Session History** toggle. The change takes effect immediately (no restart). The preference is saved in `localStorage` and re-synced from the backend on every login.
- **Recommended for local LLMs** — if you are running a small model (e.g. Ollama on a laptop) and find it rewriting short follow-up questions incorrectly, turn session handling off. Every request becomes a fresh conversation and no history is stored.
- **Disabled at the server level** — set `SESSION_ENABLED=false` in `backend/.env` to permanently disable sessions (useful for stateless or multi-replica deployments). See `backend/.env.example` for the full option block.
- **Session storage is in-memory and single-replica** — history is lost when the backend restarts and is not shared across multiple backend instances.

### New chat / clear history

The **New Chat** button (same header dropdown) clears the visible message list and immediately deletes the current session from the backend store — it does not wait for the TTL sweep. Use it whenever you want to start a completely fresh conversation.

### Dark and light mode

A theme toggle (🌙 / ☀️) in the top-right corner switches between light and dark mode. The preference is persisted in `localStorage` and applied as a `data-theme` attribute on `<html>`, so the whole UI — including the header, chat bubbles, dropdowns, and code blocks — switches instantly with no page reload.

---

## Quick start

> **Before you begin:** you need a running CAS instance with at least one vector store, and an accessible LLM. See [Getting Started](docs/GETTING_STARTED.md) if you haven't set those up yet.

If your environment is already configured:

```bash
make all
```

This installs all dependencies and starts the backend (`localhost:8000`) and frontend (`localhost:3000`) together. Press **Ctrl+C** to stop.

---

## Getting started from scratch

Read **[docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)** — it walks through every prerequisite in order:

1. Set up a CAS vector store → [`docs/01_cas-setup-guide.md`](docs/01_cas-setup-guide.md)
2. Get an LLM running → [`docs/02_LLM_deployment_port_forwarding.md`](docs/02_LLM_deployment_port_forwarding.md)
3. Run the application
4. Use the chat interface

---

## Adapting this for your own application

See **[docs/03_customization.md](docs/03_customization.md)** — covers the system prompt, RAG tuning, adding new API endpoints, and swapping the frontend.

---

## Project structure

```
├── backend/          Python / FastAPI — RAG pipeline, CAS client, LLM streaming
├── frontend/         Vite + React — chat UI, login modal, vector store picker
├── docs/
│   ├── GETTING_STARTED.md               Full setup walkthrough
│   ├── 01_cas-setup-guide.md            CAS vector store onboarding
│   ├── 02_LLM_deployment_port_forwarding.md  LLM setup (NIM or Ollama)
│   ├── 03_customization.md              How to adapt the app to your use case
│   └── adding-an-mcp.md                 How to wire in a second MCP server or data source
└── makefile          One-command setup and run (`make help` for all targets)
```

---

## Requirements

- Python 3.11+
- Node.js 18+
- An OpenAI-compatible LLM (NVIDIA NIM, Ollama, or OpenAI)
- An IBM Fusion CAS instance with at least one populated vector store

---

## Configuration reference

`backend/.env` (copy from `backend/.env.example`):
```env
LLM_BASE_URL=http://localhost:8001    # URL of your LLM service
LLM_MODEL=meta/llama-3.1-8b-instruct # model name to request
# LLM_API_KEY=                        # only if your LLM requires auth

# Session handling — omit or set true to enable, false to disable
SESSION_ENABLED=true
```

`frontend/.env` (copy from `frontend/.env.example`):
```env
VITE_API_URL=http://localhost:8000    # points to the backend (no change needed by default)
```

> CAS credentials (endpoint URL and API token) are entered in the app at runtime — they are not stored in `.env`.

---

## Backend tests

```bash
cd backend
source venv/bin/activate
pytest
```

See `make help` for individual test targets (`test-file`, `test-case`).
