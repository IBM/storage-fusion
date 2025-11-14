#!/bin/sh

case $1 in
	'hub')
		# Tuning Hub Backup Restore:
		# Long-running backup and restore jobs and increase ephemeral
		# size limit:
   		# change backupDatamoverTimeout from 20 minutes to 480
   		# (8 hours)
		# change restoreDatamoverTimeout from 20 minutes to 1200
		# (20 hours)
   		# change datamoverJobpodEphemeralStorageLimit from 2000Mi to
   		# 8000Mi or more
		# Long-running jobs:
   		# change cancelJobAfter from 3600000 milliseconds to 72000000
   		# (20 hours)
   		# Raise velero memory limits from 2Gi to 12Gi and
   		# ephemeral-storage from 500Mi to 30Gi
		oc patch dataprotectionagent dpagent -n ibm-backup-restore \
			--type merge \
			--patch '{
			  "spec": {
			    "transactionManager": {
			      "backupDatamoverTimeout": "480",
			      "restoreDatamoverTimeout": "1200",
			      "datamoverJobpodEphemeralStorageLimit": "8000Mi"
			    }
			  }
			}'
		oc patch configmap guardian-configmap -n ibm-backup-restore \
			--type merge \
			--patch '{
			  "data": {
			    "backupDatamoverTimeout": "480",
			    "restoreDatamoverTimeout": "1200",
			    "datamoverJobpodEphemeralStorageLimit": "8000Mi"
			  }
			}'
		oc patch deployment job-manager -n ibm-backup-restore \
			--patch '{
			  "spec": {
			    "template": {
			      "spec": {
			        "containers": [
			          {
			            "name": "job-manager-container",
			            "env": [
			              {
			                "name": "cancelJobAfter",
			                "value": "72000000"
			              }
			            ]
			          }
			        ]
			      }
			    }
			  }
			}'
		oc patch dataprotectionapplication velero \
			-n ibm-backup-restore \
			--type merge \
			--patch '{
			  "spec": {
			    "configuration": {
			      "velero": {
			        "podConfig": {
			          "resourceAllocations": {
			            "limits": {
			              "ephemeral-storage": "30Gi",
			              "memory": "12Gi"
			            }
			          }
			        }
			      }
			    }
			  }
		 	}'
		;;
	'checkhub')
		oc get dataprotectionagent dpagent -n ibm-backup-restore \
			-o yaml | grep -e backupDatamoverTimeout \
				-e restoreDatamoverTimeout \
				-e datamoverJobpodEphemeralStorageLimit
		oc get configmap guardian-configmap -n ibm-backup-restore \
			-o yaml | grep -e backupDatamoverTimeout \
				-e restoreDatamoverTimeout \
				-e datamoverJobpodEphemeralStorageLimit
		oc get deployment job-manager -n ibm-backup-restore \
			-o yaml | grep -A1 cancelJobAfter
		oc get dataprotectionapplication velero -n ibm-backup-restore \
			-o yaml | grep -A3 limits | tail -2
		;;
	'spoke')
		# Long-running backup and restore jobs and increase ephemeral
		# size limit:
		# change backupDatamoverTimeout from 20 minutes to 480
		# (8 hours)
		# change restoreDatamoverTimeout from 20 minutes to 1200
		# (20 hours)
		# change datamoverJobpodEphemeralStorageLimit from 2000Mi to
		# 8000Mi or more
   		# Raise velero memory limits from 2Gi to 12Gi and
   		# ephemeral-storage from 500Mi to 30Gi
		oc patch dataprotectionagent \
			ibm-backup-restore-agent-service-instance \
			-n ibm-backup-restore \
			--type merge \
			--patch '{
			  "spec": {
			    "transactionManager": {
			      "backupDatamoverTimeout": "480",
			      "restoreDatamoverTimeout": "1200",
			      "datamoverJobpodEphemeralStorageLimit": "8000Mi"
			    }
			  }
			}'
		oc patch configmap guardian-configmap -n ibm-backup-restore \
			--type merge \
			--patch '{
			  "data": {
			    "backupDatamoverTimeout": "480",
			    "restoreDatamoverTimeout": "1200",
			    "datamoverJobpodEphemeralStorageLimit": "8000Mi"
			  }
			}'
		oc patch dataprotectionapplication velero \
			-n ibm-backup-restore \
			--type merge \
			--patch '{
			  "spec": {
			    "configuration": {
			      "velero": {
			        "podConfig": {
			          "resourceAllocations": {
			            "limits": {
			              "ephemeral-storage": "30Gi",
			              "memory": "12Gi"
			            }
			          }
			        }
			      }
			    }
			  }
			}'
		;;
	'checkspoke')
		oc get dataprotectionagent \
			ibm-backup-restore-agent-service-instance \
			-n ibm-backup-restore -o yaml | \
			grep -e backupDatamoverTimeout \
				-e restoreDatamoverTimeout \
				-e datamoverJobpodEphemeralStorageLimit
		oc get configmap guardian-configmap -n ibm-backup-restore \
			-o yaml | grep -e backupDatamoverTimeout \
				-e restoreDatamoverTimeout \
				-e datamoverJobpodEphemeralStorageLimit
		oc get dataprotectionapplication velero -n ibm-backup-restore \
			-o yaml | grep -A3 limits | tail -2
		;;
	*) echo "$(basename "$0") [hub|checkhub|spoke|checkspoke]"
esac
