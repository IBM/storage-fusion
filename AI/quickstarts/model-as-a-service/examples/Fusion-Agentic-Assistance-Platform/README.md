# Fusion Agentic Assistance Platform - IBM Fusion Quick Start

This example demonstrates how to deploy the Fusion Agentic Assistance Platform using the MaaS platform with IBM Fusion Object Storage.

## Overview

The Fusion Agentic Assistance Platform provides AI-powered assistance capabilities through:
- **Two AI Models**: GPT-OSS-20B (all tiers) and Nemotron-3-Nano-30B (premium/enterprise)
- **Tiered Access**: Free, Premium, and Enterprise tiers with different rate limits
- **IBM Fusion Storage**: Integrated object storage for models and workbenches
- **Agentic Capabilities**: Intelligent assistance with context-aware responses
- **Monitoring**: Grafana dashboards for usage tracking and metrics

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     MaaS Runtime Layer                       │
│  - Gateway API                                               │
│  - Rate Limiting (Kuadrant)                                  │
│  - Authentication (Keycloak)                                 │
│  - Monitoring (Prometheus + Grafana)                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Model Services                          │
│  ┌──────────────────┐      ┌──────────────────┐            │
│  │  GPT-OSS-20B     │      │  Nemotron-30B    │            │
│  │  (All Tiers)     │      │  (Premium+)      │            │
│  └──────────────────┘      └──────────────────┘            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Application Layer                          │
│          Fusion Agentic Assistance Platform                  │
│         (AI-Powered Assistance Application)                  │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- OpenShift 4.20+ with OpenShift Data Foundation (ODF)
- 2 GPU nodes with 48GB VRAM each
- Helm CLI installed
- OpenShift CLI (oc) installed
- Cluster admin access
- OpenShift Data Foundation operator installed (for IBM Fusion storage)

## Quick Start

### 1. Deploy MaaS Runtime

```bash
# Set your admin and user passwords
export ADMIN_PASSWORD="your-secure-admin-password"
export USER_PASSWORD="your-secure-user-password"

# Deploy the runtime
helm install maas-runtime ../../deploy/maas-runtime \
  -f runtime-values.yaml \
  --set authentication.keycloak.realm.admin.password="$ADMIN_PASSWORD" \
  --set authentication.keycloak.realm.user.password="$USER_PASSWORD" \
  --timeout 20m
```

### 2. Wait for Runtime to be Ready

```bash
# Wait for DataScienceCluster
oc wait --for=condition=Ready datasciencecluster default-dsc --timeout=15m

# Wait for Kuadrant
oc wait --for=condition=Ready kuadrant kuadrant -n kuadrant-system --timeout=5m

# Wait for Keycloak
oc wait --for=condition=Ready keycloak keycloak -n keycloak --timeout=10m
```

### 3. Deploy Models

```bash
# Deploy GPT-OSS-20B (available to all tiers)
helm install gpt-oss ../../deploy/maas-model-service \
  -f models/gpt-oss-values.yaml

# Deploy Nemotron (premium and enterprise only)
helm install nemotron ../../deploy/maas-model-service \
  -f models/nemotron-values.yaml
```

### 4. Wait for Models to be Ready

```bash
# Check model status
oc get llminferenceservice -n maas-models

# Wait for models to be ready
oc wait --for=condition=Ready llminferenceservice gpt-oss-20b -n maas-models --timeout=10m
oc wait --for=condition=Ready llminferenceservice nemotron-3-nano-30b-a3b -n maas-models --timeout=10m
```

### 5. Access the Platform

```bash
# Get the OpenShift console URL
oc whoami --show-console

# Get Grafana dashboard URL
oc get route -n grafana grafana-route -o jsonpath='{.spec.host}'
```

## User Access

### Default Users

The deployment creates the following users:

| Username | Password | Tier | Models Available |
|----------|----------|------|------------------|
| admin | `$ADMIN_PASSWORD` | Enterprise | All models |
| user1-user5 | `$USER_PASSWORD` | Premium | All models |

