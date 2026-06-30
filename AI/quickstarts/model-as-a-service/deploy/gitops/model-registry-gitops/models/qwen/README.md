# Qwen2-72B Model Example

This directory contains the model definition and deployment scripts for the Qwen2-72B large language model from Alibaba Cloud.

## Model Overview

**Qwen2-72B** is a 72 billion parameter large language model that excels at:
- Text generation and completion
- Question answering
- Code generation and understanding
- Multilingual translation (8+ languages)
- Document summarization
- Reasoning and problem-solving

## Model Specifications

- **Parameters**: 72 billion
- **Context Length**: 32,768 tokens
- **Languages**: English, Chinese, Spanish, French, German, Japanese, Korean, Arabic
- **License**: Apache 2.0
- **Source**: Hugging Face (Qwen/Qwen2-72B)
- **Size**: ~145GB (full precision)

## Hardware Requirements

### Minimum Requirements
- **GPU**: 4x NVIDIA A100 80GB
- **Memory**: 160GB RAM
- **CPU**: 32 cores
- **Storage**: 200GB

### Recommended for Production
- **GPU**: 8x NVIDIA A100 80GB or H100
- **Memory**: 320GB RAM
- **CPU**: 64 cores
- **Quantization**: 4-bit or 8-bit (reduces memory to ~40GB)

## Quick Start

### Option 1: GitOps (Recommended for Production)

**Note**: Due to the large size (145GB), this model is registered as metadata only. The actual model weights are referenced from Hugging Face.

The recommended approach is to use GitOps, which automatically registers models when you commit them to your repository:

```bash
# 1. Copy model definition to your GitOps repo
cp models/qwen2/qwen2-72b.yaml /path/to/your/gitops-repo/models/

# 2. Commit and push
cd /path/to/your/gitops-repo
git add models/qwen2-72b.yaml
git commit -m "Add Qwen2-72B model"
git push

# 3. The reconciler CronJob will automatically register it in MLflow
# Check the reconciler logs:
oc logs -n model-registry-gitops -l app=model-registry-reconciler --tail=50
```

**Why GitOps?**
- ✅ Automatic synchronization
- ✅ Version control for model definitions
- ✅ Audit trail of all changes
- ✅ No need for external access to MLflow

### Option 2: Job-Based Registration (For Testing)

For quick testing without GitOps, create a Kubernetes Job that runs inside the cluster:

```bash
# Use the deploy-command-based.sh script which creates a Job
cd models/chatgpt
./deploy-command-based.sh \
  --model-file ../../models/qwen2/qwen2-72b.yaml \
  --mlflow-namespace redhat-ods-applications \
  --job-namespace model-registry-gitops

# Monitor the job
oc logs -n model-registry-gitops -l job-name=register-qwen2-72b --follow
```

**Note**: This creates a Job that runs inside the cluster where MLflow is accessible via internal service URLs.

### Option 3: Local Development

For local development with a local MLflow instance:

```bash
# Ensure MLflow is deployed locally
cd ../../
./scripts/setup-local-env.sh

# Register the model
./scripts/register-model.sh models/qwen2/qwen2-72b.yaml \
  --mlflow-uri "http://localhost:5000"
```

**Important**: The `register-model.sh` script is designed for **local development** only. It cannot access MLflow running inside OpenShift from outside the cluster due to network isolation. For OpenShift deployments, use Option 1 (GitOps) or Option 2 (Job).

## Deployment Considerations

### 1. Quantization (Recommended)

For production deployment, use quantization to reduce memory requirements:

```python
from transformers import AutoModelForCausalLM, AutoTokenizer
import torch

# Load with 4-bit quantization
model = AutoModelForCausalLM.from_pretrained(
    "Qwen/Qwen2-72B",
    device_map="auto",
    load_in_4bit=True,
    torch_dtype=torch.float16
)

tokenizer = AutoTokenizer.from_pretrained("Qwen/Qwen2-72B")
```

### 2. Tensor Parallelism

