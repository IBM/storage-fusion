#!/bin/bash

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
MONGODB_NAMESPACE=${MONGO_NAMESPACE:-$DEFAULT_NAMESPACE}

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
recipe_name="maximo-mongodb-backup-restore.yaml"
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); print}' "$recipe_name" > maximo-mongodb-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-mongodb-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/mongodb"
fi
