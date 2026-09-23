# Deploying NVIDIA RAG on IBM Fusion HCI

Retrieval-Augmented Generation (RAG) is rapidly becoming a core enterprise capability — grounding LLM responses in verified enterprise documents to eliminate hallucinations and ensure every answer is traceable to a source. Moving RAG to production demands GPU-optimized inference, scalable semantic search, efficient document ingestion, and enterprise infrastructure to hold it all together.

This guide covers deploying the NVIDIA RAG Blueprint on **IBM Fusion HCI** with **Red Hat OpenShift**. Two deployment paths are documented:

- **v2 (Recommended) — OpenShift Software Catalog:** IBM Fusion HCI packages RAG v2.6.0 as a Helm chart with images pre-mirrored to IBM Cloud Container Registry (`icr.io/cp/fsh/`). The chart appears automatically in the OpenShift Software Catalog — no Helm CLI, no NGC credentials required. Uses Elasticsearch (ECK Operator) as the vector store and SeaweedFS for document storage.
- **v1 — Helm CLI:** The original deployment path using RAG v2.3.0 pulled from NVIDIA NGC. Uses Milvus as the vector store and MinIO for object storage. Still valid for environments that prefer direct Helm control.

---

## What Is NVIDIA RAG?

NVIDIA's Enterprise RAG Blueprint provides a consistent, production-oriented pipeline connecting LLMs to multi-modal enterprise content:

- **Multi-modal document intelligence** — OCR, PDF layout parsing, table and chart extraction
- **Grounded generation** — provides context and citations to LLMs for traceable, accurate responses
- **Semantic search** — vector embeddings + re-ranking ensure the most relevant content surfaces every time
- **Enterprise operations** — built-in telemetry, evaluation tooling, and Kubernetes-native deployment

### RAG Pipeline Architecture

**Query Flow:**
User question → RAG server → vector embedding → Elasticsearch (v2) / Milvus (v1) semantic search → re-ranker → augmented prompt → LLM → grounded answer with citations

**Document Ingestion Flow:**
Upload → ingestor-server → OCR / table parsing / chart extraction → SeaweedFS (v2) / MinIO (v1) → embedding model → vector store index

---

## Why IBM Fusion HCI?

Enterprise RAG simultaneously demands high GPU utilization, consistent storage performance, and streamlined operations. IBM Fusion HCI provides converged infrastructure where compute, storage, and Red Hat OpenShift are integrated and managed as a unified system:

- **Direct GPU pass-through** — no virtualization overhead for NIM containers
- **NVMe-backed storage** — high-performance persistent volumes for vector database operations
- **Unified management plane** — single control plane for infrastructure and AI workloads
- **Air-gap readiness** — in v2, all images are pre-mirrored to IBM ICR; no NGC access needed at deploy time
- **Deployed directly from OpenShift Software Catalog** — reduces deployment to a values form, not a sequence of CLI commands

---

## What Changed from v1 to v2

| | v1 (RAG v2.3.0) | v2 (RAG v2.6.0) |
|---|---|---|
| **Deployment** | Helm CLI from NGC | OpenShift Software Catalog |
| **Image source** | NVIDIA NGC (`nvcr.io`) | IBM Cloud Registry (`icr.io/cp/fsh/`) |
| **NGC credentials** | Required | Not required |
| **Vector store** | Milvus | Elasticsearch (via ECK Operator) |
| **Object store** | MinIO | SeaweedFS |
| **OpenShift support** | Manual SCC + KubeletConfig | `openshift.enabled: true` flag |
| **Air-gap** | Manual image mirror + NGC secrets | ITMS redirect only |

---

## Prerequisites

### 1. Hardware

- IBM Fusion HCI cluster installed and running
- Minimum: 8 GPUs with 24 GB VRAM each (40 GB+ recommended)
- Supported GPU types: NVIDIA L40S, A100, H100, RTX PRO 6000, B200
- Note: v1 testing was conducted on NVIDIA L40S GPUs with 46 GB VRAM

Check available GPU resources:
```bash
oc describe nodes | grep -A 5 "Allocated resources"
oc get nodes -o json | jq -r '.items[] | select(.metadata.labels."nvidia.com/gpu.present" == "true") | {node: .metadata.name, gpu_product: .metadata.labels."nvidia.com/gpu.product", gpu_count: .metadata.labels."nvidia.com/gpu.count"}'
```

### 2. Storage

A default StorageClass is required for persistent volumes (vector database, object store, ingestor data).
```bash
oc get sc
```

**Recommended:** IBM Fusion Data Foundation — use `ocs-storagecluster-ceph-rbd` for block storage.

