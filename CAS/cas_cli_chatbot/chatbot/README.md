# CAS Chatbot CLI

Technical CLI for exploring and demonstrating the **new CAS vector search API**.

This chatbot is designed to show how to work with CAS vector stores directly from the terminal. The primary workflow is no longer based on the older semantic-search-oriented CAS flow. Instead, this CLI is centered on the **new vector search CAS API**, which returns relevant chunks from a selected vector store and can optionally feed a specific retrieved document into an LLM for follow-up analysis.

## Why this README exists

This README replaces the older positioning of the chatbot as a broad enterprise CLI. The most important thing to know now is:

- the chatbot is a **CAS vector search client**
- it is intended to **show how to use the new CAS API**
- it supports **vector-store-first workflows**
- it can surface **file name and file ID per chunk**
- it can optionally layer on **LLM summarization or question answering for a specific file**
- it is the recommended direction as the **old semantic search CAS API is being deprecated**

## Overview

At a high level, the chatbot does four things:

1. Authenticates to OpenShift / CAS
2. Creates or updates configuration interactively from the terminal at startup
3. Discovers vector stores available in the configured namespace
4. Lets the user query the new CAS vector search API and work from the returned chunks

The key search behavior is implemented in `services/query_service.py`, where the CLI sends a request to:

```text
POST {cas_url}/vector_stores/{vector_store}/search
```

with a payload shaped like:

```json
{
  "query": "What is the recommended PTF for IBM Storage Virtualize 8.5.0?",
  "max_num_results": 5,
  "enable_source": false,
  "enable_content_metadata": false
}
```

The chatbot also supports filtered vector search by including a `filters` object in the same request body.

## Migration note: semantic search is deprecated

If you previously used this chatbot as a client for the older semantic search CAS API, the recommended path is to move to the new vector search API.

### Old direction
- semantic-search-oriented workflows
- less explicit vector-store-first interaction
- older CAS API usage that is being phased out

### New direction
- explicit **vector store selection**
- direct **`/vector_stores/{vector_store}/search`** CAS API usage
- raw chunk retrieval as the first-class operation
- chunk output that includes **file name** and **file ID**
- optional file-specific LLM usage after retrieval, not before
- better alignment with current CAS API capabilities

This README assumes the new model: **search the vector store first, inspect the returned chunks, then optionally refine or summarize from a specific document**.

## Primary capabilities

### CAS vector search
The CLI can query the new CAS vector search endpoint and return the most relevant chunks from the active vector store.

### Chunk-level source visibility
Search results can show the source file name and file ID for each returned chunk. This is useful because relevant chunks may come from different files, and the user can decide which source to inspect further.

### Filtered vector search
The CLI can submit the same query with filter criteria, allowing more precise retrieval when the API supports those filters.

### File-level follow-up workflows
After finding relevant chunks, the user can retrieve file content or run an LLM-assisted file query against a specific document.

### Interactive configuration at startup
The chatbot can create or update `config.yaml` from the terminal when it starts. The project is moving away from requiring users to manually hand-edit configuration before first use.

### Optional LLM enhancement
The chatbot can call an LLM provider after retrieval to help summarize or answer questions based on a specific retrieved file. This is optional and not required for raw vector search.

## Additional Resources

### CAS Data Source Configuration
For information on how to create a data source and connect it to a domain/vector store for searching, refer to the official IBM documentation:

**[Configuring Content Aware Storage (CAS)](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.x?topic=cas-configuring-content-aware-storage)**

This guide covers:
- Creating and configuring CAS data sources
- Connecting data sources to domains/vector stores
- Setting up the infrastructure needed for vector search operations

## Prerequisites

- Python 3.8+
- OpenShift CLI (`oc`) installed and configured
- Network access to the target OpenShift / CAS environment
- Valid credentials for OpenShift / CAS authentication
- Optional: credentials or endpoints for one or more LLM providers

## Repository location

From the main repository:

```bash
cd CAS/cas_cli_chatbot/chatbot
```

## Setup

### 1. Create a virtual environment

```bash
python3 -m venv venv
source venv/bin/activate
```

### 2. Install dependencies

```bash
pip3 install -r requirements.txt
```

### 3. Start the chatbot and configure from the terminal

Do **not** treat manual `config.yaml` editing as the primary setup path.

Start the chatbot:

```bash
python3 main.py
```

On startup, the chatbot uses the interactive configuration flow in `utils/config_manager.py` to:

- detect whether `config.yaml` already exists
- prompt for OpenShift credentials if needed
- prompt for CAS API settings
- create `config.yaml` from `config.yaml.sample` when no config exists
- update stored configuration if the current config is incomplete or the user chooses to replace it

This is the preferred configuration path.

### Configuration reference

If you need to understand available settings, use these files as the source of truth:

- `config.yaml.sample`
- `utils/config_manager.py`
- `LLM_SETUP.md`

For environment-specific configuration details and CAS data source setup, refer to the [Additional Resources](#additional-resources) section above.

## Configuration behavior

The sample file is `config.yaml.sample`, but the preferred user experience is to let the chatbot create or update `config.yaml` interactively at startup.

### What the startup configuration flow currently prompts for

Based on `ConfigManager.prompt_for_credentials()`:

- OpenShift console URL
- OpenShift username
- OpenShift password
- CAS API URL
- CAS namespace

The tool also attempts to auto-generate a CAS API URL from the OpenShift console URL and asks the user whether to accept it.

### Recommended vector search settings

These options map directly to the vector search request body used by the CLI:

```yaml
enable_source: true
enable_content_metadata: true
default_limit: 5
```

In `QueryService.query_vector_store()`, the request payload includes:

- `query`
- `max_num_results`
- `enable_source`
- `enable_content_metadata`

In `QueryService.query_with_filters()`, the same payload is used with an additional:

- `filters`

### Optional LLM configuration

If you want LLM-assisted follow-up after retrieval, configure one or more LLM providers. The project already supports interactive LLM setup logic as documented in `LLM_SETUP.md`.

Example settings present in `config.yaml.sample` include:

```yaml
llm_provider_sequence: ["nvidia", "openai", "ollama"]

openai_api_key: "${OPENAI_API_KEY:}"
openai_model: "gpt-3.5-turbo"

nvidia_llm_url: "<nvidia-endpoint>"
nvidia_model: "meta/llama3-8b-instruct"
ngc_api_key: "<your-ngc-api-key>"

ollama_host: "http://localhost:11434"
ollama_model: "llama3"
```

Use environment variables for secrets where possible.

```bash
export OPENAI_API_KEY="sk-..."
export OC_PASSWORD="your-password"
```

## How startup works

The CLI is intentionally **vector-store-first**.

When the application starts, it authenticates, checks service health, and then guides the user toward selecting a vector store. This behavior is documented in `VECTOR_STORE_STARTUP_SELECTION.md`.

Startup flow:

1. Start `python3 main.py`
2. Create or update configuration interactively if needed
3. Validate configuration
4. Authenticate with OpenShift / CAS
5. Run health checks
6. Display available vector stores
7. Check whether `default_vector_store` is configured
8. If accessible, allow the user to use it immediately
9. Otherwise, let the user select an accessible vector store interactively
10. Optionally prompt for LLM configuration if none exists

This matters because all meaningful search operations depend on having an active vector store.

## Running the CLI

From the `chatbot/` directory:

```bash
python3 main.py
```

## Core CLI commands

The command set is defined in `cli/chatbot_cli.py`.

### Vector store commands

```bash
vector stores list
vector stores select
vector stores info
```

Use these commands to inspect what is available and to set the active vector store.

### Vector search commands

```bash
vector search
vector search filter
show file content
```

These commands are the core of the new CAS API workflow.

### LLM-assisted query commands

```bash
llm query ask
llm query file
```

These are optional follow-up workflows after retrieval.

### Query history and session commands

```bash
query history
query export
session view
session history
session stats
session export
session clear
```

### System and troubleshooting commands

```bash
config show
config reload
metrics
health
help
clear
exit
quit
```

## Recommended usage model

The recommended mental model for this chatbot is:

1. select a vector store
2. run vector search
3. inspect returned chunks, including file names and file IDs
4. either narrow the same question with a filter or target a specific file
5. optionally use an LLM for a quick answer grounded in that file

That is the core behavior this README is documenting and that the CLI is intended to demonstrate.

## End-to-end workflow: raw vector search first

This is the primary workflow the chatbot is meant to showcase.

```bash
# Start the CLI
python3 main.py

# View available vector stores
vector stores list

# Select a vector store
vector stores select
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

Chunk 1: [filename: storage-virtualize-release-notes.pdf] [file ID: 1234567]
<chunk text from that file>

Chunk 2: [filename: support-matrix.pdf] [file ID: 8901234]
<chunk text from a different file>
```

The important point is that **file name and file ID may vary from chunk to chunk**. This lets the user see exactly which documents are contributing to the result set.

## End-to-end workflow: ask the same question again with a filter

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

> Note: the exact filter keys supported by your CAS environment may vary. Replace `file_name` with the correct field if your deployment uses a different filter key.

## End-to-end workflow: target one file with `llm query file`

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

### Why this matters

This pattern is one of the best demonstrations of the new CAS API flow:

1. use **vector search** to discover relevant chunks
2. observe **file name + file ID** for each chunk
3. use **vector search filter** to focus on a specific file if needed
4. use **llm query file** with the selected file ID for a targeted answer

That is both technically clear and operationally useful.

## CAS API behavior used by this CLI

The technical heart of this chatbot is the new vector search endpoint.

### Search endpoint

```text
POST {cas_url}/vector_stores/{vector_store}/search
```

### Headers

```http
Authorization: Bearer <token>
Content-Type: application/json
```

### Request body used by `query_vector_store()`

```json
{
  "query": "<user query>",
  "max_num_results": 5,
  "enable_source": false,
  "enable_content_metadata": false
}
```

### Request body used by `query_with_filters()`

```json
{
  "query": "<user query>",
  "filters": {
    "key": "<field>",
    "type": "eq",
    "value": "<value>"
  },
  "max_num_results": 5,
  "enable_source": false,
  "enable_content_metadata": false
}
```

### Notes

- the bearer token comes from the authentication service
- the active vector store is either selected interactively or taken from `default_vector_store`
- request timeout is controlled by `request_timeout`
- TLS verification behavior depends on `allow_self_signed`

## Operational notes

### Authentication
The CLI requires a valid bearer token before vector store listing or search operations will succeed.

### Accessible vector stores
The CLI distinguishes between:
- all vector stores in the namespace
- vector stores the current user can access

A vector store may exist but still not be usable if the current user lacks access.

### Caching
Query and vector store lookups may be cached depending on configuration.

### Health checks
Use the `health` command to inspect the state of configured services.

## Troubleshooting

### I expected to edit `config.yaml` manually
That is no longer the preferred path. Start the chatbot and use the interactive setup flow first. Review `config.yaml.sample`, `utils/config_manager.py`, and `LLM_SETUP.md` for configuration reference.

### No vector stores appear
Possible causes:
- wrong `cas_namespace`
- OpenShift access issue
- no vector stores deployed in the namespace
- failed authentication

### Authentication succeeds but search fails
Check:
- `cas_url`
- whether the token is valid
- whether the user has access to the selected vector store
- network / TLS settings such as `allow_self_signed`

### No results are returned
This usually means:
- the query is too broad or too specific
- the selected vector store does not contain relevant content
- filter criteria are too restrictive

Try:
- changing query wording
- increasing `default_limit`
- enabling source and content metadata
- switching vector stores
- using the first search to identify a likely file, then applying a filter

### LLM commands do not work
Raw vector search does not require LLM configuration, but LLM-assisted commands do. Configure at least one provider in `config.yaml` or through the startup LLM setup flow if enabled.

## Files worth reading

- `README.md` - this document
- `config.yaml.sample` - configuration reference
- `VECTOR_STORE_STARTUP_SELECTION.md` - startup selection behavior
- `LLM_SETUP.md` - optional LLM configuration flow
- `utils/config_manager.py` - interactive configuration behavior
- `services/query_service.py` - CAS vector search request logic
- `cli/chatbot_cli.py` - CLI commands and interaction model

## Summary

This chatbot should be understood as a **technical demonstration client for the new CAS vector search API**.

Use it when you want to:

- configure the tool interactively from the terminal
- authenticate to CAS
- select a vector store
- run direct vector search requests
- inspect raw retrieved chunks
- see the file name and file ID associated with each chunk
- apply filters to focus on a specific source
- pass a specific file into an LLM workflow for a quick answer

If you are moving away from the deprecated semantic search approach, this CLI demonstrates the current CAS search model: **retrieve first, inspect sources, refine, then optionally summarize with an LLM**.