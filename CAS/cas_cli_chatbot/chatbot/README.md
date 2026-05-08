# CAS Chatbot CLI

Technical CLI for exploring and demonstrating the **CAS vector search API**.

For project-level setup, dependency installation, and test execution, start with [`../README.md`](../README.md). This document focuses on CLI behavior, commands, and CAS workflows.

This chatbot is designed to show how to work with CAS vector stores directly from the terminal. The CLI is centered on the **CAS vector search API**, which returns relevant chunks from a selected vector store and can optionally feed a specific retrieved document into an LLM for follow-up analysis.

## Overview

At a high level, the chatbot does four things:

1. Authenticates to OpenShift / CAS
2. Creates or updates configuration interactively from the terminal at startup
3. Discovers vector stores available in the configured namespace
4. Lets the user query the CAS vector search API and work from the returned chunks

The key search behavior is implemented in `services/query_service.py`, where the CLI sends a request to:

```text
POST {cas_url}/vector_stores/{vector_store}/search
```

with a payload shaped like:

```json
{
  "query": "What is the recommended PTF for IBM Storage Virtualize 8.5.0?",
  "max_num_results": 5,
  "enable_source": true,
  "enable_content_metadata": true
}
```

The chatbot also supports filtered vector search by including a `filters` object in the same request body.

## Primary Capabilities

### CAS Vector Search
The CLI can query the CAS vector search endpoint and return the most relevant chunks from the active vector store.

### Chunk-Level Source Visibility
Search results shows the source file name, file ID, and other metadata for each returned chunk. This is useful because relevant chunks may come from different files, and the user can decide which source to inspect further.

### Filtered Vector Search
The CLI can submit the same query with filter criteria, allowing more precise retrieval when the API supports those filters.

### File-Level Follow-Up Workflows
After finding relevant chunks, the user can retrieve file content or run an LLM-assisted file query against a specific document.

### Interactive Configuration at Startup
The chatbot can create or update `config.yaml` from the terminal when it starts.

### Optional LLM Enhancement
The chatbot can call an LLM provider after retrieval to help summarize or answer questions based on a specific retrieved file. This is optional and not required for raw vector search.

## Core CLI Commands

### Vector Store Commands

```bash
vector stores list
vector stores select
vector stores info users
vector stores info files
```

Use these commands to inspect what is available and to set the active vector store.

### Vector Search Commands

```bash
vector search
vector search filter
show file content
```

These commands are the core of the CAS API workflow.

### LLM-Assisted Query Commands

```bash
llm query ask
llm query file
llm setup
```

These are optional follow-up workflows after retrieval.

### Query History and Session Commands

```bash
query history
session info
session export
session clear
```

### System and Troubleshooting Commands

```bash
config show
metrics
health
help
clear
exit
```

## Recommended Usage Model

The recommended mental model for this chatbot is:

1. Select a vector store
2. Run vector search
3. Inspect returned chunks, including their metadata
4. Either narrow the same question with a filter or target a specific file
5. Optionally use an LLM for a quick answer grounded in that file

That is the core behavior this README is documenting and that the CLI is intended to demonstrate.

## End-to-End Workflow: Raw Vector Search First

This is the primary workflow the chatbot is meant to showcase.

```bash
# Start the CLI
python3 main.py

# View available vector stores
vector stores list

# Select a vector store
vector stores select <store_name>
```

Example interactive selection:

```text
Select vector store/domain (type to search): vs-123
✓ Selected vector store: vs-123
```

Run a search:

```bash
vector search
```

Example prompt:

```text
[admin@vs-123] Enter your query: What is the recommended PTF for IBM Storage Virtualize long term support release 8.5.0?
```

At this point, the CLI sends a request to:

```text
POST /vector_stores/vs-123/search
```

and displays matching chunks returned by the CAS API.

A typical result display can include source information per chunk, for example:

```text
Retrieving text chunks...

Chunk 1: 
  [filename: storage-virtualize-release-notes.pdf] 
  [file ID: 1234567]
  ...
<chunk text from that file>

Chunk 2: 
  [filename: support-matrix.pdf] 
  [file ID: 8901234]
  ...
<chunk text from a different file>
```

