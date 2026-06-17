# Unlocking AI-Powered Video Analytics on IBM Fusion HCI using NVIDIA VSS

Visual data has become one of the fastest-growing information sources in modern organizations. Enterprises capture massive amounts of video footage across facilities, production lines, retail environments, data centers, and operational sites. Yet most of this data remains effectively unusable — accessible only through time-consuming manual review.

Finding a specific event often requires scrubbing through hours of recordings. Answering simple questions like *“What happened during the night shift?”* can demand significant time and operational effort.

The fundamental challenge isn’t capturing video — it’s making that video searchable, understandable, and actionable.

This transformation is now possible with **NVIDIA Video Search and Summarization (VSS)** — an AI-powered visual intelligence blueprint built for production environments.

This article walks through a validated deployment of NVIDIA’s VSS Blueprint on **IBM Fusion HCI** with **Red Hat OpenShift**, following [NVIDIA’s official Helm-based deployment guide.](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html)

## What This Article Covers

This technical walk-through provides complete, step-by-step instructions for deploying NVIDIA VSS on IBM Fusion HCI:

- Infrastructure prerequisites and validation  
- Detailed Helm deployment with GPU configuration  
- Troubleshooting common deployment challenges  
- Production considerations for scaling and optimization  

## NVIDIA Video Search and Summarization (VSS)

NVIDIA’s VSS Blueprint transforms video from a passive recording into an intelligent, queryable knowledge base. Built on state-of-the-art AI models and designed for real-world deployment, VSS delivers:

- Automated video summarization with timestamped key events  
- Natural language Q&A over video content  
- Semantic search that understands meaning and context  
- Flexible processing for both live streams and archived footage  

The architecture combines three powerful AI capabilities:

- **Cosmos-Reason2 8B VLM** for visual understanding  
- **Llama 3.1 70B LLM** for natural language reasoning  
- **NeMo embedding and reranking models** for intelligent retrieval  

Together, these components convert raw video into structured, searchable intelligence.

## Why IBM Fusion HCI Provides the Ideal Foundation

Deploying AI-driven video intelligence requires more than GPUs. It demands tightly integrated compute, persistent storage, vector database infrastructure, and container orchestration — all operating cohesively.

IBM Fusion Platform HCI provides:

- **Integrated GPU compute and persistent storage**  
  Unified compute and storage eliminate external storage dependencies while supporting model caching, vector databases, and metadata persistence.

- **OpenShift-based cloud-native orchestration**  
  Deploy AI microservices as containers with lifecycle management and scaling built in.

- **Single platform for multiple AI workloads**  
  Vision models, large language models, and embedding services run together with simplified operations and optimized data locality.

- **Operational consistency**  
  A unified management interface, centralized backup strategy, and validated lifecycle workflows reduce deployment complexity.

This deployment validates that IBM Fusion HCI provides a production-ready foundation for NVIDIA’s VSS Blueprint.

## VSS Architecture Overview

VSS processes video using two coordinated pipelines:

- **Ingestion Pipeline**
- **Retrieval Pipeline**

### Ingestion Pipeline Flow

1. Video is split into short chunks and distributed across GPUs in parallel.
2. Frames are sampled from each chunk and passed to the Vision Language Model (Cosmos-Reason2 8B by default).
3. The VLM generates timestamped natural language captions.
4. Optional components:
   - Audio transcription via Riva ASR
   - Computer vision metadata (object detection)
5. Outputs are merged into structured caption data.

### Retrieval Pipeline Flow

1. Captions are converted into vector embeddings using NeMo Retriever.
2. Embeddings are indexed into Milvus for semantic search.
3. The LLM populates a Neo4j knowledge graph with structured event data.
4. Summarization aggregates captions into a time-anchored summary.
5. For Q&A:
   - User query searches vector DB and knowledge graph
   - NeMo Reranker rescoring occurs
   - Top context is passed to the LLM for grounded response generation

The result: natural language querying over video with enterprise-grade performance.

## Prerequisites

Before deploying NVIDIA VSS, ensure the following requirements are met.

### 1. Infrastructure

- IBM Fusion HCI cluster installed and running.
- Fusion HCI v2.12+ includes GPU Operator pre-installed.
- For earlier versions, install NVIDIA GPU Operator manually.

### 2. GPU Requirements

VSS supports multiple deployment configurations depending on hardware.

#### Default Configuration (Recommended Production Setup)