**Alternative: local path provisioner**
```bash
oc apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
oc patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 3. NVIDIA GPU Operator

Verify the GPU Operator is installed and running:
```bash
oc get pods -n nvidia-gpu-operator
oc get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu" != null)'
```

### 4. ECK Operator *(v2 only)*

v2 uses Elasticsearch via the ECK Operator as its vector store. The ECK Operator must be installed **before** the RAG chart — it registers the Elasticsearch CRD that the RAG chart depends on. Without it, the install fails immediately.

Install via the OpenShift Software Catalog (search for **ECK Operator**) before proceeding to RAG deployment.

### 5. NGC API Key *(v1 only)*

```bash
export NGC_API_KEY=<your-ngc-api-key>
```

### 6. Helm and CLI *(v1 only)*

Helm v3.19.4 is the validated version for the v1 RAG Blueprint:
```bash
helm version   # must show v3.19.4
oc version
oc whoami
```

---

## Deployment — v2: OpenShift Software Catalog *(Recommended)*

### Step 1: Install the ECK Operator

1. Open the **OpenShift Dashboard**
2. Navigate to **Ecosystem → Software Catalog**
3. Search for **ECK Operator** and install it
4. Verify the operator is ready before proceeding:
```bash
oc get pods -n elastic-system
```

### Step 2: Create the RAG namespace

```bash
oc new-project rag
```

Confirm the `rag` namespace is selected in the OpenShift Dashboard top navigation.

### Step 3: Find the RAG Blueprint in the Software Catalog

1. Open the **OpenShift Dashboard**
2. Confirm the `rag` namespace is selected
3. Navigate to **Ecosystem → Software Catalog**
4. Search for **NVIDIA RAG Blueprint**
5. Click the chart tile → **Create**

### Step 4: Configure the values form

**Required — OpenShift support** (handles Routes and SCC permissions automatically):
```yaml
openshift:
  enabled: true
```

**Required — Your model endpoints:**
```yaml
envVars:
  # LLM
  APP_LLM_MODELNAME: "<your-llm-model-name>"
  APP_LLM_SERVERURL: "<your-llm-service>:8000"
  APP_QUERYREWRITER_MODELNAME: "<your-llm-model-name>"
  APP_QUERYREWRITER_SERVERURL: "<your-llm-service>:8000"
  REFLECTION_LLM: "<your-llm-model-name>"
  REFLECTION_LLM_SERVERURL: "<your-llm-service>:8000"

  # Embedding
  APP_EMBEDDINGS_MODELNAME: "<your-embedding-model-name>"
  APP_EMBEDDINGS_SERVERURL: "<your-embedding-service>:8000/v1"
  APP_EMBEDDINGS_DIMENSIONS: "2048"

  # Reranking
  APP_RANKING_MODELNAME: "<your-reranking-model-name>"
  APP_RANKING_SERVERURL: "<your-reranking-service>:8000"

ingestor-server:
  envVars:
    SUMMARY_LLM: "<your-llm-model-name>"
    SUMMARY_LLM_SERVERURL: "<your-llm-service>:8000"
    APP_EMBEDDINGS_MODELNAME: "<your-embedding-model-name>"
    APP_EMBEDDINGS_SERVERURL: "<your-embedding-service>:8000/v1"

nv-ingest:
  envVars:
    EMBEDDING_NIM_MODEL_NAME: "<your-embedding-model-name>"
    EMBEDDING_NIM_ENDPOINT: "http://<your-embedding-service>:8000/v1"
```

**Conditional — StorageClass** (only if `ocs-storagecluster-ceph-rbd` is not your cluster default):
```yaml
seaweedfs:
  allInOne:
    data:
      storageClass: "ocs-storagecluster-ceph-rbd"

ingestor-server:
  persistence:
    storageClass: "ocs-storagecluster-ceph-rbd"

