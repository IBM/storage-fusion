# Operations & Troubleshooting Runbook

This guide covers operational maintenance, health verification, scaling, logging, and common failure modes for the MaaS platform.

---

## 1. Platform Health Verification

### Check Operator Status
```bash
oc get csv -n openshift-operators | grep -E "rhods|kuadrant|authorino|cert-manager"
```
*Expected Status: `Succeeded` for all ClusterServiceVersions.*

### Check DataScienceCluster (RHOAI)
```bash
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Should return "True"
```

### Check Ingress Gateway & Routing
```bash
oc get gateway,httproute -n maas-runtime
oc get route maas-gateway -n maas-runtime
```

---

## 2. Model Inference Service Diagnostics

### Check InferenceService Status
```bash
oc get llminferenceservice -n maas-models
# Or standard KServe
oc get inferenceservice -n maas-models
```

### Inspect Pod Logs (vLLM / Engine)
```bash
# Stream engine startup and weight loading logs
oc logs -n maas-models -l app.kubernetes.io/name=llminferenceservice -c kserve-container -f
```

### Common Inference Issues

| Symptom | Probable Cause | Remediation |
|---|---|---|
| `OOMKilled` or CUDA Out of Memory | `gpu.memoryUtilization` set too high or model too large for GPU VRAM | Decrease `gpu_memory_utilization` (e.g. `0.85`), enable quantization (FP8/AWQ), or increase `tensorParallelSize`. |
| `S3 connection refused / 403` | Invalid S3 credentials or bucket inaccessible | Check `s3-connection-secret` or ESO sync status in target namespace. |
| Model Pod in `Pending` | Insufficient GPU or CPU resources | Verify node resource allocations: `oc describe nodes \| grep -A 5 "Allocated resources"`. |

---

## 3. Governance & Rate Limiting Diagnostics

### Inspect Kuadrant AuthConfig & RateLimitPolicy
```bash
oc get authconfig -n maas-governance
oc get ratelimitpolicy -n maas-governance
oc logs -n kuadrant-system -l app.kubernetes.io/name=authorino -f
```

### Test API Key Authentication
```bash
GATEWAY=$(oc get route maas-gateway -n maas-runtime -o jsonpath='{.spec.host}')

# Test unauthenticated (expect 401 Unauthorized)
curl -k -i -X POST "https://${GATEWAY}/v1/chat/completions"

# Test with invalid key (expect 401/403)
curl -k -i -X POST "https://${GATEWAY}/v1/chat/completions" \
  -H "Authorization: Bearer invalid-key"
```

---

## 4. Teardown / Cleanup Runbook

To completely teardown runtime or model deployments safely:

```bash
# 1. Delete models first (to free GPU and PVC allocations)
helm uninstall model-granite-8b -n maas-models

# 2. Run runtime cleanup script
./runtime/scripts/cleanup-runtime.sh
```
