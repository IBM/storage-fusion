#!/bin/bash


oc get suites -o name | xargs oc delete
oc get workspaces -o name | xargs oc delete
oc get truststores -o name | xargs oc delete

oc get subs -o name | xargs oc delete
oc get csv -o name | xargs oc delete

oc get clusterrolebindings -o json | jq '.items[] | select(.subjects[]? | .namespace == "mas-cpst3-core") | .roleRef.name' | tr -d '"' | xargs oc delete clusterroles
oc get clusterrolebindings -o json | jq '.items[] | select(.subjects[]? | .namespace == "mas-cpst3-core") | .metadata.name' | tr -d '"' | xargs oc delete clusterrolebindings
oc delete crd -l app.kubernetes.io/name=ibm-mas,operators.coreos.com/ibm-mas.mas-cpst3-core=
oc get clusterissuer -o name | xargs oc delete

oc project default
oc delete project mas-cpst3-core
oc get project | grep mas-cpst3-core
echo 'oc get project | grep mas-cpst3-core '
