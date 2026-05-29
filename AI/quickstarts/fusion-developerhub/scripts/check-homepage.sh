#!/bin/bash
echo "=== Checking Homepage Configuration ==="
echo ""

echo "1. Checking dynamic plugins ConfigMap..."
kubectl get configmap backstage-dynamic-plugins-fusion-hub -n fusion-hub -o yaml 2>/dev/null | grep -A 30 "dynamic-plugins"
echo ""

echo "2. Testing homepage URL..."
URL="https://developerhub-fusion-hub.fusion-dh.apps.osai-demo.cp.fyre.ibm.com"
echo "Testing: $URL"
curl -k -s -o /dev/null -w "HTTP Status: %{http_code}\n" "$URL/" 2>&1 || echo "Could not reach URL"
echo ""

echo "3. Checking pod logs for errors..."
POD=$(kubectl get pods -n fusion-hub -l app.kubernetes.io/name=backstage -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD"
kubectl logs -n fusion-hub $POD --tail=50 2>&1 | grep -i "error\|404\|home\|plugin" || echo "No relevant errors found"
echo ""

echo "4. Checking Backstage instance spec..."
kubectl get backstage fusion-hub -n fusion-hub -o yaml | grep -A 10 "dynamicPlugins" || echo "No dynamicPlugins configuration"
echo ""

echo "=== Check complete ==="
