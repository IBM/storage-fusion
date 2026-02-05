# Deploying NVIDIA RAG on IBM Fusion HCI

Retrieval-Augmented Generation is rapidly becoming a core enterprise capability. However, moving RAG from development to production requires more than just connecting an LLM to a vector database — it demands GPU-optimized inference, scalable semantic search, efficient embedding generation, and enterprise infrastructure to support these components reliably.

This article walks through a validated production deployment of NVIDIA's RAG Blueprint on IBM Fusion HCI with Red Hat OpenShift. The deployment uses:

- NVIDIA RAG Blueprint v2.3.0 (Helm-based deployment)
- NVIDIA NIM with Nemotron Nano 8B for optimized LLM inference
- Milvus for distributed vector search
- NeMo Retriever for embedding generation
- IBM Fusion Data Foundation for enterprise-grade persistent storage
- Red Hat OpenShift on IBM Fusion HCI

## Table of Contents

- Why IBM Fusion HCI for RAG deployments
- Prerequisites
- Configuration steps for OpenShift deployment
- Validation & Testing
- What we accomplished
- Key observations
- Troubleshooting common issues
- Further Reading

## Why IBM Fusion HCI:

Enterprise RAG platforms simultaneously demand high GPU utilization, consistent storage performance, and streamlined operations. IBM Fusion HCI provides converged infrastructure where compute, storage, and OpenShift are integrated and managed as a unified system.

This deployment demonstrated:

- Direct GPU pass-through for NIM containers (no virtualization overhead)
- High-performance NVMe storage for Milvus vector operations
- Native OpenShift integration simplifying platform operations
- Single management plane for infrastructure and AI workloads
- Performance and reliability requirements met for production RAG

## Prerequisites

Before deploying the NVIDIA RAG Blueprint, ensure the following requirements are met on your Fusion HCI system:

### 1. Hardware requirements

Verify that your cluster meets the minimum hardware specifications for the RAG Blueprint deployment:

— IBM Fusion HCI cluster installed and running.

— GPU requirements:

- Minimum: 8 GPUs
- GPU memory: 24GB+ VRAM per GPU (40GB+ recommended for larger models).
- GPU types: NVIDIA L40S, A100, H100, RTX PRO 6000, B200 or equivalent.
- Note: This deployment was tested on NVIDIA L40S GPUs with 46GB VRAM

Check available cluster resources:
```bash
oc describe nodes | grep -A 5 "Allocated resources"
```

Identify the type of GPUs:
```bash
oc get nodes -o json | jq -r '.items[] | select(.metadata.labels."nvidia.com/gpu.present" == "true") | {node: .metadata.name, gpu_product: .metadata.labels."nvidia.com/gpu.product", gpu_count: .metadata.labels."nvidia.com/gpu.count", gpu_memory: .metadata.labels."nvidia.com/gpu.memory"}'
```

### 2. Storage configuration

Verify that you have a default storage class available:
```bash
oc get sc
```

Look for a storage class marked as (default). If a default storage class exists, you're ready to proceed.

If no default storage class is set, configure one using IBM Fusion Data Foundation or another storage provider:

**Option 1: IBM Fusion Data Foundation**

Install IBM Fusion Data Foundation following the guide here.

Once installed & configured, verify the storage class:
```bash
oc get storageclass | grep ocs
# Use: ocs-storagecluster-ceph-rbd
```

