    # CAS Chatbot - Enterprise Edition v2.0.0

An advanced, enterprise-grade CLI application for managing Cloud Application Services (CAS) with multi-provider LLM integration, comprehensive user management, and domain administration.

## 🌟 Features

### Core Capabilities
- **Multi-Source User Management**: Manage users from OpenShift (OCP) and Keycloak (IDP)
- **Domain Administration**: List, select, and manage domain access controls
- **LLM Integration**: Support for multiple LLM providers (NVIDIA, OpenAI, Ollama, Granite)
- **Intelligent Caching**: Performance optimization with TTL-based caching
- **Session Management**: Persistent session history with export capabilities
- **Health Monitoring**: Comprehensive health checks for all services
- **Metrics Tracking**: Real-time performance metrics and statistics

### Advanced Features
- **Automatic Token Refresh**: Intelligent token management with expiry tracking
- **Retry Logic**: Robust error handling with automatic retries
- **Environment Variables**: Support for environment-based configuration
- **Rich CLI Interface**: Beautiful terminal UI with autocomplete and fuzzy search
- **Structured Logging**: Rotating log files with configurable levels
- **Rate Limiting**: Protect external services with configurable rate limits

## 📋 Prerequisites

- Python 3.8 or higher
- OpenShift CLI (`oc`) installed and configured
- Access to OpenShift cluster
- (Optional) Keycloak/IDP instance for external user management
- (Optional) LLM provider API keys

## 🚀 Quick Start

### 1. Clone and Setup

```bash
# Create project directory
mkdir cas-chatbot && cd cas-chatbot

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configuration

```bash
# Copy and edit configuration
cp config.yaml.sample config.yaml
nano config.yaml  # Edit with your settings
```

**Minimum required configuration:**
```yaml
console_url: "https://console-openshift-console.apps.your-cluster.com"
oc_username: "your-username"
oc_password: "your-password"
```

**Using environment variables (recommended for secrets):**
```bash
export OPENAI_API_KEY="sk-your-key"
export KEYCLOAK_CLIENT_SECRET="your-secret"
export OC_PASSWORD="your-password"
```

### 3. Run the Application

```bash
python main.py
```

## 📁 Project Structure

```
cas-chatbot/
├── main.py                     # Application entry point
├── config.yaml                 # Configuration file
├── requirements.txt            # Python dependencies
├── README.md                   # This file
├── cli/
│   ├── __init__.py
│   ├── chatbot_cli.py         # Main CLI interface
│   └── middleware.py          # Error handling & session management
├── services/
│   ├── __init__.py
│   ├── auth_service.py        # Authentication service
│   ├── user_service.py        # User management
│   ├── domain_service.py      # Domain management
│   ├── query_service.py       # Query service
│   ├── llm_service.py         # LLM integration
│   ├── cache_service.py       # Caching layer
│   └── metrics_service.py     # Metrics tracking
├── utils/
│   ├── __init__.py
│   ├── config_loader.py       # Configuration management
│   ├── logger.py              # Logging utilities
│   └── health_check.py        # Health check utilities
└── logs/
    └── cas_chatbot.log        # Application logs
```

## 🎯 Usage Guide

### Available Commands

#### User Management
```bash
users list       # List all users (OCP + IDP)
users ocp        # List OpenShift users only
users idp        # List Keycloak/IDP users
users select     # Select/switch active user
users sync       # Force refresh user lists
```

#### Domain Management
```bash
domains list     # List all available domains
domains select   # Select a domain to work with
domains info     # Show detailed domain information
domains users    # Show users assigned to current domain
domains assign   # Assign user to current domain
```

#### Query & LLM
```bash
query ask        # Ask a question using LLM
query history    # View query history
```

#### Session Management
```bash
session view     # View current session status
session history  # Show session history
session stats    # Display session statistics
session export   # Export session to file
session clear    # Clear session history
```

#### System Commands
```bash
config show      # Show current configuration (sanitized)
config reload    # Reload configuration from file
metrics          # Display application metrics
health           # Run health checks on all services
clear            # Clear screen
help             # Show all available commands
exit/quit        # Exit application
```

### Example Workflow

```bash
# 1. Start the application
python main.py

# 2. Select a user
cas> users select
Select user (type to search): admin

# 3. Select a domain
admin> domains select
Select domain (type to search): production-domain

# 4. Assign user to domain
admin@production-domain> domains assign
Enter username to assign: developer1

# 5. Ask a query
admin@production-domain> query ask
Enter your query: What are the recent changes in this domain?

# 6. View session statistics
admin@production-domain> session stats