The important point is that **file name and file ID may vary from chunk to chunk**. This lets the user see exactly which documents are contributing to the result set.

## End-to-End Workflow: Ask the Same Question Again with a Filter

After vector search reveals which file looks most relevant, the user can run the same question again with a filter to focus on one source.

For example, imagine raw vector search returned:

- `storage-virtualize-release-notes.pdf` with file ID `1234567`
- `support-matrix.pdf` with file ID `8901234`

Now the user can run:

```bash
vector search filter
```

Then enter:

```text
Query: What is the recommended PTF for IBM Storage Virtualize long term support release 8.5.0?
Filter key: file_name
Filter type: eq
Filter value: storage-virtualize-release-notes.pdf
```

Conceptually, the request body becomes:

```json
{
  "query": "What is the recommended PTF for IBM Storage Virtualize long term support release 8.5.0?",
  "filters": {
    "key": "file_name",
    "type": "eq",
    "value": "storage-virtualize-release-notes.pdf"
  },
  "max_num_results": 5,
  "enable_source": true,
  "enable_content_metadata": true
}
```

This is useful when the first vector search shows a promising file and the user wants more chunks specifically from that file.

## End-to-End Workflow: Target One File with `llm query file`

Once vector search has shown the user a promising source document, they can use that exact document as LLM input.

Run:

```bash
llm query file
```

The CLI then prompts for:

- vector store ID
- file ID
- query text

Example:

```text
[admin@vs-123] Enter the vector store ID (might be same as vector store name): vs-123
[admin@vs-123] Enter the file ID: 1234567
[admin@vs-123] Enter your query: What is the recommended PTF for IBM Storage Virtualize long term support release 8.5.0?
```

This workflow lets the user feed **that particular document** to the LLM and get a quick answer, instead of asking the LLM to reason over the entire result set.

### Why This Matters

This pattern is one of the best demonstrations of the CAS API flow:

1. Use **vector search** to discover relevant chunks
2. Observe **file name + file ID** for each chunk
3. Use **vector search filter** to focus on a specific file if needed
4. Use **llm query file** with the selected file ID for a targeted answer

That is both technically clear and operationally useful.

### Notes

- The bearer token comes from the authentication service
- The active vector store is either selected interactively or taken from `default_vector_store` in the `config.yaml` if it already exists

## Operational Notes

### Authentication
The CLI requires a valid bearer token before vector store listing or search operations will succeed.

### Accessible Vector Stores
The CLI distinguishes between:
- All vector stores in the namespace
- Vector stores the current user can access

A vector store may exist but still not be usable if the current user lacks access.

### Caching
Query and vector store lookups may be cached depending on configuration.

### Health Checks
Use the `health` command to inspect the state of configured services.

## Files Worth Reading

- `README.md` - this document
- `GETTING_STARTED.md` - deployment and configuration instructions
- `config.yaml.sample` - configuration reference
- `VECTOR_STORE_STARTUP_SELECTION.md` - startup selection behavior
- `LLM_SETUP.md` - optional LLM configuration flow
- `utils/config_manager.py` - interactive configuration behavior
- `services/query_service.py` - CAS vector search request logic
- `cli/chatbot_cli.py` - CLI commands and interaction model

## Summary

This chatbot should be understood as a **technical demonstration client for the CAS vector search API**.

Use it when you want to:

- Configure the tool interactively from the terminal
- Authenticate to CAS
- Select a vector store
- Run direct vector search requests
- Inspect raw retrieved chunks
- See the metadata, such as file name and file ID, associated with each chunk
- Apply filters to focus on specific sources
- Pass a specific file into an LLM workflow for a quick answer

The CLI demonstrates the CAS search model: **retrieve first, inspect sources, refine, then optionally summarize with an LLM**.

---

## Getting Started

For CLI setup and configuration details, see [GETTING_STARTED.md](GETTING_STARTED.md).

For project-level installation, environment setup, and test commands, see [`../README.md`](../README.md) and [`../tests/README.md`](../tests/README.md).