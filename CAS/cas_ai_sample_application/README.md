# IBM Fusion CAS Assistant

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

### Handling multiple questions

You can submit multiple questions at once — the app will answer each one separately. Questions are split on `?`, so the simplest way to ask several things is to end each one with a question mark.

> **Fair warning:** this is a sample application, not a production NLP pipeline. The splitter covers the common case (explicit question lists) but does not attempt to handle every edge case — for example, a single compound sentence with no `?` separating two distinct asks will be treated as one question.

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

See **[docs/03_customisation.md](docs/03_customisation.md)** — covers the system prompt, RAG tuning, adding new API endpoints, and swapping the frontend.

---

## Project structure

```
├── backend/          Python / FastAPI — RAG pipeline, CAS client, LLM streaming
├── frontend/         Vite + React — chat UI, login modal, vector store picker
├── docs/
│   ├── GETTING_STARTED.md               Full setup walkthrough
│   ├── 01_cas-setup-guide.md            CAS vector store onboarding
│   ├── 02_LLM_deployment_port_forwarding.md  LLM setup (NIM or Ollama)
│   └── 03_customisation.md              How to adapt the app to your use case
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
