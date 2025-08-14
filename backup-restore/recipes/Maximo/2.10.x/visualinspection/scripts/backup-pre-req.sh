#!/bin/bash

# Default value for VISUALINSPECTION_NAMESPACE (set later based on MAS_INSTANCE_ID)
VISUALINSPECTION_NAMESPACE=""
CUSTOM_CERTS=false

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n VISUALINSPECTION_NAMESPACE    Specify the VISUALINSPECTION namespace (default: mas-<MAS_INSTANCE_ID>-visualinspection)"
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
      VISUALINSPECTION_NAMESPACE=$1
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

# Set default VISUALINSPECTION_NAMESPACE if not provided
if [[ -z $VISUALINSPECTION_NAMESPACE ]]; then
  VISUALINSPECTION_NAMESPACE="mas-${MAS_INSTANCE_ID}-visualinspection"
fi

# Add labels to application
# ========================================================================================================================

# Check if Grafana Dashboard exists
GRAFANAV4_DASHBOARD=$(oc get -n $VISUALINSPECTION_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $VISUALINSPECTION_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)


#Label all required resources for MAS Visualinspection
echo "=== Adding labels to resources ==="
oc label -n $VISUALINSPECTION_NAMESPACE visualinspectionapps $MAS_INSTANCE_ID for-backup=true 
oc label -n $VISUALINSPECTION_NAMESPACE visualinspectionappworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true
oc label -n $VISUALINSPECTION_NAMESPACE $(oc get -n $VISUALINSPECTION_NAMESPACE operatorgroups.operators.coreos.com -o name) for-backup=true
oc label -n $VISUALINSPECTION_NAMESPACE subscription.operators.coreos.com ibm-mas-visualinspection for-backup=true
oc label -n $VISUALINSPECTION_NAMESPACE secret ibm-entitlement for-backup=true

for configmap in $(oc get -n $VISUALINSPECTION_NAMESPACE configmap -o custom-columns=NAME:.metadata.name |grep ^custom-.*-config$); do
  oc label -n $VISUALINSPECTION_NAMESPACE configmap $configmap for-backup=true
done

# Custom secret name based on https://www.ibm.com/docs/en/masv-and-l/continuous-delivery?topic=management-uploading-public-certificates-in-red-hat-openshift
if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $VISUALINSPECTION_NAMESPACE secret public-visualinspection-tls for-backup=true
fi


#Showing labels of all resources
echo -e "\n=== Visual Inspection Resources ==="
oc get -n $VISUALINSPECTION_NAMESPACE visualinspectionapps -l for-backup=true --show-labels
oc get -n $VISUALINSPECTION_NAMESPACE visualinspectionappworkspaces -l for-backup=true --show-labels


echo -e "\n=== OperatorGroup/Subscriptions ==="
oc get -n $VISUALINSPECTION_NAMESPACE operatorgroup.operators.coreos.com -l for-backup=true --show-labels
oc get -n $VISUALINSPECTION_NAMESPACE subscription.operators.coreos.com  -l for-backup=true --show-labels

echo -e "\n=== Secrets ==="
oc get -n $VISUALINSPECTION_NAMESPACE secret ibm-entitlement --show-labels
if [[ $CUSTOM_CERTS = true ]]; then
  oc get -n $VISUALINSPECTION_NAMESPACE secret public-visualinspection-tls
fi

echo -e "\n=== Custom Configmaps ==="
oc get -n $VISUALINSPECTION_NAMESPACE configmap -l for-backup=true 2>/dev/null

# Create local recipe
# ========================================================================================================================

export MAS_INSTANCE_ID
recipe_name="maximo-visualinspection-backup-restore.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); print}' "$recipe_name" > maximo-visualinspection-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-visualinspection-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/visualinspection"
fi

local_recipe="maximo-visualinspection-backup-restore-local.yaml"
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

# add role
CLUSTERROLE="transaction-manager-ibm-backup-restore"

# Check if the rule for predictapps already exists
oc get clusterrole "$CLUSTERROLE" -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["apps.mas.ibm.com"] and
    (.resources | contains(["predictapps"])) and
    (.verbs | contains(["get"]) and contains(["list"]) and contains(["watch"]))
  )' > /dev/null

if [[ $? -ne 0 ]]; then
  echo "Adding predictapps rule to ClusterRole '$CLUSTERROLE'..."
  oc patch clusterrole "$CLUSTERROLE" --type=json -p='[
    {
      "op": "add",
      "path": "/rules/-",
      "value": {
        "apiGroups": ["apps.mas.ibm.com"],
        "resources": ["predictapps"],
        "verbs": ["get", "list", "watch"]
      }
    }
  ]'
else
  echo "Rule for predictapps already exists. Skipping."
fi