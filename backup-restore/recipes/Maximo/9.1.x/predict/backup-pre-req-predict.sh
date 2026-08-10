#!/bin/bash

# Default value for PREDICT_NAMESPACE (set later based on MAS_INSTANCE_ID)
PREDICT_NAMESPACE=""
CUSTOM_CERTS=false

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n PREDICT_NAMESPACE    Specify the Predict namespace (default: mas-<MAS_INSTANCE_ID>-predict)"
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
      PREDICT_NAMESPACE=$1
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

# Validate inputs
if [[ -z $MAS_INSTANCE_ID || -z $MAS_WORKSPACE_ID ]]; then
  echo "MAS_INSTANCE_ID and MAS_WORKSPACE_ID are required"
  usage
  exit 1
fi

# Set default PREDICT_NAMESPACE if not provided
if [[ -z $PREDICT_NAMESPACE ]]; then
  PREDICT_NAMESPACE="mas-${MAS_INSTANCE_ID}-predict"
fi

# Add labels to application
# ========================================================================================================================

echo "=== Labeling Predict resources in namespace: $PREDICT_NAMESPACE ==="

# Label predictapps and predictworkspaces
oc label -n $PREDICT_NAMESPACE predictapps.apps.mas.ibm.com $MAS_INSTANCE_ID for-backup=true --overwrite
oc label -n $PREDICT_NAMESPACE predictworkspaces.apps.mas.ibm.com ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true --overwrite

# Label operatorgroup and subscription
oc label -n $PREDICT_NAMESPACE $(oc get operatorgroups.operators.coreos.com -n $PREDICT_NAMESPACE -o name) for-backup=true --overwrite
oc label -n $PREDICT_NAMESPACE subscription.operators.coreos.com ibm-mas-predict for-backup=true --overwrite

# Label secrets (common ones)
oc label -n $PREDICT_NAMESPACE secret ibm-entitlement for-backup=true --overwrite
oc label -n $PREDICT_NAMESPACE secret ${MAS_INSTANCE_ID}-truststore for-backup=true --overwrite

# Optional custom cert
if [[ $CUSTOM_CERTS == true ]]; then
  oc label -n $PREDICT_NAMESPACE secret ${MAS_INSTANCE_ID}-public-tls for-backup=true --overwrite
fi

# Show labeled resources
echo -e "\n=== Labeled Resources ==="
oc get predictapps.apps.mas.ibm.com -n $PREDICT_NAMESPACE -l for-backup=true --show-labels
oc get predictworkspaces.apps.mas.ibm.com -n $PREDICT_NAMESPACE -l for-backup=true --show-labels
oc get operatorgroups.operators.coreos.com -n $PREDICT_NAMESPACE -l for-backup=true --show-labels
oc get subscriptions.operators.coreos.com -n $PREDICT_NAMESPACE -l for-backup=true --show-labels
oc get secrets -n $PREDICT_NAMESPACE -l for-backup=true --show-labels


# Create local recipe
# ========================================================================================================================

export MAS_INSTANCE_ID
recipe_name="predict/maximo-child-predict-backup-restore.yaml"
local_recipe="predict/maximo-child-predict-backup-restore-local.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); print}' "$recipe_name" > ${local_recipe}
  echo "Recipe YAML file: ${local_recipe}"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/predict"
fi

#Remove all lines that contain comments from local recipe
awk '!/#/' $local_recipe > temp.yaml && mv temp.yaml $local_recipe

# Create role and rolebindings for Fusion transaction-manager
# ========================================================================================================================
echo -e "\n=== Creating Role and RoleBinding for predict access from Fusion transaction-manager ==="

CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "predictapps"
add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "predictworkspaces"

# check if namespace is added to Fusion App CR.
add_ns_if_missing_from_fapp ${PREDICT_NAMESPACE}

echo -e "\nTo apply recipe:"
echo "oc -n $ISF_NAMESPACE apply -f ${local_recipe}"
