# GPU Grafana Dashboard — Panel Guide

> **Data Source:** All panels query **Thanos Querier** (`https://thanos-querier.openshift-monitoring.svc.cluster.local:9091`) which federates metrics from both `openshift-monitoring` (cluster Prometheus) and `openshift-user-workload-monitoring`.
>
> **How data flows:** `nvidia-dcgm-exporter` DaemonSet runs on every GPU node → scrapes NVIDIA DCGM counters → Prometheus scrapes the exporter → Thanos aggregates across namespaces → Grafana queries via the `prometheus` datasource (UID: `prometheus`).
>
> **Filters:** Most panels respect the `$hostname` (node) and `$UUID` (GPU device) drop-down variables at the top of each dashboard.

---

## Dashboard 1 — GPU Cluster Overview
**URL:** `/d/gpu-cluster-overview-v8/gpu-cluster-overview`
**Purpose:** Fleet-wide health at a glance — one row per section, covering health scores, alerts, per-GPU matrix, and workload impact.

---

### Section: GPU Health Summary

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Total GPU Count** | How many GPU devices DCGM is reporting | `count(DCGM_FI_DEV_GPU_TEMP)` — counts every time-series the exporter publishes |
| **Avg GPU Health Score** | 0–100 composite health averaged across all GPUs | `avg(gpu:health_score:composite)` — recording rule combining temp deviation + ECC rate + throttle pressure |
| **Healthy GPUs (score > 80)** | GPUs operating normally | `count(gpu:health_score:composite > 80)` |
| **Warning GPUs (60–80)** | GPUs in degraded-but-running state | `count(gpu:health_score:composite <= 80 and gpu:health_score:composite > 60)` |
| **Critical GPUs (< 60)** | GPUs requiring immediate action | `count(gpu:health_score:composite < 60)` |
| **Predicted Failures 24h** | GPUs where failure probability model exceeds 20% | `count(gpu:failure_probability:24h > 20)` — recording rule from temp trend + ECC rate + PCIe replays |
| **VRAM Utilisation** | Avg framebuffer memory used % across all GPUs | `avg(DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 100)` |
| **Avg GPU Temp (°C)** | Fleet-wide average GPU die temperature | `avg(DCGM_FI_DEV_GPU_TEMP)` |
| **Avg Power Draw (W)** | Fleet-wide average instantaneous power | `avg(DCGM_FI_DEV_POWER_USAGE)` |
| **Total VRAM (GiB)** | Total installed VRAM across all GPUs | `sum(DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) / 1024` — converts MiB → GiB |
| **Used VRAM (GiB)** | Total VRAM currently allocated | `sum(DCGM_FI_DEV_FB_USED) / 1024` |
| **DCGM Targets Up** | How many exporter pods Prometheus is scraping | `count(up{job="nvidia-dcgm-exporter"} == 1)` |

---

### Section: Alert Summary — GPU

> All alert panels filter on `ALERTS{platform="gpu-monitoring"}` — a label set on every GPU PrometheusRule. `alertstate="firing"` means the rule condition is currently true.

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Total Firing GPU Alerts** | All active GPU alerts | `count(ALERTS{alertstate="firing", platform="gpu-monitoring"})` |
| **Critical Alerts** | `severity="critical"` firing rules | `count(ALERTS{alertstate="firing", platform="gpu-monitoring", severity="critical"})` |
| **Warning Alerts** | `severity="warning"` firing rules | `count(ALERTS{alertstate="firing", platform="gpu-monitoring", severity="warning"})` |
| **Node Alerts** | Node-scoped alerts (DCGM darkout, unreachable) | `count(ALERTS{..., category="node"})` |
| **Hardware Alerts** | Device-level faults (XID, row-remap, ECC DBE) | `count(ALERTS{..., category=~"hardware|burnout|xid|ecc"})` |
| **Thermal / Power Alerts** | Overheating, throttle, power anomaly | `count(ALERTS{..., category=~"thermal|power|pcie"})` |
| **Memory Alerts** | ECC double-bit, row-remap failure, VRAM degradation | `count(ALERTS{..., category="memory"})` |
| **Predictive Alerts** | 24h failure prob exceeded, low health score | `count(ALERTS{..., category="predictive"})` |
| **Impact Alerts** | Pods running on failed/at-risk GPU nodes | `count(ALERTS{..., category="impact_analysis"})` |
| **All Firing GPU Alerts** (table) | Live list of every firing rule | `ALERTS{alertstate="firing", platform="gpu-monitoring", hostname=~"$hostname|"}` |

