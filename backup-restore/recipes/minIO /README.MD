# MinIO image based Fusion backup & restore 

MinIO is an open-source, high-performance object storage system that is purpose-built for cloud-native environments. It's designed to be high performance, scalable, and secure, and can run on any infrastructure or cloud. MinIO operates on an object storage model, treating data as objects and providing an API-compatible alternative to Amazon S3.

## Install and Setup MinIO 

1. Clone [this](https://github.ibm.com/ProjectAbell/workload-squad.git) repo.

2. Create project 
   ```
   $ oc new-project minio
   ```
3. Change directory to workload-squad/minIO/
   ```
   $ cd workload-squad/minIO/
   ```
4. Create the deployment 
   ```
   $ oc apply -f minio-deployment.yaml 
   ```
5. Get the status of pods
   ```
   $ oc get all,pvc 
   Warning: apps.openshift.io/v1 DeploymentConfig is deprecated in v4.14+, unavailable in v4.10000+
   NAME                         READY   STATUS    RESTARTS   AGE
   pod/minio-579bddbb9b-slzzk   1/1     Running   0          68s

   NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
   service/minio-service   ClusterIP   172.30.111.46   <none>        9000/TCP,9001/TCP   67s

   NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
   deployment.apps/minio   1/1     1            1           69s

   NAME                               DESIRED   CURRENT   READY   AGE
   replicaset.apps/minio-579bddbb9b   1         1         1       69s

   NAME                                           HOST/PORT                                                 PATH   SERVICES        PORT      TERMINATION   WILDCARD
   route.route.openshift.io/minio-api-route       minio-api-route-minio.apps.ocp4xdcd.cp.fyre.ibm.com              minio-service   api       edge          None
   route.route.openshift.io/minio-console-route   minio-console-route-minio.apps.ocp4xdcd.cp.fyre.ibm.com          minio-service   console   edge          None

   NAME                              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS                  AGE
   persistentvolumeclaim/minio-pvc   Bound    pvc-3f039703-d76a-4a39-ba25-360a4e4b063b   10Gi       RWO            ocs-storagecluster-ceph-rbd   77s

   ```

## Persist data in MinIO


### Creating a User via MinIO Console

1. **Login to the MinIO Console**  
   Open your browser and navigate to the MinIO console URL using the **minio-console-route**. Use your admin credentials to login.

2. **Navigate to the Users Section**  
   Once logged in, select the **"Identity"** option from the left-hand side menu, and then click **"Users"**.

3. **Create a New User**  
   - Click the **"Create User"** button.
   - In the pop-up window, enter the user details. For ex.:
     - Username: `user-1`
     - Password: `password`
   - Click **"Save"** to create the new user.

4. **Assign Policies**  
   After creating the user, assign the necessary policies (like read/write access) for the user to interact with the buckets.
   

### Uploading Data 

1. Login to the MinIO Console using your credentials.
   
2. Navigate to the Buckets Section: Once logged in, click on the **"Buckets"** tab from the left-hand navigation pane.

3. Create a New Bucket: 
   - Click the "Create Bucket" button at the top right of the Buckets page.
   - In the pop-up window, enter a name for your new bucket. Bucket names must be unique within your MinIO instance.
   - (Optional) Configure additional settings like Versioning, Quota, or Object Locking.
   - Click "Create Bucket" to finish.
![alt text](image.png)

4. Verify Bucket Creation: After creating, your new bucket will appear in the list of available buckets.

5. Select the bucket where you want to upload your data.

6. Upload Data to the Bucket:
   - Inside the bucket, click the "Upload" button at the top right.
   - In the pop-up window, Browse files/folders for upload.
   - Click "Upload" to begin the transfer.

5. Verify Upload: After the upload completes, verify the uploaded files by checking the list of objects inside the bucket.


## Backup & Restore for MinIO

There are two approaches for performing backup and restore operations for MinIO:
- **Using Scale Hook:** The scale hook method scales down the MinIO pod, guaranteeing that no write operations occur while the volume snapshot is being taken. After the snapshot, the pod is scaled back up. This is a reliable approach to ensure data consistency during backup.
- **Using Sync:** This approach employs the `sync -f /data/*` command through an exec hook to flush in-memory data to disk. During sync operation read and writes are allowed but user will experience some performance degradations. This method can be useful when the scale hook approach is not feasible.

If you choose the scale hook method, use the `minio-scale-backup-restore.yaml` file. For the sync approach, use the `minio-sync-backup-restore.yaml` file.

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