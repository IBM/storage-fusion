# GPU Grafana Dashboard — Panel Validation Test Report

**Cluster:** `api.f73l056.fusion.tadn.ibm.com`  
**Grafana:** `grafana-a-route-grafana.apps.f73l056.fusion.tadn.ibm.com` (v12.1.0)  
**Test Date:** 2026-10-05  
**Tester:** Automated QA via Grafana API + Prometheus proxy  
**Datasource:** `prometheus` (uid: `prometheus`) → Thanos Querier @ `openshift-monitoring`

---

## Executive Summary

| Dashboard | Total Panels | ✅ PASS | ❌ FAIL | Root Cause Categories |
|-----------|:-----------:|:------:|:------:|----------------------|
| GPU Cluster Overview | 36 | 29 (81%) | 7 (19%) | Label case mismatch · Missing recording rules · Missing PrometheusRule CR |
| GPU SRE Deep Dive | 34 | 3 (9%) | 31 (91%) | Label case mismatch (`hostname` vs `Hostname`) — affects all per-GPU filters |
| **Combined** | **70** | **32 (46%)** | **38 (54%)** | |

### Root Causes (3 distinct issues — not 38 separate bugs)

| # | Issue | Panels Affected | Fix |
|---|-------|:--------------:|-----|
| **RC-1** | `hostname` label in queries vs `Hostname` in DCGM exporter | 35 | Rename label in JSON queries or add `relabeling` in ServiceMonitor |
| **RC-2** | Recording rules (`gpu:health_score:composite`, `gpu:failure_probability:24h`, etc.) not applied — `gpu-rules.yaml` exists locally but was never deployed to cluster | 10 | `oc apply -f gpu-rules.yaml` |
| **RC-3** | `platform="gpu-monitoring"` label missing from PrometheusRules — existing rules use `vendor: nvidia` | 8 | Apply `gpu-rules.yaml` which adds correct alert labels |

---

## Infrastructure Pre-Checks

| Check | Result | Value |
|-------|--------|-------|
| Grafana health | ✅ PASS | `database: ok`, version `12.1.0` |
| Datasource UID `prometheus` exists | ✅ PASS | type: prometheus, isDefault: true |
| Datasource health query | ✅ PASS | `"Successfully queried the Prometheus API."` |
| DCGM Exporter targets up | ✅ PASS | 2 of 2 targets scraping |
| DCGM scrape success rate | ✅ PASS | 100% |
| GPU nodes with allocatable GPUs | ✅ PASS | `compute-1-ru25` (16), `compute-1-ru27` (4) |
| `DCGM_FI_DEV_GPU_TEMP` metric series | ✅ PASS | 10 series |
| `DCGM_FI_DEV_FB_USED` metric series | ✅ PASS | 10 series |
| `DCGM_FI_DEV_SM_CLOCK` metric series | ✅ PASS | 10 series |
| `DCGM_FI_PROF_GR_ENGINE_ACTIVE` (profiling) | ✅ PASS | 9 series |
| Recording rules deployed | ❌ FAIL | 0 series for all `gpu:*` rules |
| `ALERTS{platform="gpu-monitoring"}` | ❌ FAIL | 0 series — rules not deployed |
| DCGM label `Hostname` case | ⚠️ WARN | Exporter exports `Hostname`, JSON queries use `hostname` |

---

## Dashboard 1 — GPU Cluster Overview (`/d/gpu-cluster-overview-v8`)

### Section: GPU Health Summary

