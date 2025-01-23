#!/bin/bash

oc label crd cassandradatacenters.cassandra.datastax.com custom-label=cassandra-operator
oc label crd cassandratasks.control.k8ssandra.io custom-label=cassandra-operator

oc label clusterrole cass-operator-manager-role custom-label=cassandra-operator
oc label clusterrolebinding cass-operator-manager-res-rolebinding custom-label=cassandra-operator

oc label validatingwebhookconfiguration cass-operator-validating-webhook-configuration custom-label=cassandra-operator

