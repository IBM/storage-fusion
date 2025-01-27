#!/bin/bash

# Variables are grouped by application, modify this script based on applications to backup and restore

# MAS Core / MAS Manage / MongoDb
export MAS_INSTANCE_ID=inst1

#MAS Core
export REPORTING_OPERATOR_NAMESPACE=redhat-marketplace
export REPORTING_OPERATOR=dro

# MAS Manage
export MAS_WORKSPACE_ID=dev

# MongoDb
export MONGODB_NAMESPACE=mongoce

# DB2
export DB2_NAMESPACE=db2u

# AMQ Streams
# MAS Core also requires this variable, if no kafka resource to backup, leave default value
export KAFKA_NAMESPACE=amq-streams

# SLS
export SLS_NAMESPACE=ibm-sls
