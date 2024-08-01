#!/bin/bash

# Add labels to application
# ========================================================================================================================

#Default value for SLS namespace
DEFAULT_NAMESPACE="ibm-sls"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n SLS_NAMESPACE    Specify the SLS namespace (default: $DEFAULT_NAMESPACE)"
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
      SLS_NAMESPACE=$1
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
SLS_NAMESPACE=${SLS_NAMESPACE:-$DEFAULT_NAMESPACE}

#Label all required resources for SLS
echo "=== Adding labels to resources ==="
oc label -n $SLS_NAMESPACE secrets ibm-sls-mongo-credentials for-backup=true
oc label -n $SLS_NAMESPACE secrets ibm-sls-sls-entitlement for-backup=true
oc label -n $SLS_NAMESPACE secrets ibm-sls-sls-entitlement for-restore-overwrite=true

oc label -n $SLS_NAMESPACE licenseservices sls for-backup=true

oc label -n $SLS_NAMESPACE operatorgroups ibm-sls-operator-group for-backup=true
oc label -n $SLS_NAMESPACE subscriptions ibm-sls for-backup=true

#Showing labels of all resources
echo -e "\n=== Secrets ==="
oc get -n $SLS_NAMESPACE secrets -l for-backup=true

echo -e "\n=== LicenseServices ==="
oc get -n $SLS_NAMESPACE licenseservices -l for-backup=true

echo -e "\n=== OperatorGroups/Subscriptions ==="
oc get -n $SLS_NAMESPACE operatorgroups -l for-backup=true
oc get -n $SLS_NAMESPACE subscriptions -l for-backup=true

# Create local recipe
# ========================================================================================================================
echo -e "\n=== Creating recipe from template ==="
recipe_name="maximo-sls-backup-restore.yaml"
if [[ -f $recipe_name ]]; then
  cp $recipe_name maximo-sls-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-sls-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/sls"
fi
