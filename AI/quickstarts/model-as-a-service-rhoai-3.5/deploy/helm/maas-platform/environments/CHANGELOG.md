# Changelog - MaaS Platform

All notable changes to the MaaS Platform configuration will be documented in this file.

## Configuration Structure

```
maas-platform/
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
dataScienceCluster:
  components:
    trustyai:
      managementState: Removed  # Override base value (Managed) for dev only
```

---

## Version History

### v1 (June 2026) - CURRENT
**Date:** 2026-06-24

#### Added
- Environment-specific values structure
- Dev/Staging/Prod environment configurations

#### Configuration
- DataScienceCluster: Enabled with default-dsc
- Platform Kuadrant: Enabled in kuadrant-system namespace
- Leader Worker Set: Enabled in openshift-lws-operator namespace

---

### v0 (May 2026) - BASELINE
**Date:** 2026-05-01

#### Initial Release
- DataScienceCluster configuration with all components
- Kuadrant platform integration
- Leader Worker Set operator instance

---

## Rollback

```bash
# Rollback specific environment
git checkout HEAD~1 -- environments/dev/values.yaml

# Rollback to v0 (single file)
cp environments/values-v0-may2026.yaml ../values.yaml