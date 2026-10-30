# MaaS Governance (Subscriptions & Auth Policies)

This repository manages multi-tenant access control, API authentication policies, and rate limits for models deployed on the MaaS platform.

---

## Directory Structure

```
governance/
├── README.md                          # Governance overview
├── charts/
│   └── maas-config/                   # Helm chart for MaaSSubscription, MaaSAuthPolicy, Groups
└── config/
    ├── helm/                          # Per-environment Helm values (dev, staging, prod)
    └── gitops/                        # ArgoCD Application manifests (dev, staging, prod)
```

---

## Deployment

### Using Helm:
```bash
helm upgrade --install maas-governance charts/maas-config \
  -n redhat-ai-gateway-infra \
  -f config/helm/prod/values.yaml
```

### Using GitOps:
```bash
oc apply -f config/gitops/prod/appproject-prod.yaml
oc apply -f config/gitops/prod/application-governance-prod.yaml
```
