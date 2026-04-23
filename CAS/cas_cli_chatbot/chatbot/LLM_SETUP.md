# LLM Setup Feature

## Overview
This feature prompts users to configure an LLM (Large Language Model) provider after they select a vector store during CLI startup. This ensures users can take advantage of LLM-enhanced commands without manual configuration.

## Implementation Details

### New Methods in `ConfigManager` (chatbot/utils/config_manager.py)

#### `has_llm_configured(config: Dict[str, Any]) -> bool`
Checks if at least one LLM provider is properly configured in the config.

**Logic:**
- Checks `llm_provider_sequence` for available providers
- For each provider, validates that credentials/endpoints are not placeholders:
  - **OpenAI**: Checks `openai_api_key` is not empty, not `${...}`, not `sk-YOUR...`
  - **Ollama**: Checks `ollama_host` is not empty, not a placeholder, not default localhost
  - **NVIDIA**: Checks `nvidia_llm_url` is not empty and not a placeholder

**Returns:** `True` if at least one provider is properly configured

#### `prompt_for_llm_setup() -> Dict[str, Any]`
Interactively prompts user to configure an LLM provider.

**Flow:**
1. Displays available providers:
   - OpenAI (requires API key)
   - Ollama (local, requires running instance)
   - NVIDIA NIM (requires endpoint URL)
   - Skip for now
2. Based on selection, prompts for provider-specific configuration
3. Returns dictionary with LLM configuration settings

**Provider-Specific Prompts:**

**OpenAI:**
- API Key (required)
- Model (default: gpt-3.5-turbo)

**Ollama:**
- Host URL (default: http://localhost:11434)
- Model (default: llama3)

**NVIDIA:**
- Endpoint URL (required)
- Model (default: meta/llama3-8b-instruct)

#### `update_llm_config(llm_config: Dict[str, Any])`
Updates the config.yaml file with LLM configuration settings.

### New Methods in `ChatbotCLI` (chatbot/cli/chatbot_cli.py)

#### `_has_valid_llm_config() -> bool`
Wrapper method that uses ConfigManager to check if LLM is configured.

#### `_ensure_llm_configured() -> bool`
Checks whether an LLM provider is configured before running LLM-backed commands.

**Flow:**
1. Checks if LLM is already configured (via `_has_valid_llm_config()`)
2. If configured, returns `True`
3. If not configured, prints a message directing the user to run `llm setup`
4. Returns `False` so the command exits before calling the LLM

#### `cmd_llm_setup() -> None`
CLI command handler that invokes the interactive LLM setup flow on demand.

#### `_prompt_llm_setup() -> None`
Main method that handles the interactive LLM setup flow after vector store selection or when explicitly invoked with `llm setup`.

**Flow:**
1. Checks if LLM is already configured (via `_has_valid_llm_config()`)
2. If already configured, asks whether to use the default configured LLM
3. If the user declines, resets the existing LLM config so a new provider can be configured
4. If not configured, asks user: "Would you like to configure an LLM provider now?"
5. If user declines, shows message explaining they can configure LLM later with `llm setup`
6. If user accepts:
   - Calls `ConfigManager.prompt_for_llm_setup()`
   - Updates config file via `ConfigManager.update_llm_config()`
   - Updates in-memory config
   - Shows success message

**Error Handling:**
- General exceptions: Logs warning and suggests manual configuration

### Integration Point

The LLM setup prompt is called in `run()` after a vector store is successfully selected:

## User Experience Scenarios

### Scenario 1: User with No LLM Configured (Accepts Setup)
```
✓ Using vector store: vs-123

Some commands use an LLM to enhance responses. Would you like to configure an LLM provider now? [y/N]: y

LLM Provider Setup
Some commands use an LLM to enhance responses (e.g., 'query ask').

Available LLM Providers:
  1. OpenAI (requires API key)
  2. Ollama (local, requires running instance)
  3. NVIDIA NIM (requires endpoint URL)
  4. Skip for now

Select provider [1/2/3/4] (4): 1

OpenAI Configuration
OpenAI API Key: sk-...
Model (gpt-3.5-turbo): 
✓ OpenAI configured
✓ LLM configuration saved

✓ LLM configuration complete!
You can now use commands like 'query ask' with LLM enhancement.
```

### Scenario 2: User with No LLM Configured (Declines Setup)
```
✓ Using vector store: vs-123

Some commands use an LLM to enhance responses. Would you like to configure an LLM provider now? [y/N]: n
You can configure LLM later by editing the config.yaml file.
```

### Scenario 3: User with LLM Already Configured
```
✓ Using vector store: vs-123

[No LLM prompt - silently continues]
```

## Configuration Structure

### config.yaml LLM Settings

```yaml
# LLM Provider Configuration
llm_provider_sequence: ["openai"]  # or ["ollama"], ["nvidia"], or multiple

# OpenAI Configuration
openai_api_key: "sk-..."
openai_model: "gpt-3.5-turbo"

# Ollama Configuration
ollama_host: "http://localhost:11434"
ollama_model: "llama3"

# NVIDIA NIM Configuration
nvidia_llm_url: "your-endpoint-url"
nvidia_model: "meta/llama3-8b-instruct"

# LLM Request Configuration
llm_timeout: 60
llm_max_retries: 2
```

## Commands That Use LLM

The following commands require LLM configuration:

1. **`llm query ask`** - Uses LLM to provide enhanced responses based on semantic search results
2. **`llm query file`** - Uses LLM to analyze a specific file from a vector store

When LLM is not configured, these commands do not proceed. Instead, they display a message directing the user to run:

```bash
llm setup
```

## New Command

A dedicated setup command is now available:

- **`llm setup`** - Launches the interactive LLM provider setup flow at any time

This allows users to configure or reconfigure their LLM provider without waiting for the startup prompt.

## Manual Configuration

Users can always configure LLM manually by editing `config.yaml`:

1. Set `llm_provider_sequence` to desired providers (e.g., `["openai"]`)
2. Configure provider-specific settings (API keys, endpoints, models)
3. Save the file and restart the CLI

## Benefits

1. **Seamless Onboarding**: Users are guided to configure LLM right after vector store setup
2. **Non-Intrusive**: Users can skip if they don't need LLM features
3. **Contextual**: Happens when user is already in setup mode
4. **Flexible**: Multiple provider options with sensible defaults
5. **Graceful Degradation**: Commands work without LLM, just without enhancement
6. **Persistent**: Configuration is saved to config.yaml for future sessions

## Technical Notes

- The feature only prompts if no valid LLM configuration exists
- Uses `rich.prompt.Confirm` for yes/no prompts
- Uses `rich.prompt.Prompt` for text input
- Integrates with existing `ConfigManager` for config file updates
- Handles all edge cases gracefully with appropriate user feedback
- Logs debug information for troubleshooting

## Future Enhancements

Potential improvements for future versions:

1. **Validation**: Test provider connectivity before saving configuration
2. **Provider Status**: Show which providers are configured in `config show`
3. **Multiple Providers**: Allow configuring multiple providers in sequence
4. **Environment Variables**: Support for environment variable substitution in prompts