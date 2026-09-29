# GPU Monitoring — Single-Cluster Grafana Dashboards

Grafana dashboards for NVIDIA GPU observability on OpenShift within a single cluster. Powered by DCGM metrics scraped via Prometheus and User Workload Monitoring (UWM).

For multi-cluster setups using Red Hat Advanced Cluster Management (ACM), see [`grafana-dashboards/multi-cluster/ACM/2.14/GPU/README-MULTI-CLUSTER-ACM.md`](../../multi-cluster/ACM/2.14/GPU/README-MULTI-CLUSTER-ACM.md).

---

## Architecture

```
GPU Node (NVIDIA DCGM Exporter)
        │  scraped every 30s
        ▼
OpenShift User Workload Monitoring (Thanos Querier)
        │
        ▼
Grafana
├── GPU Cluster Overview  (gpu-grafana-cluster-overview.json)
└── GPU SRE Deep Dive     (gpu-grafana-sre-dashboard.json)
```

---

## Dashboards

### 1. GPU Cluster Overview
High-level health summaries, predictive failure risk, workload attribution, and time-series trends.

**File:** `gpu-grafana-cluster-overview.json`  
**Dashboard UID:** `gpu-cluster-overview-v8`

![GPU Cluster Overview — Health Summary](screenshots/gpu-cluster-overview-health.png)
![GPU Cluster Overview — Trends](screenshots/gpu-cluster-overview-trends.png)

---

### 2. GPU SRE Deep Dive
Per-GPU forensic telemetry: power instability, thermal throttle, Tensor/GR engine activity, VRAM, ECC row remapping, and PCIe replay counters.

**File:** `gpu-grafana-sre-dashboard.json`  
**Dashboard UID:** `gpu-sre-dashboard-v5`

![GPU SRE Deep Dive — VRAM](screenshots/gpu-sre-vram-utilisation.png)
![GPU SRE Deep Dive — Power & Memory](screenshots/gpu-sre-power-memory.png)
![GPU SRE Deep Dive — ECC & PCIe](screenshots/gpu-sre-ecc-pcie.png)
![GPU SRE Deep Dive — Predictive](screenshots/gpu-sre-predictive.png)

---

## Prerequisites

1. **NVIDIA GPU Operator** installed with `nvidia-dcgm-exporter` pods `Running`:
   ```bash
   oc get pods -n nvidia-gpu-operator
   ```

2. **User Workload Monitoring** enabled:
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

3. **Grafana** instance accessible with a Prometheus data source pointed at the Thanos Querier:
   - URL: `https://thanos-querier.openshift-monitoring.svc.cluster.local:9091`

---

## Setup

### Import via Grafana UI

1. Go to **Dashboards → New → Import**.
2. Upload `gpu-grafana-cluster-overview.json` and `gpu-grafana-sre-dashboard.json`.
3. Map `${datasource}` to your Prometheus/Thanos data source and click **Import**.

---

## Dashboard Variables

| Variable | Description |
|---|---|
| `datasource` | Prometheus / Thanos Querier data source |
| `hostname` | GPU worker node hostname |
| `UUID` | GPU UUID on the selected host |
| `ocp_console` | OpenShift Web Console base URL for deep links |

To set `ocp_console`: **Dashboard Settings → Variables → `ocp_console`** → set your cluster URL → **Save**.

---

## Reference

- [NVIDIA GPU Operator on OpenShift](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/openshift/contents.html)
- [NVIDIA DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
- [OpenShift User Workload Monitoring](https://docs.openshift.com/container-platform/latest/monitoring/enabling-monitoring-for-user-defined-projects.html)
