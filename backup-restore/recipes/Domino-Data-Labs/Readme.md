# Domino Data Labs - IBM Fusion backup and restore
Custom backup/restore recipe (Kenneth Salerno <kpsalerno@us.ibm.com>)

The purpose of this recipe is to backup and restore specific prerequisite
cluster-scoped resources, in additional to the namespace-scoped resources,
namely:
  - ClusterRoles
  - ClusterRoleBindings
  - CustomResourceDefinitions
  - IngressClasses
  - PriorityClasses
  - SecurityContextConstraints

Note: we also exclude certain resources to not bloat the backup and more
importantly to not break OpenShift Disaster Recovery (ODR) and VolSync

This recipe will cover all Domino namespaces with an Application definition:
  - domino-system
  - domino-platform (including the shared/blob PVCs)
  - domino-compute (excluding the shared/blob PVCs)

# 1) Fusion Application YAML
```
apiVersion: application.isf.ibm.com/v1alpha1
kind: Application
metadata:
  name: dominolab
  namespace: ibm-spectrum-fusion-ns
spec:
  appType: dominolab
  includedNamespaces: 
    - domino-system
    - domino-platform
    - domino-compute
```
# 2) Fusion Recipe YAML
```
apiVersion: spp-data-protection.isf.ibm.com/v1alpha1
kind: Recipe
metadata:
  name: domino-cluster-recipe
  namespace: domino-system
spec:
  appType: dominolab
  groups:
  - name: platform-volumes
    type: volume
    includedNamespaces:
    - domino-platform
  - name: compute-volumes
    type: volume
    essential: false
    includedNamespaces:
    - domino-compute
    labelSelector: dominodatalab.com/type notin (Workspace),app.kubernetes.io/name notin (hephaestus)
  - name: namespace-resources
    type: resource
    includedNamespaces:
    - domino-system
    - domino-platform
    - domino-compute
    excludedResourceTypes:
    - events
    - events.events.k8s.io
    - imagetags.openshift.io
    - pods
    - subscriptions.operators.coreos.com
    - clusterserviceversions.operators.coreos.com
    - installplans.operators.coreos.com
    - persistentvolumes
    - persistentvolumeclaims
    - replicasets
    - volumereplications.replication.storage.openshift.io
    - volumegroupreplications.replication.storage.openshift.io
    - replicationsources.volsync.backube
    - replicationdestinations.volsync.backube
    - endpointslices.discovery.k8s.io
    - endpoints
    - volumesnapshots.snapshot.storage.k8s.io
    - volumegroupsnapshots.groupsnapshot.storage.k8s.io
  - name: cluster-resources
    type: resource
    includeClusterResources: true
    includedResourceTypes:
    - clusterroles
    - clusterrolebindings
    - customresourcedefinitions.apiextensions.k8s.io
    - ingressclasses.networking.k8s.io
    - priorityclasses
    - securitycontextconstraints.security.openshift.io
  workflows:
  - failOn: essential-error
    name: backup
    sequence:
    - group: cluster-resources
    - group: namespace-resources
    - group: compute-volumes
    - group: platform-volumes
  - failOn: essential-error
    name: restore
    sequence:
    - group: platform-volumes
    - group: compute-volumes
    - group: cluster-resources
    - group: namespace-resources
```

# 3) Application and Recipe installation steps
Create Fusion application definition that spans multiple namespaces

Note: For applications deployed on a HCP managed cluster, apply on spoke
```
oc apply -f dominolab-cluster-application.yaml
```
Create recipe in domino-system namespace

Note: For applications deployed on a HCP managed cluster, apply on spoke
```
oc apply -f dominolab-cluster-recipe.yaml
```
Exclude domino-compute Shared and Blob PVCs from backup
```
oc label pvc -n domino-compute \
  domino-shared-store-domino-compute \
  domino-blob-store-domino-compute \
  velero.io/exclude-from-backup=true
```
Also exclude domino-compute Shared and Blob PVCs from RegionalDR
```
oc label pvc -n domino-compute \
  domino-shared-store-domino-compute \
  domino-blob-store-domino-compute \
  ramendr.openshift.io/exclude=true
```
From Hub's Fusion GUI, find Application "dominolab", add to backup policies

