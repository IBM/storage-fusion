# Model Registry GitOps — Verification Guide

Post-deployment health checks for the Model Registry GitOps pipeline.

## GitOps Flow

```
Git (models/*.yaml)
    ↓  ArgoCD syncs on push
ConfigMap: model-definitions
    ↓  Reconciler watches
Model Reconciler Deployment
    ↓  Calls REST API
Model Registry API  (rhoai-model-registries)
    ↓
PostgreSQL Database  →  RHOAI UI
```

---

## 1. ArgoCD Application

```bash
# Check sync and health status
oc get applications -n openshift-gitops -l app=fusion-model-registry-gitops

# Detailed status for a specific environment
argocd app get fusion-model-registry-gitops-dev
argocd app get fusion-model-registry-gitops-staging
argocd app get fusion-model-registry-gitops-prod

# Trigger manual sync (staging/prod)
argocd app sync fusion-model-registry-gitops-staging
```

**Expected:** `STATUS: Synced`, `HEALTH: Healthy`

---

## 2. Reconciler Deployment

```bash
# Check pod is running
oc get deployment model-reconciler -n fusion-model-registry-gitops-dev
oc get pods -n fusion-model-registry-gitops-dev -l app=model-reconciler

# Watch live logs
oc logs -f deployment/model-reconciler -n fusion-model-registry-gitops-dev
```

**Expected log messages (successful run):**

```
INFO - Connected to Model Registry at http://model-registry.rhoai-model-registries.svc.cluster.local:8080
INFO - Watching ConfigMap model-definitions in namespace fusion-model-registry-gitops-dev
INFO - ConfigMap model-definitions changed, reconciling...
INFO - Found N model definition(s)
INFO - Processing model: <model-name>
INFO - Model <model-name> version <x.x.x> already exists    ← idempotent skip
# OR
INFO - Successfully registered model <model-name> (ID: X)  ← new registration
INFO - Reconciliation complete
```

---

## 3. ConfigMap Contents

```bash
# View all model definitions loaded into the ConfigMap
oc get configmap model-definitions -n fusion-model-registry-gitops-dev -o yaml

# Check a specific model is present
oc get configmap model-definitions -n fusion-model-registry-gitops-dev \
  -o jsonpath='{.data}' | jq 'keys'
```

---

## 4. Model Registry API

```bash
# List all registered models
oc exec -n rhoai-model-registries deployment/model-registry -- \
  curl -s http://localhost:8080/api/model_registry/v1alpha3/registered_models | jq

# Get a specific model
oc exec -n rhoai-model-registries deployment/model-registry -- \
  curl -s "http://localhost:8080/api/model_registry/v1alpha3/registered_models/<model-name>" | jq

# Port-forward for local inspection
oc port-forward -n rhoai-model-registries svc/model-registry 8080:8080
# Then: curl http://localhost:8080/api/model_registry/v1alpha3/registered_models
```

---

## 5. Database (PostgreSQL)

Direct database verification when API checks are insufficient:

```bash
# Find the database pod
oc get pods -n rhoai-model-registries | grep db

# Connect to the database
oc rsh -n rhoai-model-registries <model-registry-db-pod>
psql -U postgres -d modelregistry

# List all registered models
SELECT id, name FROM "Context" WHERE type_id = (
  SELECT id FROM "Type" WHERE name = 'odh.RegisteredModel'
);

# List all model versions
SELECT id, name FROM "Context" WHERE type_id = (
  SELECT id FROM "Type" WHERE name = 'odh.ModelVersion'
);

# List all artifacts (storage URIs)
SELECT id, uri, state FROM "Artifact";
```

---

## 6. RHOAI Dashboard

1. Open the OpenShift AI Dashboard
2. Navigate to **Model Registry**
3. Confirm your models appear with correct names, versions, and metadata
4. Click a model → verify the storage URI and description are correct

---

## Verification Checklist

- [ ] ArgoCD application status is **Synced** and **Healthy**
- [ ] Reconciler pod is **Running** in `fusion-model-registry-gitops-{env}`
- [ ] ConfigMap `model-definitions` contains the expected model keys
- [ ] Reconciler logs show successful processing (no ERROR lines)
- [ ] Model Registry API returns the expected models
- [ ] Models are visible in the RHOAI Dashboard

---

## Troubleshooting

### ArgoCD application not syncing

```bash
# Check for sync errors
oc describe application fusion-model-registry-gitops-dev -n openshift-gitops

# Check ArgoCD controller logs
oc logs -n openshift-gitops deployment/argocd-application-controller --tail=50

# Force sync
oc patch application fusion-model-registry-gitops-dev -n openshift-gitops \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### Reconciler pod not starting / ImagePullBackOff

```bash
oc describe pod -n fusion-model-registry-gitops-dev -l app=model-reconciler
oc get events -n fusion-model-registry-gitops-dev --sort-by='.lastTimestamp'
```

### Model registered but not in RHOAI dashboard

```bash
# Check model catalog ConfigMap
oc get configmap model-catalog-sources -n rhoai-model-registries -o yaml

# Restart catalog pods to force a refresh
oc delete pod -l component=model-catalog -n rhoai-model-registries
```

### RBAC errors in reconciler logs

```bash
# Check what the reconciler service account is allowed to do
oc auth can-i --list \
  --as=system:serviceaccount:fusion-model-registry-gitops-dev:model-reconciler \
  -n rhoai-model-registries
```
