# Adding a Model to the Registry

This guide explains how to register a new model in the OpenShift AI Model Registry via GitOps by creating a `ModelVersion` YAML file.

## How It Works

1. You create a YAML file under `models/<your-org>/your-model.yaml`
2. You commit and push to Git
3. ArgoCD detects the change and updates the `model-definitions` ConfigMap
4. The Model Reconciler reads the ConfigMap and registers the model via the Model Registry API

---

## File Location

Place your file in a subdirectory named after the model family or your organisation:

```
models/
├── granite/          # IBM Granite models
├── qwen/             # Qwen models
├── chatgpt/          # OpenAI-based models
├── gpt-oss/          # GPT OSS models
├── test-model/       # Lightweight models for testing
└── <your-org>/       # ← create your own subdirectory
    └── your-model.yaml
```

---

## YAML Structure

Every model file must follow this structure. Fields marked **required** must always be present.

```yaml
apiVersion: v1              # required — always v1
kind: ModelVersion          # required — always ModelVersion
metadata:
  name: my-model-name       # required — lowercase, hyphens only (e.g. granite-4-8b)
  labels:                   # optional — used for filtering in ArgoCD and the registry
    model-type: public       # public | private | fine-tuned | internal
    source: huggingface      # huggingface | s3 | http | local
    task: text-generation    # free-form task label
    governance-status: approved   # approved | pending | rejected

spec:
  modelName: "My Model"     # required — display name in the UI
  version: "1.0.0"          # required — version string
  description: |            # required — human-readable description
    What this model does, who it is for, and any important notes.

  author: "Your Org"        # optional — model creator

  # --- Where the upstream model comes from ---
  baseModel:                # optional but recommended
    name: "org/model-id"
    source: huggingface     # huggingface | s3 | http | local
    sourceUrl: "https://huggingface.co/org/model-id"
    version: "main"         # branch, tag, or commit hash
    license: "Apache-2.0"   # SPDX identifier
    licenseUrl: "https://..."

  # --- Governance / compliance sign-off ---
  governance:               # optional but recommended for production models
    approvedBy: "platform-team@example.com"
    approvalDate: "2024-06-01"
    approvalTicket: "JIRA-12345"
    licenseVerified: true
    securityScanned: true
    scanDate: "2024-05-31"
    scanTool: "trivy"
    complianceStatus: approved   # approved | pending | rejected
    restrictions:
      - "Requires GPU for optimal performance"
      - "Not approved for medical advice"

  # --- Where the model artifacts are stored ---
  storage:                  # required
    uri: "hf://org/model-id"            # storage URI (see URI Formats below)
    type: huggingface                   # huggingface | s3 | http | local | oci
    size: "16GB"                        # optional — approximate size
    format: safetensors                 # optional — safetensors | pytorch | onnx | gguf

  # --- Technical metadata ---
  metadata:                 # optional — enriches the registry catalog
    framework: transformers
    frameworkVersion: "4.40.0"
    modelType: causal-lm
    architecture: Llama
    parameters: "8B"
    contextLength: "8192"
    languages:
      - en
    tasks:
      - text-generation
      - instruction-following
    metrics:
      perplexity: "6.2"
    training:
      dataset: "Publicly available datasets"
      trainingFramework: PyTorch
    requirements:
      minMemory: "16GB"
      recommendedMemory: "32GB"
      gpu: required         # required | optional | not-required
      minCpu: "4 cores"
      recommendedGpu: "NVIDIA A100"

  # --- Approved use cases ---
  useCases:                 # optional
    - name: "Enterprise Chatbot"
      description: "Conversational AI for customer support"
      status: approved      # approved | pending | rejected

  # --- KServe deployment hints ---
  deployment:               # optional
    servingFramework: kserve
    runtime: huggingface
    replicas: 1
    resources:
      requests:
        memory: "16Gi"
        cpu: "4"
        nvidia.com/gpu: "1"
      limits:
        memory: "32Gi"
        cpu: "8"
        nvidia.com/gpu: "1"
    autoscaling:
      enabled: true
      minReplicas: 1
      maxReplicas: 3
      targetCPU: 70

  # --- Searchable tags ---
  tags:                     # optional — flat list of strings
    - llm
    - my-org
    - approved
    - production-ready
```

