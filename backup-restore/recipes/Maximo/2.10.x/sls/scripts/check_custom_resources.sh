#!/bin/bash

for i in `oc get crd -l operators.coreos.com/ibm-sls.ibm-sls= --no-headers | awk '{print $1}' | xargs`; do echo -e "\n=== $i ==="; oc get $i -A;  done
