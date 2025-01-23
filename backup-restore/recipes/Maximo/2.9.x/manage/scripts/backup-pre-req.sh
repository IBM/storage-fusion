#!/bin/bash

# Default value for MANAGE_NAMESPACE (set later based on MAS_INSTANCE_ID)
MANAGE_NAMESPACE=""
CUSTOM_CERTS=false
JMS=false

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n MANAGE_NAMESPACE    Specify the MANAGE namespace (default: mas-<MAS_INSTANCE_ID>-manage)"
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
      MANAGE_NAMESPACE=$1
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

# Set default MANAGE_NAMESPACE if not provided
if [[ -z $MANAGE_NAMESPACE ]]; then
  MANAGE_NAMESPACE="mas-${MAS_INSTANCE_ID}-manage"
fi

# Add labels to application
# ========================================================================================================================

#Retrive ManageServerBundles
MANAGE_SERVER_BUNDLES=$(oc get -n $MANAGE_NAMESPACE manageserverbundle -o custom-columns=NAME:.metadata.name --no-headers)

# Check if Grafana Dashboard exists
GRAFANAV4_DASHBOARD=$(oc get -n $MANAGE_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $MANAGE_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

#Validate if JMS is enabled in Manage application
if echo "$MANAGE_SERVER_BUNDLES" | grep -q "jms"; then
  JMS=true
  ALL_BUNDLE_SECRET=$(oc get -n $MANAGE_NAMESPACE manageworkspace ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} -o json | jq -r '.spec.settings.deployment.serverBundles[] | select(.bundleType == "all") | .additionalServerConfig.secretName')
  JMS_BUNDLE_SECRET=$(oc get -n $MANAGE_NAMESPACE manageworkspace ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} -o json | jq -r '.spec.settings.deployment.serverBundles[] | select(.bundleType == "standalonejms") | .additionalServerConfig.secretName')
fi

#Label all required resources for MAS Manage
echo "=== Adding labels to resources ==="
oc label -n $MANAGE_NAMESPACE manageapps $MAS_INSTANCE_ID for-backup=true 
oc label -n $MANAGE_NAMESPACE manageworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true
oc label -n $MANAGE_NAMESPACE $(oc get -n $MANAGE_NAMESPACE operatorgroups.operators.coreos.com -o name) for-backup=true
oc label -n $MANAGE_NAMESPACE subscription.operators.coreos.com ibm-mas-manage for-backup=true
oc label -n $MANAGE_NAMESPACE secret ibm-entitlement for-backup=true
oc label -n $MANAGE_NAMESPACE secret ${MAS_WORKSPACE_ID}-manage-encryptionsecret-operator for-backup=true
oc label -n $MANAGE_NAMESPACE secret ${MAS_WORKSPACE_ID}-manage-encryptionsecret for-backup=true

if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $MANAGE_NAMESPACE secret ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID}-cert-public-81 for-backup=true
fi

# JMS resources
if [[ $JMS = true ]]; then
    oc label -n $MANAGE_NAMESPACE secret $ALL_BUNDLE_SECRET for-backup=true
    oc label -n $MANAGE_NAMESPACE secret $JMS_BUNDLE_SECRET for-backup=true
fi

#Showing labels of all resources
echo -e "\n=== Manage Resources ==="
oc get -n $MANAGE_NAMESPACE manageapps -l for-backup=true --show-labels
oc get -n $MANAGE_NAMESPACE manageworkspaces -l for-backup=true --show-labels


echo -e "\n=== OperatorGroup/Subscriptions ==="
oc get -n $MANAGE_NAMESPACE operatorgroup.operators.coreos.com -l for-backup=true --show-labels
oc get -n $MANAGE_NAMESPACE subscription.operators.coreos.com  -l for-backup=true --show-labels

echo -e "\n=== Secrets ==="
oc get -n $MANAGE_NAMESPACE secret ibm-entitlement --show-labels
oc get -n $MANAGE_NAMESPACE secret ${MAS_WORKSPACE_ID}-manage-encryptionsecret-operator --show-labels
oc get -n $MANAGE_NAMESPACE secret ${MAS_WORKSPACE_ID}-manage-encryptionsecret --show-labels


# JMS resources
if [[ $JMS = true ]]; then
    echo -e "\n=== JMS Secrets ==="
    oc get -n $MANAGE_NAMESPACE secret $ALL_BUNDLE_SECRET --show-labels
    oc get -n $MANAGE_NAMESPACE secret $JMS_BUNDLE_SECRET --show-labels
fi

# Create local recipe
# ========================================================================================================================

export MAS_INSTANCE_ID
recipe_name="maximo-manage-backup-restore.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); print}' "$recipe_name" > maximo-manage-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-manage-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/manage"
fi

local_recipe="maximo-manage-backup-restore-local.yaml"
# Validate if Grafanav4 Dashboard exists
if [[ -n $GRAFANAV4_DASHBOARD ]]; then
  awk '{gsub(/#IfGrafanaUncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
  awk '{gsub(/#IfGrafanav4Uncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

# Validate if Grafanav5 Dashboard exists
if [[ -n $GRAFANAV5_DASHBOARD ]]; then
  awk '{gsub(/#IfGrafanaUncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
  awk '{gsub(/#IfGrafanav5Uncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

#Remove all lines that contain comments from local recipe
awk '!/#/' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
