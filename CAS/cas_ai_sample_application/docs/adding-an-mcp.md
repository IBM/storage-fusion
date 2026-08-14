# Adding a Custom MCP Server

This guide explains how to wire a second MCP (Model Context Protocol) server into the retrieval pipeline alongside CAS.

The integration point is a single method in [`backend/llm_service.py`](../backend/llm_service.py) — everything else (the retrieval loop, tool routing, prompt assembly) already supports multiple tools out of the box.

---

## How the retrieval loop works

Each query goes through a loop:

1. The loop calls a registered **tool** (by default, `cas`) with the user's query.
2. The LLM reads the returned chunks and either answers (`FULL_ANSWER:`) or asks for more context (`[CHUNK:<tool>] <refined query>`).
3. If it asks for more context, the loop calls the named tool and repeats.

A **tool** is any callable that accepts `(query: str, **kwargs)` and returns:

```python
{"status": "success", "data": [{"content": "...", "filename": "...", "score": {...}}]}
# or on failure:
{"status": "error", "error": "reason"}
```

---

## Step 1 — Build a callable for your MCP

Your callable must fetch from your MCP and return the standard result shape.

### Option A — fastmcp streamable-http endpoint

If your server uses the `fastmcp` streamable-http transport (path contains `/mcp-streamable/`):

```python
import requests, json

def _my_mcp_search(query: str, **_kwargs) -> dict:
    """Search my-mcp for `query` and return chunks."""
    url = "http://my-mcp-host:8003/mcp-streamable/"
    auth_token = "my-secret-token"   # or load from os.getenv()

    # 1. Initialize — get session id
    init_payload = {
        "jsonrpc": "2.0", "id": 0, "method": "initialize",
        "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                   "clientInfo": {"name": "cas-backend", "version": "1.0"}},
    }
    headers = {"Content-Type": "application/json",
               "Accept": "application/json, text/event-stream"}
    r = requests.post(url, json=init_payload, headers=headers, stream=True, timeout=10, verify=False)
    r.raise_for_status()
    for _ in r.iter_lines():
        pass
    session_id = r.headers.get("mcp-session-id")

    # 2. Call the tool
    call_payload = {
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": "my_tool_name", "arguments": {"query": query, "auth_token": auth_token}},
    }
    if session_id:
        headers["mcp-session-id"] = session_id
    r2 = requests.post(url, json=call_payload, headers=headers, stream=True, timeout=30, verify=False)
    r2.raise_for_status()

    # 3. Parse SSE response
    last = None
    for raw in r2.iter_lines():
        ln = raw.decode() if isinstance(raw, bytes) else raw
        if not ln.startswith("data:"):
            continue
        p = ln[5:].strip()
        if not p:
            continue
        try:
            m = json.loads(p)
            if "result" in m:
                last = m["result"]
        except Exception:
            pass

    if last is None:
        return {"status": "error", "error": "Empty response from my-mcp"}

    # 4. Normalise to the standard chunk shape
    content = str(last)
    return {"status": "success", "data": [{"content": content, "filename": "my-mcp", "score": {}}]}
```

### Option B — plain JSON-RPC endpoint (no SSE)

If your server returns `application/json` directly (no session handshake, no SSE):

```python
import requests

def _my_mcp_search(query: str, **_kwargs) -> dict:
    url = "http://my-mcp-host:8003/mcp"
    payload = {
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": "my_tool_name", "arguments": {"query": query}},
    }
    r = requests.post(url, json=payload, headers={"Content-Type": "application/json"}, timeout=30)
    r.raise_for_status()
    body = r.json()
    if "error" in body:
        return {"status": "error", "error": str(body["error"])}
    result = body.get("result", "")
    return {"status": "success", "data": [{"content": str(result), "filename": "my-mcp", "score": {}}]}
```

### Option C — a Python SDK client

If you have a Python client library for your data source:

```python
from my_sdk import MyClient

_client = MyClient(api_key=os.getenv("MY_API_KEY"))

def _my_mcp_search(query: str, **_kwargs) -> dict:
    results = _client.search(query, max_results=10)
    data = [{"content": r.text, "filename": r.title, "score": {"combined_probability_score": r.score}}
            for r in results]
    return {"status": "success", "data": data}
```

---

## Step 2 — Register the tool in `LLMService`

Open [`backend/llm_service.py`](../backend/llm_service.py) and find this comment inside `__init__`:

```python
self._register_cas_tools()
# To add a second MCP server, call self.tool_registry.register() here.
# See docs/adding-an-mcp.md for a step-by-step guide.
```

Add one line after it:

```python
self._register_cas_tools()
self.tool_registry.register(
    "my_mcp",                          # tool name — LLM uses this in [CHUNK:my_mcp]
    _my_mcp_search,                    # callable from Step 1
    description="My MCP — one sentence describing what it indexes or answers.",
)
```

The `description` is injected into the retrieval prompt so the LLM can pick the right tool for each question. Make it concise and accurate.

---

## Step 3 — Verify

Run the backend and send a query that should hit your new tool. In the logs you will see:

```
tool_registry registered name='my_mcp'
retrieval_loop iter=1 tool='cas' decision='[CHUNK:my_mcp] <refined query>'
retrieval_loop refetch tool='my_mcp' query='<refined query>'
```

If the LLM always stays on `cas`, sharpen the `description` so the topic mismatch is obvious (e.g. `"Real-time stock prices — NOT for document or policy questions"`).

---

## Checklist

- [ ] Callable returns `{"status": "success", "data": [...]}` or `{"status": "error", "error": "..."}`.
- [ ] Each item in `data` has at least a `"content"` key (string).
- [ ] `score` dict can be empty (`{}`) for sources that don't produce relevance scores.
- [ ] `description` is one sentence that accurately describes what the tool answers.
- [ ] Credentials (tokens, URLs) are loaded from environment variables, not hard-coded.
