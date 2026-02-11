# CAS CLI Chatbot v1.0.0

An enhanced enterprise-grade chatbot for Content-Aware Storage (CAS) systems with advanced features, robust error handling, and comprehensive logging.

##  Features

### Core Capabilities
- **Semantic Search Integration**: Query CAS tables using natural language
- **Multi-LLM Support**: OpenAI, Ollama, and NVIDIA LLM providers
- **Interactive CLI**: Rich terminal interface with auto-completion
- **Session Management**: Persistent history and auto-suggestions
- **Authentication**: Secure OpenShift integration
- **Real-time Monitoring**: Health checks and service validation

### Enhanced Features
- **Smart Command Recognition**: Fuzzy matching for commands
- **Export Functionality**: Save chat history to JSON
- **Session Statistics**: Track usage and performance metrics
- **Table Management**: Easy switching between data tables
- **Comprehensive Logging**: File and console logging with different levels
- **Error Recovery**: Graceful handling of network and API failures

## 📋 Requirements

### System Requirements
- Python 3.10 or higher
- OpenShift CLI (`oc` command)
- Access to CAS-enabled OpenShift cluster
- Internet connection for LLM providers

### Python Dependencies
```bash
# Core dependencies
requests>=2.31.0
PyYAML>=6.0
prompt-toolkit>=3.0.36
rich>=13.3.5
openai>=1.3.0

# Optional dependencies for enhanced features
difflib  # Built-in Python module
argparse # Built-in Python module
logging  # Built-in Python module
```

## Installation

### 1. Clone or Download Files

```bash
# Create project directory
mkdir cas-chatbot
cd cas-chatbot

# Save the chatbot.py file to this directory
# Save the configuration files (shown below)
```

### 2. Install Dependencies

```bash
# Install required Python packages
pip install requests PyYAML prompt-toolkit rich openai

# Or install from requirements.txt
pip install -r requirements.txt
```

### 3. Install OpenShift CLI

#### macOS
```bash
# Using Homebrew
brew install openshift-cli

# Or download from Red Hat
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-mac.tar.gz
```

#### Linux
```bash
# Download and install
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc /usr/local/bin/
```

#### Windows
```powershell
# Download from Red Hat and add to PATH
# https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-windows.zip
```

### 4. Verify Installation

```bash
# Check Python version
python --version  # Should be 3.10+

# Check OpenShift CLI
oc version

# Test Python dependencies
python -c "import requests, yaml, prompt_toolkit, rich, openai; print('All dependencies installed successfully')"
```

## ⚙️ Configuration

### 1. Create Configuration File

Create a `config.yaml` file in your project directory:

```yaml
# OpenShift Configuration
console_url: "https://console-openshift-console.apps.your-cluster.com"
oc_username: "your-username"
oc_password: "your-password"

# CAS Service Configuration
cas_url: "https://cas-service.apps.your-cluster.com"

# Query Configuration
default_limit: 10
default_table: "your-default-table"  # Optional
enable_source: true
enable_content_metadata: true

# Request Configuration
request_timeout: 30  # seconds

# LLM Provider Configuration
llm_provider_sequence:
  - "openai"    # Try OpenAI first
  - "ollama"    # Then try Ollama
  - "nvidia"    # Finally try NVIDIA

# OpenAI Configuration
openai_api_key: "your-openai-api-key"
openai_model: "gpt-4"  # or gpt-3.5-turbo
temperature: 0.7

# Ollama Configuration (Local LLM)
ollama_host: "http://localhost:11434"
ollama_model: "llama2"

# NVIDIA Configuration
nvidia_llm_url: "https://api.nvidia.com/llm"
nvidia_model: "meta/llama2-70b"

# Logging Configuration
log_level: "INFO"  # DEBUG, INFO, WARNING, ERROR
log_file: "cas_chatbot.log"
```