---

## Storage URI Formats

| Source | URI Format | Example |
|--------|-----------|---------|
| Hugging Face | `hf://org/model-id` | `hf://ibm-granite/granite-4.1-8b` |
| S3 / ODF | `s3://bucket/path/to/model` | `s3://model-artifacts/granite/v1` |
| OCI Registry | `oci://registry/image:tag` | `oci://registry.redhat.io/rhelai1/modelcar-granite:1.4.0` |
| HTTP | `https://example.com/model.tar.gz` | — |

---

## Naming Rules (`metadata.name`)

The name must be **DNS-1123 compliant**:
- Lowercase letters, digits, and hyphens only
- Must start and end with a letter or digit
- No underscores, dots, or uppercase letters

| ✅ Valid | ❌ Invalid |
|---------|----------|
| `granite-4-8b` | `Granite_4.8B` |
| `qwen3-8b-fp8` | `qwen3 8b fp8` |
| `my-model-v2` | `-my-model` |

---

## Minimal Example

The smallest valid file — only required fields:

```yaml
apiVersion: v1
kind: ModelVersion
metadata:
  name: my-small-model
spec:
  modelName: "My Small Model"
  version: "1.0.0"
  description: "A compact model for text classification tasks."
  storage:
    uri: "hf://my-org/my-small-model"
    type: huggingface
```

---

## Full Examples

See the existing models for complete, production-ready examples:

| File | What it shows |
|------|--------------|
| [`granite/granite-4.1-8b.yaml`](granite/granite-4.1-8b.yaml) | GPU model with autoscaling, governance, multilingual metadata |
| [`qwen/qwen3-8b-fp8-dynamic-hf.yaml`](qwen/qwen3-8b-fp8-dynamic-hf.yaml) | FP8-quantised model, tool-calling use case |
| [`chatgpt/dialogpt-medium.yaml`](chatgpt/dialogpt-medium.yaml) | Smaller CPU-capable model with performance metrics |
| [`test-model/tiny-llama.yaml`](test-model/tiny-llama.yaml) | Minimal test model, no GPU required |

---

## Step-by-Step: Register a New Model

### 1. Create the file

```bash
mkdir -p models/my-org
vi models/my-org/my-new-model.yaml
```

### 2. Validate YAML syntax locally

```bash
# Install yamllint if needed
pip install yamllint

# Lint against the project rules
yamllint -c .yamllint models/my-org/my-new-model.yaml
```

### 3. Commit and push

```bash
git add models/my-org/my-new-model.yaml
git commit -m "feat: register my-new-model v1.0.0"
git push origin <your-branch>
```

### 4. Open a pull request

The CI workflow (`.github/workflows/validate-models.yaml`) will automatically:
- Lint all YAML files
- Check for duplicate `metadata.name` values
- Validate required fields

### 5. After merge — watch the sync

```bash
# Watch ArgoCD pick up the change
oc get applications -n openshift-gitops -l app=fusion-model-registry-gitops

# Watch the reconciler register the model
oc logs -f deployment/model-reconciler -n fusion-model-registry-gitops-dev

# Confirm it appears in the registry
oc exec -n rhoai-model-registries deployment/model-registry -- \
  curl -s http://localhost:8080/api/model_registry/v1alpha3/registered_models | \
  grep my-new-model
```

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `metadata.name` uses uppercase or underscores | Use only lowercase letters, digits, and hyphens |
| Two files have the same `metadata.name` | CI will catch this — each model must have a unique name |
| `storage.uri` missing | `storage` with `uri` and `type` is required |
| `storage.type` is `huggingface` but `uri` starts with `s3://` | Match the URI scheme to the `type` value |
| `governance.complianceStatus` is not `approved` | The reconciler will skip non-approved models in production environments |
