# Unlocking AI-Powered Video Analytics on IBM Fusion HCI using NVIDIA VSS

Visual data is one of the fastest-growing information sources in modern organizations. Enterprises capture massive amounts of video footage across facilities, production lines, retail environments, and data centers — yet most of it remains effectively unusable, accessible only through time-consuming manual review.

**NVIDIA Video Search and Summarization (VSS)** solves this: ingest footage, generate AI-powered timestamped captions, and ask natural-language questions like *"What happened during the morning shift?"* — answered in seconds, not hours.

This guide covers deploying VSS on **IBM Fusion HCI** with **Red Hat OpenShift**. Two deployment paths are documented:

- **v2 (Recommended) — OpenShift Software Catalog:** IBM Fusion HCI 2.14+ packages VSS as a Helm chart in IBM's own repository, with container images pre-mirrored to IBM Cloud Container Registry (`icr.io/cp/fsh/`). The chart appears automatically in the OpenShift Software Catalog — no Helm CLI, no NGC credentials required.
- **v1 — Helm CLI:** The original deployment path using NVIDIA's Helm chart pulled directly from NGC. Still fully valid for clusters running Fusion HCI < 2.14 or for users who prefer CLI-based control.

---

## What Is NVIDIA VSS?

NVIDIA's VSS Blueprint transforms video from a passive recording into an intelligent, queryable knowledge base:

- Automated video summarization with timestamped key events
- Natural language Q&A over video content — ask anything, get grounded answers
- Semantic search that understands meaning and context
- Flexible processing for both live streams and archived footage

### How VSS Works

VSS processes video through two coordinated pipelines:

**Ingestion Pipeline**
1. Video is split into short chunks and distributed across GPUs in parallel
2. A Vision Language Model (VLM) generates timestamped natural language captions per chunk
3. Optional: Riva ASR adds speech-to-text transcription; computer vision modules add object detection metadata
4. Captions are embedded and indexed in a vector store for semantic search

**Retrieval Pipeline**
1. User submits a natural language question
2. Query is converted to a vector embedding and searched against indexed captions
3. Top results are re-ranked by relevance
4. LLM generates a grounded answer with timestamps — fully traceable to source footage

---

## Why IBM Fusion HCI?

Deploying AI-driven video intelligence demands tightly integrated compute, persistent storage, and container orchestration. IBM Fusion HCI provides:

- **Converged GPU compute and storage** — GPU nodes and NVMe-backed storage on the same platform; no external storage dependencies
- **OpenShift-native orchestration** — AI microservices run as containers with lifecycle management, scaling, and RBAC built in
- **Unified multi-blueprint environment** — RAG, AI-Q, and VSS coexist on one cluster, sharing GPU and storage resources
- **IBM Fusion Data Foundation** — provides both RWO (CephRBD) and RWX (CephFS) storage classes that VSS requires out of the box
- **Air-gap readiness** — in v2, all images are pre-mirrored to IBM ICR; no NGC registry access needed at deploy time

---

## Prerequisites

### 1. Infrastructure

- IBM Fusion HCI cluster installed and running
- For the **Software Catalog (v2) path**: IBM Fusion HCI 2.14+ — the Fusion operator automatically registers the VSS chart in the OpenShift Software Catalog at install time
- For the **Helm CLI (v1) path**: any Fusion HCI version with GPU Operator installed; Helm v3.19.4 and `oc` CLI

### 2. GPU Requirements

VSS itself is lightweight on GPU. Requirements depend on whether models run on the same cluster or externally.

**Default configuration with bring-your-own endpoints (`nims.enabled: false`):**

| Component | GPUs |
|---|---|
| VSS core services | 1 A100 / H100 |
| VLM (e.g., Cosmos-Reason2 8B) | External endpoint |
| LLM (e.g., Llama 3.1 70B) | External endpoint |

> This guide uses `nims.enabled: false` — you deploy models separately and supply their endpoint URLs. For the full 8-GPU default config (LLM + VLM on the same cluster), refer to the [NVIDIA VSS documentation](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html).

