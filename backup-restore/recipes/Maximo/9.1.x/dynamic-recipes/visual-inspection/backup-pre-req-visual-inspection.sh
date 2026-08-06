#!/bin/bash

source maximo_env.sh

# Default value for VISUALINSPECTION_NAMESPACE (set later based on MAS_INSTANCE_ID)
VISUALINSPECTION_NAMESPACE=""
CUSTOM_CERTS=false

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n VISUALINSPECTION_NAMESPACE    Specify the VISUALINSPECTION namespace (default: mas-<MAS_INSTANCE_ID>-visualinspection)"
  echo "  --mas-instance-id MAS_INSTANCE_ID    Specify the MAS Instance ID (Required)"
  echo "  --mas-workspace-id MAS_WORKSPACE_ID    Specify the MAS Workspace ID (Required)"
  echo "  --custom-certs    Allow script to label custom cert (default: false)"
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
      VISUALINSPECTION_NAMESPACE=$1
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

# Check if MAS_WORKSPACE_ID is set
if [[ -z $MAS_WORKSPACE_ID ]]; then
  MAS_WORKSPACE_ID=$MAS_WORKSPACE_ID
fi

# Check if MAS_WORKSPACE_ID is still not set
if [[ -z $MAS_WORKSPACE_ID ]]; then
  echo "Error: --mas-workspace-id is mandatory"
  usage
  exit 1
fi

# Set default VISUALINSPECTION_NAMESPACE if not provided
if [[ -z $VISUALINSPECTION_NAMESPACE ]]; then
  VISUALINSPECTION_NAMESPACE="mas-${MAS_INSTANCE_ID}-visualinspection"
fi

# Add labels to application
# ========================================================================================================================

