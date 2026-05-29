#!/bin/bash
# Script to create RHOAI connector token secret for Red Hat Developer Hub
# This is the only manual step required for OpenShift AI integration

set -e

# Configuration
NAMESPACE="${NAMESPACE:-fusion-dev-hub}"
SECRET_NAME="${SECRET_NAME:-rhdh-rhoai-connector-token}"

echo "=================================================="
echo "RHOAI Connector Token Secret Setup"
echo "=================================================="
echo ""
echo "This script will create the token secret required for"
echo "Red Hat Developer Hub to connect to OpenShift AI."
echo ""
echo "Namespace: $NAMESPACE"
echo "Secret Name: $SECRET_NAME"
echo ""

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "❌ ERROR: Namespace '$NAMESPACE' does not exist"
    echo "Please create the namespace first or set NAMESPACE environment variable"
    exit 1
fi

# Check if secret already exists
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "⚠️  WARNING: Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'"
    read -p "Do you want to replace it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
    echo "✅ Deleted existing secret"
fi

echo ""
echo "Choose token source:"
echo "1) Use Service Account token (Recommended - automatically rotated)"
echo "2) Use RHOAI API token (Manual - get from OpenShift AI console)"
echo ""
read -p "Enter choice (1 or 2): " -n 1 -r CHOICE
echo ""

case $CHOICE in
    1)
        echo ""
        echo "Using Service Account token..."
        
        # Get the service account name
        SA_NAME=$(kubectl get sa -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="default")].metadata.name}' 2>/dev/null || echo "default")
        
        if [ -z "$SA_NAME" ]; then
            echo "❌ ERROR: Could not find service account in namespace '$NAMESPACE'"
            exit 1
        fi
        
        echo "Service Account: $SA_NAME"
        
        # Get the token from service account secret
        SECRET_NAME_SA=$(kubectl get sa "$SA_NAME" -n "$NAMESPACE" -o jsonpath='{.secrets[0].name}' 2>/dev/null)
        
        if [ -z "$SECRET_NAME_SA" ]; then
            echo "⚠️  No secret found for service account. Creating token..."
            # For newer Kubernetes versions, create a token
            TOKEN=$(kubectl create token "$SA_NAME" -n "$NAMESPACE" --duration=87600h 2>/dev/null)
        else
            # Get token from secret
            TOKEN=$(kubectl get secret "$SECRET_NAME_SA" -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)
        fi
        
        if [ -z "$TOKEN" ]; then
            echo "❌ ERROR: Could not retrieve service account token"
            exit 1
        fi
        
        echo "✅ Retrieved service account token"
        ;;
        
    2)
        echo ""
        echo "To get your RHOAI API token:"
        echo "1. Log in to OpenShift AI console"
        echo "2. Navigate to: Settings → Access Tokens"
        echo "3. Click 'Create Token'"
        echo "4. Give it a name and select read permissions"
        echo "5. Copy the token value"
        echo ""
        read -p "Enter your RHOAI token: " -s TOKEN
        echo ""
        
        if [ -z "$TOKEN" ]; then
            echo "❌ ERROR: Token cannot be empty"
            exit 1
        fi
        
        echo "✅ Token received"
        ;;
        
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

# Create the secret
echo ""
echo "Creating secret '$SECRET_NAME' in namespace '$NAMESPACE'..."

kubectl create secret generic "$SECRET_NAME" \
    --from-literal=token="$TOKEN" \
    --namespace="$NAMESPACE"

if [ $? -eq 0 ]; then
    echo ""
    echo "=================================================="
    echo "✅ SUCCESS!"
    echo "=================================================="
    echo ""
    echo "Secret '$SECRET_NAME' created successfully in namespace '$NAMESPACE'"
    echo ""
    echo "Next steps:"
    echo "1. Verify the secret:"
    echo "   kubectl get secret $SECRET_NAME -n $NAMESPACE"
    echo ""
    echo "2. Deploy/upgrade Developer Hub:"
    echo "   helm upgrade --install fusion-hub ./helm-charts/fusion-developer-hub \\"
    echo "     -f examples/quickstart-production-values.yaml \\"
    echo "     --namespace $NAMESPACE"
    echo ""
    echo "3. Verify RHOAI connector is working:"
    echo "   kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=backstage -c backstage-backend | grep -i rhoai"
    echo ""
else
    echo ""
    echo "❌ ERROR: Failed to create secret"
    exit 1
fi

# Made with Bob
