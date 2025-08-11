#!/bin/bash

#Default value for AMQ Streams namespace
DEFAULT_NAMESPACE="amq-streams"

# Default Backup Restore namespace
DEFAULT_BR_NAMESPACE="ibm-backup-restore"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n KAFKA_NAMESPACE    Specify the Kafka namespace (default: $DEFAULT_NAMESPACE)"
  echo "  --backup-restore-ns   Specify the Backup Restore namespace (default: ${DEFAULT_BR_NAMESPACE})"
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
    --backup-restore-ns )
      shift
      BR_NAMESPACE=$1
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

# Check if BR_NAMESPACE is set, otherwise use the default value
BR_NAMESPACE=${BR_NAMESPACE:-$DEFAULT_BR_NAMESPACE}

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
recipe_name="maximo-amq-streams-backup-restore.yaml"
if [[ -f $recipe_name ]]; then
  cp $recipe_name maximo-amq-streams-backup-restore-local.yaml
  echo "Recipe YAML file: maximo-amq-streams-backup-restore-local.yaml"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/amq-streams"
fi

local_recipe="maximo-amq-streams-backup-restore-local.yaml"
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

# Create required Role and RoleBinding.
echo -e "\n=== Creating Role and RoleBinding for Kafka access ==="

cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: amq-streams-permissions
  namespace: ${KAFKA_NAMESPACE}
rules:
  - apiGroups: ["kafka.strimzi.io"]
    resources:
      - kafkas
      - kafkausers
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: amq-streams-permissions-binding
  namespace: ${KAFKA_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: amq-streams-permissions
subjects:
  - kind: ServiceAccount
    name: transaction-manager
    namespace: ${BR_NAMESPACE}
EOF

echo -e "\n=== Script execution completed ==="
