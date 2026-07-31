# Fusion AI Platform

A collection of guides, configurations, and sample applications for deploying enterprise AI workloads on **IBM Fusion HCI** with **Red Hat OpenShift AI (RHOAI)**.

The repository is organised as modular, loosely coupled components. Each directory is independently usable; together they form an end-to-end GitOps-managed AI platform.

## Repository Structure

| Directory | Purpose |
|---|---|
| [`fusion-openshift-ai/`](./fusion-openshift-ai/) | Install and configure RHOAI on Fusion HCI |
| [`fusion-model-serving/`](./fusion-model-serving/) | Deploy LLM inference with KServe + vLLM |
| [`fusion-gitops-argocd/`](./fusion-gitops-argocd/) | Bootstrap ArgoCD (OpenShift GitOps) |
| [`fusion-gitops-sample-app/`](./fusion-gitops-sample-app/) | Agentic chat assistant sample app with full GitOps deployment |
| [`fusion-backstage/`](./fusion-backstage/) | Red Hat Developer Hub portal with RHOAI model discovery |
| [`fusion-rh-ai-quickstart/`](./fusion-rh-ai-quickstart/) | RAG chatbot quickstart (Llama Stack, vLLM, Docling, Kubeflow) |
| [`fusion-mig-enablement/`](./fusion-mig-enablement/) | Enable NVIDIA MIG for GPU partitioning |
| [`fusion-inference-sizing/`](./fusion-inference-sizing/) | GPU capacity planning and inference sizing reference |
| [`FusionAIDataService/`](./FusionAIDataService/) | Data ingestion and pipeline infrastructure |
| [`NVIDIA Blueprints/`](./NVIDIA%20Blueprints/) | Validated NVIDIA RAG/AIQ/VSS blueprints for Fusion HCI |
| [`quickstarts/`](./quickstarts/) | Rapid-start guides: MaaS, Developer Hub, GitOps + Vault + ESO |

## Components

### `fusion-openshift-ai/`
Installs and configures Red Hat OpenShift AI on Fusion HCI. Covers three deployment methods (GitOps, Helm, raw Kubernetes manifests) and sets up all RHOAI components: dashboards, workbenches, KServe, model registry, ML pipelines, Ray, and the Training Operator. GPU enablement and storage prerequisites are included.

### `fusion-model-serving/`
Deploys enterprise LLM inference using RHOAI, KServe, and vLLM. Supports multiple models (Granite, Qwen, Ministral) and three deployment paths. Includes configurations for exposing model endpoints externally via OpenShift Routes.

### `fusion-gitops-argocd/`
Bootstrap manifests and RBAC for Red Hat OpenShift GitOps (ArgoCD). Provides the initial `Application` resource and role bindings to enable self-healing, Git-driven continuous deployment across the platform.

### `fusion-gitops-sample-app/`
An end-to-end agentic chat assistant that demonstrates GitOps deployment patterns on Fusion. Highlights include sync-wave orchestration, secret rotation via HashiCorp Vault and External Secrets Operator, and a full ArgoCD application hierarchy.

### `fusion-backstage/`
Deploys Red Hat Developer Hub as an AI developer portal on Fusion. Integrates with RHOAI for automatic model discovery, proxies requests to Fusion Assistant services, and provides golden-path templates for scaffolding new AI applications.

### `fusion-rh-ai-quickstart/`
Quickstart for a production-ready RAG chatbot on RHOAI. Combines Llama Stack, vLLM, Docling (document ingestion), and Kubeflow Pipelines into a guided end-to-end deployment with safety controls.

### `fusion-mig-enablement/`
Guide for partitioning high-end NVIDIA GPUs using Multi-Instance GPU (MIG) technology on Fusion HCI. Covers MIG profile selection, memory allocation, and best practices for running multiple concurrent LLM inference workloads on shared hardware.

### `fusion-inference-sizing/`
Technical reference for GPU capacity planning. Explains inference benchmarking concepts (TFLOPS, memory bandwidth, throughput, latency) and provides practical guidance for right-sizing GPU infrastructure for LLM workloads on Fusion HCI.

### `FusionAIDataService/`
Infrastructure and documentation for data pipelines that feed AI workloads on Fusion HCI. Covers data ingestion, processing, and storage integration.

### `NVIDIA Blueprints/`
Production-ready NVIDIA enterprise AI blueprints (RAG, AIQ, Visual Search) validated for IBM Fusion HCI. Each blueprint includes deployment guides, Backstage catalog integrations, and reference configurations.

### `quickstarts/`
Three self-contained quickstart guides:
- **Model-as-a-Service (MaaS)** — expose models via RHOAI on Fusion
- **IBM Fusion Developer Hub** — Backstage-based AI developer portal
- **GitOps + Vault + ESO** — platform bootstrap with secret management

## License

See [LICENSE](./LICENSE).