**If letting the chart deploy NIM models (`nims.enabled: true`):**

| Component | GPUs |
|---|---|
| LLM (Llama 3.1 70B) | 4 × H100/A100 80GB+ |
| VSS + VLM | 2 |
| NeMo Embedding | 2 |
| NeMo Reranking | 1 |

Verify GPU availability:
```bash
oc describe node <your-node> | grep nvidia.com/gpu
```

### 3. Storage

IBM Fusion Data Foundation (FDF) is recommended. The chart creates PVCs automatically:
- General workloads: `ocs-storagecluster-ceph-rbd` (RWO)
- Shared VST storage: `ocs-storagecluster-cephfs` (RWX)

If using a different storage provider, override the storage classes in the values form at install time.

### 4. Model Endpoints (for bring-your-own path)

Have your VLM and LLM service URLs ready before deploying. For help deploying models on IBM Fusion HCI, see the [Model-as-a-Service Quickstart](https://community.ibm.com/community/user/blogs/harichandana-kotha/2026/06/29/quickstart-maas-ibm-fusion-gitops).

### 5. NIM Operator and credentials (only if `nims.enabled: true`)

If you want the chart to deploy NIM models directly:
```bash
export NGC_API_KEY=<your-ngc-api-key>
export HF_TOKEN=<your-huggingface-token>   # only if required by your model

oc create secret docker-registry ngc-docker-reg-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NGC_API_KEY

oc create secret generic ngc-api-key-secret --from-literal=NGC_API_KEY=$NGC_API_KEY
oc create secret generic hf-token-secret --from-literal=HF_TOKEN=$HF_TOKEN
```

---

## Deployment — v2: OpenShift Software Catalog *(Recommended for Fusion HCI 2.14+)*

The Software Catalog path requires no Helm CLI, no NGC credentials, and no image-pull secrets. All images are sourced from `icr.io/cp/fsh/`.

### Step 1: Create a namespace

VSS deploys into whichever namespace is selected in the OpenShift Dashboard. Create and select one first:

```bash
oc new-project vss
```

### Step 2: Find VSS in the Software Catalog

1. Open the **OpenShift Dashboard**
2. Confirm the `vss` namespace is selected in the top navigation
3. Navigate to **Ecosystem → Software Catalog**
4. Search for **Video Search and Summarization**
5. Click the chart tile → **Create**

### Step 3: Configure the values form

The form pre-populates IBM defaults for a standard Fusion HCI deployment. Supply the fields below:

**Required — External host:**
```yaml
global:
  externalHost: "<your-cluster-hostname-or-ip>"
```

**Required — VLM and LLM endpoints:**
```yaml
global:
  vlmBaseUrl: "http://<vlm-service-url>:<port>"
  vlmName: "<vlm-model-name>"
  llmBaseUrl: "http://<llm-service-url>:<port>"
  llmName: "<llm-model-name>"
```

**IBM defaults (pre-set, override only if needed):**
```yaml
nims:
  enabled: false          # NIM model deployment disabled — bring your own endpoints

vssIngress:
  enabled: true
  ingressClassName: openshift-default

global:
  storageClass: ocs-storagecluster-ceph-rbd  # general RWO PVCs

vstStorage:
  accessMode: ReadWriteMany
  createSharedPvcs: true
  streamerVideos:
    size: 20Gi
    storageClass: ocs-storagecluster-cephfs
  vstData:
    size: 10Gi
    storageClass: ocs-storagecluster-cephfs
  vstVideo:
    size: 20Gi
    storageClass: ocs-storagecluster-cephfs
```

### Step 4: Install and verify

Click **Create**. OpenShift runs `helm install` in the background. Installation takes a few minutes to an hour depending on whether images are cached on the node.

**Verify all pods are running:**
```bash
oc get pods -n vss
```

Expected pods (all `Running`, `1/1`):
```
phoenix-*
redis-0
vss-agent-*
vss-agent-ui-*
vss-vios-ingress-*
vss-vios-postgres-0
vss-vios-sensor-*
vss-vios-streamprocessing-0
```

**Verify PVCs are bound:**
```bash
oc get pvc -n vss
```

Expected:
```
data-redis-0                Bound   5Gi   RWO   ocs-storagecluster-ceph-rbd
phoenix-data                Bound   10Gi  RWO   ocs-storagecluster-ceph-rbd
vss-vios-postgres-data      Bound   10Gi  RWO   ocs-storagecluster-ceph-rbd
vss-vst-data                Bound   10Gi  RWX   ocs-storagecluster-cephfs
vss-vst-streamer-videos     Bound   20Gi  RWX   ocs-storagecluster-cephfs
vss-vst-video               Bound   20Gi  RWX   ocs-storagecluster-cephfs
```

### Step 5: Access the UI

```bash
oc get route -n vss -o jsonpath='{range .items[*]}{.spec.path}{"\t"}{.spec.host}{"\n"}{end}' | grep "^/$"
```

Open `http://<HOST>` — the route with path `/` points to `vss-agent-ui`, the main VSS interface.

---

## Deployment — v1: Helm CLI *(For Fusion HCI < 2.14 or CLI-preferred workflows)*

### Step 1: Create secrets

```bash
export NGC_API_KEY=<YOUR_NGC_API_KEY>
export HF_TOKEN=<YOUR_HUGGING_FACE_TOKEN>

oc create secret docker-registry ngc-docker-reg-secret \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password=$NGC_API_KEY

oc create secret generic ngc-api-key-secret --from-literal=NGC_API_KEY=$NGC_API_KEY
oc create secret generic hf-token-secret --from-literal=HF_TOKEN=$HF_TOKEN
oc create secret generic graph-db-creds-secret --from-literal=username=neo4j --from-literal=password=password
oc create secret generic arango-db-creds-secret --from-literal=username=root --from-literal=password=password
oc create secret generic minio-creds-secret --from-literal=access-key=minio --from-literal=secret-key=minio123
```

### Step 2: Fetch the Helm chart

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

> **Why 200Gi?** The default 50Gi PVC is insufficient for Llama 3.1 70B. 200Gi ensures adequate model storage.

### Step 4: Verify deployment

```bash
oc get pods -n default
oc get svc -n default
```

Deployment is complete when all pods show `Running` and `1/1`.

### Troubleshooting: NeMo Rerank pod fails

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

- Port 8000 → REST API
- Port 9000 → UI

Open: `http://<NODE_IP>:<NODEPORT_FOR_9000>`

---

## Air-Gapped (Disconnected) Deployment

### v2 Air-Gap Path

Mirror all VSS images from `icr.io/cp/fsh/` to your internal registry, then follow the Software Catalog steps above. Apply an `ImageTagMirrorSet` to redirect pulls transparently — no chart value changes needed.

```bash
DEST=<YOUR-INTERNAL-REGISTRY>

skopeo copy docker://icr.io/cp/fsh/nvidia/vss-core/vss-agent:3.2.1              docker://${DEST}/nvidia/vss-core/vss-agent:3.2.1
skopeo copy docker://icr.io/cp/fsh/nvidia/vss-core/vss-agent-ui:3.2.0           docker://${DEST}/nvidia/vss-core/vss-agent-ui:3.2.0
skopeo copy docker://icr.io/cp/fsh/nvidia/vss-core/vss-vios-ingress:3.2.1       docker://${DEST}/nvidia/vss-core/vss-vios-ingress:3.2.1
skopeo copy docker://icr.io/cp/fsh/nvidia/vss-core/vss-vios-sensor:3.2.1        docker://${DEST}/nvidia/vss-core/vss-vios-sensor:3.2.1
skopeo copy docker://icr.io/cp/fsh/nvidia/vss-core/vss-vios-streamprocessing:3.2.1 docker://${DEST}/nvidia/vss-core/vss-vios-streamprocessing:3.2.1
skopeo copy docker://icr.io/cp/fsh/nvidia/arize/phoenix:14.15.0                  docker://${DEST}/nvidia/arize/phoenix:14.15.0
skopeo copy docker://icr.io/cp/fsh/nvidia/redis:8.6.2-alpine                     docker://${DEST}/nvidia/redis:8.6.2-alpine
skopeo copy docker://icr.io/cp/fsh/nvidia/postgres:17.9-alpine                   docker://${DEST}/nvidia/postgres:17.9-alpine
skopeo copy docker://icr.io/cp/fsh/nvidia/busybox:1.37.0                         docker://${DEST}/nvidia/busybox:1.37.0
```

```yaml
apiVersion: config.openshift.io/v1
kind: ImageTagMirrorSet
metadata:
  name: ibm-fsh-itms-vss
spec:
  imageTagMirrors:
  - mirrors:
    - <YOUR-INTERNAL-REGISTRY>
    source: icr.io/cp/fsh
```

```bash
oc apply -f ibm-fsh-itms-vss.yaml
```

**Known air-gap issue:** Two pods download runtime dependencies from the internet at startup:
- `vss-agent` — downloads NumPy + OpenCV wheels from PyPI
- `vss-vios-streamprocessing` — downloads ~30 GStreamer `.deb` packages from Ubuntu apt repos

Use the `vss-prepare-offline.sh` and `vss-deploy-offline.sh` scripts in the `scripts/` directory to pre-stage these dependencies before deploying on a disconnected cluster.

---

## Validation & Testing

Once all pods are running and the UI is accessible, verify end-to-end by uploading and querying a video.

1. Open the VSS UI (`http://<HOST>`)
2. Upload a sample video
3. Select chunk size (recommended: 5 seconds) and configure prompts as needed

**Example prompt for a technical demo video:**
```
Summarize this demo video in a completed long paragraph. Explain what is happening step by step.
Identify any products, platforms, tools, workflows, and technical concepts shown.
Describe the full process clearly.
```

**Example caption summarization prompt:**
```
Watch this video and generate a clear technical paragraph describing the main workflow demonstrated.
Identify the platforms, services, tools, and integration steps shown. Explain how the system is
configured, how components are connected, and how the final solution is deployed.
Break the video into 30–40 second timestamp segments with brief descriptions of each.
```

4. Click **Summarize** and monitor progress:
```bash
oc logs -f <vss-vss-deployment-pod-id> -n vss
```

5. Once complete, the summary appears in the UI. You can then ask natural language questions against the indexed video and generate highlights.

---

## What We Achieved

By deploying NVIDIA VSS on IBM Fusion HCI:

- Video is ingested, captioned, and indexed in a vector store
- Content becomes searchable using natural language — no manual scrubbing
- Query response time reduces from hours to seconds
- Entire system runs on-premises with GPU acceleration through OpenShift
- v2 eliminates NGC dependency and delivers a point-and-click deployment experience via the OpenShift Software Catalog

---

## Extending VSS — Audio Transcription (Riva ASR)

Optional capability that adds speech-to-text transcription and merges spoken content with visual captions. Ideal for briefings, announcements, and training videos.

**Requirements:**
- 1 additional GPU (can share on 80GB+ GPUs)
- Model: `parakeet-0-6b-ctc-riva-en-us`

Refer to NVIDIA's audio deployment guide for configuration details.

---

## Explore Further

- [IBM Fusion documentation](https://www.ibm.com/docs/en/fusion-hci-systems)
- [NVIDIA VSS Helm deployment guide](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html)
- [NVIDIA NIM documentation](https://docs.nvidia.com/nim/large-language-models/latest/supported-models.html)
- [NVIDIA VSS FAQ and Known Issues](https://docs.nvidia.com/vss/latest/content/faq.html)
- [IBM Tech Exchange Blog — VSS v1](https://community.ibm.com/community/user/blogs/namita-singroha/2025/04/01/unlocking-ai-powered-video-analytics-on-ibm-fusion)
- [IBM Tech Exchange Blog — VSS v2](https://community.ibm.com/community/user/blogs/namita-singroha/2026/08/26/unlocking-ai-powered-video-analytics-on-ibm-fusion)
- To uninstall: go to **Ecosystem → Helm** in the OpenShift Dashboard, find the VSS release, and select **Delete**
