#!/bin/bash

# Add labels to application
# ========================================================================================================================

# Default value for SLS namespace
DEFAULT_NAMESPACE="ibm-sls"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n SLS_NAMESPACE    Specify the SLS namespace (default: $DEFAULT_NAMESPACE)"
}

# Handling options specified in command line
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


# Check if Grafana Dashboard exists
GRAFANAV4_DASHBOARD=$(oc get -n $SLS_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $SLS_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)


# Label all required resources for SLS
echo "=== Adding labels to resources ==="
oc label -n $SLS_NAMESPACE secrets ibm-sls-mongo-credentials for-backup=true
oc label -n $SLS_NAMESPACE secrets ibm-sls-sls-entitlement for-backup=true
oc label -n $SLS_NAMESPACE secrets ibm-sls-sls-entitlement for-restore-overwrite=true

oc label -n $SLS_NAMESPACE licenseservices sls for-backup=true

oc label -n $SLS_NAMESPACE $(oc get -n $SLS_NAMESPACE operatorgroups.operators.coreos.com -o name) for-backup=true
oc label -n $SLS_NAMESPACE subscriptions.operators.coreos.com ibm-sls for-backup=true

# Label GrafanaDashboard v4 if exists
if [[ -n $GRAFANAV4_DASHBOARD ]]; then
  oc label -n $SLS_NAMESPACE grafanadashboards.integreatly.org $GRAFANAV4_DASHBOARD for-backup=true
fi

#Label GrafanaDashboard v5 if exists
if [[ -n $GRAFANAV5_DASHBOARD ]]; then
  oc label -n $SLS_NAMESPACE grafanadashboards.grafana.integreatly.org $GRAFANAV5_DASHBOARD for-backup=true
fi

# Showing labels of all resources
echo -e "\n=== Secrets ==="
oc get -n $SLS_NAMESPACE secrets -l for-backup=true

echo -e "\n=== LicenseServices ==="
oc get -n $SLS_NAMESPACE licenseservices -l for-backup=true

echo -e "\n=== OperatorGroups/Subscriptions ==="
oc get -n $SLS_NAMESPACE operatorgroups.operators.coreos.com -l for-backup=true
oc get -n $SLS_NAMESPACE subscriptions.operators.coreos.com -l for-backup=true

# Showing label of dashboards if exists
if [[ -n $GRAFANAV4_DASHBOARD ]]; then
  echo -e "\n=== Grafana v4 Dashboards ==="
  oc get -n $SLS_NAMESPACE grafanadashboards.integreatly.org -l for-backup=true
fi

if [[ -n $GRAFANAV5_DASHBOARD ]]; then
  echo -e "\n=== Grafana v5 Dashboards ==="
  oc get -n $SLS_NAMESPACE grafanadashboards.grafana.integreatly.org -l for-backup=true
fi


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

local_recipe="maximo-sls-backup-restore-local.yaml"
# Validate if Grafanav4 Dashboard exists
if [[ -n $GRAFANAV4_DASHBOARD ]]; then
  awk '{gsub(/#IfGrafanav4Uncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

# Validate if Grafanav5 Dashboard exists
if [[ -n $GRAFANAV5_DASHBOARD ]]; then
  awk '{gsub(/#IfGrafanav5Uncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

#Remove all lines that contain comments from local recipe
awk '!/#/' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
