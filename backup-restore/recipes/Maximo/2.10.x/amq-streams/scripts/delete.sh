#!/bin/bash

amq_namespace=$1

[ -z $amq_namespace ] && amq_namespace=amq-streams

oc get kafkausers.kafka.strimzi.io -o name | xargs oc delete
oc get kafkas.kafka.strimzi.io -o name | xargs oc delete
sleep 30
oc get pvc -o name | xargs oc delete
oc get subscriptions.operators.coreos.com -o name | xargs oc delete
oc get csv -o name | xargs oc delete
oc get operatorgroups -o name | xargs oc delete

oc get clusterroles -l olm.owner.namespace=$amq_namespace -o name | xargs oc delete
oc get clusterroles -l app=strimzi  -o name | xargs oc delete
oc get clusterrolebindings -l olm.owner.namespace=$amq_namespace -o name | xargs oc delete

oc delete crd -l operators.coreos.com/$amq_namespace.$amq_namespace

oc project default
oc delete project $amq_namespace
oc get project | grep $amq_namespace
echo "oc get project | grep $amq_namespace" 
