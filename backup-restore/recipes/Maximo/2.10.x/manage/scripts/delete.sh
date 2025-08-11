#!/bin/bash


oc get manageapps.apps.mas.ibm.com -o name | xargs oc delete
oc get manageworkspaces.apps.mas.ibm.com -o name | xargs oc delete
oc get truststores -o name | xargs oc delete

oc get subs -o name | xargs oc delete
oc get csv -o name | xargs oc delete

oc delete crd -l app.kubernetes.io/name=ibm-mas-manage 

oc project default
oc delete project mas-cpst3-manage
oc get project | grep mas-cpst3-manage
echo 'oc get project | grep mas-cpst3-manage '