eck-elasticsearch:
  nodeSets:
  - name: default
    count: 1
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        storageClassName: "ocs-storagecluster-ceph-rbd"
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 50Gi
```

**IBM defaults (pre-set, no changes needed):** All container images are pre-configured to pull from `icr.io/cp/fsh/nvidia/`. No NGC image-pull secret required.

### Step 5: Install and monitor

Click **Create**. OpenShift runs `helm install` in the background. Installation takes approximately 15–25 minutes, primarily waiting for Elasticsearch to initialize.

```bash
oc get pods -n rag -w
```

### Step 6: Verify deployment

**All pods should show `Running` and `1/1`:**
```bash
oc get pods -n rag
```

Expected pods:
```
ingestor-server-<hash>                  1/1   Running
rag-eck-elasticsearch-es-default-0      1/1   Running
rag-frontend-<hash>                     1/1   Running
rag-nv-ingest-<hash>                    1/1   Running
rag-redis-master-0                      1/1   Running
rag-redis-replicas-0                    1/1   Running
rag-seaweedfs-all-in-one-<hash>         1/1   Running
rag-server-<hash>                       1/1   Running
```

**Verify PVCs are bound:**
```bash
oc get pvc -n rag
```

Expected:
```
elasticsearch-data-rag-eck-elasticsearch-...   Bound   50Gi
ingestor-server-data                           Bound   50Gi
rag-seaweedfs-all-in-one-data                  Bound   50Gi
```

### Step 7: Access the UI

```bash
oc port-forward -n rag service/rag-frontend 3000:3000 --address 0.0.0.0
```

Open `http://localhost:3000`.

---

## Deployment — v1: Helm CLI *(RAG v2.3.0, Milvus-based)*

### Step 1: Download and extract the Helm chart

```bash
wget https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz
tar xvzf nvidia-blueprint-rag-v2.3.0.tgz
cd nvidia-blueprint-rag
```

### Step 2: Configure pod PID limits

Red Hat OpenShift requires increased PID limits for the RAG workload:
```bash
cat <<EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: custom-config
spec:
  kubeletConfig:
    podPidsLimit: 12228
  machineConfigPoolSelector:
    matchExpressions:
      - key: machineconfiguration.openshift.io/mco-built-in
        operator: Exists
EOF
```

Monitor the rollout — worker nodes undergo a rolling update:
```bash
oc get mcp -w
```

Wait until all machine config pools show `UPDATED=True` before proceeding.

### Step 3: Modify RAG server deployment

From the Helm chart root, edit `templates/deployment.yaml`:

In the `volumeMounts:` section, add:
```yaml
volumeMounts:
  - name: prompt-volume
    mountPath: /prompt.yaml
    subPath: prompt.yaml
  - name: tmp-data
    mountPath: /workspace/tmp-data
  - name: prom-data
    mountPath: /tmp-data/prom_data
```

In the `volumes:` section, add:
```yaml
volumes:
  - name: prompt-volume
    configMap:
      name: {{ include "nvidia-blueprint-rag.fullname" . }}-prompt
      defaultMode: 0555
  - name: tmp-data
    emptyDir: {}
  - name: prom-data
    emptyDir: {}
```

### Step 4: Adjust model configuration for L40S GPUs *(Optional)*

Only required if using L40S GPUs. Switch to the lighter Nemotron Nano model:
```bash
sed -i '' 's/llama-3.3-nemotron-super-49b-v1.5/llama-3.1-nemotron-nano-8b-v1/g' values.yaml
sed -i '' 's/tag: "1.13.1"/tag: "1.8.4"/g' values.yaml
```

### Step 5: Configure security permissions

```bash
oc create namespace rag

oc adm policy add-scc-to-user anyuid -z default -n rag
oc adm policy add-scc-to-user anyuid -z rag-nv-ingest -n rag
oc adm policy add-scc-to-user anyuid -z rag-server -n rag
```

### Step 6: Deploy

```bash
helm upgrade --install rag ./ \
  --username '$oauthtoken' \
  --password "${NGC_API_KEY}" \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set nv-ingest.redis.image.repository=bitnamilegacy/redis \
  --set nv-ingest.redis.image.tag=8.2.1-debian-12-r0
```

Installation takes approximately 15–25 minutes.

### Step 7: Verify deployment

```bash
oc get pods -n rag
oc get svc -n rag
```

### Step 8: Port-forward to access the UI

```bash
oc port-forward -n rag service/rag-frontend 3000:3000 --address 0.0.0.0
```

Open `http://localhost:3000`.

---

## Air-Gapped (Disconnected) Deployment

### v2 Air-Gap Path

Mirror all RAG images from `icr.io/cp/fsh/` to your internal registry, then follow the Software Catalog steps above. Apply an `ImageTagMirrorSet` — no chart value changes needed.

