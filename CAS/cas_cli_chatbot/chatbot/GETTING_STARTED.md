# Getting Started with CAS Chatbot CLI

This guide provides step-by-step instructions for deploying and configuring the CAS Chatbot CLI.

## Prerequisites

Before you begin, ensure you have:

- Python 3.8 or higher installed
- OpenShift CLI (`oc`) installed and configured
- Network access to the target OpenShift / CAS environment
- Valid credentials for OpenShift / CAS authentication
- Optional: credentials or endpoints for one or more LLM providers (if you want LLM-assisted features)

## Repository Location

Run setup from the `cas_cli_chatbot` project root.

## Quick Start

### 1. Create a Virtual Environment

```bash
python3 -m venv venv
source venv/bin/activate
```

### 2. Install Dependencies

```bash
pip install -r requirements.txt
```

### 3. Start the Chatbot

From the project root, run:

```bash
cd CAS/cas_cli_chatbot/chatbot
python3 main.py
```

The chatbot will guide you through the setup process interactively!

## Configuration Options

You have two ways to configure the chatbot:

### Option 1: Interactive Setup (Recommended)

When you first start the chatbot with `python3 main.py`, it will automatically:

1. Check if a `config.yaml` file exists
2. If not, guide you through creating one by prompting for:
   - **OpenShift console URL** - The URL of your OpenShift console
   - **OpenShift username** - Your OpenShift username
   - **OpenShift password** - Your OpenShift password
   - **CAS API URL** - The CAS API endpoint URL (can be auto-generated)
   - **CAS namespace** - The namespace where CAS is deployed
3. Create the `config.yaml` file automatically
4. Continue to the chatbot interface

The tool will also attempt to auto-generate a CAS API URL from your OpenShift console URL and ask if you want to use it.

**This is the easiest way to get started!**

### Option 2: Manual Configuration

If you prefer to manually configure settings or need to update existing configuration:

1. Copy the sample configuration file if there is no existing config.yaml file:
   ```bash
   cp config.yaml.sample config.yaml
   ```

2. Edit `config.yaml` with your preferred text editor:
   ```bash
   nano config.yaml
   # or
   vim config.yaml
   ```

3. Update the following required settings:
   ```yaml
   openshift:
     console_url: "https://your-openshift-console.com"
     username: "your-username"
     password: "your-password"
   
   cas:
     api_url: "https://your-cas-api.com"
     namespace: "your-namespace"
   ```

4. Save the file and start the chatbot:
   ```bash
   python3 main.py
   ```

**Note:** You can always re-run the interactive setup by declining to use the existing config.yaml upon startup or manually deleting the config.yaml file and restart the chatbot.

### Recommended Vector Search Settings

These options map directly to the vector search request body used by the CLI. You can configure them in `config.yaml`:

```yaml
enable_source: true
enable_content_metadata: true
default_limit: 5
```

These settings control:
- `enable_source` - Whether to include source file information in results
- `enable_content_metadata` - Whether to include content metadata
- `default_limit` - Default number of results to return (max_num_results)

### Optional LLM Configuration

If you want LLM-assisted follow-up after retrieval, configure one or more LLM providers. The project supports interactive LLM setup logic as documented in `LLM_SETUP.md`.

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

### Using Environment Variables for Secrets

Use environment variables for sensitive information:

```bash
export OPENAI_API_KEY="sk-..."
export OC_PASSWORD="your-password"
```

### Configuration Reference Files

If you need to understand available settings, use these files as the source of truth:

- `config.yaml.sample` - Sample configuration with all available options
- `utils/config_manager.py` - Interactive configuration behavior
- `LLM_SETUP.md` - LLM provider configuration details

## CAS Data Source Configuration

For information on how to create a data source and connect it to a domain/vector store for searching, refer to the official IBM documentation:

**[Configuring Content Aware Storage (CAS)](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.x?topic=cas-configuring-content-aware-storage)**

This guide covers:
- Creating and configuring CAS data sources
- Connecting data sources to domains/vector stores
- Setting up the infrastructure needed for vector search operations

## How Startup Works

The CLI is intentionally **vector-store-first**.

When the application starts, it authenticates, checks service health, and then guides the user toward selecting a vector store. This behavior is documented in `VECTOR_STORE_STARTUP_SELECTION.md`.

### Startup Flow

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

Once started, you can use any of the available commands. Type `help` to see all available commands.

## Using the Chatbot

After starting the chatbot, you'll have access to a comprehensive set of commands organized by functionality.

### Getting Help

```bash
help                    # Display all available commands
```

### Vector Store Commands

Before you can search, you need to select a vector store:

```bash
vector stores list          # List all available vector stores in your namespace
vector stores select        # Interactively select a vector store to use
vector stores info users    # Show user assignments and access for the selected vector store
vector stores info files    # Show file counts, bytes, and storage details from CAS API
```

**Example workflow:**
```bash
[admin] vector stores list
# Review the available vector stores
[admin] vector stores select
# Choose a vector store from the interactive menu
[admin@vs-123] vector stores info users
# View user access information
```