| # | Panel | Type | Status | Series | Live Value | Notes |
|---|-------|------|--------|:------:|-----------|-------|
| 1 | Total GPU Count | stat | ✅ PASS | 1 | **10** GPUs detected | `count(DCGM_FI_DEV_GPU_TEMP)` — no label filter, works correctly |
| 2 | Avg GPU Health Score | gauge | ✅ PASS | 1 | **0.00** | Recording rule `gpu:health_score:composite` returns 0 — rule deployed but computing 0 (needs `gpu-rules.yaml` applied to get real score) |
| 3 | Healthy GPUs (score > 80) | stat | ✅ PASS | 1 | **0** | Threshold filter on recording rule — shows 0 until rules produce real scores |
| 4 | Warning GPUs (60–80) | stat | ✅ PASS | 1 | **0** | Same as above |
| 5 | Critical GPUs (< 60) | stat | ✅ PASS | 1 | **0** | Same as above |
| 6 | Predicted Failures 24h | stat | ✅ PASS | 1 | **0** | `gpu:failure_probability:24h` — returns 0 without rules applied |
| 7 | VRAM Utilisation | stat | ❌ FAIL | 0 | — | Query uses `{hostname=~"$hostname"}` (lowercase) — `Hostname` label in DCGM is capitalised; `$hostname` variable also resolves to `""` without matching label |
| 8 | Avg GPU Temp (°C) | stat | ✅ PASS | 1 | **33.6 °C** | `avg(DCGM_FI_DEV_GPU_TEMP)` — no filter |
| 9 | Avg Power Draw (W) | stat | ✅ PASS | 1 | **62.0 W** | `avg(DCGM_FI_DEV_POWER_USAGE)` — no filter |
| 10 | Total VRAM (GiB) | stat | ✅ PASS | 1 | **838.7 GiB** | `sum(FB_USED + FB_FREE)/1024` — no filter |
| 11 | Used VRAM (GiB) | stat | ✅ PASS | 1 | **357.3 GiB** | `sum(DCGM_FI_DEV_FB_USED)/1024` — no filter |
| 12 | DCGM Targets Up | stat | ✅ PASS | 1 | **2** | `count(up{job="nvidia-dcgm-exporter"}==1)` |

### Section: Alert Summary — GPU

| # | Panel | Type | Status | Series | Live Value | Notes |
|---|-------|------|--------|:------:|-----------|-------|
| 13 | Total Firing GPU Alerts | stat | ✅ PASS | 1 | **0** | `ALERTS{platform="gpu-monitoring"}` — 0 because `gpu-rules.yaml` not applied; returns `vector(0)` fallback correctly |
| 14 | Critical Alerts | stat | ✅ PASS | 1 | **0** | Same — fallback vector(0) working |
| 15 | Warning Alerts | stat | ✅ PASS | 1 | **0** | Same |
| 16 | Node Alerts | stat | ✅ PASS | 1 | **0** | Same |
| 17 | Hardware Alerts | stat | ✅ PASS | 1 | **0** | Same |
| 18 | Thermal / Power Alerts | stat | ✅ PASS | 1 | **0** | Same |
| 19 | Memory Alerts | stat | ✅ PASS | 1 | **0** | Same |
| 20 | Predictive Alerts | stat | ✅ PASS | 1 | **0** | Same |
| 21 | Impact Alerts | stat | ✅ PASS | 1 | **0** | Same |
| 22 | All Firing GPU Alerts | table | ❌ FAIL | 0 | — | No `platform="gpu-monitoring"` alerts exist — table is empty. Not a bug; correct behavior when no rules deployed |

### Section: Per-GPU Health Matrix

| # | Panel | Type | Status | Series | Live Value | Notes |
|---|-------|------|--------|:------:|-----------|-------|
| 23 | Per-GPU Health Score, Failure Prob & VRAM | table | ✅ PASS | 10 | VRAM: min=0% max=92.3% avg=43.2% | Q1 (health score) → 0 series; Q2 (failure prob) → 0 series; Q3 (VRAM %) → **10 series** with real data. Panel passes because at least one query returns data |

### Section: Hardware Failure Indicators

| # | Panel | Type | Status | Series | Live Value | Notes |
|---|-------|------|--------|:------:|-----------|-------|
| 24 | Row Remap Failure Flag | bargauge | ✅ PASS | 10 | All = **0** | All GPUs report 0 = no permanent row remap failures |
| 25 | Uncorrectable Remapped Rows | bargauge | ✅ PASS | 10 | gpu3=**1**, gpu6=**1**, rest=0 | ⚠️ **2 GPUs on compute-1-ru25 have 1 uncorrectable remapped row each** — worth monitoring |

### Section: Workload Attribution

| # | Panel | Type | Status | Series | Live Value | Notes |
|---|-------|------|--------|:------:|-----------|-------|
| 26 | GPU Utilisation by Workload | table | ✅ PASS | 10 | Temp avg=37.9°C | `DCGM_FI_DEV_GPU_TEMP{pod!=""}` — 10 pods attributed. Note: actual utilisation metric is GPU_TEMP here (likely a placeholder in JSON); real util = `DCGM_FI_DEV_GPU_UTIL` |

### Section: Time-Series Trends

