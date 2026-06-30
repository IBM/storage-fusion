#!/bin/bash

# Setup Git credentials for private repositories

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="${NAMESPACE:-model-registry-gitops}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Git Credentials Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Not logged into OpenShift. Run 'oc login' first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Logged in as: $(oc whoami)"

# Check if namespace exists
if ! oc get namespace $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace $NAMESPACE not found. Creating...${NC}"
    oc create namespace $NAMESPACE
fi

echo ""
echo -e "${BLUE}Git Authentication Methods:${NC}"
echo "  1. Personal Access Token (PAT) - Recommended"
echo "  2. Username + Password"
echo "  3. SSH Key"
echo ""

read -p "Select authentication method (1-3): " AUTH_METHOD

case $AUTH_METHOD in
    1)
        echo ""
        echo -e "${BLUE}Personal Access Token Setup${NC}"
        echo ""
        echo "Create a token at:"
        echo "  GitHub Enterprise: https://github.your-company.com/settings/tokens"
        echo "  GitHub.com: https://github.com/settings/tokens"
        echo ""
        echo "Required scopes: repo (full control)"
        echo ""
        
        read -p "Enter your GitHub username: " GIT_USERNAME
        read -sp "Enter your Personal Access Token: " GIT_TOKEN
        echo ""
        
        # Create secret with token
        oc create secret generic git-credentials \
          --from-literal=username="${GIT_USERNAME}" \
          --from-literal=token="${GIT_TOKEN}" \
          --from-literal=auth-method="token" \
          -n $NAMESPACE \
          --dry-run=client -o yaml | oc apply -f -
        
        echo -e "${GREEN}✓${NC} Git credentials secret created (token-based)"
        
        # Show example Git URL
        echo ""
        echo -e "${BLUE}Use this Git URL format:${NC}"
        echo -e "  ${YELLOW}https://github.your-company.com/org/repo.git${NC}"
        ;;
    
    2)
        echo ""
        echo -e "${BLUE}Username + Password Setup${NC}"
        echo ""
        
        read -p "Enter your GitHub username: " GIT_USERNAME
        read -sp "Enter your GitHub password: " GIT_PASSWORD
        echo ""
        
        # Create secret with password
        oc create secret generic git-credentials \
          --from-literal=username="${GIT_USERNAME}" \
          --from-literal=password="${GIT_PASSWORD}" \
          --from-literal=auth-method="password" \
          -n $NAMESPACE \
          --dry-run=client -o yaml | oc apply -f -
        
        echo -e "${GREEN}✓${NC} Git credentials secret created (password-based)"
        
        echo ""
        echo -e "${BLUE}Use this Git URL format:${NC}"
        echo -e "  ${YELLOW}https://github.your-company.com/org/repo.git${NC}"
        ;;
    
    3)
        echo ""
        echo -e "${BLUE}SSH Key Setup${NC}"
        echo ""
        
        read -p "Enter path to SSH private key [~/.ssh/id_rsa]: " SSH_KEY_PATH
        SSH_KEY_PATH="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
        
        if [ ! -f "$SSH_KEY_PATH" ]; then
            echo -e "${RED}✗ SSH key not found at: $SSH_KEY_PATH${NC}"
            exit 1
        fi
        
        # Expand tilde
        SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
        
        # Create secret with SSH key
        oc create secret generic git-credentials \
          --from-file=ssh-privatekey="${SSH_KEY_PATH}" \
          --from-literal=auth-method="ssh" \
          -n $NAMESPACE \
          --dry-run=client -o yaml | oc apply -f -
        
        echo -e "${GREEN}✓${NC} Git credentials secret created (SSH-based)"
        
        echo ""
        echo -e "${BLUE}Use this Git URL format:${NC}"
        echo -e "  ${YELLOW}git@github.your-company.com:org/repo.git${NC}"
        
        echo ""
        echo -e "${YELLOW}Note:${NC} Add your SSH public key to GitHub:"
        echo "  https://github.your-company.com/settings/keys"
        ;;
    
    *)
        echo -e "${RED}✗ Invalid selection${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Git Credentials Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Secret created in namespace:${NC} $NAMESPACE"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Update CronJob or sync script with your Git repository URL"
echo "  2. Test the connection:"
echo -e "     ${YELLOW}./scripts/test-git-connection.sh${NC}"
echo ""

