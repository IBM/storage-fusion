## Steps to setup ACM Operator and add Custom dashboard to the Grafana
Use these instructions to enable multi-cluster observability for IBM Fusion clusters by using Red Hat® Advanced Cluster Management.

### ACM Operator Setup
Make sure that you meet the following prerequisites:
1. Install the ACM operator on your hub clusters. For the procedure, see Install Red Hat Advanced Cluster Management.
2. Make sure that you add all other IBM Fusion clusters to the ACM hub as managed clusters. For procedure Cluster management.
3. Make sure that you enable the ACMs observability stack to collect and visualize metrics. For procedure, see Observability.
4. Verify whether the observability stack is enabled as follows:
    1. Log in to the OpenShift® Container Platform web console where ACM is installed.
    2. Go to **Infrastructure** > **Clusters**.
    3. In the Clusters page, click the **Grafana** outbound arrow. The Grafana dashboard page opens.
    4. Verify whether the dashboards display metrics from all managed clusters.

If the metrics are visible across clusters, then the observability stack setup is successful.

### Add Custom Dashboards to the ACM's Grafana
Follow the instructions to include IBM Fusion dashboards in ACMs Grafana. With this setup in place, your Network Operations Center (NOC) team can use a centralized dashboard to monitor the health of various components across multiple IBM Fusion clusters.
1. Download the `metrics-custom-allowlist` and `ibm-fusion-fleet-dashboard` YAML files from above.
2. Run the following commands to apply the YAML files on the Hub cluster where the ACM is installed.
```
oc apply -f configmap-observability-metrics-custom-allowlist.yaml
oc apply -f ibm-fusion-fleet-dashboard.yaml
```

The first YAML adds IBM Fusion-specific metrics to the ACM allowlist.
The second YAML registers a custom dashboard that shows up in the ACM Grafana dashboard.

After the setup, open Grafana and go to `Dashboard > Customs`.
The IBM Fusion observability dashboard displays metrics from all managed clusters.
