#!/bin/bash

# Test Git connection with configured credentials

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
echo -e "${BLUE}Testing Git Connection${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Not logged into OpenShift. Run 'oc login' first.${NC}"
    exit 1
fi

# Check if git-credentials secret exists
if ! oc get secret git-credentials -n $NAMESPACE &> /dev/null; then
    echo -e "${RED}✗ Git credentials secret not found${NC}"
    echo ""
    echo "Run this first:"
    echo -e "  ${YELLOW}./scripts/setup-git-credentials.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Git credentials secret found"

# Get auth method
AUTH_METHOD=$(oc get secret git-credentials -n $NAMESPACE -o jsonpath='{.data.auth-method}' 2>/dev/null | base64 -d 2>/dev/null || echo "unknown")

echo -e "${GREEN}✓${NC} Authentication method: ${AUTH_METHOD}"

# Prompt for Git repository URL
echo ""
read -p "Enter Git repository URL to test: " GIT_REPO

if [ -z "$GIT_REPO" ]; then
    echo -e "${RED}✗ No repository URL provided${NC}"
    exit 1
fi

# Extract host from URL
if [[ "$GIT_REPO" =~ ^https://([^/]+) ]]; then
    GIT_HOST="${BASH_REMATCH[1]}"
elif [[ "$GIT_REPO" =~ ^git@([^:]+): ]]; then
    GIT_HOST="${BASH_REMATCH[1]}"
else
    echo -e "${RED}✗ Could not parse Git host from URL${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Git host: ${GIT_HOST}"

# Create test pod
echo ""
echo -e "${BLUE}Creating test pod...${NC}"

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: git-connection-test
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 0
  containers:
    - name: test
      image: registry.access.redhat.com/ubi9/ubi:latest
      securityContext:
        runAsUser: 0
      command: ["/bin/bash", "-c"]
      args:
        - |
          set -e
          
          echo "Installing dependencies..."
          dnf install -y git openssh-clients --setopt=tsflags=nodocs
          
          # Setup Git authentication
          if [ -f /git-credentials/token ]; then
            echo "Using token authentication..."
            GIT_USERNAME=\$(cat /git-credentials/username)
            GIT_TOKEN=\$(cat /git-credentials/token)
            
            git config --global credential.helper store
            echo "https://\${GIT_USERNAME}:\${GIT_TOKEN}@${GIT_HOST}" > ~/.git-credentials
            
          elif [ -f /git-credentials/password ]; then
            echo "Using password authentication..."
            GIT_USERNAME=\$(cat /git-credentials/username)
            GIT_PASSWORD=\$(cat /git-credentials/password)
            
            git config --global credential.helper store
            echo "https://\${GIT_USERNAME}:\${GIT_PASSWORD}@${GIT_HOST}" > ~/.git-credentials
            
          elif [ -f /git-credentials/ssh-privatekey ]; then
            echo "Using SSH key authentication..."
            
            mkdir -p ~/.ssh
            chmod 700 ~/.ssh
            cp /git-credentials/ssh-privatekey ~/.ssh/id_rsa
            chmod 600 ~/.ssh/id_rsa
            
            ssh-keyscan -H ${GIT_HOST} >> ~/.ssh/known_hosts 2>/dev/null || true
            
            git config --global core.sshCommand "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no"
          fi
          
          echo "Testing Git clone..."
          cd /tmp
          git clone --depth 1 ${GIT_REPO} test-repo
          
          if [ -d test-repo ]; then
            echo "✓ Successfully cloned repository"
            cd test-repo
            echo "✓ Repository contents:"
            ls -la
            exit 0
          else
            echo "✗ Failed to clone repository"
            exit 1
          fi
      volumeMounts:
        - name: git-credentials
          mountPath: /git-credentials
          readOnly: true
  volumes:
    - name: git-credentials
      secret:
        secretName: git-credentials
        defaultMode: 0400
EOF

echo -e "${GREEN}✓${NC} Test pod created"

# Wait for pod to complete
echo ""
echo -e "${BLUE}Waiting for test to complete...${NC}"
echo ""

sleep 5

# Stream logs
oc logs -f git-connection-test -n $NAMESPACE 2>/dev/null || true

# Check result
echo ""
POD_STATUS=$(oc get pod git-connection-test -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
EXIT_CODE=$(oc get pod git-connection-test -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || echo "1")

if [ "$POD_STATUS" = "Succeeded" ] || [ "$EXIT_CODE" = "0" ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ Git Connection Test PASSED!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Your Git credentials are working correctly."
    echo "You can now use the CronJob or sync script."
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Git Connection Test FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Check the logs above for errors."
    echo ""
    echo "Common issues:"
    echo "  - Invalid token or password"
    echo "  - Token doesn't have 'repo' scope"
    echo "  - SSH key not added to GitHub"
    echo "  - Wrong repository URL"
fi

# Cleanup
echo ""
read -p "Delete test pod? (Y/n): " DELETE_POD
if [[ ! "$DELETE_POD" =~ ^[Nn]$ ]]; then
    oc delete pod git-connection-test -n $NAMESPACE 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Test pod deleted"
fi

echo ""

