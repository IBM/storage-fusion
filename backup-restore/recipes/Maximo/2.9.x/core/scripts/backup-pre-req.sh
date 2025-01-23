#!/bin/bash

# Default value for CORE_NAMESPACE (set later based on MAS_INSTANCE_ID)
CORE_NAMESPACE=""
DEFAULT_REPORTING_OPERATOR="dro"
DEFAULT_REPORTING_NAMESPACE="redhat-marketplace"
CUSTOM_CERTS=false

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n CORE_NAMESPACE    Specify the CORE namespace (default: mas-<MAS_INSTANCE_ID>-core)"
  echo "  --mas-instance-id MAS_INSTANCE_ID    Specify the MAS Instance ID (Required)"
  echo "  --reporting-operator REPORTING_OPERATOR Specify the Reporting Operator (default: $DEFAULT_REPORTING_OPERATOR)"
  echo "  --reporting-operator-ns REPORTING_OPERATOR_NAMESPACE Specify the Reporting Operator NAMESPACE (default: $DEFAULT_REPORTING_NAMESPACE)"
  echo "  --custom-certs  Allow script to label custom cert (default: false)"
}

yq_validate() {
  #Validate if yq is installed, required for 
  if command -v yq &> /dev/null
  then
      :
  else
      echo "yq is not installed"
      exit 1
  fi
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
      CORE_NAMESPACE=$1
      ;;
    --mas-instance-id )
      shift
      MAS_INSTANCE_ID=$1
      ;;
    --reporting-operator )
      shift
      REPORTING_OPERATOR=$1
      ;;
    --reporting-operator-ns )
      shift
      REPORTING_OPERATOR_NAMESPACE=$1
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

# Set default CORE_NAMESPACE if not provided
if [[ -z $CORE_NAMESPACE ]]; then
  CORE_NAMESPACE="mas-${MAS_INSTANCE_ID}-core"
fi

# Check if REPORTING_OPERATOR is set, otherwise use the default value
REPORTING_OPERATOR=${REPORTING_OPERATOR:-$DEFAULT_REPORTING_OPERATOR}


# Check if REPORTING_OPERATOR is set, otherwise use the default value
REPORTING_OPERATOR_NAMESPACE=${REPORTING_OPERATOR_NAMESPACE:-$DEFAULT_REPORTING_NAMESPACE}

# Add labels to application
# ========================================================================================================================

#Validate JDBCCfg exists and retrieve credentials
JDBC_CFG=$(oc get -n $CORE_NAMESPACE jdbccfg -o custom-columns=NAME:.metadata.name --no-headers)

#Validate KafkaCfg exists and retrieve its credentials
KAFKA_CFG=$(oc get -n $CORE_NAMESPACE kafkacfg -o custom-columns=NAME:.metadata.name --no-headers)

#Validate ObjectStorageCfg exists and retrieve its credentials
OBJECT_STORAGE_CFG=$(oc get -n $CORE_NAMESPACE objectstoragecfg -o custom-columns=NAME:.metadata.name --no-headers)

#Validate WatsonStudioCfg exists and retrieve its credentials
WATSON_STUDIO_CFG=$(oc get -n $CORE_NAMESPACE watsonstudiocfg -o custom-columns=NAME:.metadata.name --no-headers)