# 7. Export session
admin@production-domain> session export
Enter filename: my-session-2025-01-01.json
```

## ⚙️ Configuration Reference

### Core Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `console_url` | OpenShift console URL | Required |
| `oc_username` | OpenShift username | Required |
| `oc_password` | OpenShift password | Required |
| `cas_url` | CAS API endpoint | Required |
| `default_table` | Default CAS table | `gt20` |

### LLM Providers

Configure multiple providers with fallback:

```yaml
llm_provider_sequence: ["nvidia", "openai", "ollama"]

# NVIDIA Configuration
nvidia_llm_url: "http://your-nvidia-endpoint"
nvidia_model: "meta/llama3-8b-instruct"

# OpenAI Configuration
openai_api_key: "${OPENAI_API_KEY}"
openai_model: "gpt-3.5-turbo"

# Ollama Configuration
ollama_host: "http://localhost:11434"
ollama_model: "llama3"
```

### Caching

```yaml
cache:
  default_ttl: 300              # 5 minutes
  max_entries: 1000
  user_cache_ttl: 600           # 10 minutes
  domain_cache_ttl: 300         # 5 minutes
```

### Logging

```yaml
logging:
  level: "INFO"                 # DEBUG, INFO, WARNING, ERROR, CRITICAL
  file: "logs/cas_chatbot.log"
  max_bytes: 10485760           # 10MB
  backup_count: 5
  console_output: false
  structured: false             # JSON format
```

## 🔒 Security Best Practices

1. **Never commit credentials**: Use environment variables or `.env` files
2. **Restrict file permissions**: `chmod 600 config.yaml`
3. **Use service accounts**: Prefer service accounts over personal credentials
4. **Rotate tokens**: Implement regular token rotation
5. **Enable SSL verification**: Set `allow_self_signed: false` in production

### Using .env File

Create a `.env` file (add to `.gitignore`):

```bash
OC_PASSWORD=your-secure-password
OPENAI_API_KEY=sk-your-openai-key
KEYCLOAK_CLIENT_SECRET=your-keycloak-secret
NGC_API_KEY=your-nvidia-key
```

Update config.yaml to use environment variables:

```yaml
oc_password: "${OC_PASSWORD}"
openai_api_key: "${OPENAI_API_KEY}"
client_secret: "${KEYCLOAK_CLIENT_SECRET}"
```

## 📊 Monitoring & Observability

### Health Checks

Run comprehensive health checks:

```bash
cas> health
```

Health checks include:
- Authentication service status
- Cache service statistics
- User service connectivity
- Domain service availability
- LLM provider status
- OpenShift CLI availability

### Metrics

View application metrics:

```bash
cas> metrics
```

Tracked metrics:
- Request counts by service
- Response times (min, max, avg, p95, p99)
- Cache hit/miss rates
- Error counts by type
- Uptime

### Logs

Logs are stored in `logs/cas_chatbot.log` with automatic rotation:

```bash
# View logs
tail -f logs/cas_chatbot.log

# Search for errors
grep ERROR logs/cas_chatbot.log

# View specific service logs
grep "UserService" logs/cas_chatbot.log
```

## 🐛 Troubleshooting

### Common Issues

#### 1. Authentication Failed

**Error**: `Authentication failed: Login failed`

**Solutions**:
- Verify credentials in `config.yaml`
- Check OpenShift cluster URL is correct
- Ensure `oc` CLI is installed: `oc version`
- Test manual login: `oc login <api-url> -u <username> -p <password>`

#### 2. Cannot Fetch Users

**Error**: `Failed to fetch OCP users`

**Solutions**:
- Ensure you're authenticated: `oc whoami`
- Check cluster permissions: `oc auth can-i list users`
- Verify network connectivity to cluster

#### 3. LLM Provider Failures

**Error**: `All LLM providers failed`

**Solutions**:
- Check provider URLs are accessible
- Verify API keys are correct
- Check provider is in `llm_provider_sequence`
- Review logs for specific error messages

#### 4. Cache Issues

**Problem**: Stale data being displayed

**Solutions**:
```bash
# Clear cache and force refresh
cas> users sync
cas> domains sync

# Or restart the application
```

#### 5. Configuration Errors

**Error**: `Configuration validation failed`

**Solutions**:
- Validate YAML syntax: `python -c "import yaml; yaml.safe_load(open('config.yaml'))"`
- Check required fields are present
- Verify URLs start with `http://` or `https://`
- Check numeric values are positive integers

### Debug Mode

Enable debug logging for detailed troubleshooting:

```yaml
logging:
  level: "DEBUG"
```

Or set environment variable:
```bash
export LOG_LEVEL=DEBUG
python main.py
```

