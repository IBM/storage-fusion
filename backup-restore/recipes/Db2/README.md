# How to protect Db2 application using Fusion Recipe

Example below covers for Db2uinstance backup and restore
## Backup
1. Deploy Db2 application
2. Add Backup location (object store)
    Fusion UI  ---> Backup & Restore  ---> Add Location  ---> Choose Location type --> Add Login credentials --> Click Add
    Once location successfully added, it will be shown in Fusion UI as connected (green check mark)
3. Create backup policy from Fusion UI
    Fusion UI  ---> Backup & Restore  ---> Policies  ---> Add policy  ---> Fill details  ---> Click Create policy
4. Add backup policy to Db2 application (Policy assignment)
    Fusion UI  ---> Backup & Restore  ---> Backed up applications  ---> Protect Apps  ---> Choose cluster  ---> Select Application  ---> Next  ---> Select backup policy (Uncheck "Back up now", if don't want immediate backup)  ---> Assign
5. Apply Db2uinstance Fusion Recipe either from OpenShift Console OR cli as -
```
$ oc apply -f db2u-instance-backup-restore-recipe.yaml 
recipe.spp-data-protection.isf.ibm.com/db2u-instance-backup-restore-recipe created
```
6.  Update recipe details to Fusion Policy Assignment custom resource
```
## Get Db2 Policy Assignment name
$ oc get fpa -A | grep db2
NAMESPACE                NAME                                                                 CLUSTER   APPLICATION   BACKUPPOLICY                RECIPE                                     RECIPENAMESPACE          PHASE      LASTBACKUPTIMESTAMP   CAPACITY
ibm-spectrum-fusion-ns   db2-db2-backup-policy-apps.san-ocp.cp.fyre.ibm.com                             db2           db2-backup-policy                     Assigned                  

## Add recipe name and namespace to Policy Assignment
$ oc patch fpa <Policy Assignment Name> -n ibm-spectrum-fusion-ns --type='json' -p='[{"op": "add", "path": "/spec/recipe", "value": [{"name": "<Recipe Name>", "namespace": "<Recipe Namespace>"}]}]'

## In Console it can be seen as
  spec:
    application: db2
    backupPolicy: db2-backup-policy
    recipe:
      name: db2u-instance-backup-restore-recipe
      namespace: ibm-spectrum-fusion-ns

## Check updated Policy Assignment
$ oc get fpa -A
NAMESPACE                NAME                                                                 CLUSTER   APPLICATION   BACKUPPOLICY                RECIPE                                     RECIPENAMESPACE          PHASE      LASTBACKUPTIMESTAMP   CAPACITY
ibm-spectrum-fusion-ns   db2-db2-backup-policy-apps.san-ocp.cp.fyre.ibm.com                             db2           db2-backup-policy           db2u-instance-backup-restore-recipe        ibm-spectrum-fusion-ns   Assigned                  
```
7. Add Db2uinstance labels by running below script
```
$ ./backup-pre-req.sh
# Labels Db2uinstance or Db2ucluster custom resources if present on the cluster
Usage: ./backup-pre-req.sh <DB2U_NAMESPACE>

$ ./backup-pre-req.sh  db2
db2uinstance.db2u.databases.ibm.com/demo-instance1 labeled
db2uinstance.db2u.databases.ibm.com/demo-instance2 labeled
```
8. Start Backup
    Fusion UI  ---> Backup & Restore  ---> Backed up applications  ---> Select Application  ---> select Backups tab  ---> Actions  ---> Back up now 

**Note:** All above CLI operations can be performed using OpenShift Console as well.

## Restore
1. On Spoke cluster, run below to add necessary clusterroles. 
_Note_: If you want to recover on the same Hub cluster then it will act as both (Hub and Spoke) and this need to be executed on Hub itself.
```
$ ./restore-pre-req.sh
clusterrole.rbac.authorization.k8s.io/transaction-manager-ibm-backup-restore configured
```
2. Start Restore
     Fusion UI ---> Backup & Restore ---> Backed up applications ---> Select Application ---> select Backups tab ---> Select Backup Snapshot  ---> Click Restore
