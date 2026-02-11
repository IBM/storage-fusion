# 🚀 Quick Start Guide

Get CAS Chatbot up and running in 5 minutes!

## Prerequisites Check

Before you begin, ensure you have:

- [ ] Python 3.8 or higher installed
- [ ] OpenShift CLI (`oc`) installed
- [ ] Access to an OpenShift cluster
- [ ] Network connectivity to your cluster

## Installation

### Option 1: Automated Setup (Recommended)

```bash
# 1. Make setup script executable
chmod +x setup.sh

# 2. Run setup
./setup.sh

# 3. Edit configuration
nano config.yaml

# 4. Run the application
source venv/bin/activate
python main.py
```

### Option 2: Manual Setup

```bash
# 1. Create virtual environment
python3 -m venv venv
source venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Create directories
mkdir -p logs backups

# 4. Copy and edit configuration
cp config.yaml.sample config.yaml
nano config.yaml

# 5. Run the application
python main.py
```

### Option 3: Using Makefile

```bash
# One command setup
make all

# Activate virtual environment
source venv/bin/activate

# Edit configuration
nano config.yaml

# Run application
make run
```

## Minimum Configuration

Edit `config.yaml` with at least these settings:

```yaml
# Required settings
console_url: "https://console-openshift-console.apps.YOUR-CLUSTER.com"
oc_username: "your-username"
oc_password: "your-password"

# Optional but recommended
llm_provider_sequence: ["nvidia"]  # Or your preferred LLM provider
```

## First Run

```bash
# Start the application
python main.py

# You should see:
# ╔═══════════════════════════════════════════════════════════╗
# ║                                                           ║
# ║           CAS Chatbot - Enterprise Edition               ║
# ║                                                           ║
# ╚═══════════════════════════════════════════════════════════╝
```

## Quick Commands

Once the application starts, try these commands:

```bash
# See all commands
help

# List users
users list

# Select a user
users select

# List domains
domains list

# Select a domain
domains select

# Ask a question
query ask

# View session stats
session stats

# Exit
exit
```

## Environment Variables (Recommended for Production)

Create a `.env` file for sensitive data:

```bash
# .env file
OC_PASSWORD=your-secure-password
OPENAI_API_KEY=sk-your-api-key
KEYCLOAK_CLIENT_SECRET=your-secret
```

Update `config.yaml` to reference them:

```yaml
oc_password: "${OC_PASSWORD}"
openai_api_key: "${OPENAI_API_KEY}"
client_secret: "${KEYCLOAK_CLIENT_SECRET}"
```

## Verify Installation

Run health checks:

```bash
cas> health
```

All services should show as healthy (✓).

## Common First-Time Issues

### Issue: "oc: command not found"

**Solution**: Install OpenShift CLI
```bash
# Download from: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
# Or use package manager:
brew install openshift-cli  # macOS
```

### Issue: "Authentication failed"

**Solution**: Test manual login first
```bash
oc login <your-api-url> -u <username> -p <password> --insecure-skip-tls-verify
```

### Issue: "Configuration validation failed"

**Solution**: Check YAML syntax
```bash
python3 -c "import yaml; yaml.safe_load(open('config.yaml'))"
```

### Issue: "Module not found"

**Solution**: Ensure virtual environment is activated
```bash
source venv/bin/activate
pip install -r requirements.txt
```

## Makefile Commands Reference

```bash
make help          # Show all available commands
make setup         # Run initial setup
make run           # Run the application
make dev           # Run with debug logging
make backup        # Backup configuration
make logs          # View logs in real-time
make clean         # Clean temporary files
make info          # Show project information
```

## Next Steps

1. **Explore the interface**: Try different commands
2. **Read the README**: `less README.md`
3. **Configure LLM providers**: Add your API keys
4. **Setup Keycloak** (optional