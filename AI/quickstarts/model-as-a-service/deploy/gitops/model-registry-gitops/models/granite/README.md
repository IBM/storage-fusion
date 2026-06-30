# IBM Granite Models

This directory contains model definitions for IBM Granite language models available through Red Hat AI Model Catalog.

## Available Models

### granite-3.1-8b-lab-v1

IBM Granite 3.1 8B Lab v1 is an enterprise-grade language model optimized for:
- Instruction following
- Code generation
- General-purpose text generation
- Question answering
- Document summarization

**Key Features:**
- 8 billion parameters
- 8K context length
- Apache 2.0 license
- Optimized for Red Hat OpenShift AI
- Supports quantization (4-bit, 8-bit)

**Model Registry Information:**
- **URI**: `oci://registry.redhat.io/rhelai1/modelcar-granite-3-1-8b-lab-v1:1.4.0`
- **Version**: 1.4.0
- **Source**: Red Hat AI Model Catalog
- **Model Source Class**: `redhat_ai_models`
- **Model Source Name**: `granite-3.1-8b-lab-v1`

**Hardware Requirements:**
- Minimum: 32GB RAM, 8 CPU cores, 1x A10G/T4 GPU
- Recommended: 64GB RAM, 16 CPU cores, 1x A100/L4 GPU

**Deployment:**
- Serving Framework: vLLM
- Runtime: HuggingFace Transformers
- Supports autoscaling (1-3 replicas)
- Optimized with 8-bit quantization

## GitOps Workflow

When this model definition is committed to the repository:

1. **ArgoCD/Flux Sync**: The GitOps controller detects the new model file
2. **ConfigMap Update**: Model definition is added to the `model-definitions` ConfigMap
3. **Registry Sync**: The model reconciler syncs the model to the Model Registry
4. **Database Entry**: Model metadata is stored in the registry database

## Verification

To verify the model is registered in the database:

```bash
# Connect to the model registry database
oc rsh -n rhoai-model-registries model-registry-db-<pod-id>

# Check the Artifact table
psql -U postgres -d modelregistry
SELECT * FROM "Artifact" WHERE name LIKE '%granite%';

# Check the ArtifactProperty table
SELECT * FROM "ArtifactProperty" WHERE artifact_id IN (
  SELECT id FROM "Artifact" WHERE name LIKE '%granite%'
);

# Check the Context table
SELECT * FROM "Context" WHERE name LIKE '%granite%';
```

## Model Usage

Once registered, the model can be deployed using:

1. **Red Hat OpenShift AI Dashboard**: Select the model from the Model Registry
2. **Helm Chart**: Use the `maas-model-service` chart with the model name
3. **GitOps**: Deploy via ArgoCD application referencing this model

## Related Documentation

- [Model Registry GitOps Guide](../../README.md)
- [Red Hat OpenShift AI Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai)
- [IBM Granite Models](https://www.ibm.com/granite)