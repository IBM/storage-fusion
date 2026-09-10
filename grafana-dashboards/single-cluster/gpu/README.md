# GPU Monitoring — Grafana Dashboards

Two complementary Grafana dashboards for NVIDIA GPU observability on OpenShift with DCGM Exporter.
They share a common data pipeline and are bidirectionally cross-linked, so an operator moves
naturally from a fleet-level alert straight into a per-GPU forensic view.

---

## How the Data Flows

```
NVIDIA GPU Hardware
       │
       ▼
DCGM Exporter  (DaemonSet, port 9400)
  Exposes 39 raw hardware metrics defined in dcgm-metrics.csv
       │
       ▼
Prometheus
  Scrapes DCGM Exporter via ServiceMonitor (job: nvidia-dcgm-exporter)
       │
       ├──► PrometheusRule: gpu-alert-rules   (prometheus-alert-rules.yaml)
       │       6 recording rules  ─ pre-compute health scores, failure
       │                            probability, blast-radius counts
       │      27 alert rules      ─ platform → node → hardware → degradation
       │                            → predictive → impact → operator
       │
       ▼
Grafana  (datasource uid: gpu-monitoring-prometheus)
       │
       ├──► GPU Cluster Overview   uid: gpu-cluster-overview-v8
       │      Fleet health · alert triage · workload attribution · trends
       │
       └──► GPU SRE Deep Dive      uid: gpu-sre-dashboard-v5
              Per-GPU forensics · ECC · thermal · power · PCIe · profiling
```

The two dashboards are **bidirectionally linked**.  
Every fleet panel in Cluster Overview carries a **"SRE Deep Dive →"** button.  
Every section in SRE Deep Dive carries a **"← Cluster Overview"** button.

---

## Dashboard 1 — GPU Cluster Overview

**File:** `grafana-cluster-overview.json`  
**UID:** `gpu-cluster-overview-v8`  
**Purpose:** Answer "is my GPU fleet healthy right now?" at a glance and navigate to the affected device.

### Template Variables

| Variable | Label | Populated from |
|---|---|---|
| `$datasource` | Datasource | Prometheus datasource picker |
| `$hostname` | Node | `label_values(DCGM_FI_DEV_GPU_UTIL, Hostname)` |
| `$UUID` | GPU (UUID) | `label_values(DCGM_FI_DEV_GPU_UTIL{Hostname=~"$hostname"}, UUID)` |

### Panel Sections

#### ╌ GPU Fleet Health Summary

Stat and gauge panels that aggregate across the entire fleet. Values are sourced from
recording rules rather than raw DCGM metrics so the maths is consistent with alert thresholds.

| Panel | Backing metric / rule | What it shows |
|---|---|---|
| Total GPU Count | `count(DCGM_FI_DEV_GPU_TEMP)` | GPUs currently visible to DCGM |
| Fleet Avg GPU Health Score | `avg(gpu:health_score:composite)` | Fleet mean of the 0–100 composite score |
| Healthy GPUs (score > 80) | `gpu:health_score:composite > 80` | Count of GPUs in the safe zone |
| Warning GPUs (60–80) | `gpu:health_score:composite` 60–79 | Count approaching degradation |
| Critical GPUs (< 60) | `gpu:health_score:composite < 60` | Count in high-risk / replacement zone |
| Predicted Failures 24h | `gpu:failure_probability:24h > 70` | GPUs with > 70 % 24 h failure probability |
| VRAM Utilisation | `DCGM_FI_DEV_FB_USED / (FB_USED + FB_FREE)` | Fleet VRAM bar gauge |
| Avg GPU Temp (°C) | `avg(DCGM_FI_DEV_GPU_TEMP)` | Fleet average die temperature |
| Avg Power Draw (W) | `avg(DCGM_FI_DEV_POWER_USAGE)` | Fleet average power draw |
| Total VRAM / Used VRAM (GiB) | `DCGM_FI_DEV_FB_FREE` / `FB_USED` | Aggregate framebuffer capacity vs consumption |
| DCGM Targets Up | `count(up{job="nvidia-dcgm-exporter"} == 1)` | Observability coverage — how many exporters are alive |

#### ╌ Alert Summary — GPU Fleet

