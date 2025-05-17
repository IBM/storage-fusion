# ElasticSearch Image based Backup and Restore 

## Preparation for Backup & Restore

1. Create the recipe 
```
oc apply -f elasticsearch-image-based-backup-restore.yaml
```

2. Create backup policy from Fusion UI
   From Fusion UI --> Backup & restore --> Policies --> Add policy --> (fill details) --> Create policy
```
oc get fbp -A | grep es

NAMESPACE                NAME              BACKUPSTORAGELOCATION   SCHEDULE      RETENTION   RETENTIONUNIT
ibm-spectrum-fusion-ns   es-policy         ibm-s3                  00 0 31 * *    30          days
```

3. Assign backup policy to elasticsearch application from Fusion UI
   Note: We have deployed elasticsearch in "elasticsearch-demo" namespace. So, "elasticsearch" is the application, which need to be protected.
   From Fusion UI --> Backup & restore --> Backed up applications --> Project apps --> Select a cluster --> Select application --> Next --> Select a backup policy --> Assign

```
oc get fpa -A | grep elastic   
   
NAMESPACE                 NAME                  CLUSTER  APPLICATION          BACKUPPOLICY  RECIPE                RECIPENAMESPACE          PHASE      
ibm-spectrum-fusion-ns   <POLICY_ASSIGNMENT_NAME>        elasticsearch-demo   es-policy     elasticsearch-recipe  ibm-spectrum-fusion-ns   Assigned  
```

4. Update the policy assignment
```
oc -n ibm-spectrum-fusion-ns patch policyassignment <POLICY_ASSIGNMENT_NAME> --type merge -p '{"spec":{"recipe":{"name":"elasticsearch-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'
```

5. Initiate bakup from Fusion UI.
   From Fusion UI --> Backup & restore --> Backed up applications --> Click backed up application --> Actions --> Backup now

6. Uninstall application 
```
oc delete project elasticsearch-demo
```
7. Restore the application for Fusion UI.
   From Fusion UI --> Backup & restore --> Backed up applications --> Click backed up application --> Backups --> select snapshot triple dot drop down --> Restore --> Choose cluster and other details --> Next --> Restore
