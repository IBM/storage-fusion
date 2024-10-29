# MinIO image based Backup and Restore


There are two approaches for performing backup and restore operations for MinIO:
- **Using Scale Hook:** The scale hook method scales down the MinIO pod, guaranteeing that no write operations occur while the volume snapshot is being taken. After the snapshot, the pod is scaled back up. This is a reliable approach to ensure data consistency during backup.
- **Using Sync:** This approach employs the `sync -f /data/*` command through an exec hook to flush in-memory data to disk. During sync operation read and writes are allowed but user will experience some performance degradations. This method can be useful when the scale hook approach is not feasible.

If you choose the scale hook method, use the `minio-scale-backup-restore.yaml` file. For the sync approach, use the `minio-sync-backup-restore.yaml` file. 

**Note:**
Both the recipe files are included in this repository. For our Backup and Restore, we prefer the scale hook approach so implemented it using the recipe `minio-scale-backup-restore.yaml`. 

**Steps:**
1. Create the recipe 
   ```
   $ oc apply -f minio-scale-backup-restore.yaml
   ```

2. Create backup policy from Fusion UI
   From Fusion UI --> Backup & restore --> Policies --> Add policy --> (fill details) --> Create policy
   ```
   $ oc get fbp -A | grep minio

   NAMESPACE                NAME              BACKUPSTORAGELOCATION   SCHEDULE      RETENTION   RETENTIONUNIT
   ibm-spectrum-fusion-ns   minio-bp                ibm-s3                  00 0  * * *      30          days
   ```

3. Assign backup policy to minio application from Fusion UI
   From Fusion UI --> Backup & restore --> Backed up applications --> Protect apps --> Select a cluster --> Select application --> Next --> Select our backup policy --> Assign

   ```
   $ oc get fpa -A | grep minio   

   NAMESPACE                NAME                                                                    CLUSTER   APPLICATION           BACKUPPOLICY            RECIPE                                            RECIPENAMESPACE          PHASE      LASTBACKUPTIMESTAMP   CAPACITY
   ibm-spectrum-fusion-ns   minio-minio-bp-apps.ocp4xdcd.cp.fyre.ibm.com                                      minio                 minio-bp                minio-scale-backup-restore-recipe                       ibm-spectrum-fusion-ns   Assigned   21m                   7518202394                                    
   ```

4. Update the policy assignment
   ```
   $ oc -n ibm-spectrum-fusion-ns patch policyassignment minio-minio-bp-apps.ocp4xdcd.cp.fyre.ibm.com --type merge -p '{"spec":{"recipe":{"name":"minio-scale-backup-restore-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}
   ```

5. Initiate bakup from Fusion UI.
   From Fusion UI --> Backup & restore --> Backed up applications --> Click backed up application --> Actions --> Backup now

6. Uninstall the application and then restore it. 
   ```
   $ oc delete project minio
   ```
7. Restore the application for Fusion UI.
   From Fusion UI --> Backup & restore --> Backed up applications --> Click the application --> Restore (upper right corner) --> Choose cluster and other details --> Next --> Restore