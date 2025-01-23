MariaDB Operator Based Recipe
==============================

## Preparation for Backup & Restore
1. `./scripts/labels.sh`

2. Update the clusterrole transaction-manager-ibm-backup-restore as need to check the status of custom resource mariadb (i.e. Running).
 This step is required during restore on target cluster only.
```
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["mariadb.mmontes.io"],"resources":["mariadbs"]}]' | oc apply -f -
```

3. Create the recipe `oc apply -f mariadb-operator-based-backup-restore.yaml`

4. Update the policy assignment
```
oc -n ibm-spectrum-fusion-ns patch policyassignment mariadb-mariadb-policy-workload-vpc-cameo-98b7318c91b01bd72490e80cc2328915-0000.us-south.containers.appdomain.cloud --type merge -p '{"spec":{"recipe":{"name":"mariadb-operator-based-backup-restore-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'
```