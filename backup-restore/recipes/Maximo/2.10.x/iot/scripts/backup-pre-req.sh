#!/bin/bash

# Default value for IOT_NAMESPACE (set later based on MAS_INSTANCE_ID)
IOT_NAMESPACE=""
CUSTOM_CERTS=false

# Default Backup Restore namespace
DEFAULT_BR_NAMESPACE="ibm-backup-restore"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n IOT_NAMESPACE    Specify the IOT namespace (default: mas-<MAS_INSTANCE_ID>-iot)"
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
      IOT_NAMESPACE=$1
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

# Check if MAS_WORKSPACE_ID is still not set
if [[ -z $MAS_WORKSPACE_ID ]]; then
  echo "Error: --mas-workspace-id is mandatory"
  usage
  exit 1
fi

# Set default IOT_NAMESPACE if not provided
if [[ -z $IOT_NAMESPACE ]]; then
  IOT_NAMESPACE="mas-${MAS_INSTANCE_ID}-iot"
fi

# Check if BR_NAMESPACE is set, otherwise use the default value
BR_NAMESPACE=${BR_NAMESPACE:-$DEFAULT_BR_NAMESPACE}

# Add labels to application
# ========================================================================================================================

# Check if Grafana Dashboard exists
GRAFANAV4_DASHBOARD=$(oc get -n $IOT_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $IOT_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)


#Label all required resources for MAS IOT
echo "=== Adding labels to resources ==="
oc label -n $IOT_NAMESPACE iot $MAS_INSTANCE_ID for-backup=true 
oc label -n $IOT_NAMESPACE iotworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true
oc label -n $IOT_NAMESPACE $(oc get -n $IOT_NAMESPACE operatorgroups.operators.coreos.com -o name) for-backup=true
oc label -n $IOT_NAMESPACE subscription.operators.coreos.com ibm-mas-iot for-backup=true
oc label -n $IOT_NAMESPACE secret ibm-entitlement for-backup=true
oc label -n $IOT_NAMESPACE secret actions-credsenckey for-backup=true
oc label -n $IOT_NAMESPACE secret auth-encryption-secret for-backup=true
oc label -n $IOT_NAMESPACE secret provision-creds-enckey for-backup=true
oc label -n $IOT_NAMESPACE secret auth-edc-user-sync-secret for-backup=true

# Custom secret name based on https://www.ibm.com/docs/en/masv-and-l/continuous-delivery?topic=management-uploading-public-certificates-in-red-hat-openshift
if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $IOT_NAMESPACE secret ${MAS_INSTANCE_ID}-public-tls for-backup=true
fi


#Showing labels of all resources
echo -e "\n=== IOT Resources ==="
oc get -n $IOT_NAMESPACE iot -l for-backup=true --show-labels
oc get -n $IOT_NAMESPACE iotworkspaces -l for-backup=true --show-labels


echo -e "\n=== OperatorGroup/Subscriptions ==="
oc get -n $IOT_NAMESPACE operatorgroup.operators.coreos.com -l for-backup=true --show-labels
oc get -n $IOT_NAMESPACE subscription.operators.coreos.com  -l for-backup=true --show-labels

echo -e "\n=== Secrets ==="
oc get -n $IOT_NAMESPACE secret -l for-backup=true --show-labels

# Create local recipe
# ========================================================================================================================

export MAS_INSTANCE_ID
recipe_name="maximo-iot-backup-restore.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); print}' "$recipe_name" > maximo-iot-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-iot-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/iot"
fi

local_recipe="maximo-iot-backup-restore-local.yaml"
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


#add role
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["iot.ibm.com"] and
    (.resources | contains(["iotworkspaces", "iots"])) and
    (.verbs | contains(["get", "list", "watch"]))
  )' > /dev/null

if [[ $? -ne 0 ]]; then
  echo "Adding iotworkspaces and iots rule to ClusterRole 'transaction-manager-ibm-backup-restore'..."
  oc patch clusterrole transaction-manager-ibm-backup-restore --type=json -p='[
    {
      "op": "add",
      "path": "/rules/-",
      "value": {
        "apiGroups": ["iot.ibm.com"],
        "resources": ["iotworkspaces", "iots"],
        "verbs": ["get", "list", "watch"]
      }
    }
  ]'
else
  echo "Rule already exists. Skipping."
fi
