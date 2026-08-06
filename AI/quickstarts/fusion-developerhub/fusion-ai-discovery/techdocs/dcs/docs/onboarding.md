# Onboarding a New DCS Cluster

As a **developer**, you register a new DCS cluster in two steps using the self-service template wizard. No cluster access, no SA token, no YAML edits required.

> **Platform engineer?** See the [Platform Onboarding Guide](#platform-onboarding-reference) at the bottom of this page.

## Developer Onboarding — Template Wizard

### Step 1 — Open the wizard

In Developer Hub, click **Create** in the left navigation, then choose **"Add IBM Fusion DCS Cluster"**.

### Step 2 — Fill in two fields

| Field | Example | Notes |
|---|---|---|
| **Name** | `prod-east` | Lowercase, letters/numbers/hyphens. Used as the catalog entity name. |
| **OCP API URL** | `https://api.prod-east.example.com:6443` | Paste exactly from your `oc login` command. |

Click **Next → Create**.

### Step 3 — Done

All DCS endpoints are auto-derived and the component appears in the catalog immediately:

| Endpoint | Derived URL |
|---|---|
| DCS Console | `https://console-ibm-data-cataloging.apps.<domain>` |
| MCP HTTP | `https://dcs-mcp-route-ibm-data-cataloging.apps.<domain>/mcp/http` |
| MCP SSE | `https://dcs-mcp-route-ibm-data-cataloging.apps.<domain>/mcp` |

> The entity is stored in Developer Hub's catalog DB. To make it permanent across RHDH reinstalls, ask your platform engineer to commit it to Git (Option B in the main README).

---

## Platform Onboarding Reference

This section is for **platform engineers** who manage the RHDH instance and Git repo. Developers do not need to follow these steps.

### Prerequisites

- OpenShift cluster with IBM Fusion HCI 2.13+ deployed
- DCS installed and running in `ibm-data-cataloging` namespace
- Admin access to the Git repo (this repository)

### Step 1 — Apply RBAC on the Fusion cluster (K8s plugin only)

Skip this step if K8s plugin tab is not needed for this cluster (proxy-only access is zero-config).

```bash
# Run against the target Fusion cluster, not the RHDH cluster
oc login --server=https://api.<cluster-id>.example.com:6443

# Apply SA + ClusterRole + ClusterRoleBinding
oc apply -n ibm-data-cataloging -f k8s/sa-rbac.yaml
oc apply -f k8s/sa-rbac.yaml   # ClusterRole + DCS binding

# Mint a 1-year token
TOKEN=$(oc create token rhdh-fusion-reader -n ibm-data-cataloging --duration=8760h)
```

### Step 2 — Store SA token in the RHDH namespace

```bash
oc create secret generic fusion-<cluster-id>-sa-token \
  --from-literal=FUSION_<CLUSTER_ID>_SA_TOKEN="${TOKEN}" \
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

### Step 5 — Add proxy entries to app-config-fusion-services.yaml

```yaml
/fusion-<cluster-id>-dcs:
  target: https://console-ibm-data-cataloging.apps.<cluster-id>.example.com
  changeOrigin: true
  secure: false
  allowedHeaders: [Authorization, Content-Type, Accept, x-auth-token]
  pathRewrite:
    '^/api/proxy/fusion-<cluster-id>-dcs': ''

/fusion-<cluster-id>-dcs-mcp:
  target: https://dcs-mcp-route-ibm-data-cataloging.apps.<cluster-id>.example.com
  changeOrigin: true
  secure: false
  allowedHeaders: [Content-Type, Accept, Mcp-Session-Id]
  pathRewrite:
    '^/api/proxy/fusion-<cluster-id>-dcs-mcp': ''
```

### Step 6 — Commit and push → ArgoCD syncs automatically

```bash
git add quickstarts/fusion-developerhub/fusion-ai-discovery/clusters/<cluster-id>/
git commit -m "feat: add <cluster-id> DCS"
git push origin main
# RHDH catalog picks it up within ~60s — no restart needed
```
