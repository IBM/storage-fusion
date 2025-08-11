#!/bin/bash


echo "=== Update domain licenseservices.sls.ibm.com  ==="
oc patch licenseservices.sls.ibm.com sls --type merge  -p '{"spec":{"domain":"cpst3.maximo-vpc-test1-98b7318c91b01bd72490e80cc2328915-0000.us-east.containers.appdomain.cloud"}}' -n ibm-sls