# Check if Grafana Dashboard exists
GRAFANAV4_DASHBOARD=$(oc get -n $VISUALINSPECTION_NAMESPACE grafanadashboards.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
GRAFANAV5_DASHBOARD=$(oc get -n $VISUALINSPECTION_NAMESPACE grafanadashboards.grafana.integreatly.org -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)


#Label all required resources for MAS Visualinspection
echo "=== Adding labels to resources ==="
oc label -n $VISUALINSPECTION_NAMESPACE visualinspectionapps $MAS_INSTANCE_ID for-backup=true 
oc label -n $VISUALINSPECTION_NAMESPACE visualinspectionappworkspaces ${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID} for-backup=true
oc label -n $VISUALINSPECTION_NAMESPACE $(oc get -n $VISUALINSPECTION_NAMESPACE operatorgroups.operators.coreos.com -o name) for-backup=true
oc label -n $VISUALINSPECTION_NAMESPACE subscription.operators.coreos.com ibm-mas-visualinspection for-backup=true
oc label -n $VISUALINSPECTION_NAMESPACE secret ibm-entitlement for-backup=true

for configmap in $(oc get -n $VISUALINSPECTION_NAMESPACE configmap -o custom-columns=NAME:.metadata.name | grep ^custom-.*-config$); do
  oc label -n $VISUALINSPECTION_NAMESPACE configmap $configmap for-backup=true
done

# Mark only these two configmaps to be excluded from backup/restore
for configmap in custom-edgeman-config custom-ui-config; do
  if oc get -n $VISUALINSPECTION_NAMESPACE configmap $configmap &>/dev/null; then
    oc label -n $VISUALINSPECTION_NAMESPACE configmap $configmap custom-configmap-exclude=true
  fi
done

# Custom secret name based on https://www.ibm.com/docs/en/masv-and-l/continuous-delivery?topic=management-uploading-public-certificates-in-red-hat-openshift
if [[ $CUSTOM_CERTS = true ]]; then
  oc label -n $VISUALINSPECTION_NAMESPACE secret public-visualinspection-tls for-backup=true
fi


#Showing labels of all resources
echo -e "\n=== Visual Inspection Resources ==="
oc get -n $VISUALINSPECTION_NAMESPACE visualinspectionapps -l for-backup=true --show-labels
oc get -n $VISUALINSPECTION_NAMESPACE visualinspectionappworkspaces -l for-backup=true --show-labels


echo -e "\n=== OperatorGroup/Subscriptions ==="
oc get -n $VISUALINSPECTION_NAMESPACE operatorgroup.operators.coreos.com -l for-backup=true --show-labels
oc get -n $VISUALINSPECTION_NAMESPACE subscription.operators.coreos.com  -l for-backup=true --show-labels

echo -e "\n=== Secrets ==="
oc get -n $VISUALINSPECTION_NAMESPACE secret ibm-entitlement --show-labels
if [[ $CUSTOM_CERTS = true ]]; then
  oc get -n $VISUALINSPECTION_NAMESPACE secret public-visualinspection-tls
fi
oc get -n $VISUALINSPECTION_NAMESPACE secret -l for-backup=true --show-labels 2>/dev/null

echo -e "\n=== Custom Configmaps ==="
oc get -n $VISUALINSPECTION_NAMESPACE configmap -l for-backup=true 2>/dev/null

# Dump custom-edgeman-config and custom-ui-config to secrets and print to stdout
# These configmaps are excluded from restore (cluster-specific content: hostnames, CSP headers)
# The secrets are backed up and restored by Fusion; customer can apply the configmaps manually after adjusting values
echo -e "\n=== Backing up custom configmaps as secrets (excluded from configmap restore) ==="
for configmap in custom-edgeman-config custom-ui-config; do
  if oc get -n $VISUALINSPECTION_NAMESPACE configmap $configmap &>/dev/null; then
    secret_name="${configmap}-backup"
    cm_yaml=$(oc get -n $VISUALINSPECTION_NAMESPACE configmap $configmap -o yaml)

    # Print content to stdout for customer reference
    echo -e "\n--- Contents of configmap ${configmap} ---"
    echo "$cm_yaml"
    echo "--- End of ${configmap} ---"

    # Create or update a secret holding the configmap YAML, labelled for backup
    oc create secret generic $secret_name \
      -n $VISUALINSPECTION_NAMESPACE \
      --from-literal=configmap.yaml="$cm_yaml" \
      --dry-run=client -o yaml | \
      oc label -n $VISUALINSPECTION_NAMESPACE --local -f - for-backup=true -o yaml | \
      oc apply -n $VISUALINSPECTION_NAMESPACE -f -
    echo "Secret '${secret_name}' created/updated in namespace ${VISUALINSPECTION_NAMESPACE} with label for-backup=true"
  else
    echo "Warning: configmap '${configmap}' not found in namespace ${VISUALINSPECTION_NAMESPACE}, skipping."
  fi
done

# Create local recipe
# ========================================================================================================================
export MAS_INSTANCE_ID
recipe_name="visual-inspection/maximo-child-visual-inspection-backup-restore.yaml"
local_recipe="visual-inspection/maximo-child-visual-inspection-backup-restore-local.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v mas_id="$MAS_INSTANCE_ID" \
    -v vi_ns="$VISUALINSPECTION_NAMESPACE" \
    '{gsub(/\$\{MAS_INSTANCE_ID\}/, mas_id); \
      gsub(/\$\{VISUALINSPECTION_NAMESPACE\}/, vi_ns); \
      print}' "$recipe_name" > ${local_recipe}
  echo "Recipe YAML file: ${local_recipe}"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo/visual-inspection"
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

# add role
CLUSTERROLE="transaction-manager-ibm-backup-restore"
add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "visualinspectionapps"
add_rule_if_missing ${CLUSTERROLE} "apps.mas.ibm.com" "visualinspectionappworkspaces"

# check if namespace is added to Fusion App CR.
add_ns_if_missing_from_fapp ${VISUALINSPECTION_NAMESPACE}

echo -e "\nTo apply recipe:"
echo "oc -n $ISF_NAMESPACE apply -f ${local_recipe}"