Then patch dominolab PolicyAssignments to use custom recipe
```
for i in $(oc get policyassignment -n ibm-spectrum-fusion-ns -o name | \
  grep /dominolab); do
  oc -n ibm-spectrum-fusion-ns \
    patch $i \
      --type merge \
      -p '{
        "spec": {
          "recipe": {
            "name": "domino-cluster-recipe",
            "namespace": "'domino-system'",
            "apiVersion": "spp-data-protection.isf.ibm.com/v1alpha1"
          }
        }
      }'
done
```
Note: although newer releases of Fusion automatically find recipes in a
namespace associated with a policyassignment, for Applications that span
multiple namespaces we need to patch the policyassignment manually here

# 4) Tune Fusion backup and restore settings (defaults will cancel your job)
```
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
		# (increase from 1 hour to 20 hours)
		# Raise velero memory limits from 2Gi to 12Gi and
		# ephemeral-storage from 500Mi to 30Gi
		# Raise backup-location-deployment limit from 1Gi to 4Gi
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
		oc scale deployment backup-location-deployment \
			-n ibm-backup-restore --replicas=0
		oc patch deployment backup-location-deployment \
			-n ibm-backup-restore \
			--patch '{
			  "spec": {
			    "template": {
			      "spec": {
			        "containers": [
			          {
			            "name": "backup-location-container",
			            "resources": {
			              "limits": {
			                "memory": "4Gi"
			              }
			            }
			          }
			        ]
			      }
			    }
			  }
			}'
		oc scale deployment backup-location-deployment \
			-n ibm-backup-restore --replicas=1
		;;
	'checkhub')
		echo "dpagent settings:"
		oc get dataprotectionagent dpagent -n ibm-backup-restore \
			-o yaml | grep -e backupDatamoverTimeout \
				-e restoreDatamoverTimeout \
				-e datamoverJobpodEphemeralStorageLimit
		echo "guardian-configmap settings:"
		oc get configmap guardian-configmap -n ibm-backup-restore \
			-o yaml | grep -e backupDatamoverTimeout \
				-e restoreDatamoverTimeout \
				-e datamoverJobpodEphemeralStorageLimit
		echo "job-manager deployment settings:"
		oc get deployment job-manager -n ibm-backup-restore \
			-o yaml | grep -A1 cancelJobAfter
		echo "velero settings:"
		oc get dataprotectionapplication velero -n ibm-backup-restore \
			-o yaml | grep -A3 limits | tail -4
		echo "backup-location-deployment settings:"
		oc get deployment backup-location-deployment \
			-n ibm-backup-restore -o yaml | grep -A3 limits
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
		echo "dpagent settings:"
		oc get dataprotectionagent \
			ibm-backup-restore-agent-service-instance \
			-n ibm-backup-restore -o yaml | \
			grep -e backupDatamoverTimeout \
				-e restoreDatamoverTimeout \
				-e datamoverJobpodEphemeralStorageLimit
		echo "guardian-configmap settings:"
		oc get configmap guardian-configmap -n ibm-backup-restore \
			-o yaml | grep -e backupDatamoverTimeout \
				-e restoreDatamoverTimeout \
				-e datamoverJobpodEphemeralStorageLimit
		echo "velero settings:"
		oc get dataprotectionapplication velero -n ibm-backup-restore \
			-o yaml | grep -A3 limits | tail -4
		;;
	*) echo "$(basename "$0") [hub|checkhub|spoke|checkspoke]"
esac
```

