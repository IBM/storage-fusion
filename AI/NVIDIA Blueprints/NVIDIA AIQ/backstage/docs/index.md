# Deploying NVIDIA AI-Q on IBM Fusion HCI

Generative AI blueprints are increasingly delivered as Kubernetes-native applications. NVIDIA AI-Q is one such blueprint — a research assistant that helps teams extract insights from documents using RAG pipelines and GPU-accelerated LLM inference. Unlike a simple chatbot, AI-Q represents a full AI workflow: multi-stage reasoning, relevancy checking, source summarization, and report generation — all in a single deployment.

This guide covers deploying NVIDIA AI-Q on **IBM Fusion HCI** with **Red Hat OpenShift**. Two deployment paths are documented:

- **v2 (Recommended) — OpenShift Software Catalog:** IBM Fusion HCI packages AI-Q v2.2.0 as a Helm chart with images pre-mirrored to IBM Cloud Container Registry (`icr.io/cp/fsh/`). Credentials are handled via a single Kubernetes Secret. PostgreSQL-backed job persistence makes deep-research workloads production-ready.
- **v1 — Helm CLI:** The original deployment path using AI-Q v1.2.0 (aiq-aira) pulled from NVIDIA NGC with NGC and Tavily API keys as Helm `--set` flags.

---

## What Is NVIDIA AI-Q?

NVIDIA AI-Q is a research assistant blueprint that turns document collections into a queryable, AI-powered knowledge base:

- **RAG pipelines** for document-based Q&A — answers grounded in your actual documents
- **Multi-stage reasoning** — RAG answer → relevancy check → web enrichment → summarization → reflection
- **GPU-accelerated LLM inference** via external NIM endpoints
- **PostgreSQL-backed job persistence** (v2) — deep-research jobs survive pod restarts
- **Simple UI** for running research workflows and downloading structured reports

**AI-Q depends on the NVIDIA RAG Blueprint** — it connects to an external RAG server and ingestor endpoint. Deploy RAG first.

---

## Why IBM Fusion HCI?

IBM Fusion HCI is a Kubernetes-native platform built on Red Hat OpenShift, designed to run stateful and GPU-accelerated workloads in an enterprise environment:

- **Predictable GPU scheduling** — OpenShift + NVIDIA GPU Operator reliably schedules GPU-backed AI services
- **IBM-hosted image registry** — in v2, all AI-Q images are pre-mirrored to `icr.io/cp/fsh/`; no NGC pull required
- **Unified multi-blueprint environment** — RAG, AI-Q, and VSS coexist on one cluster
- **Air-gap ready** — v2 can be deployed on disconnected clusters using the same `ImageTagMirrorSet` pattern as other IBM-packaged NVIDIA blueprints

---

## What Changed from v1 to v2

| | v1 (AI-Q v1.2.0 / aiq-aira) | v2 (AI-Q v2.2.0) |
|---|---|---|
| **Deployment** | Helm CLI from NGC | OpenShift Software Catalog |
| **Image source** | NVIDIA NGC (`nvcr.io`) | IBM Cloud Registry (`icr.io/cp/fsh/`) |
| **NGC credentials** | Required (`--set imagePullSecret.password=...`) | Not required |
| **Tavily API key** | Required | Not required (optional web enrichment) |
| **Secret management** | Helm `--set` flags at install time | Pre-created `aiq-credentials` Secret; auto-mounted |
| **Job persistence** | None — jobs lost on pod restart | PostgreSQL backend — jobs survive restarts |
| **Chart name** | `aiq-aira` | `aiq` |

---

## Prerequisites

- IBM Fusion HCI cluster installed and running
- GPU-enabled OpenShift worker nodes (Fusion HCI automatically installs the NVIDIA GPU Operator)
- Persistent storage via IBM Fusion Data Foundation or another storage provider
- **NVIDIA RAG Blueprint deployed and reachable** — AI-Q connects to the RAG server and ingestor endpoints
- For **v1 only**: `oc` CLI and Helm v3.19.4

```bash
# Check GPU availability
oc describe node <node-name> | grep -E "Capacity|Allocatable|nvidia.com/gpu"
```

---

## Deployment — v2: OpenShift Software Catalog *(Recommended)*

### Step 1: Generate database credentials

AI-Q v2 uses a PostgreSQL database for job-state persistence. Export the credentials:

```bash
export DB_USER_NAME="aiq"
export DB_USER_PASSWORD="aiq_dev"
```

### Step 2: Create the AI-Q namespace

```bash
oc create namespace aiq
```

### Step 3: Create the credentials Secret

In v2, credentials are pre-created as a Kubernetes Secret and automatically mounted on all pods via `sharedSecrets.autoMount`. This is a deliberate improvement for secret hygiene over v1's `--set` flags.