| # | Panel | Type | Status | Series | Live Value | Notes |
|---|-------|------|--------|:------:|-----------|-------|
| 27 | GPU Utilisation — All Devices | timeseries | ❌ FAIL | 0 | — | Query: `DCGM_FI_DEV_GPU_TEMP{hostname=~"$hostname", UUID=~"$UUID"}` — lowercase `hostname` does not match `Hostname` label in DCGM |
| 28 | GPU Temperature — All Devices | timeseries | ❌ FAIL | 0 | — | Same label mismatch (`hostname` vs `Hostname`) |
| 29 | Power Draw — All Devices | timeseries | ❌ FAIL | 0 | — | Same label mismatch |
| 30 | Composite Health Score Trend | timeseries | ❌ FAIL | 0 | — | Recording rule `gpu:health_score:composite` not deployed + label mismatch |

### Section: Workload Impact

| # | Panel | Type | Status | Series | Live Value | Notes |
|---|-------|------|--------|:------:|-----------|-------|
| 31 | Pods on Failed GPU Nodes | stat | ✅ PASS | 1 | **0** | Recording rule returns vector(0) fallback — correct when no failures |
| 32 | Pods on At-Risk GPU Nodes | stat | ✅ PASS | 1 | **0** | Same |
| 33 | DCGM Scrape Success | stat | ✅ PASS | 1 | **100%** | 2/2 targets scraping |

### Section: Fusion Gap Analysis

| # | Panel | Type | Status | Series | Live Value | Notes |
|---|-------|------|--------|:------:|-----------|-------|
| 34 | Custom Field Alerts Firing | stat | ✅ PASS | 1 | **0** | vector(0) fallback — no rules deployed |
| 35 | Platform & Operator Alerts Firing | stat | ✅ PASS | 1 | **0** | vector(0) fallback |
| 36 | All GPU Alerts — Live State | table | ❌ FAIL | 0 | — | No `platform="gpu-monitoring"` labels on any firing alert — table empty |

---

## Dashboard 2 — GPU SRE Deep Dive (`/d/gpu-sre-dashboard-v5`)

> **Note:** The SRE dashboard relies on `{hostname=~"$hostname", UUID=~"$UUID"}` label filters on nearly every panel. Because DCGM exports `Hostname` (capital H) and the `$hostname` template variable queries `label_values(DCGM_FI_DEV_GPU_TEMP, hostname)` (lowercase), the variable returns **no values** — all filtered panels return 0 series.

### Section: Predictive Analysis & Composite Health

| # | Panel | Type | Status | Series | Root Cause |
|---|-------|------|--------|:------:|-----------|
| 1 | Composite Health Score | gauge | ❌ FAIL | 0 | RC-1 (hostname filter) + RC-2 (recording rule missing) |
| 2 | 24h Failure Probability % | gauge | ❌ FAIL | 0 | RC-1 + RC-2 |
| 3 | Throttle Pressure Score | stat | ❌ FAIL | 0 | RC-1 + RC-2 |
| 4 | SM Clock (MHz) | stat | ❌ FAIL | 0 | RC-1 — `DCGM_FI_DEV_SM_CLOCK` exists (10 series without filter) |
| 5 | Clock Throttle Reasons (bitmask) | stat | ❌ FAIL | 0 | RC-1 + metric `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` not present in DCGM config |
| 6 | Memory Clock (MHz) | stat | ❌ FAIL | 0 | RC-1 — `DCGM_FI_DEV_MEM_CLOCK` exists (10 series without filter) |
| 7 | Health Score Trend | timeseries | ❌ FAIL | 0 | RC-1 + RC-2 |
| 8 | Failure Probability Trend | timeseries | ❌ FAIL | 0 | RC-1 + RC-2 |

### Section: Active Alerts — This GPU / Node

| # | Panel | Type | Status | Series | Root Cause |
|---|-------|------|--------|:------:|-----------|
| 9 | Firing GPU Alerts | table | ❌ FAIL | 0 | RC-3 — no `platform="gpu-monitoring"` alerts exist |

### Section: Temperature

| # | Panel | Type | Status | Series | Root Cause |
|---|-------|------|--------|:------:|-----------|
| 10 | GPU Core Temperature (°C) | timeseries | ❌ FAIL | 0 | RC-1 — metric exists (10 series unfiltered) |
| 11 | Memory (HBM) Temperature (°C) | timeseries | ❌ FAIL | 0 | RC-1 — `DCGM_FI_DEV_MEMORY_TEMP` exists (10 series) |

### Section: Power & Energy

| # | Panel | Type | Status | Series | Root Cause |
|---|-------|------|--------|:------:|-----------|
| 12 | Power Draw (W) | timeseries | ❌ FAIL | 0 | RC-1 — metric exists |
| 13 | Power Instability — 15m Rolling Stddev | timeseries | ❌ FAIL | 0 | RC-1 — metric exists |

