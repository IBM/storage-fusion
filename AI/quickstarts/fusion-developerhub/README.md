# IBM Fusion Developer Hub

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenShift](https://img.shields.io/badge/OpenShift-4.12+-red.svg)](https://www.redhat.com/en/technologies/cloud-computing/openshift)
[![Red Hat](https://img.shields.io/badge/Red%20Hat-Certified-red.svg)](https://www.redhat.com/)

Production-ready deployment of Red Hat Developer Hub (Backstage) with IBM Fusion AI components on IBM Fusion HCI. Installs and manages Red Hat Developer Hub and Crunchy PostgreSQL via Kubernetes operators, and supports both **Helm** and **GitOps with ArgoCD** deployment models.

> **Platform**: IBM Fusion on Red Hat OpenShift 4.12+
> **Full guide**: See [QUICKSTART.md](QUICKSTART.md) for step-by-step instructions covering Helm and GitOps deployment, configuration, customization, upgrade, and troubleshooting.

## What You Get

- **AI homepage** with automatic OpenShift AI model discovery (KServe InferenceServices cataloged every 30s)
- **Pre-built AI app templates** — chatbot, RAG, code generation, object detection
- **Software catalog** for Fusion components, NVIDIA blueprints, and custom services
- **GitHub integration** — GitHub.com and GitHub Enterprise supported
- **OIDC authentication** — OpenShift, Keycloak, or any OIDC-compliant provider
- **High-availability PostgreSQL** — 3-instance Crunchy cluster with automatic failover and ODF backups
- **Enterprise security** — RBAC, network policies, pod security standards, secret encryption
- **GitOps ready** — ArgoCD Application CRs with sync-wave ordering included

## Repository Layout

```
deploy/
├── helm/                          # Helm chart
│   ├── templates/                 # Kubernetes resource templates
│   └── environments/
│       ├── dev/values.yaml        # Development values
│       ├── staging/values.yaml    # Staging values
│       └── prod/values.yaml       # Production values
└── gitops/
    └── environments/
        ├── dev/application.yaml   # ArgoCD Application CR — dev
        ├── staging/application.yaml
        └── prod/application.yaml  # ArgoCD Application CR — prod
```

## Prerequisites

- IBM Fusion on Red Hat OpenShift 4.12+
- `oc` CLI and Helm 3.8+
- Cluster admin access
- For GitOps: OpenShift GitOps (ArgoCD) installed

## Quick Start

Choose the deployment method that fits your workflow:

| Method | When to use | Guide |
|---|---|---|
| **Helm** | Direct install, one-off deployment, local testing | [QUICKSTART.md — Deploy using Helm](QUICKSTART.md#21-deploy-using-helm) |
| **GitOps (ArgoCD)** | Production, audit trail, Git-driven config management | [QUICKSTART.md — Deploy using GitOps](QUICKSTART.md#22-deploy-using-gitops) |

Both methods deploy the same Helm chart. The values files under `deploy/helm/environments/` are used directly for Helm installs and referenced by the ArgoCD Application CRs for GitOps.

> **First time?** Start with [QUICKSTART.md](QUICKSTART.md) — it covers prerequisites, required configuration changes (cluster domain, storage class), step-by-step deployment, verification, and access.

## Environment Values Files

Pre-built values files are provided for dev, staging, and production. Each file has guest access enabled by default; OIDC fields are included as comments ready to fill in.

| Environment | File | Notes |
|---|---|---|
| Development | `deploy/helm/environments/dev/values.yaml` | Guest access, minimal resources |
| Staging | `deploy/helm/environments/staging/values.yaml` | Guest access or OIDC |
| Production | `deploy/helm/environments/prod/values.yaml` | HA PostgreSQL, ODF backups, OIDC recommended |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    IBM Fusion Platform                   │
│                                                          │
│  ┌──────────────────┐      ┌──────────────────┐        │
│  │  RHDH Operator   │      │ Postgres Operator│        │
│  └────────┬─────────┘      └────────┬─────────┘        │
│           │ manages                  │ manages           │
│           ▼                          ▼                   │
│  ┌──────────────────┐      ┌──────────────────┐        │
│  │   Backstage CR   │      │ PostgresCluster  │        │
│  │  (3 replicas)    │◄────►│  (3 instances)   │        │
│  └──────────────────┘      └──────────────────┘        │
│           │                                              │
│           ▼                                              │
│  OpenShift AI (optional) — model discovery               │
└─────────────────────────────────────────────────────────┘
```

## Documentation

| Topic | Link |
|---|---|
| Full deployment guide | [QUICKSTART.md](QUICKSTART.md) |
| Helm blog post | [IBM Community — Fusion Developer Hub Quickstart](https://community.ibm.com/community/user/blogs/anushka-jaiswal/2026/05/29/quickstart-developer-hub-on-ibm-fusion-with-redhat) |
| Homepage customization | [QUICKSTART.md — Section 3.1](QUICKSTART.md#31-customize-homepage) |
| GitHub integration | [QUICKSTART.md — Section 3.3](QUICKSTART.md#33-configure-github-integration) |
| RHOAI model registry | [QUICKSTART.md — Section 3.4](QUICKSTART.md#34-rhoai-model-registry-integration) |
| Upgrade & rollback | [QUICKSTART.md — Section 5](QUICKSTART.md#upgrade) |
| Troubleshooting | [QUICKSTART.md — Troubleshooting](QUICKSTART.md#troubleshooting) |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/IBM/storage-fusion/issues)
- **IBM Fusion Support**: Contact your IBM Fusion support team
