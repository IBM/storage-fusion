#!/bin/bash
echo "=== Checking Fusion Hub Deployment ==="
echo ""

echo "1. Checking if fusion-hub release exists..."
helm list -n fusion-hub 2>/dev/null || echo "No fusion-hub release found"
echo ""

echo "2. Checking Backstage instance..."
kubectl get backstage -n fusion-hub 2>/dev/null || echo "No Backstage instance found"
echo ""

echo "3. Checking pods..."
kubectl get pods -n fusion-hub 2>/dev/null || echo "No pods found in fusion-hub namespace"
echo ""

echo "4. Checking ConfigMaps..."
kubectl get configmap -n fusion-hub 2>/dev/null | grep -E "developerhub|backstage" || echo "No relevant ConfigMaps found"
echo ""

echo "5. Checking app-config content..."
kubectl get configmap developerhub-app-config -n fusion-hub -o yaml 2>/dev/null | grep -A 20 "app-config.yaml:" || echo "No app-config ConfigMap found"
echo ""

echo "=== Diagnostic script complete ==="
echo "Please share the output above so we can diagnose the issue."
