# Neo4j standalone Backup & Restore using IBM Storage Fusion

## Prepare for backup and restore 
1. create the custom recipe 
    ```
        oc apply -f neo4j-backup-restore.yaml
    ```
2. Create backup policy from Fusion UI From Fusion UI --> Backup & restore --> Policies --> Add policy --> (fill details) --> Create policy
    ```
        $ oc get fbp  neo4j-policy -n ibm-spectrum-fusion-ns 

        NAME           BACKUPSTORAGELOCATION   SCHEDULE      RETENTION   RETENTIONUNIT
        neo4j-policy   ashish-bucket           00 0 1 * *    30          days
    ```

3. Assign backup policy to Neo4j application from Fusion UI 
    
    Note: We have deployed Neo4j in <NAMESPACE> namespace. So, <NAMESPACE> is the application, which need to be protected.
    
    From Fusion UI --> Backup & restore --> Backed up applications --> Project apps --> Select a cluster --> Select application --> Next --> Select a backup policy --> Assign

    ```
        $ oc get fpa neo4j-project-neo4j-policy-apps.ocp4xdcd.cp.fyre.ibm.com -n ibm-spectrum-fusion-ns

        NAME                                                       CLUSTER   APPLICATION     BACKUPPOLICY   RECIPE                        RECIPENAMESPACE          PHASE      LASTBACKUPTIMESTAMP   CAPACITY
        neo4j-project-neo4j-policy-apps.ocp4xdcd.cp.fyre.ibm.com             neo4j-project   neo4j-policy   neo4j-backup-restore-recipe   ibm-spectrum-fusion-ns   Assigned   58m                   12547217
    ```

4. Update the policy assignment
    ```
        $ oc -n ibm-spectrum-fusion-ns patch policyassignment neo4j-project-neo4j-policy-apps.ocp4xdcd.cp.fyre.ibm.com --type merge -p '{"spec":{"recipe":{"name":"neo4j-backup-restore-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'

    ```

5. Initiate bakup from Fusion UI.

     From Fusion UI --> Backup & restore --> Backed up applications --> Click backed up application --> Actions --> Backup now


### Note:
    1. To change the mode to READ mode use below command after logging into the CLI
        ```
            :access-mode READ
        ```
        if using recipe we can do this then restart of pod is not required.

        something like this 
        ```
            cypher-shell -u neo4j -p password | echo ":access-mode READ;"  
        ```

        right now no utility is available inside this pod by which we can do this.


    2. We are using below method to enable and disable with write operation
        ```
            cypher-shell -u neo4j -p securepassword "CALL dbms.setConfigValue('server.databases.default_to_read_only', 'true');"
            cypher-shell -u neo4j -p securepassword "CALL dbms.setConfigValue('server.databases.default_to_read_only', 'false');"
        ```

    3. If you are facing below error while deployment 
        ```
            Failed to read config: Unrecognized setting. No declared setting with name: SERVICE.PORT.7687.TCP.PROTO. 
            Cleanup the config or disable 'server.config.strict_validation.enabled' to continue.
        ```
        Then set `server.config.strict_validation.enabled=false` in neo4j.conf which is referred by configmap
