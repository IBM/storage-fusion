# Version Management Guide

This document describes the versioning strategy for Fusion Developer Hub configuration files.

## 📁 Directory Structure

```
deploy/helm/
├── values.yaml                        # Base configuration (template)
├── Chart.yaml
├── templates/
└── environments/
    └── prod/
        ├── values.yaml                # CURRENT/ACTIVE production overrides
        ├── value-v0-may2026.yaml      # May 2026 baseline
        └── value-v1-june2026.yaml     # June 2026 (future archive)
```

## 🎯 Versioning Strategy

### Core Principles

1. **`values.yaml` is always CURRENT** - Base template with all defaults
2. **`environments/prod/values.yaml` is CURRENT production** - Active production overrides
3. **Archive before changes** - Copy current prod values to versioned file before updates
4. **Clear naming** - Use semantic versioning with date: `value-v{N}-{month}{year}.yaml`
5. **Minimal overrides** - Production file contains only necessary overrides

### Why This Approach?

✅ **Zero ArgoCD changes** - Applications always point to `values.yaml` and `environments/prod/values.yaml`  
✅ **Complete history** - All versions preserved with dates  
✅ **Easy rollback** - Simple file copy operation  
✅ **Clean structure** - Active files separate from archives  
✅ **Audit trail** - Git history + archived files  

## 🔄 Monthly Update Workflow

### Step 1: Archive Current Version

Before making any changes, archive the current production configuration:

```bash
# Navigate to production directory
cd quickstarts/fusion-developerhub/deploy/helm/environments/prod

# Archive current version with date
cp values.yaml value-v1-june2026.yaml
```

### Step 2: Update Production values.yaml

Make your changes to `environments/prod/values.yaml`:

```yaml
# Example: Update PostgreSQL configuration
developerHub:
  database:
    instances: 3  # Changed from 1
    backup:
      enabled: true  # Changed from false
```

### Step 3: Commit Changes

```bash
# Add all changes
git add environments/prod/

# Commit with descriptive message
git commit -m "chore: Archive v1 (June 2026) and update to v2 (July 2026)

Changes:
- PostgreSQL HA: 3 instances
- Enabled automated backups

Archived version:
- value-v1-june2026.yaml"

# Push to repository
git push origin main
```

### Step 4: ArgoCD Auto-Sync

ArgoCD will automatically detect the changes to `values.yaml` and sync:

```bash
# Monitor sync status
kubectl get applications -n openshift-gitops

# Check specific application
kubectl describe application fusion-developer-hub -n openshift-gitops
```

## 🔙 Rollback Procedure

### Quick Rollback

To rollback to a previous version:

```bash
# Copy archived version back to current
cp environments/prod/value-v1-june2026.yaml \
   environments/prod/values.yaml

# Commit the rollback
git add environments/prod/values.yaml
git commit -m "rollback: Revert to v1 (June 2026)"
git push origin main
```

### Verify Rollback

```bash
# Check ArgoCD sync status
kubectl get application fusion-developer-hub -n openshift-gitops

# View application details
argocd app get fusion-developer-hub
```

## 📋 Version Naming Convention

Format: `value-v{VERSION}-{MONTH}{YEAR}.yaml`

### Examples

- `value-v0-may2026.yaml` - Baseline version (May 2026)
- `value-v1-june2026.yaml` - First update (June 2026)
- `value-v2-july2026.yaml` - Second update (July 2026)
- `value-v3-august2026.yaml` - Third update (August 2026)

### Version Numbering

- **v0** - Initial/baseline version
- **v1, v2, v3...** - Sequential updates (typically monthly)
- Include month and year for clarity

## 📊 Comparison Between Versions

### View Differences

```bash
# Compare current with previous version
diff environments/prod/values.yaml \
     environments/prod/value-v1-june2026.yaml

# Or use git diff
git diff environments/prod/value-v0-may2026.yaml \
         environments/prod/value-v1-june2026.yaml
```

### Generate Change Report

```bash
# Create a detailed diff report
diff -u environments/prod/value-v0-may2026.yaml \
        environments/prod/values.yaml > changes-v0-to-current.diff
```

## 🔍 Best Practices

### DO ✅

- Archive current version BEFORE making changes
- Keep production overrides minimal (only what's needed)
- Use descriptive commit messages
- Test changes in dev/staging first
- Review diffs before committing
- Keep version files in git
- We recommend users always create a copy of base values.yaml and edit it rather than editing the base directly

### DON'T ❌

- Don't modify archived versions (they're historical records)
- Don't skip archiving step
- Don't edit base values.yaml for production
- Don't make changes directly in production
- Don't use ambiguous version names