**8 GPUs (H100 / H200 / B200 / A100 80GB+) on a single node**

| Component | GPUs |
|------------|------|
| LLM (Llama 3.1 70B) | 4 |
| VSS (VLM processing) | 2 |
| NeMo Embedding | 2 |
| NeMo Reranking | 1 |

> Note: This guide follows the default configuration using 8 H200 GPUs.

#### Other Options

- Customized GPU allocation (explicit GPU-to-service pinning)
- Fully local single GPU deployment (dev/test environments)

Verify GPU availability:

```bash
oc describe node <your-node> | grep nvidia.com/gpu
```

### 3. Storage

This reference deployment uses IBM Fusion Data Foundation v4.18.

If unavailable, configure a local path provisioner:

```bash
oc apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

oc patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 4. Model Access & Credentials

You will need:

- **NGC API Key** for NVIDIA container images  
- **Hugging Face Token** for Cosmos-Reason2 8B model access  

Steps:

- Register for NGC API key at https://ngc.nvidia.com  
- Generate Hugging Face token  
- Accept model terms at https://huggingface.co/nvidia/Cosmos-Reason2-8B  

### 5. Tooling

- Helm v3.19.4 (validated version)  
- OpenShift CLI (oc)  

Validate:

```bash
helm version
oc version
oc whoami
```

# Deployment Steps

For full configuration options, refer to NVIDIA’s [official](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html) Helm documentation.

### Step 1: Create Secrets

Export credentials:

```bash
export NGC_API_KEY=<YOUR_LEGACY_NGC_API_KEY>
export HF_TOKEN=<YOUR_HUGGING_FACE_TOKEN>
```

Create required secrets:

```bash
oc create secret docker-registry ngc-docker-reg-secret \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password=$NGC_API_KEY

oc create secret generic ngc-api-key-secret \
    --from-literal=NGC_API_KEY=$NGC_API_KEY

oc create secret generic hf-token-secret \
    --from-literal=HF_TOKEN=$HF_TOKEN

oc create secret generic graph-db-creds-secret \
    --from-literal=username=neo4j --from-literal=password=password

oc create secret generic arango-db-creds-secret \
    --from-literal=username=root --from-literal=password=password

oc create secret generic minio-creds-secret \
    --from-literal=access-key=minio --from-literal=secret-key=minio123
```

### Step 2: Fetch the Helm Chart

```bash
helm fetch \
https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-vss-2.4.1.tgz \
--username='$oauthtoken' --password=$NGC_API_KEY
```

### Step 3: Deploy

```bash
helm install vss-blueprint nvidia-blueprint-vss-2.4.1.tgz \
  --set global.ngcImagePullSecretName=ngc-docker-reg-secret \
  --set nim-llm.persistence.size=200Gi
```

### Why 200Gi?

The default 50Gi PVC is insufficient for the Llama 3.1 70B model. Increasing to 200Gi ensures adequate model storage.

Installation time may vary from a few minutes to an hour depending on network speed and model caching.

### Step 4: Verify Deployment

Check pods:

```bash
oc get pods -n default
```

Check services:

```bash
oc get svc -n default
```

Deployment is complete when all pods show:

- STATUS: Running  
- READY: 1/1 (or appropriate replica count)  

### Troubleshooting

### Nemo Rerank Pod Fails

If `nemo-rerank-ranking-deployment` does not start:

```bash
oc scale deployment nemo-rerank-ranking-deployment --replicas=0

oc patch deployment nemo-rerank-ranking-deployment \
-p '{"spec":{"template":{"spec":{"securityContext":{"fsGroup":1000,"runAsUser":1000,"runAsGroup":1000}}}}}'

