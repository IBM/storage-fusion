# Deploying NVIDIA AI-Q on IBM Fusion HCI

## Running NVIDIA AI Enterprise Blueprints on a Production-Ready OpenShift Platform

Generative AI blueprints are increasingly delivered as Kubernetes-native applications. NVIDIA AI-Q is one such blueprint — designed to help teams build deep research and document-driven AI workflows using Retrieval-Augmented Generation (RAG) and GPU-accelerated inference.

However, deploying an AI blueprint is only part of the story. For developers and SREs, the real challenge is running these applications reliably on an enterprise-grade platform — one that supports standardized deployment, GPU-enabled infrastructure, and operational best practices.

In this blog, we walk through how to deploy and run the NVIDIA AI-Q blueprint on IBM Fusion HCI, using standard OpenShift and Helm-based workflows. The goal is not just to deploy AI-Q, but to demonstrate how Fusion HCI can serve as a foundation for enabling NVIDIA AI Enterprise (NVAIE) blueprints as part of a broader enterprise AI platform strategy.

This article is intended for developers, platform engineers, and SREs who want to:

- Deploy the NVIDIA AI-Q blueprint on IBM Fusion HCI
- Understand how AI-Q fits into an OpenShift-based AI platform
- Use standard OpenShift namespaces and Helm workflows on Fusion HCI
- Apply best practices for operating GPU-enabled AI workloads in production

---

## What Is NVIDIA AI-Q?

NVIDIA AI-Q is a research assistant blueprint that helps users extract insights from documents using generative AI. It combines:

- RAG pipelines for document-based Q&A
- GPU-accelerated LLM inference
- Multi-stage reasoning and validation
- A simple UI for running research workflows

Unlike a simple chatbot, AI-Q represents a full AI workflow, making it ideal for validating enterprise AI platforms like IBM Fusion HCI.

---

## Why IBM Fusion HCI?

IBM Fusion HCI is a Kubernetes-native platform built on Red Hat OpenShift, designed to run stateful and GPU-accelerated workloads in an enterprise environment. It provides a consistent operational foundation for deploying and managing AI applications using standard Kubernetes and OpenShift constructs.

For AI workloads such as NVIDIA AI-Q, Fusion HCI offers:

- Predictable GPU scheduling and utilization using OpenShift in combination with the NVIDIA GPU Operator
- Secure, controlled deployment within enterprise infrastructure
- A unified platform for multiple AI blueprints on the same OpenShift-based environment

---

## Prerequisites

Before deploying NVIDIA AI‑Q, ensure the following are in place:

- IBM Fusion HCI cluster installed and running.

- GPU-enabled OpenShift worker nodes (Fusion HCI automatically installs and configures the NVIDIA GPU Operator for GPU workloads).

Note: We used NVIDIA L40 GPUs for this AIQ deployment. Exact requirements vary by GPU model and workload — refer to NVIDIA’s documentation for specific GPU and memory recommendations.

- Persistent storage via IBM Fusion Data Foundation or another storage provider.

- NVIDIA RAG Blueprint deployed (required by AI‑Q).

- CLI tools: oc and Helm v3.19.4 installed and configured.

Note: Helm v3.19.4 is the validated version for NVIDIA AI‑Q.

💡 Tip: To check how many GPUs are available on a node, describe the node and look at the allocatable GPU resources:
```
oc describe node <node-name> | grep -E "Capacity|Allocatable|nvidia.com/gpu"
```

You’ll see output like `nvidia.com/gpu: 4`, which indicates how many GPUs the node can schedule for workloads.

---

## Step 1: Generate Required API Keys

AI-Q requires two external APIs:

- NVIDIA NGC API Key — pulls containers and model artifacts
- Tavily API Key — for web-based search and enrichment

Export the keys on your system:

```
export NGC_API_KEY="<your-ngc-api-key>"
export TAVILY_API_KEY="<your-tavily-api-key>"
```

## Step 2: Create a Namespace for AI-Q

Create a dedicated namespace to isolate AI-Q components from other workloads:

```
oc create namespace aiq
```

## Step 3: Download the NVIDIA AI-Q Helm Chart

```
wget https://helm.ngc.nvidia.com/nvidia/blueprint/charts/aiq-aira-v1.2.0.tgz
tar -xvf aiq-aira-v1.2.0.tgz
cd aiq-aira
```