```bash
DEST=<YOUR-INTERNAL-REGISTRY>

skopeo copy docker://icr.io/cp/fsh/nvidia/blueprint/rag-server:2.6.0           docker://${DEST}/nvidia/blueprint/rag-server:2.6.0
skopeo copy docker://icr.io/cp/fsh/nvidia/blueprint/ingestor-server:2.6.0      docker://${DEST}/nvidia/blueprint/ingestor-server:2.6.0
skopeo copy docker://icr.io/cp/fsh/nvidia/blueprint/rag-frontend:2.6.0         docker://${DEST}/nvidia/blueprint/rag-frontend:2.6.0
skopeo copy docker://icr.io/cp/fsh/nvidia/nemo-microservices/nv-ingest:26.3.0  docker://${DEST}/nvidia/nemo-microservices/nv-ingest:26.3.0
skopeo copy docker://icr.io/cp/fsh/nvidia/redis:8.2.1                           docker://${DEST}/nvidia/redis:8.2.1
skopeo copy docker://icr.io/cp/fsh/nvidia/seaweedfs:3.73                        docker://${DEST}/nvidia/seaweedfs:3.73
skopeo copy docker://icr.io/cp/fsh/nvidia/elastic/elasticsearch:9.3.0           docker://${DEST}/nvidia/elastic/elasticsearch:9.3.0
skopeo copy docker://icr.io/cp/fsh/nvidia/elastic/eck-operator:3.4.1            docker://${DEST}/nvidia/elastic/eck-operator:3.4.1
```

```yaml
apiVersion: config.openshift.io/v1
kind: ImageTagMirrorSet
metadata:
  name: ibm-fsh-itms-rag
spec:
  imageTagMirrors:
  - mirrors:
    - <YOUR-INTERNAL-REGISTRY>
    source: icr.io/cp/fsh
```

```bash
oc apply -f ibm-fsh-itms-rag.yaml
```

---

## Validation & Testing

After deployment, verify the RAG system is operational via the UI.

1. Open a browser and navigate to the RAG frontend URL
2. Click **Create New Collection** at the bottom left — provide a name and upload your documents (IBM Fusion HCI PDFs, manuals, etc.)
3. Click **Create Collection** and wait for ingestion to complete. Monitor progress via the notifications icon (top right) or pod logs:
```bash
oc logs -f deployment/ingestor-server -n rag
```
4. Once ingestion finishes, click the uploaded collection in the left panel
5. Ask questions related to your documents — responses will be grounded with citations from your source documents
6. Monitor LLM response logs:
```bash
oc logs -f rag-nim-llm-0 -n rag
```

---

## Troubleshooting

### Helm deployment fails with duplicate environment variable errors *(v1)*

**Issue:**
```
Error: failed to create typed patch object: .spec.template.spec.containers[name="nv-ingest"].env: duplicate entries for key [name="INGEST_LOG_LEVEL"]
```
**Resolution:** Use exactly Helm v3.19.4. Other versions have compatibility issues with this chart.

### Pods stuck in ImagePullBackOff *(v1)*

**Resolution:** Verify container image names match the NVIDIA NIM documentation and ensure the NGC secret is configured correctly.

### Pods in CrashLoopBackOff *(v1)*

**Resolution:** Verify SCC permissions are applied to the correct service accounts:
```bash
oc get scc
oc describe pod <pod-name> -n rag
```

---

## What We Achieved

- Deployed a production RAG system where users query enterprise documents and receive AI-generated answers grounded in their own data
- Successfully ran all RAG components (LLM inference, vector database, embeddings, document ingestion) on IBM Fusion HCI with stable performance
- v2 eliminates all NGC dependencies, simplifies OpenShift-specific configuration to a single flag (`openshift.enabled: true`), and replaces Milvus + MinIO with Elasticsearch + SeaweedFS for a reduced operational footprint
- Architecture runs entirely on-premises on OpenShift — fully air-gap ready from day one

---

## Further Reading

- [IBM Fusion documentation](https://www.ibm.com/docs/en/fusion-hci-systems)
- [NVIDIA RAG Blueprint deployment guide](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/docs/deploy-helm.md)
- [NVIDIA NIM documentation](https://docs.nvidia.com/nim/large-language-models/latest/_include/models.html)
- [NVIDIA troubleshooting guide](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/docs/troubleshooting.md)
- [IBM Tech Exchange Blog — RAG v1](https://community.ibm.com/community/user/blogs/hasrat-ali-arzoo/2026/01/21/deploying-nvidia-rag-on-ibm-fusion-hci)
- [IBM Tech Exchange Blog — RAG v2](https://community.ibm.com/community/user/blogs/hasrat-ali-arzoo/2026/08/30/deploying-nvidia-rag-on-fusion-hci-v2)
- To uninstall: follow the guidance [here](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/docs/deploy-helm.md#uninstall-a-deployment)

**Acknowledgments:** Thanks to Sandeep Zende for his collaboration in validating this blueprint on IBM Fusion HCI.
