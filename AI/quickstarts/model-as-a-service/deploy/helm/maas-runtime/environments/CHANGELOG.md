# Changelog - MaaS Runtime

All notable changes to the MaaS Runtime configuration will be documented in this file.

## Configuration Structure

```
maas-runtime/
├── values.yaml                    # Base defaults (required)
└── environments/
    ├── dev/values.yaml           # Dev overrides
    ├── staging/values.yaml       # Staging overrides
    └── prod/values.yaml          # Production overrides
```

**How it works:**
- Base `values.yaml` contains defaults for all environments
- Environment files only override what's different
- Helm merges base + environment values automatically

---

## How to Update Values

### Update All Environments
Edit `../values.yaml` for changes affecting all environments.

### Update Specific Environment
Edit `environments/{env}/values.yaml` for environment-specific changes.

**Example:**
```yaml
# environments/dev/values.yaml
monitoring:
  grafana:
    enabled: false  # Override base value (true) for dev only
```

---

## Version History

### v1 (June 2026) - CURRENT
**Date:** 2026-06-24

#### Added
- Environment-specific values structure
- Dev/Staging/Prod environment configurations

#### Configuration
- Gateway API: OpenShift AI Inference gateway enabled
- Tier-based access control: Free, Premium, Enterprise tiers
- Monitoring: Grafana dashboards and cluster monitoring
- Model Registry: IBM Fusion Object Storage integration
- RBAC: Model service account configured

---

### v0 (May 2026) - BASELINE
**Date:** 2026-05-01

#### Initial Release
- Gateway API configuration for model access
- Tier-based rate limiting (free, premium, enterprise)
- Monitoring stack with Grafana integration
- Model Registry with automatic bucket creation
- RBAC and authentication setup

---

## Rollback

```bash
# Rollback specific environment
git checkout HEAD~1 -- environments/dev/values.yaml

# Rollback to v0 (single file)
cp environments/values-v0-may2026.yaml ../values.yaml