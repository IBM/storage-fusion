## Pre-requisite
1. Install jq
    #### For Mac
    ```
        brew install jq
    ```
    ### For Linux
    ```
        sudo apt update
        sudo apt install jq
    ```

# Prepare for Backup and restore

## BACKUP Steps
### Run the below steps where the elasticsearch application present (either on HUB or on SPOKE)
1. Run the below pre backup script to prepare for backup 
  ```
    ./scripts/pre-backup.sh 
  ```

2. Apply the recipe 
  ```
    oc apply -f elasticsearch-operator-based-recipe.yaml
  ```

### Run these steps on HUB cluster
1. Create backup policy from Fusion UI
   From Fusion UI --> Backup & restore --> Policies --> Add policy --> (fill details) --> Create policy
##### For example:    
  ```
  $ oc get fbp -A
  NAMESPACE                NAME                 BACKUPSTORAGELOCATION   SCHEDULE      RETENTION   RETENTIONUNIT
  ibm-spectrum-fusion-ns   elastic-system       ibm-s3                  00 0 1 * *    30          days
  ```

2. Assign backup policy to elasticsearch application from Fusion UI
   Note: We have deployed elasticsearch cluster in "elastic-system" namespace. So, "elastic-system" is the application, which needs to be protected.
   From Fusion UI --> Backup & restore --> Backed up applications --> Project apps --> Select a cluster --> Select application --> Next --> Select a backup policy --> Assign
##### For example:  
  ```
  $ oc get fpa -A | grep elastic
  NAMESPACE                NAME                    CLUSTER  APPLICATION   BACKUPPOLICY      RECIPE                      RECIPENAMESPACE         PHASE     LASTBACKUPTIMESTAMP   CAPACITY
  ibm-spectrum-fusion-ns   <policy-assignment-name>         elastic-system  elastic-system   es-operator-based-recipe   ibm-spectrum-fusion-ns   Assigned  
  ```
  
  ```
    $ oc -n ibm-spectrum-fusion-ns patch policyassignment elastic-system-elastic-policy-apps.ocp4xdcd.cp.fyre.ibm.com --type merge -p '{"spec":{"recipe":{"name":"elasticsearch-operator-based-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'
  ```

3. Now take the backup from fusion UI.


## Restore Steps

### Run these steps on Restore cluster
1. Run the below pre restore srcipt to prepare for restore , run on the target cluster(where the restore will happen).
  ```
    ./scripts/pre-restore.sh 
  ```
