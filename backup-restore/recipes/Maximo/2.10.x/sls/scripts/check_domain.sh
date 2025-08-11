#!/bin/bash

echo "=== licenseservices.sls.ibm.com ==="
oc get licenseservices.sls.ibm.com sls -o json -n ibm-sls | jq ".spec.domain"
