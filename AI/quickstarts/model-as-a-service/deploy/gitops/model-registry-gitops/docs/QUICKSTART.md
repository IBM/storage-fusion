# Model Registry GitOps — Quick Start

Get from zero to a registered model in production by following these steps.

## Prerequisites

- OpenShift cluster with OpenShift AI and Model Registry enabled
- ODF (OpenShift Data Foundation) for object storage
- OpenShift GitOps (ArgoCD) installed
- `oc` CLI logged in to the cluster
- Membership in the `model-registry-prod-admins` or `model-registry-prod-deployers` ArgoCD group

---

## Step 1: Create the AppProject

The AppProject must exist before any secrets or the Application are created — it defines the allowed namespaces and RBAC. The `fusion-model-registry-gitops-prod` namespace does not exist yet; it is created in Step 3.

```bash
oc apply -f argocd/environments/prod/appproject-prod.yaml

# Verify it was created in openshift-gitops
oc get appproject fusion-model-registry-gitops-prod -n openshift-gitops
```

---

## Step 2: Create Secrets

### Git credentials (private repositories only)

> **⚠️ Create the namespace first**, then the secret. The `fusion-model-registry-gitops-prod` namespace does not exist yet, so create it manually before adding the secret:

```bash
# Create the namespace manually (ArgoCD will adopt it in Step 3)
oc create namespace fusion-model-registry-gitops-prod

# Create the git-credentials secret into that namespace
oc create secret generic git-credentials \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_TOKEN \
  --namespace=fusion-model-registry-gitops-prod

# Verify
oc get secret git-credentials -n fusion-model-registry-gitops-prod
```

### S3 / ODF credentials (for model artifact storage)

These go into `rhoai-model-registries`, which already exists:

```bash
S3_ENDPOINT=$(oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}')
OBC_NAME="model-registry-artifacts-prod"

AWS_ACCESS_KEY=$(oc get secret ${OBC_NAME} -n rhoai-model-registries \
  -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
AWS_SECRET_KEY=$(oc get secret ${OBC_NAME} -n rhoai-model-registries \
  -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
AWS_BUCKET=$(oc get configmap ${OBC_NAME} -n rhoai-model-registries \
  -o jsonpath='{.data.BUCKET_NAME}')

oc create secret generic model-registry-artifacts \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_KEY}" \
  --from-literal=AWS_S3_ENDPOINT="https://${S3_ENDPOINT}" \
  --from-literal=AWS_S3_BUCKET="${AWS_BUCKET}" \
  -n rhoai-model-registries
```

### Hugging Face token (gated models only — Llama, Gemma, Mistral)

```bash
oc create secret generic huggingface-token \
  --from-literal=token="hf_your_token_here" \
  -n rhoai-model-registries
```

---

## Step 3: Deploy the ArgoCD Application

Now that the namespace and secrets are in place, apply the Application manifest. ArgoCD will adopt the existing namespace.

```bash
oc apply -f argocd/environments/prod/application.yaml

# Verify the Application was created
oc get application fusion-model-registry-gitops-prod -n openshift-gitops
```

> **⚠️ Production uses manual sync.** Auto-sync is disabled — ArgoCD will show the application as `OutOfSync` until you trigger a sync manually. Proceed to Step 4 to do that.

---

## Step 4: Trigger the First Sync

Production sync must always be triggered explicitly. Review the diff before syncing:

```bash
# Review what ArgoCD will apply
argocd app diff fusion-model-registry-gitops-prod

# Trigger the sync
argocd app sync fusion-model-registry-gitops-prod

# Watch until Healthy
oc get application fusion-model-registry-gitops-prod -n openshift-gitops -w
```

Or via the ArgoCD UI:
1. Open **Applications** → `fusion-model-registry-gitops-prod`
2. Review the diff
3. Click **Sync** → **Synchronize**

---

## Step 5: Add Your First Model

Create `models/my-org/my-first-model.yaml`:

```yaml
apiVersion: v1
kind: ModelVersion
metadata:
  name: my-first-model
  labels:
    source: huggingface
    task: text-generation
    governance-status: approved
spec:
  modelName: "My First Model"
  version: "1.0.0"
  description: "A production model for GitOps"
  author: "Your Team"
  baseModel:
    name: "microsoft/DialoGPT-small"
    source: "huggingface"
    sourceUrl: "https://huggingface.co/microsoft/DialoGPT-small"
    license: "MIT"
  storage:
    uri: "hf://microsoft/DialoGPT-small"
    type: huggingface
    format: pytorch
  metadata:
    framework: transformers
    modelType: causal-lm
    parameters: "117M"
  tags:
    - chatbot
    - conversational-ai
    - production-ready
```