## 🔧 Advanced Configuration

### Custom Cache TTL per Service

```yaml
cache:
  default_ttl: 300
  user_cache_ttl: 600      # Users change less frequently
  domain_cache_ttl: 180    # Domains change more frequently
```

### Rate Limiting

Protect external services:

```yaml
rate_limit:
  enabled: true
  max_requests: 100
  time_window: 60  # seconds
```

### Multiple Environment Support

Create environment-specific configs:

```bash
config.dev.yaml
config.staging.yaml
config.prod.yaml
```

Run with specific config:

```bash
# Modify main.py to accept --config argument
python main.py --config config.prod.yaml
```

## 📚 API Integration Examples

### Query Service Integration

```python
from services.query_service import QueryService

query_service = QueryService(config, logger)
results = query_service.query_table(table="gt20", limit=10)
```

### User Service Integration

```python
from services.user_service import UserService

user_service = UserService(config, auth_service, logger)
ocp_users = user_service.list_oc_users()
keycloak_users = user_service.list_keycloak_users()
```

### Domain Service Integration

```python
from services.domain_service import DomainService

domain_service = DomainService(config, auth_service, logger)
domains = domain_service.list_domains()
domain_service.assign_users_to_domain("my-domain", ["user1", "user2"])
```

## 🧪 Testing

### Manual Testing Checklist

- [ ] Authentication successful
- [ ] Users can be listed from OCP
- [ ] Users can be listed from Keycloak
- [ ] Domains can be listed
- [ ] User can be assigned to domain
- [ ] Query can be executed with LLM
- [ ] Session is persisted
- [ ] Metrics are tracking
- [ ] Health checks pass

### Performance Testing

Monitor metrics after operations:

```bash
cas> metrics
```

Expected performance:
- User list retrieval: < 2s (cached: < 100ms)
- Domain list retrieval: < 3s (cached: < 100ms)
- LLM query: 5-30s (depending on provider)

## 📝 Development Guide

### Adding a New Command

1. Add command to `COMMANDS` dict in `chatbot_cli.py`
2. Implement handler method: `cmd_<name>(self)`
3. Add command to `execute_command()` mapping

Example:

```python
# In ChatbotCLI class
COMMANDS = {
    # ... existing commands
    'backup create': 'Create a backup of current configuration'
}

def cmd_backup_create(self):
    """Create configuration backup"""
    # Implementation
    pass

def execute_command(self, command: str):
    command_map = {
        # ... existing mappings
        'backup create': self.cmd_backup_create
    }
```

### Adding a New Service

1. Create service file in `services/`
2. Implement service class
3. Initialize in `main.py`
4. Inject into CLI

Example:

```python
# services/backup_service.py
class BackupService:
    def __init__(self, config, logger):
        self.config = config
        self.logger = logger
    
    def create_backup(self):
        # Implementation
        pass

# main.py
backup_service = BackupService(config, logger)
services['backup'] = backup_service
```

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Update documentation
6. Submit a pull request

### Code Style

- Follow PEP 8 guidelines
- Use type hints where appropriate
- Add docstrings to all functions/classes
- Keep functions focused and small

### Commit Messages

Use conventional commits:
```
feat: add user search functionality
fix: resolve cache invalidation issue
docs: update configuration guide
refactor: improve error handling in auth service
```

## 📄 License

This project is proprietary software. All rights reserved.

## 🆘 Support

### Getting Help

1. Check this README first
2. Review logs in `logs/cas_chatbot.log`
3. Check configuration in `config.yaml`
4. Run health checks: `cas> health`

### Reporting Issues

When reporting issues, include:
- Error message and stack trace
- Relevant configuration (sanitized)
- Log excerpts
- Steps to reproduce
- Expected vs actual behavior

## 🗺️ Roadmap

### Planned Features

- [ ] Web UI dashboard
- [ ] RESTful API server mode
- [ ] Advanced query analytics
- [ ] User role management
- [ ] Audit logging
- [ ] Multi-cluster support
- [ ] Configuration validation tool
- [ ] Automated testing suite
- [ ] Docker containerization
- [ ] Helm chart for deployment

### Version History

**v2.0.0** (Current)
- Enhanced CLI with advanced features
- Multi-provider LLM support
- Intelligent caching system
- Comprehensive metrics tracking
- Health monitoring
- Session management
- Improved error handling

**v1.0.0**
- Initial release
- Basic user management
- Domain administration
- Simple LLM integration

## 📞 Contact

For questions or support, contact your system administrator or the development team.

---

**Built with ❤️ for enterprise cloud management**