# 5) Restore steps for Domino Data Labs on a fresh (blank) cluster
   Perform these steps in this explicit order:
   1) Tune Fusion backup and restore settings (see above step 4)
   2) From Fusion GUI: restore Fusion catalog (Fusion service restore) - this
      is required when you have a new blank cluster freshly installed or when
      you lose your catalog
   3) From Fusion GUI: restore application "dominolab"
   4) Note that PVCs domino-shared-store-domino-compute and
      domino-blob-store-domino-compute in the domino-compute namespace were
      intentionally excluded from the backup.

      (The Blob and Shared PVCs in domino-compute must point to the same CephFS
      volumeHandles that the respective PVCs in the "domino-platform" project
      is using, otherwise you will have two independent versions of the blob
      and shared file systems in these two separate projects that will cause
      file-not-found issues in your workspaces when you upload new documents in
      the UI)

      First copy the PV that the domino-shared-store in domino-platform is
      pointing to, give it a unique name (append -copy to its name), and
      remove the uid, creationTimestamp, resourceVersion, finalizers, and
      remove the status and claimRef blocks.

      Then copy the PVC from domino-platform and change the PVC name to
      domino-shared-store-domino-compute, change the PV name to what you
      assigned your PV above, namespace to domino-compute, and remove the uid,
      resourceVersion, creationTimestamp, finalizers, bind/bound annotations
      and remove the status block.

      Repeat this process for the domino-blob-store-domino-compute PVC.

      Here is an automated script to accomplish the above steps:
      ```
      #!/bin/sh
      for i in domino-shared-store domino-blob-store; do
        oc get pv $(oc get pvc $i -n domino-platform \
          -o jsonpath='{.spec.volumeName}') -o json | \
          jq '.metadata.name += "-copy" | del(.metadata.uid) | del(.metadata.creationTimestamp) | del(.metadata.resourceVersion) | del(.metadata.finalizers) | del(.spec.claimRef) | del(.status)' | \
          oc apply -f -
        sleep 2
        oc get pvc $i -n domino-platform -o json | \
          jq '.metadata.name += "-domino-compute" | .metadata.namespace = "domino-compute" | del(.metadata.uid) | del(.metadata.creationTimestamp) | del(.metadata.resourceVersion) | del(.metadata.annotations."pv.kubernetes.io/bind-completed") | del(.metadata.annotations."pv.kubernetes.io/bound-by-controller") | del(.metadata.finalizers) | .spec.volumeName += "-copy" |  del(.status)' | \
          oc apply -f -
      done
      oc label pvc -n domino-compute \
        domino-shared-store-domino-compute \
        domino-blob-store-domino-compute \
        velero.io/exclude-from-backup=true
      oc label pvc -n domino-compute \
        domino-shared-store-domino-compute \
        domino-blob-store-domino-compute \
        ramendr.openshift.io/exclude=true
      ```

   5) From OpenShift Console: label nodes accordingly for your environment to
      schedule compute and platform pods:

      If using HCP NodePools:

      For platform workers:
      ```
      spec:
        nodeLabels:
          dominodatalab.com/node-pool: "platform"
      ```
      For compute workers:
      ```
      spec:
        nodeLabels:
          dominodatalab.com/node-pool: "default"
      ```

   6) Scale deployments down/up that rely on HashiCorp Vault running (their secrets won't be injected until Vault is up)

   Versions < 6.0:
   Validate if restore has generated valid certificates, if not run these
   additional steps:

   7) From OpenShift Console: delete CertificateRequests for hephaestus\*-tls
      in domino-compute NS

   8) From Linux shell: restart Domino using restart script here (this will
      also delete your hephaestus TLS secrets which is why we had to clear
      previous reqs)
      https://support.domino.ai/support/s/article/Restart-Script

