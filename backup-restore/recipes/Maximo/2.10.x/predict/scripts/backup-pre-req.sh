#!/bin/bash

# Default value for PREDICT_NAMESPACE (set later based on MAS_INSTANCE_ID)
PREDICT_NAMESPACE=""
CUSTOM_CERTS=false

# Default Backup Restore namespace
DEFAULT_BR_NAMESPACE="ibm-backup-restore"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n PREDICT_NAMESPACE    Specify the Predict namespace (default: mas-<MAS_INSTANCE_ID>-predict)"
  echo "  --mas-instance-id MAS_INSTANCE_ID    Specify the MAS Instance ID (Required)"
  echo "  --mas-workspace-id MAS_WORKSPACE_ID    Specify the MAS Workspace ID (Required)"
  echo "  --custom-certs    Allow script to label custom cert (default: false)"
  echo "  --backup-restore-ns   Specify the Backup Restore namespace (default: ${DEFAULT_BR_NAMESPACE})"
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
    --backup-restore-ns )
      shift
      BR_NAMESPACE=$1
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

# Check if BR_NAMESPACE is set, otherwise use the default value
BR_NAMESPACE=${BR_NAMESPACE:-$DEFAULT_BR_NAMESPACE}

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
recipe_name="maximo-predict-backup-restore.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); print}' "$recipe_name" > maximo-predict-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-predict-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/predict"
fi

local_recipe="maximo-iot-backup-restore-local.yaml"

#Remove all lines that contain comments from local recipe
awk '!/#/' $local_recipe > temp.yaml && mv temp.yaml $local_recipe


#add role
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["apps.mas.ibm.com"] and
    (.resources | contains(["predictapps", "predictworkspaces"])) and
    (.verbs | contains(["get", "list", "watch"]))
  )' > /dev/null

if [[ $? -ne 0 ]]; then
  echo "Adding predictworkspaces and predictapps rule to ClusterRole 'transaction-manager-ibm-backup-restore'..."
  oc patch clusterrole transaction-manager-ibm-backup-restore --type=json -p='[
    {
      "op": "add",
      "path": "/rules/-",
      "value": {
        "apiGroups": ["apps.mas.ibm.com"],
        "resources": ["predictapps", "predictworkspaces"],
        "verbs": ["get", "list", "watch"]
      }
    }
  ]'
else
  echo "Rule already exists. Skipping."
fi