# Check if Grafana Dashboard exists
GRAFANAV4_DASHBOARD=$(oc get -n $CORE_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $CORE_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

#Label all required resources for MAS Core
echo "=== Adding labels to resources ==="
oc label -n $CORE_NAMESPACE secret ${MAS_INSTANCE_ID}-credentials-superuser   for-backup=true
oc label -n $CORE_NAMESPACE secret ibm-entitlement for-backup=true
oc label -n $CORE_NAMESPACE secret mongodb-mongoce-admin for-backup=true
oc label -n $CORE_NAMESPACE secret sls-registration-key for-backup=true
oc label -n $CORE_NAMESPACE secret ${REPORTING_OPERATOR}-apikey for-backup=true

#Label JDBC credentials if JDBCCfg exists
if [[ -n $JDBC_CFG ]]; then
  oc label -n $CORE_NAMESPACE secret mas-jdbc-credentials for-backup=true

  JDBC_CFG_CREDENTIALS=$(oc get -n $CORE_NAMESPACE jdbccfg $JDBC_CFG -o json | jq -r .spec.config.credentials.secretName)
  oc label -n $CORE_NAMESPACE secret $JDBC_CFG_CREDENTIALS for-backup=true
fi

#Label Kafka credentials if KafkaCfg exists
if [[ -n $KAFKA_CFG ]]; then
  oc label -n $CORE_NAMESPACE secret mas-kafka-credentials for-backup=true

  KAFKA_CFG_CREDENTIALS=$(oc get -n $CORE_NAMESPACE kafkacfg $KAFKA_CFG -o json | jq -r .spec.config.credentials.secretName)
  oc label -n $CORE_NAMESPACE secret $KAFKA_CFG_CREDENTIALS for-backup=true
fi

#Label ObjectStorage credentials if ObjectStorageCfg exists
if [[ -n $OBJECT_STORAGE_CFG ]]; then
  OBJECT_STORAGE_CFG_CREDENTIALS=$(oc get -n $CORE_NAMESPACE objectstoragecfg $OBJECT_STORAGE_CFG -o json | jq -r .spec.config.credentials.secretName)
  oc label -n $CORE_NAMESPACE secret $OBJECT_STORAGE_CFG_CREDENTIALS for-backup=true
fi

#Label WatsonStudio credentials if WatsonStudioCfg exists
if [[ -n $WATSON_STUDIO_CFG ]]; then
  WATSON_STUDIO_CFG_CREDENTIALS=$(oc get -n $CORE_NAMESPACE watsonstudiocfg $OBJECT_STORAGE_CFG -o json | jq -r .spec.config.credentials.secretName)
  oc label -n $CORE_NAMESPACE secret $WATSON_STUDIO_CFG_CREDENTIALS for-backup=true
fi

if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $CORE_NAMESPACE secret ${MAS_INSTANCE_ID}-cert-public for-backup=true
fi


#Showing labels of all resources
echo -e "\n=== Secrets ==="
oc get -n $CORE_NAMESPACE secrets -l for-backup=true


# Create local recipe
# ========================================================================================================================
echo -e "\n=== Creating recipe from template ==="
export MAS_INSTANCE_ID
export REPORTING_OPERATOR
if [[ $REPORTING_OPERATOR = "dro" ]]; then
    export REPORTING_OPERATOR_ENDPOINT="ibm-data-reporter"
else
    export REPORTING_OPERATOR_ENDPOINT="uds-endpoint"
fi

recipe_name="maximo-core-backup-restore.yaml"
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" \
    -v kafka_ns="$KAFKA_NAMESPACE" \
    -v reporting_endpoint="$REPORTING_OPERATOR_ENDPOINT" \
    -v reporting_ns="$REPORTING_OPERATOR_NAMESPACE" \
    '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); \
      gsub(/\$\{KAFKA_NAMESPACE\}/, kafka_ns); \
      gsub(/\$\{REPORTING_OPERATOR_ENDPOINT\}/, reporting_endpoint); \
      gsub(/\$\{REPORTING_OPERATOR_NAMESPACE\}/, reporting_ns); \
      print}' "$recipe_name" > maximo-core-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-core-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/core"
fi

local_recipe="maximo-core-backup-restore-local.yaml"
#Add JDBC resource type if found
if [[ -n $JDBC_CFG ]]; then
  awk '{gsub(/#IfDb2Uncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

#Add Kafka resource type if found
if [[ -n $KAFKA_CFG ]]; then
  awk '{gsub(/#IfKafkaUncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

#Add ObjectStorage resource type if found
if [[ -n $OBJECT_STORAGE_CFG ]]; then
  awk '{gsub(/#IfObjectStorageUncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

#Add WatsonStudio resource type if found
if [[ -n $WATSON_STUDIO_CFG ]]; then
  awk '{gsub(/#IfWatsonStudioUncomment/, ""); print}' $local_recipe > temp.yaml && mv temp.yaml $local_recipe
fi

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