# Backup recipe execution log example:
```
2025-12-01 21:20:33 [INFO]: === Backup & recipe validation ===
2025-12-01 21:20:33 [INFO]: App namespace: ibm-spectrum-fusion-ns name: dominolab
2025-12-01 21:20:33 [INFO]: Recipe found with labels = dp.isf.ibm.com/parent-recipe:domino-cluster-recipe and dp.isf.ibm.com/parent-recipe-namespace:domino-system is []
2025-12-01 21:20:33 [INFO]: Effective namespaces of application: ['domino-system', 'domino-platform', 'domino-compute']
2025-12-01 21:20:34 [INFO]: Job: fd59106d-3612-401e-82be-a3b99c7154c3 
Recipe name: domino-cluster-recipe 
Details: name: domino-cluster-recipe, namespace: domino-system, app_type: dominolab, version: 10.1.12, clusterId: 3a05cc5d-d9b6-4014-82cd-47cdb8386096, applicationId: 50ae2862-3718-426c-aabb-22dac1e727fe, jobId: fd59106d-3612-401e-82be-a3b99c7154c3, volume_groups[0]: platform-volumes, volume_groups[1]: compute-volumes, resource_groups[0]: namespace-resources, resource_groups[1]: cluster-resources, workflows[0]: backup, workflows[1]: restore
2025-12-01 21:20:34 [INFO]: Evaluating volume group platform-volumes with 8 pvc candidates...
2025-12-01 21:20:36 [INFO]: Evaluating volume group compute-volumes with 8 pvc candidates...
2025-12-01 21:20:36 [INFO]: Looking for pvcs with label 'dominodatalab.com/type notin (Workspace),app.kubernetes.io/name notin (hephaestus)'
2025-12-01 21:20:36 [INFO]: Looking for pvcs with or_select_labels 'None'
2025-12-01 21:20:37 [INFO]: The recipe "domino-cluster-recipe" for apptype "dominolab" in namespace "domino-system" was validated.
2025-12-01 21:20:37 [INFO]: === Recipe execution ===
2025-12-01 21:20:37 [INFO]: Job fd59106d-3612-401e-82be-a3b99c7154c3 recipe domino-cluster-recipe starting execution
2025-12-01 21:20:37 [INFO]: Starting workflow "backup" of recipe "domino-system:domino-cluster-recipe" ...
2025-12-01 21:20:37 [INFO]: Executing workflow: backup in context backup
2025-12-01 21:20:37 [INFO]: Start execution sequence "group/cluster-resources" ...
2025-12-01 21:20:47 [INFO]: The backup operation of resources from namespace ['domino-compute', 'domino-system', 'domino-platform'] completed successfully.
2025-12-01 21:20:49 [INFO]: End execution sequence "group/cluster-resources" completed successfully.
2025-12-01 21:20:49 [INFO]: Start execution sequence "group/namespace-resources" ...
2025-12-01 21:21:02 [INFO]: The backup operation of resources from namespace ['domino-compute', 'domino-system', 'domino-platform'] completed successfully.
2025-12-01 21:21:02 [INFO]: End execution sequence "group/namespace-resources" completed successfully.
2025-12-01 21:21:02 [INFO]: Start execution sequence "group/compute-volumes" ...
2025-12-01 21:21:02 [INFO]: Reevaluating inventory...
2025-12-01 21:21:02 [INFO]: Effective namespaces of application: ['domino-system', 'domino-platform', 'domino-compute']
2025-12-01 21:21:03 [INFO]: Job: fd59106d-3612-401e-82be-a3b99c7154c3 
Recipe name: domino-cluster-recipe 
Details: name: domino-cluster-recipe, namespace: domino-system, app_type: dominolab, version: 10.1.12, clusterId: 3a05cc5d-d9b6-4014-82cd-47cdb8386096, applicationId: 50ae2862-3718-426c-aabb-22dac1e727fe, jobId: fd59106d-3612-401e-82be-a3b99c7154c3, volume_groups[0]: platform-volumes, volume_groups[1]: compute-volumes, resource_groups[0]: namespace-resources, resource_groups[1]: cluster-resources, workflows[0]: backup, workflows[1]: restore
2025-12-01 21:21:03 [INFO]: Evaluating volume group platform-volumes with 8 pvc candidates...
2025-12-01 21:21:05 [INFO]: Evaluating volume group compute-volumes with 8 pvc candidates...
2025-12-01 21:21:05 [INFO]: Looking for pvcs with label 'dominodatalab.com/type notin (Workspace),app.kubernetes.io/name notin (hephaestus)'
2025-12-01 21:21:05 [INFO]: Looking for pvcs with or_select_labels 'None'
2025-12-01 21:21:06 [INFO]: The recipe "domino-cluster-recipe" for apptype "dominolab" in namespace "domino-system" was validated.
2025-12-01 21:21:06 [INFO]: Reevaluation complete: 2 volume groups
2025-12-01 21:21:06 [INFO]: Vols in vg: 1
2025-12-01 21:21:06 [INFO]: Volume from inventory: domino-compute:disappearing-volume-troublemaker
2025-12-01 21:21:06 [INFO]: Executing VolumeGroup compute-volumes with workflow type backup...
2025-12-01 21:21:06 [INFO]: Including volume: domino-compute:disappearing-volume-troublemaker
2025-12-01 21:21:06 [INFO]: Starting CSI snapshot of PVC disappearing-volume-troublemaker
2025-12-01 21:21:10 [ERROR]: Error: Processing of volume disappearing-volume-troublemaker failed with error "An unexpected error occurred during the backup. PVCNotFoundException('domino-compute/disappearing-volume-troublemaker') This error occurred while processing PersistentVolumeClaim disappearing-volume-troublemaker.".
2025-12-01 21:21:10 [INFO]: Start execution sequence "group/platform-volumes" ...
2025-12-01 21:21:11 [INFO]: Reevaluating inventory...
2025-12-01 21:21:11 [INFO]: Effective namespaces of application: ['domino-system', 'domino-platform', 'domino-compute']
2025-12-01 21:21:11 [INFO]: Job: fd59106d-3612-401e-82be-a3b99c7154c3 
Recipe name: domino-cluster-recipe 
Details: name: domino-cluster-recipe, namespace: domino-system, app_type: dominolab, version: 10.1.12, clusterId: 3a05cc5d-d9b6-4014-82cd-47cdb8386096, applicationId: 50ae2862-3718-426c-aabb-22dac1e727fe, jobId: fd59106d-3612-401e-82be-a3b99c7154c3, volume_groups[0]: platform-volumes, volume_groups[1]: compute-volumes, resource_groups[0]: namespace-resources, resource_groups[1]: cluster-resources, workflows[0]: backup, workflows[1]: restore
2025-12-01 21:21:12 [INFO]: Evaluating volume group platform-volumes with 7 pvc candidates...
2025-12-01 21:21:13 [INFO]: Evaluating volume group compute-volumes with 7 pvc candidates...
2025-12-01 21:21:13 [INFO]: Looking for pvcs with label 'dominodatalab.com/type notin (Workspace),app.kubernetes.io/name notin (hephaestus)'
2025-12-01 21:21:13 [INFO]: Looking for pvcs with or_select_labels 'None'
2025-12-01 21:21:13 [INFO]: The recipe "domino-cluster-recipe" for apptype "dominolab" in namespace "domino-system" was validated.
2025-12-01 21:21:14 [INFO]: Reevaluation complete: 2 volume groups
2025-12-01 21:21:14 [INFO]: Vols in vg: 2
2025-12-01 21:21:14 [INFO]: Volume from inventory: domino-platform:domino-blob-store
2025-12-01 21:21:14 [INFO]: Volume from inventory: domino-platform:domino-shared-store
2025-12-01 21:21:14 [INFO]: Executing VolumeGroup platform-volumes with workflow type backup...
2025-12-01 21:21:14 [INFO]: Including volume: domino-platform:domino-blob-store
2025-12-01 21:21:14 [INFO]: Including volume: domino-platform:domino-shared-store
2025-12-01 21:21:14 [INFO]: Starting CSI snapshot of PVC domino-blob-store
2025-12-01 21:21:14 [INFO]: Starting CSI snapshot of PVC domino-shared-store
2025-12-01 21:21:14 [INFO]: Reevaluation complete: 2 volume groups
2025-12-01 21:21:14 [INFO]: Vols in vg: 2
2025-12-01 21:21:14 [INFO]: Volume from inventory: domino-platform:domino-blob-store
2025-12-01 21:21:14 [INFO]: Volume from inventory: domino-platform:domino-shared-store
2025-12-01 21:21:14 [INFO]: Executing VolumeGroup platform-volumes with workflow type backup...
2025-12-01 21:21:14 [INFO]: Including volume: domino-platform:domino-blob-store
2025-12-01 21:21:14 [INFO]: Including volume: domino-platform:domino-shared-store
2025-12-01 21:21:14 [INFO]: Starting CSI snapshot of PVC domino-blob-store
2025-12-01 21:21:14 [INFO]: Starting CSI snapshot of PVC domino-shared-store
2025-12-01 21:21:17 [INFO]: End execution sequence "group/platform-volumes" completed successfully.
2025-12-01 21:21:17 [INFO]: Execution of workflow backup completed. Number of failed commands: 1, 0 are essential
2025-12-01 21:21:17 [INFO]: Execution of workflow "backup" of recipe "domino-system:domino-cluster-recipe" completed successfully.
2025-12-01 21:21:17 [INFO]: Recipe executed. Fail Count=0, rollback=False, last failed command: 
2025-12-01 21:21:20 [INFO]: === Post recipe execution ===
2025-12-01 21:21:36 [INFO]: Data upload is in progress. Successfully transferred 0.
2025-12-01 21:22:01 [INFO]: Cleanup the snapshots created during the backup.
2025-12-01 21:22:01 [INFO]: Deleting snapshot 6537ffab-3abd-438a-84e1-17534d3d984a-1764624073.6692712 in ns domino-platform
2025-12-01 21:22:01 [INFO]: Deleting snapshot 28363fce-9596-4093-af37-acf7b34fb77a-1764624073.6878705 in ns domino-platform
2025-12-01 21:22:01 [INFO]: Copy backup job completed successfully.
2025-12-01 21:22:01 [INFO]: Cleanup the data uploads created during the backup.
```

