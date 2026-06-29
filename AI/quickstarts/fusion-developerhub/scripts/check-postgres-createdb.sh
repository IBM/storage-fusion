#!/bin/bash
# Check if PostgreSQL CREATEDB privilege has been granted

NAMESPACE="${1:-fusion-dev-hub}"
CLUSTER_NAME="${2:-fusion-guest-postgres}"

echo "Checking CREATEDB privilege for PostgreSQL cluster: $CLUSTER_NAME in namespace: $NAMESPACE"
echo ""

# Check if grant-createdb job exists
JOB_NAME="${CLUSTER_NAME}-grant-createdb"
if oc get job "$JOB_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "Grant-createdb job status:"
    oc get job "$JOB_NAME" -n "$NAMESPACE"
    echo ""
    
    # Check job completion
    COMPLETIONS=$(oc get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}')
    if [[ "$COMPLETIONS" == "1" ]]; then
        echo "✓ CREATEDB privilege has been granted successfully"
        exit 0
    else
        echo "⚠ Job is still running or failed"
        echo ""
        echo "Job logs:"
        oc logs job/"$JOB_NAME" -n "$NAMESPACE" --tail=50
        exit 1
    fi
else
    echo "✗ Grant-createdb job not found"
    exit 1
fi
