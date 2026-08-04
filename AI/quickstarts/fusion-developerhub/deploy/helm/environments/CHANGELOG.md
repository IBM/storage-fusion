# Changelog - Fusion Developer Hub Environments

All notable changes to the Fusion Developer Hub environment configurations will be documented in this file.

---

## v2 (July 2026) - CAS/DCS Integration — CURRENT
**Date:** 2026-07-01

### Added
- IBM Fusion CAS (Content Aware Storage) and DCS (Data Cataloging Service) self-service Backstage templates
- TechDocs for CAS and DCS covering API, architecture, MCP server, onboarding, and troubleshooting
- Multi-cluster catalog support — cluster entities generated from `fusionServices.clusters[]` values
- Platform Domain / System / Group entities (`fusion-ai-platform-entities` ConfigMap)
- GitHub Enterprise integration: `catalog.github.enterpriseHost`, `auth.github.enterpriseInstanceUrl`
- New homepage icon set: `ai-models-icon.png`, `ibm-blue.svg`, `redhat-red.svg`, `nvidia-green.svg`
- `fusionServices.enabled` guard — all CAS/DCS content off by default (`false`) in dev and staging

### Changed
- Welcome card grid height: h:2 → h:4/h:5 (taller layout)
- Default `welcomeTitle` changed to "Streamline Development with Fusion Developer Hub"
- `auth.environment` string key added; falls back to legacy `auth.guest.enabled` path if not set

### Migration from v1 to v2

> **IMPORTANT — read before upgrading an existing cluster**

#### 1. Helm chart path changed
The Helm chart was reorganised from `helm-charts/fusion-developer-hub/` to `deploy/helm/`.
Any ArgoCD Application pointing to the old path **must be updated** before syncing:

```yaml
# Old path
spec:
  source:
    path: quickstarts/fusion-developerhub/helm-charts/fusion-developer-hub

# New path
spec:
  source:
    path: quickstarts/fusion-developerhub/deploy/helm
```

#### 2. Homepage icon ConfigMap schema changed
`community-icon.png` was removed and replaced by four new icon files.
The `home-quick-access` ConfigMap now carries `helm.sh/resource-policy: replace` to
ensure Helm replaces it on upgrade instead of patching in-place (which would leave stale keys).

For **GitOps (ArgoCD)** deployments, `Replace=true` is set in the syncOptions of the
Application CR — no manual action required.

For **manual Helm upgrades** on existing clusters, run once before upgrading:
```bash
oc delete cm <instance-name>-home-quick-access -n <namespace> --ignore-not-found
helm upgrade fusion-developer-hub ./deploy/helm \
  -n <namespace> \
  -f deploy/helm/environments/prod/values.yaml
```

#### 3. CAS/DCS features are off by default
`fusionServices.enabled` defaults to `false` in the base `values.yaml` and is explicitly
set to `false` in `dev/` and `staging/` environment values.
Existing deployments that do not set `fusionServices.enabled: true` are unaffected.

---

## Configuration Structure

```
fusion-developer-hub/
├── values.yaml                    # Base defaults (required)
└── environments/
    ├── dev/values.yaml           # Development overrides
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

### v1 (June 2026) - CURRENT
**Date:** 2026-06-24

#### Added
- Environment-specific values structure (`dev/`, `staging/`, `prod/`)
- GitOps-based deployment support via ArgoCD Applications
- Fusion-specific customizations:
  - Custom homepage with Fusion branding
  - NVIDIA blueprints integration
  - Fusion quickstarts and documentation
  - Model catalog with automatic RHOAI discovery
  - Self-service application templates
- Environment-specific sync policies:
  - Dev: Automated sync with self-heal
  - Staging: Automated sync with self-heal
  - Prod: Manual sync for controlled releases

#### Changed
- Directory structure: Moved from root-level `environments/` to `deploy/helm/environments/`
- GitOps applications: Updated to reference new environment paths
- Documentation: Restructured QUICKSTART.md with GitOps deployment section

#### Enhanced
- Homepage customization with Fusion logo and branding
- Quick access cards for common tasks
- Integrated documentation and resources
- Model catalog with deployed AI models visibility

---

### v0 (May 2026) - BASELINE
**Date:** 2026-05-01  
**Files:** 
- `dev/values-v0-may2026.yaml`
- `staging/values-v0-may2026.yaml`
- `prod/values-v0-may2026.yaml`

#### Initial Release
- Basic Developer Hub deployment
- PostgreSQL database integration
- RHOAI connector setup
- Standard Backstage configuration
- Single deployment approach (Helm-only)

---

## Rollback

### Rollback Specific Environment
```bash
# Rollback to previous version
git checkout HEAD~1 -- environments/dev/values.yaml

# Rollback to v0 baseline
cp environments/dev/values-v0-may2026.yaml environments/dev/values.yaml
```

### Rollback All Environments
```bash
# Restore all environments to v0
cp environments/dev/values-v0-may2026.yaml environments/dev/values.yaml
cp environments/staging/values-v0-may2026.yaml environments/staging/values.yaml
cp environments/prod/values-v0-may2026.yaml environments/prod/values.yaml
```

---

## Migration Notes

### From v0 to v1

**Key Changes:**
1. New directory structure under `deploy/helm/`
2. GitOps deployment option added
3. Fusion customizations enabled by default
4. Environment-specific sync policies

**Migration Steps:**
1. Review new environment structure in `deploy/helm/environments/`
2. Update GitOps applications to reference new paths
3. Customize environment-specific values as needed
4. Test in dev environment before promoting to staging/prod

---

## Best Practices

1. **Always test in dev first** before promoting changes to staging/prod
2. **Use version control** for all environment value changes
3. **Document significant changes** in this CHANGELOG
4. **Keep archived versions** in `{env}/values-v{X}-{date}.yaml` format
5. **Review diffs carefully** when updating production values