#!/bin/bash

#Default value for Db2 namespace
DEFAULT_NAMESPACE="db2u"

# Default Backup Restore namespace
DEFAULT_BR_NAMESPACE="ibm-backup-restore"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n DB2_NAMESPACE    Specify the Db2 namespace (default: $DEFAULT_NAMESPACE)"
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
      DB2_NAMESPACE=$1
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

# Check if SLS_NAMESPACE is set, otherwise use the default value
DB2_NAMESPACE=${DB2_NAMESPACE:-$DEFAULT_NAMESPACE}

# Check if BR_NAMESPACE is set, otherwise use the default value
BR_NAMESPACE=${BR_NAMESPACE:-$DEFAULT_BR_NAMESPACE}

# Create Role and RoleBinding for db2uclusters access.
echo "=== Creating Role and RoleBinding for db2uclusters access ==="
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: db2uclusters-reader
  namespace: ${DB2_NAMESPACE}
rules:
- apiGroups:
  - db2u.databases.ibm.com
  resources:
  - db2uclusters
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: transaction-manager-db2uclusters-binding
  namespace: ${DB2_NAMESPACE}
subjects:
- kind: ServiceAccount
  name: transaction-manager
  namespace: ${BR_NAMESPACE}
roleRef:
  kind: Role
  name: db2uclusters-reader
  apiGroup: rbac.authorization.k8s.io
EOF

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
