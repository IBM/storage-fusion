# Domino Data Labs - IBM Fusion backup and restore
Custom backup/restore recipe (Kenneth Salerno <kpsalerno@us.ibm.com>)

The purpose of this recipe is to backup and restore specific prerequisite
cluster-scoped resources, namely:
  - ClusterRoles
  - ClusterRoleBindings
  - CustomResourceDefinitions
  - IngressClasses
  - SecurityContextConstraints

Note: we also exclude certain resources to not bloat the backup.

This recipe does not backup PVCs and should only be used on a blank namespace.
You must also schedule your application projects to be backed up using the
default recipe which will backup their namespace-scope resources and PVCs.

This recipe only needs to be utilized by one unique namespace. In the following
example, I create a new blank project named "domino-cluster" and register this
recipe to that project's Fusion PolicyAssignments.

# Summary of backup policy assignments:
  - namespace +"domino-cluster": domino-cluster-recipe recipe (select cluster-scope resources only)
  - namespace \*"domino-operator": default recipe (namespace-scoped resources)
  - namespace \*"domino-system": default recipe (namespace-scoped resources)
  - namespace \*"domino-platform": default recipe (namespace-scoped resources and PVCs)
  - namespace \*"domino-compute": default recipe (namespace-scoped resources and PVCs)

+: blank namespace for this custom recipe only

\*: your application is installed here

# 1) Recipe YAML
```
apiVersion: spp-data-protection.isf.ibm.com/v1alpha1
kind: Recipe
metadata:
  name: domino-cluster-recipe
  namespace: domino-cluster
spec:
  appType: fusion-backup-restore
  groups:
  - excludedResourceTypes:
    - event
    - event.events.k8s.io
    - imagetags.openshift.io
    - pod
    - subscriptions.operators.coreos.com
    - clusterserviceversions.operators.coreos.com
    - installplans.operators.coreos.com
    name: domino-cluster-resources
    type: resource
    includeClusterResources: true
  - backupRef: domino-cluster-resources
    includedResourceTypes:
    - clusterroles
    - clusterrolebindings
    - customresourcedefinitions.apiextensions.k8s.io
    - ingressclasses.networking.k8s.io
    - securitycontextconstraints.security.openshift.io
    name: domino-cluster-included-resources
    type: resource
  workflows:
  - failOn: any-error
    name: backup
    priority: 0
    sequence:
    - group: domino-cluster-resources
  - failOn: any-error
    name: restore
    priority: 0
    sequence:
    - group: domino-cluster-included-resources
```

# 2) Recipe installation steps
```
   #
   # create blank namespace "domino-cluster" to use with this custom recipe
   #
   oc new-project domino-cluster
   oc apply -f domino-cluster-recipe.yaml
   oc get frcpe -n domino-cluster
   #
   # 1) From Fusion GUI, assign domino-cluster project to your desired policies
   # 2) then apply domino-cluster-recipe Recipe to PolicyAssignments:
   #
   #    for example, here are a couple of PolicyAssignments on my system:
   #
   for i in \
     domino-cluster-daily-s3-1week-retention-apps.sts-pok-ocp-4.ww.pbm.ihost.com \
     domino-cluster-4hour-snapshot-3day-retention-apps.sts-pok-ocp-4.ww.pbm.ihost.com
   do
   oc -n ibm-spectrum-fusion-ns \
     patch policyassignment \
     $i \
     --type merge \
     -p '{
       "spec": {
         "recipe": {
           "name": "domino-cluster-recipe",
           "namespace": "'domino-cluster'",
           "apiVersion": "spp-data-protection.isf.ibm.com/v1alpha1"
         }
       }
     }'
   done
```
Note: newer releases of Fusion automatically apply the recipes it finds in
the project without requiring a patch to each PolicyAssignment.