**Option 2: Local path provisioner**
```bash
oc apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
oc patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

Note: This deployment was tested with Fusion Data Foundation v4.18.

### 3. NVIDIA GPU Operator

- Verify that you have installed the NVIDIA GPU Operator using the instructions here.
- Check GPU operator status:
```bash
oc get pods -n nvidia-gpu-operator
```

- Confirm GPU resources are detected:
```bash
oc get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu" != null)'
```

### 4. NGC API key

- Obtain your NGC API key from: https://ngc.nvidia.com/setup/api-key
- Export as environment variable:
```bash
export NGC_API_KEY=<your-ngc-api-key>
```

### 5. Optional: GPU time-slicing

- You can enable time slicing for sharing GPUs between pods
- For details, refer to this detailed guide on time-slicing.

### 6. Install Helm and OpenShift CLI

Ensure Helm v3.19.4 is installed, as this version was validated with the NVIDIA RAG Blueprint.
```bash
helm version
<-- output --> 
version.BuildInfo{Version:"v3.19.4", ...}
```

Verify OpenShift CLI is installed and connected to the cluster:
```bash
oc version
oc whoami
```

## Configuration steps:

Before deploying the NVIDIA RAG Blueprint, a few modifications are required. Follow these steps sequentially-

### Step 1: Download and extract the Helm chart

Download the NVIDIA RAG Blueprint package locally for customization:
```bash
wget https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz
tar xvzf nvidia-blueprint-rag-v2.3.0.tgz
cd nvidia-blueprint-rag
```

### Step 2: Configure pod PID limits

OpenShift requires increased PID limits for the RAG workload. Create and apply the kubelet configuration:
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

Monitor the machine-config rollout. Worker nodes will undergo a rolling update:
```bash
oc get mcp -w
```

Wait until all machine config pools show UPDATED=True before proceeding.

### Step 3: Modify RAG server deployment

From the Helm chart root (nvidia-blueprint-rag/), edit templates/deployment.yaml as shown below:

Become a member

Locate the volumeMounts: section (around line 58) and add two new mounts:
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

Locate the volumes: section (around line 65) and add two new volumes:
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

The diff below shows the exact additions made to the RAG server deployment yaml.

Press enter or click to view image in full size

### Step 4: Adjust model configuration (Optional)

This step is only required if using L40S GPUs. For other GPU types, skip to Step 5.

The default configuration uses a large model requiring significant GPU memory. For L40S GPUs, switch to the lighter Nemotron Nano model:
```bash
sed -i '' 's/llama-3.3-nemotron-super-49b-v1.5/llama-3.1-nemotron-nano-8b-v1/g' values.yaml
sed -i '' 's/tag: "1.13.1"/tag: "1.8.4"/g' values.yaml
```

### Step 5: Configure security permissions

Allow RAG pods to run as any user by granting them the anyuid SCC. Run below commands-
```bash
# Create the namespace
oc create namespace rag

