# Explore the Developer Hub

> **This handbook has three sections — choose what you need:**
>
> | Section | Go here if... |
> |---|---|
> | **Explore the Developer Hub** ← you are here | You're new here and want to know what this portal offers and where to find things |
> | [Using Fusion AI Services](using-fusion-ai-services.md) | You want to find, access, or connect to a CAS / DCS / WXO service |
> | [Managing the Catalog](managing-the-catalog.md) | You're a platform engineer registering clusters or extending the hub |

---

## What is this portal?

**IBM Fusion Developer Hub** is an internal developer portal built on Red Hat
Developer Hub (Backstage). It gives every developer on your team a single place
to discover platform services, access documentation, run self-service workflows,
and find learning resources — without needing cluster access or hunting for URLs.

This page is a map of everything available. Read it once, then use the nav on
the left to jump to any section.

---

## Homepage

The homepage is your starting point. It has a **Quick Access** panel on the
right with several sections. What appears in each section depends on what your
platform team has enabled.

### Blueprints & Quickstarts

Pre-built solution patterns and step-by-step guides to get started with common
workloads on IBM Fusion.

| Tile | What it leads to |
|---|---|
| Browse NVIDIA Blueprints | Catalog of NVIDIA AI blueprint solutions validated on Fusion |
| Browse Fusion Quickstarts | IBM Fusion quickstart guides in the catalog |
| Browse Red Hat Quickstarts | Red Hat AI learning quickstarts (external link) |

### AI & Platform Services

Self-service capabilities for AI and platform workloads on Fusion.

| Tile | What it leads to |
|---|---|
| Deploy a Model on Fusion | Quickstart guide: Model-as-a-Service (MaaS) on Fusion with GitOps |
| View Deployed Models | Catalog of AI models currently deployed via OpenShift AI |
| Explore All MaaS Tutorials | Learning Paths — full list of MaaS and AI tutorials |
| Explore Self-Service Namespace | Namespace-as-a-Service quickstart guide |

### Fusion AI Services _(appears only when services are registered)_

Links to IBM Fusion AI Services registered in this hub. These tiles only appear
when at least one instance of that service has been registered by your platform team.

| Tile | What it leads to |
|---|---|
| Access CAS MCP | Catalog entries for all registered CAS clusters — get MCP endpoint and API links |
| Access DCS MCP | Catalog entries for all registered DCS clusters — get MCP endpoint and API links |
| watsonx Orchestrate | Catalog entries for all registered WXO instances |

If none of these tiles appear, no Fusion AI Services have been registered yet.
See [Using Fusion AI Services](using-fusion-ai-services.md) or ask your platform team.

### Documentation

Direct links to IBM product documentation.

| Tile | What it leads to |
|---|---|
| Fusion HCI Knowledge Center | IBM Docs for Fusion HCI Systems |
| Fusion SDS Knowledge Center | IBM Docs for Fusion Software-Defined Storage |

### Resources & Community

| Tile | What it leads to |
|---|---|
| Fusion Tech Community | IBM Fusion AI community site |
| IBM Tech Exchange | IBM community blogs and resources |

---

## Catalog

The catalog (`/catalog`) is the central registry of everything known to this
Developer Hub — services, APIs, documentation, and templates.

**Filter by Kind** in the left panel to find what you need:

| Kind | What it contains |
|---|---|
| **Component** | Registered services: Fusion AI services (CAS, DCS, WXO), blueprints, quickstarts, documentation components |
| **API** | OpenAPI specs for CAS and DCS REST APIs |
| **Resource** | AI models deployed via OpenShift AI / RHOAI |
| **Template** | Self-service scaffolding templates (see Create section) |
| **System** | `fusion-ai-services` — groups all Fusion AI service components |
| **Domain** | `IBM Fusion AI Services` — top-level grouping for all Fusion services |
| **Group** | Platform teams: `fusion-platform-team`, `fusion-team` |

**Useful catalog searches:**

