#!/bin/bash

source maximo_env.sh

# Default value for AISERVICE_NAMESPACE (set later based on AI_INSTANCE_ID)
AISERVICE_NAMESPACE=""
AISERVICE_TENANT_NAMESPACE=""
MINIO_NAMESPACE="${MINIO_NAMESPACE:-minio}"

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help      Show this help message and exit"
  echo "  -n AISERVICE_NAMESPACE    Specify the AISERVICE namespace (default: aiservice-<AI_INSTANCE_ID>)"
  echo "  --ai-instance-id AI_INSTANCE_ID    Specify the AI Instance ID (Required)"
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
      AISERVICE_NAMESPACE=$1
      ;;
    --ai-instance-id )
      shift
      AI_INSTANCE_ID=$1
      ;;
    * )
      echo "Invalid option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# Check if AI_INSTANCE_ID is set
if [[ -z $AI_INSTANCE_ID ]]; then
  AI_INSTANCE_ID=$AI_INSTANCE_ID
fi

# Check if AI_INSTANCE_ID is still not set
if [[ -z $AI_INSTANCE_ID ]]; then
  echo "Error: --ai-instance-id is mandatory"
  usage
  exit 1
fi


# Set default AISERVICE_NAMESPACE if not provided
if [[ -z $AISERVICE_NAMESPACE ]]; then
  AISERVICE_NAMESPACE="aiservice-${AI_INSTANCE_ID}"
fi