For multi-GPU deployment:

```python
# Using vLLM for efficient serving
from vllm import LLM

llm = LLM(
    model="Qwen/Qwen2-72B",
    tensor_parallel_size=4,  # Use 4 GPUs
    dtype="float16",
    max_model_len=8192
)
```

### 3. Inference Service

Deploy using KServe/vLLM:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: qwen2-72b
spec:
  predictor:
    model:
      modelFormat:
        name: vllm
      storageUri: "hf://Qwen/Qwen2-72B"
      resources:
        requests:
          nvidia.com/gpu: "4"
          memory: "160Gi"
        limits:
          nvidia.com/gpu: "4"
          memory: "320Gi"
      args:
        - --tensor-parallel-size=4
        - --dtype=float16
        - --max-model-len=8192
```

## Use Cases

### 1. Enterprise Chatbot

```python
import mlflow
from transformers import pipeline

# Load model from MLflow
model_uri = "models:/qwen2-72b/Production"
model = mlflow.transformers.load_model(model_uri)

# Create chatbot
chatbot = pipeline("text-generation", model=model)

response = chatbot(
    "What are the key features of cloud computing?",
    max_length=200
)
```

### 2. Code Generation

```python
prompt = """
Write a Python function to calculate the Fibonacci sequence:
"""

response = chatbot(prompt, max_length=300)
print(response[0]['generated_text'])
```

### 3. Multilingual Translation

```python
prompt = """
Translate the following English text to Chinese:
"Artificial intelligence is transforming the way we work."
"""

response = chatbot(prompt, max_length=100)
```

## Performance Benchmarks

- **MMLU**: 84.2% (Massive Multitask Language Understanding)
- **HumanEval**: 64.6% (Code generation)
- **GSM8K**: 89.5% (Math reasoning)

## Governance and Compliance

- ✅ **License**: Apache 2.0 (commercial use allowed)
- ✅ **Security**: Scanned with Trivy
- ✅ **Approval**: Approved by AI Governance team
- ⚠️ **Restrictions**:
  - Requires GPU infrastructure
  - Monitor for bias in multilingual outputs
  - Human oversight recommended for critical applications
  - Quantization recommended for production

## Cost Considerations

### Cloud Costs (Estimated)

**AWS**:
- 4x p4d.24xlarge (A100): ~$32/hour
- 8x p4d.24xlarge (A100): ~$64/hour

**Azure**:
- 4x Standard_ND96asr_v4 (A100): ~$27/hour
- 8x Standard_ND96asr_v4 (A100): ~$54/hour

**With Quantization (4-bit)**:
- Can run on 2x A100 80GB: ~$16/hour
- Reduces costs by 50-75%

## Troubleshooting

### Out of Memory Errors

```bash
# Use quantization
model = AutoModelForCausalLM.from_pretrained(
    "Qwen/Qwen2-72B",
    load_in_4bit=True,
    device_map="auto"
)

# Or reduce context length
llm = LLM(model="Qwen/Qwen2-72B", max_model_len=4096)
```

### Slow Inference

```bash
# Use vLLM for faster inference
pip install vllm

# Enable tensor parallelism
llm = LLM(model="Qwen/Qwen2-72B", tensor_parallel_size=4)
```

### Model Download Issues

```bash
# Use Hugging Face CLI for better control
huggingface-cli download Qwen/Qwen2-72B --local-dir ./qwen2-72b

# Or use snapshot download
from huggingface_hub import snapshot_download
snapshot_download("Qwen/Qwen2-72B", local_dir="./qwen2-72b")
```

## Resources

- **Model Card**: https://huggingface.co/Qwen/Qwen2-72B
- **Paper**: https://arxiv.org/abs/2407.10671
- **GitHub**: https://github.com/QwenLM/Qwen2
- **Documentation**: https://qwenlm.github.io/

## Support

For issues or questions:
- Check Qwen2 GitHub issues
- Review Hugging Face model card
- Contact AI platform team