```bash
oc create secret generic aiq-credentials -n aiq \
  --from-literal=DB_USER_NAME="$DB_USER_NAME" \
  --from-literal=DB_USER_PASSWORD="$DB_USER_PASSWORD"
```

### Step 4: Find AI-Q in the Software Catalog

AI-Q deploys into whichever namespace is selected in the OpenShift Dashboard. Make sure `aiq` is selected.

1. Open the **OpenShift Dashboard**
2. Confirm the `aiq` namespace is selected in the top navigation
3. Navigate to **Ecosystem → Software Catalog**
4. Search for **NVIDIA AI-Q**
5. Click the chart tile → **Create**

### Step 5: Configure the values form

The form pre-populates IBM defaults. The most important update is pointing AI-Q at your deployed RAG Blueprint:

```yaml
aiq:
  apps:
    backend:
      env:
        # --- Update these to point at your RAG Blueprint ---
        RAG_SERVER_URL: http://rag-server.rag.svc.cluster.local:8080
        RAG_INGEST_URL: http://rag-ingest.rag.svc.cluster.local:8080
        COLLECTION_NAME: default_collection
        MODE: web
        FILE_UPLOAD_ACCEPTED_TYPES: .pdf,.docx,.txt,.md
        FILE_UPLOAD_MAX_SIZE_MB: '100'
        FILE_UPLOAD_MAX_FILE_COUNT: '10'

    # Shared secrets — mounts aiq-credentials on all pods automatically
    sharedSecrets:
      enabled: true
      autoMount: true
```

All three images — `aiq-agent`, `aiq-frontend`, and `bitnami/postgresql` — are pre-mirrored to `icr.io/cp/fsh/`. No NGC image-pull secret or authentication flags needed.

### Step 6: Deploy

Click **Create**. OpenShift runs `helm install` in the background and picks up the pre-created `aiq-credentials` Secret automatically. Installation takes a few minutes while images are pulled and the PostgreSQL init container bootstraps the database schema.

> **Note:** The backend pod includes a `db-init` init container that waits for PostgreSQL and runs the schema bootstrap SQL. If the backend shows `Init:0/1` briefly, this is expected.

### Step 7: Verify all pods

```bash
oc get pods -n aiq
```

Expected output (all `Running`, `1/1`):
```
aiq-backend-xxx    1/1   Running
aiq-frontend-xxx   1/1   Running
aiq-postgres-xxx   1/1   Running
```

Verify the PostgreSQL PVC is bound:
```bash
oc get pvc -n aiq
# aiq-postgres-data   Bound   10Gi   RWO   ocs-storagecluster-ceph-rbd
```

### Step 8: Access the AI-Q UI

```bash
oc get route -n aiq
```

Example output:
```
NAME           HOST/PORT                                  PORT
aiq-frontend   aiq-frontend-aiq.apps.<cluster-domain>    3000
```

Open the `HOST/PORT` value in your browser. If you prefer CLI access:
```bash
oc port-forward -n aiq svc/aiq-frontend 3000:3000
# Open http://localhost:3000
```

---

## Deployment — v1: Helm CLI *(AI-Q v1.2.0 / aiq-aira)*

### Step 1: Generate required API keys

```bash
export NGC_API_KEY="<your-ngc-api-key>"
export TAVILY_API_KEY="<your-tavily-api-key>"
```

### Step 2: Create a namespace

```bash
oc create namespace aiq
```

### Step 3: Download the Helm chart

```bash
wget https://helm.ngc.nvidia.com/nvidia/blueprint/charts/aiq-aira-v1.2.0.tgz
tar -xvf aiq-aira-v1.2.0.tgz
cd aiq-aira
```

### Step 4: Configure values.yaml

Select your model. This deployment uses `llama-3.2-3b-instruct`:

```yaml
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

image:
  repository: nvcr.io/nvidia/blueprint/aira-backend
  tag: v1.2.0

backendEnvVars:
  INSTRUCT_MODEL_NAME: "meta-llama/llama-3.2-3b-instruct"
  INSTRUCT_BASE_URL: "http://instruct-llm:8000"
  NEMOTRON_MODEL_NAME: "nvidia/llama-3.3-nemotron-super-49b-v1.5"
  NEMOTRON_BASE_URL: "http://nim-llm.rag.svc.cluster.local:8000"
  RAG_SERVER_URL: "http://rag-server.rag.svc.cluster.local:8081"
  RAG_INGEST_URL: "http://ingestor-server.rag.svc.cluster.local:8082"

nim-llm:
  enabled: true
  service:
    name: "instruct-llm"
  image:
    repository: nvcr.io/nim/meta/llama-3.2-3b-instruct
    tag: "1.10.1"
  resources:
    limits:
      nvidia.com/gpu: 2
    requests:
      nvidia.com/gpu: 2
  model:
    name: "meta-llama/llama-3.2-3b-instruct"
```

### Step 5: Deploy

