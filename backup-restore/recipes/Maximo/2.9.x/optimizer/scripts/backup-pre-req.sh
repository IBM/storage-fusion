#!/bin/bash

# Default value for OPTIMIZER_NAMESPACE (set later based on MAS_INSTANCE_ID)
OPTIMIZER_NAMESPACE=""
CUSTOM_CERTS=false

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n OPTIMIZER_NAMESPACE    Specify the OPTIMIZER namespace (default: mas-<MAS_INSTANCE_ID>-optimizer)"
  echo "  --mas-instance-id MAS_INSTANCE_ID    Specify the MAS Instance ID (Required)"
  echo "  --mas-workspace-id MAS_WORKSPACE_ID    Specify the MAS Workspace ID (Required)"
  echo "  --custom-certs    Allow script to label custom cert (default: false)"
}

#Handling options specified in command line
while [[ "$1" != "" ]]; do
  case $1 in
    -h | --help )
      usage
      exit 0
      ;;
    -n )
      shift
      OPTIMIZER_NAMESPACE=$1
      ;;
    --mas-instance-id )
      shift
      MAS_INSTANCE_ID=$1
      ;;
    --mas-workspace-id )
      shift
      MAS_WORKSPACE_ID=$1
      ;;
    --custom-certs)
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

# Check if MAS_INSTANCE_ID is set
if [[ -z $MAS_INSTANCE_ID ]]; then
  MAS_INSTANCE_ID=$MAS_INSTANCE_ID
fi

# Check if MAS_INSTANCE_ID is still not set
if [[ -z $MAS_INSTANCE_ID ]]; then
  echo "Error: --mas-instance-id is mandatory"
  usage
  exit 1
fi

# Check if MAS_WORKSPACE_ID is set
if [[ -z $MAS_WORKSPACE_ID ]]; then
  MAS_WORKSPACE_ID=$MAS_WORKSPACE_ID
fi

# Check if MAS_WORKSPACE_ID is still not set
if [[ -z $MAS_WORKSPACE_ID ]]; then
  echo "Error: --mas-workspace-id is mandatory"
  usage
  exit 1
fi

# Set default OPTMIZER_NAMESPACE if not provided
if [[ -z $OPTIMIZER_NAMESPACE ]]; then
  OPTIMIZER_NAMESPACE="mas-${MAS_INSTANCE_ID}-optimizer"
fi

# Add labels to application
# ========================================================================================================================

#Label all required resources for MAS Optimizer
echo "=== Adding labels to resources ==="
oc label -n $OPTIMIZER_NAMESPACE optimizerapp $MAS_INSTANCE_ID for-backup=true 
oc label -n $OPTIMIZER_NAMESPACE optimizerworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true
oc label -n $OPTIMIZER_NAMESPACE operatorgroup.operators.coreos.com mas-${MAS_INSTANCE_ID}-optimizer-operator-group for-backup=true
oc label -n $OPTIMIZER_NAMESPACE subscription.operators.coreos.com ibm-mas-optimizer for-backup=true
oc label -n $OPTIMIZER_NAMESPACE secret ibm-entitlement for-backup=true

if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $OPTIMIZER_NAMESPACE secret ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID}-cert-optimizer-public for-backup=true
fi

#Showing labels of all resources
echo -e "\n=== Optimizer Resources ==="
oc get -n $OPTIMIZER_NAMESPACE --show-labels optimizerapp $MAS_INSTANCE_ID
oc get -n $OPTIMIZER_NAMESPACE --show-labels optimizerworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID}
oc get -n $OPTIMIZER_NAMESPACE --show-labels secret ibm-entitlement

echo -e "\n=== OperatorGroup/Subscriptions ==="
oc get -n $OPTIMIZER_NAMESPACE --show-labels operatorgroup.operators.coreos.com mas-${MAS_INSTANCE_ID}-optimizer-operator-group
oc get -n $OPTIMIZER_NAMESPACE --show-labels subscription.operators.coreos.com ibm-mas-optimizer

echo -e "\n=== Secrets ==="
oc get -n $OPTIMIZER_NAMESPACE --show-labels secret ibm-entitlement

# Create local recipe
# ========================================================================================================================

echo -e "\n=== Creating recipe from template ==="
export MAS_INSTANCE_ID
recipe_name="maximo-optimizer-backup-restore.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); print}' "$recipe_name" > maximo-optimizer-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-optimizer-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/optimizer"
fi