oc scale deployment nemo-rerank-ranking-deployment --replicas=1
```

### Step 5: Access the UI

```bash
oc get svc vss-service
```

From the output:

- Port 8000 → REST API  
- Port 9000 → UI  

Open:

```
http://<NODE_IP>:<NODEPORT_FOR_9000>
```

# Validation & Testing

After deployment:

1. Open the VSS UI.  
2. Upload a sample video.  

<img width="1546" height="920" alt="image" src="https://github.com/user-attachments/assets/0c8c1ba8-9c74-41c2-b9bb-b4c8013336c0" />

3. Select chunk size (recommended: 5 seconds).  
4. Configure prompts as needed. The examples below are templates — adjust them based on the type of video being uploaded and the level of technical detail required.

    
    #### Prompt
    ```bash
    Summarize this demo video in a completed long paragraph. Explain how the MCP (Model Context Protocol) server is integrated with Watson Orchestrate. Explain what is happening in this video step by step. Identify any products, platforms, tools, workflows, and technical concepts shown. Describe the full process clearly.
    ```
    #### Caption Summarization Prompt

    ```bash
    Watch this video and generate a clear technical paragraph describing the main workflow demonstrated. Identify the platforms, services, tools, and integration steps shown. Explain how the system is configured, how components are connected, how functionality is validated, and how the final solution is deployed. Keep the paragraph simple, technical, and focused on process rather than marketing language.
    
    Break the video into 30–40 second timestamp segments. For each segment, briefly describe what happens, including any setup steps, UI actions, commands, configuration changes, or validation shown. If a major action occurs (such as integration, testing, or deployment), highlight it clearly even if it does not align exactly with the 30–40 second window.
    ```
    #### Summary Aggregation Prompt

    ```bash
    Generate a concise technical summary of this integration demo using the following structure:
    
    #### 1. OVERVIEW  
    Explain the goal of the demo and what problem the solution addresses.
    
    #### 2. WORKFLOW SUMMARY  
    Describe the main steps shown, including platform connection, service configuration, tool integration, validation or testing, and final deployment.
    
    #### 3. KEY FEATURES DEMONSTRATED  
    Summarize the core capabilities shown such as integration workflow, agent or service creation, tool ingestion, authentication, data querying, and deployment.
    
    #### 4. TECHNICAL ARCHITECTURE (HIGH LEVEL)  
    Explain how the main components interact, including orchestration platform, backend services, infrastructure layer, and data sources.
    
    #### 5. CONCLUSION  
    Summarize the final outcome and how this workflow supports enterprise AI or automation use cases.
    
    Keep everything technical, concise, and non-repetitive. Use short paragraphs.
    ```
6. Click **Summarize**.  

<img width="1546" height="940" alt="image" src="https://github.com/user-attachments/assets/758294eb-0c13-43c8-bbf0-df0418d4f864" />

To monitor processing:

```bash
oc logs -f vss-vss-deployment-<pod-id> -n default
```

Once complete, the summary appears in the UI.

<img width="1538" height="924" alt="image" src="https://github.com/user-attachments/assets/8d5ad6e1-8725-420e-b777-52d350b37bc7" />

You can Ask natural language questions  

<img width="1540" height="926" alt="image" src="https://github.com/user-attachments/assets/6e6ebdd7-3e36-406f-b536-f5cce784c97c" />

Higlights can also be generated for the uploaded video file.

<img width="1552" height="936" alt="image" src="https://github.com/user-attachments/assets/f5dc2903-ea66-4dc5-9013-61c8cc9dfd75" />

# What We Achieved

By deploying NVIDIA VSS on IBM Fusion HCI:

- Video is ingested, captioned, and indexed.  
- Content becomes searchable using natural language.  
- Query response time reduces from hours of manual review to seconds.  
- Entire system runs on-premises with GPU acceleration.  
- All services are orchestrated through OpenShift.  

This validates IBM Fusion HCI as a production-ready platform for enterprise AI-powered video analytics.


# Extending VSS

### Audio Transcription (Riva ASR)

Optional capability:

- Adds speech-to-text transcription  
- Merges spoken content with visual captions  
- Ideal for briefings, announcements, and training videos  

**Requirements:**

- 1 additional GPU (can share on 80GB+ GPUs)  
- Model: `parakeet-0-6b-ctc-riva-en-us`  

Refer to NVIDIA’s audio deployment guide for configuration details.

---

# Explore Further

- To learn more about IBM Fusion HCI, explore the [IBM Fusion documentation](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.x?topic=installing)
- For detailed Helm deployment options, refer to the NVIDIA VSS Helm [deployment](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html) guide
- Model specifications and supported configurations are available in the [NVIDIA NIM documentation](https://docs.nvidia.com/nim/large-language-models/latest/supported-models.html)
- Common deployment issues and solutions can be found in the [NVIDIA VSS FAQ](https://docs.nvidia.com/vss/latest/content/faq.html) and [Known Issues](https://docs.nvidia.com/vss/latest/content/known_issues.html)
- To uninstall the deployment, follow the guidance [here.](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html#uninstalling-the-deployment)
