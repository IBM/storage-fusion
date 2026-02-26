# 🚀 Enterprise RAG Chatbot on Red Hat OpenShift AI & IBM Fusion HCI

This project demonstrates how to deploy and validate an **enterprise-grade Retrieval-Augmented Generation (RAG) chatbot** on **Red Hat OpenShift AI (RHOAI)** running on **IBM Fusion HCI**.

It combines scalable infrastructure, GPU-backed inference, and enterprise-ready orchestration for a production-style RAG setup.

---

## 📌 What You’ll Build

A layered enterprise RAG system with:

- **IBM Fusion HCI** as the infrastructure foundation
- **Red Hat OpenShift AI** for pipelines and model serving
- **Llama Stack API** for RAG orchestration and safety controls
- **vLLM** for high-performance LLM inference
- **Docling + Kubeflow Pipelines** for document ingestion and embedding workflows

---

## 🧭 Table of Contents

- [Overview](#-overview)
- [Architecture High-Level](#-architecture-high-level)
- [Tested Stack Example](#-tested-stack-example)
- [Prerequisites](#-prerequisites)
- [Models Used Examples](#-models-used-examples)
- [End-to-End Workflow](#-end-to-end-workflow)
- [Deployment Quickstart-Style](#-deployment-quickstart-style)
- [Verification Checklist](#-verification-checklist)
- [Troubleshooting Tips](#-troubleshooting-tips)
- [Why This Matters Enterprise Perspective](#-why-this-matters-enterprise-perspective)
- [References](#-references)

---

## 🔍 Overview

Enterprise AI systems need more than a powerful LLM. They need:

- **Grounded answers** from enterprise knowledge
- **Data privacy** and controlled access
- **Scalable inference**
- **Operational reliability**
- **Safety guardrails**

This setup is designed to address those requirements using an OpenShift-native deployment model.

---

## 🏗️ Architecture (High-Level)

### 1) Foundation Layer — IBM Fusion HCI
Provides the infrastructure backbone for AI workloads:

- NVMe-backed high-performance storage
- GPU-capable compute nodes
- Integrated OpenShift platform
- S3-compatible object storage via Fusion Data Foundation (FDF)

### 2) Engine Layer — Red Hat OpenShift AI (RHOAI)
Runs the operational AI pipelines:

- **Ingestion pipeline** (Docling + Kubeflow Pipelines)
- **Vector database** (for example, Milvus / PGVector)
- **Inference runtime** using **vLLM**

### 3) Brain Layer — Llama Stack API Service
Coordinates the RAG conversation flow:

- Retrieval orchestration
- Prompt augmentation
- Agentic logic / tool selection
- Safety checks (input/output guardrails)

---

## ✅ Tested Stack (Example)

> **Note:** Update versions below to match your exact environment / blog screenshots.

- **OpenShift Container Platform (OCP):** `4.19.x`
- **NVIDIA GPU Operator:** `25.x`
- **Red Hat OpenShift Serverless:** `1.37.x`
- **Red Hat OpenShift AI (RHOAI):** `2.25.x`
- **GPU example:** `NVIDIA H100`

---

## 📋 Prerequisites

Before deployment, ensure the following are available.

### Platform / Infrastructure
- Red Hat OpenShift cluster
- Red Hat OpenShift AI installed
- NVIDIA GPU Operator installed and healthy
- At least **1 NVIDIA GPU** available for vLLM inference
- S3-compatible storage (Fusion FDF object bucket works well)
- Persistent storage for vector DB and pipeline assets

### Access / Tools
- `oc` CLI access to the cluster
- `helm` installed
- `jq` installed (used by some scripts)
- Hugging Face token
- Approved access to:
  - Meta Llama model(s)

---

## 🧠 Models Used (Examples)

- `meta-llama/Llama-3.2-3B-Instruct`
- `meta-llama/Llama-3.1-8B-Instruct`

> Choose model size based on available GPU memory, throughput needs, and latency targets.

---

## 🔄 End-to-End Workflow

### Phase 1 — Ingestion Path (Teach the system)
1. Pull raw documents (PDFs / wikis / manuals) from source storage (S3/Git).
2. Parse and clean content using **Docling**.
3. Chunk and embed content through **Kubeflow Pipelines**.
4. Store embeddings in a **Vector Database** for retrieval.

### Phase 2 — Inference Path (Answer questions)
1. User asks a question in the chat UI.
2. Llama Stack retrieves relevant chunks from the vector DB.
3. The system augments the prompt with retrieved context.
4. vLLM generates the response on GPU.
5. The chatbot returns a grounded answer.

---

## ⚙️ Deployment (Quickstart-Style)

> This follows a Helm-based deployment flow similar to the Red Hat Enterprise RAG quickstart.

### 1) Clone the RAG repo
```bash
git clone https://github.com/rh-ai-quickstart/RAG
cd RAG/deploy/helm
```

### 2) Log in to your OpenShift cluster
```bash
oc login --token=<token> --server=<server>
```

### 3) Confirm GPU is allocatable
```bash
oc get node <node-name> -o jsonpath='{.status.allocatable.nvidia\.com/gpu}{"\n"}'
```

If your GPU nodes are tainted, inspect taints:
```bash
oc get nodes -l nvidia.com/gpu.present=true -o yaml | grep -A 3 taint
```

Example taint output:
```yaml
taints:
  - effect: NoSchedule
    key: nvidia.com/gpu
    value: "true"
```

### 4) List available models
```bash
make list-models
```

### 5) Install the stack (example)
```bash
make install NAMESPACE=llama-stack-rag \
  LLM=llama-3-2-3b-instruct
```

You may be prompted for:
- Hugging Face token
- Tavily Search API key (optional, for web-search-enabled agent flows)

---

## ✅ Verification Checklist

Use this checklist after installation to confirm the stack is healthy end-to-end.

### 1) Pods in the RAG namespace
```bash
oc get pods -n llama-stack-rag -w
```

**Expected:** Pods should move to `Running` or `Completed` as applicable.

---

### 2) Data Science Pipelines
In **Red Hat OpenShift AI → Data Science Pipelines → Runs**:
- Confirm successful ingestion pipeline runs for the RAG project.

---

### 3) Workbench / Notebook
In **Data Science Projects**:
- Start and verify the `rag-pipeline-notebook` (or equivalent workbench).

---

### 4) Model Deployments
In **Models → Model deployments**:
- Confirm the vLLM-backed model deployment is **Started / Running**.

---

### 5) Chat UI Route
In **Networking → Routes**:
- Open the `rag` route (or your deployed chat app route).
- Verify the chatbot UI loads and answers queries.

---

## 🛠️ Troubleshooting Tips

### GPU not detected
- Verify NVIDIA GPU Operator pods are healthy
- Check node labels and allocatable GPU resources

```bash
oc get nodes --show-labels | grep -i nvidia
oc get node <node-name> -o jsonpath='{.status.allocatable.nvidia\.com/gpu}{"\n"}'
```

---

### Model pod pending / unschedulable
- Check node taints and pod tolerations
- Verify GPU memory is sufficient for the selected model
- Inspect pod events

```bash
oc describe pod <pod-name> -n llama-stack-rag
```

---

### Route opens but app is not serving
- Check backing pods and services
- Inspect route + endpoints

```bash
oc get route -n llama-stack-rag
oc get svc -n llama-stack-rag
oc get endpoints -n llama-stack-rag
```

---

### Ingestion pipeline failed
- Check pipeline run logs in the RHOAI UI
- Verify source bucket / credentials
- Verify vector DB connectivity and PVC health

---

## 🌍 Why This Matters (Enterprise Perspective)

This architecture helps solve common enterprise AI problems:

- **Performance** → Fast retrieval + GPU-backed inference
- **Safety** → Centralized guardrails and policy controls
- **Scale** → Kubernetes/OpenShift-native deployment and scaling
- **Reliability** → Managed components with self-healing behavior
- **Governance** → Controlled data ingestion and enterprise platform integration

---

## 🔗 References
- TechXchange blog post: [**Building an Enterprise RAG Chatbot on Red Hat OpenShift AI & IBM Fusion HCI**](https://community.ibm.com/community/user/blogs/rupali3/2026/02/25/building-an-enterprise-rag-chatbot-on-red-hat-open)
- Red Hat Developer: [**Deploy an enterprise RAG chatbot with Red Hat OpenShift AI**](https://developers.redhat.com/articles/2026/01/29/deploy-enterprise-rag-chatbot-red-hat-openshift-ai)
- Red Hat AI Quickstarts: [**Enterprise RAG Chatbot**](https://github.com/rh-ai-quickstart/RAG)
- IBM Fusion HCI / Fusion Data Foundation documentation: [**IBM Fusion HCI documentation**](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.0)


---