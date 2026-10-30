# Air-Gapped / Disconnected Deployment Guide

In enterprise environments without direct internet connectivity, MaaS can be deployed completely air-gapped by pre-mirroring container images and staging model weights into internal object storage.

---

## 1. Mirror Container Images

All required images must be mirrored to an internal container registry (e.g. Quay Enterprise or OpenShift internal registry):

- **Serving Runtimes:**
  - `quay.io/modh/vllm:latest`
  - `registry.redhat.io/rhoai/odh-modelmesh-runtime-rhel9:latest`
- **Operators:**
  - Red Hat OpenShift AI Operator
  - Kuadrant Operator
  - Authorino Operator
  - cert-manager Operator

### ImageContentSourcePolicy / ImageDigestMirrorSet
Configure OpenShift to redirect public image pulls to your internal mirror:

```yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: maas-mirror
spec:
  imageDigestMirrors:
    - mirrors:
        - internal-registry.corp.local/rhoai/vllm
      source: quay.io/modh/vllm
```

---

## 2. Stage Model Weights into Internal S3 Storage

Do not download weights dynamically from Hugging Face in air-gapped clusters. Instead:

1. **Download model weights on a connected workstation:**
   ```bash
   huggingface-cli download ibm-granite/granite-3.1-8b-instruct --local-dir ./granite-3.1-8b
   ```

2. **Sync weights to internal S3 / IBM Storage Ceph:**
   ```bash
   aws s3 sync ./granite-3.1-8b s3://model-weights-bucket/granite-3.1-8b/ \
     --endpoint-url https://s3.internal.storage.corp.local
   ```

3. **Configure Model Helm values to use internal S3 storage:**
   ```yaml
   storage:
     type: s3
     bucket: model-weights-bucket
     path: granite-3.1-8b/
   ```
