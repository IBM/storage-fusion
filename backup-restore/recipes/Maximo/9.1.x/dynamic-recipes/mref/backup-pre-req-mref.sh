#!/bin/bash

source maximo_env.sh

# Default value for FACILITIES_NAMESPACE
FACILITIES_NAMESPACE=""
CUSTOM_CERTS=false

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n FACILITIES_NAMESPACE    Specify the Facilities namespace (default: mas-<MAS_INSTANCE_ID>-facilities)"
  echo "  --mas-instance-id MAS_INSTANCE_ID    Specify the MAS Instance ID (Required)"
  echo "  --mas-workspace-id MAS_WORKSPACE_ID  Specify the MAS Workspace ID (Required)"
  echo "  --custom-certs    Allow script to label custom cert (default: false)"
}

# Handling options
while [[ "$1" != "" ]]; do
  case $1 in
    -h | --help )
      usage
      exit 0
      ;;
    -n )
      shift
      FACILITIES_NAMESPACE=$1
      ;;
    --mas-instance-id )
      shift
      MAS_INSTANCE_ID=$1
      ;;
    --mas-workspace-id )
      shift
      MAS_WORKSPACE_ID=$1
      ;;
    --custom-certs )
      CUSTOM_CERTS=true
      ;;
    * )
      echo "Invalid option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# Validate MAS instance
if [[ -z $MAS_INSTANCE_ID ]]; then
  echo "Error: --mas-instance-id is mandatory"
  exit 1
fi

# Validate workspace
if [[ -z $MAS_WORKSPACE_ID ]]; then
  echo "Error: --mas-workspace-id is mandatory"
  exit 1
fi

# Default namespace
if [[ -z $FACILITIES_NAMESPACE ]]; then
  FACILITIES_NAMESPACE="mas-${MAS_INSTANCE_ID}-facilities"
fi

echo "Using namespace: $FACILITIES_NAMESPACE"

# ======================================================================
# Label resources
# ======================================================================

echo "=== Adding labels to Facilities resources ==="

oc label -n $FACILITIES_NAMESPACE facilitiesapps $MAS_INSTANCE_ID for-backup=true 

oc label -n $FACILITIES_NAMESPACE facilitiesworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true 

oc label -n $FACILITIES_NAMESPACE $(oc get operatorgroups.operators.coreos.com -n $FACILITIES_NAMESPACE -o name) for-backup=true 

oc label -n $FACILITIES_NAMESPACE subscription.operators.coreos.com ibm-mas-facilities for-backup=true 

oc label -n $FACILITIES_NAMESPACE secret ibm-entitlement for-backup=true 

# Optional custom cert
if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $FACILITIES_NAMESPACE secret ${MAS_INSTANCE_ID}-cert-facilities-public for-backup=true 
fi

# Show labeled resources
echo -e "\n=== FacilitiesApp ==="
oc get -n $FACILITIES_NAMESPACE facilitiesapps $MAS_INSTANCE_ID --show-labels

echo -e "\n=== FacilitiesWorkspace ==="
oc get -n $FACILITIES_NAMESPACE facilitiesworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} --show-labels

echo -e "\n=== OperatorGroup ==="
oc get -n $FACILITIES_NAMESPACE operatorgroups.operators.coreos.com -l for-backup=true --show-labels

echo -e "\n=== Subscription ==="
oc get -n $FACILITIES_NAMESPACE subscription.operators.coreos.com ibm-mas-facilities --show-labels

echo -e "\n=== Secrets ==="
oc get -n $FACILITIES_NAMESPACE secrets -l for-backup=true --show-labels

# ======================================================================
# Create local recipe
# ======================================================================

export MAS_INSTANCE_ID

recipe_name="mref/maximo-child-facilities-backup-restore.yaml"
local_recipe="mref/maximo-child-facilities-backup-restore-local.yaml"

echo -e "\n=== Creating recipe from template ==="

if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" \
      -v facilities_ns="$FACILITIES_NAMESPACE" \
      '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id);
        gsub(/\$\{FACILITIES_NAMESPACE\}/, facilities_ns);
        print}' "$recipe_name" > ${local_recipe}

  echo "Recipe YAML file: ${local_recipe}"
else
  echo "Template Recipe YAML file not found. Make sure to cd to mref/facilities"
fi

# ======================================================================
# Add namespace to core recipe
# ======================================================================

local_core_recipe="core/maximo-child-core-backup-restore-local.yaml"

INCLUDE_NAMESPACE="${FACILITIES_NAMESPACE}" yq -i \
'(.spec.groups[] | select(.name == "maximo-core-resources") | .includedNamespaces) |= . + [env(INCLUDE_NAMESPACE)]' \
${local_core_recipe}

# Remove commented lines
awk '!/#/' $local_recipe > temp.yaml && mv temp.yaml $local_recipe

# ======================================================================
# RBAC permissions
# ======================================================================

CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "facilitiesapps"
add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "facilitiesworkspaces"

# ======================================================================
# Add namespace to Fusion App
# ======================================================================

add_ns_if_missing_from_fapp ${FACILITIES_NAMESPACE}

echo -e "\nTo apply recipe:"
echo "oc -n $ISF_NAMESPACE apply -f ${local_recipe}"
