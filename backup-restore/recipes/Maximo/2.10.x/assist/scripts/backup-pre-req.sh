#!/bin/bash

# Default value for ASSIST_NAMESPACE (set later based on MAS_INSTANCE_ID)
ASSIST_NAMESPACE=""
CUSTOM_CERTS=false

# Default Backup Restore namespace
DEFAULT_BR_NAMESPACE="ibm-backup-restore"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n ASSIST_NAMESPACE    Specify the ASSIST namespace (default: mas-<MAS_INSTANCE_ID>-assist)"
  echo "  --mas-instance-id MAS_INSTANCE_ID    Specify the MAS Instance ID (Required)"
  echo "  --mas-workspace-id MAS_WORKSPACE_ID    Specify the MAS Workspace ID (Required)"
  echo "  --custom-certs    Allow script to label custom cert (default: false)"
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
      ASSIST_NAMESPACE=$1
      ;;
    --mas-instance-id )
      shift
      MAS_INSTANCE_ID=$1
      ;;
    --mas-workspace-id )
      shift
      MAS_WORKSPACE_ID=$1
      ;;
    --custom-certs)
      CUSTOM_CERTS=true
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

# Check if MAS_WORKSPACE_ID is still not set
if [[ -z $MAS_WORKSPACE_ID ]]; then
  echo "Error: --mas-workspace-id is mandatory"
  usage
  exit 1
fi

# Set default ASSIST_NAMESPACE if not provided
if [[ -z $ASSIST_NAMESPACE ]]; then
  ASSIST_NAMESPACE="mas-${MAS_INSTANCE_ID}-assist"
fi

# Check if BR_NAMESPACE is set, otherwise use the default value
BR_NAMESPACE=${BR_NAMESPACE:-$DEFAULT_BR_NAMESPACE}

# Add labels to application
# ========================================================================================================================

# Check if Grafana Dashboard exists
GRAFANAV4_DASHBOARD=$(oc get -n $ASSIST_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $ASSIST_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

#Label all required resources for MAS Assist
echo "=== Adding labels to resources ==="
oc label -n $ASSIST_NAMESPACE assistapp $MAS_INSTANCE_ID for-backup=true 
oc label -n $ASSIST_NAMESPACE assistworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true
oc label -n $ASSIST_NAMESPACE $(oc get -n $ASSIST_NAMESPACE operatorgroups.operators.coreos.com -o name) for-backup=true
oc label -n $ASSIST_NAMESPACE subscription.operators.coreos.com ibm-mas-assist for-backup=true

oc label -n $ASSIST_NAMESPACE configmap assist-apppkgmgmt for-backup=true
oc label -n $ASSIST_NAMESPACE configmap ${MAS_INSTANCE_ID}-ema-redis-configmap for-backup=true
oc label -n $ASSIST_NAMESPACE configmap ${MAS_INSTANCE_ID}-ema-redis-haproxy for-backup=true
oc label -n $ASSIST_NAMESPACE configmap ${MAS_INSTANCE_ID}-ema-redis-probes for-backup=true
oc label -n $ASSIST_NAMESPACE configmap ${MAS_INSTANCE_ID}-ema-redis-secret-config for-backup=true

oc label -n $ASSIST_NAMESPACE secret ibm-entitlement for-backup=true
oc label -n $ASSIST_NAMESPACE secret assist-secret for-backup=true
oc label -n $ASSIST_NAMESPACE secret redis-ha-secret-host-and-port for-backup=true
oc label -n $ASSIST_NAMESPACE secret redis-url for-backup=true
oc label -n $ASSIST_NAMESPACE secret ${MAS_INSTANCE_ID}-ema-redis for-backup=true
oc label -n $ASSIST_NAMESPACE secret ${MAS_INSTANCE_ID}-ema-redis-cert for-backup=true

if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $ASSIST_NAMESPACE secret public-assist-tls for-backup=true
fi

#Showing labels of all resources
echo -e "\n=== Assist Resources ==="
oc get -n $ASSIST_NAMESPACE --show-labels assistapp
oc get -n $ASSIST_NAMESPACE --show-labels assistworkspaces

echo -e "\n=== OperatorGroup/Subscriptions ==="
oc get -n $ASSIST_NAMESPACE operatorgroup.operators.coreos.com -l for-backup=true --show-labels
oc get -n $ASSIST_NAMESPACE subscription.operators.coreos.com -l for-backup=true --show-labels 

echo -e "\n=== Secrets ==="
oc get -n $ASSIST_NAMESPACE secret -l for-backup=true --show-labels

echo -e "\n=== Configmaps ==="
oc get -n $ASSIST_NAMESPACE configmap -l for-backup=true --show-labels


# Create local recipe
# ========================================================================================================================

export MAS_INSTANCE_ID
recipe_name="maximo-assist-backup-restore.yaml"
local_recipe="maximo-assist-backup-restore-local.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); print}' "$recipe_name" > $local_recipe
  echo "Recipe YAML file: $local_recipe"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/assist"
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


# Create role and rolebindings for Fusion transaction-manager
# ========================================================================================================================
echo -e "\n=== Creating Role and RoleBinding for assist access from Fusion transaction-manager ==="
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: allow-assist-access
  namespace: $ASSIST_NAMESPACE
rules:
  - apiGroups: ["apps.mas.ibm.com"]
    resources: ["assistapps", "assistworkspaces"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bind-assist-access
  namespace: $ASSIST_NAMESPACE
subjects:
  - kind: ServiceAccount
    name: transaction-manager
    namespace: $BR_NAMESPACE
roleRef:
  kind: Role
  name: allow-assist-access
  apiGroup: rbac.authorization.k8s.io
EOF
