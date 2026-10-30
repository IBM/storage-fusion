# Secrets Management Guide

MaaS supports two modes of secrets management:
1. **External Secrets Operator (ESO) + HashiCorp Vault / AWS Secrets Manager** (Recommended for Production)
2. **Kubernetes Native Secrets** (Development / Testing)

---

## 1. External Secrets Operator (ESO) Mode

When `externalSecrets.enabled=true` in Helm values, the charts generate `ExternalSecret` custom resources referencing your cluster `ClusterSecretStore` or `SecretStore`.

### Architecture

```
┌─────────────────────────┐
│ Vault / Cloud KMS       │
│ secret/data/maas/s3     │
│ secret/data/maas/tokens │
└────────────┬────────────┘
             │ Synced by ESO Controller
┌────────────▼────────────┐
│ ExternalSecret CR       │ ──► Generates K8s Secret (e.g. s3-connection-secret)
└─────────────────────────┘
```

### Required Secret Keys in Vault

#### S3 Storage Credentials (`secret/data/maas/s3`)
```json
{
  "AWS_ACCESS_KEY_ID": "minioadmin",
  "AWS_SECRET_ACCESS_KEY": "minioadmin",
  "AWS_DEFAULT_REGION": "us-east-1",
  "AWS_S3_ENDPOINT": "http://minio.storage.svc:9000"
}
```

#### Hugging Face / Model Access Token (`secret/data/maas/tokens`)
```json
{
  "HF_TOKEN": "hf_xxxxxxxxxxxxxxxxxxxxxx"
}
```

---

## 2. Kubernetes Native Secrets Mode

When running without Vault, create secrets directly in your model and runtime namespaces:

### S3 Connection Secret
```bash
oc create secret generic s3-connection-secret \
  --from-literal=AWS_ACCESS_KEY_ID="minioadmin" \
  --from-literal=AWS_SECRET_ACCESS_KEY="minioadmin" \
  --from-literal=AWS_DEFAULT_REGION="us-east-1" \
  --from-literal=AWS_S3_ENDPOINT="http://minio.storage.svc:9000" \
  -n maas-models
```

### Hugging Face Token Secret
```bash
oc create secret generic huggingface-token \
  --from-literal=token="hf_xxxxxxxxxxxxxxxxxxxxxx" \
  -n maas-models
```
