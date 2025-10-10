#!/bin/bash
# Run this script on hub cluster that is stuck upgrading to the 2.9.1 release.

patch_usage() {
  echo "Usage: $0 (-help)"
  echo "Options:"
  echo "  -help  Display usage"
}

PATCH=
if [[ "$#" -ne 0 ]]; then
    patch_usage
    exit 0
fi

mkdir -p /tmp/br-upgrade-patch-291
if [ "$?" -eq 0 ]
then DIR=/tmp/br-upgrade-patch-291
else DIR=/tmp
fi
LOG=$DIR/br-upgrade-patch-291_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-upgrade-patch-291.sh script to $LOG"

#check_cmd:
# Returns:
#   0 on finding the command
#   1 if the command does not exist
check_cmd ()
{
   type $1 > /dev/null
   echo $?
}

REQUIREDCOMMANDS=("oc" "jq")
echo -e "Checking for required commands: ${REQUIREDCOMMANDS[*]}"
for COMMAND in "${REQUIREDCOMMANDS[@]}"; do
    IS_COMMAND=$(check_cmd $COMMAND)
    if [ $IS_COMMAND -ne 0 ]; then
        echo "ERROR: $COMMAND command not found, install $COMMAND command to apply patch"
        exit $IS_COMMAND
    fi
done

oc whoami > /dev/null || ( echo "Not logged in to your cluster" ; exit 1)

ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)
if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
if [ -n "$BR_NS" ]
 then
 HUB=true
else
   BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
fi

if [ -z "$BR_NS" ] 
 then
    echo "ERROR: No B&R installation found. Exiting."
    exit 1
fi

CONTAINER_NAME="manager"
RESOURCE_TYPE="ClusterServiceVersion"
RESOURCE_NAME="ibm-dataprotectionserver.v2.9.1"


if (oc get $RESOURCE_TYPE -n $BR_NS $RESOURCE_NAME -o yaml > "$DIR/$RESOURCE_NAME-$RESOURCE_TYPE.save.yaml")
then
    INDEX=$(oc get $RESOURCE_TYPE $RESOURCE_NAME -o json | jq ".spec.install.spec.deployments[0].spec.template.spec.containers | to_entries | map(select(.value.name == \"$CONTAINER_NAME\")) | .[0].key")
    if [ -z "$INDEX" ] || [ "$INDEX" == "null" ]; then
    echo "Error: Container '$CONTAINER_NAME' not found."
    else
    echo "Patching $RESOURCE_TYPE $RESOURCE_NAME"
    oc patch $RESOURCE_TYPE $RESOURCE_NAME --type=json \
        -p="[{\"op\":\"replace\", \"path\":\"/spec/install/spec/deployments/0/spec/template/spec/containers/${INDEX}/image\", \"value\":\"icr.io/cpopen/idp-server-operator@sha256:22432607e7a514cc210d3b9c97865c4eebc54f8fe857c50c3c520bf92cc81892\"}]"
    fi
else
    echo "ERROR: Failed to save original $RESOURCE_NAME $RESOURCE_TYPE. Skipped updates."
fi