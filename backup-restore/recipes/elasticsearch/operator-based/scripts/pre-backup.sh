#!/bin/bash

# Prompt for Elasticsearch namespace
read -rp "Enter Elasticsearch namespace: " ELASTIC_NAMESPACE_INPUT

# Validate the namespace exists
if ! oc get namespace "$ELASTIC_NAMESPACE_INPUT" &>/dev/null; then
  echo "============>  Namespace '$ELASTIC_NAMESPACE_INPUT' does not exist in the cluster."
  exit 1
fi

export ELASTIC_NAMESPACE="$ELASTIC_NAMESPACE_INPUT"

# Get Elasticsearch instance
ELASTIC_INSTANCE=$(oc get elasticsearches.elasticsearch.k8s.elastic.co -n "$ELASTIC_NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

if [ -z "$ELASTIC_INSTANCE" ]; then
  echo "============>  No Elasticsearch instance found in namespace '$ELASTIC_NAMESPACE'."
  exit 1
fi

export ELASTIC_INSTANCE

# Switch project
oc project "$ELASTIC_NAMESPACE"

# Display vars
echo "ELASTIC_NAMESPACE=$ELASTIC_NAMESPACE"
echo "ELASTIC_INSTANCE=$ELASTIC_INSTANCE"

# Label the secret and subscription
echo "============>  Labels the secrets..."
oc label secret $ELASTIC_INSTANCE-es-xpack-file-realm for-fusion-backup=    
oc label subs elasticsearch-eck-operator-certified for-fusion-backup=
oc label $(oc get kibanas.kibana.k8s.elastic.co -o name) for-fusion-backup=

# Create Role & RoleBinding for auto-approving InstallPlans
echo "============>  Creating role and binding for InstallPlan auto-approval..."
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: additional-permissions-installplans
  namespace: ${ELASTIC_NAMESPACE}
rules:
- apiGroups: ["operators.coreos.com"]
  resources: ["installplans"]
  verbs: ["get", "list", "patch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: additional-permissions-installplans-binding
  namespace: ${ELASTIC_NAMESPACE}
subjects:
- kind: ServiceAccount
  name: marketplace-operator
  namespace: openshift-marketplace
roleRef:
  kind: Role
  name: additional-permissions-installplans
  apiGroup: rbac.authorization.k8s.io
EOF

# Create Role & RoleBinding to access Subscription
echo "============>  Creating role and binding to access Subscription..."
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: additional-permissions-subscription
  namespace: ${ELASTIC_NAMESPACE}
rules:
- apiGroups: ["operators.coreos.com"]
  resources: ["subscriptions"]
  verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: additional-permissions-subscription-binding
  namespace: ${ELASTIC_NAMESPACE}
subjects:
- kind: ServiceAccount
  name: marketplace-operator
  namespace: openshift-marketplace
roleRef:
  kind: Role
  name: additional-permissions-subscription
  apiGroup: rbac.authorization.k8s.io
EOF

# echo "Applying the elasticsearch-operator-based-recipe.yaml file..."
# oc apply -f elasticsearch-operator-based-recipe.yaml


NAMESPACE_IBM_SPECTRUM_FUSION_NS="ibm-spectrum-fusion-ns"

echo "============>  Fetching existing fapp: $ELASTIC_NAMESPACE in namespace $NAMESPACE_IBM_SPECTRUM_FUSION_NS..."

# Get the existing resource, inject the variables field, and apply it
oc get fapp "$ELASTIC_NAMESPACE" -n "$NAMESPACE_IBM_SPECTRUM_FUSION_NS" -o json | \
jq --arg instance "$ELASTIC_INSTANCE" '
  .spec.variables = [{"name": "ELASTIC_INSTANCE", "value": $instance}]
' | oc apply -f -

echo "============>  fapp '$ELASTIC_NAMESPACE' updated with variable ELASTIC_INSTANCE=$ELASTIC_INSTANCE"


echo "All steps completed successfully."
