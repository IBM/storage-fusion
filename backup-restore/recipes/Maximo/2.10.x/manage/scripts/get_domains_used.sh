#!/bin/bash

for i in `oc get crd -l app.kubernetes.io/name=ibm-mas-manage --no-headers | awk '{print $1}' | xargs`; do echo -e "\n=== $i ==="; for j in `oc get $i -o name | xargs`; do echo -e "\n$j"; oc get $j -o yaml | grep "test2"; done; done