Nine stat panels backed by `ALERTS{platform="gpu-monitoring", alertstate="firing"}`,
each filtered by `category` or `severity` label. Every panel links to the Grafana Alerting
list pre-filtered to that category.

| Panel | Filter applied |
|---|---|
| Total Firing GPU Alerts | all `platform="gpu-monitoring"` |
| Critical Alerts | `severity="critical"` |
| Warning Alerts | `severity="warning"` |
| Node Alerts | `category="node"` |
| Hardware Alerts | `category=~"hardware\|burnout\|xid\|ecc"` |
| Thermal / Power Alerts | `category=~"thermal\|power\|pcie"` |
| Memory Alerts | `category="memory"` |
| Predictive Alerts | `category="predictive"` |
| Impact Alerts | `category="impact_analysis"` |

**All Firing GPU Alerts** — a live table below the stats showing every firing alert with
per-row links to drill into the SRE Deep Dive for the affected node/UUID.

#### ╌ Per-GPU Health Matrix

A table panel that renders one row per GPU across the fleet, showing:
- `gpu:health_score:composite`
- `gpu:failure_probability:24h`
- Current VRAM utilisation

Clicking any row opens the SRE Deep Dive scoped to that node.

#### ╌ Hardware Failure Indicators

Fleet-wide view of the two irreversible memory failure signals:

| Panel | Metric | Condition |
|---|---|---|
| Row Remap Failure Flag — All GPUs | `DCGM_FI_DEV_ROW_REMAP_FAILURE` | `= 1` → spare DRAM rows exhausted, GPU producing corrupted output **now** |
| Uncorrectable Remapped Rows — All GPUs | `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS` | `> 0` → permanent DRAM damage, GPU replacement required |

#### ╌ Workload Attribution — GPU Utilisation by Pod

A table of `DCGM_FI_DEV_GPU_UTIL` joined with Kubernetes metadata (`namespace`, `pod`, `device`).
Identifies exactly which workloads are consuming GPU resources at the time of an incident.

#### ╌ Fleet Time-Series Trends

Four time-series panels drawing all GPUs simultaneously — useful for distinguishing a
cluster-wide event from a single-device fault:

| Panel | Metric |
|---|---|
| GPU Utilisation — All Devices | `DCGM_FI_DEV_GPU_UTIL` |
| GPU Temperature — All Devices | `DCGM_FI_DEV_GPU_TEMP` |
| Power Draw — All Devices | `DCGM_FI_DEV_POWER_USAGE` |
| Composite Health Score Trend | `gpu:health_score:composite` |

#### ╌ Workload Impact

Derived from recording rules; shows the blast-radius of hardware failures on running pods.

| Panel | Recording rule | Linked alert |
|---|---|---|
| Pods on Failed GPU Nodes | `gpu:impact:pod_count_on_failed_nodes` | `WorkloadsOnFailedGPUNodes` |
| Pods on At-Risk GPU Nodes (> 30 % 24 h fail prob) | `gpu:impact:pod_count_on_at_risk_nodes` | `WorkloadsOnAtRiskGPUNodes` |
| DCGM Scrape Success | `up{job="nvidia-dcgm-exporter"}` | `GPUDCGMScrapeDegraded` |

#### ╌ Fusion Gap Analysis

A comparison section showing how many custom-field alerts (ECC / XID / PCIe / Memory / Thermal)
are firing versus baseline platform/operator alerts. Used to validate observability coverage
beyond a default NVIDIA out-of-box setup.

#### All GPU Alerts — Live State

Full table of every alert in any state (`firing`, `pending`, `inactive`) with links to
filter the Grafana Alerting UI to the exact rule or firing subset.

---

## Dashboard 2 — GPU SRE Deep Dive

**File:** `grafana-sre-dashboard.json`  
**UID:** `gpu-sre-dashboard-v5`  
**Purpose:** Root-cause analysis for a single GPU. Scoped to one node + UUID via template
variables. Always reached from the Cluster Overview via a drill-down link.

### Template Variables

| Variable | Label | Populated from |
|---|---|---|
| `$datasource` | Datasource | Prometheus datasource picker |
| `$hostname` | Node | `label_values(DCGM_FI_DEV_GPU_UTIL, Hostname)` |
| `$UUID` | GPU (UUID) | `label_values(DCGM_FI_DEV_GPU_UTIL{Hostname=~"$hostname"}, UUID)` |

