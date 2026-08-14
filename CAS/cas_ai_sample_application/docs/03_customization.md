# Customizing the Application
# Authors: Vitaliy Kornev & Priyas Ojha
This guide is for developers who have the app running and want to adapt it for their own use case — different documents, different behaviour, or a different UI.

---

## What you can change

| What | Where | Effort |
|---|---|---|
| What the LLM is instructed to do | `backend/system_prompt.md` | Low |
| How many / which document chunks are retrieved | `backend/.env` RAG settings | Low |
| Which LLM is used | `backend/.env` LLM settings | Low |
| The chat UI appearance | `frontend/src/` CSS files | Low–Medium |
| Adding new API endpoints | `backend/api_server.py` | Medium |
| Changing how chunks are filtered and ranked | `backend/chunk_processor.py` | Medium |
| Replacing the frontend entirely | `frontend/` | High |

---

## 1 — Change the system prompt

The LLM's behaviour is entirely controlled by [`backend/system_prompt.md`](../backend/system_prompt.md). Edit this file to change:

- **What the assistant is allowed to say** — the current prompt restricts answers strictly to context sources. Remove or relax the `RULES` section to allow the model to use its own knowledge.
- **The response format** — the current prompt requires a `FULL_ANSWER: ... [SOURCE: N]` structure. Change this for free-form answers, bullet points, or any other format you need.
- **The domain and tone** — the examples use generic placeholder data. Replace them with examples from your actual domain (financial reports, legal documents, technical specs, etc.) to improve accuracy on your content.
- **The language** — the prompt is in English; translate it to have the assistant respond in another language.

After editing `system_prompt.md`, restart the backend — no rebuild needed.

---

## 2 — Tune RAG retrieval

The following settings in `backend/.env` control how many document chunks are fetched from CAS and which ones are passed to the LLM:

```env
# How many chunks to fetch per question (actual fetch is this value × 2 before filtering)
RAG_MAX_RESULTS=10

# Minimum relevance score for a chunk to be included at all (0.0–1.0)
# Raise this to cut low-confidence chunks; lower it if the model says "not in context" too often
RAG_MIN_SCORE=0.1

# Maximum characters per chunk passed to the LLM (0 = no limit)
RAG_MAX_CHUNK_CHARS=0

# Cross-document filtering: any source whose best score is more than this below the
# top-scoring source is dropped. Lower = more aggressive. Set 0.0 to disable.
RAG_DOMINANT_GAP=0.09
```

**Common adjustments:**
- Getting answers from the wrong document? Raise `RAG_DOMINANT_GAP` (e.g. `0.15`) to filter out lower-scoring sources more aggressively.
- Model says "not available in context" but you know the answer is there? Lower `RAG_MIN_SCORE` (e.g. `0.05`) or raise `RAG_MAX_RESULTS`.
- Answers are slow? Lower `RAG_MAX_RESULTS` and raise `RAG_MIN_SCORE` to pass fewer, higher-quality chunks.

---

## 3 — Swap the LLM

Change `LLM_BASE_URL` and `LLM_MODEL` in `backend/.env`. The backend works with any service that implements the OpenAI `/v1/chat/completions` API:

```env
# NVIDIA NIM
LLM_BASE_URL=http://localhost:8001
LLM_MODEL=meta/llama-3.1-8b-instruct

# Local Ollama
LLM_BASE_URL=http://localhost:11434
LLM_MODEL=llama3.2:3b

# OpenAI
LLM_BASE_URL=https://api.openai.com
LLM_MODEL=gpt-4o
LLM_API_KEY=sk-...
```

You can also control the maximum number of tokens in the LLM's response:

```env
LLM_MAX_TOKENS=300   # increase for longer answers, decrease to save cost/latency
```

Restart the backend after changing `.env`.

---

## 4 — Change the frontend UI

The frontend is plain React + CSS — no component library. Everything is in `frontend/src/`:

| File | What it controls |
|---|---|
| [`src/index.css`](../frontend/src/index.css) | CSS custom properties for light and dark themes |
| [`src/App.css`](../frontend/src/App.css) | Header, layout, welcome screen, theme toggle, session toggle pill |
| [`src/components/ChatInterface.css`](../frontend/src/components/ChatInterface.css) | Message bubbles, input bar, typing indicator |
| [`src/components/LoginModal.css`](../frontend/src/components/LoginModal.css) | Login modal, vector store picker |
| [`src/components/ChatInterface.jsx`](../frontend/src/components/ChatInterface.jsx) | Chat logic, streaming, message rendering, New Chat, session id forwarding |
| [`src/components/LoginModal.jsx`](../frontend/src/components/LoginModal.jsx) | Auth form, vector store selection |
| [`src/App.jsx`](../frontend/src/App.jsx) | Top-level layout, header, auth state, theme toggle, session toggle |

**Common UI changes:**

