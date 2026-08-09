# ISF Network Monitoring — Grafana Dashboard & Prometheus Alert Rules

This directory contains the Grafana dashboard and Prometheus alert rules for IBM Storage Fusion (ISF) network switch monitoring.

## Files

| File | Description |
|------|-------------|
| `ISF_Network_Monitoring_Alerts_Dashboard.json` | Grafana dashboard — network drill-down with active alert summary |
| `ISF_Network_Monitoring_Prometheus_Alert_Rules.yaml` | Kubernetes `PrometheusRule` CR — 6 alert rules for switch health |

---

## 1. Deploy the Grafana Dashboard

### Option A — Grafana UI (manual import)

1. Open your Grafana instance and navigate to **Dashboards → New → Import**.
2. Click **Upload dashboard JSON file** and select `ISF_Network_Monitoring_Alerts_Dashboard.json`.
3. Grafana will display an import screen and prompt you to map **"Prometheus"** to a datasource in your instance — select the appropriate Prometheus datasource from the dropdown.
4. Click **Import**.

### Option B — Grafana HTTP API

```bash
GRAFANA_URL="https://<your-grafana-host>"
GRAFANA_TOKEN="<your-service-account-token>"

curl -s -X POST \
  "${GRAFANA_URL}/api/dashboards/import" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -d "{
    \"dashboard\": $(cat ISF_Network_Monitoring_Alerts_Dashboard.json),
    \"overwrite\": true,
    \"inputs\": [{
      \"name\": \"DS_PROMETHEUS\",
      \"type\": \"datasource\",
      \"pluginId\": \"prometheus\",
      \"value\": \"<your-prometheus-datasource-name>\"
    }],
    \"folderId\": 0
  }"
```

Replace `<your-prometheus-datasource-name>` with the exact name of your Prometheus datasource as it appears in **Connections → Data sources**.

---

## 2. Apply the Prometheus Alert Rules on OpenShift (OCP)

The alert rules are packaged as a `PrometheusRule` custom resource targeting the `openshift-monitoring` namespace.

### Prerequisites

- OpenShift cluster with the Prometheus Operator (User Workload Monitoring or cluster monitoring) enabled.
- The `openshift-monitoring` namespace is a system namespace that already exists on any OCP cluster with cluster monitoring enabled — no setup needed.

### Apply

```bash
oc apply -f ISF_Network_Monitoring_Prometheus_Alert_Rules.yaml
```

### Verify the rules loaded

```bash
# Check the PrometheusRule was accepted
oc get prometheusrule isf-network-monitoring-alerts -n openshift-monitoring

# Check Prometheus has picked up the rules (may take up to 30s)
oc -n openshift-monitoring exec -it \
  $(oc -n openshift-monitoring get pod -l app.kubernetes.io/name=prometheus -o name | head -1) \
  -- promtool check rules /etc/prometheus/rules/*/network-monitoring-alerts.yaml
```

### Alert rules summary

| Alert | Severity | Threshold | For |
|-------|----------|-----------|-----|
| `SwitchMemoryHigh` | warning | Memory > 85% | 5 m |
| `SwitchMemoryCritical` | critical | Memory > 95% | 2 m |
| `SwitchCPUHigh` | warning | CPU > 80% | 5 m |
| `SwitchCPUCritical` | critical | CPU > 90% | 2 m |
| `SwitchTemperatureHigh` | warning | Max sensor > 70 °C | 5 m |
| `SwitchTemperatureCritical` | critical | Max sensor > 80 °C | 2 m |

### Remove the rules

```bash
oc delete prometheusrule isf-network-monitoring-alerts -n openshift-monitoring
```

---

## Dashboard variables

The dashboard exposes three template variables used to filter panels:

| Variable | Source metric | Description |
|----------|--------------|-------------|
| `switch` | `isf_switches_info{name}` | Filter by one or more switch names |
| `rack` | `isf_switches_info{rack}` | Filter by rack |
| `port` | `ifOperStatus{ifName}` | Filter by port / interface name |

All variables support multi-select and default to **All** (`.*`).