### Panel Sections

#### ╌ Predictive Analysis & Composite Health

The top row surfaces the computed risk scores before any raw metric, so an operator gets
an immediate severity read the moment they land on the dashboard.

| Panel | Type | Metric / rule | Threshold colours |
|---|---|---|---|
| Composite Health Score | Gauge | `gpu:health_score:composite` | Red < 60 · Orange 60–79 · Yellow 80–94 · Green ≥ 95 |
| 24 h Failure Probability % | Gauge | `gpu:failure_probability:24h` | Green < 20 · Orange ≥ 20 · Red ≥ 50 |
| Throttle Pressure Score | Stat | `gpu:throttle:pressure_score` | Green = No Throttle · Orange = Moderate · Red = High |
| SM Clock (MHz) | Time-series | `DCGM_FI_DEV_SM_CLOCK` | Sudden drops indicate active clock throttling |
| Memory Clock (MHz) | Time-series | `DCGM_FI_DEV_MEM_CLOCK` | Memory clock frequency trend |
| Health Score Trend | Time-series | `gpu:health_score:composite` | Historical score trajectory |
| Failure Probability Trend | Time-series | `gpu:failure_probability:24h` | Rising curve = proactive drain signal |
| Clock Throttle Reasons (bitmask) | Time-series | `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` | Non-zero = throttle reason active |

**Health score formula** (recording rule `gpu:health_score:composite`):

```
score = 100
  − thermal_penalty    × 0.25   (die temp ramp 65–95 °C + 15 m rising trend)
  − ecc_memory_penalty × 0.30   (row remap failure + uncorrectable rows + DBE errors)
  − power_penalty      × 0.18   (15 m stddev instability + rolling avg delta)
  − pcie_penalty       × 0.12   (PCIe replay rate + 15 m vs 1 h trend)
  − xid_penalty        × 0.15   (XID errors in last 1 h and last 30 m)
```

**24 h failure probability formula** (recording rule `gpu:failure_probability:24h`):

```
probability = 0
  + thermal_trend  up to 30   (30 m avg temp − 2 h avg temp, normalised over 8 °C)
  + pcie_replay    up to 25   (30 m replay rate / 10 × 25)
  + memory_remap   up to 15   (uncorrectable rows × 12 + remap failure flag × 15)
  + power_instab   up to 10   (15 m stddev − 20 W, normalised over 80 W)
  + ecc_errors     up to 20   (SBE rate × 5 + DBE volatile total × 20)
```

#### ╌ Active Alerts — This GPU / Node

A table of `ALERTS{Hostname=~"$hostname", platform="gpu-monitoring"}` with per-row links to:
- The firing alert in Grafana Alerting
- The alert rule definition

**Firing GPU Alerts — All (fleet-level)**: A second table for alerts that have no `Hostname`
label (e.g. `WorkloadsOnFailedGPUNodes`, `GPUPlatformRecordingRulesDown`).

#### ╌ Temperature

| Panel | Metric | Linked alert | Fires when |
|---|---|---|---|
| GPU Core Temperature (°C) | `DCGM_FI_DEV_GPU_TEMP` | `GPUOverheating` | > 85 °C for 5 m |
| Memory (HBM) Temperature (°C) | `DCGM_FI_DEV_MEMORY_TEMP` | — | Reference only |

#### ╌ Power & Energy

| Panel | Metric | Linked alert | Fires when |
|---|---|---|---|
| Power Draw (W) | `DCGM_FI_DEV_POWER_USAGE` | `GPUPowerAnomaly` | > 350 W or 10 m stddev > 50 W |
| Power Instability — 15 m Rolling Stddev | `stddev_over_time(DCGM_FI_DEV_POWER_USAGE[15m])` | feeds health score | — |

#### ╌ GPU Utilisation & Profiling

