# Version Management Guide

This document describes the versioning strategy for MaaS (Model-as-a-Service) configuration files.

## 📁 Directory Structure

```
deploy/
├── maas-operators/
│   ├── values.yaml                    # CURRENT/ACTIVE configuration
│   ├── Chart.yaml
│   ├── templates/
│   └── versions/                      # Version archive
│       ├── CHANGELOG.md              # Change history
│       ├── values-v0-may2026.yaml    # May 2026 baseline
│       └── values-v1-june2026.yaml   # June 2026 (future archive)
│
├── maas-platform/
│   ├── values.yaml                    # CURRENT/ACTIVE configuration
│   ├── Chart.yaml
│   ├── templates/
│   └── versions/                      # Version archive
│       └── CHANGELOG.md
│
└── maas-runtime/
    ├── values.yaml                    # CURRENT/ACTIVE configuration
    ├── Chart.yaml
    ├── templates/
    └── versions/                      # Version archive
        └── CHANGELOG.md
```

## 🎯 Versioning Strategy

### Core Principles

1. **`values.yaml` is always CURRENT** - ArgoCD applications always reference this file
2. **Archive before changes** - Move current values.yaml to versions/ before making updates
3. **Maintain all keys** - Keep all configuration keys even if values don't change
4. **Clear naming** - Use semantic versioning with date: `values-v{N}-{month}{year}.yaml`
5. **Document changes** - Update CHANGELOG.md with every version

### Why This Approach?

✅ **Zero ArgoCD changes** - Applications always point to `values.yaml`  
✅ **Complete history** - All versions preserved in `versions/` directory  
✅ **Easy rollback** - Simple file copy operation  
✅ **Clean structure** - Active files separate from archives  
✅ **Audit trail** - Git history + CHANGELOG + archived files  

## 🔄 Monthly Update Workflow

### Step 1: Archive Current Version

Before making any changes, archive the current `values.yaml`:

```bash
# Navigate to component directory
cd quickstarts/model-as-a-service/deploy/maas-operators

# Archive current version with date
cp values.yaml versions/values-v1-june2026.yaml

# Repeat for other components if needed
cd ../maas-platform
cp values.yaml versions/values-v1-june2026.yaml

cd ../maas-runtime
cp values.yaml versions/values-v1-june2026.yaml
```

### Step 2: Update values.yaml

Make your changes to `values.yaml`:

```yaml
# Example: Update operator channel
operators:
  openshiftAI:
    enabled: true
    channel: stable-3.x  # Changed from fast-3.x
    namespace: redhat-ods-operator
    source: redhat-operators
    sourceNamespace: openshift-marketplace
    installPlanApproval: Automatic
  
  # Keep ALL other keys even if unchanged
  connectivityLink:
    enabled: true
    channel: stable  # No change, but maintained
    # ... rest of config
```

### Step 3: Update CHANGELOG.md

Document changes in `versions/CHANGELOG.md`:

```markdown
## v2 (July 2026) - CURRENT
**Date:** 2026-07-01
**File:** `../values.yaml`

### Changed
- OpenShift AI channel: `fast-3.x` → `stable-3.x`
- Removed startingCSV pinning

### Maintained (No Changes)
- All other operator configurations unchanged
```

### Step 4: Commit Changes

```bash
# Add all changes
git add deploy/*/values.yaml deploy/*/versions/

# Commit with descriptive message
git commit -m "chore: Archive v1 (June 2026) and update to v2 (July 2026)

Components updated:
- maas-operators: OpenShift AI channel stable-3.x
- maas-platform: No changes (keys maintained)
- maas-runtime: No changes (keys maintained)

Archived versions:
- values-v1-june2026.yaml"

# Push to repository
git push origin main
```

### Step 5: ArgoCD Auto-Sync

ArgoCD will automatically detect the changes to `values.yaml` and sync:

```bash
# Monitor sync status
kubectl get applications -n openshift-gitops

# Check specific application
kubectl describe application maas-operators -n openshift-gitops
```

## 🔙 Rollback Procedure

### Quick Rollback

To rollback to a previous version:

```bash
# Copy archived version back to values.yaml
cp deploy/maas-operators/versions/values-v1-june2026.yaml \
   deploy/maas-operators/values.yaml

# Commit the rollback
git add deploy/maas-operators/values.yaml
git commit -m "rollback: Revert maas-operators to v1 (June 2026)"
git push origin main
```

### Verify Rollback

```bash
# Check ArgoCD sync status
kubectl get application maas-operators -n openshift-gitops

# View application details
argocd app get maas-operators
```

## 📋 Version Naming Convention

Format: `values-v{VERSION}-{MONTH}{YEAR}.yaml`

### Examples

- `values-v0-may2026.yaml` - Baseline version (May 2026)
- `values-v1-june2026.yaml` - First update (June 2026)
- `values-v2-july2026.yaml` - Second update (July 2026)
- `values-v3-august2026.yaml` - Third update (August 2026)

### Version Numbering

- **v0** - Initial/baseline version
- **v1, v2, v3...** - Sequential updates (typically monthly)
- Include month and year for clarity

## 📊 Comparison Between Versions

### View Differences

```bash
# Compare current with previous version
diff deploy/maas-operators/values.yaml \
     deploy/maas-operators/versions/values-v1-june2026.yaml

# Or use git diff
git diff deploy/maas-operators/versions/values-v0-may2026.yaml \
         deploy/maas-operators/versions/values-v1-june2026.yaml
```

### Generate Change Report

```bash
# Create a detailed diff report
diff -u deploy/maas-operators/versions/values-v0-may2026.yaml \
        deploy/maas-operators/values.yaml > changes-v0-to-current.diff
```

## 🔍 Best Practices

### DO ✅

- Archive current version BEFORE making changes
- Maintain ALL configuration keys (even unchanged ones)
- Update CHANGELOG.md with every version
- Use descriptive commit messages
- Test changes in dev/staging first
- Review diffs before committing
- Keep version files in git

### DON'T ❌

- Don't modify archived versions (they're historical records)
- Don't skip archiving step
- Don't remove configuration keys
- Don't make changes directly in production
- Don't forget to update CHANGELOG
- Don't use ambiguous version names

## 🚀 Advanced Usage

### Create Version Snapshot Script

```bash
#!/bin/bash
# archive-version.sh

VERSION=$1
DATE=$2

if [ -z "$VERSION" ] || [ -z "$DATE" ]; then
    echo "Usage: ./archive-version.sh <version> <date>"
    echo "Example: ./archive-version.sh v2 july2026"
    exit 1
fi

cd quickstarts/model-as-a-service/deploy

for component in maas-operators maas-platform maas-runtime; do
    echo "Archiving $component..."
    cp $component/values.yaml $component/versions/values-$VERSION-$DATE.yaml
done

echo "✅ All components archived as $VERSION-$DATE"
```

### Automated Diff Report

```bash
#!/bin/bash
# generate-diff-report.sh

COMPONENT=$1
OLD_VERSION=$2
NEW_VERSION=$3

diff -u deploy/$COMPONENT/versions/values-$OLD_VERSION.yaml \
        deploy/$COMPONENT/versions/values-$NEW_VERSION.yaml \
        > reports/$COMPONENT-$OLD_VERSION-to-$NEW_VERSION.diff

echo "✅ Diff report generated: reports/$COMPONENT-$OLD_VERSION-to-$NEW_VERSION.diff"
```

## 📞 Support

For questions or issues with version management:

1. Check CHANGELOG.md in each component's versions/ directory
2. Review git commit history: `git log -- deploy/*/values.yaml`
3. Compare versions using diff tools
4. Consult team documentation

## 📚 Related Documentation

- [MaaS Operators Guide](../docs/01-setup/MAAS_OPERATORS_GUIDE.md)
- [MaaS Platform Customization](../docs/01-setup/MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md)
- [MaaS Runtime Customization](../docs/01-setup/MAAS_RUNTIME_CUSTOMIZATION_GUIDE.md)
- [Deployment Order](../docs/01-setup/DEPLOYMENT_ORDER.md)