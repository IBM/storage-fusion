MySQL Operator Based Recipe
==============================

## Preparation for Backup & Restore
1. `./scripts/labels.sh`

2. Update the clusterrole transaction-manager-ibm-backup-restore as need to check the status of custom resource innodbcluster.mysql.oracle.com (i.e. ONLINE)
```
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["mysql.oracle.com"],"resources":["innodbclusters"]}]' | oc apply -f -
```

3. Create the recipe `oc apply -f mysql-operator-based-backup-restore.yaml`

4. Update the policy assignment
```
oc -n ibm-spectrum-fusion-ns patch policyassignment <policy-assignment-name> --type merge -p '{"spec":{"recipe":{"name":"mysql-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'
```