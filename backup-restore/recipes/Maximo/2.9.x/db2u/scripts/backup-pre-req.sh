#!/bin/bash

#Default value for Db2 namespace
DEFAULT_NAMESPACE="db2u"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n DB2_NAMESPACE    Specify the Db2 namespace (default: $DEFAULT_NAMESPACE)"
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
      DB2_NAMESPACE=$1
      ;;
    * )
      echo "Invalid option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# Check if SLS_NAMESPACE is set, otherwise use the default value
DB2_NAMESPACE=${DB2_NAMESPACE:-$DEFAULT_NAMESPACE}

# Add labels to application
# ========================================================================================================================

#Label all required resources for Db2
echo "=== Adding labels to resources ==="
oc label -n $DB2_NAMESPACE `oc get db2uclusters.db2u.databases.ibm.com -o name -n $DB2_NAMESPACE` for-backup=true

#Showing labels of all resources
echo -e "\n=== Db2uclusters ==="
oc get -n $DB2_NAMESPACE db2uclusters -l for-backup=true

# Create local recipe
# ========================================================================================================================

echo -e "\n=== Creating recipe from template ==="
recipe_name="maximo-db2-backup-restore.yaml"
if [[ -f $recipe_name ]]; then
  awk -v db2_ns="$DB2_NAMESPACE" '{gsub(/\$\{DB2_NAMESPACE\}/, db2_ns); print}' "$recipe_name" > maximo-db2-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-db2-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/db2"
fi
