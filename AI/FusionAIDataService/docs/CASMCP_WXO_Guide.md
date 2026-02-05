# Overview:

LLMs are powerful, but without access to enterprise data, they're flying blind. They can reason, generate text, and answer questions — but they can't tap into the knowledge bases, vector stores, and proprietary data that drive real business decisions. That's the gap we're solving today.

In this guide, I'll walk you through integrating IBM Content-Aware Storage (CAS) with watsonx Orchestrate using the Model Context Protocol (MCP). The result? An AI agent that can seamlessly search enterprise vector stores and return accurate, context-aware answers — no custom APIs, no complex integrations.

IBM's Watsonx Orchestrate orchestrates workflows using AI agents. With MCP support, Orchestrate can now discover and use CAS vector stores conversationally — no custom integration code required.

An end-to-end demo of this integration is available as a YouTube video here.

## Prerequisites:

Before starting, ensure the following are in place:

- Watsonx Orchestrate instance — An active Orchestrate deployment with CLI access. If you haven't set this up yet, follow this official installation guide.
- Add a model to your Orchestrate Deployment — To run AI agents that query CAS, make sure your instance has a model configured. Follow these steps to add model.
- IBM Fusion instance with CAS deployed — CAS instance running on OpenShift. Visit for installation steps.
- CAS authentication token — Bearer token for API access.
- CAS route URL — OpenShift route where CAS is accessible , for example: https://<console-ibm-spectrum-fusion-ns.apps.openshifturl>
- Network connectivity — The watsonx Orchestrate instance must have network access to the CAS server route.

## Configuration Steps:

### Step 1: Set Up the watsonx Orchestrate CLI Environment

The watsonx Orchestrate CLI allows you to manage MCP servers, toolkits, and agents directly from your terminal.

#### 1.1 Install the watsonx Orchestrate CLI

Download and install the CLI for your operating system (macOS, Linux, or Windows)

watsonx Orchestrate CLI installation guide: https://developer.watson-orchestrate.ibm.com/getting_started/installing

Verify installation: orchestrate --version

#### 1.2 Set up Python virtual environment (recommended):
```bash
python3 -m venv orchestrate-env
source orchestrate-env/bin/activate  # On Windows: orchestrate-env\Scripts\activate
```

You'll need watsonx Orchestrate instance URL & its credentials (username/password) later.

### Step 2: Configure Orchestrate Environment

Get your Orchestrate instance URL from Profile Settings in the Orchestrate Dashboard.
```bash
# Add your Orchestrate environment
orchestrate env add -n wxo-instance -u <your-orchestrate-url>

# Activate the environment
orchestrate env activate wxo-instance
```

**Note** You'll be prompted for credentials—enter your Orchestrate username and password.

### Step 3: Prepare the CAS Server URL

Retrieve the CAS route from your OpenShift dashboard. To help you locate the route, here's a screenshot of the OpenShift dashboard showing the CAS route:

Press enter or click to view image in full size

Add "/cas/api/v1/mcp-streamable/" in end of the Route. Example — "https://<cas-route>/cas/api/v1/mcp-streamable/"

### Step 4: Register CAS MCP Server

Add the CAS MCP server as a toolkit in watsonx Orchestrate:
```bash
orchestrate toolkits add \
  --kind mcp \
  --name cas \
  --description "MCP server for CAS vector stores" \
  --url <your-cas-mcp-url> \
  --transport streamable_http \
  --tools "search_vector_stores,list_vector_stores"
```

This command registers the CAS MCP server and makes both tools available to Orchestrate agents.

Become a member

### Step 5: Create and Configure Agent

1. Access Orchestrate UI

   - Navigate to your watsonx Orchestrate dashboard
   - Click "Create Agent"



   <img width="1694" alt="Screenshot 2026-01-22 at 4 27 23 PM" src="https://github.ibm.com/user-attachments/assets/b6be7d70-7e2e-417e-a410-54b8b8cbbdc0" />


2. Add MCP Tools

   - In agent configuration, select "Add Tools"




<img width="1660" alt="Screenshot 2026-01-22 at 4 28 02 PM" src="https://github.ibm.com/user-attachments/assets/1d59fc1a-4fb9-46bd-8e69-1878581f89fc" />





   - Choose tools from "cas-vector-search" toolkit
   - Select both list_vector_stores and search_vector_stores




<img width="1651" alt="Screenshot 2026-01-22 at 4 28 19 PM" src="https://github.ibm.com/user-attachments/assets/7b97c94a-9e26-46d4-80ff-2ace01a188d8" />




3. Save Configuration & Deploy Agent


<img width="1659" alt="Screenshot 2026-01-22 at 4 28 43 PM" src="https://github.ibm.com/user-attachments/assets/20d9b6f9-6cb1-4d7c-95f8-17eccb808636" />






## Validation

— Tool Listing after registering MCP Server

<img width="1664" alt="Screenshot 2026-01-22 at 4 29 01 PM" src="https://github.ibm.com/user-attachments/assets/be9f991a-58cc-4c3a-8fd6-97324ee2a8c7" />






— Verify Tool Execution

Once deployed, test the agent with natural language queries:

Example prompts:

- "What vector stores are available in CAS?"
- "Find documents about installation guides"

Provide URL and token as prompted by agent in chat.

<img width="1464" alt="Screenshot 2026-01-22 at 4 29 20 PM" src="https://github.ibm.com/user-attachments/assets/f6db0da6-f854-45c4-9991-a6dd207dff61" />




<img width="1721" alt="Screenshot 2026-01-22 at 4 29 30 PM" src="https://github.ibm.com/user-attachments/assets/a5b3fa8e-649b-46af-9938-f4ccb0fc46c1" />



## What You've Accomplished

You've successfully connected IBM CAS to watsonx Orchestrate, enabling AI agents to query enterprise vector stores directly through natural language. With this integration, you can:

- Run agentic workflows — Let Orchestrate autonomously retrieve and act on enterprise knowledge.
- Leverage RAG pipelines — Seamlessly connect MCP-compatible AI agents to CAS vector stores.
- Avoid custom code — Orchestrate handles the connection and workflow orchestration for you.

## Key Takeaways

- watsonx Orchestrate makes enterprise data conversational — no manual API glue needed.
- CAS vector stores become agent-ready — your AI agents can access and reason over enterprise knowledge.

## Explore further:

- For details on IBM Fusion, please refer our [product page](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.0?topic=capabilities-fusion-services)
- For more protocol details and implementation examples, visit our [official page](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.0?topic=cas-integrating-model-context-protocol-mcp)
- Learn more about MCP and CAS architecture [here](https://medium.com/@singrohanamita/from-rest-apis-to-conversational-ai-how-mcp-makes-ibm-cas-talk-to-your-ai-agents-5478cd584ca5)
- An end-to-end demo of this integration is available as a YouTube video [here](https://www.youtube.com/watch?v=XMYs0Qe-9Fk)

