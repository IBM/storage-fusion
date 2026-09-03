# ISF Network Monitoring — Grafana Dashboard

This directory contains the Grafana dashboard for IBM Storage Fusion (ISF) network switch monitoring.

## Files

| File | Description |
|------|-------------|
| `ISF_Network_Monitoring_Alerts_Dashboard.json` | Grafana dashboard — network drill-down with active alert summary |

---

## Deploy the Grafana Dashboard

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

## Dashboard variables

The dashboard exposes three template variables used to filter panels:

| Variable | Source metric | Description |
|----------|--------------|-------------|
| `switch` | `isf_switches_info{name}` | Filter by one or more switch names |
| `rack` | `isf_switches_info{rack}` | Filter by rack |
| `port` | `ifOperStatus{ifName}` | Filter by port / interface name |

All variables support multi-select and default to **All** (`.*`).
