# Contributing to MaaS

Thank you for contributing to the Model as a Service (MaaS) platform! This repository follows an opinionated GitHub Organization multi-repo mental model.

---

## Repository Structure & Separation of Concerns

```
maas/
├── runtime/                        # Platform runtime (Operators, Platform, Gateway, Registry)
├── models/                         # Model serving charts, Helm values, and deployment scripts
├── governance/                     # Multi-tenant subscriptions and access policies
├── bob (llm-d only deployment)/   # IBM Bob & Bifrost integration recipes
└── docs/                           # Architectural reference and operational guides
```

---

## 1. Onboarding a New Model

1. Create or configure a model Helm values file under `models/config/helm/<model-name>.yaml`.
2. Register the model in OpenShift AI Model Registry using `models/scripts/register-models.sh`:
   ```bash
   ./models/scripts/register-models.sh models/config/helm/<model-name>.yaml
   ```
3. Deploy the model to the cluster using `models/scripts/deploy-model.sh`:
   ```bash
   ./models/scripts/deploy-model.sh models/config/helm/<model-name>.yaml
   ```

---

## 2. Adding or Updating Deployment Configurations

- **Helm Values:** Add environment-specific values files under `models/config/helm/` or `runtime/config/helm/{dev,staging,prod}/`.
- **GitOps Applications:** Add ArgoCD Application manifests under `{segment}/config/gitops/{env}/applications/`.

---

## 3. Pull Request Guidelines

- Do not mix runtime platform changes with model deployment configurations.
- Ensure all Helm charts pass `helm lint`.
- Update relevant documentation in `docs/` when introducing new CRDs or configuration parameters.
