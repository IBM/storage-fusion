# Onboarding a New CAS Cluster

As a **developer**, you register a new CAS cluster in two steps using the self-service template wizard. No cluster access, no SA token, no YAML edits required.

> **Platform engineer?** See the [Platform Onboarding Guide](#platform-onboarding-reference) at the bottom of this page.

## Developer Onboarding — Template Wizard

### Step 1 — Open the wizard

In Developer Hub, click **Create** in the left navigation, then choose **"Add IBM Fusion CAS Cluster"**.

### Step 2 — Fill in two fields

| Field | Example | Notes |
|---|---|---|
| **Name** | `prod-east` | Lowercase, letters/numbers/hyphens. Used as the catalog entity name. |
| **OCP API URL** | `https://api.prod-east.example.com:6443` | Paste exactly from your `oc login` command. |

Click **Next → Create**.

### Step 3 — Done

All CAS endpoints are auto-derived and the component appears in the catalog immediately:

| Endpoint | Derived URL |
|---|---|
| CAS Console | `https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/overview` |
| Swagger UI | `https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/docs` |
| MCP Standard | `https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/mcp` |
| MCP Streamable | `https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/mcp-streamable/` |
| Health | `https://console-ibm-spectrum-fusion-ns.apps.<domain>/cas/api/v1/health` |

> The entity is stored in Developer Hub's catalog DB. To make it permanent across RHDH reinstalls, ask your platform engineer to commit it to Git (Option B in the main README).

---

## Platform Onboarding Reference

This section is for **platform engineers** who manage the RHDH instance and Git repo. Developers do not need to follow these steps.

### Prerequisites

- OpenShift cluster with IBM Fusion HCI 2.13+ deployed
- CAS installed and running in `ibm-spectrum-fusion-ns` namespace
- Admin access to the Git repo (this repository)

### Step 1 — Apply RBAC on the Fusion cluster (K8s plugin only)

Skip this step if K8s plugin tab is not needed for this cluster (proxy-only access is zero-config).

```bash
# Run against the target Fusion cluster, not the RHDH cluster
oc login --server=https://api.<cluster-id>.example.com:6443

# Apply SA + ClusterRole + ClusterRoleBinding
oc apply -n ibm-spectrum-fusion-ns -f k8s/sa-rbac.yaml
oc apply -f k8s/sa-rbac.yaml   # ClusterRole + CAS binding

# Mint a 1-year token
TOKEN=$(oc create token rhdh-fusion-reader -n ibm-spectrum-fusion-ns --duration=8760h)
```

### Step 2 — Store SA token in the RHDH namespace

```bash
oc create secret generic fusion-<cluster-id>-cas-sa-token \
  --from-literal=FUSION_<CLUSTER_ID>_CAS_SA_TOKEN="${TOKEN}" \
  -n <rhdh-namespace> \
  --dry-run=client -o yaml | oc apply -f -
```

### Step 3 — Add cluster entity file

```bash
cp -r clusters/cluster-template clusters/<cluster-id>
# Edit clusters/<cluster-id>/catalog-info.yaml:
#   - Replace all <cluster-id> placeholders
#   - Set fusion.ibm.com/cluster-type: "self-hosted" (K8s plugin) or "proxy-only"
#   - Remove backstage.io/kubernetes-* lines if proxy-only
```

### Step 4 — Register in catalog/locations.yaml

```yaml
    - quickstarts/fusion-developerhub/fusion-ai-discovery/clusters/<cluster-id>/catalog-info.yaml
```

### Step 5 — Add proxy entry to app-config-fusion-services.yaml

```yaml
/fusion-<cluster-id>-cas:
  target: https://console-ibm-spectrum-fusion-ns.apps.<cluster-id>.example.com
  changeOrigin: true
  secure: false
  allowedHeaders: [Authorization, Content-Type, Accept]
  pathRewrite:
    '^/api/proxy/fusion-<cluster-id>-cas': ''
```

### Step 6 — Commit and push → ArgoCD syncs automatically

```bash
git add quickstarts/fusion-developerhub/fusion-ai-discovery/clusters/<cluster-id>/
git commit -m "feat: add <cluster-id> CAS"
git push origin main
# RHDH catalog picks it up within ~60s — no restart needed
```