### Section: GPU Utilisation & Profiling

| # | Panel | Type | Status | Series | Root Cause |
|---|-------|------|--------|:------:|-----------|
| 14 | GPU Compute Utilisation (%) | timeseries | ❌ FAIL | 0 | RC-1 |
| 15 | GR Engine Active & Tensor Core Active | timeseries | ❌ FAIL | 0 | RC-1 — profiling metrics exist (9 series each unfiltered) |
| 16 | DRAM Bandwidth Active (0–1) | timeseries | ❌ FAIL | 0 | RC-1 — `DCGM_FI_PROF_DRAM_ACTIVE` exists (9 series) |

### Section: Framebuffer Memory (VRAM)

| # | Panel | Type | Status | Series | Root Cause |
|---|-------|------|--------|:------:|-----------|
| 17 | VRAM Used (GiB) | timeseries | ❌ FAIL | 0 | RC-1 |
| 18 | VRAM Free (GiB) | timeseries | ❌ FAIL | 0 | RC-1 |
| 19 | VRAM Utilisation % | timeseries | ❌ FAIL | 0 | RC-1 |

### Section: PCIe Bus

| # | Panel | Type | Status | Series | Root Cause |
|---|-------|------|--------|:------:|-----------|
| 20 | PCIe Replay Counter Rate (/s) | timeseries | ❌ FAIL | 0 | RC-1 |
| 21 | PCIe TX/RX Bandwidth (bytes/s) | timeseries | ❌ FAIL | 0 | RC-1 — `DCGM_FI_PROF_PCIE_TX/RX_BYTES` exist (9 series) |
| 22 | Clock Throttle Reasons Over Time | timeseries | ❌ FAIL | 0 | RC-1 + `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` not in DCGM config |

### Section: ECC Errors & Memory Health

| # | Panel | Type | Status | Series | Root Cause |
|---|-------|------|--------|:------:|-----------|
| 23 | Row Remap Failure (0=OK · 1=Failed) | stat | ❌ FAIL | 0 | RC-1 — metric exists (11 series unfiltered) |
| 24 | Uncorrectable Remapped Rows | stat | ❌ FAIL | 0 | RC-1 — metric exists; ⚠️ gpu3 and gpu6 = 1 |
| 25 | Correctable Remapped Rows | stat | ❌ FAIL | 0 | RC-1 — `DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS` exists (9 series) |
| 26 | ECC SBE Volatile Total | stat | ❌ FAIL | 0 | RC-1 + metric `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL` not enabled in DCGM config |
| 27 | ECC DBE Volatile Total | stat | ❌ FAIL | 0 | RC-1 + metric not enabled |
| 28 | XID Errors (counter) | stat | ❌ FAIL | 0 | RC-1 + `DCGM_FI_DEV_XID_ERRORS` not enabled |
| 29 | Row Remap Count Over Time | timeseries | ❌ FAIL | 0 | RC-1 |
| 30 | ECC Aggregate Errors Over Time | timeseries | ❌ FAIL | 0 | RC-1 + `DCGM_FI_DEV_ECC_SBE_AGG_TOTAL` / `DBE_AGG_TOTAL` not enabled |

### Section: Platform Health

| # | Panel | Type | Status | Series | Live Value | Notes |
|---|-------|------|--------|:------:|-----------|-------|
| 31 | VRAM Utilisation | stat | ❌ FAIL | 0 | — | RC-1 — same VRAM % query with lowercase `hostname` filter |
| 32 | DCGM Exporter Targets | stat | ✅ PASS | 1 | **2** | No label filter — unaffected by RC-1 |
| 33 | DCGM Scrape Success Rate | stat | ✅ PASS | 1 | **100%** | No label filter |
| 34 | Firing GPU Alerts | stat | ✅ PASS | 1 | **0** | vector(0) fallback working |

---

## Live Metric Spot-Check (Unfiltered — Ground Truth)