# Discover tenant namespaces dynamically from aiservicetenant CRs
AISERVICE_TENANT_NAMESPACE=$(oc get aiservicetenant -n "$AISERVICE_NAMESPACE" \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
if [[ -z "$AISERVICE_TENANT_NAMESPACE" ]]; then
  echo "WARNING: No AI Service tenant namespaces found via CRs, defaulting to aiservice-${AI_INSTANCE_ID}-user"
  AISERVICE_TENANT_NAMESPACE="aiservice-${AI_INSTANCE_ID}-user"
else
  echo "Discovered tenant namespace(s): $AISERVICE_TENANT_NAMESPACE"
fi



# Add labels to application
# ========================================================================================================================

#Label resources in AI Service operator namespace
echo -e "\n=== Adding labels to AI Service operator namespace resources ==="
oc label -n "$AISERVICE_NAMESPACE" aiserviceapps "$AI_INSTANCE_ID" for-backup=true --overwrite 2>/dev/null || true
oc label -n "$AISERVICE_NAMESPACE" aiservicetenants --all for-backup=true --overwrite 2>/dev/null || true
oc label -n "$AISERVICE_NAMESPACE" \
  "$(oc get -n "$AISERVICE_NAMESPACE" operatorgroups.operators.coreos.com -o name)" \
  for-backup=true --overwrite 2>/dev/null || true
oc label -n "$AISERVICE_NAMESPACE" subscription.operators.coreos.com ibm-aiservice for-backup=true --overwrite 2>/dev/null || true
oc label -n "$AISERVICE_NAMESPACE" secret ibm-entitlement for-backup=true --overwrite 2>/dev/null || true

#Label resources in Open Data Hub operator namespace
echo -e "\n=== Adding labels to Open Data Hub namespace resources ==="
oc label -n "$ODH_NAMESPACE" modelcontrollers.components.platform.opendatahub.io --all for-backup=true --overwrite 2>/dev/null || true

#Label resources in AI Service tenant namespace
echo -e "\n=== Adding labels to AI Service tenant namespace(s) resources ==="
for tenant_ns in $AISERVICE_TENANT_NAMESPACE; do
  echo "Labeling resources in tenant namespace: $tenant_ns"
  oc label -n "$tenant_ns" deployment --all for-backup=true --overwrite 2>/dev/null || true
  oc label -n "$tenant_ns" secrets --all for-backup=true --overwrite 2>/dev/null || true
  oc label -n "$tenant_ns" configmaps --all for-backup=true --overwrite 2>/dev/null || true
  oc label -n "$tenant_ns" serviceaccounts --all for-backup=true --overwrite 2>/dev/null || true
  oc label -n "$tenant_ns" inferenceservices.serving.kserve.io --all for-backup=true --overwrite 2>/dev/null || true
done


#Showing labels of all resources
echo -e "\n=== AI service Resources ==="
oc get -n $AISERVICE_NAMESPACE aiserviceapps -l for-backup=true --show-labels
oc get -n $AISERVICE_NAMESPACE aiservicetenants -l for-backup=true --show-labels


echo -e "\n=== OperatorGroup/Subscriptions ==="
oc get -n $AISERVICE_NAMESPACE operatorgroup.operators.coreos.com -l for-backup=true --show-labels
oc get -n $AISERVICE_NAMESPACE subscription.operators.coreos.com  -l for-backup=true --show-labels

echo -e "\n=== Secrets ==="
oc get -n $AISERVICE_NAMESPACE secret -l for-backup=true --show-labels

# Create local recipe
# ========================================================================================================================

export AI_INSTANCE_ID
export AISERVICE_NAMESPACE
export AISERVICE_TENANT_NAMESPACE
export MINIO_NAMESPACE
export ODH_NAMESPACE

recipe_name="aiservice/maximo-child-aiservice-backup-restore.yaml"
local_recipe="aiservice/maximo-child-aiservice-backup-restore-local.yaml"
echo -e "\n=== Creating recipe from template ==="
if [[ -f $recipe_name ]]; then
  awk -v aiservice_id="$AI_INSTANCE_ID" \
      -v aiservice_ns="$AISERVICE_NAMESPACE" \
      -v aiservice_ns_upper="${AISERVICE_NAMESPACE^^}" \
      -v minio_ns="$MINIO_NAMESPACE" \
      -v reporting_ns="$REPORTING_OPERATOR_NAMESPACE" \
      -v db2_ns="$DB2_NAMESPACE" \
    '{gsub(/\$\{AI_INSTANCE_ID\}/, aiservice_id); \
      gsub(/\$\{AISERVICE_NAMESPACE\}/, aiservice_ns); \
      gsub(/\$\{MINIO_NAMESPACE\}/, minio_ns); \
      gsub(/\$\{REPORTING_OPERATOR_NAMESPACE\}/, reporting_ns); \
      gsub(/\$\{AISERVICE_NS_UPPER\}/, aiservice_ns_upper); \
      gsub(/\$\{DB2_NAMESPACE\}/, db2_ns); \
      print}' "$recipe_name" > "${local_recipe}"
  echo "Recipe YAML file: ${local_recipe}"
else
  echo "Template Recipe YAML file not found. Make sure to cd to maximo directory"
fi

echo -e "\n=== Adding Tenant hooks and sequences ==="

TEMPLATES="tenant-exec-hook-template.yaml inferenceservices-check-template.yaml tenant_patch_sequences_template.yaml inferenceservices-sequence-template.yaml"

for template in $TEMPLATES; do
  local_template=${template}.local
  >aiservice/${local_template}
  if [[ -f aiservice/${template} ]]; then
    for tenant_ns in $AISERVICE_TENANT_NAMESPACE; do
        awk -v aiservice_ns="$AISERVICE_NAMESPACE" \
            -v tenant_ns="${tenant_ns}" \
          '{gsub(/\$\{AISERVICE_NAMESPACE\}/, aiservice_ns); \
            gsub(/\$\{TENANT_NS\}/, tenant_ns); \
            print}' "aiservice/${template}" >> "aiservice/${local_template}"
        echo "Template YAML file: aiservice/${local_template}"
    done
  else
    echo "Template YAML file not found (aiservice/${template})."
  fi
done

sed -i '/#AddTenantPatchExecHookCommands/r aiservice/tenant-exec-hook-template.yaml.local' ${local_recipe}
sed -i '/#AddTenantInferenceServicesCheckHooks/r aiservice/inferenceservices-check-template.yaml.local' ${local_recipe}
sed -i '/#AddTenantPatchSequences/r aiservice/tenant_patch_sequences_template.yaml.local' ${local_recipe}
sed -i '/#AddTenantInferenceServicesChecks/r aiservice/inferenceservices-sequence-template.yaml.local' ${local_recipe}

#Remove all lines that contain comments from local recipe
awk '!/#/' $local_recipe > temp.yaml && mv temp.yaml $local_recipe

# Add tenant namespaces to all tenant groups in local recipe
TENANT_GROUPS="maximo-aiservice-tenant-resources restore-maximo-aiservice-tenant-resources"
for tenant_ns in $AISERVICE_TENANT_NAMESPACE; do
  for tenant_group in $TENANT_GROUPS; do
    INCLUDE_NAMESPACE="${tenant_ns}" TENANT_GROUP="${tenant_group}" yq -i \
    '(.spec.groups[] | select(.name == env(TENANT_GROUP)) | .includedNamespaces) |= . + [env(INCLUDE_NAMESPACE)]' \
    "${local_recipe}"
  done
done

echo "=== Applying Role and RoleBinding for manageapps and manageworkspaces access ==="

CLUSTERROLE="transaction-manager-ibm-backup-restore"

add_rule_if_missing ${CLUSTERROLE} "aiservice.ibm.com" "aiserviceapps"
add_rule_if_missing ${CLUSTERROLE} "aiservice.ibm.com" "aiservicetenants"
add_rule_if_missing ${CLUSTERROLE} "serving.kserve.io" "inferenceservices"

# check if namespaces are added to Fusion App CR
add_ns_if_missing_from_fapp "${AISERVICE_NAMESPACE}"
for tenant_ns in $AISERVICE_TENANT_NAMESPACE; do
  add_ns_if_missing_from_fapp "${tenant_ns}"
done
add_ns_if_missing_from_fapp "${MINIO_NAMESPACE}"

echo -e "\nTo apply recipe:"
echo "oc -n $ISF_NAMESPACE apply -f ${local_recipe}"