# 3) Restore steps for Domino Data Labs on a fresh (blank) cluster
   Perform these steps in this explicit order:
   1) From Fusion GUI: restore Fusion catalog (Fusion service restore) - this
      is required when you have a new blank cluster freshly installed or when
      you lose your catalog
   2) From Fusion GUI: restore project "domino-cluster" (the one using this
      custom recipe to restore cluster-scope resources which are prerequisites
      for restoring your application projects domino-system, domino-platform
      and domino-compute)
   3) From Fusion GUI: restore project "domino-operator"
   4) From Fusion GUI: restore project "domino-system"
   5) From Fusion GUI: restore project "domino-platform"
   6) From Fusion GUI: restore project "domino-compute", however do NOT restore
      the domino-shared-store-domino-compute and
      domino-blob-store-domino-compute PVCs: check the option to select PVCs to
      restore and exclude these two PVCs in the domino-compute namespace.

      (The Blob and Shared PVCs must point to the same CephFS volumeHandles
      that the respective PVCs in the "domino-platform" project is using,
      otherwise you will have two independent versions of the blob and shared
      file systems in these two separate projects that will
      cause file-not-found issues between workspaces versus UI uploads)

      To create the domino-shared-store-domino-compute PVC in domino-compute,
      copy the PV that the domino-shared-store in domino-platform is pointing
      to, give it a unique name, remove the UID and claimRef block.

      Then copy the PVC and change the name to
      domino-shared-store-domino-compute, change the PV name to what you
      assigned your PV above, namespace to domino-compute, remove the UID.

      Repeat this process for the domino-blob-store-domino-compute PVC.

   7) From OpenShift Console: label nodes accordingly for your environment to
      schedule compute and platform pods:

      If using HCP NodePools:
      For platform workers:
      spec:
        nodeLabels:
          dominodatalab.com/node-pool: "platform"

      For compute workers:
      spec:
        nodeLabels:
          dominodatalab.com/node-pool: "default"

   Validate if restore has generated valid certificates, if not run these
   additional steps:

   8) From OpenShift Console: delete CertificateRequests for hephaestus\*-tls
      in domino-compute NS

   9) From Linux shell: restart Domino using restart script here (this will
      also delete your hephaestus TLS secrets which is why we had to clear
      previous reqs)
      https://support.domino.ai/support/s/article/Restart-Script

# Backup recipe execution: 43 seconds
```
2025-07-17 09:00:02 [INFO]: === Backup & recipe validation ===
2025-07-17 09:00:02 [INFO]: App namespace: ibm-spectrum-fusion-ns name: domino-cluster
2025-07-17 09:00:02 [INFO]: Recipe found with labels = dp.isf.ibm.com/parent-recipe:domino-cluster-recipe and dp.isf.ibm.com/parent-recipe-namespace:domino-cluster is []
2025-07-17 09:00:02 [INFO]: Effective namespaces of application: ['domino-cluster']
2025-07-17 09:00:03 [INFO]: Job: 11fde838-4cda-49dc-961f-d1f7813fcf81 
Recipe name: domino-cluster-recipe 
Details: name: domino-cluster-recipe, namespace: domino-cluster, app_type: fusion-backup-restore, version: 10.1.12, clusterId: c8bbcbfd-003d-4991-affc-804926289647, applicationId: d75720e8-7012-4b57-badc-aa94bd4cd70d, jobId: 11fde838-4cda-49dc-961f-d1f7813fcf81, resource_groups[0]: domino-cluster-resources, resource_groups[1]: domino-cluster-included-resources, workflows[0]: backup, workflows[1]: restore
2025-07-17 09:00:03 [INFO]: The recipe "domino-cluster-recipe" for apptype "fusion-backup-restore" in namespace "domino-cluster" was validated.
2025-07-17 09:00:03 [INFO]: === Recipe execution ===
2025-07-17 09:00:03 [INFO]: Job 11fde838-4cda-49dc-961f-d1f7813fcf81 recipe domino-cluster-recipe starting execution
2025-07-17 09:00:03 [INFO]: Starting workflow "backup" of recipe "domino-cluster:domino-cluster-recipe" ...
2025-07-17 09:00:03 [INFO]: Executing workflow: backup in context backup
2025-07-17 09:00:03 [INFO]: Start execution sequence "group/domino-cluster-resources" ...
2025-07-17 09:00:43 [INFO]: The backup operation of resources from namespace ['domino-cluster'] completed successfully.
2025-07-17 09:00:43 [INFO]: End execution sequence "group/domino-cluster-resources" completed successfully.
2025-07-17 09:00:43 [INFO]: Execution of workflow backup completed. Number of failed commands: 0, 0 are essential
2025-07-17 09:00:43 [INFO]: Execution of workflow "backup" of recipe "domino-cluster:domino-cluster-recipe" completed successfully.
2025-07-17 09:00:43 [INFO]: Recipe executed. Fail Count=0, rollback=False, last failed command: 
2025-07-17 09:00:43 [INFO]: === Post recipe execution ===
```