```bash
helm install aiq-aira . \
  --username='$oauthtoken' \
  --password=$NGC_API_KEY \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set tavilyApiSecret.password=$TAVILY_API_KEY \
  -n aiq
```

### Step 6: Verify pods

```bash
oc get pods -n aiq
```

Expected:
```
aiq-aira-aira-backend-xxx    1/1   Running
aiq-aira-aira-frontend-xxx   1/1   Running
aiq-aira-nim-llm-0           1/1   Running
aiq-aira-phoenix-xxx         1/1   Running
```

### Step 7: Access the UI

```bash
oc get svc -n aiq | grep frontend
# aiq-aira-aira-frontend   NodePort   3000:30080/TCP
```

Open `http://<cluster-node-ip>:30080`.

---

## Air-Gapped (Disconnected) Deployment

### v2 Air-Gap Path

Mirror all AI-Q images to your internal registry, then follow the Software Catalog steps above. Apply an `ImageTagMirrorSet` — no chart value changes needed.

```bash
DEST=<YOUR-INTERNAL-REGISTRY>

skopeo copy docker://icr.io/cp/fsh/nvidia/blueprint/aiq-agent:2.2.0     docker://${DEST}/nvidia/blueprint/aiq-agent:2.2.0
skopeo copy docker://icr.io/cp/fsh/nvidia/blueprint/aiq-frontend:2.2.0  docker://${DEST}/nvidia/blueprint/aiq-frontend:2.2.0
skopeo copy docker://icr.io/cp/fsh/bitnami/postgresql:latest             docker://${DEST}/bitnami/postgresql:latest
```

```yaml
apiVersion: config.openshift.io/v1
kind: ImageTagMirrorSet
metadata:
  name: ibm-fsh-itms-aiq
spec:
  imageTagMirrors:
  - mirrors:
    - <YOUR-INTERNAL-REGISTRY>
    source: icr.io/cp/fsh
```

```bash
oc apply -f ibm-fsh-itms-aiq.yaml
```

---

## Validation & Testing

Once all pods are running, verify AI-Q end-to-end.

### 1. Upload enterprise documents

- Click **New Collection** in the UI
- Upload your documents — PDFs, DOCX, TXT, MD (up to 100 MB each, up to 10 files)
- Wait for indexing to complete (time depends on document size)

### 2. Generate a research report

1. **Define the report topic** — e.g., *"IBM Fusion HCI deployment configurations"*
2. **Provide a report structure:**
   ```
   Give a simple overview of IBM Fusion HCI using the selected documents.
   Explain: what it is, what it is used for, and its main components.
   ```
3. **Select document sources** — click your uploaded collection → **Select Sources**
4. **Click Start Generating** — AI-Q enters its thinking phase
5. **Click Execute Plan** — triggers the full multi-stage execution pipeline:
   - RAG Answer → Relevancy Check → Web Answer → Summarize Sources → Running Summary → Reflect on Summary
6. **Download the final report** — once all stages complete, a structured report is available for download

---

## Use Cases

- **Automated deployment reporting** — generate structured reports from Fusion HCI documentation, deployment guides, and runbooks
- **Knowledge extraction for SRE teams** — index internal manuals and troubleshooting guides; query them during incidents
- **Durable deep-research workflows** (v2) — PostgreSQL persistence means long-running batch research jobs survive pod restarts
- **Air-gap ready enterprise AI** — v2 runs fully offline on restricted-network Fusion HCI clusters

---

## What We Achieved

By deploying NVIDIA AI-Q on IBM Fusion HCI:

- Demonstrated how quickly enterprise AI document-intelligence workloads can be stood up on Fusion HCI
- v2 eliminates NGC dependencies, consolidates credentials into a single auto-mounted Secret, and adds PostgreSQL-backed job persistence — making it meaningfully more production-ready than v1
- The move to IBM-mirrored images makes AI-Q air-gap deployable with the same `ImageTagMirrorSet` pattern used across all IBM-packaged NVIDIA blueprints
- From RAG pipelines to deep-research workflows, IBM Fusion HCI provides a robust, unified foundation for enterprise AI at scale

---

## Further Reading

- [IBM Fusion documentation](https://www.ibm.com/docs/en/fusion-hci-systems)
- [NVIDIA NIM documentation](https://docs.nvidia.com/nim/large-language-models/latest/supported-models.html)
- [IBM Tech Exchange Blog — AI-Q v1](https://community.ibm.com/community/user/blogs/hasrat-ali-arzoo/2026/03/01/deploying-nvidia-ai-q-on-ibm-fusion-hci)
- [IBM Tech Exchange Blog — AI-Q v2](https://community.ibm.com/community/user/blogs/hasrat-ali-arzoo/2026/08/30/deploying-nvidia-ai-q-on-ibm-fusion-hci-v2)
- [NVIDIA AI-Q Blueprint catalog](https://build.nvidia.com/nvidia/aiq)
