#!/bin/bash

set -euo pipefail

# Constants
NAMESPACE="ibm-spectrum-fusion-ns"
CSV_PREFIX="isf-operator"
DEPLOYMENT="isf-compute-operator-controller-manager"
CONTAINER="manager"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <compute-image>"
  exit 1
fi

LOG=/tmp/$(basename "$0")_log.txt
exec &> >(tee -a "$LOG")
echo "Logging to $LOG"

compute_image="$1"
echo "Using compute image: $compute_image"

echo "Locating compute operator CSV..."
csv_name=$(oc get csv -n "$NAMESPACE" --no-headers | awk "/^$CSV_PREFIX/"'{ print $1 }' | sort -V | tail -1)

if [[ -z "$csv_name" ]]; then
  echo "ERROR: Couldn't find any CSV starting with '$CSV_PREFIX' in $NAMESPACE"
  exit 1
fi

echo "Found CSV: $csv_name"

deployments_str=$(oc get csv "$csv_name" -n "$NAMESPACE" -o jsonpath="{.spec.install.spec.deployments[*].name}")
read -a deployments <<< "$deployments_str"

deployment_index=-1
for i in "${!deployments[@]}"; do
  if [[ "${deployments[i]}" == "$DEPLOYMENT" ]]; then
    deployment_index=$i
    break
  fi
done

if [[ $deployment_index -lt 0 ]]; then
  echo "ERROR: Deployment '$DEPLOYMENT' not found in CSV $csv_name"
  exit 1
fi

containers_str=$(oc get csv "$csv_name" -n "$NAMESPACE" -o jsonpath="{.spec.install.spec.deployments[$deployment_index].spec.template.spec.containers[*].name}")
read -a containers <<< "$containers_str"

container_index=-1
for i in "${!containers[@]}"; do
  if [[ "${containers[i]}" == "$CONTAINER" ]]; then
    container_index=$i
    break
  fi
done

if [[ $container_index -lt 0 ]]; then
  echo "ERROR: Container '$CONTAINER' not found in deployment '$DEPLOYMENT'"
  exit 1
fi

patch_path="/spec/install/spec/deployments/$deployment_index/spec/template/spec/containers/$container_index/image"

patch_json=$(cat <<EOF
[
  {
    "op": "replace",
    "path": "$patch_path",
    "value": "$compute_image"
  }
]
EOF
)

echo "Patching compute image at: $patch_path"
oc patch csv "$csv_name" -n "$NAMESPACE" --type json -p "$patch_json"
echo "Compute image patched."