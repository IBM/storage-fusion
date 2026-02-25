#!/bin/bash
# Script to create ArgoCD repository secret for Fusion-AI

set -e

echo "=========================================="
echo "Create ArgoCD Repository Secret"
echo "=========================================="
echo ""

# Check if logged in to OpenShift
if ! oc whoami &>/dev/null; then
    echo "❌ Not logged in to OpenShift. Please run: oc login"
    exit 1
fi

echo "✅ Logged in as: $(oc whoami)"
echo ""

# Prompt for GitHub credentials
read -p "Enter your GitHub username [Purnanand-Kumar1]: " GITHUB_USER
GITHUB_USER=${GITHUB_USER:-Purnanand-Kumar1}

echo ""
echo "GitHub Personal Access Token is required."
echo "Create one at: https://github.ibm.com/settings/tokens"
echo "Required scopes: repo (all)"
echo ""
read -sp "Enter your GitHub Personal Access Token: " GITHUB_TOKEN
echo ""

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GitHub token is required"
    exit 1
fi

# Repository URL
REPO_URL="https://github.ibm.com/${GITHUB_USER}/Fusion-AI.git"

echo ""
echo "Creating repository secret..."
echo "Repository: $REPO_URL"
echo "Username: $GITHUB_USER"
echo ""

# Create the secret
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: fusion-ai-repo
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: $REPO_URL
  username: $GITHUB_USER
  password: $GITHUB_TOKEN
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Repository secret created successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Verify the secret:"
    echo "   oc get secret fusion-ai-repo -n openshift-gitops"
    echo ""
    echo "2. Apply the bootstrap:"
    echo "   oc apply -f bootstrap.yaml"
    echo ""
    echo "3. Monitor deployment:"
    echo "   watch -n 5 'oc get application.argoproj.io -n openshift-gitops'"
else
    echo ""
    echo "❌ Failed to create repository secret"
    exit 1
fi