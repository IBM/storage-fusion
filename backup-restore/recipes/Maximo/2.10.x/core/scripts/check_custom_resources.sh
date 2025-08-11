#!/bin/bash

for i in `oc get crd -l app.kubernetes.io/name=ibm-mas --no-headers | awk '{print $1}' | xargs`; do echo -e "\n=== $i ==="; oc get $i -A;  done

echo -e "\n=== truststores ==="
oc get truststores -A | grep -v ibm-sls