- **Branding / colours** — the primary accent colour is `#8A3FFC` (IBM purple). Search for it across the CSS files and replace with your brand colour.
- **App title** — change `"CAS AI Sample Application"` in [`src/App.jsx`](../frontend/src/App.jsx) and the `<title>` in [`index.html`](../frontend/index.html).
- **Logo** — replace the logo files in `src/assets/` and [`public/favicon.png`](../frontend/public/favicon.png) with your own images. Two logo files are used: one for light mode and one for dark mode (the dark variant uses `mix-blend-mode: screen` so it renders correctly on a dark background).
- **Placeholder text** — the chat input placeholder is set in `ChatInterface.jsx`; the login hints are in `LoginModal.jsx`.
- **Dark/light theme colours** — all theme tokens live in [`src/index.css`](../frontend/src/index.css) under `:root` (light) and `[data-theme="dark"]`. Change any token there to update colours globally across both themes.
- **Default theme** — the initial theme is read from `localStorage` key `theme` (values: `'light'` or `'dark'`). To change the fallback, edit the `useState` initialiser in [`src/App.jsx`](../frontend/src/App.jsx).

Run `npm run dev` to see changes live with hot reload.

---

## 5 — Session handling

Session handling is the feature that lets users ask follow-up questions in natural language. The backend maintains a per-session conversation history (queries + answers + a rolling summary) and rewrites each new query against that history before hitting CAS.

### How it works

1. On the first query, the backend creates a new session and returns its `session_id` in the `[DONE]` payload.
2. The frontend stores this id in a React ref (`sessionIdRef`) and forwards it on every subsequent request as `session_id` in the POST body.
3. The backend looks up the session, builds a history block, and passes it to `LLMService._resolve_query_from_block()` to rewrite the user's query before retrieval.
4. After each answer the backend appends a `Turn` (query + answer + source) to the session. When total history exceeds the budget, a compaction step folds old turns into a running summary.

### Configuring session behaviour

All session settings are in `backend/.env` (full reference in [`backend/.env.example`](../backend/.env.example)):

```env
# Master on/off switch (default: true)
SESSION_ENABLED=true

# Memory budget for stored history (tokens). Default calibrated for Llama 3.1 8B.
SESSION_MAX_CONTEXT_TOKENS=25000

# Compact when history reaches this fraction of the budget (default 80%)
SESSION_COMPACT_THRESHOLD=0.80

# Verbatim turns to keep after compaction (older turns fold into the summary)
SESSION_KEEP_TURNS=5
```

### Disabling sessions (recommended for small local LLMs)

Set `SESSION_ENABLED=false` in `backend/.env`. With this setting:
- Every request is treated as a fresh conversation.
- Nothing is stored and no background TTL sweep task starts.
- The `DELETE /api/session/{id}` endpoint becomes a no-op.
- The toggle in the UI still works at the frontend level but the backend never reads the `session_id` field.

This is the recommended setting when running a small local model (< 7 B parameters) that may struggle with query rewriting.

### Runtime toggle

Users can toggle sessions on/off without a restart from the **Session History** switch in the header dropdown. This calls `POST /api/session/toggle` which flips `_session_state["enabled"]` in memory. The frontend persists the resulting state in `localStorage` so the UI reflects the correct toggle position after a page reload.

---

## 6 — Add a new API endpoint

All endpoints live in [`backend/api_server.py`](../backend/api_server.py). To add one:

1. Define a Pydantic request/response model near the top of the file.
2. Add a route handler using the `@app.get` / `@app.post` decorators.
3. Construct `CASClient` and `LLMService` inside the handler — both are lightweight and created per-request (see the existing `query_llm_stream` handler for the pattern).

Example skeleton:

```python
class MyRequest(CASCredentialsBase):
    query: str

@app.post("/api/my-endpoint")
async def my_endpoint(request: MyRequest):
    cas = _build_cas_client(request.cas_api_key, request.cas_endpoint)
    llm = LLMService(cas)
    return {"result": "..."}
```

API docs are auto-generated at `http://localhost:8000/api/docs` (Swagger UI) — your new endpoint will appear there automatically.

---

## 7 — Run the backend tests

The backend has a unit test suite in `backend/testing/unit/`. After making changes:

```bash
cd backend
source venv/bin/activate
make test                          # full suite
make test-file F=test_llm_service  # one file
make test-case K=TC-LLM-001        # one test by ID
```

---

## Where to go next

- [`backend/llm_service.py`](../backend/llm_service.py) — the RAG pipeline: retrieval, chunk filtering, prompt assembly, and LLM streaming
- [`backend/chunk_processor.py`](../backend/chunk_processor.py) — post-retrieval filtering and ranking logic
- [`backend/agents/cas_client.py`](../backend/agents/cas_client.py) — the CAS HTTP client (auth, search, vector store listing)
- [`backend/session_store.py`](../backend/session_store.py) — the in-memory session store: `Turn`, `Session`, compaction, TTL sweep
- [`backend/.env.example`](../backend/.env.example) — full reference of every available configuration variable