# Grant the `anyuid` SCC to the required service accounts
oc adm policy add-scc-to-user anyuid -z default -n rag
oc adm policy add-scc-to-user anyuid -z rag-nv-ingest -n rag
oc adm policy add-scc-to-user anyuid -z rag-server -n rag
```

### Step 6: Deploy the RAG Blueprint

Install the Helm chart with customized configurations:
```bash
helm upgrade --install rag ./ \
--username '$oauthtoken' \
--password "${NGC_API_KEY}" \
--set imagePullSecret.password=$NGC_API_KEY \
--set ngcApiSecret.password=$NGC_API_KEY \
--set nv-ingest.redis.image.repository=bitnamilegacy/redis \
--set nv-ingest.redis.image.tag=8.2.1-debian-12-r0
```

The installation process takes approximately 15–25 minutes.

Verify the output as below:
```bash
helm upgrade --install rag ./ \                                                          
--username '$oauthtoken' \
--password "${NGC_API_KEY}" \
--set imagePullSecret.password=$NGC_API_KEY \
--set ngcApiSecret.password=$NGC_API_KEY \
--set nv-ingest.redis.image.repository=bitnamilegacy/redis \
--set nv-ingest.redis.image.tag=8.2.1-debian-12-r0
Release "rag" does not exist. Installing it now.
coalesce.go:237: warning: skipped value for etcd.extraVolumeMounts: Not a table.
coalesce.go:237: warning: skipped value for etcd.extraVolumes: Not a table.
I0106 23:00:32.999018   14427 warnings.go:110] "Warning: spec.template.spec.containers[0].env[18]: hides previous definition of \"INGEST_LOG_LEVEL\", which may be dropped when using apply"
I0106 23:00:32.999091   14427 warnings.go:110] "Warning: spec.template.spec.containers[0].env[47]: hides previous definition of \"VLM_CAPTION_ENDPOINT\", which may be dropped when using apply"
I0106 23:00:32.999101   14427 warnings.go:110] "Warning: spec.template.spec.containers[0].env[65]: hides previous definition of \"OTEL_EXPORTER_OTLP_ENDPOINT\", which may be dropped when using apply"
NAME: rag
LAST DEPLOYED: Tue Jan  6 22:59:26 2026
NAMESPACE: rag
STATUS: deployed
REVISION: 1
```

### Step 7: Verify deployment

Check that all pods are running successfully:
```bash
oc get pods -n rag
```
```
NAME                                                         READY   STATUS    RESTARTS      AGE
ingestor-server-65b858cf4d-c2bch                             1/1     Running   0             35h
milvus-standalone-7588f6787f-tz4fs                           1/1     Running   3 (43h ago)   43h
nv-ingest-ocr-75bc9c7bdd-g4l9l                               1/1     Running   0             43h
rag-etcd-0                                                   1/1     Running   0             43h
rag-frontend-75dbf7f8d9-6kvkq                                1/1     Running   0             43h
rag-minio-5bb67c8d9f-pj2kh                                   1/1     Running   0             43h
rag-nemoretriever-graphic-elements-v1-68bf49c49d-8nhxg       1/1     Running   0             34h
rag-nemoretriever-page-elements-v2-86655669f4-wdh5z          1/1     Running   0             34h
rag-nemoretriever-table-structure-v1-6c96bb8b66-mxrsj        1/1     Running   0             43h
rag-nim-llm-0                                                1/1     Running   0             35h
rag-nv-ingest-7c6c84cb5c-ctgwl                               1/1     Running   0             43h
rag-nvidia-nim-llama-32-nv-embedqa-1b-v2-569467f68b-44mjn    1/1     Running   0             34h
rag-nvidia-nim-llama-32-nv-rerankqa-1b-v2-7f8b6b6f9c-5pght   1/1     Running   0             34h
rag-opentelemetry-collector-65d96849fc-t6m8d                 1/1     Running   0             35h
rag-redis-master-0                                           1/1     Running   0             43h
rag-redis-replicas-0                                         1/1     Running   0             43h
rag-server-69ddffbfbb-dnsrk                                  1/1     Running   0             35h
```

Verify key services are available:
```bash
oc get svc -n rag
```
```
NAME                                TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                                                   AGE
ingestor-server                     ClusterIP   172.X.X.X    <none>        8082/TCP                                                  43h
milvus                              ClusterIP   172.X.X.X   <none>        19530/TCP,9091/TCP                                        43h
nemoretriever-embedding-ms          ClusterIP   172.X.X.X    <none>        8000/TCP                                                  43h
nemoretriever-graphic-elements-v1   ClusterIP   172.X.X.X   <none>        8000/TCP,8001/TCP                                         43h
nemoretriever-page-elements-v2      ClusterIP   172.X.X.X    <none>        8000/TCP,8001/TCP                                         43h
nemoretriever-ranking-ms            ClusterIP   172.X.X.X   <none>        8000/TCP                                                  43h
nemoretriever-table-structure-v1    ClusterIP   172.X.X.X    <none>        8000/TCP,8001/TCP                                         43h
nim-llm                             ClusterIP   172.X.X.X    <none>        8000/TCP                                                  35h
nim-llm-sts                         ClusterIP   None             <none>        8000/TCP                                                  35h
nv-ingest-ocr                       ClusterIP   172.X.X.X    <none>        8000/TCP,8001/TCP                                         43h
rag-etcd                            ClusterIP   172.X.X.X   <none>        2379/TCP,2380/TCP                                         43h
rag-etcd-headless                   ClusterIP   None             <none>        2379/TCP,2380/TCP                                         43h
rag-frontend                        NodePort    172.X.X.X    <none>        3000:31273/TCP                                            43h
rag-minio                           ClusterIP   172.X.X.X    <none>        9000/TCP                                                  43h
rag-nv-ingest                       ClusterIP   172.X.X.X    <none>        7670/TCP                                                  43h
rag-opentelemetry-collector         ClusterIP   172.X.X.X    <none>        6831/UDP,14250/TCP,14268/TCP,4317/TCP,4318/TCP,9411/TCP   35h
rag-redis-headless                  ClusterIP   None             <none>        6379/TCP                                                  43h
rag-redis-master                    ClusterIP   172.X.X.X   <none>        6379/TCP                                                  43h
rag-redis-replicas                  ClusterIP   172.X.X.X     <none>        6379/TCP                                                  43h
rag-server                          ClusterIP   172.X.X.X    <none>        8081/TCP                                                  43h
rag-zipkin                          ClusterIP   172.X.X.X   <none>        9411/TCP                                                  35h
```

The deployment is complete when all pods show Running status and 1/1 or appropriate replica counts in the READY column.

### Step 8: Port-Forwarding to Access Web User Interface:

Run the following cmd to port-forward the RAG UI service to your local machine. Then access the RAG UI at http://localhost:3000.
```bash
oc port-forward -n rag service/rag-frontend 3000:3000 --address 0.0.0.0
```

## Validation & Testing:

After deployment, you can verify the RAG system is operational via the UI:

1. Open a web browser and navigate to the RAG frontend.


<img width="1664" alt="Screenshot 2026-01-21 at 10 58 15 PM" src="https://github.ibm.com/user-attachments/assets/d6d2a3d3-bc81-4103-a8cd-503c16de8aa8" />


2. Create a new collection by clicking "Create New Collection" at the bottom left. Provide a name and upload your documents (for example, IBM Fusion HCI and SDS PDFs).


3. Click Create Collection and wait for ingestion to complete. Depending on document size, this may take a few minutes.



<img width="1648" alt="Screenshot 2026-01-21 at 10 59 06 PM" src="https://github.ibm.com/user-attachments/assets/18f44d39-ea7e-4264-9a17-bd8df83042ed" />



4. In the home tab, click on notifications icon in top right.



<img width="1301" alt="Screenshot 2026-01-21 at 10 59 38 PM" src="https://github.ibm.com/user-attachments/assets/55bba55c-6025-43ee-9626-902fe80d5131" />



5. Monitor the logs of the <ingestor-server-xxxxx> pod in the rag namespace to check for any errors.




6. Wait for the process to complete; ingestion may take several minutes depending on the size and number of documents uploaded.




<img width="1314" alt="Screenshot 2026-01-21 at 11 00 01 PM" src="https://github.ibm.com/user-attachments/assets/0b068aab-6bb0-4909-86ae-a19fdcac140e" />




7. Once ingestion finishes, click on the uploaded document in the left panel. The collection will appear in the bottom right panel, ready for querying.



<img width="1723" alt="Screenshot 2026-01-21 at 11 00 24 PM" src="https://github.ibm.com/user-attachments/assets/0a281141-d396-42a3-9570-e214d21d3f71" />




8. Now you can ask questions related to your document.



<img width="681" alt="Screenshot 2026-01-21 at 11 00 43 PM" src="https://github.ibm.com/user-attachments/assets/74acefdf-31e8-4d6c-93f6-a11315886c61" />




9. Monitor the logs of the <rag-nim-llm-0> pod in the rag namespace to observe AI responses.

## What we accomplished:

- Deployed a production RAG system that allows users to query enterprise documents and get AI-generated answers grounded in their own data.
- Successfully ran all RAG components (LLM inference, vector database, embeddings) on IBM Fusion HCI with stable performance.
- Validated that the NVIDIA RAG Blueprint works on OpenShift, making it accessible to organizations using enterprise Kubernetes.

## Key Observations:

- Model selection directly impacts GPU requirements — Nemotron Nano 8B suits L40S GPUs while larger models need more VRAM; evaluate model capabilities against available resources before deployment
- Use Helm version 3.19.4 or less — other versions may have compatibility issues with the NVIDIA RAG Blueprint chart.

## Troubleshooting common issues:

### 1. Helm deployment fails with duplicate environment variable errors

**Issue:** Deployment fails during Helm install with error:
```
Release "rag" does not exist. Installing it now.
Error: failed to create typed patch object (rag/rag-nv-ingest; apps/v1, Kind=Deployment): errors:
  .spec.template.spec.containers[name="nv-ingest"].env: duplicate entries for key [name="INGEST_LOG_LEVEL"]
  .spec.template.spec.containers[name="nv-ingest"].env: duplicate entries for key [name="VLM_CAPTION_ENDPOINT"]
```

**Resolution:** Verify Helm version is exactly 3.19.4 using helm version

### 2. Pods stuck in ImagePullBackOff

**Issue:** Pods show ImagePullBackOff status

**Resolution:** Verify container image names match the model list in NVIDIA NIM documentation and check NGC secret is configured

### 3. Pods in CrashLoopBackOff

**Issue:** Pods repeatedly crash with security errors

**Resolution:** Verify SCC permissions are applied to the correct service account using oc get scc and oc describe pod

## Further reading

- To learn more about IBM Fusion HCI, explore the [IBM Fusion documentation](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.0?topic=installing)
- For detailed Helm deployment steps, refer to the [NVIDIA RAG Blueprint deployment guide](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/docs/deploy-helm.md)
- Model specifications and options are available in the [NVIDIA NIM documentation](https://docs.nvidia.com/nim/large-language-models/latest/_include/models.html)
- Common deployment issues and solutions can be found in the [NVIDIA troubleshooting guide](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/docs/troubleshooting.md)
- To uninstall the deployment, follow the guidance [here](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/docs/deploy-helm.md#uninstall-a-deployment)


**Acknowledgments:** Thanks to Sandeep Zende for his collaboration in validating this blueprint on IBM Fusion HCI.
