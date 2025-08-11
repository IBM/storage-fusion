#!/bin/bash


oc get licenseclients.sls.ibm.com -o name | xargs oc delete
oc get licenseservices.sls.ibm.com -o name | xargs oc delete


oc delete subs -l operators.coreos.com/ibm-sls.ibm-sls=
oc delete csv -l operators.coreos.com/ibm-sls.ibm-sls=
oc delete csv -l operators.coreos.com/ibm-truststore-mgr.ibm-sls=

oc delete crd -l operators.coreos.com/ibm-sls.ibm-sls=

oc project default
oc delete project ibm-sls
oc get project | grep ibm-sls
echo 'oc get project | grep ibm-sls '
