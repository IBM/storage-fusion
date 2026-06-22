#!/usr/bin/env bash
set -eu


# Set up minimal environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export ROOT_DIR

# Source required files
# shellcheck source=../lib/constants.sh
source "$ROOT_DIR/lib/constants.sh"
# shellcheck source=../lib/utils.sh
source "$ROOT_DIR/lib/utils.sh"
# shellcheck source=../modules/df_utils.sh
source "$ROOT_DIR/modules/df_utils.sh"
# shellcheck source=../config/config.env
source "$ROOT_DIR/config/config.env"

# Set required environment variable
#export OCS_BACKING_STORAGECLASS="ocs-backing-lvs"

# Array of test match expressions
test_expressions=(
    "Exists:node-role.kubernetes.io/worker"
    "NotIn:beta.kubernetes.io/instance-type=gx3d.160x1792.8h100,another.type"
    "In:region=us-east,us-west"
    "Exists:node-role.kubernetes.io/worker;NotIn:beta.kubernetes.io/instance-type=gx3d.160x1792.8h100"
)

# Loop through each test expression
for STORAGE_NODE_MATCH in "${test_expressions[@]}"; do
    echo "========================================"
    echo "STORAGE_NODE_MATCH: ${STORAGE_NODE_MATCH}"
    echo "========================================"
    echo ""

    echo "=== Testing match_expressions_list() ==="
    echo ""
    match_expressions_list "${STORAGE_NODE_MATCH}"
    echo ""

    # Call the function and display output
    echo "=== Testing gen_local_volume_set() ==="
    echo ""

    if output=$(gen_local_volume_set); then
        exit_code=$?
        echo "✅ Function succeeded"
        echo ""
        echo "=== Generated YAML ==="
        echo "$output"
        echo "=== Exit Code: ${exit_code} ==="
    else
        exit_code=$?
        echo "❌ Function failed with exit code: $exit_code"
        echo ""
        echo "=== Captured Output ==="
        echo "$output"
        echo "=== Exit Code: ${exit_code} ==="
    fi

    echo ""
done
