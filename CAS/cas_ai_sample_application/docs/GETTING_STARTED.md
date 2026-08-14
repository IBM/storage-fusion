# Getting Started
# Authors: Vitaliy Kornev & Priyas Ojha
This guide walks you through every prerequisite and runs you through starting the application for the first time. Follow the steps in order.

---

## Overview

There are three things to have in place before running the app:

| # | What | Where |
|---|---|---|
| 1 | A CAS vector store with ingested documents | [`docs/01_cas-setup-guide.md`](01_cas-setup-guide.md) |
| 2 | An accessible LLM service | [`docs/02_LLM_deployment_port_forwarding.md`](02_LLM_deployment_port_forwarding.md) |
| 3 | The app configured and running | This document (steps below) |

If you already have CAS and an LLM set up, jump straight to [Run the app](#run-the-app).

---

## Step 1 — Set up a CAS vector store

Follow **[01_cas-setup-guide.md](01_cas-setup-guide.md)** to:

- Connect a data source to IBM Fusion CAS
- Create and populate a vector store
- Verify the search API is working

At the end of that guide you will have a **CAS endpoint URL** and **API token** — you will enter these in the app's login screen at runtime.

---

## Step 2 — Get an LLM running

Follow **[02_LLM_deployment_port_forwarding.md](02_LLM_deployment_port_forwarding.md)** to set up one of:

- **NVIDIA NIM on a cluster** — deploy the model and port-forward it locally
- **Ollama (local)** — pull a model and run it on your laptop

At the end of that guide you will have `LLM_BASE_URL` and `LLM_MODEL` values ready for your `.env`.

---

## Step 3 — Configure the app

### Python + Node prerequisites

- **Python 3.11+** — verify with `python3 --version`
- **Node.js 18+** — verify with `node --version`

### Backend

```bash
cd backend
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

> **`.env` required — the app will not start without it.**
> Copy the example file and edit it before running anything:
> ```bash
> cp .env.example .env
> ```

Open `backend/.env` and fill in the LLM settings for your setup:

```env
# URL of your LLM service (required — pick one):
LLM_BASE_URL=http://localhost:8001          # NVIDIA NIM via port-forward
# LLM_BASE_URL=http://localhost:11434       # Local Ollama
# LLM_BASE_URL=https://api.openai.com      # OpenAI

# Model name to request from that service (required — must match your service):
LLM_MODEL=meta/llama-3.1-8b-instruct       # NVIDIA NIM example
# LLM_MODEL=llama3.2:3b                    # Local Ollama example (must match `ollama pull <name>`)
# LLM_MODEL=gpt-4o                         # OpenAI example

# Set only if your LLM service requires an API key:
# LLM_API_KEY=
```

The rest of the defaults (port 8000, localhost CORS, etc.) work out of the box.

### Frontend

Open a **second terminal**:

```bash
cd frontend

# Install Node dependencies
npm install

# Create your .env from the example
cp .env.example .env
```

The default `VITE_API_URL=http://localhost:8000` already points to the backend correctly. No edits needed unless you changed the backend port.

---

## Run the app

**Recommended — one command from the repo root:**

```bash
make all
```

This creates the Python virtualenv, installs all dependencies, and starts the backend and frontend together. Press **Ctrl+C** to shut both down.

**Or start manually in two terminals:**

```bash
# Terminal 1 — backend
cd backend && source venv/bin/activate && python api_server.py

# Terminal 2 — frontend
cd frontend && npm run dev
```

---

## Step 4 — Use the app

Open `http://localhost:3000` in your browser:

1. Click **Login** and enter your **CAS endpoint URL** and **CAS API token** (from Step 1).
2. Select a vector store from the list.
3. Ask questions about your ingested documents in the chat interface.

### Header controls

After logging in, the header exposes several controls via the vector-store pill (top-right):

| Control | How to access | What it does |
|---|---|---|
| **New Chat** | Vector-store pill → New Chat | Clears the chat and immediately removes the current session from the backend. |
| **Session History toggle** | Vector-store pill → Session History | Flips conversation history on or off at runtime — no restart needed. |
| **Change Vector Store** | Vector-store pill → Change Vector Store | Re-opens the vector-store picker without requiring a full logout. |
| **Logout** | Vector-store pill → Logout | Clears credentials from the frontend. |
| **Dark / light mode** | 🌙 / ☀️ button in the header | Switches the UI theme. Preference is persisted in `localStorage`. |

### Session handling

By default the app remembers your conversation so you can ask follow-up questions without repeating context. The backend rewrites each follow-up against the prior turns before querying CAS.

**Turn it off when:**
- You are running a small local LLM (e.g. Ollama on a laptop) and find that short follow-up questions are being rewritten incorrectly.
- You want every request to be fully independent (stateless).

To disable permanently, set `SESSION_ENABLED=false` in `backend/.env` — see the full option block in [`backend/.env.example`](../backend/.env.example).

> **Note:** session history is stored in memory on a single backend process. It is lost on restart and is not shared across multiple replicas.

### New chat

Click **New Chat** in the dropdown at any time to wipe the visible conversation and tell the backend to discard the current session. This is equivalent to starting a completely fresh conversation — subsequent questions will have no prior context.

---

## Services at a glance

| Service  | Start command                              | Default URL                      |
|----------|--------------------------------------------|----------------------------------|
| Backend  | `python api_server.py` (inside `venv`)     | `http://localhost:8000`          |
| Frontend | `npm run dev`                              | `http://localhost:3000`          |
| API docs | *(served by backend)*                      | `http://localhost:8000/api/docs` |

---

## Common issues

**`Module not found` on backend start**
Make sure your virtual environment is activated before running `python api_server.py`.

```bash
source venv/bin/activate   # Windows: venv\Scripts\activate
```

**LLM not responding**
Check that `LLM_BASE_URL` in `backend/.env` points to a running service. For NIM, confirm the port-forward is active:

```bash
oc get pods -n <namespace>
oc port-forward -n <namespace> service/meta-llama-3-1-8b-instruct 8001:8000
```

For Ollama, confirm the model is downloaded and the daemon is running:

```bash
ollama list
ollama serve
```

**Auth failure in the UI**
The CAS endpoint and token are entered at login time, not in `.env`. Double-check the URL format and that your token has not expired. The backend accepts both a bare domain and a full `/cas/api/v1` path.

**CORS errors in the browser**
If you changed the frontend port, add it to `CORS_ORIGINS` in `backend/.env`:

```env
CORS_ORIGINS=http://localhost:3000,http://localhost:YOUR_PORT
```

**Port already in use**

```bash
# Find and kill the process on a given port
lsof -i :8000
kill -9 <PID>
```

---

## Next steps

Now that the app is running, see **[docs/03_customization.md](03_customization.md)** to learn how to adapt it for your own use case — changing the system prompt, tuning RAG parameters, adding endpoints, or replacing the frontend.
