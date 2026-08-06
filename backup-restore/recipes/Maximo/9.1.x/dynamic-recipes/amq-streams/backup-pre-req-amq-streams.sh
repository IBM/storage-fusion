#!/bin/bash

source maximo_env.sh

#Default value for AMQ Streams namespace
DEFAULT_NAMESPACE="amq-streams"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n KAFKA_NAMESPACE    Specify the Kafka namespace (default: $DEFAULT_NAMESPACE)"
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
      KAFKA_NAMESPACE=$1
      ;;
    * )
      echo "Invalid option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# Check if KAFKA_NAMESPACE is set, otherwise use the default value
KAFKA_NAMESPACE=${KAFKA_NAMESPACE:-$DEFAULT_NAMESPACE}

# Add labels to application
# ========================================================================================================================

# Check if Grafana Dashboard exists
GRAFANAV4_DASHBOARD=$(oc get -n $KAFKA_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $KAFKA_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

#Retrieving the Kafka Cluster and KafkaUser
KAFKA_CLUSTER=$(oc get -n $KAFKA_NAMESPACE kafkas.kafka.strimzi.io -o custom-columns=NAME:.metadata.name --no-headers)
KAFKA_USER=$(oc get -n $KAFKA_NAMESPACE kafkausers.kafka.strimzi.io -o custom-columns=NAME:.metadata.name --no-headers)

#Label all required resources for AMQ Streams
echo "=== Adding labels to resources ==="
oc label -n $KAFKA_NAMESPACE cm/kafka-metrics-config for-backup=true
oc label -n $KAFKA_NAMESPACE cm/kafka-logging-config for-backup=true
oc label -n $KAFKA_NAMESPACE secrets/maskafka-credentials for-backup=true
oc label -n $KAFKA_NAMESPACE kafkas.kafka.strimzi.io/${KAFKA_CLUSTER} for-backup=true
oc label -n $KAFKA_NAMESPACE kafkausers.kafka.strimzi.io/${KAFKA_USER} for-backup=true

#Showing labels of all resources
echo -e "\n=== ConfigMaps ==="
oc get -n $KAFKA_NAMESPACE configmap -l for-backup=true --show-labels 

echo -e "\n=== Secrets ==="
oc get -n $KAFKA_NAMESPACE secrets -l for-backup=true --show-labels

echo -e "\n=== Kafka Resources ==="
oc get -n $KAFKA_NAMESPACE kafkas.kafka.strimzi.io/${KAFKA_CLUSTER} --show-labels
oc get -n $KAFKA_NAMESPACE kafkausers.kafka.strimzi.io/${KAFKA_USER} --show-labels

# Create local recipe
# ========================================================================================================================

echo -e "\n=== Creating recipe from template ==="
recipe_name="amq-streams/maximo-child-amq-streams-backup-restore.yaml"
local_recipe="amq-streams/maximo-child-amq-streams-backup-restore-local.yaml"
if [[ -f $recipe_name ]]; then
  awk -v kafka_ns="$KAFKA_NAMESPACE" \
    '{gsub(/\$\{KAFKA_NAMESPACE\}/, kafka_ns); \
      print}' "$recipe_name" > ${local_recipe}
  echo "Recipe YAML file: ${local_recipe}"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/amq-streams"
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

# Create required Role and RoleBinding.
echo -e "\n=== Creating Role and RoleBinding for Kafka access ==="

CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing ${CLUSTERROLE} "kafka.strimzi.io" "kafkas"
add_rule_if_missing ${CLUSTERROLE} "kafka.strimzi.io" "kafkausers"

# check if namespace is added to Fusion App CR.
APP_NAMESPACE=${KAFKA_NAMESPACE}
CORE_NAMESPACE="mas-${MAS_INSTANCE_ID}-core"
echo -e "\n=== Checking if ${APP_NAMESPACE} is added to Fusion App CR ==="
app_ns="$(oc get fapp -n ${ISF_NAMESPACE} ${CORE_NAMESPACE} -ojson | jq --arg APP_NAMESPACE "${APP_NAMESPACE}" '.spec.includedNamespaces[] | select(. == $APP_NAMESPACE)')"
if [[ -z "${app_ns}" ]]; then
   echo "${APP_NAMESPACE} not included, adding to Fusion App CR..."
   oc patch -n ${ISF_NAMESPACE} fapp ${CORE_NAMESPACE} --type=json -p='[{"op": "add", "path": "/spec/includedNamespaces/-", "value": "'${APP_NAMESPACE}'"}]'
else
   echo "${APP_NAMESPACE} already added."
fi

echo -e "\nTo apply recipe:"
echo "oc -n $ISF_NAMESPACE apply -f ${local_recipe}"
