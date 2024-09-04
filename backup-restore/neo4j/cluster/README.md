# Neo4j cluster Backup & Restore using IBM Storage Fusion

## Prepare for backup and restore 

1. Export the neo4j namespace
    ```
        export NEO4J_NAMESPACE='<NEO4J_NAMESPACE>'
    ```
2. Dowload (**generate_recipe.sh and neo4j-cluster-backup-restore-template.yaml in same location**) and run the below script to generate recipe
    ```
        ./generate_recipe.sh $NEO4J_NAMESPACE
    ```
3. Apply the recipe
    ```
        oc apply -f neo4j-cluster-backup-restore.yaml
    ```    

2. Create backup policy from Fusion UI From Fusion UI --> Backup & restore --> Policies --> Add policy --> (fill details) --> Create policy
    ```
        $ oc get fbp  neo4j-cluster-policy -n ibm-spectrum-fusion-ns 

        NAME                    BACKUPSTORAGELOCATION   SCHEDULE      RETENTION   RETENTIONUNIT
        neo4j-cluster-policy    ashish-bucket           00 0 1 * *    30          days
    ```

3. Assign backup policy to Neo4j application from Fusion UI 
    
    Note: We have deployed Neo4j in <NAMESPACE> namespace. So, <NAMESPACE> is the application, which need to be protected.
    
    From Fusion UI --> Backup & restore --> Backed up applications --> Project apps --> Select a cluster --> Select application --> Next --> Select a backup policy --> Assign

    ```
        $ oc get fpa neo4j-cluster-neo4j-cluster-policy-apps.ocp4xdcd.cp.fyre.ibm.com -n ibm-spectrum-fusion-ns

        NAME                                                           CLUSTER  APPLICATION    BACKUPPOLICY          RECIPE   RECIPENAMESPACE          PHASE      LASTBACKUPTIMESTAMP   CAPACITY
       neo4j-cluster-neo4j-cluster-policy-apps.ocp4xdcd.cp.fyre.ibm.com          neo4j-cluster neo4j-cluster-policy                               Assigned   58m                   12547217
    ```

4. Update the policy assignment
    ```
        $ oc -n ibm-spectrum-fusion-ns patch policyassignment neo4j-cluster-neo4j-cluster-policy-apps.ocp4xdcd.cp.fyre.ibm.com --type merge -p '{"spec":{"recipe":{"name":"neo4j-cluster-backup-restore-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'

    ```

5. Initiate bakup from Fusion UI.

     From Fusion UI --> Backup & restore --> Backed up applications --> Click backed up application --> Actions --> Backup now

