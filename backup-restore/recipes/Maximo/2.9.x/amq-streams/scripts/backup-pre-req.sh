#!/bin/bash

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

#Retrieving the Kafka Cluster and KafkaUser
KAFKA_CLUSTER=$(oc get -n $KAFKA_NAMESPACE kafkas.kafka.strimzi.io -o custom-columns=NAME:.metadata.name --no-headers)
KAFKA_USER=$(oc get -n $KAFKA_NAMESPACE kafkausers.kafka.strimzi.io -o custom-columns=NAME:.metadata.name --no-headers)

#Label all required resources for AMQ Streams
echo "=== Adding labels to resources ==="
oc label -n $KAFKA_NAMESPACE cm/kafka-metrics-config for-backup=true
oc label -n $KAFKA_NAMESPACE cm/kafka-logging-config for-backup=true
oc label -n $KAFKA_NAMESPACE secrets/${KAFKA_CLUSTER}-credentials for-backup=true
oc label -n $KAFKA_NAMESPACE kafkas.kafka.strimzi.io/${KAFKA_CLUSTER} for-backup=true
oc label -n $KAFKA_NAMESPACE kafkausers.kafka.strimzi.io/${KAFKA_USER} for-backup=true

#Showing labels of all resources
echo -e "\n=== ConfigMaps ==="
oc get -n $KAFKA_NAMESPACE --show-labels cm/kafka-metrics-config
oc get -n $KAFKA_NAMESPACE --show-labels cm/kafka-logging-config

echo -e "\n=== Secrets ==="
oc get -n $KAFKA_NAMESPACE --show-labels secrets/${KAFKA_CLUSTER}-credentials

echo -e "\n=== Kafka Resources ==="
oc get -n $KAFKA_NAMESPACE kafkas.kafka.strimzi.io/${KAFKA_CLUSTER} --show-labels
oc get -n $KAFKA_NAMESPACE kafkausers.kafka.strimzi.io/${KAFKA_USER} --show-labels

# Create local recipe
# ========================================================================================================================

echo -e "\n=== Creating recipe from template ==="
recipe_name="maximo-amq-streams-backup-restore.yaml"
if [[ -f $recipe_name ]]; then
  cp $recipe_name maximo-amq-streams-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-amq-streams-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/amq-streams"
fi