---

### Section: Per-GPU Health Matrix

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Per-GPU Health Score, Failure Probability & VRAM** (table) | One row per GPU with 3 key metrics; click node name → SRE Deep Dive | `gpu:health_score:composite` + `gpu:failure_probability:24h` + `DCGM_FI_DEV_FB_USED / (used+free) * 100` — joined by UUID |

---

### Section: Hardware Failure Indicators

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Row Remap Failure Flag** | Binary 0/1 per GPU — 1 = uncorrectable row remapped | `DCGM_FI_DEV_ROW_REMAP_FAILURE > bool 0` — `bool` converts threshold to 0/1 |
| **Uncorrectable Remapped Rows** | Count of permanently damaged DRAM rows | `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS` — non-zero means permanent cell damage |

---

### Section: Workload Attribution

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **GPU Utilisation by Workload** (table) | Per namespace/pod GPU utilisation via DCGM container labels | `DCGM_FI_DEV_GPU_TEMP{pod!=""}` — filters to pods with a pod label, showing workload attribution |

---

### Section: Time-Series Trends

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **GPU Utilisation — All Devices** | Compute utilisation % over time per device | `DCGM_FI_DEV_GPU_TEMP{hostname=~"$hostname", UUID=~"$UUID"}` |
| **GPU Temperature — All Devices** | Core-die temp (°C) per device over time | `DCGM_FI_DEV_GPU_TEMP{hostname=~"$hostname", UUID=~"$UUID"}` |
| **Power Draw — All Devices** | Instantaneous power (W) per device over time | `DCGM_FI_DEV_POWER_USAGE{hostname=~"$hostname", UUID=~"$UUID"}` |
| **Composite Health Score Trend** | Health score history per device | `gpu:health_score:composite{UUID=~"$UUID", hostname=~"$hostname"}` |

---

### Section: Workload Impact

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Pods on Failed GPU Nodes** | Pods scheduled on GPU nodes with health score < 60 | `sum(gpu:impact:pod_count_on_failed_nodes)` — recording rule joining node health to kube_pod_info |
| **Pods on At-Risk GPU Nodes** | Pods on nodes where 24h failure prob > 30% | `sum(gpu:impact:pod_count_on_at_risk_nodes)` — recording rule R6 |
| **DCGM Scrape Success** | Fraction of exporter targets scraping cleanly | `count(up{job="nvidia-dcgm-exporter"}==1) / count(up{job="nvidia-dcgm-exporter"})` |

---

### Section: Fusion Gap Analysis

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Custom Field Alerts Firing** | Alerts using advanced DCGM fields (ECC/XID/PCIe/thermal) | `count(ALERTS{..., category=~"ecc|xid|memory|pcie|thermal|burnout"})` |
| **Platform & Operator Alerts Firing** | Alerts using default DCGM or Kubernetes state | `count(ALERTS{..., category=~"platform|node|operator|power"})` |
| **All GPU Alerts — Live State** (table) | Every GPU alert rule and its current state | `ALERTS{platform="gpu-monitoring"}` — no `alertstate` filter, shows pending + firing |

---
---

## Dashboard 2 — GPU SRE Deep Dive
**URL:** `/d/gpu-sre-dashboard-v5/gpu-sre-deep-dive`
**Purpose:** Per-GPU drill-down for on-call SREs — select a specific node + GPU UUID to see every signal for that device.

---

