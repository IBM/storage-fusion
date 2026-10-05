# GPU Monitoring — Single-Cluster Grafana Dashboards

Grafana dashboards for NVIDIA GPU observability on OpenShift and IBM Storage Fusion within a single cluster. Powered by standard NVIDIA DCGM metrics scraped via Prometheus and User Workload Monitoring (UWM).

For multi-cluster setups using Red Hat Advanced Cluster Management (ACM), refer to [README-MULTI-CLUSTER-ACM.md](README-MULTI-CLUSTER-ACM.md).

---

## Architecture Overview

```
GPU Node (NVIDIA DCGM Exporter)
        │
        │ Scraped every 30s
        ▼
OpenShift User Workload Monitoring (UWM / Thanos Querier)
Namespace: openshift-user-workload-monitoring / openshift-monitoring
        │
        ▼
Grafana (Local OpenShift Instance)
        ├── GPU Cluster Overview (gpu-cluster-overview-cr.yaml / .json)
        └── GPU SRE Deep Dive (gpu-sre-deep-dive-cr.yaml / .json)
```

---

## Dashboards & Visuals

### 1. GPU Cluster Overview
Provides high-level health summaries, predictive failure risk, active alerts, workload attribution (blast radius), and time-series trends across all GPU nodes in the cluster.

**Files:** `gpu-cluster-overview-cr.yaml` (Grafana Operator) / `gpu-grafana-cluster-overview.json` (UI Import)  
**Dashboard UID:** `gpu-cluster-overview-v8`

#### Fleet Health & Alert Summary
![GPU Cluster Overview — Fleet Health & Alert Summary](screenshots/gpu-cluster-overview-health.png)

#### Fleet Time-Series Trends & Workload Impact
![GPU Cluster Overview — Fleet Time-Series Trends & Workload Impact](screenshots/gpu-cluster-overview-trends.png)

---

### 2. GPU SRE Deep Dive
Provides granular per-GPU forensic telemetry: power instability (15-min rolling standard deviation), thermal throttle events, Tensor/GR engine activity, VRAM utilization, ECC memory row remapping, and PCIe replay counters.

**Files:** `gpu-sre-deep-dive-cr.yaml` (Grafana Operator) / `gpu-grafana-sre-dashboard.json` (UI Import)  
**Dashboard UID:** `gpu-sre-dashboard-v5`

#### GPU Utilisation & VRAM Telemetry
![GPU SRE Deep Dive — GPU Utilisation & VRAM](screenshots/gpu-sre-vram-utilisation.png)

#### Power, Compute & Memory Telemetry
![GPU SRE Deep Dive — Power & Memory](screenshots/gpu-sre-power-memory.png)

#### PCIe Bus, ECC Memory Health & Platform Status
![GPU SRE Deep Dive — ECC & PCIe](screenshots/gpu-sre-ecc-pcie.png)

#### Predictive Analysis & Composite Health
![GPU SRE Deep Dive — Predictive Analysis & Composite Health](screenshots/gpu-sre-predictive.png)

---

## Prerequisites

Before deploying the dashboards, ensure the following components are configured:

### 1. NVIDIA GPU Operator & DCGM Exporter
The **NVIDIA GPU Operator** (e.g., `gpu-operator-certified` v26.7.1+) must be installed on the cluster to manage NVIDIA drivers, device plugins, and the DCGM Exporter.