| What you're looking for | Filter |
|---|---|
| All Fusion AI services (CAS, DCS, WXO) | Kind: Component, Type: fusion-service |
| NVIDIA AI blueprints | Kind: Component, Type: blueprint |
| Deployed AI models | Kind: Resource, Type: ai-model |
| All documentation components | Kind: Component, Type: documentation |

---

## Create

The Create page (`/create`) lists all self-service templates available in this
hub. Each template walks you through a form and performs an action for you.

| Template | What it does | Who should use it |
|---|---|---|
| **Add IBM Fusion CAS Cluster** | Registers a CAS instance in the catalog with all endpoints auto-derived from the OCP API URL | Platform engineers with a CAS cluster to onboard |
| **Add IBM Fusion DCS Cluster** | Registers a DCS instance in the catalog with all endpoints auto-derived | Platform engineers with a DCS cluster to onboard |
| **Add watsonx Orchestrate Instance** | Registers a WXO instance in the catalog | Platform engineers with WXO installed |
| **Namespace-as-a-Service** _(if enabled)_ | Provisions a new OpenShift namespace with RBAC and quota via GitOps | Developers requesting a dedicated namespace |

> After running a template, open the catalog and find the new entry — go to its
> **Links** tab to get all pre-filled endpoints.

---

## Docs

The Docs section (`/docs`) renders TechDocs — Markdown documentation pulled
directly from Git and rendered here in the portal.

| Documentation | What it covers |
|---|---|
| **IBM Fusion AI Services** ← this handbook | Three-part guide: explore the hub, use services, manage the catalog |
| **IBM Fusion CAS** | CAS architecture, MCP server, REST API reference, onboarding guide, troubleshooting |
| **IBM Fusion DCS** | DCS MCP server, health check, AI agents on WXO, REST API, onboarding, troubleshooting |

Click any **Docs** tab on a catalog component to open its documentation directly.

---

## Learning Paths

The Learning Paths page (`/learning-paths`) is a curated library of tutorials
covering AI workloads, platform services, and tooling on IBM Fusion. Each path
links to a blog post, guide, or IBM Docs article with an estimated time.

### Model-as-a-Service (MaaS)

| Tutorial | Time |
|---|---|
| Getting started with Model-as-a-Service on Fusion | 1 hr |
| Configure subscription-based model governance on Fusion MaaS | 45 min |
| CPU-based LLM inference on Fusion with GitOps | 45 min |
| Build an agentic chat assistant on Fusion AI | 1 hr |
| Registering models from the Model Catalog | 20 min |

### Namespace-as-a-Service (NaaS)

| Tutorial | Time |
|---|---|
| Getting started with Namespace-as-a-Service on Fusion | 1 hr 30 min |

### watsonx Orchestrate

| Tutorial | Time |
|---|---|
| Building agents with the watsonx Orchestrate AI Builder | 25 min |
| Running watsonx Orchestrate Developer Edition locally | 30 min |
| Creating and building AI agents with the watsonx Orchestrate ADK | 30 min |
| Deploying agents in watsonx Orchestrate | 20 min |
| Deploying watsonx.ai and watsonx Orchestrate on Fusion HCI | 1 hr |

### IBM Fusion HCI — AI Infrastructure

| Tutorial | Time |
|---|---|
| AI workloads on IBM Fusion HCI | 25 min |
| GPU servers and sizing on Fusion HCI | 15 min |

### Developer Hub

| Tutorial | Time |
|---|---|
| Getting started with Fusion Developer Hub | 1 hr |

---

## Where to go next

| I want to... | Go to |
|---|---|
| Find and use a Fusion AI Service (CAS, DCS, WXO) | [Using Fusion AI Services](using-fusion-ai-services.md) |
| Register a cluster or extend this hub | [Managing the Catalog](managing-the-catalog.md) |
| Deploy a model on Fusion | Learning Paths → MaaS section |
| Request a namespace | Create → Namespace-as-a-Service template |
| Read CAS or DCS technical docs | Docs → IBM Fusion CAS / DCS |