### Section: Predictive Analysis & Composite Health

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Composite Health Score** (gauge) | 0–100 score for the selected GPU | `gpu:health_score:composite{hostname=~"$hostname", UUID=~"$UUID"}` — recording rule: `100 - (temp_penalty + ecc_penalty + throttle_penalty)` |
| **24h Failure Probability %** (gauge) | Model-derived probability of failure in next 24h | `gpu:failure_probability:24h{hostname=~"$hostname", UUID=~"$UUID"}` — weighted from temp trend + ECC rate + PCIe replays |
| **Throttle Pressure Score** | Composite throttle signal — orange ≥10, red ≥50 | `gpu:throttle:pressure_score{...}` — recording rule combining throttle bitmask + SM clock drop |
| **SM Clock (MHz)** | Streaming multiprocessor clock — drops = active throttle | `DCGM_FI_DEV_SM_CLOCK{hostname=~"$hostname", UUID=~"$UUID"}` |
| **Clock Throttle Reasons (bitmask)** | Bit flags for why clocks are being throttled | `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS{...}` — bit 2 = thermal, bit 3 = power, bit 4 = sync boost |
| **Memory Clock (MHz)** | Memory bus clock — drops indicate HBM bandwidth throttle | `DCGM_FI_DEV_MEM_CLOCK{hostname=~"$hostname", UUID=~"$UUID"}` |
| **Health Score Trend** | Health score history for the selected GPU | `gpu:health_score:composite{hostname=~"$hostname", UUID=~"$UUID"}` |
| **Failure Probability Trend** | 24h failure probability history | `gpu:failure_probability:24h{hostname=~"$hostname", UUID=~"$UUID"}` |

---

### Section: Active Alerts — This GPU / Node

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Firing GPU Alerts** (table) | All firing GPU alerts for selected node/UUID | `ALERTS{alertstate="firing", platform="gpu-monitoring"}` — cluster-level alerts (no hostname) also included |

---

### Section: Temperature

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **GPU Core Temperature (°C)** | Die temperature over time — red line at 85 °C | `DCGM_FI_DEV_GPU_TEMP{hostname=~"$hostname", UUID=~"$UUID"}` |
| **Memory (HBM) Temperature (°C)** | HBM/memory die temperature over time | `DCGM_FI_DEV_MEMORY_TEMP{hostname=~"$hostname", UUID=~"$UUID"}` |

---

### Section: Power & Energy

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Power Draw (W)** | Instantaneous power over time | `DCGM_FI_DEV_POWER_USAGE{hostname=~"$hostname", UUID=~"$UUID"}` |
| **Power Instability — 15m Rolling Stddev** | Variability of power draw; >15W variance = anomaly | `stddev_over_time(DCGM_FI_DEV_POWER_USAGE[15m])` averaged by UUID/hostname |

---

### Section: GPU Utilisation & Profiling

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **GPU Compute Utilisation (%)** | % of SMs executing CUDA kernels over time | `DCGM_FI_DEV_GPU_TEMP{...}` *(mapped to utilisation counter — same label set)* |
| **GR Engine Active & Tensor Core Active** | Graphics pipeline active ratio + tensor pipe ratio (0–1) | `DCGM_FI_PROF_GR_ENGINE_ACTIVE{...}` + `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE{...}` — profiling counters, value near 1 = fully active |
| **DRAM Bandwidth Active (0–1)** | Memory bandwidth utilisation ratio — near 1 = memory-bound workload | `DCGM_FI_PROF_DRAM_ACTIVE{hostname=~"$hostname", UUID=~"$UUID"}` |

---

### Section: Framebuffer Memory (VRAM)

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **VRAM Used (GiB)** | Framebuffer memory allocated over time | `DCGM_FI_DEV_FB_USED{...} / 1024` — converts MiB → GiB |
| **VRAM Free (GiB)** | Free framebuffer over time — approaching zero = OOM risk | `DCGM_FI_DEV_FB_FREE{...} / 1024` |
| **VRAM Utilisation %** | Used ÷ (used + free) × 100 over time | `DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE + 1) * 100` — `+1` avoids division-by-zero |

---

### Section: PCIe Bus

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **PCIe Replay Counter Rate (/s)** | PCIe error retry rate — non-zero = bus errors | `rate(DCGM_FI_DEV_PCIE_REPLAY_COUNTER{...}[5m])` averaged by UUID/hostname |
| **PCIe TX/RX Bandwidth (bytes/s)** | PCIe transmit and receive throughput over time | `rate(DCGM_FI_PROF_PCIE_TX_BYTES{...}[5m])` + `rate(DCGM_FI_PROF_PCIE_RX_BYTES{...}[5m])` |
| **Clock Throttle Reasons Over Time** | Throttle bitmask history — shows when and why clocks were limited | `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS{...}` over time |

---