| Panel | Metric | Description |
|---|---|---|
| GPU Compute Utilisation (%) | `DCGM_FI_DEV_GPU_UTIL` | SM occupancy — workload intensity |
| GR Engine Active & Tensor Core Active (0–1) | `DCGM_FI_PROF_GR_ENGINE_ACTIVE` / `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | Profiling counters for AI / HPC workload characterisation |
| DRAM Bandwidth Active (0–1) | `DCGM_FI_PROF_DRAM_ACTIVE` | Memory bus saturation |

#### ╌ Framebuffer Memory (VRAM)

| Panel | Metric | Unit |
|---|---|---|
| VRAM Used (GiB) | `DCGM_FI_DEV_FB_USED / 1024` | GiB |
| VRAM Free (GiB) | `DCGM_FI_DEV_FB_FREE / 1024` | GiB |
| VRAM Utilisation % | `FB_USED / (FB_USED + FB_FREE) × 100` | % |

#### ╌ PCIe Bus

| Panel | Metric | Linked alert | Fires when |
|---|---|---|---|
| PCIe Replay Counter Rate (/s) | `rate(DCGM_FI_DEV_PCIE_REPLAY_COUNTER[30m])` | `GPUPCIeReplayRateHigh` | > 5 /s sustained 30 m |
| PCIe TX / RX Bandwidth (bytes/s) | `DCGM_FI_PROF_PCIE_TX_BYTES` / `PCIE_RX_BYTES` | — | Throughput reference |
| Clock Throttle Reasons Over Time | `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` | `GPUThermalThrottlingSustained` | Bitmask non-zero |

#### ╌ ECC Errors & Memory Health

The most critical section for hardware failure diagnosis. Each panel is directly linked to its
alert rule so an operator can jump from a visual spike straight to the firing alert.

| Panel | Metric | Linked alert | Meaning |
|---|---|---|---|
| Row Remap Failure (0 = OK · 1 = Failed) | `DCGM_FI_DEV_ROW_REMAP_FAILURE` | `GPURowRemapFailure` | **Spare DRAM rows exhausted — GPU producing corrupted output now** |
| Uncorrectable Remapped Rows | `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS` | `GPUUncorrectableRemappedRows` | Permanently damaged DRAM row count — replacement required |
| Correctable Remapped Rows | `DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS` | `GPUCorrectableRemapAccelerating` | Accelerating rate predicts future `ROW_REMAP_FAILURE` |
| ECC SBE Volatile Total | `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL` | `GPUMemoryDegradationCritical` | Single-bit ECC errors since last driver reset |
| ECC DBE Volatile Total | `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | `GPUDoubleBitECCDetected` | **Uncorrectable double-bit errors — workload outputs may be wrong** |
| XID Errors (counter) | `DCGM_FI_DEV_XID_ERRORS` | `GPUXIDErrorsDetected` / `GPUXIDFatalCritical` | NVIDIA driver fault codes (XID 48/79/94 = fatal) |
| Row Remap Count Over Time | `DCGM_FI_DEV_ROW_REMAP_*` | `GPURowRemapFailure` · `GPUCorrectableRemapAccelerating` | Remap trajectory — watch for accelerating slope |
| ECC Aggregate Errors Over Time | `DCGM_FI_DEV_ECC_DBE_AGG_TOTAL` | `GPUDoubleBitECCDetected` · `GPUMemoryDegradationCritical` | Long-term ECC trend |

#### ╌ Platform Health

| Panel | Metric | Linked alert |
|---|---|---|
| VRAM Utilisation | `FB_USED / (FB_USED + FB_FREE)` | — (links back to VRAM section) |
| DCGM Exporter Targets | `up{job="nvidia-dcgm-exporter"}` | `GPUDCGMScrapeDegraded` · `GPUNodeDCGMDarkout` |
| DCGM Scrape Success Rate | `count(up == 1) / count(up)` | `GPUDCGMScrapeDegraded` |
| Firing GPU Alerts | `count(ALERTS{platform="gpu-monitoring", alertstate="firing"})` | All active GPU alerts |

---

## Alert Rules Reference

Defined in `../alert-rules/prometheus-alert-rules.yaml` as a single `PrometheusRule` object
named `gpu-alert-rules` in the `openshift-monitoring` namespace.

Every alert carries:
- `platform: gpu-monitoring` — used by the dashboard `ALERTS{}` queries to scope results
- `fusion_enhanced: "true"` — distinguishes custom-field alerts from NVIDIA baseline

### Recording Rules (group: `gpu.recording.core`, interval 60 s)

Evaluated before any alert rule. Dashboards and alerts consume these derived metrics,
not the raw DCGM counters.

