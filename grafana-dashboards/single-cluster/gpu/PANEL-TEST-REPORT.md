# GPU dashboards - end-to-end panel test

Run against `https://grafana-a-route-grafana.apps.f73l056.fusion.tadn.ibm.com` (datasource uid `prometheus`).

- Scenario ALL: 2 hosts, 10 GPUs. Scenario ONE: `compute-1-ru25.f73l056.fusion.tadn.ibm.com` / `GPU-211307ce-d30b-a533-1e12-4a864a1a2a54`
- Panels tested: 65; dynamic failures: 0; checklist failures: 0
- Panels with no series in ALL: 6 (expected for exceptions-only panels and metrics this exporter does not export)

## Dynamic results

| Dashboard | ID | Type | Panel | Series ALL | Series ONE | State (ALL) | Links | Deployed==file | Result |
|---|---|---|---|---|---|---|---|---|---|
| gpu-cluster-overview-v8 | 1 | stat | Total GPU Count | 1 | 1 | 10 -> text | ok | same | PASS |
| gpu-cluster-overview-v8 | 2 | gauge | Avg GPU Health Score | 1 | 1 | 99.1 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 3 | stat | Healthy GPUs (score ≥ 80) | 1 | 1 | 10 -> text | ok | same | PASS |
| gpu-cluster-overview-v8 | 4 | stat | Warning GPUs (60–79) | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 5 | stat | Critical GPUs (< 60) | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 6 | stat | Failure risk > 30% (24h) | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 7 | stat | VRAM Utilisation | 1 | 1 | 43.1617 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 8 | stat | Avg GPU Temp (°C) | 1 | 1 | 32.8 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 12 | stat | DCGM Targets Up | 1 | 1 | 2 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 107 | stat | Total Firing GPU Alerts | 1 | 1 | 1 -> orange | ok | same | PASS |
| gpu-cluster-overview-v8 | 13 | stat | Critical Alerts | 1 | 1 | 1 -> red | ok | same | PASS |
| gpu-cluster-overview-v8 | 14 | stat | Warning Alerts | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 15 | stat | Node Alerts | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 16 | stat | Hardware Alerts | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 17 | stat | Thermal / Power Alerts | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 18 | stat | Memory Alerts | 1 | 1 | 1 -> orange | ok | same | PASS |
| gpu-cluster-overview-v8 | 19 | stat | Predictive Alerts | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 20 | stat | Impact Alerts | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 21 | table | All Firing GPU Alerts | 1 | 1 | 1 series | ok | same | PASS |
| gpu-cluster-overview-v8 | 22 | table | Per-GPU Health Score, Failure Probability & VRAM | 31 | 27 | 31 series | ok | same | PASS |
| gpu-cluster-overview-v8 | 23 | bargauge | Row Remap FAILED — affected GPUs only | 0 | 0 | - | ok | same | PASS |
| gpu-cluster-overview-v8 | 24 | bargauge | Uncorrectable Remapped Rows — affected GPUs only | 2 | 0 | 1 -> red | ok | same | PASS |
| gpu-cluster-overview-v8 | 25 | table | GPU Utilisation by Workload — Namespace · Pod · Device | 11 | 1 | 11 series | - | same | PASS |
| gpu-cluster-overview-v8 | 26 | timeseries | GPU Utilisation — All Devices | 12 | 1 | 12 series | - | same | PASS |
| gpu-cluster-overview-v8 | 27 | timeseries | GPU Temperature — All Devices | 12 | 1 | 12 series | ok | same | PASS |
| gpu-cluster-overview-v8 | 28 | timeseries | Power Draw — All Devices | 12 | 1 | 12 series | ok | same | PASS |
| gpu-cluster-overview-v8 | 29 | timeseries | Composite Health Score Trend | 10 | 1 | 10 series | ok | same | PASS |
| gpu-cluster-overview-v8 | 30 | stat | Pods on Failed GPU Nodes | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 32 | stat | Pods on At-Risk GPU Nodes (>30% 24h failure prob) | 1 | 1 | 0 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 31 | stat | DCGM Scrape Success | 1 | 1 | 1 -> green | ok | same | PASS |
| gpu-cluster-overview-v8 | 40 | stat | GPU Scoring & Alert Rules | 1 | 1 | 1 -> green | - | same | PASS |
| gpu-sre-dashboard-v5 | 1 | gauge | Composite Health Score | 10 | 1 | 100 -> green | ok | same | PASS |
| gpu-sre-dashboard-v5 | 2 | gauge | 24h Failure Probability % | 10 | 1 | 0 -> green | ok | same | PASS |
| gpu-sre-dashboard-v5 | 3 | stat | Throttle Pressure Score | 10 | 1 | 0 -> green | ok | same | PASS |
| gpu-sre-dashboard-v5 | 4 | stat | SM Clock (MHz) | 10 | 1 | 180 -> text | - | same | PASS |
| gpu-sre-dashboard-v5 | 5 | stat | Clock Throttle Reasons (bitmask) | 0 | 0 | - | ok | same | PASS |
| gpu-sre-dashboard-v5 | 6 | stat | Memory Clock (MHz) | 10 | 1 | 405 -> text | - | same | PASS |
| gpu-sre-dashboard-v5 | 7 | timeseries | Health Score Trend | 10 | 1 | 10 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 8 | timeseries | Failure Probability Trend | 10 | 1 | 10 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 9 | table | Firing GPU Alerts — All (cluster-level alerts have no hostname/UUID) | 1 | 1 | 1 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 10 | timeseries | GPU Core Temperature (°C) | 12 | 1 | 12 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 11 | timeseries | Memory (HBM) Temperature (°C) | 12 | 1 | 12 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 12 | timeseries | Power Draw (W) | 12 | 1 | 12 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 13 | timeseries | Power Instability — 15m Rolling Stddev | 10 | 1 | 10 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 14 | timeseries | GPU Compute Utilisation (%) | 12 | 1 | 12 series | - | same | PASS |
| gpu-sre-dashboard-v5 | 15 | timeseries | GR Engine Active & Tensor Core Active (0–1) | 24 | 2 | 24 series | - | same | PASS |
| gpu-sre-dashboard-v5 | 16 | timeseries | DRAM Bandwidth Active (0–1) | 12 | 1 | 12 series | - | same | PASS |
| gpu-sre-dashboard-v5 | 17 | timeseries | VRAM Used (GiB) | 12 | 1 | 12 series | - | same | PASS |
| gpu-sre-dashboard-v5 | 18 | timeseries | VRAM Free (GiB) | 12 | 1 | 12 series | - | same | PASS |
| gpu-sre-dashboard-v5 | 19 | timeseries | VRAM Utilisation % | 12 | 1 | 12 series | - | same | PASS |
| gpu-sre-dashboard-v5 | 20 | timeseries | PCIe Replay Counter Rate (/s) | 10 | 1 | 10 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 21 | timeseries | PCIe TX/RX Bandwidth (bytes/s) | 20 | 2 | 20 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 22 | timeseries | Clock Throttle Reasons Over Time | 0 | 0 | - | ok | same | PASS |
| gpu-sre-dashboard-v5 | 23 | stat | Row Remap Failure (0=OK · 1=Failed) | 11 | 1 | 0 -> green | ok | same | PASS |
| gpu-sre-dashboard-v5 | 24 | stat | Uncorrectable Remapped Rows | 11 | 1 | 0 -> green | ok | same | PASS |
| gpu-sre-dashboard-v5 | 25 | stat | Correctable Remapped Rows | 11 | 1 | 0 -> green | ok | same | PASS |
| gpu-sre-dashboard-v5 | 26 | stat | ECC SBE Volatile Total | 0 | 0 | - | ok | same | PASS |
| gpu-sre-dashboard-v5 | 27 | stat | ECC DBE Volatile Total | 0 | 0 | - | ok | same | PASS |
| gpu-sre-dashboard-v5 | 28 | stat | XID Errors (counter) | 13 | 1 | 43 -> red | ok | same | PASS |
| gpu-sre-dashboard-v5 | 29 | timeseries | Row Remap Count Over Time | 24 | 2 | 24 series | ok | same | PASS |
| gpu-sre-dashboard-v5 | 30 | timeseries | ECC Aggregate Errors Over Time | 0 | 0 | - | ok | same | PASS |
| gpu-sre-dashboard-v5 | 31 | stat | GPU Scoring & Alert Rules | 1 | 1 | 1 -> green | - | same | PASS |
| gpu-sre-dashboard-v5 | 32 | stat | DCGM Exporter Targets | 1 | 1 | 2 -> green | ok | same | PASS |
| gpu-sre-dashboard-v5 | 33 | stat | DCGM Scrape Success Rate | 1 | 1 | 1 -> green | ok | same | PASS |
| gpu-sre-dashboard-v5 | 34 | stat | Firing GPU Alerts | 1 | 1 | 1 -> red | ok | same | PASS |

