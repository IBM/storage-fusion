# Pod Resource Recommendation and Patch Tool

This toolkit analyzes CPU and memory usage for pods in an OpenShift namespace using Prometheus metrics. It generates resource recommendations and provides scripts to apply those recommendations to Deployments, StatefulSets, and CSV-managed pods.

> **Does not cover Kafka/Strimzi pods.** This tool does **not** produce resource recommendations for Kafka or Strimzi-managed pods (brokers, ZooKeeper, entity operator, Connect, Bridge, MirrorMaker, etc.) — they are fully excluded from analysis and patching. See [Exclusions](#exclusions) for why. If you need right-sizing for Kafka/Strimzi workloads, that has to be done separately (manual review, or a tool with JVM-aware sizing).

## Features

- Analyzes pod CPU and memory usage based on actual Prometheus metrics
- Considers only pods running for more than 24 hours (override with `--force`)
- **Excludes Kafka/Strimzi-managed pods entirely** — no recommendation, no patch entry (see [Exclusions](#exclusions))
- Produces an Excel report and console summary
- Generates a JSON patch file for workloads requiring updates
- Provides a patch script to apply recommendations safely (dry-run by default)
- Automatically sets up Python virtual environment and required libraries

## Recommendation Rules

Requests and limits are **not** a flat percentage of the current value. They're computed from observed P95/max usage over the analysis window, with workload-specific headroom multipliers and 20% hysteresis to avoid recommendation churn on minor fluctuations.

**Container classes**

| Class | Detection | Notes |
|---|---|---|
| Proxy/sidecar | Container name matches a proxy pattern (`*rbac-proxy*`, etc.) | Higher CPU/mem floors — latency-critical |
| App | Everything else | Default policy |

There is currently no separate JVM/Kafka class — see [Exclusions](#exclusions).

**App policy (defaults, overridable via env vars)**

| | Request | Limit |
|---|---|---|
| CPU | `P95 usage × 1.20` (floor 50m) | `max(request × 1.50, 100m)`, raised further on sustained throttling |
| Memory | `P95 usage × 1.10` (floor 64Mi) | `max(request × 1.50, max_usage × 1.30, 128Mi)`, raised further on OOM (×2.0) or sustained pressure (P95 ≥ 85% of limit) |

**Proxy/sidecar policy** uses the same shape with wider floors (100m/200m CPU, 128Mi/256Mi memory) and a lower CPU request headroom (×1.10) since these containers are usually latency-bound rather than throughput-bound.

**Hysteresis:** a change is only recommended if it differs from the current value by ≥ 20%; smaller deltas are left as-is.

**Additional notes:**
- Analysis uses the last 15 days of Prometheus data, at 5-minute query resolution. Short bursts (e.g. JVM startup spikes lasting under a few minutes) are smoothed by this resolution and may not be reflected in the recommendation, regardless of how much history is available.
- Ephemeral storage recommendations are not yet supported.

## Exclusions

### Kafka / Strimzi-managed pods

Any pod matched by name (`kafka`, `zookeeper`, `entity-operator`, `strimzi`) or by a Strimzi label (`strimzi.io/cluster`, `strimzi.io/kind`, `strimzi.io/name`) is **excluded from analysis entirely** — no Excel row, no patch entry, regardless of pod age or `--force`. The tool prints the excluded pod names to the console.

This exists because these are JVM workloads with startup resource needs (JIT compilation, heap/metaspace initialization) that the tool's P95/max-based model has no way to represent, and because a specific incident showed the risk directly: applying this tool's recommendation to a Strimzi entity-operator container (`user-operator`) cut its CPU limit by 80% and memory limit by ~81%, causing `CrashLoopBackOff` on startup. Reverting to the original values resolved it.

**Note on CRD ownership:** the tool's workload-grouping logic (`workload_of()`) only classifies a pod as CRD-managed — and therefore normally excluded from patching by the general CRD-skip rule below — when its **direct** Kubernetes owner reference is `StrimziPodSet` or a `Kafka*` kind. A pod whose direct owner is a `ReplicaSet`/`Deployment` (even if that Deployment was itself created by the Strimzi Cluster Operator, as with the entity operator) is **not** caught by that rule and is treated as an ordinary Deployment. This is exactly the gap the Kafka/Strimzi exclusion above closes — do not rely on CRD-ownership detection alone to keep Strimzi components safe.

### Legacy CRD-grouping logic (superseded for Kafka/Strimzi)

The script's `workload_of()` function still recognizes pods whose **direct** owner is `Kafka`, `KafkaConnect`, `KafkaMirrorMaker`, `KafkaMirrorMaker2`, `KafkaBridge`, or `StrimziPodSet`, and groups them under a `Strimzi/<name>` workload key. Before the Kafka/Strimzi exclusion above existed, this was the mechanism that kept such pods out of `pod-res-apply.sh` patching, while still showing their computed (but unapplied) recommendation in the Excel report.

**This no longer applies to Kafka/Strimzi pods in practice.** The name/label exclusion described above runs earlier in the script and drops these pods from `allowed_pods` before any report row is built — every place the Excel/console data is assembled filters on `allowed_pods` (see `pod-res-recommend.sh`, the `df["Pod"].isin(allowed_pods)` filters). So a pod owned directly by one of these CRD kinds is now excluded outright, the same as every other Kafka/Strimzi pod: no Excel row, no patch entry. It does not fall back to "shown but not patched."

This grouping code is left in place only because it's harmless and would matter again if the exclusion patterns above were ever narrowed or the label check removed. It is not an active safety mechanism today — don't rely on it.

## Scripts Included

### 1. pod-res-recommend.sh
Generates resource usage reports and recommendations for all eligible pods in a namespace.

### 2. pod-res-apply.sh
Applies the generated recommendations to selected workload types (dry-run by default).

## Dependencies

| Dependency | Purpose |
|------------|---------|
| Python 3.9+ | Runs the analysis logic and generates Excel reports. Automatically installs numpy, pandas, openpyxl, xlsxwriter, and tabulate. |
| jq | Performs JSON filtering and transformation. |
| oc | Communicates with the OpenShift cluster. |

## Generating Recommendations

### Command
```
./pod-res-recommend.sh <namespace> [options]
```

### Examples
```
./pod-res-recommend.sh ibm-backup-restore
./pod-res-recommend.sh ibm-backup-restore --mem-only
./pod-res-recommend.sh ibm-backup-restore --cpu-only
./pod-res-recommend.sh ibm-backup-restore --force
```

### Output Files (Saved under /tmp)

| File | Description |
|------|-------------|
| /tmp/usage_report_\<namespace\>_15d.xlsx | Excel report with usage data and recommendations |
| /tmp/pods_to_patch_\<namespace\>.json | JSON file containing updated requests and limits |

## Applying Recommendations

### Dry-run mode (default)
```
./pod-res-apply.sh /tmp/pods_to_patch_<namespace>.json
```

### Apply changes (persist updates)
```
./pod-res-apply.sh /tmp/pods_to_patch_<namespace>.json -p
```

### Optional Filters

| Flag | Description |
|------|-------------|
| --deploy-only | Patch only Deployments |
| --sts-only | Patch only StatefulSets |
| --deploy-sts-only | Patch Deployments and StatefulSets |
| --deploy-csv-only | Patch Deployments and CSV-managed pods |

## Recommended Workflow

1. Run pod-res-recommend.sh to generate recommendations.
2. Review the Excel and console output. Check the console notice for any Kafka/Strimzi pods that were excluded.
3. Run pod-res-apply.sh to apply the recommendations.
4. Monitor rollout using:
```
oc get pods -n <namespace>
```