This Helm chart packages all AI-Q components, including UI, backend, and model serving configuration.
After extracting, the aiq-aira directory contains the following files and folders:

```
Chart.lock

Chart.yaml

charts/

files/

templates/

values.yaml
```

## Step 4: Configure the Model in values.yaml

Select the model you want AI-Q to use. In this deployment, we chose llama-3.2-3b-instruct

To configure this, update the model name in the values.yaml file located in the aiq-aira directory. The snippet below shows an example configuration using the llama-3.2-3b-instruct model:

```
# ------------------------------------------------------------
# The following values are for the AIQ AIRA backend service.
# ------------------------------------------------------------

replicaCount: 1

imagePullSecret:
  name: "ngc-secret"
  registry: "nvcr.io"
  username: "$oauthtoken"
  password: ""
  create: true

ngcApiSecret:
  name: "ngc-api"
  password: ""
  create: true

tavilyApiSecret:
  name: "tavily-secret"
  create: true
  password: ""

# The image repository and tag for the AIQ AIRA backend service.
image:
  baserepo: nvcr.io
  repository: nvcr.io/nvidia/blueprint/aira-backend
  tag: v1.2.0
  pullPolicy: Always

# The service type and port for the main AIQ AIRA backend service
service:
  port: 3838

backendEnvVars:
  # update the model name here
  INSTRUCT_MODEL_NAME: "meta-llama/llama-3.2-3b-instruct"
  INSTRUCT_MODEL_TEMP: "0.0"
  NEMOTRON_MAX_TOKENS: "5000"
  INSTRUCT_MAX_TOKENS: "20000"
  INSTRUCT_BASE_URL: "http://instruct-llm:8000"
  INSTRUCT_API_KEY: "not-needed"
  NEMOTRON_MODEL_NAME: "nvidia/llama-3.3-nemotron-super-49b-v1.5"
  NEMOTRON_MODEL_TEMP: "0.5"
  NEMOTRON_BASE_URL: "http://nim-llm.rag.svc.cluster.local:8000"
  AIRA_APPLY_GUARDRAIL: "false"
  RAG_SERVER_URL: "http://rag-server.rag.svc.cluster.local:8081"
  RAG_INGEST_URL: "http://ingestor-server.rag.svc.cluster.local:8082"
  
nim-llm:
  enabled: true
  service:
    name: "instruct-llm"
  image:
      # update the model name here
      repository: nvcr.io/nim/meta/llama-3.2-3b-instruct
      pullPolicy: IfNotPresent
      tag: "1.10.1"
  resources:
    limits:
      nvidia.com/gpu: 2
    requests:
      nvidia.com/gpu: 2
  # Configure NIM Model Profile for optimal performance
  env:
    - name: NIM_MODEL_PROFILE
      value: ""  # Empty for automatic selection, or specify tensorrt_llm profile
  model:
    ngcAPIKey: ""
    # update the model name here
    name: "meta-llama/llama-3.2-3b-instruct"
```

Note: Model tag and GPU requirements were validated using NVIDIA’s documentation: https://docs.nvidia.com/nim/large-language-models/latest/supported-models.html


## Step 5: Deploy NVIDIA AI-Q Using Helm

```
helm install aiq-aira . \
  --username='$oauthtoken' \
  --password=$NGC_API_KEY \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set tavilyApiSecret.password=$TAVILY_API_KEY \
  -n aiq
```
This will deploy all AI-Q components into the aiq namespace.

## Step 6: Verify all the pods in namespace aiq:

Run below oc command to get the status of all pods in namespace aiq

```
oc get pods -n aiq
```

Expected output:
```
aiq-aira-aira-backend-7cd46449bd-snbsm    1/1     Running   0          3h8m
aiq-aira-aira-frontend-59d9c897f6-c47z9   1/1     Running   0          3h8m
aiq-aira-nim-llm-0                        1/1     Running   0          177m
aiq-aira-phoenix-78fd7584b7-ntllt         1/1     Running   0          3h8m
```

This confirms that all the pods are running and their containers are ready.
Now we are good to try out accessing AIQ-UI


## Step 7: Access the AI-Q UI

To access the AI-Q user interface, first identify the frontend service:

```oc get svc -n aiq | grep frontend```

Example Output:

```
aiq-aira-aira-frontend   NodePort   3000:30080/TCP
```

Make a note of the NodePort value (for example, 30080).
You can now access the AI-Q UI using the cluster node name or IP:

```
http://<cluster-node-name-or-ip>:30080
```

![AI-Q UI Overview](https://cdn-images-1.medium.com/max/1600/1*GbW-Exa_pogBXUhDBFjKgw.png)


On clicking on the option Begin Researching , we will see the page as shown below:

![alt text](https://miro.medium.com/v2/resize:fit:1400/format:webp/1*MmfOzn9meHXI-eL5c7KEqg.png)

## Step 8: Upload Enterprise Documents

On the UI:

- Click New Collection
- Upload the required documents (PDFs, manuals, technical documentation, etc.)
- Wait for the documents to be uploaded and indexed

![alt text](https://miro.medium.com/v2/resize:fit:1400/format:webp/1*YzDU2J3UOqG3H6yH6Gz4uQ.png)

Note: Processing time depends on document size.

## Step 9: Generate AI-Powered Research Reports

Once the documents are indexed, AI-Q is ready to generate insights.

1. Define the Report Topic: Start by defining a report topic. In this example, we used.
Example: IBM Fusion HCI deployment configurations

2. Provide a Report Structure: A simple structure helps AI-Q organize its output. For example:

Give a simple overview of IBM Fusion HCI using the selected documents
Explain:
- What IBM Fusion HCI is
- What it is used for
- Its main components

3. Select Document Sources: Choose the document collection you want AI-Q to use and click Select Sources.

![alt text](https://miro.medium.com/v2/resize:fit:1400/format:webp/1*BeKfxn5B5icOZdjriIiM5g.png)

4. Start the Generation Process : Click Start Generating.

![alt text](https://miro.medium.com/v2/resize:fit:1400/format:webp/1*XDdx6SdG8s5ZdaTN0XCuaA.png)

AI-Q will process your topic and structure, preparing to create the report.

![alt text](https://miro.medium.com/v2/resize:fit:1400/format:webp/1*QjE2DHlAkwDJRZKJI_xwfA.png)

5. Execute the Plan: Once the thinking phase completes, click Execute Plan to trigger AI-Q’s full execution pipeline

![alt text](https://miro.medium.com/v2/resize:fit:1400/format:webp/1*uwtPD9M7InxQhLcXdMz9DQ.png)

6. How AI-Q generates the report:
Behind the scenes, AI-Q processes the request through multiple stages:

- RAG Answer — extracts info from documents
- Relevancy Check — validates content
- Web Answer — supplements info (if enabled)
- Summarize Sources — condenses findings
- Running Summary — structures output
- Reflect on Summary — improves clarity


![alt text](https://miro.medium.com/v2/resize:fit:1400/format:webp/1*GwizReSVtTi6qQ0JmskEzg.png)
AI-Q execution pipeline

7. Download the Final Report: Once all stages complete, AI-Q produces a final, structured research report, which can be downloaded directly from the UI.

On clicking on the option Begin Researching , we will see the page as shown below:

![alt text](https://miro.medium.com/v2/resize:fit:1400/format:webp/1*N_njerUy9k_lQcRuiB1SNQ.png)

## Use Cases / Benefits

Running NVIDIA AI-Q on IBM Fusion HCI provides several practical benefits for enterprises:

1. Automated deployment reporting : AI-Q can generate structured reports from Fusion HCI documentation, deployment guides, or operational runbooks using RAG pipelines.

2. Knowledge extraction for SRE and operations teams: Internal manuals, troubleshooting guides, and configuration documents can be indexed and queried to quickly surface relevant information during day-to-day operations.

## Final Thoughts

By deploying NVIDIA AI-Q on IBM Fusion HCI, we’ve demonstrated how quickly enterprise AI workloads can be enabled and how Fusion HCI simplifies AI infrastructure operations.

From RAG pipelines to fine-tuned models and automated AI workflows, IBM Fusion HCI provides a robust foundation for scaling AI initiatives across the enterprise.

This is just the beginning. From RAG pipelines to fine-tuned models and automated AI workflows, IBM Fusion HCI provides a strong foundation for enterprise AI at scale.



