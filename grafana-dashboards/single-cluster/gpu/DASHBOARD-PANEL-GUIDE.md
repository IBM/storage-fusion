# GPU Grafana Dashboards — Panel Guide

> Generated from the dashboard JSON by the dashboard-advisor refactor. Every panel below was tested end to end; results are in [`PANEL-TEST-REPORT.md`](PANEL-TEST-REPORT.md).

**Data path:** `nvidia-dcgm-exporter` → Prometheus → Thanos Querier → Grafana datasource `prometheus` (UID `prometheus`).  
**Filters:** `$hostname` (node, label `Hostname`) and `$UUID` (GPU). Both default to *All*.  
**Labels:** DCGM exports the node as `Hostname`; the GPU's consumer pod is in `exported_pod` / `exported_namespace`.

## Design rules applied (dashboard-advisor method)

| Rule | How it shows up |
|---|---|
| Layers: status → exceptions → detail | Overview: health + alert tiles on top, exception tables next, trends last. SRE: score gauges first, raw telemetry below. |
| Valence only where there is an action | Every stat/gauge has threshold steps matching `gpu-rules.yaml`, or is explicitly *neutral* (counts, clocks). |
| Thresholds = alert rules | Panel colours flip at the same numbers as the alerts they link to (e.g. health 60 / 80, temperature 85 °C, predictive 70 %). |
| Exceptions only | Hardware-fault bar gauges list affected GPUs only and say *None — no GPU affected* when healthy. |
| No fake zeros | Metrics this exporter does not export show **Not collected**, never 0. |
| Drill-down | Valence tiles link to the owning alert rule or the SRE dashboard, keeping time range and variables. |
| No pie / donut / dual axis | Bar gauges, tables, timeseries and gauges only. |

---

## GPU Cluster Overview

**UID:** `gpu-cluster-overview-v8` · **Display type:** Monitoring / fleet · **Question:** Is every GPU healthy right now, and if not, which ones and which workloads are hit?

### GPU Health Summary

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 1 | **Total GPU Count** — Total number of NVIDIA GPUs detected across all nodes via DCGM Exporter. | stat | neutral (no action) | `count(DCGM_FI_DEV_GPU_TEMP{Hostname=~"$hostname"})` |
| 2 | **Avg GPU Health Score** — Composite health (0–100), average of selected GPUs. Red <60 = GPUHealthScoreCritical; orange 60–80 = GPUHealthScoreHigh; green ≥80. | gauge | red < 60, orange ≥ 60, green ≥ 80 | `avg(gpu:health_score:composite{UUID=~"$UUID"})` |
| 3 | **Healthy GPUs (score ≥ 80)** — GPUs with a composite health score above 80 — operating normally. | stat | neutral (no action) | `count(gpu:health_score:composite{UUID=~"$UUID"} >= 80) or (count(gpu:health_score:composite{UUID=~"$UUID"}) * 0)` |
| 4 | **Warning GPUs (60–79)** — GPUs in the warning band (60–80). Investigate temperature, ECC or clock throttle. | stat | green < 1, orange ≥ 1 | `count(gpu:health_score:composite{UUID=~"$UUID"} >= 60 < 80) or (count(gpu:health_score:composite{UUID=~"$UUID"}) * 0)` |
| 5 | **Critical GPUs (< 60)** — GPUs below health score 60 or with active predictive-failure alerts — require immediate attention. | stat | green < 1, red ≥ 1 | `count(gpu:health_score:composite{UUID=~"$UUID"} < 60) or (count(gpu:health_score:composite{UUID=~"$UUID"}) * 0)` |
| 6 | **Failure risk > 30% (24h)** — GPUs with >30% predicted 24h failure probability — the cut-off WorkloadsOnAtRiskGPUNodes uses. | stat | green < 1, orange ≥ 1 | `count(gpu:failure_probability:24h{UUID=~"$UUID"} > 30) or (count(gpu:health_score:composite{UUID=~"$UUID"}) * 0)` |
| 7 | **VRAM Utilisation** — Avg GPU framebuffer memory used as % of total. Orange ≥80%, red ≥95%. High VRAM pressure causes workload OOM kills. | stat | green < 80, orange ≥ 80, red ≥ 95 | `avg(DCGM_FI_DEV_FB_USED{Hostname=~"$hostname"} / (DCGM_FI_DEV_FB_USED{Hostname=~"$hostname"} + DCGM_FI_DEV_FB_FREE{Hostname=~"$hostname"}) * 100)` |
| 8 | **Avg GPU Temp (°C)** — Orange ≥85°C matches GPUHighTemperatureSustained (>85°C). Red ≥90°C is near hardware slowdown. | stat | green < 85, orange ≥ 85, red ≥ 90 | `avg(DCGM_FI_DEV_GPU_TEMP{Hostname=~"$hostname"})` |
| 12 | **DCGM Targets Up** — Number of DCGM Exporter targets currently being scraped successfully by Prometheus. | stat | red < 1, green ≥ 1 | `count(up{job="nvidia-dcgm-exporter"} == 1) or vector(0)` |