| Rule | Inputs from `dcgm-metrics.csv` | What it computes |
|---|---|---|
| `gpu:platform:heartbeat` | — | `vector(1)` liveness signal; absence fires `GPUPlatformRecordingRulesDown` |
| `gpu:health_score:composite` | `GPU_TEMP`, `ROW_REMAP_FAILURE`, `UNCORRECTABLE_REMAPPED_ROWS`, `CORRECTABLE_REMAPPED_ROWS`, `ECC_DBE_VOL_TOTAL`, `POWER_USAGE`, `PCIE_REPLAY_COUNTER`, `XID_ERRORS` | 0–100 composite GPU health weighted across 5 subsystems |
| `gpu:failure_probability:24h` | `GPU_TEMP`, `PCIE_REPLAY_COUNTER`, `UNCORRECTABLE_REMAPPED_ROWS`, `ROW_REMAP_FAILURE`, `POWER_USAGE`, `ECC_SBE_VOL_TOTAL`, `ECC_DBE_VOL_TOTAL` | 0–100 predicted probability of hardware failure within 24 h |
| `gpu:impact:pod_count_on_failed_nodes` | `ROW_REMAP_FAILURE`, `kube_pod_info` | Pod count on nodes where `ROW_REMAP_FAILURE = 1` |
| `gpu:throttle:pressure_score` | `CLOCK_THROTTLE_REASONS`, `THERMAL_VIOLATION`, `POWER_VIOLATION` | Composite throttle pressure score (0 = none) |
| `gpu:impact:pod_count_on_at_risk_nodes` | `gpu:failure_probability:24h`, `kube_pod_info` | Pod count on nodes with failure probability > 30 % |

### Alert Groups

#### Group A — Platform liveness (`gpu.alerts.platform`)

| Alert | Sev | Condition | `for` |
|---|---|---|---|
| `GPUPlatformRecordingRulesDown` | critical | `absent(gpu:platform:heartbeat)` | 5 m |
| `GPUDCGMScrapeDegraded` | warning | `count(up == 1) / count(up) < 0.9` for `job="nvidia-dcgm-exporter"` | 5 m |

> If `GPUPlatformRecordingRulesDown` fires, **no predictive or impact alerts will fire** — health scores and failure probabilities are all dark.

#### Group B — Node failure path (`gpu.alerts.node`)

| Alert | Sev | Condition | `for` |
|---|---|---|---|
| `GPUNodeNotReady` | critical | Node `NotReady` and was carrying GPU workloads 10 m ago | 2 m |
| `GPUNodeUnreachable` | critical | `node_exporter` absent or `up == 0` on GPU node | 5 m |
| `GPUNodeDCGMDarkout` | critical | Node `Ready` but DCGM metrics (`DCGM_FI_DEV_GPU_TEMP`) absent | 10 m |
| `GPUNodePressure` | warning | `MemoryPressure`, `DiskPressure`, or `PIDPressure` condition active on GPU node | 5 m |
| `GPUDevicePluginFailure` | critical | NVIDIA Device Plugin pods not `Ready` or absent | 5 m |

#### Group C — Confirmed hardware failures (`gpu.alerts.hardware`)

| Alert | Sev | Condition | `for` |
|---|---|---|---|
| `GPUDeviceUnreachable` | critical | GPU UUID had metrics 30 m ago, now absent from DCGM | 5 m |
| `GPUBurnoutPermanentFailure` | critical | GPU UUID absent from DCGM > 10 m, node still `Ready` | 10 m |
| `GPURowRemapFailure` | critical | `DCGM_FI_DEV_ROW_REMAP_FAILURE > 0` | immediate |
| `GPUDoubleBitECCDetected` | critical | `increase(DCGM_FI_DEV_ECC_DBE_VOL_TOTAL[5m]) > 0` | 5 m |
| `GPUXIDErrorsDetected` | critical | `increase(DCGM_FI_DEV_XID_ERRORS[1h]) > 0` | 5 m |
| `GPUXIDFatalCritical` | critical | Fatal XID 48 / 79 / 94 detected in last 30 m | immediate |
| `GPUPowerAnomaly` | warning | Power > 350 W **or** 10 m stddev > 50 W | 5 m |
| `GPUPCIeReplayRateHigh` | warning | `rate(DCGM_FI_DEV_PCIE_REPLAY_COUNTER[30m]) > 5` | 30 m |