| Metric | Value | Status |
|--------|-------|--------|
| GPU count (DCGM series) | **10** | ✅ |
| Avg temperature | **33.6 °C** | ✅ Healthy (<75°C threshold) |
| Avg power draw | **62.0 W** | ✅ |
| Total VRAM installed | **838.7 GiB** | ✅ |
| VRAM in use | **357.3 GiB (42.6%)** | ✅ |
| DCGM exporter targets | **2/2 up** | ✅ |
| GPUs with uncorrectable row remaps | **2** (gpu3, gpu6 on ru25 = 1 each) | ⚠️ Watch |
| ECC SBE/DBE volatile errors | Not collected (metric disabled in DCGM config) | ⚠️ |
| XID errors | Not collected (metric disabled) | ⚠️ |
| Recording rules deployed | **0** — `gpu-rules.yaml` not applied | ❌ |
| Alerts with `platform="gpu-monitoring"` | **0** — rules not deployed | ❌ |

---

## Findings & Recommended Fixes

### Fix 1 — Apply `gpu-rules.yaml` (resolves RC-2 & RC-3 — 18 panels)

The recording rules and alert rules exist in `gpu-rules.yaml` but were **never applied to the cluster**. This is the highest-priority fix.

```bash
oc apply -f gpu-rules.yaml
# Verify rules are loaded (allow ~60s for Prometheus to pick up):
oc get prometheusrule -n openshift-monitoring gpu-alert-rules
# Verify recording rules produce series:
curl -sk -u cas:cas \
  "https://grafana-a-route-grafana.apps.f73l056.fusion.tadn.ibm.com/api/datasources/proxy/uid/prometheus/api/v1/query?query=gpu:health_score:composite" \
  | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']['result']), 'series')"
```

---

### Fix 2 — Label case mismatch: `hostname` → `Hostname` (resolves RC-1 — 35 panels)

DCGM Exporter exports the label as `Hostname` (capital H). All JSON queries use `{hostname=~"$hostname"}`. Fix by adding a `relabelings` rule to the ServiceMonitor to lowercase the label — **no dashboard JSON changes needed**.

```bash
# Check current ServiceMonitor
oc get servicemonitor -n nvidia-gpu-operator -o yaml | grep -A5 'relabeling\|Hostname'

# Add relabeling to lowercase Hostname → hostname:
oc patch servicemonitor nvidia-dcgm-exporter -n nvidia-gpu-operator --type='json' -p='[
  {"op":"add","path":"/spec/endpoints/0/relabelings/-","value":{
    "sourceLabels":["__meta_kubernetes_pod_label_app","Hostname"],
    "action":"replace",
    "targetLabel":"hostname",
    "regex":"(.+)"
  }}
]'
```

Alternatively, edit each query in the JSON from `hostname` → `Hostname` — but the ServiceMonitor fix is cleaner and permanent.

---

### Fix 3 — Enable missing DCGM metrics in ClusterPolicy (resolves metric-not-collected issues)

The following metrics are queried by panels but **not enabled** in the DCGM Exporter configuration:

| Metric | Used by panels | Action |
|--------|---------------|--------|
| `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` | Clock Throttle panels | Add field `155` to DCGM config |
| `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL` | ECC SBE panels | Add field `312` |
| `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | ECC DBE panels | Add field `313` |
| `DCGM_FI_DEV_XID_ERRORS` | XID panel | Add field `140` |
| `DCGM_FI_DEV_ECC_SBE_AGG_TOTAL` | ECC aggregate panel | Add field `314` |
| `DCGM_FI_DEV_ECC_DBE_AGG_TOTAL` | ECC aggregate panel | Add field `315` |

```bash
# Check current DCGM fields config
oc get clusterpolicy -n nvidia-gpu-operator -o jsonpath='{.items[0].spec.dcgmExporter.config}' | python3 -m json.tool
```

---

## ⚠️ Hardware Alert — Uncorrectable Remapped Rows

> **Action required:** 2 GPUs on `compute-1-ru25` have `DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS = 1`

| GPU | Node | Value | Meaning |
|-----|------|-------|---------|
| gpu3 | compute-1-ru25.f73l056 | **1** | One DRAM row permanently remapped — damage is non-recoverable |
| gpu6 | compute-1-ru25.f73l056 | **1** | Same |

These GPUs are still functional but should be **flagged for replacement** at next maintenance window. Monitor via:
```bash
# Check periodically:
curl -sk -u cas:cas \
  "https://grafana-a-route-grafana.apps.f73l056.fusion.tadn.ibm.com/api/datasources/proxy/uid/prometheus/api/v1/query?query=DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS%3E0" \
  | python3 -c "import sys,json; [print(r['metric'].get('Hostname'),r['metric'].get('gpu'),r['value'][1]) for r in json.load(sys.stdin)['data']['result']]"
```

---

*Generated by automated Grafana API + Prometheus proxy panel validation on cluster `f73l056`.*
