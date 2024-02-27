#!/bin/bash

oc label crd cassandradatacenters.cassandra.datastax.com custom-label=cassandra-operator
oc label crd cassandratasks.control.k8ssandra.io custom-label=cassandra-operator

oc label clusterrole cass-operator-manager-role custom-label=cassandra-operator
oc label clusterrolebinding cass-operator-manager-res-rolebinding custom-label=cassandra-operator

oc label serviceaccount cass-operator-controller-manager custom-label=cassandra-operator

oc label role cass-operator-leader-election-role custom-label=cassandra-operator

oc label role cass-operator-manager-role custom-label=cassandra-operator

oc label rolebinding cass-operator-leader-election-rolebinding custom-label=cassandra-operator
oc label rolebinding cass-operator-manager-rolebinding custom-label=cassandra-operator


oc label configmap cass-operator-manager-config custom-label=cassandra-operator

oc label service cass-operator-webhook-service custom-label=cassandra-operator 

oc label deployment cass-operator-controller-manager custom-label=cassandra-operator

oc label certificate cass-operator-serving-cert custom-label=cassandra-operator

oc label issuer cass-operator-selfsigned-issuer custom-label=cassandra-operator 
oc label validatingwebhookconfiguration cass-operator-validating-webhook-configuration custom-label=cassandra-operator