#### Group D — Progressive hardware degradation (`gpu.alerts.degradation`)

| Alert | Sev | Condition | `for` |
|---|---|---|---|
| `GPUOverheating` | critical | `DCGM_FI_DEV_GPU_TEMP > 85` | 5 m |
| `GPUUncorrectableRemappedRows` | critical | `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS > 0` | 5 m |
| `GPUCorrectableRemapAccelerating` | warning | `increase(DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS[6h]) > 5` | 10 m |
| `GPUMemoryDegradationCritical` | critical | ≥ 2 simultaneous signals: SBE > 10/h, correctable remap > 3/6h, uncorrectable rows present | 10 m |
| `GPUThermalThrottlingSustained` | warning | ≥ 2 of: thermal violation > 1 s/30 m, temp > 82 °C, clock throttle reasons non-zero | 15 m |

#### Group E — Predictive / composite early warning (`gpu.alerts.predictive`)

| Alert | Sev | Condition | `for` |
|---|---|---|---|
| `GPUHealthScoreCritical` | critical | `gpu:health_score:composite` 40–59 | 10 m |
| `GPUHealthScoreHigh` | warning | `gpu:health_score:composite` 60–79 | 15 m |
| `GPUPredictiveFailure` | critical | Failure prob > 70 % **and** health score < 60 | 10 m |

#### Group F — Workload blast-radius impact (`gpu.alerts.impact`)

| Alert | Sev | Condition | `for` |
|---|---|---|---|
| `WorkloadsOnFailedGPUNodes` | critical | `gpu:impact:pod_count_on_failed_nodes > 0` | 2 m |
| `WorkloadsOnAtRiskGPUNodes` | warning | `gpu:impact:pod_count_on_at_risk_nodes > 0` | 5 m |

#### Group G — GPU Operator health (`gpu.alerts.operator`)

| Alert | Sev | Condition | `for` |
|---|---|---|---|
| `GPUOperatorReconciliationFailed` | warning | No successful reconciliation in > 1 h | immediate |
| `GPUOperatorDriverAutoUpgradeFailures` | warning | Auto-upgrade enabled and `nodes_upgrades_failed > 0` | immediate |

---

## DCGM Metrics (39 total)

Collected by DCGM Exporter and defined in `../configmap/dcgm-metrics.csv`.
These are the raw inputs consumed by the recording rules and surfaced directly in dashboard panels.