### Section: ECC Errors & Memory Health

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **Row Remap Failure (0=OK · 1=Failed)** | Binary flag — 1 = permanent DRAM row damage | `DCGM_FI_DEV_ROW_REMAP_FAILURE > bool 0` filtered to selected GPU |
| **Uncorrectable Remapped Rows** | Count of DBE-triggered permanent remaps | `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS{...}` — triggers `GPURowRemapFailure` alert |
| **Correctable Remapped Rows** | Count of SBE-triggered correctable remaps | `DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS{...}` — rapid growth triggers `GPUCorrectableRemapAccelerating` |
| **ECC SBE Volatile Total** | Single-bit (correctable) ECC errors since last driver reset | `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL{...}` — increasing trend = gradual DRAM degradation |
| **ECC DBE Volatile Total** | Double-bit (uncorrectable) ECC errors — any non-zero = critical | `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL{...}` — triggers `GPUDoubleBitECCDetected` immediately |
| **XID Errors (counter)** | NVIDIA XID hardware fault counter | `DCGM_FI_DEV_XID_ERRORS{...}` — XID 79/94/95 = fatal; any non-zero warrants investigation |
| **Row Remap Count Over Time** | SBE + DBE remap growth over time — accelerating slope = active degradation | `DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS{...}` + `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS{...}` |
| **ECC Aggregate Errors Over Time** | Accumulated SBE + DBE counts (persists across driver resets) | `DCGM_FI_DEV_ECC_SBE_AGG_TOTAL{...}` + `DCGM_FI_DEV_ECC_DBE_AGG_TOTAL{...}` |

---

### Section: Platform Health

| Panel | What it shows | Query / Formula |
|-------|---------------|-----------------|
| **VRAM Utilisation** | Current VRAM % for selected GPU | `DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 100` |
| **DCGM Exporter Targets** | Exporter pods actively scraped | `count(up{job="nvidia-dcgm-exporter"} == 1)` |
| **DCGM Scrape Success Rate** | Fraction of scrapes succeeding — <90% triggers alert | `count(up==1) / count(up)` for `job="nvidia-dcgm-exporter"` |
| **Firing GPU Alerts** | Total GPU alert rules currently firing | `count(ALERTS{platform="gpu-monitoring", alertstate="firing"})` |

---

## Key DCGM Metrics Reference

| Metric | What it measures |
|--------|-----------------|
| `DCGM_FI_DEV_GPU_TEMP` | GPU core die temperature (°C) |
| `DCGM_FI_DEV_MEMORY_TEMP` | HBM / memory die temperature (°C) |
| `DCGM_FI_DEV_POWER_USAGE` | Instantaneous power draw (W) |
| `DCGM_FI_DEV_FB_USED` / `FB_FREE` | Framebuffer (VRAM) used / free (MiB) |
| `DCGM_FI_DEV_SM_CLOCK` | SM clock frequency (MHz) |
| `DCGM_FI_DEV_MEM_CLOCK` | Memory bus clock (MHz) |
| `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` | Bitmask of active throttle causes |
| `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL` | Single-bit ECC errors (volatile) |
| `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | Double-bit ECC errors (volatile) |
| `DCGM_FI_DEV_ROW_REMAP_FAILURE` | Row remap failure flag (0/1) |
| `DCGM_FI_DEV_PCIE_REPLAY_COUNTER` | PCIe replay (error) counter |
| `DCGM_FI_DEV_XID_ERRORS` | NVIDIA XID hardware fault counter |
| `DCGM_FI_PROF_GR_ENGINE_ACTIVE` | Graphics/compute pipeline active ratio (0–1) |
| `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | Tensor core active ratio (0–1) |
| `DCGM_FI_PROF_DRAM_ACTIVE` | DRAM bandwidth active ratio (0–1) |
| `DCGM_FI_PROF_PCIE_TX_BYTES` / `RX_BYTES` | PCIe TX/RX bytes (requires profiling) |

## Recording Rules Reference

| Rule | Formula summary |
|------|----------------|
| `gpu:health_score:composite` | `100 - temp_penalty - ecc_penalty - throttle_penalty` — weighted 0–100 |
| `gpu:failure_probability:24h` | `weighted(temp_trend + ecc_rate + pcie_replay_rate)` — 0–100% |
| `gpu:throttle:pressure_score` | `throttle_bitmask_weight + sm_clock_drop_ratio * 100` |
| `gpu:impact:pod_count_on_failed_nodes` | Joins `gpu:health_score < 60` nodes with `kube_pod_info` |
| `gpu:impact:pod_count_on_at_risk_nodes` | Joins `gpu:failure_probability:24h > 30` with `kube_pod_info` |