# Restore recipe execution: 29 seconds
```
2025-07-17 09:03:55 [INFO]: === Restore & recipe validation ===
2025-07-17 09:04:11 [INFO]: Creating namespace: domino-cluster with labels: {'kubernetes.io/metadata.name': 'domino-cluster', 'pod-security.kubernetes.io/audit': 'restricted', 'pod-security.kubernetes.io/audit-version': 'latest', 'pod-security.kubernetes.io/warn': 'restricted', 'pod-security.kubernetes.io/warn-version': 'latest'} and annotations: {'openshift.io/description': '', 'openshift.io/display-name': '', 'openshift.io/requester': 'system:admin', 'openshift.io/sa.scc.mcs': 's0:c28,c12', 'openshift.io/sa.scc.supplemental-groups': '1000780000/10000', 'openshift.io/sa.scc.uid-range': '1000780000/10000'}
2025-07-17 09:04:11 [INFO]: Namespace already exists. Continuing.
2025-07-17 09:04:11 [INFO]: Recipe name: domino-cluster-recipe 
Details: name: domino-cluster-recipe, namespace: domino-cluster, app_type: fusion-backup-restore, version: 10.1.12, clusterId: c8bbcbfd-003d-4991-affc-804926289647, applicationId: d75720e8-7012-4b57-badc-aa94bd4cd70d, jobId: f7d83e7b-eacd-4e4d-a4b7-c6cbc956f6b0, resource_groups[0]: domino-cluster-resources, resource_groups[1]: domino-cluster-included-resources, workflows[0]: backup, workflows[1]: restore
2025-07-17 09:04:11 [INFO]: The recipe "domino-cluster-recipe" for apptype "fusion-backup-restore" in namespace "domino-cluster" was validated.
2025-07-17 09:04:11 [INFO]: === Recipe execution ===
2025-07-17 09:04:11 [INFO]: Recipe domino-cluster-recipe starting execution
2025-07-17 09:04:11 [INFO]: Starting workflow "restore" of recipe "domino-cluster:domino-cluster-recipe" ...
2025-07-17 09:04:11 [INFO]: Executing workflow: restore in context restore
2025-07-17 09:04:11 [INFO]: Start execution sequence "group/domino-cluster-included-resources" ...
2025-07-17 09:04:11 [INFO]: The backup operation of resources from namespace ['domino-cluster'] completed successfully.
2025-07-17 09:04:11 [INFO]: Executing Velero restore backup-resources-1643a307-1180-4046-bc98-8b3017f24764 using backup backup-resources-56ad58ef-a36b-47fc-8e77-981d7c589f6b with include_namespaces ['domino-cluster'], exclude_namespaces None, label-selector None, include-resourcetypes ['clusterroles', 'clusterrolebindings', 'customresourcedefinitions.apiextensions.k8s.io', 'ingressclasses.networking.k8s.io', 'securitycontextconstraints.security.openshift.io'], exclude-resourcetypes ['PersistentVolumeClaim', 'imagestreamtags.image.openshift.io', 'virtualmachineinstancemigrations.kubevirt.io', 'virtualmachineclones.clone.kubevirt.io'], include-cluster-resources None, namespace-mapping None, and restore-overwrite-resource False, or-label-selector None and labelSelectorType None
2025-07-17 09:04:18 [INFO]: End execution sequence "group/domino-cluster-included-resources" completed successfully.
2025-07-17 09:04:18 [INFO]: Execution of workflow restore completed. Number of failed commands: 0, 0 are essential
2025-07-17 09:04:18 [INFO]: Execution of workflow "restore" of recipe "domino-cluster:domino-cluster-recipe" completed successfully.
2025-07-17 09:04:18 [INFO]: === Post recipe execution ===
2025-07-17 09:04:18 [INFO]: Restoring annotations {'openshift.io/description': '', 'openshift.io/display-name': '', 'openshift.io/requester': 'system:admin', 'openshift.io/sa.scc.mcs': 's0:c28,c12', 'openshift.io/sa.scc.supplemental-groups': '1000780000/10000', 'openshift.io/sa.scc.uid-range': '1000780000/10000'} and labels {} to namespace domino-cluster
2025-07-17 09:04:18 [INFO]: Restore job completed successfully.
```
