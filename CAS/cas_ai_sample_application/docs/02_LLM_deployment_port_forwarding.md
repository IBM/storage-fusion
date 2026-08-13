# LLM Deployment & Local Access
# Authors: Vitaliy Kornev & Priyas Ojha
**Purpose:** Get an LLM accessible locally so the application can query it. There are two supported paths — choose whichever fits your setup:

| Option | When to use |
|---|---|
| [**A — NVIDIA NIM (cluster)**](#option-a--nvidia-nim-on-cluster) | LLM runs on an OpenShift cluster; you port-forward it to your machine. |
| [**B — Ollama (local)**](#option-b--ollama-local) | You want a fully local setup without cluster access. |

Once the LLM is reachable, complete [Step 3 — Configure the `.env`](#step-3--configure-the-env) to point the application at it.

---

## Option A — NVIDIA NIM (on cluster)

### A1 — Log Into the Cluster

```
oc login <cluster-url>
```

---

### A2 — Check for an Existing LLM Deployment

An LLM may already be running in the cluster — it can live in any namespace. Look for something matching your model name (e.g. `meta-llama-3-2-1b-instruct`):

```
oc get NIMCache
oc get NIMService
oc get Deployments
```

If a matching NIMCache / NIMService / Deployment already exists, skip ahead to [**A6 — Port Forward the Service**].

---

### A3 — Create the NIMCache

```yaml
apiVersion: apps.nvidia.com/v1alpha1
kind: NIMCache
metadata:
  name: meta-llama-3-2-1b-instruct
  namespace: <your-namespace>
spec:
  source:
    ngc:
      modelPuller: nvcr.io/nim/meta/llama-3.2-1b-instruct:1.12.0
      pullSecret: <ngc-pull-secret>
      authSecret: <ngc-api-secret>
      model:
        engine: tensorrt_llm
        tensorParallelism: "1"
  storage:
    pvc:
      create: true
      storageClass: "<your-storage-class>"
      size: "<size>"
      volumeAccessMode: ReadWriteOnce
```

```
oc create -f llm-nimcache.yaml
```

Wait for the cache to be created — check under **Workloads → Deployments** for the pod matching your model name in your namespace, or run:

```
oc get nimcache meta-llama-3-2-1b-instruct -o yaml
```

Wait until status shows `Ready` before continuing.

---

### A4 — Check for Available MIG Capacity

The NIMService below requests a **MIG (Multi-Instance GPU)** slice rather than a whole GPU. MIG lets NVIDIA GPUs be partitioned into smaller, isolated slices so multiple workloads can share one physical GPU.

A profile like `mig-2g.35gb` follows the pattern `<compute-slices>g.<memory>gb` — e.g. `2g` = 2 compute slices, `35gb` = 35 GB of GPU memory for that slice. The exact profiles available depend on your GPU model and how the node has been partitioned.

Before deploying, check whether your cluster has an open MIG slice matching the profile you need:

```
oc describe node <gpu-node-name> | grep -A 10 "Allocatable"
```

Look for a line matching your target profile (e.g. `nvidia.com/mig-2g.35gb`) and confirm the available count is greater than 0. You can also check what's already been claimed by other pods:

```
oc get pods -A -o json | grep -B 5 "mig-"
```

If no matching slice is free, you'll need to either wait for one to free up, use a different profile size, or repartition.

---

### A5 — Create the NIMService

> ⚠️ Only run this **after** the NIMCache pod is up and ready, and you've confirmed MIG capacity above.

```yaml
apiVersion: apps.nvidia.com/v1alpha1
kind: NIMService
metadata:
  name: meta-llama-3-2-1b-instruct
  namespace: <your-namespace>
spec:
  image:
    repository: nvcr.io/nim/meta/llama-3.2-1b-instruct
    tag: "1.12.0"
    pullPolicy: IfNotPresent
    pullSecrets:
      - <ngc-pull-secret>
  authSecret: <ngc-api-secret>
  storage:
    nimCache:
      name: meta-llama-3-2-1b-instruct
      profile: ''
  resources:
    limits:
      nvidia.com/gpu: 0
      nvidia.com/mig-2g.35gb: 1
  expose:
    service:
      type: ClusterIP
      port: 8000
```

```
oc create -f llm-nimservice.yaml
```

Check **Workloads → Deployments** or run:

```
oc get nimservice meta-llama-3-2-1b-instruct -o yaml
```

Wait until the pod is `Running` before forwarding a port to it.

---

### A6 — Port Forward the Service

```
oc port-forward -n <your-namespace> service/meta-llama-3-2-1b-instruct 8001:8000
```

- `8001` — the local port on your machine
- `8000` — the service port on the cluster

The local port can be any unused port number. Keep this command running in your terminal; it forwards traffic for as long as it's active.

---

### A7 — Verify

```
curl http://localhost:8001/v1/models
```

A successful response confirms the LLM is reachable locally. Now continue to [Step 3 — Configure the `.env`](#step-3--configure-the-env).

---

## Option B — Ollama (local)

Ollama runs models entirely on your local machine. No cluster access required.

### B1 — Install Ollama

Download and install from [ollama.com](https://ollama.com), then confirm it's available:

```
ollama --version
```

---

### B2 — Pull a Model

```
ollama pull llama3.2:3b     # ~2 GB — runs on most laptops (8 GB RAM+)
# ollama pull llama3.1:8b   # ~5 GB — better answers, needs 16 GB RAM+
# ollama pull gemma3:4b     # ~3 GB — good alternative
```

Replace the model name with whichever you prefer (see [ollama.com/library](https://ollama.com/library)). To list what you already have:

```
ollama list
```

---

### B3 — Start the Ollama Server

If Ollama is not already running as a background service, start it:

```
ollama serve
```

By default it listens on `http://localhost:11434`.

---

### B4 — Verify

```
curl http://localhost:11434/api/tags
```

A successful response lists your available models and confirms Ollama is running.

---

## Step 3 — Configure the `.env`

Whichever option you used above, the application needs to know where the LLM is and which model to request. These two values go in **`backend/.env`**:

```env
LLM_BASE_URL=   # URL of your LLM service (see table below)
LLM_MODEL=      # Model name/identifier to request
```

| Setup | `LLM_BASE_URL` | `LLM_MODEL` example |
|---|---|---|
| NVIDIA NIM (port-forwarded, Option A) | `http://localhost:8001` | `meta/llama-3.2-1b-instruct` |
| Ollama (local, Option B) | `http://localhost:11434` | `llama3.2:3b` |

The full list of available variables and their descriptions is in [`backend/.env.example`](../backend/.env.example).

Once `LLM_BASE_URL` and `LLM_MODEL` are set, return to **[Getting Started](GETTING_STARTED.md#step-3--configure-the-app)** to configure and run the application.
