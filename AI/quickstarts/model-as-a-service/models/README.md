# MaaS Models (Serving & Deployment)

The `models` repository manages the full lifecycle of LLMs on the platform:
1. **Serving Helm Charts:** Standardized templates for `LLMInferenceService` (KServe / vLLM on GPU and CPU).
2. **Deployment Configuration:** Per-model Helm values (single source of truth) and ArgoCD Applications.
3. **Model Registration & Automated Deployment:** Scripts to register models in OpenShift AI Model Registry and deploy them to the cluster.

---

## Directory Structure

```
models/
├── README.md                          # Models lifecycle guide
├── charts/                            # Model serving Helm charts
│   ├── maas-model-service/            # Standard LLMInferenceService + HTTPRoute + vLLM (Production)
│   ├── maas-model-deploy/             # Weight staging (OBC + HF download + PVC populate)
│   └── model-deploy-vllm-cpu/         # CPU-optimized vLLM serving runtime
├── config/                            # Model deployment values & GitOps
│   ├── helm/                          # Per-model values files (single source of truth)
│   │   ├── nemotron-3-ultra-550b-nvfp4.yaml
│   │   ├── gpt-oss-20b.yaml
│   │   ├── granite-3.1-8b.yaml
│   │   ├── laguna-s2-1.yaml
│   │   ├── mistral-medium-3.5-fp8.yaml
│   │   └── qwen3-8b-fp8.yaml
│   └── gitops/                        # ArgoCD Application manifests for models
│       ├── dev/
│       ├── staging/
│       └── prod/
└── scripts/
    ├── register-models.sh             # Registers model and versions in Model Registry REST API
    └── deploy-model.sh                # Single model deployer with RHOAI dashboard validation
```

---

## 2-Step Model Lifecycle

### Step 1: Configure or Select Model Values

Configure your model values under `models/config/helm/<model-name>.yaml` (e.g. storage URI, tensor parallelism, accelerator type).

### Step 2: Register in Model Registry

```bash
# Register a specific model by name or values file:
./models/scripts/register-models.sh nemotron-ultra-550b
# or:
./models/scripts/register-models.sh models/config/helm/nemotron-3-ultra-550b-nvfp4.yaml
# or register all known models:
./models/scripts/register-models.sh --all
```

### Step 3: Deploy Model Inference Service

#### Using Helm / CLI:
```bash
./scripts/deploy-model.sh config/helm/granite-3.1-8b.yaml
```

#### Using GitOps (ArgoCD):
```bash
oc apply -f config/gitops/prod/applications/application-gpt-oss-20b.yaml
```

---

## Verifying Model Serving

```bash
# Check inference service status
oc get llminferenceservice -n deploy-models-rhoai

# Stream vLLM engine logs
oc logs -n deploy-models-rhoai -l serving.kserve.io/inferenceservice=granite-3.1-8b -c kserve-container -f
```