```

### 3. Secure Configuration Management

For production environments, consider using environment variables:

```yaml
# Use environment variables for sensitive data
oc_username: "${OC_USERNAME}"
oc_password: "${OC_PASSWORD}"
openai_api_key: "${OPENAI_API_KEY}"
```

Set environment variables:
```bash
export OC_USERNAME="your-username"
export OC_PASSWORD="your-password"
export OPENAI_API_KEY="your-api-key"
```

## 🏃‍♂️ Usage

### Basic Usage

```bash
# Start with default configuration
python  cas_chatbot_cli.py -c config.yaml
```

### Interactive Commands

Once the chatbot is running, you can use these commands:

| Command | Description | Example |
|---------|-------------|---------|
| `help` | Show available commands | `help` |
| `bye`, `exit`, `quit` | Exit the chatbot | `bye` |
| `history` | Show query history | `history` |
| `clear` | Clear query history | `clear` |
| `tables` | List available tables | `tables` |
| `table <name>` | Switch to specific table | `table customers` |
| `stats` | Show session statistics | `stats` |
| `export` | Export chat history | `export` |

### Query Examples

```bash
# Natural language queries
What are the top selling products this month?
Show me customer complaints from last week
Analyze sales trends for Q4
Find security incidents in the network logs
```

## 🔧 Advanced Configuration

### LLM Provider Setup


#### Granite Setup
1. Get access to IBM watsonx Granite AI Foundation Models
2. Configure endpoint:
```yaml
granite_llm_url: "http://localhost:8000"
granite_llm_model: "ibm-granite/granite-vision-3.2-2b"
```

#### OpenAI Setup
1. Get API key from [OpenAI Platform](https://platform.openai.com/api-keys)
2. Add to configuration:
```yaml
openai_api_key: "sk-your-api-key-here"
openai_model: "gpt-4"  # or gpt-3.5-turbo for cost efficiency
```

#### Ollama Setup (Local LLM)
1. Install Ollama: https://ollama.ai/
2. Pull a model: `ollama pull llama2`
3. Configure:
```yaml
ollama_host: "http://localhost:11434"
ollama_model: "llama2"
```

#### NVIDIA Setup
1. Get access to NVIDIA AI Foundation Models
2. Configure endpoint:
```yaml
nvidia_llm_url: "https://api.nvidia.com/llm"
nvidia_model: "meta/llama2-70b"
```



### Custom Logging

Configure detailed logging for troubleshooting:

```yaml
log_level: "DEBUG"
log_file: "debug.log"
```

View logs in real-time:
```bash
tail -f cas_chatbot.log
```

## 🔍 Troubleshooting

### Common Issues

#### Authentication Problems
```bash
# Error: Authentication failed
# Solution: Check credentials and cluster URL
oc login https://api.your-cluster.com:6443 --username=user --password=pass
```

#### CAS Service Connectivity
```bash
# Error: CAS service validation failed
# Check: Network connectivity and service status
curl -k https://cas-service.apps.your-cluster.com/api/v1/querysearch/health
```

#### LLM Provider Issues
```bash
# Error: All LLM providers failed
# Check: API keys and network connectivity
# Test OpenAI: curl -H "Authorization: Bearer $OPENAI_API_KEY" https://api.openai.com/v1/models
```

### Debug Mode

Run with debug logging:
```bash
python chatbot.py --config debug.yaml
```

Debug configuration (`debug.yaml`):
```yaml
log_level: "DEBUG"
request_timeout: 60
default_limit: 1  # Reduce for testing
```

### Log Analysis

Check common log patterns:
```bash
# Authentication issues
grep "Authentication" cas_chatbot.log

# Network issues
grep "timeout\|connection" cas_chatbot.log -i

# LLM provider issues
grep "LLM\|provider" cas_chatbot.log -i
```


### Log Monitoring

Monitor real-time activity:
```bash
# Follow logs
tail -f cas_chatbot.log

# Filter for specific events
grep "Query executed" cas_chatbot.log
grep "Authentication" cas_chatbot.log
```

### Development Setup

```bash
# Clone repository
git clone <repository-url>
cd cas-chatbot

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Linux/Mac
# venv\Scripts\activate   # Windows

# Install development dependencies
pip install -r requirements.txt

# Run tests
python -m pytest tests/


### Code Structure

```
cas-chatbot/
├── cas_cli_chatbot.py      # Main application
├── config.yaml             # Default configuration
├── requirements.txt        # Python dependencies

## 📝 Changelog

### v2.0.0 (Current)
- Enhanced error handling and recovery
- Multi-LLM provider support
- Session statistics and export functionality
- Improved CLI with auto-completion
- Comprehensive logging system
- Table management features
- Configuration validation

### v1.0.0 (Previous)
- Basic chatbot functionality
- OpenShift authentication
- CAS integration
- Simple query processing

## 📄 License

This project is licensed under the IBM CAS License - see the LICENSE file for details.



### Getting Help
- Check the troubleshooting section above
- Review log files for error messages
- Verify configuration settings
- Test network connectivity

### Reporting Issues
When reporting issues, please include:
- Configuration file (sanitized)
- Log files
- Error messages
- Steps to reproduce

### Contact Information
- Project maintainer: [Kumar Nishant]
- Email: [k.nishant@ibm.com]
- 

---

**Made for Enterprise CAS Users**