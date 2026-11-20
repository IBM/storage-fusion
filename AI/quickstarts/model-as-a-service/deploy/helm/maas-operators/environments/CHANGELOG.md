# Changelog - MaaS Operators

All notable changes to the MaaS Operators configuration will be documented in this file.

## Configuration Structure

```
maas-operators/
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


---

## Version History

### v2 (September 2026) - CURRENT
**Date:** 2026-09-30

#### Changed
- OpenShift AI channel: `beta` → `stable-3.x`
- OpenShift AI startingCSV: `rhods-operator.3.5.0-ea.x` → `rhods-operator.3.5.0` (GA release)
- `maas-operators` Helm chart `version` and `appVersion`: `2.0.0` → `2.1.0` (`Chart.yaml`)

#### Archived
- `environments/dev/values-v1-aug2026.yaml`
- `environments/staging/values-v1-aug2026.yaml`
- `environments/prod/values-v1-aug2026.yaml`

---

### v1 (June 2026)
**Date:** 2026-06-24

#### Added
- Environment-specific values structure
- Dev: Grafana disabled to save resources
- Staging/Prod: Manual sync policies

#### Changed
- OpenShift AI channel: `fast-3.x` → `stable-3.x`
- Directory: `versions/` → `environments/`

---

### v0 (May 2026) - BASELINE
**Date:** 2026-05-01  
**File:** `values-v0-may2026.yaml`

#### Initial Release
- OpenShift AI: `fast-3.x` channel
- All operators with `Automatic` install plan approval

---

## Rollback

```bash
# Rollback specific environment
git checkout HEAD~1 -- environments/dev/values.yaml

# Rollback to v0 (single file)
cp environments/values-v0-may2026.yaml ../values.yaml