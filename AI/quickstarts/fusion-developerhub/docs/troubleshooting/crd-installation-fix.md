# CRD Installation Fix - Single Command Installation

## Overview

This document explains the fix for the "CRDs are not installed" error that occurred during Helm installation. The Helm chart has been updated to support **single-command installation** using Helm hooks.

## Problem Statement

Previously, when running:
```bash
helm install fusion-developer-hub \
  ./helm-charts/fusion-developer-hub \
  -n fusion-developer-hub \
  --create-namespace \
  -f examples/quickstart-production-values.yaml \
  --timeout 20m
```

The installation would fail with:
```
Error: INSTALLATION FAILED: unable to build kubernetes objects from release manifest: 
[resource mapping not found for name: "developer-hub" namespace: "fusion-developer-hub" 
from "": no matches for kind "Backstage" in version "rhdh.redhat.com/v1alpha5"
ensure CRDs are installed first, resource mapping not found for name: "developerhub-postgres" 
namespace: "fusion-developer-hub" from "": no matches for kind "PostgresCluster" 
in version "postgres-operator.crunchydata.com/v1beta1"
ensure CRDs are installed first]
```

### Root Cause

Helm validates all resources before installation, but the required CRDs (`Backstage` and `PostgresCluster`) don't exist until the operators are installed and running. This created a chicken-and-egg problem.

## Solution: Helm Hooks

The Helm chart now uses **Helm hooks** to orchestrate the installation in the correct order:

### Installation Flow

1. **Pre-Install Hooks** (weight: -10 to -5)
   - Create operator namespaces
   - Install operator subscriptions
   - Check for existing operators

2. **Post-Install Hooks** (weight: 1-2)
   - Wait for operators to be ready
   - **Wait for CRDs to be created** (NEW!)

3. **Post-Install Hooks** (weight: 5-10)
   - Create PostgresCluster instance
   - Create Backstage instance

### Key Changes

#### 1. CRD Waiter Job (`wait-for-crds.yaml`)
A new job that waits for the required CRDs to be available:
- Checks for `Backstage` CRD from RHDH operator
- Checks for `PostgresCluster` CRD from Crunchy PostgreSQL operator
- Waits up to 10 minutes for each CRD
- Runs at hook-weight: 2 (after operators are ready)

#### 2. Updated Resource Annotations
Both `PostgresCluster` and `Backstage` resources now have:
```yaml
annotations:
  helm.sh/hook: post-install,post-upgrade
  helm.sh/hook-weight: "5"  # PostgresCluster
  helm.sh/hook-weight: "10" # Backstage (after database)
```

This ensures they are created **after** the CRDs exist.

## Usage

### Single Command Installation (Recommended)

Simply run the original command - it now works correctly:

```bash
helm install fusion-developer-hub \
  ./helm-charts/fusion-developer-hub \
  -n fusion-developer-hub \
  --create-namespace \
  -f examples/quickstart-production-values.yaml \
  --timeout 20m
```

### What Happens During Installation

You'll see the following sequence:

1. **Namespace Creation**
   ```
   namespace/fusion-developer-hub created
   namespace/rhdh-operator created
   namespace/postgres-operator created
   ```

2. **Operator Installation**
   ```
   subscription.operators.coreos.com/rhdh-operator created
   subscription.operators.coreos.com/crunchy-postgres-operator created
   ```

3. **Operator Readiness Check**
   ```
   job.batch/wait-for-rhdh-operator created
   job.batch/wait-for-postgres-operator created
   ```

4. **CRD Availability Check** (NEW!)
   ```
   job.batch/wait-for-crds created
   Waiting for Backstage CRD...
   ✓ CRD found: backstages
   Waiting for PostgresCluster CRD...
   ✓ CRD found: postgresclusters
   All Required CRDs are Available
   ```

5. **Instance Creation**
   ```
   postgrescluster.postgres-operator.crunchydata.com/developerhub-postgres created
   backstage.rhdh.redhat.com/developer-hub created
   ```

### Installation Time

Expect the installation to take **10-15 minutes**:
- Operator installation: 2-3 minutes
- CRD creation: 1-2 minutes
- PostgreSQL cluster: 3-5 minutes
- Developer Hub: 3-5 minutes

## Verification

After installation completes, verify everything is running:

```bash
# Check all pods
oc get pods -n fusion-developer-hub

# Check Backstage instance
oc get backstage -n fusion-developer-hub

# Check PostgreSQL cluster
oc get postgrescluster -n fusion-developer-hub

# Get the Developer Hub URL
oc get route -n fusion-developer-hub developer-hub -o jsonpath='{.spec.host}'
```

Expected output:
```bash
# Pods should show Running status
NAME                                    READY   STATUS    RESTARTS   AGE
backstage-developer-hub-xxx             1/1     Running   0          5m
developerhub-postgres-instance1-xxx     4/4     Running   0          8m

# Backstage instance should show Available
NAME             PHASE       AGE
developer-hub    Available   5m

# PostgreSQL cluster should show Ready
NAME                    INSTANCES   READY   AGE
developerhub-postgres   3           3       8m
```

## Troubleshooting

### Installation Hangs at CRD Wait

If the installation hangs at the CRD wait step:

```bash
# Check operator status
oc get csv -n rhdh-operator
oc get csv -n postgres-operator

# Check operator pods
oc get pods -n rhdh-operator
oc get pods -n postgres-operator

# View CRD waiter logs
oc logs -n fusion-developer-hub job/wait-for-crds
```

### CRDs Not Created After 10 Minutes

If CRDs are not created after 10 minutes:

1. Check operator installation:
   ```bash
   oc get subscription -n rhdh-operator
   oc get subscription -n postgres-operator
   ```

2. Check for install plan issues:
   ```bash
   oc get installplan -n rhdh-operator
   oc get installplan -n postgres-operator
   ```

3. Check operator logs:
   ```bash
   oc logs -n rhdh-operator deployment/rhdh-operator
   oc logs -n postgres-operator deployment/pgo
   ```

### Manual CRD Verification

To manually verify CRDs are installed:

```bash
# List all CRDs
oc get crds

# Check specific CRDs
oc get crd backstages.rhdh.redhat.com
oc get crd postgresclusters.postgres-operator.crunchydata.com

# Check CRD details
oc describe crd backstages.rhdh.redhat.com
```

## Cleanup

To uninstall and start fresh:

```bash
# Uninstall the Helm release
helm uninstall fusion-developer-hub -n fusion-developer-hub

# Delete the namespace
oc delete namespace fusion-developer-hub

# Optionally remove operators (if you want to reinstall them)
oc delete namespace rhdh-operator postgres-operator
```

## Configuration Options

### Skip Operator Installation

If operators are already installed in your cluster:

```bash
helm install fusion-developer-hub \
  ./helm-charts/fusion-developer-hub \
  -n fusion-developer-hub \
  --create-namespace \
  -f examples/quickstart-production-values.yaml \
  --set operators.enabled=false \
  --timeout 20m
```

### Use Existing Operators

To use existing operators without reinstalling:

```bash
helm install fusion-developer-hub \
  ./helm-charts/fusion-developer-hub \
  -n fusion-developer-hub \
  --create-namespace \
  -f examples/quickstart-production-values.yaml \
  --set operators.skipIfExists=true \
  --timeout 20m
```

## Technical Details

### Helm Hook Weights

The installation uses the following hook weights:

| Component | Hook Type | Weight | Purpose |
|-----------|-----------|--------|---------|
| Operator Namespaces | pre-install | -10 | Create namespaces first |
| Operator Groups | pre-install | -9 | Create operator groups |
| Operator Subscriptions | pre-install | -8 | Subscribe to operators |
| Operator Check | pre-install | -5 | Check existing operators |
| Operator Wait Jobs | post-install | 1 | Wait for operators ready |
| CRD Wait Job | post-install | 2 | **Wait for CRDs** |
| PostgresCluster | post-install | 5 | Create database |
| Backstage | post-install | 10 | Create Developer Hub |

### Why This Works

1. **Pre-install hooks** run before Helm validates the main resources
2. Operators are installed and start creating CRDs
3. **Post-install hooks** run in order by weight
4. CRD waiter ensures CRDs exist before instance creation
5. Instances are created only after CRDs are available

This eliminates the validation error because the CRD-dependent resources are created via hooks, not as part of the main manifest.

## Related Documentation

- [PostgreSQL Troubleshooting](./postgresql-troubleshooting.md)
- [Operator Installation Guide](../getting-started/README.md)
- [Helm Chart Architecture](../../helm-charts/fusion-developer-hub/ARCHITECTURE.md)