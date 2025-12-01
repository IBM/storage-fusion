# Pod Resource Recommendation and Patch Tool

This toolkit analyzes CPU and memory usage for pods in an OpenShift namespace using Prometheus metrics. It generates resource recommendations and provides scripts to apply those recommendations to Deployments, StatefulSets, and CSV-managed pods.

## Features

- Analyzes pod CPU and memory usage based on actual Prometheus metrics
- Considers only pods running for more than 24 hours (override with `--force`)
- Produces an Excel report and console summary
- Generates a JSON patch file for workloads requiring updates
- Provides a patch script to apply recommendations safely (dry-run by default)
- Automatically sets up Python virtual environment and required libraries

## Recommendation Rules

| Resource Type | Condition | Recommended Change |
|---------------|-----------|--------------------|
| CPU / Memory Request | Max usage < 50% of current request | Set request to 50% of current value |
| CPU / Memory Limit | Max usage < 50% of current limit | Set limit to 75% of current value |

Additional notes:
- Analysis uses the last 15 days of Prometheus data.
- Pods owned by custom resources are included in the report but skipped during patching.
- Ephemeral storage recommendations are not yet supported.

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
| /tmp/usage_report_<namespace>_15d.xlsx | Excel report with usage data and recommendations |
| /tmp/pods_to_patch_<namespace>.json | JSON file containing updated requests and limits |

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
2. Review the Excel and console output.
3. Run pod-res-apply.sh to apply the recommendations.
4. Monitor rollout using:
```
oc get pods -n <namespace>
```
