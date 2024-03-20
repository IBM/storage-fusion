#!/bin/bash
# This script returns resource details that are backed up or restored by a job in IBM Storage Fusion Backup & Restore service.
# Usage: getResources.sh (backup | restore) <job name>
#        e.g. getResources.sh backup filebrowser-filebrowser-policy-apps.hostname-202402161744

if [[ -n $2 ]]; then
	if [[ $1 = "restore" ]]; then
		queryParam="?type=restore"
	else
		queryParam=""
	fi

	fusionNs=$(oc get spectrumfusion -A --no-headers | cut -d" " -f1)
        uid=$(oc get f$1 $2 -n $fusionNs -o json | jq '.metadata.uid' | tr -d '"')
    brNs=$(oc -n "$fusionNs" get fusionserviceinstance ibm-backup-restore-service-instance -o json |jq -rc '[(.spec.parameters[]|"\n",.name,.value)]|@csv' | tr -d '"' | grep ",namespace," | cut -d"," -f3)

    if [[ -z "$brNs" ]]; then
        echo "Error: Backup & Restore service not found";exit
    fi

	podName=$(oc get pod -n "$brNs" --field-selector=status.phase=Running --selector=app=backup-service | grep backup-service | head -n 1 | cut -d ' ' -f1)
	
	if [[ -z "$podName" ]]; then
		echo "Error: Backup-service pod is not running";exit
    fi

	oc exec -it $podName -n $brNs -- curl -k https://backup-service:9443/dataprotection/backup-service/v1/logs/$uid/resources$queryParam | jq

	echo "===== CSV format ====="
	oc exec -it $podName -n $brNs -- curl -k https://backup-service:9443/dataprotection/backup-service/v1/logs/$uid/resources$queryParam | jq -r '[.logs] | @sh'
else
	echo "Usage: " $0 " (backup | restore) <job name>"
fi