### Vector Search Commands

These are the core commands for searching your vector store:

```bash
vector search           # Search the selected vector store with a query
vector search filter    # Search with filter criteria (e.g., by file name)
show file content       # Display the content of a specific file from the vector store
```

**Example: Basic search**
```bash
[admin@vs-123] vector search
Enter your query: What is the recommended PTF for IBM Storage Virtualize 8.5.0?
```

**Example: Filtered search**
```bash
[admin@vs-123] vector search filter
Query: What is the recommended PTF for IBM Storage Virtualize 8.5.0?
Filter key: file_name
Filter type: eq
Filter value: storage-virtualize-release-notes.pdf
```

### LLM-Assisted Query Commands

Optional commands that use LLM providers for enhanced responses:

```bash
llm query ask           # Ask a question using LLM with vector search context
llm query file          # Query a specific file using LLM
```

**Example: Query a specific file**
```bash
[admin@vs-123] llm query file
Enter the vector store ID: vs-123
Enter the file ID: 1234567
Enter your query: Summarize the key features in this document
```

### Query History and Session Commands

Track and manage your search history:

```bash
query history           # View your recent queries
session info            # Show comprehensive session information
session export          # Export session data
session clear           # Clear current session data
```

### System and Configuration Commands

Manage configuration and check system status:

```bash
config show             # Display current configuration
metrics                 # Show performance metrics
health                  # Check health status of all services
clear                   # Clear the terminal screen
exit                    # Exit the chatbot
```

### Typical Usage Flow

Here's a recommended workflow for new users:

1. **Start the chatbot**
   ```bash
   python3 main.py
   ```

2. **Check available vector stores**
   ```bash
   vector stores list
   ```

3. **Select a vector store**
   ```bash
   vector stores select
   ```

4. **Run your first search**
   ```bash
   vector search
   ```

5. **Review the results** - Note the file names and file IDs in the results

6. **Refine your search** (optional)
   - Use `vector search filter` to focus on a specific file
   - Use `llm query file` to get an LLM-assisted answer from a specific document

7. **Check your history**
   ```bash
   query history
   ```

### Tips for Effective Searching

- **Enable source information**: Set `enable_source: true` in your config to see which files chunks come from
- **Use filters strategically**: After a broad search reveals relevant files, use filters to focus on specific sources
- **Adjust result limits**: Increase `default_limit` if you need more results
- **Try different query phrasings**: If you don't get good results, rephrase your question
- **Use file-specific queries**: Once you identify a relevant file, use `llm query file` for targeted questions

## Troubleshooting

### No Vector Stores Appear

Possible causes:
- Wrong `cas_namespace` configured
- OpenShift access issue
- No vector stores deployed in the namespace
- Failed authentication

**Solution:** Verify your namespace configuration and ensure you have proper access to the OpenShift cluster.

### Authentication Succeeds but Search Fails

Check:
- `cas_url` is correct
- The token is valid
- The user has access to the selected vector store
- Network / TLS settings such as `allow_self_signed`

**Solution:** Use the `health` command to check service status and verify your CAS API URL.

### No Results Are Returned

This usually means:
- The query is too broad or too specific
- The selected vector store does not contain relevant content
- Filter criteria are too restrictive

Try:
- Changing query wording
- Increasing `default_limit`
- Enabling source and content metadata
- Switching vector stores
- Using the first search to identify a likely file, then applying a filter

### LLM Commands Do Not Work

Raw vector search does not require LLM configuration, but LLM-assisted commands do. Configure at least one provider in `config.yaml` or through the startup LLM setup flow if enabled.

**Solution:** Follow the LLM configuration steps in `LLM_SETUP.md` or use the interactive LLM setup during startup.

### Connection or TLS Errors

If you encounter TLS/SSL certificate errors:

1. Check if your environment uses self-signed certificates
2. Set `allow_self_signed: true` in your `config.yaml`
3. Verify network connectivity to the CAS API endpoint

### Token Expiration

If you receive authentication errors during a session:

1. The bearer token may have expired
2. Restart the CLI to re-authenticate
3. Check your OpenShift credentials are still valid

## Next Steps

Once you have the chatbot running:

1. Use `vector stores list` to see available vector stores
2. Use `vector stores select` to choose a vector store
3. Use `vector search` to run your first query
4. Explore other commands with `help`

For detailed usage examples and workflows, see the package guide [README.md](README.md) and the project root guide [`../README.md`](../README.md).

## Additional Resources

- [README.md](README.md) - Overview and usage examples
- [config.yaml.sample](config.yaml.sample) - Configuration reference
- [VECTOR_STORE_STARTUP_SELECTION.md](VECTOR_STORE_STARTUP_SELECTION.md) - Startup selection behavior
- [LLM_SETUP.md](LLM_SETUP.md) - Optional LLM configuration flow
- [IBM CAS Documentation](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.x?topic=cas-configuring-content-aware-storage) - Official CAS configuration guide