Commit and push to `main` (the branch tracked by the prod Application):

```bash
git add models/my-org/my-first-model.yaml
git commit -m "feat: register my-first-model v1.0.0"
git push origin main
```

Then trigger a manual sync to pick up the new model definition:

```bash
argocd app sync fusion-model-registry-gitops-prod
```

---

## Step 6: Verify Registration

```bash
# Watch the reconciler process the model
oc logs -n fusion-model-registry-gitops-prod -l app=model-reconciler -f

# Confirm the model is registered
oc exec -n rhoai-model-registries deployment/model-registry -- \
  curl -s http://localhost:8080/api/model_registry/v1alpha3/registered_models | jq
```

Then in the OpenShift AI dashboard:
1. Navigate to **Model Registry**
2. Look for **My First Model**
3. Click to view details and deploy to a serving runtime

---

## Useful Commands

```bash
# Check application status
oc get application fusion-model-registry-gitops-prod -n openshift-gitops

# View all model definitions currently in the ConfigMap
oc get configmap model-definitions -n fusion-model-registry-gitops-prod -o yaml

# List all models in the registry
oc exec -n rhoai-model-registries deployment/model-registry -- \
  curl -s http://localhost:8080/api/model_registry/v1alpha3/registered_models | \
  jq '.items[].name'

# Trigger a manual sync
argocd app sync fusion-model-registry-gitops-prod

# Check reconciler status
oc get deployment model-reconciler -n fusion-model-registry-gitops-prod

# Check reconciler logs
oc logs -n fusion-model-registry-gitops-prod -l app=model-reconciler --tail=50
```

---

## Common Issues

### Reconciler pod not starting

```bash
oc get pods -n fusion-model-registry-gitops-prod
oc get events -n fusion-model-registry-gitops-prod --sort-by='.lastTimestamp'
oc describe pod -n fusion-model-registry-gitops-prod -l app=model-reconciler
```

### Model not appearing in registry

```bash
# Check reconciler logs for errors
oc logs -n fusion-model-registry-gitops-prod -l app=model-reconciler --tail=100

# Verify model ConfigMap was updated after sync
oc get configmap model-definitions -n fusion-model-registry-gitops-prod -o yaml | grep your-model-name

# Verify Model Registry is reachable
oc get svc -n rhoai-model-registries
```

### S3 upload failing

```bash
# Check credentials secret
oc get secret model-registry-artifacts -n rhoai-model-registries -o yaml

# Test S3 connectivity
oc run -it --rm s3-test --image=amazon/aws-cli --restart=Never -- \
  s3 ls --endpoint-url=https://YOUR-S3-ENDPOINT
```

### Model not visible in dashboard

```bash
# Check catalog ConfigMap
oc get configmap model-catalog-sources -n rhoai-model-registries -o yaml

# Restart catalog pods to pick up changes
oc delete pod -l component=model-catalog -n rhoai-model-registries
```

### Application stuck OutOfSync after model commit

Production does not auto-sync. After every merge to `main` you must trigger sync manually:

```bash
argocd app sync fusion-model-registry-gitops-prod
```

---

## Next Steps

- **Add more models** — see [`../models/ADDING_A_MODEL.md`](../models/ADDING_A_MODEL.md) for the full field reference
- **Understand the full deployment runbook** — see [`../argocd/environments/DEPLOYMENT_GUIDE.md`](../argocd/environments/DEPLOYMENT_GUIDE.md)
- **Verify a deployment** — see [`VERIFICATION_GUIDE.md`](VERIFICATION_GUIDE.md)

## Success Criteria

- [ ] AppProject `fusion-model-registry-gitops-prod` exists in `openshift-gitops`
- [ ] ArgoCD application shows **Synced** and **Healthy** after manual sync
- [ ] Reconciler pod is running in `fusion-model-registry-gitops-prod`
- [ ] Model appears in OpenShift AI Model Registry UI
- [ ] Model can be deployed to a serving runtime
