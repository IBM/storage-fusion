# CAS Resource Configuration

Automation for configuring IBM CAS resources on OpenShift.

## What this script does

- Logs into OpenShift
- Creates a CAS DataSource
  - IBM Scale
  - AWS S3
- Creates a Domain and attaches the DataSource
- Creates a DocumentProcessor
  - NVIDIA multimodal
  - Docling multimodal
- Validates resource creation

---

## Prerequisites

- OpenShift CLI (`oc`) installed
- Access to OpenShift cluster
- CAS operator installed
- Namespace exists (default: `ibm-cas`)
- AWS secret pre-created if using S3

---

## Files

| File | Description |
|-----|------------|
| `create-cas-flow.sh` | Production automation script |
| `cas-config.env` | Configuration file |
| `README.md` | Documentation |

---

## Configuration

Create `cas-config.env`:

```bash
# OpenShift
OC_SERVER=https://api.ocp.example.com:6443
OC_TOKEN=sha256~XXXX

# Namespace
NAMESPACE=ibm-cas

# Resource names
DATASOURCE_NAME=cas-ds
DOMAIN_NAME=cas-domain
DOC_PROCESSOR_NAME=cas-doc-processor

# scale | aws
DATASOURCE_TYPE=scale

# IBM Scale
SCALE_FILESYSTEM_NAME=gpfs3
SCALE_PATH=/gpfs/gpfs3/cast

# AWS S3 (only if DATASOURCE_TYPE=aws)
AWS_BUCKET=my-bucket
AWS_ENDPOINT=https://s3.amazonaws.com
AWS_SECRET_NAME=aws-s3-secret
AWS_FILESYSTEM_NAME=s3-fs

# nvidia | docling
DOC_PROCESSOR_TYPE=nvidia
