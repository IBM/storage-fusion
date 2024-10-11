#!/bin/bash

##############################################################################
#Script Name	: preupgrade-patch.sh
#Description	: Utility to patch the FSI CRs before upgrading the Fusion operator
#Args       	:
#Author       	: Vineeth Nair
#Email         	: vineethvenunair98@gmail.com
##############################################################################

##############################################################################
# This utility will patch the FusionServiceInstance CRs present in the cluster
# to allow the Fusion operator upgrade to proceed without any issues
# Execute it from a bash shell where you have logged into the OpenShift cluster

function print_header() {
    echo "================================ $1 ================================"
}

print_header "Patching triggerCatSrcCreateStartTime field in FusionServiceInstance CRs"
oc get fusionserviceinstance -o jsonpath='{.items[*].metadata.name}' |tr ' ' '\n' | xargs -I {} oc patch fusionserviceinstance {} --type=merge --subresource=status -p '{"status": {"triggerCatSrcCreateStartTime": 0}}'

print_header "Patching currentInstallStartTime field in FusionServiceInstance CRs"
oc get fusionserviceinstance -o jsonpath='{.items[*].metadata.name}' |tr ' ' '\n' | xargs -I {} oc patch fusionserviceinstance {} --type=merge --subresource=status -p '{"status": {"currentInstallStartTime": 0}}'

print_header "Patching operatorUpgradeStartTime field in FusionServiceInstance CRs"
oc get fusionserviceinstance -o jsonpath='{.items[*].metadata.name}' |tr ' ' '\n' | xargs -I {} oc patch fusionserviceinstance {} --type=merge --subresource=status -p '{"status": {"operatorUpgradeStartTime": 0}}'

print_header "Patching operatorLastUpdateTime field in FusionServiceInstance CRs"
oc get fusionserviceinstance -o jsonpath='{.items[*].metadata.name}' |tr ' ' '\n' | xargs -I {} oc patch fusionserviceinstance {} --type=merge --subresource=status -p '{"status": {"operatorLastUpdateTime": 0}}'