### Alert Summary — GPU

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 107 | **Total Firing GPU Alerts** — Total number of GPU alert rules currently in the Firing state. | stat | green < 1, orange ≥ 1, red ≥ 3 | `count(ALERTS{alertstate="firing",platform="gpu-monitoring"}) or vector(0)` |
| 13 | **Critical Alerts** — Alerts at Severity=Critical — require immediate action. | stat | green < 1, red ≥ 1 | `count(ALERTS{alertstate="firing",platform="gpu-monitoring",severity="critical"}) or vector(0)` |
| 14 | **Warning Alerts** — Alerts at Severity=Warning — should be investigated promptly. | stat | green < 1, orange ≥ 1 | `count(ALERTS{alertstate="firing",platform="gpu-monitoring",severity="warning"}) or vector(0)` |
| 15 | **Node Alerts** — Alerts scoped to a GPU worker node (e.g. node unreachable, DCGM darkout). | stat | green < 1, red ≥ 1 | `count(ALERTS{alertstate="firing",platform="gpu-monitoring",category="node"}) or vector(0)` |
| 16 | **Hardware Alerts** — Alerts scoped to a specific GPU device (e.g. row-remap failure, XID errors). | stat | green < 1, red ≥ 1 | `count(ALERTS{alertstate="firing",platform="gpu-monitoring",category=~"hardware\|burnout\|xid\|ecc"}) or vector(0)` |
| 17 | **Thermal / Power Alerts** — Thermal and power alerts: overheating, sustained throttling, power anomaly. | stat | green < 1, orange ≥ 1 | `count(ALERTS{alertstate="firing",platform="gpu-monitoring",category=~"thermal\|power\|pcie"}) or vector(0)` |
| 18 | **Memory Alerts** — Memory alerts: ECC double-bit errors, row-remap failures, VRAM degradation. | stat | green < 1, orange ≥ 1 | `count(ALERTS{alertstate="firing",platform="gpu-monitoring",category="memory"}) or vector(0)` |
| 19 | **Predictive Alerts** — Predictive alerts: 24 h failure probability exceeded, composite health score low. | stat | green < 1, orange ≥ 1 | `count(ALERTS{alertstate="firing",platform="gpu-monitoring",category="predictive"}) or vector(0)` |
| 20 | **Impact Alerts** — Workload-impact alerts: pods running on failed or at-risk GPU nodes. | stat | green < 1, red ≥ 1 | `count(ALERTS{alertstate="firing",platform="gpu-monitoring",category="impact_analysis"}) or vector(0)` |
| 21 | **All Firing GPU Alerts** — Live table of all firing GPU alerts with rule name, severity, and labels. | table | neutral (no action) | `ALERTS{alertstate="firing",platform="gpu-monitoring",Hostname=~"$hostname\|"} or ALERTS{alertstate="firing",platform="gpu-monitoring",category=~"ope...` |

### Per-GPU Health Matrix

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 22 | **Per-GPU Health Score, Failure Probability & VRAM** — Click any Node name (blue) to open the SRE Deep Dive dashboard scoped to that GPU. Sorted worst health first. | table | neutral (no action) | `gpu:health_score:composite * on(UUID) group_left(Hostname) (max by(UUID, Hostname) (DCGM_FI_DEV_GPU_TEMP{Hostname=~"$hostname"}) * 0 + 1)` |

