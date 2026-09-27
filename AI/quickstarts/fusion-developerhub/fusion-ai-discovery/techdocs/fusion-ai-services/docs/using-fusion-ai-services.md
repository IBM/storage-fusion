# Using Fusion AI Services

**Who this is for:** Developers and data scientists who want to discover and use
IBM Fusion AI Services — Content Aware Storage (CAS), Data Cataloging Service (DCS),
or watsonx Orchestrate (WXO) — from this Developer Hub.

**Time:** 5–10 minutes.

**What you need:** Access to this Developer Hub. That's it.

---

## What is IBM Fusion?

IBM Fusion is an enterprise software platform that runs on Red Hat OpenShift —
on your organisation's own infrastructure, on-premises or in a private cloud.
It is not a hosted cloud service. Your data stays on your infrastructure.

Fusion bundles storage, data services, and AI-ready integrations as native
OpenShift capabilities. The services you can discover and use from this
Developer Hub are a subset of what Fusion offers. For the full picture,
see the [IBM Fusion Knowledge Center](https://www.ibm.com/docs/en/fusion-software).

### Services available here

| Service | What it does |
|---|---|
| **CAS** — Content Aware Storage | Stores, indexes, and semantically searches unstructured data — documents, images, files — directly on your cluster. Exposes a REST API and an MCP server for AI tooling. |
| **DCS** — Data Cataloging Service | Discovers, classifies, tags, and governs data assets across connected storage systems. Exposes a REST API and an MCP server. |
| **WXO** — watsonx Orchestrate | AI agent platform deployed on OpenShift via Fusion Software Hub. Lets you build and run AI agents that can use CAS and DCS as data sources. |

Not every cluster has all three services installed. What appears in this
Developer Hub depends on what your platform team has registered.

---

## Step 1 — Check what's already available

Before doing anything, look at the homepage. The **Quick Access** section under
**Fusion AI Services** shows you instantly what is registered:

- **Access CAS MCP** — at least one CAS cluster is registered and ready to use
- **Access DCS MCP** — at least one DCS cluster is registered and ready to use
- **watsonx Orchestrate** — at least one WXO instance is registered

If those tiles are there, your services are already registered.
**Click the tile and skip to [Step 2 — Use a service](#step-2--use-a-service).**

If the tiles are not there, your cluster may not be registered yet.
Search the catalog to confirm:

👉 [Browse registered Fusion AI Services](/catalog?filters%5Bkind%5D=component&filters%5Btype%5D=fusion-service)

Type your cluster name in the search box (e.g. `prod-east`, `mycluster`).

- **Found it?** → Skip to [Step 2 — Use a service](#step-2--use-a-service)
- **Not found?** → Your cluster isn't registered yet. Check with your cluster
  administrator to confirm which services are installed, then ask your platform
  engineer to register it — or see the
  [Platform Engineer Guide](platform.md) if that's you.

---

## Step 2 — Use a service

**From the homepage** (easiest)

The **Quick Access** section under **Fusion AI Services** shows only the services
that are actually registered. If you see **Access CAS MCP**, **Access DCS MCP**,
or **watsonx Orchestrate** tiles — click one. It takes you straight to a filtered
catalog view listing all registered instances of that service across every cluster.
Pick your cluster from the list.

**From the catalog**

If you want to browse everything at once:

👉 [Browse all registered Fusion AI Services](/catalog?filters%5Bkind%5D=component&filters%5Btype%5D=fusion-service)

You'll see one entry per registered service per cluster. Click the one you need.

Once you're on the component page, go to the **Links** tab.
Every endpoint is pre-filled — no cluster login, no VPN, no `oc` commands needed.

### What you'll find in the Links tab

**For CAS:**

| Link | What it is |
|---|---|
| CAS Console | The CAS web UI — browse vector stores, monitor jobs |
| Swagger UI | Interactive REST API explorer — try calls directly in the browser |
| MCP (Streamable) | MCP server endpoint for SSE-based AI tools |
| MCP (Standard) | MCP server endpoint for JSON-RPC 2.0 AI tools |
| Health | Health check URL — confirm the service is responding |
| OCP Console | OpenShift console for this cluster |

**For DCS:**

| Link | What it is |
|---|---|
| DCS Console | The Spectrum Discover web UI |
| MCP Endpoint | MCP server endpoint for AI tools |
| MCP HTTP Endpoint | HTTP transport variant |
| MCP SSE Endpoint | SSE transport variant |
| Health | Health check URL |

**For WXO:**

| Link | What it is |
|---|---|
| WXO UI | The watsonx Orchestrate interface for this instance |
| IBM Docs | watsonx Orchestrate product documentation |
| ADK | Agent Developer Kit — build agents that use CAS/DCS as tools |

---

## Step 3 — Connect your AI tool via MCP

CAS and DCS each expose an MCP (Model Context Protocol) server. MCP is an open
standard that lets AI tools — agents, assistants, IDEs — call data operations
as native tools without custom integration code.

Copy the MCP endpoint from the **Links** tab of the catalog component and
configure it in your AI tool. MCP is one way to use these services — direct
REST API calls via the Swagger UI or programmatic HTTP are equally valid.

### CAS MCP tools

Once connected, your AI tool can call:

| Tool | What it does |
|---|---|
| `list_vector_stores` | List all vector stores on this CAS instance |
| `search_vector_stores` | Semantic search across stored documents, files, and images |
| `get_vector_store_file_content` | Retrieve the content of a file from a search result |

📖 [CAS MCP Integration — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-integrating-model-context-protocol-mcp)
· [CAS + watsonx Orchestrate via MCP](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-integrating-watsonx-orchestrate-by-using-mcp)
· [Blog: Bob meets IBM CAS MCP](https://community.ibm.com/community/user/blogs/namita-singroha/2026/03/24/bob-meets-ibm-cas-mcp)

### DCS MCP tools

| Tool | What it does |
|---|---|
| `dcs_file_search` | Search data assets in the catalog |
| `dcs_get_registered_tags` | List all metadata tags |
| `dcs_get_recommend_tags` | AI-suggested tags for a dataset |
| `dcs_create_tag` | Create a new metadata tag |
| `dcs_create_policy` | Define a data governance policy |
| `dcs_get_policies` | List all active governance policies |
| `dcs_set_credentials` | Configure credentials for a data source |

📖 [DCS MCP Server — IBM Docs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=capabilities-data-cataloging-mcp-server)
· [Blog: Explore your data catalog with NLP](https://community.ibm.com/community/user/blogs/paul-llamas-virgen/2026/03/06/exploring-your-fusion-data-catalog-with-nlp)
· [Blog: AI Agents on WXO for DCS](https://community.ibm.com/community/user/blogs/paul-llamas-virgen/2026/03/06/create-your-ai-agents-on-wx-orch-for-data-catalog)

### WXO — build agents that use CAS and DCS

From the WXO catalog entry, open the **WXO UI** link and use the Agent Developer
Kit (ADK) to build agents. You can wire CAS and DCS as MCP tool sources so your
agents can search and govern data directly on your cluster.

📖 [watsonx Orchestrate Docs](https://www.ibm.com/docs/en/watsonx/watson-orchestrate)
· [ADK: Build an Agent](https://developer.watson-orchestrate.ibm.com/ai_builder/creating_agent)

---

## IBM Documentation

- [IBM Fusion Knowledge Center](https://www.ibm.com/docs/en/fusion-software)
- [IBM Fusion HCI Knowledge Center](https://www.ibm.com/docs/en/fusion-hci-systems)
- [IBM Fusion Tech Community](https://ibm.github.io/storage-fusion/fusion-ai/overview/)
- [CAS REST APIs](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=cas-content-aware-storage-apis)
- [IBM Research — 100B Vector Storage for AI](https://research.ibm.com/blog/cas-100-billion-vector-storage-ai)
- [IBM Tech Exchange — Fusion Community](https://community.ibm.com/community/user/groups/community-home/recent-community-blogs?communitykey=e596ba82-cd57-4fae-8042-163e59279ff3)
