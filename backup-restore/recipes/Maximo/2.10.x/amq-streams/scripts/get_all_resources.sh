#!/bin/bash

amq_namespace=$1
[ -z $amq_namespace ] && amq_namespace=amq-streams

echo -e "\n==== All resources..."
oc get all

echo -e "\n==== PVCs..."
oc get pvc

echo -e "\n==== kafkas.kafka.strimzi.io..."
oc get kafkas.kafka.strimzi.io
oc get kafkausers.kafka.strimzi.io

echo -e "\n==== clusterroles..."
oc get clusterroles -l olm.owner.namespace=$amq_namespace
echo -e "\n"
oc get clusterroles -l app=strimzi

echo -e "\n==== clusterrolebindings..."
oc get clusterrolebindings -l olm.owner.namespace=$amq_namespace 

echo -e "\n==== CRDs..."
oc get crds -l operators.coreos.com/$amq_namespace.$amq_namespace

echo -e "\n==== routes..."
oc get routes

echo -e "\n==== CSV..."
oc get csv

echo -e "\n==== subscriptions.operators.coreos.com..."
oc get subscriptions.operators.coreos.com