### Hardware Failure Indicators

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 23 | **Row Remap FAILED — affected GPUs only** — Per-GPU row-remap failure flag. 1 = at least one uncorrectable row has been remapped — GPU may need replacement. | bargauge | green < 1, red ≥ 1 | `max by(Hostname, device, gpu) (DCGM_FI_DEV_ROW_REMAP_FAILURE{Hostname=~"$hostname",UUID=~"$UUID"} > 0)` |
| 24 | **Uncorrectable Remapped Rows — affected GPUs only** — Only GPUs with ≥1 uncorrectable remapped row (fires GPUDBERetiredPages, critical). Action: schedule GPU replacement. | bargauge | green < 1, red ≥ 1 | `max by(Hostname, device, gpu) (DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS{Hostname=~"$hostname",UUID=~"$UUID"} > 0)` |

### Workload Attribution — GPU Utilisation by Pod

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 25 | **GPU Utilisation by Workload — Namespace · Pod · Device** — GPU compute utilisation per consuming pod (DCGM exported_pod). Informational — high utilisation is not a fault. | table | neutral (no action) | `DCGM_FI_DEV_GPU_UTIL{exported_pod!="",Hostname=~"$hostname",UUID=~"$UUID"}` |

### Time-Series Trends

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 26 | **GPU Utilisation — All Devices** — GPU compute utilisation (%) time-series for every device. Hover for per-GPU breakdown. | timeseries | neutral (no action) | `DCGM_FI_DEV_GPU_UTIL{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 27 | **GPU Temperature — All Devices** — GPU core-die temperature (°C) per device over time. Sustained values above 85 °C trigger GPUOverheating alert. | timeseries | green < 85, orange ≥ 85, red ≥ 90 | `DCGM_FI_DEV_GPU_TEMP{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 28 | **Power Draw — All Devices** — Instantaneous power draw (W) per device. Spikes or sustained drops may indicate power anomalies. | timeseries | neutral (no action) | `DCGM_FI_DEV_POWER_USAGE{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 29 | **Composite Health Score Trend** — Composite health score trend (0–100) per device over the selected time range. | timeseries | red < 60, orange ≥ 60, green ≥ 80 | `gpu:health_score:composite{UUID=~"$UUID"}` |

### Workload Impact

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 30 | **Pods on Failed GPU Nodes** — Pods on nodes with a failed row remap. >0 fires WorkloadsOnFailedGPUNodes (critical). Action: cordon/drain the node. | stat | green < 1, red ≥ 1 | `sum(gpu:impact:pod_count_on_failed_nodes)` |
| 32 | **Pods on At-Risk GPU Nodes (>30% 24h failure prob)** — Pods on nodes with a GPU above 30% 24h failure probability. >0 fires WorkloadsOnAtRiskGPUNodes (warning). | stat | green < 1, orange ≥ 1 | `sum(gpu:impact:pod_count_on_at_risk_nodes)` |
| 31 | **DCGM Scrape Success** — Share of DCGM exporter targets scraping. <90% fires GPUDCGMScrapeDegraded. | stat | red < 0.01, orange ≥ 0.01, green ≥ 0.9 | `(count(up{job="nvidia-dcgm-exporter"} == 1) / count(up{job="nvidia-dcgm-exporter"})) or vector(0)` |
| 40 | **GPU Scoring & Alert Rules** — Are the gpu-alert-rules recording rules evaluating? NOT LOADED = health score, failure probability, impact counts and every platform=gpu-monitoring alert are not computed, so a 0 or empty value elsewhere does NOT mean healthy. Fix: oc apply -f gpu-rules.yaml. | stat | red < 1, green ≥ 1 | `count(gpu:platform:heartbeat) or vector(0)` |

---

## GPU SRE Deep Dive

**UID:** `gpu-sre-dashboard-v5` · **Display type:** Entity deep dive · **Question:** Why is this GPU / node unhealthy, and what is the evidence?

### Predictive Analysis & Composite Health

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 1 | **Composite Health Score** — Red <60 = GPUHealthScoreCritical; orange 60–80 = GPUHealthScoreHigh; green ≥80. | gauge | red < 60, orange ≥ 60, green ≥ 80 | `gpu:health_score:composite{UUID=~"$UUID"}` |
| 2 | **24h Failure Probability %** — Orange >30% = at-risk (WorkloadsOnAtRiskGPUNodes). Red >70% with health <60 fires GPUPredictiveFailure24h. | gauge | green < 30, orange ≥ 30, red ≥ 70 | `gpu:failure_probability:24h{UUID=~"$UUID"}` |
| 3 | **Throttle Pressure Score** — Composite throttle signal (0 = no throttle). Turns orange ≥10, red ≥50. Triggers GPUThermalThrottlingSustained at sustained pressure. | stat | green < 10, orange ≥ 10, red ≥ 50 | `gpu:throttle:pressure_score{UUID=~"$UUID"}` |
| 4 | **SM Clock (MHz)** — Current SM (streaming multiprocessor) clock frequency in MHz. Drops below base clock indicate active throttling. | stat | neutral (no action) | `DCGM_FI_DEV_SM_CLOCK{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 5 | **Clock Throttle Reasons (bitmask)** — DCGM clock-throttle bitmask. Non-zero bits indicate active throttle reasons: thermal (bit 2), power (bit 3), sync boost (bit 5). | stat | green < 1, orange ≥ 1 | `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 6 | **Memory Clock (MHz)** — Current memory clock frequency in MHz. Drops indicate memory bandwidth throttling, often correlated with thermal events. | stat | neutral (no action) | `DCGM_FI_DEV_MEM_CLOCK{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 7 | **Health Score Trend** — Composite health score trend over the selected time window. Downward trend warrants proactive investigation. | timeseries | red < 60, orange ≥ 60, green ≥ 80 | `gpu:health_score:composite{UUID=~"$UUID"}` |
| 8 | **Failure Probability Trend** — 24 h failure-probability trend. Rising curve indicates worsening GPU condition. | timeseries | green < 30, orange ≥ 30, red ≥ 70 | `gpu:failure_probability:24h{UUID=~"$UUID"}` |

### Active Alerts — This GPU / Node

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 9 | **Firing GPU Alerts — All (cluster-level alerts have no hostname/UUID)** — All GPU alert rules currently in Firing state for the selected node and GPU. | table | neutral (no action) | `ALERTS{alertstate="firing",platform="gpu-monitoring"}` |

### Temperature

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 10 | **GPU Core Temperature (°C)** — GPU core-die temperature (°C) over time. Sustained readings above 85 °C trigger the GPUOverheating alert. | timeseries | green < 85, orange ≥ 85, red ≥ 90 | `DCGM_FI_DEV_GPU_TEMP{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 11 | **Memory (HBM) Temperature (°C)** — HBM/memory die temperature (°C) over time. Elevated values alongside ECC errors indicate thermal-induced memory degradation. | timeseries | green < 85, orange ≥ 85, red ≥ 95 | `DCGM_FI_DEV_MEMORY_TEMP{Hostname=~"$hostname",UUID=~"$UUID"}` |

### Power & Energy

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 12 | **Power Draw (W)** — Instantaneous power draw (W) over time. Spikes or sustained drops from TDP may indicate power-rail anomalies. | timeseries | neutral (no action) | `DCGM_FI_DEV_POWER_USAGE{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 13 | **Power Instability — 15m Rolling Stddev** — 15m rolling stddev of power draw. Orange >50 W matches GPUPowerFluctuation. | timeseries | green < 50, orange ≥ 50 | `avg by(UUID, hostname, gpu, modelName, device, pci_bus_id) ( stddev_over_time(DCGM_FI_DEV_POWER_USAGE{Hostname=~"$hostname",UUID=~"$UUID"}[15m]) )` |

### GPU Utilisation & Profiling

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 14 | **GPU Compute Utilisation (%)** — GPU compute utilisation (%) — percentage of SMs actively executing CUDA kernels. | timeseries | neutral (no action) | `DCGM_FI_DEV_GPU_UTIL{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 15 | **GR Engine Active & Tensor Core Active (0–1)** — GR Engine Active (graphics/compute pipeline) and Tensor Core Active ratios (0–1). Tensor values near 1 indicate AI/ML workload saturation. | timeseries | neutral (no action) | `(DCGM_FI_PROF_GR_ENGINE_ACTIVE{Hostname=~"$hostname",UUID=~"$UUID"})` |
| 16 | **DRAM Bandwidth Active (0–1)** — DRAM bandwidth active ratio (0–1). Values near 1 indicate memory-bandwidth-bound workloads. | timeseries | neutral (no action) | `(DCGM_FI_PROF_DRAM_ACTIVE{Hostname=~"$hostname",UUID=~"$UUID"})` |

### Framebuffer Memory (VRAM)

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 17 | **VRAM Used (GiB)** — Framebuffer (VRAM) memory used in GiB over time. | timeseries | neutral (no action) | `DCGM_FI_DEV_FB_USED{Hostname=~"$hostname",UUID=~"$UUID"} / 1024` |
| 18 | **VRAM Free (GiB)** — Framebuffer (VRAM) memory free in GiB over time. Approaching zero triggers workload OOM risks. | timeseries | neutral (no action) | `DCGM_FI_DEV_FB_FREE{Hostname=~"$hostname",UUID=~"$UUID"} / 1024` |
| 19 | **VRAM Utilisation %** — VRAM utilisation as a percentage of total framebuffer capacity. Orange ≥80%, red ≥95%. | timeseries | green < 80, orange ≥ 80, red ≥ 95 | `DCGM_FI_DEV_FB_USED{Hostname=~"$hostname",UUID=~"$UUID"} / (DCGM_FI_DEV_FB_USED{Hostname=~"$hostname",UUID=~"$UUID"} + DCGM_FI_DEV_FB_FREE{Hostname...` |

### PCIe Bus

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 20 | **PCIe Replay Counter Rate (/s)** — Rate of PCIe replay events per second. Non-zero values indicate PCIe bus errors — triggers GPUPCIeReplayRateHigh. | timeseries | green < 5, orange ≥ 5 | `avg by(UUID, hostname, gpu, modelName, device, pci_bus_id) ( rate(DCGM_FI_DEV_PCIE_REPLAY_COUNTER{Hostname=~"$hostname",UUID=~"$UUID"}[5m]) )` |
| 21 | **PCIe TX/RX Bandwidth (bytes/s)** — PCIe transmit and receive bandwidth in bytes/s. Useful for diagnosing data-transfer bottlenecks. | timeseries | neutral (no action) | `(avg by(UUID, hostname, gpu, modelName, device, pci_bus_id) ( rate(DCGM_FI_PROF_PCIE_TX_BYTES{Hostname=~"$hostname",UUID=~"$UUID"}[5m]) ))` |
| 22 | **Clock Throttle Reasons Over Time** — Clock throttle reason bitmask over time, showing which throttle condition was active at each point. | timeseries | green < 1, orange ≥ 1 | `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS{Hostname=~"$hostname",UUID=~"$UUID"}` |

### ECC Errors & Memory Health

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 23 | **Row Remap Failure (0=OK · 1=Failed)** — Row-remap failure flag per GPU. 1 = an uncorrectable DRAM row has been permanently remapped — GPU may require replacement. | stat | green < 1, red ≥ 1 | `(DCGM_FI_DEV_ROW_REMAP_FAILURE{Hostname=~"$hostname",UUID=~"$UUID",container="nvidia-dcgm-exporter"} > bool 0) or (DCGM_FI_DEV_GPU_TEMP{Hostname=~"...` |
| 24 | **Uncorrectable Remapped Rows** — Count of uncorrectable (DBE-driven) remapped DRAM rows. Non-zero means permanent cell damage has occurred. | stat | green < 1, red ≥ 1 | `(DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS{Hostname=~"$hostname",UUID=~"$UUID",container="nvidia-dcgm-exporter"}) or (DCGM_FI_DEV_GPU_TEMP{Hostname=~...` |
| 25 | **Correctable Remapped Rows** — Count of correctable (SBE-driven) remapped DRAM rows. Rapid growth triggers GPUCorrectableRemapAccelerating alert. | stat | green < 10, orange ≥ 10 | `(DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS{Hostname=~"$hostname",UUID=~"$UUID",container="nvidia-dcgm-exporter"}) or (DCGM_FI_DEV_GPU_TEMP{Hostname=~"$...` |
| 26 | **ECC SBE Volatile Total** — Single-bit ECC (correctable) volatile error count since last driver reset. Increasing values indicate DRAM degradation. 'Not collected' = DCGM field 312 not enabled in exporter config. | stat | green < 1, orange ≥ 1 | `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 27 | **ECC DBE Volatile Total** — Double-bit ECC (uncorrectable) volatile error count. Any non-zero value triggers GPUDoubleBitECCDetected — immediate action required. 'Not collected' = DCGM field 313 not enabled in exporter config. | stat | green < 1, red ≥ 1 | `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL{Hostname=~"$hostname",UUID=~"$UUID"}` |
| 28 | **XID Errors (counter)** — XID error counter. XID codes indicate GPU hardware faults; specific codes (e.g. 79, 94, 95) indicate fatal errors. | stat | green < 1, red ≥ 1 | `DCGM_FI_DEV_XID_ERRORS{Hostname=~"$hostname",UUID=~"$UUID"} or DCGM_FI_DEV_GPU_TEMP{Hostname=~"$hostname",UUID=~"$UUID",container="nvidia-dcgm-expo...` |
| 29 | **Row Remap Count Over Time** — Row-remap count over time — both correctable and uncorrectable. Accelerating slope indicates active DRAM degradation. | timeseries | neutral (no action) | `(DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS{Hostname=~"$hostname",UUID=~"$UUID",container="nvidia-dcgm-exporter"}) or (DCGM_FI_DEV_GPU_TEMP{Hostname=~"$...` |
| 30 | **ECC Aggregate Errors Over Time** — ECC aggregate error time-series showing accumulated SBE and DBE counts. | timeseries | green < 1, orange ≥ 1 | `DCGM_FI_DEV_ECC_SBE_AGG_TOTAL{Hostname=~"$hostname",UUID=~"$UUID"}` |

### Platform Health

| ID | Panel | Type | Thresholds | Query |
|---|---|---|---|---|
| 31 | **GPU Scoring & Alert Rules** — Are the gpu-alert-rules recording rules evaluating? NOT LOADED = health score, failure probability, impact counts and every platform=gpu-monitoring alert are not computed, so a 0 or empty value elsewhere does NOT mean healthy. Fix: oc apply -f gpu-rules.yaml. | stat | red < 1, green ≥ 1 | `count(gpu:platform:heartbeat) or vector(0)` |
| 32 | **DCGM Exporter Targets** — Number of nvidia-dcgm-exporter pods Prometheus is successfully scraping. Zero means no GPU hardware metrics are flowing — all DCGM panels will show No data. | stat | red < 1, green ≥ 1 | `count(up{job="nvidia-dcgm-exporter"} == 1) or vector(0)` |
| 33 | **DCGM Scrape Success Rate** — Fraction of nvidia-dcgm-exporter targets Prometheus scraped successfully in the last interval. Below 90% triggers GPUDCGMScrapeDegraded (warning). Below 100% means some GPU nodes are producing no metrics. | stat | red < 0.01, orange ≥ 0.01, green ≥ 0.9 | `(count(up{job="nvidia-dcgm-exporter"} == 1) / count(up{job="nvidia-dcgm-exporter"})) or vector(0)` |
| 34 | **Firing GPU Alerts** — Count of ALERTS{platform=gpu-monitoring, alertstate=firing}. Any value above 0 means at least one GPU alert rule has triggered. Green = no active incidents. | stat | green < 1, red ≥ 1 | `count(ALERTS{platform="gpu-monitoring",alertstate="firing"}) or vector(0)` |

---

## Metrics this exporter may not export

`DCGM_FI_DEV_CLOCK_THROTTLE_REASONS`, `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL`, `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL`, `DCGM_FI_DEV_ECC_*_AGG_TOTAL` depend on the dcgm-exporter field list. When absent, the matching panels display *Not collected* and the alerts built on them stay inactive. Enable them in the exporter's counters ConfigMap to light these panels up.

## Recording rules (from `gpu-rules.yaml`)

| Rule | Meaning |
|---|---|
| `gpu:health_score:composite` | 0–100; 100 minus weighted penalties for temperature, memory/row-remap, power instability, PCIe replays, XID errors |
| `gpu:failure_probability:24h` | 0–100 %; temperature trend, PCIe replay rate, remapped rows, power, ECC |
| `gpu:throttle:pressure_score` | clock-throttle, thermal and power violation rates |
| `gpu:impact:pod_count_on_failed_nodes` | pods on nodes with a row-remap failure |
| `gpu:impact:pod_count_on_at_risk_nodes` | pods on nodes with failure probability > 30 % |
| `gpu:platform:heartbeat` | constant 1; proves the rules are evaluating (the *GPU Scoring & Alert Rules* tile) |
