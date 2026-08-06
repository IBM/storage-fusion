#!/bin/bash

source maximo_env.sh 

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

# Check if Grafana Dashboard exists
GRAFANAV4_DASHBOARD=$(oc get -n $OPTIMIZER_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $OPTIMIZER_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

#Label all required resources for MAS Optimizer
echo "=== Adding labels to resources ==="
oc label -n $OPTIMIZER_NAMESPACE optimizerapp $MAS_INSTANCE_ID for-backup=true 
oc label -n $OPTIMIZER_NAMESPACE optimizerworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true
oc label -n $OPTIMIZER_NAMESPACE $(oc get -n $OPTIMIZER_NAMESPACE operatorgroups.operators.coreos.com -o name) for-backup=true
oc label -n $OPTIMIZER_NAMESPACE subscription.operators.coreos.com ibm-mas-optimizer for-backup=true
oc label -n $OPTIMIZER_NAMESPACE secret ibm-entitlement for-backup=true

# Custom secret name based on https://www.ibm.com/docs/en/masv-and-l/continuous-delivery?topic=management-uploading-public-certificates-in-red-hat-openshift
if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $OPTIMIZER_NAMESPACE secret ${MAS_INSTANCE_ID}-cert-optimizer-public for-backup=true
fi

#Showing labels of all optimizer resources
echo -e "\n=== Optimizer Resources ==="
oc get -n $OPTIMIZER_NAMESPACE --show-labels optimizerapp $MAS_INSTANCE_ID
oc get -n $OPTIMIZER_NAMESPACE --show-labels optimizerworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID}

echo -e "\n=== OperatorGroup/Subscriptions ==="
oc get -n $OPTIMIZER_NAMESPACE operatorgroup.operators.coreos.com -l for-backup=true --show-labels
oc get -n $OPTIMIZER_NAMESPACE --show-labels subscription.operators.coreos.com ibm-mas-optimizer

echo -e "\n=== Secrets ==="
oc get -n $OPTIMIZER_NAMESPACE secret -l for-backup=true --show-labels

# Create local recipe
# ========================================================================================================================

export MAS_INSTANCE_ID
recipe_name="optimizer/maximo-child-optimizer-backup-restore.yaml"
local_recipe="optimizer/maximo-child-optimizer-backup-restore-local.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" \
    -v optimizer_ns="$OPTIMIZER_NAMESPACE" \
    '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); \
      gsub(/\$\{OPTIMIZER_NAMESPACE\}/, optimizer_ns); \
      print}' "$recipe_name" > ${local_recipe}
  echo "Recipe YAML file: ${local_recipe}"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/optimizer"
fi

# Add optimizer namespace to includedNamespaces in core child recipe
local_core_recipe="core/maximo-child-core-backup-restore-local.yaml"
INCLUDE_NAMESPACE="${OPTIMIZER_NAMESPACE}" yq -i '(.spec.groups[] | select(.name == "maximo-core-resources") | .includedNamespaces) |= . + [env(INCLUDE_NAMESPACE)]' ${local_core_recipe}

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

# Create role and rolebindings for Fusion transaction-manager
#first check it's already exists
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq -e \
  '.rules[] | select(
    .apiGroups == ["apps.mas.ibm.com"] and
    (.resources | contains(["optimizerapps", "optimizerworkspaces"])) and
    (.verbs | contains(["get", "list", "watch"]))
  )' > /dev/null

#if not, add it 
CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "optimizerapps"
add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "optimizerworkspaces"

# check if namespace is added to Fusion App CR.
add_ns_if_missing_from_fapp ${OPTIMIZER_NAMESPACE}

echo -e "\nTo apply recipe:"
echo "oc -n $ISF_NAMESPACE apply -f ${local_recipe}"
