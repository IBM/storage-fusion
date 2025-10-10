#!/bin/bash

# display usage information
usage() {
  echo "Usage: $0 [enable|disable]"
  echo "  enable:  Set the autoUpgrade parameter to true"
  echo "  disable: Set the autoUpgrade parameter to false"
  exit 1
}

#check_cmd:
# Returns:
#   0 on finding the command
#   1 if the command does not exist
check_cmd ()
{
   type $1 > /dev/null
   echo $?
}

if [ "$#" -ne 1 ]; then
  echo "Error: Incorrect number of arguments provided."
  usage
fi

case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
  enable)
    UPGRADE_VALUE="true"
    ;;
  disable)
    UPGRADE_VALUE="false"
    ;;
  *)
    echo "Error: Invalid argument '$1'."
    usage
    ;;
esac

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

echo "Attempting to set autoUpgrade to '$UPGRADE_VALUE'..."

INDEX=$(oc get fusionserviceinstance ibm-backup-restore-service-instance -n $ISF_NS -o json | jq '.spec.parameters | to_entries | map(select(.value.name == "autoUpgrade")) | .[0].key')


if [ -z "$INDEX" ] || [ "$INDEX" == "null" ]; then
  PATCH_JSON=$(printf '[{"op":"add", "path":"/spec/parameters/-", "value":{"name":"autoUpgrade","provided":true,"value":"%s"}}]' "$UPGRADE_VALUE")
else
  PATCH_JSON=$(printf '[{"op":"replace", "path":"/spec/parameters/%s/value", "value":"%s"}]' "$INDEX" "$UPGRADE_VALUE")
fi

echo "Applying patch: $PATCH_JSON"

if oc patch fusionserviceinstance ibm-backup-restore-service-instance -n $ISF_NS --type=json -p="$PATCH_JSON"; then
  echo "Success: Auto upgrade has been set to '$UPGRADE_VALUE'."
else
  echo "Error: Failed to update the auto upgrade setting."
  exit 1
fi
