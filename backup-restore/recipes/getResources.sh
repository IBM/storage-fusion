#!/bin/zsh
# This script returns resource details that are backed up or restored by a job in IBM Storage Fusion Backup & Restore service.
# Usage: getResources.sh (backup | restore) <job id>
#        e.g. getResources.sh backup 9c1e7f2d-fd74-4bcc-b28e-6cb82785913a

if [[ -n $2 ]]; then
	if [[ $1 = "restore" ]]; then
		queryParam="?type=restore"
	else
		queryParam=""
	fi

	podName=$(oc get pod -n ibm-backup-restore --field-selector=status.phase=Running --selector=app=backup-service | grep backup-service | head -n 1 | cut -d ' ' -f1)

	oc exec -it $podName -n ibm-backup-restore -- curl -k https://backup-service:9443/dataprotection/backup-service/v1/logs/$2/resources$queryParam | jq

	echo "\n\n===== CSV format ====="
	oc exec -it $podName -n ibm-backup-restore -- curl -k https://backup-service:9443/dataprotection/backup-service/v1/logs/$2/resources$queryParam | jq -r '[.logs] | @sh' 
else
	echo "Usage: " $0 " (backup | restore) <job id>"
fi
