#!/bin/bash

# Labels Db2uinstance or Db2ucluster custom resources if present on the cluster

if [ "$#" -ne 1 ]; then
  echo "# Labels Db2uinstance or Db2ucluster custom resources if present on the cluster"
  echo "Usage: $0 <DB2U_NAMESPACE>"
  exit 1
fi

DB2U_NAMESPACE=$1
oc get db2uinstances -n $DB2U_NAMESPACE 2>&1 | grep -qv "No resources found" && oc label `oc get db2uinstances.db2u.databases.ibm.com -o name -n $DB2U_NAMESPACE` for-backup=true
oc get db2uclusters -n $DB2U_NAMESPACE 2>&1 | grep -qv "No resources found" && oc label `oc get db2uclusters.db2u.databases.ibm.com -o name -n $DB2U_NAMESPACE` for-backup=true