## Valence checklist, alert alignment and variables

| Dashboard | Item | Finding | Result |
|---|---|---|---|
| gpu-cluster-overview-v8 | variable $hostname | 2 values | PASS |
| gpu-cluster-overview-v8 | variable $UUID | 10 values | PASS |
| gpu-cluster-overview-v8 | #1 Total GPU Count | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #2 Avg GPU Health Score | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #3 Healthy GPUs (score ≥ 80) | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #4 Warning GPUs (60–79) | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #5 Critical GPUs (< 60) | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #6 Failure risk > 30% (24h) | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #7 VRAM Utilisation | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #8 Avg GPU Temp (°C) | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #12 DCGM Targets Up | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #107 Total Firing GPU Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #13 Critical Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #14 Warning Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #15 Node Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #16 Hardware Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #17 Thermal / Power Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #18 Memory Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #19 Predictive Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #20 Impact Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #21 All Firing GPU Alerts | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #22 Per-GPU Health Score, Failure Probabilit | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #23 Row Remap FAILED — affected GPUs only | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #24 Uncorrectable Remapped Rows — affected G | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #25 GPU Utilisation by Workload — Namespace  | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #26 GPU Utilisation — All Devices | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #27 GPU Temperature — All Devices | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #28 Power Draw — All Devices | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #29 Composite Health Score Trend | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #30 Pods on Failed GPU Nodes | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #32 Pods on At-Risk GPU Nodes (>30% 24h fail | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #31 DCGM Scrape Success | valence+alignment ok | PASS |
| gpu-cluster-overview-v8 | #40 GPU Scoring & Alert Rules | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | variable $hostname | 2 values | PASS |
| gpu-sre-dashboard-v5 | variable $UUID | 10 values | PASS |
| gpu-sre-dashboard-v5 | #1 Composite Health Score | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #2 24h Failure Probability % | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #3 Throttle Pressure Score | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #4 SM Clock (MHz) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #5 Clock Throttle Reasons (bitmask) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #6 Memory Clock (MHz) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #7 Health Score Trend | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #8 Failure Probability Trend | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #9 Firing GPU Alerts — All (cluster-level a | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #10 GPU Core Temperature (°C) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #11 Memory (HBM) Temperature (°C) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #12 Power Draw (W) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #13 Power Instability — 15m Rolling Stddev | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #14 GPU Compute Utilisation (%) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #15 GR Engine Active & Tensor Core Active (0 | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #16 DRAM Bandwidth Active (0–1) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #17 VRAM Used (GiB) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #18 VRAM Free (GiB) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #19 VRAM Utilisation % | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #20 PCIe Replay Counter Rate (/s) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #21 PCIe TX/RX Bandwidth (bytes/s) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #22 Clock Throttle Reasons Over Time | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #23 Row Remap Failure (0=OK · 1=Failed) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #24 Uncorrectable Remapped Rows | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #25 Correctable Remapped Rows | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #26 ECC SBE Volatile Total | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #27 ECC DBE Volatile Total | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #28 XID Errors (counter) | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #29 Row Remap Count Over Time | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #30 ECC Aggregate Errors Over Time | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #31 GPU Scoring & Alert Rules | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #32 DCGM Exporter Targets | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #33 DCGM Scrape Success Rate | valence+alignment ok | PASS |
| gpu-sre-dashboard-v5 | #34 Firing GPU Alerts | valence+alignment ok | PASS |