| Category | Metric name | Type | Description |
|---|---|---|---|
| **Compute** | `DCGM_FI_DEV_GPU_UTIL` | gauge | GPU utilisation (%) |
| | `DCGM_FI_DEV_MEM_COPY_UTIL` | gauge | Memory copy engine utilisation (%) |
| | `DCGM_FI_DEV_ENC_UTIL` | gauge | Encoder utilisation (%) |
| | `DCGM_FI_DEV_DEC_UTIL` | gauge | Decoder utilisation (%) |
| **Temperature** | `DCGM_FI_DEV_GPU_TEMP` | gauge | GPU die temperature (°C) |
| | `DCGM_FI_DEV_MEMORY_TEMP` | gauge | VRAM temperature (°C) |
| | `DCGM_FI_DEV_THERMAL_VIOLATION` | counter | Cumulative thermal throttle microseconds |
| **Clocks & throttle** | `DCGM_FI_DEV_SM_CLOCK` | gauge | SM clock frequency (MHz) |
| | `DCGM_FI_DEV_MEM_CLOCK` | gauge | Memory clock frequency (MHz) |
| | `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` | gauge | Active clock throttle reason bitmask |
| **Power & energy** | `DCGM_FI_DEV_POWER_USAGE` | gauge | GPU power draw (W) |
| | `DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION` | counter | Total energy consumed (mJ) |
| | `DCGM_FI_DEV_POWER_VIOLATION` | counter | Cumulative power-cap throttle microseconds |
| **Framebuffer (VRAM)** | `DCGM_FI_DEV_FB_FREE` | gauge | Framebuffer free memory (MiB) |
| | `DCGM_FI_DEV_FB_USED` | gauge | Framebuffer used memory (MiB) |
| | `DCGM_FI_DEV_FB_RESERVED` | gauge | Framebuffer reserved memory (MiB) |
| **PCIe bus** | `DCGM_FI_DEV_PCIE_REPLAY_COUNTER` | counter | PCIe replay / retry counter |
| | `DCGM_FI_PROF_PCIE_TX_BYTES` | counter | PCIe transmit bytes |
| | `DCGM_FI_PROF_PCIE_RX_BYTES` | counter | PCIe receive bytes |
| **NVLink** | `DCGM_FI_DEV_NVLINK_CRC_FLIT_ERROR_COUNT_TOTAL` | counter | NVLink CRC FLIT error count (all links) |
| | `DCGM_FI_DEV_NVLINK_CRC_DATA_ERROR_COUNT_TOTAL` | counter | NVLink CRC data error count (all links) |
| | `DCGM_FI_DEV_NVLINK_REPLAY_ERROR_COUNT_TOTAL` | counter | NVLink replay error count (all links) |
| | `DCGM_FI_DEV_NVLINK_RECOVERY_ERROR_COUNT_TOTAL` | counter | NVLink recovery error count (all links) |
| | `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` | gauge | NVLink aggregate bandwidth (MB/s) |
| **XID faults** | `DCGM_FI_DEV_XID_ERRORS` | counter | XID driver-reported GPU fault counter |
| **ECC errors** | `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL` | counter | Volatile single-bit ECC errors (total) |
| | `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | counter | Volatile double-bit ECC errors (total) |
| | `DCGM_FI_DEV_ECC_SBE_AGG_TOTAL` | counter | Aggregate single-bit ECC errors |
| | `DCGM_FI_DEV_ECC_DBE_AGG_TOTAL` | counter | Aggregate double-bit ECC errors |
| **Row remap & retirement** | `DCGM_FI_DEV_ROW_REMAP_FAILURE` | gauge | Row remap failure (1 = spare rows exhausted) |
| | `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS` | counter | Uncorrectable remapped DRAM rows |
| | `DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS` | counter | Correctable remapped DRAM rows |
| | `DCGM_FI_DEV_ROW_REMAP_PENDING` | gauge | Row remap pending flag |
| | `DCGM_FI_DEV_RETIRED_DBE` | counter | Pages retired by DBE errors |
| | `DCGM_FI_DEV_RETIRED_SBE` | counter | Pages retired by SBE errors |
| | `DCGM_FI_DEV_RETIRED_PENDING` | gauge | Pages pending retirement |
| **Profiling** | `DCGM_FI_PROF_DRAM_ACTIVE` | gauge | DRAM bandwidth utilisation (0–1) |
| | `DCGM_FI_PROF_GR_ENGINE_ACTIVE` | gauge | Graphics engine active fraction (0–1) |
| | `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | gauge | Tensor core active fraction (0–1) |

---

## Typical Operator Workflow

```
GPU Cluster Overview
  │
  ├─ Alert Summary: Critical Alerts > 0 ?
  │     └─ "All Firing GPU Alerts" table  →  identify Hostname + UUID
  │
  ├─ Per-GPU Health Matrix: Health Score < 60 or Failure Prob > 70 % ?
  │     └─ Click row  →  opens SRE Deep Dive scoped to that GPU
  │
  └─ Hardware Failure Indicators: ROW_REMAP_FAILURE = 1 anywhere ?
        └─ Cordon node immediately (compute results are corrupted)

        ↓  drill-down link

GPU SRE Deep Dive  ($hostname + $UUID)
  │
  ├─ Predictive row
  │     Health Score gauge  +  24 h Failure Probability gauge
  │     → both red?  proceed to ECC section without delay
  │
  ├─ Active Alerts table
  │     → check which alert groups (B/C/D/E/F) are firing for this GPU
  │
  ├─ ECC Errors & Memory Health
  │     ROW_REMAP_FAILURE = 1  →  oc adm cordon <node>   (output corrupted NOW)
  │     DBE Volatile > 0       →  oc adm cordon <node>   (uncorrectable errors)
  │     Correctable rows ↑     →  schedule replacement window
  │     XID 48 / 79 / 94       →  oc adm cordon + escalate to hardware team
  │
  ├─ Temperature / Power
  │     Temp > 85 °C sustained  →  check cooling, reduce workload
  │     Power stddev > 50 W     →  check PSU, may indicate failing GPU
  │
  └─ PCIe Bus
        Replay rate > 5 /s      →  check riser / slot / cable integrity
```
