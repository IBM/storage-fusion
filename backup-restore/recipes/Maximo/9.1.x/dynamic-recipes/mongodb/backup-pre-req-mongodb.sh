#!/bin/bash

source maximo_env.sh

#Default value for Mongo namespace
DEFAULT_NAMESPACE="mongoce"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n MONGODB_NAMESPACE    Specify the Mongo namespace (default: $DEFAULT_NAMESPACE)"
  echo "  --mas-instance-id MAS_INSTANCE_ID    Specify the MAS Instance ID (Required)"
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
      MONGODB_NAMESPACE=$1
      ;;
    --mas-instance-id )
      shift
      MAS_INSTANCE_ID=$1
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


# Check if MONGODB_NAMESPACE is set, otherwise use the default value
MONGODB_NAMESPACE=${MONGODB_NAMESPACE:-$DEFAULT_NAMESPACE}

#Determine if MVI App exists
VISUALINSPECTION_NAMESPACE="mas-${MAS_INSTANCE_ID}-visualinspection"
MVI_APP=$(oc get -n $VISUALINSPECTION_NAMESPACE visualinspectionapps -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

#Determine if Assist App exists
ASSIST_NAMESPACE="mas-${MAS_INSTANCE_ID}-assist"
ASSIST_APP=$(oc get -n $ASSIST_NAMESPACE assistapps -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

# Add SCC to User
# ========================================================================================================================

echo "=== Adding SCC to user ==="
oc adm policy add-scc-to-user anyuid -z mongodb-kubernetes-operator -n $MONGODB_NAMESPACE
oc adm policy add-scc-to-user anyuid -z mongodb-database -n $MONGODB_NAMESPACE


# Add labels to application
# ========================================================================================================================
echo -e "\n=== Adding labels to resources ==="
oc label crd mongodbcommunity.mongodbcommunity.mongodb.com mongodb-custom-label=manual

echo -e "\n=== CRD ==="
oc get crd mongodbcommunity.mongodbcommunity.mongodb.com --show-labels

# Create local recipe
# ========================================================================================================================

echo -e "\n=== Creating recipe from template ==="
export MAS_INSTANCE_ID
recipe_name="mongodb/maximo-child-mongodb-backup-restore.yaml"
local_recipe="mongodb/maximo-child-mongodb-backup-restore-local.yaml"
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" \
    -v mongodb_ns="$MONGODB_NAMESPACE" \
    '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); \
      gsub(/\$\{MONGODB_NAMESPACE\}/, mongodb_ns); \
      print}' "$recipe_name" > ${local_recipe}
  echo "Recipe YAML file: ${local_recipe}"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/mongodb"
fi

# Validate if Grafanav4 Dashboard exists
if oc get grafanadashboard.integreatly.org -n $MONGODB_NAMESPACE --no-headers 2>/dev/null | grep -q .; then
  awk '!/- grafanadashboards\.grafana\.integreatly\.org/ && NF' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

# Validate if Grafanav5 Dashboard exists
if oc get grafanadashboard.grafana.integreatly.org -n $MONGODB_NAMESPACE --no-headers 2>/dev/null | grep -q .; then
  awk '!/- grafanadashboards\.grafana\.integreatly\.org/ && NF' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

# If MVI exists, add hook
if [[ -n $MVI_APP ]]; then
  awk '{gsub(/#IfMVIUncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

# If Assist exists, add hook
if [[ -n $ASSIST_APP ]]; then
  awk '{gsub(/#IfAssistUncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

# Apply RBAC MongoDB.
echo -e "\n=== Creating Roles and RoleBindings for Mongodb ==="

CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing ${CLUSTERROLE} "mongodbcommunity.mongodb.com" "mongodbcommunity"

# check if namespace is added to Fusion App CR.
add_ns_if_missing_from_fapp ${MONGODB_NAMESPACE}

echo -e "\nTo apply recipe:"
echo "oc -n $ISF_NAMESPACE apply -f ${local_recipe}"