For installation and configuration instructions, refer to:
- [NVIDIA GPU Operator on Red Hat OpenShift Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/openshift/contents.html)
- [NVIDIA DCGM Exporter Documentation](https://github.com/NVIDIA/dcgm-exporter)

Verify operator and DCGM Exporter status on the cluster:
```bash
# Check GPU Operator CSV installation
oc get csv -n nvidia-gpu-operator -l operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator

# Check GPU Operator pods and DCGM Exporter daemons
oc get pods -n nvidia-gpu-operator
```
*(All pods including `nvidia-dcgm-exporter` must be in `Running` status.)*

### 2. OpenShift User Workload Monitoring (UWM)
User Workload Monitoring must be enabled to allow Prometheus to scrape DCGM exporter metrics.

Verify:
```bash
oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml | grep enableUserWorkload
```

Enable if not present:
```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF
```

### 3. Grafana Instance
Ensure either:
- **Grafana Operator** is installed with an active `Grafana` CR instance (recommended for CR deployment), OR
- A standalone Grafana instance is accessible (for JSON manual import).

---

## Step-by-Step Setup Guide

### Step 1: Deploy Dashboards

Choose **Option A** (Grafana Operator CR) or **Option B** (Manual JSON Import).

#### Option A: Deploy via Grafana Operator CR (Recommended)

1. **Verify Grafana instance selector label:**
   ```bash
   oc get grafana -n grafana -o jsonpath='{.items[0].metadata.labels}'
   ```
   *(Ensure `dashboards: grafana-a` matches `spec.instanceSelector.matchLabels` in the CR files).*

2. **Apply Custom Resources:**
   ```bash
   oc apply -f gpu-cluster-overview-cr.yaml
   oc apply -f gpu-sre-deep-dive-cr.yaml
   ```

3. **Verify dashboard creation:**
   ```bash
   oc get grafanadashboard -n grafana
   ```

#### Option B: Deploy via Grafana API (JSON — no Grafana Operator needed)

Use this method when you want to push the JSON dashboards directly to a running Grafana instance via its REST API. This is the **recommended path** when deploying to an existing Grafana and you do not want to manage Kubernetes CRs.

> **Before you start:** Grafana must have a working **Prometheus datasource** with UID `prometheus` pointing at Thanos Querier. If your Grafana shows empty panels after import, follow **[Troubleshooting: Empty Panels — No Datasource](#troubleshooting-empty-panels--no-prometheus-datasource)** below first.

1. **Get the Grafana route:**
   ```bash
   oc get route -n grafana
   # Example output:
   # grafana-a-route   grafana-a-route-grafana.apps.<cluster>.ibm.com
   ```

2. **Verify Grafana is reachable:**
   ```bash
   curl -sk https://grafana-a-route-grafana.apps.<cluster>.ibm.com/api/health
   # Expected: {"database":"ok","version":"12.x.x", ...}
   ```

3. **Push both JSON dashboards via the API** (replace `<GRAFANA_URL>`, `<USER>`, `<PASSWORD>`):
   ```bash
   for JSON in gpu-grafana-cluster-overview.json gpu-grafana-sre-dashboard.json; do
     curl -sk -u <USER>:<PASSWORD> \
       -X POST \
       -H "Content-Type: application/json" \
       -d "{\"dashboard\": $(cat ${JSON}), \"overwrite\": true, \"folderId\": 0}" \
       https://<GRAFANA_URL>/api/dashboards/db
     echo ""
   done
   ```
   Successful output looks like:
   ```json
   {"status":"success","uid":"gpu-cluster-overview-v8","url":"/d/gpu-cluster-overview-v8/gpu-cluster-overview","version":1}
   {"status":"success","uid":"gpu-sre-dashboard-v5","url":"/d/gpu-sre-dashboard-v5/gpu-sre-deep-dive","version":1}
   ```

4. **Verify dashboards appear in Grafana:**
   ```bash
   curl -sk -u <USER>:<PASSWORD> \
     "https://<GRAFANA_URL>/api/search?type=dash-db" | python3 -m json.tool
   ```

---

## Troubleshooting: Empty Panels — No Prometheus Datasource

If dashboards are applied but **all panels show "No data"**, the Grafana instance has no Prometheus datasource configured. Both JSON dashboards reference datasource UID `prometheus` — if that UID does not exist in Grafana, every panel returns empty.

Follow these steps to create the datasource from scratch using a ServiceAccount token.

### Step 1 — Check datasources in Grafana

```bash
curl -sk -u <USER>:<PASSWORD> https://<GRAFANA_URL>/api/datasources
# If output is [] — no datasources configured. Proceed below.
```

### Step 2 — Identify the Grafana ServiceAccount

```bash
oc get sa -n grafana
# Look for the SA tied to your Grafana instance, e.g. grafana-a-sa
```

### Step 3 — Grant `cluster-monitoring-view` to the ServiceAccount

This RBAC role allows the SA token to query Thanos Querier in `openshift-monitoring`:

```bash
oc adm policy add-cluster-role-to-user cluster-monitoring-view \
  -z grafana-a-sa -n grafana
```

Verify:
```bash
oc get clusterrolebinding -o name | grep grafana-a
```

### Step 4 — Create a long-lived Bearer token for the ServiceAccount

```bash
SA_TOKEN=$(oc create token grafana-a-sa -n grafana --duration=8760h)
echo $SA_TOKEN   # Save this — you will use it in the next step
```

> **Note:** `--duration=8760h` = 1 year. Adjust to your security policy. The token is scoped only to `cluster-monitoring-view` — read-only access to Prometheus metrics.

### Step 5 — Create the Prometheus datasource in Grafana

```bash
curl -sk -u <USER>:<PASSWORD> \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"prometheus\",
    \"uid\": \"prometheus\",
    \"type\": \"prometheus\",
    \"access\": \"proxy\",
    \"url\": \"https://thanos-querier.openshift-monitoring.svc.cluster.local:9091\",
    \"isDefault\": true,
    \"jsonData\": {
      \"httpHeaderName1\": \"Authorization\",
      \"timeInterval\": \"30s\",
      \"tlsSkipVerify\": true
    },
    \"secureJsonData\": {
      \"httpHeaderValue1\": \"Bearer ${SA_TOKEN}\"
    }
  }" \
  https://<GRAFANA_URL>/api/datasources
```

Key fields explained:

| Field | Value | Why |
|-------|-------|-----|
| `uid` | `prometheus` | **Must match exactly** — both JSON dashboards hard-reference this UID |
| `url` | `https://thanos-querier.openshift-monitoring.svc.cluster.local:9091` | Thanos Querier federates all namespaces including `nvidia-gpu-operator` |
| `httpHeaderName1` | `Authorization` | Passes the Bearer token as an HTTP header on every query |
| `tlsSkipVerify` | `true` | Thanos Querier uses a self-signed cert inside the cluster |
| `timeInterval` | `30s` | Matches DCGM scrape interval to avoid gap artifacts in panels |

### Step 6 — Test the datasource

```bash
curl -sk -u <USER>:<PASSWORD> \
  -X POST \
  https://<GRAFANA_URL>/api/datasources/uid/prometheus/health
# Expected: {"status":"OK","message":"Successfully queried the Prometheus API."}
```

### Step 7 — Verify GPU metrics are flowing

```bash
curl -sk -u <USER>:<PASSWORD> \
  -G --data-urlencode 'query=DCGM_FI_DEV_GPU_UTIL' \
  "https://<GRAFANA_URL>/api/datasources/proxy/uid/prometheus/api/v1/query" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('data',{}).get('result',[])
print(f'GPU metric series found: {len(results)}')
for r in results[:3]:
    m = r['metric']
    print(f\"  node={m.get('Hostname','?')}  gpu={m.get('gpu','?')}  model={m.get('modelName','?')}  val={r['value'][1]}\")
"
```

If `GPU metric series found: 0` — DCGM Exporter is not scraping. Check:
```bash
oc get pods -n nvidia-gpu-operator | grep dcgm
oc get servicemonitor -n nvidia-gpu-operator
```

### Step 8 — Re-apply dashboards (picks up the new datasource)

```bash
for JSON in gpu-grafana-cluster-overview.json gpu-grafana-sre-dashboard.json; do
  curl -sk -u <USER>:<PASSWORD> \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"dashboard\": $(cat ${JSON}), \"overwrite\": true, \"folderId\": 0}" \
    https://<GRAFANA_URL>/api/dashboards/db
  echo ""
done
```

Panels should now show live data. Refresh the dashboard in your browser.

---

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| All panels empty after import | No `prometheus` datasource with UID `prometheus` | Follow steps above |
| Datasource health returns 401 | SA token expired or wrong permissions | Re-run Steps 3–5 with a new token |
| Datasource health returns 403 | SA missing `cluster-monitoring-view` role | Re-run Step 3 |
| `GPU metric series found: 0` | DCGM Exporter pods not running / not scraped | Check `nvidia-gpu-operator` namespace pods |
| Datasource health returns `connection refused` | Wrong Thanos URL or port | Use `9091` not `9090`; confirm `thanos-querier` service exists in `openshift-monitoring` |
| Panels show data for some nodes only | Some GPU nodes have DCGM pods in `Init` state (driver not loaded) | Check `nvidia-driver-daemonset` pods — ImagePullBackOff = missing driver image |

### Step 2: Configure OpenShift Console Deep-Links (Optional)

Both dashboards support direct links (↗) to OpenShift node and pod console pages:

- **Via CR File:** Update `"query"` and `"current.value"` for the `ocp_console` variable in `gpu-cluster-overview-cr.yaml` and `gpu-sre-deep-dive-cr.yaml` with your cluster URL:
  ```json
  "query": "https://console-openshift-console.apps.<your-cluster-domain>"
  ```
- **Via Grafana UI:** Dashboard **Settings** → **Variables** → `ocp_console` → Set value → **Save dashboard**.

---

## Dashboard Variable Reference

| Variable | Type | Description |
|---|---|---|
| `datasource` | Datasource | Prometheus / Thanos Querier datasource. |
| `hostname` | Query | Filters by GPU worker node hostname (`label_values(DCGM_FI_DEV_GPU_TEMP, hostname)`). |
| `UUID` | Query | Filters by specific GPU UUID on the selected host (`label_values(DCGM_FI_DEV_GPU_TEMP{hostname=~"$hostname"}, UUID)`). |
| `ocp_console` | Constant | Base URL of the OpenShift Web Console for deep links. |

---

## Key Metrics Reference

| Metric | Description |
|---|---|
| `DCGM_FI_DEV_GPU_UTIL` | GPU compute utilization percentage (0–100%). |
| `DCGM_FI_DEV_GPU_TEMP` | GPU core die temperature in Celsius (°C). |
| `DCGM_FI_DEV_POWER_USAGE` | Instantaneous power consumption in Watts (W). |
| `DCGM_FI_DEV_FB_USED` / `DCGM_FI_DEV_FB_FREE` | VRAM Framebuffer memory used / free in MiB. |
| `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | Double-bit ECC uncorrectable errors (volatile). |
| `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL` | Single-bit ECC correctable errors (volatile). |
| `DCGM_FI_DEV_PCIE_REPLAY_COUNTER` | PCIe replay counter for tracking bus errors and degraded links. |
| `DCGM_FI_PROF_GR_ENGINE_ACTIVE` | Graphics / compute engine active ratio (0–1). |
| `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | Tensor Core pipeline utilization ratio (0–1). |
| `gpu:health_score:composite` | Composite health score (0–100) computed from temperature, throttling, and ECC events. |
| `gpu:failure_probability:24h` | 24-hour predictive failure risk score (0–100%). |

---

## Reference Documentation
- [NVIDIA GPU Operator on Red Hat OpenShift](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/openshift/contents.html)
- [NVIDIA DCGM Metrics & Architecture Documentation](https://docs.nvidia.com/datacenter/dcgm/latest/dcgm-user-guide/feature-overview.html)
- [OpenShift User Workload Monitoring Documentation](https://docs.openshift.com/container-platform/latest/monitoring/enabling-monitoring-for-user-defined-projects.html)
- [Grafana Operator on OpenShift](https://grafana-operator.github.io/grafana-operator/)
- [IBM Storage Fusion Documentation](https://www.ibm.com/docs/en/storage-fusion)