### Tier Limits

| Tier | Request Rate | Token Rate | Models |
|------|--------------|------------|--------|
| Free | 5 req/2min | 100 tokens/min | GPT-OSS-20B |
| Premium | 20 req/2min | 10,000 tokens/min | All models |
| Enterprise | 50 req/2min | 20,000 tokens/min | All models |

## Using the Fusion Agentic Assistance Platform

### Via Application Interface

1. Deploy the Fusion Agentic Assistance Platform application
2. Access the application through its route
3. Authenticate using your OpenShift credentials
4. Interact with the AI-powered assistance features
5. The application automatically uses the deployed MaaS models

### Via API

```bash
# Get the model endpoint
MODEL_ENDPOINT=$(oc get route -n maas-models gpt-oss-20b -o jsonpath='{.spec.host}')

# Get your token
TOKEN=$(oc whoami -t)

# Make a request
curl -X POST "https://${MODEL_ENDPOINT}/v1/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "prompt": "def fibonacci(n):",
    "max_tokens": 100
  }'
```

## Monitoring

### Grafana Dashboards

Access Grafana dashboards to monitor:
- Request rates per user and tier
- Token consumption
- Model latency
- GPU utilization
- Error rates

```bash
# Get Grafana URL
echo "https://$(oc get route -n grafana grafana-route -o jsonpath='{.spec.host}')"
```

### Prometheus Metrics

```bash
# Port-forward to Prometheus
oc port-forward -n openshift-user-workload-monitoring svc/prometheus-user-workload 9090:9090

# Access at http://localhost:9090
```

## Customization

### Adding More Users

Edit `runtime-values.yaml` and add users to tiers:

```yaml
userMapping:
  premium:
    - user1
    - user2
    - newuser1  # Add new user
  enterprise:
    - admin
    - poweruser  # Add new user
```

Then upgrade the runtime:

```bash
helm upgrade maas-runtime ../../deploy/maas-runtime \
  -f runtime-values.yaml
```

### Adjusting Rate Limits

Edit `runtime-values.yaml` to modify tier limits:

```yaml
tiers:
  premium:
    requestRates:
      - limit: 30  # Increase from 20
        window: 2m
    tokenRates:
      - limit: 15000  # Increase from 10000
        window: 1m
```

### Scaling Models

Increase model replicas for higher throughput:

```bash
helm upgrade gpt-oss ../../deploy/maas-model-service \
  -f models/gpt-oss-values.yaml \
  --set inference.replicas=3
```

## Troubleshooting

### Models Not Starting

```bash
# Check model pods
oc get pods -n maas-models

# Check pod logs
oc logs -n maas-models <pod-name>

# Check events
oc get events -n maas-models --sort-by='.lastTimestamp'
```

### Rate Limiting Issues

```bash
# Check RateLimitPolicy
oc get ratelimitpolicy -n maas-models

# Check user groups
oc get groups | grep maas-tier
```

### Authentication Issues

```bash
# Check Keycloak status
oc get keycloak -n keycloak

# Check OAuth configuration
oc get oauth cluster -o yaml
```

## Cleanup

### Remove Models

```bash
helm uninstall gpt-oss
helm uninstall nemotron
```

### Remove Runtime

```bash
helm uninstall maas-runtime
```

### Complete Cleanup

```bash
# Remove all resources
helm uninstall gpt-oss nemotron maas-runtime

# Remove namespaces
oc delete namespace maas-models keycloak grafana

# Remove operators (if desired)
# Follow operator-specific uninstallation procedures
```

## Next Steps

- Explore other [use case examples](../)
- Read the [Model Deployment Guide](../../docs/MODEL_DEPLOYMENT_GUIDE.md)
- Learn about [Runtime Configuration](../../docs/RUNTIME_GUIDE.md)
- Check the [Architecture Documentation](../../docs/ARCHITECTURE.md)