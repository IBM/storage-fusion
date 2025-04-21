#!/bin/bash
# Download and run this script before upgrading to version 2.10.0 or higher
# from 2.9.1 or lower versions. Not needed if Fusion and Backup & Restore are already at 2.10.0 or higher.
# This script extract the CPU and Memory limit settings for operator from CSVs
# and persist them in a operators-resources configmap. In B&R 2.10 and higher version,
# for Fusion isf-prereq-operator-controller-manager and for Backup & Restore
# ibm-dataprotectionagent-controller-manager would take higher of the limits
# in the CSVs and operators-resources configmap and persist in both. 
# With that any higher CPU and Memory limits set on the cluster will be preserved.

LOG=/tmp/$(basename $0)_log.txt
rm -f "$LOG"
exec &> >(tee -a $LOG)
echo "Logging in $LOG"

err_exit()
{
        echo "ERROR:" "$@" >&2
        exit 1
}

check_cmd ()
{
   (type "$1" > /dev/null) || err_exit "$1  command not found"
}

check_cmd oc
check_cmd jq

oc whoami > /dev/null || err_exit "Not logged in a cluster"

_configmap=operators-resources

genrate_cm ()
{
  NS="$1"
  [[ -z $NS ]]  && echo "No namespace provided, returning" && return
  for CSV_NAME in $(oc -n $NS get csv -o name)
  do
      STATUS=$(oc -n $NS get $CSV_NAME -o custom-columns=:status.phase --no-headers)
      if [ "$STATUS" == "Pending" ] 
        then
          echo "Skipping pending CSV $CSV_NAME"
          continue
      fi
      echo "Capturing resources for ${CSV_NAME}"
      name=$(echo $CSV_NAME | cut -d"/" -f2 | cut -d"." -f1)
      # json struct to hold the resource data
      resource_json="{}"

      ns=$NS
      csv=$(oc get $CSV_NAME -n $NS -ojson)

      deployments=$(echo $csv | jq '.spec.install.spec.deployments')

      for deployment in $(echo $deployments | jq -c '.[]'); do
          dep_name=$(echo $deployment | jq -r '.name')
          echo "DEPLOYMENT $dep_name"

          containers_json="{}"

          containers=$(echo $deployment | jq -c '.spec.template.spec.containers')

          for container in $(echo "$containers" | jq -c '.[]'); do
              container_name=$(echo $container | jq -r '.name')
              echo "CONTAINER $container_name"
              cpu_limit=$(echo $container | jq -r '.resources.limits.cpu')
              memory_limit=$(echo $container | jq -r '.resources.limits.memory')

              jq_str="{\"$container_name\": {resources: {limits: {cpu: \"$cpu_limit\", memory: \"$memory_limit\"}}}}"
              container_details=$( jq -n "$jq_str")

              containers_json=$(echo "$containers_json" | jq --argjson container_details "$container_details" '. + $container_details')
          done
           RES_JQ_STR=". + {\"$dep_name\": {\"containers\": $containers_json}}"
          resource_json=$(echo "${resource_json}" | jq "$RES_JQ_STR")
      done
      cm_data=$(echo "${resource_json}" | jq -c .)
      output=$(oc get configmap ${_configmap} -n $NS 2> /dev/null)
      if [[ $? -ne 0 ]]; then
          echo "Config map ${_configmap} does not exist, creating it"
          cmdOutput=$(oc create configmap ${_configmap} -n $NS --from-literal=${name}=$cm_data)
          if [[ $? -ne 0 ]]; then
              err_exit "Failed to create ${_configmap}: ${cmdOutput}"
          fi
      else
          output=$(echo "$cm_data" | sed -e "s/\"/\\\\\"/g")
          cmdOutput=$(oc -n $NS patch --type json configmap ${_configmap} -p "[{\"op\": \"add\", \"path\": \"/data/$name\", \"value\": \"$output\"}]")
          if [[ $? -ne 0 ]]; then
              echo "Failed to update ${_configmap}: ${cmdOutput}"
          fi
      fi
  done
}

ver_greater_than_29 ()
{
    VER="$1"
    [ -z "$VER" ]  && return -1
    MJR=$(echo $VER | cut -d'.' -f1)
    MNR=$(echo $VER | cut -d'.' -f2)
    if [ "$MJR" -gt "2" ] || [ "$MNR" -gt "9" ]
     then
        return 0
    fi
    return -1
}

ISF_NS=$(oc get spectrumfusion -A -o custom-columns=:metadata.namespace --no-headers)
if [ -z "$ISF_NS" ]
 then
    err_exit "No Fusion install found. Exiting"
 else
    echo "Fusion namespace: $ISF_NS"
    ISF_VERSION=$(oc -n $ISF_NS get spectrumfusion -o custom-columns=:status.isfVersion --no-headers)
    if ( ver_greater_than_29 $ISF_VERSION ) && [ "$1" != "-f" ]
     then
        echo "Fusion is already at 2.10 or higher. Skipping Fusion"
     else
       genrate_cm "$ISF_NS"
    fi
fi


BR_NS=$(oc get dataprotectionagent -A -o custom-columns=:metadata.namespace --no-headers)
if [ -z "$BR_NS" ]
 then
    echo "No Backup & Restore install found, skipping"
 else
    echo "Backup & Restore namespace: $BR_NS"
    BR_VERSION=$(oc -n $BR_NS get dataprotectionagent -o custom-columns=:status.installedVersion --no-headers)
    if (ver_greater_than_29 $BR_VERSION) && [ "$1" != "-f" ]
     then
        echo "Backup & Restore already at 2.10 or higher. Skipping B&R"
     else
        genrate_cm "$BR_NS"
    fi
fi

