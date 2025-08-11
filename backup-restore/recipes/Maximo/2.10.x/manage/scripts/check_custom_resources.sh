#!/bin/bash

for i in `oc get crd -l app.kubernetes.io/name=ibm-mas-manage --no-headers | awk '{print $1}' | xargs`; do echo -e "\n=== $i ==="; oc get $i -A;  done
