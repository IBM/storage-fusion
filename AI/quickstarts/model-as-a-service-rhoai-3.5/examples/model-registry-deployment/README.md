# Deploying Models from Model Registry

This directory contains Helm values files and documentation for deploying models directly from the OpenShift AI Model Registry.

## Overview

The enhanced `maas-model-service` Helm chart now supports deploying models that are registered in the Model Registry. The deployment script automatically:

1. **Validates** that the model exists in the registry
2. **Fetches** the model URI from the registry database
3. **Deploys** the model using the LLMInferenceService CR

## Prerequisites

- OpenShift AI with Model Registry installed
- Models registered in the model registry (see `model-registry` namespace)
- Target namespace for model deployment
- Connection secret for OCI registry access (if required)

## How It Works

### Model Registry Validation

When `modelRegistry.enabled: true` is set in the values file, the deployment script:

1. Connects to the model registry database
2. Queries for the specified model name
3. Retrieves the model ID and URI
4. Validates the model exists before proceeding with deployment

### Connection Secret

The connection secret is used for pulling model images from OCI registries. Key points:

- **First deployment**: You must specify a connection secret name in the values file
- **Subsequent deployments**: Models in the same namespace can reuse existing connection secrets
- **Secret contents**: Contains OCI registry host and access type (Pull)

Example secret structure:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: granite-3-1-8b-lab-v1-model
  annotations:
    opendatahub.io/connection-type-protocol: oci
    opendatahub.io/connection-type-ref: oci-v1
    openshift.io/display-name: granite-3-1-8b-lab-v1-model
data:
  ACCESS_TYPE: WyJQdWxsIl0=  # ["Pull"]
  OCI_HOST: cmVnaXN0cnkucmVkaGF0Lmlv  # registry.redhat.io
type: Opaque
```

## Usage

### 1. Check Available Models

List all models registered in the model registry:

```bash
cd quickstarts/model-as-a-service
./scripts/query-model-registry.sh --list
```

### 2. Get Model Details

Query specific model information:

```bash
./scripts/query-model-registry.sh --model granite-3.1-8b-lab-v1
```

### 3. Deploy a Model

Deploy using the provided values files:

```bash
./scripts/deploy-model.sh examples/model-registry-deployment/granite-31-8b-lab-v1-values.yaml
```

The script will:
- Validate the model exists in the registry
- Show model details (ID, name, URI)
- Deploy the model to the specified namespace

## Values File Configuration

### Required Fields

```yaml
model:
  name: granite-31-8b-lab-v1-version-1  # Kubernetes resource name
  displayName: "granite-3.1-8b-lab-v1 - Version 1"
  namespace: model-deploy-rhoai  # Target namespace

modelRegistry:
  enabled: true  # Enable model registry mode
  name: model-registry  # Registry name
  namespace: rhoai-model-registries  # Registry namespace
  registeredModelName: "granite-3.1-8b-lab-v1"  # Model name in registry
  connectionSecret: "granite-3-1-8b-lab-v1-model"  # Connection secret name

source:
  uri: oci://registry.redhat.io/rhelai1/modelcar-granite-3-1-8b-lab-v1:1.4.0
```

### Optional Fields

```yaml
modelRegistry:
  registeredModelId: "1"  # Model ID (auto-fetched if not provided)
  modelVersionId: "2"  # Version ID (uses latest if not provided)
```

## Example Values Files

### granite-31-8b-lab-v1-values.yaml

Deploys the Granite 3.1 8B Lab model from the registry.

```bash
./scripts/deploy-model.sh examples/model-registry-deployment/granite-31-8b-lab-v1-values.yaml
```

### qwen3-8b-fp8-dynamic-values.yaml

Deploys the Qwen3 8B FP8 Dynamic model from the registry.

```bash
./scripts/deploy-model.sh examples/model-registry-deployment/qwen3-8b-fp8-dynamic-values.yaml
```

## Deployment Workflow

```
1. User specifies model name in values.yaml
   ↓
2. Script validates model exists in registry
   ↓
3. Script fetches model URI from database
   ↓
4. Helm deploys LLMInferenceService CR
   ↓
5. OpenShift AI creates inference pods
   ↓
6. Model becomes available for inference
```

## Model Registry Database Schema

The model registry uses PostgreSQL with the following key tables:

- **Context**: Stores registered models (type_id = 17) and versions (type_id = 18)
- **Artifact**: Stores model artifacts with URIs
- **ArtifactProperty**: Stores model metadata (source_name, source_class, etc.)
- **ParentContext**: Links versions to their parent models

## Troubleshooting

### Model Not Found

If you see "Model not found in registry":

1. Check available models:
   ```bash
   ./scripts/query-model-registry.sh --list
   ```

2. Verify the exact model name (case-sensitive)

3. Ensure the model is registered in the correct registry

### Connection Secret Issues

If deployment fails due to missing connection secret:

1. Check if secret exists:
   ```bash
   oc get secret -n <namespace>
   ```

2. Create the connection secret manually or deploy a model via the UI first

3. Reuse existing connection secrets for subsequent deployments

### Database Connection Issues

If the script cannot connect to the database:

1. Verify the model registry pod is running:
   ```bash
   oc get pods -n rhoai-model-registries -l app.kubernetes.io/component=database
   ```

2. Check the registry namespace is correct in values file

## Advanced Usage

### Query Model Registry Directly

```bash
# Get model by ID
./scripts/query-model-registry.sh --id 1

# Get model with specific version
./scripts/query-model-registry.sh --model granite-3.1-8b-lab-v1 --version "Version 1"

# Output in JSON format
./scripts/query-model-registry.sh --model granite-3.1-8b-lab-v1 --format json
```

### Custom Registry Configuration

```yaml
modelRegistry:
  enabled: true
  name: custom-registry  # Custom registry name
  namespace: custom-namespace  # Custom namespace
  registeredModelName: "my-model"
```

## Benefits of Model Registry Deployment

1. **Centralized Management**: All models registered in one place
2. **Version Control**: Track model versions and metadata
3. **Validation**: Automatic validation before deployment
4. **Consistency**: Ensures deployed models match registry entries
5. **Traceability**: Clear lineage from registry to deployment

## Next Steps

- Explore GitOps deployment with ArgoCD (see `../maas-model-service-gitops-deployment/`)
- Set up monitoring and observability
- Configure rate limiting and access control
- Integrate with CI/CD pipelines
