#!/bin/bash

source maximo_env.sh

# Default value for MONITOR_NAMESPACE (set later based on MAS_INSTANCE_ID)
MONITOR_NAMESPACE=""
JMS=false
CUSTOM_CERTS=false

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n MONITOR_NAMESPACE    Specify the Monitor namespace (default: mas-<MAS_INSTANCE_ID>-monitor)"
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
      MONITOR_NAMESPACE=$1
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

# Check if MAS_WORKSPACE_ID is still not set
if [[ -z $MAS_WORKSPACE_ID ]]; then
  echo "Error: --mas-workspace-id is mandatory"
  usage
  exit 1
fi

# Set default MONITOR_NAMESPACE if not provided
if [[ -z $MONITOR_NAMESPACE ]]; then
  MONITOR_NAMESPACE="mas-${MAS_INSTANCE_ID}-monitor"
fi

# Add labels to application
# ========================================================================================================================

# Check if Grafana Dashboard exists in Monitor Dashboard
GRAFANAV4_DASHBOARD=$(oc get -n $MONITOR_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $MONITOR_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

# Since Monitor has resources across two namespaces, patching Monitor Fusion Aplication to include AssetDirectories Namespace
echo "=== Adding includedNamespaces patch to Monitor Application ==="
oc patch application.application.isf.ibm.com -n ibm-spectrum-fusion-ns $MONITOR_NAMESPACE --type merge -p "{\"spec\":{\"includedNamespaces\":[\"$MONITOR_NAMESPACE\", \"$ADD_NAMESPACE\"]}}"

#Label all required resources for MAS Monitor
echo -e "\n=== Adding labels to Monitor resources ==="
oc label -n $MONITOR_NAMESPACE monitorapps $MAS_INSTANCE_ID for-backup=true
oc label -n $MONITOR_NAMESPACE monitorworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true
oc label -n $MONITOR_NAMESPACE $(oc get -n $MONITOR_NAMESPACE operatorgroups.operators.coreos.com -o name) for-backup=true
oc label -n $MONITOR_NAMESPACE subscription.operators.coreos.com ibm-mas-monitor for-backup=true
oc label -n $MONITOR_NAMESPACE secret ibm-entitlement for-backup=true
oc label -n $MONITOR_NAMESPACE secret monitor-kitt for-backup=true

# Custom secret name based on https://www.ibm.com/docs/en/masv-and-l/continuous-delivery?topic=management-uploading-public-certificates-in-red-hat-openshift
if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $MONITOR_NAMESPACE secret ${MAS_INSTANCE_ID}-public-tls for-backup=true
fi

#Showing labels of all Monitor resources
echo -e "\n=== Monitor Resources ==="
oc get -n $MONITOR_NAMESPACE monitorapps -l for-backup=true --show-labels
oc get -n $MONITOR_NAMESPACE monitorworkspaces -l for-backup=true --show-labels

echo -e "\n=== Monitor OperatorGroup/Subscriptions ==="
oc get -n $MONITOR_NAMESPACE operatorgroup.operators.coreos.com -l for-backup=true --show-labels
oc get -n $MONITOR_NAMESPACE subscription.operators.coreos.com  -l for-backup=true --show-labels

echo -e "\n=== Monitor Secrets ==="
oc get -n $MONITOR_NAMESPACE secret -l for-backup=true --show-labels

# Create local recipe
# ========================================================================================================================

export MAS_INSTANCE_ID
recipe_name="monitor/maximo-child-monitor-backup-restore.yaml"
local_recipe="monitor/maximo-child-monitor-backup-restore-local.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" \
    -v monitor_ns="$MONITOR_NAMESPACE" \
    '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); \
      gsub(/\$\{MONITOR_NAMESPACE\}/, monitor_ns); \
      print}' "$recipe_name" > ${local_recipe}
  echo "Recipe YAML file: ${local_recipe}"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/monitor"
fi

# Add Monitor namespace to includedNamespaces in core child recipe
local_core_recipe="maximo-child-core-backup-restore-local.yaml"
INCLUDE_NAMESPACE="${MONITOR_NAMESPACE}" yq -i '(.spec.groups[] | select(.name == "maximo-core-resources") | .includedNamespaces) |= . + [env(INCLUDE_NAMESPACE)]' ${local_core_recipe}

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
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["apps.mas.ibm.com"] and
    (.resources | contains(["monitorapps", "monitorworkspaces"])) and
    (.verbs | contains(["get", "list", "watch"]))
  )' > /dev/null

#add role
CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "monitorapps"
add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "monitorworkspaces"

# check if namespace is added to Fusion App CR.
add_ns_if_missing_from_fapp ${MONITOR_NAMESPACE}

echo -e "\nTo apply recipe:"
echo "oc -n $ISF_NAMESPACE apply -f ${local_recipe}"
