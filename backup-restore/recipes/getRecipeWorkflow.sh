#!/bin/bash
# This script returns recipe workflow logs of a backup or restore job in IBM Storage Fusion Backup & Restore service.
# Usage: getRecipeWorkflow.sh (backup | restore) <job uid | -n job name>
#        example -
#        getRecipeWorkflow.sh backup 9c1e7f2d-fd74-4bcc-b28e-6cb82785913a
#        getRecipeWorkflow.sh backup -n filebrowser-filebrowser-policy-apps.hostname-202402161744

usage() {
    echo "Usage: $0 (backup | restore) <job_uid | -n job_name>"
    exit 1
}

[[ "$1" = "-h" ]] && usage
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Error: Command line args not in range 2 and 3"
  usage
fi

case $1 in
    "backup"|"restore")
    job_type=$1
        if [ "$2" = "-n" ]; then
            option=$2
            if [ -z "$3" ]; then
                echo "Error: Job name is missing"
                usage
            fi
            job_name=$3
        elif [[ "$2" =~ ^-.* ]]; then
            echo "Error: Invalid option $2"
            usage
        else
            job_uid=$2
        fi
        ;;
    *)
        echo "Error: Unknown command: $1"
        usage
        ;;
esac

if [[ -n $2 ]]; then

	if [[ $1 = "restore" ]]; then
		queryParam="?type=restore"
	else
		queryParam=""
	fi

	fusionNs=$(oc get spectrumfusion -A --no-headers | cut -d" " -f1)
        [ "${job_name+set}" ] && job_uid=$(oc get f$job_type $job_name -n $fusionNs -o json | jq '.metadata.uid' | tr -d '"')
	brNs=$(oc -n "$fusionNs" get fusionserviceinstance ibm-backup-restore-service-instance -o json |jq -rc '[(.spec.parameters[]|"\n",.name,.value)]|@csv' | tr -d '"' | grep ",namespace," | cut -d"," -f3)

	if [[ -z "$brNs" ]]; then
		echo "Error: Backup & Restore service not found";exit
	fi

	podName=$(oc get pod -n "$brNs" --field-selector=status.phase=Running --selector=app=backup-service | grep backup-service | head -n 1 | cut -d ' ' -f1)

	if [[ -z "$podName" ]]; then
		echo "Error: Backup-service pod is not running";exit
	fi

	oc exec -it $podName -n $brNs -- curl -k https://backup-service:9443/dataprotection/backup-service/v1/logs/$job_uid/recipe$queryParam | jq

	echo "===== Log format ====="
	oc exec -it $podName -n $brNs -- curl -k https://backup-service:9443/dataprotection/backup-service/v1/logs/$job_uid/recipe$queryParam | jq -r '[.logs] | @sh'
else
        usage
fi