# Restore recipe execution log example:
```
2025-12-01 21:24:09 [INFO]: === Restore & recipe validation ===
2025-12-01 21:24:24 [INFO]: Creating namespace: domino-system with labels: {'kubernetes.io/metadata.name': 'domino-system', 'pod-security.kubernetes.io/audit': 'restricted', 'pod-security.kubernetes.io/audit-version': 'latest', 'pod-security.kubernetes.io/warn': 'restricted', 'pod-security.kubernetes.io/warn-version': 'latest'} and annotations: {'openshift.io/description': '', 'openshift.io/display-name': '', 'openshift.io/requester': 'system:admin', 'openshift.io/sa.scc.mcs': 's0:c41,c40', 'openshift.io/sa.scc.supplemental-groups': '1001720000/10000', 'openshift.io/sa.scc.uid-range': '1001720000/10000', 'security.openshift.io/MinimallySufficientPodSecurityStandard': 'restricted'}
2025-12-01 21:24:24 [INFO]: Created namespace: domino-system
2025-12-01 21:24:24 [INFO]: Creating namespace: domino-platform with labels: {'kubernetes.io/metadata.name': 'domino-platform', 'pod-security.kubernetes.io/audit': 'restricted', 'pod-security.kubernetes.io/audit-version': 'latest', 'pod-security.kubernetes.io/warn': 'restricted', 'pod-security.kubernetes.io/warn-version': 'latest'} and annotations: {'openshift.io/description': '', 'openshift.io/display-name': '', 'openshift.io/requester': 'system:admin', 'openshift.io/sa.scc.mcs': 's0:c42,c9', 'openshift.io/sa.scc.supplemental-groups': '1001740000/10000', 'openshift.io/sa.scc.uid-range': '1001740000/10000', 'security.openshift.io/MinimallySufficientPodSecurityStandard': 'restricted'}
2025-12-01 21:24:24 [INFO]: Created namespace: domino-platform
2025-12-01 21:24:24 [INFO]: Creating namespace: domino-compute with labels: {'kubernetes.io/metadata.name': 'domino-compute', 'pod-security.kubernetes.io/audit': 'restricted', 'pod-security.kubernetes.io/audit-version': 'latest', 'pod-security.kubernetes.io/warn': 'restricted', 'pod-security.kubernetes.io/warn-version': 'latest'} and annotations: {'openshift.io/description': '', 'openshift.io/display-name': '', 'openshift.io/requester': 'system:admin', 'openshift.io/sa.scc.mcs': 's0:c42,c19', 'openshift.io/sa.scc.supplemental-groups': '1001760000/10000', 'openshift.io/sa.scc.uid-range': '1001760000/10000', 'security.openshift.io/MinimallySufficientPodSecurityStandard': 'restricted'}
2025-12-01 21:24:25 [INFO]: Created namespace: domino-compute
2025-12-01 21:24:25 [INFO]: Recipe name: domino-cluster-recipe 
Details: name: domino-cluster-recipe, namespace: domino-system, app_type: dominolab, version: 10.1.12, clusterId: 084032b2-f016-4ad7-af1c-99c12afb76dc, applicationId: 50ae2862-3718-426c-aabb-22dac1e727fe, jobId: e25742ea-7f14-416e-9235-61c4dd1ee0e1, volume_groups[0]: platform-volumes, volume_groups[1]: compute-volumes, resource_groups[0]: namespace-resources, resource_groups[1]: cluster-resources, workflows[0]: backup, workflows[1]: restore
2025-12-01 21:24:25 [WARNING]: Number of potential problems found in recipe "domino-cluster-recipe" for apptype "dominolab" in namespace "domino-system": "2".
2025-12-01 21:24:29 [INFO]: === Recipe execution ===
2025-12-01 21:24:29 [INFO]: Recipe domino-cluster-recipe starting execution
2025-12-01 21:24:29 [INFO]: Starting workflow "restore" of recipe "domino-system:domino-cluster-recipe" ...
2025-12-01 21:24:29 [INFO]: Executing workflow: restore in context restore
2025-12-01 21:24:29 [INFO]: Start execution sequence "group/platform-volumes" ...
2025-12-01 21:24:29 [INFO]: Executing VolumeGroup platform-volumes with workflow type restore...
2025-12-01 21:24:29 [INFO]: Including volume: domino-platform:domino-blob-store
2025-12-01 21:24:29 [INFO]: Including volume: domino-platform:domino-shared-store
2025-12-01 21:25:11 [INFO]: End execution sequence "group/platform-volumes" completed successfully.
2025-12-01 21:25:11 [INFO]: Start execution sequence "group/compute-volumes" ...
2025-12-01 21:25:11 [INFO]: Executing VolumeGroup compute-volumes with workflow type restore...
2025-12-01 21:25:11 [INFO]: End execution sequence "group/compute-volumes" completed successfully.
2025-12-01 21:25:11 [INFO]: Start execution sequence "group/cluster-resources" ...
2025-12-01 21:25:11 [INFO]: The backup operation of resources from namespace ['domino-system', 'domino-platform', 'domino-compute'] completed successfully.
2025-12-01 21:25:11 [INFO]: Executing Velero restore backup-resources-c529ccde-7f4b-4fb2-b19e-d1855f363e80 using backup backup-resources-933007f3-9175-4bde-8b54-889d9fdb2488 with include_namespaces ['domino-system', 'domino-platform', 'domino-compute'], exclude_namespaces None, label-selector None, include-resourcetypes ['clusterroles', 'clusterrolebindings', 'customresourcedefinitions.apiextensions.k8s.io', 'ingressclasses.networking.k8s.io', 'priorityclasses', 'securitycontextconstraints.security.openshift.io'], exclude-resourcetypes ['PersistentVolumeClaim', 'imagestreamtags.image.openshift.io', 'virtualmachineinstancemigrations.kubevirt.io', 'virtualmachineclones.clone.kubevirt.io'], include-cluster-resources True, namespace-mapping None, and restore-overwrite-resource False, or-label-selector None and labelSelectorType None
2025-12-01 21:25:24 [INFO]: End execution sequence "group/cluster-resources" completed successfully.
2025-12-01 21:25:24 [INFO]: Start execution sequence "group/namespace-resources" ...
2025-12-01 21:25:25 [INFO]: The backup operation of resources from namespace ['domino-compute', 'domino-platform', 'domino-system'] completed successfully.
2025-12-01 21:25:25 [INFO]: Executing Velero restore backup-resources-f2124b0e-7d52-437c-b8e2-33f5456c5d87 using backup backup-resources-c1fc4ef2-a14c-492e-b13c-625efce154e0 with include_namespaces ['domino-compute', 'domino-platform', 'domino-system'], exclude_namespaces None, label-selector None, include-resourcetypes None, exclude-resourcetypes ['events', 'events.events.k8s.io', 'imagetags.openshift.io', 'pods', 'subscriptions.operators.coreos.com', 'clusterserviceversions.operators.coreos.com', 'installplans.operators.coreos.com', 'persistentvolumes', 'persistentvolumeclaims', 'replicasets', 'volumereplications.replication.storage.openshift.io', 'volumegroupreplications.replication.storage.openshift.io', 'replicationsources.volsync.backube', 'replicationdestinations.volsync.backube', 'endpointslices.discovery.k8s.io', 'endpoints', 'volumesnapshots.snapshot.storage.k8s.io', 'volumegroupsnapshots.groupsnapshot.storage.k8s.io', 'PersistentVolumeClaim', 'imagestreamtags.image.openshift.io', 'virtualmachineinstancemigrations.kubevirt.io', 'virtualmachineclones.clone.kubevirt.io'], include-cluster-resources None, namespace-mapping None, and restore-overwrite-resource False, or-label-selector None and labelSelectorType None
2025-12-01 21:25:32 [INFO]: End execution sequence "group/namespace-resources" completed successfully.
2025-12-01 21:25:32 [INFO]: Execution of workflow restore completed. Number of failed commands: 0, 0 are essential
2025-12-01 21:25:32 [INFO]: Execution of workflow "restore" of recipe "domino-system:domino-cluster-recipe" completed successfully.
2025-12-01 21:25:32 [INFO]: === Post recipe execution ===
2025-12-01 21:25:32 [INFO]: Restore job completed successfully.
```
