Backup
----

### Steps for Maximo Optimizer namespace backup
For detailed information about IBM Fusion resources such as backup policy, recipes and backup storage location, please refer the [Backing up and restoring with IBM Fusion](https://www.ibm.com/docs/en/masv-and-l/continuous-delivery?topic=suite-backing-up-restoring-storage-fusion#taskt_backing_up_and_restoring_with_ibm_fusion__steps__1) section in MAS documentation <br>

1. cd to `maximo/optimizer`
2. Export Optimizer required variables, this can be achieving by sourcing the `maximo_env.sh`:
    ```
    MAS_INSTANCE_ID (REQUIRED)
    MAS_WORKSPACE_ID (REQUIRED)
    ```

    e.g
    `export MAS_INSTANCE_ID=inst1`
    `export MAS_WORKSPACE_ID=dev`


3. Run the prerequisite script, for more information, run with the `-h` option

    `./scripts/backup-pre-req.sh`

4. Apply the local recipe (frcpe) generated by the backup-pre-req script

    `oc apply -f maximo-optimizer-backup-restore-local.yaml`

**Note:** Following steps needs to be made on Hub cluster

5. From Fusion Console, create backup policy (fbp) specifying the frequency for backups
6. From Fusion Console, associate the backup policy to the Optimizer application. 
7. Retrieve the Policy Assignment Name:

    `oc get fpa -n ibm-spectrum-fusion-ns -o custom-columns=NAME:.metadata.name --no-headers`
8. Update policy assignments (fpa) with recipe name and namespace

    `oc -n ibm-spectrum-fusion-ns patch fpa <policy-assignment-name> --type merge -p '{"spec":{"recipe":{"name":"maximo-optimizer-backup-restore-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'`
    ```
    recipe:
        name: maximo-optimizer-backup-restore-recipe
        namespace: ibm-spectrum-fusion-ns
    ```

Restore
----
### Prerequisite: 
**Required:** <br>
1. Restore Maximo Application Suite with either [Suite](../suite/README.md) or [Core](../core/README.md) recipes and its optional prerequisites <br>

**Optional:** <br>
2. [Grafana](https://ibm-mas.github.io/ansible-devops/roles/grafana/): You must install same version (v4 or v5) as in source cluster if you were previously using Grafana <br>
3. Restore [DB2](../db2u/README.md) namespace if configured in source cluster <br>

### Steps for Maximo Optimizer namespace restore
1. Before restoring application run the prerequisite script:

    `./scripts/restore-pre-req.sh`
2. Start Optimizer namespace restore to same or alternate cluster. For detailed procedure on how to restore an application with IBM Fusion, please refer to detailed steps in [Restoring Maximo Application Suite with IBM Fusion](https://www.ibm.com/docs/en/masv-and-l/continuous-delivery?topic=suite-backing-up-restoring-storage-fusion#restore_mas_w_fusion__title__1)
