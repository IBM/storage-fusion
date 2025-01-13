Cassandra Operator Based Recipe
==============================

## Preparation for Backup & Restore
1. `./scripts/labels.sh`

2. Create the recipe `oc apply -f cassandra-operator-based-backup-restore.yaml`

3. Update the clusterrole transaction-manager-ibm-backup-restore as need to check the status of custom resource cassandradatacenters (i.e. Ready)
```
oc get clusterrole transaction-manager-ibm-backup-restore -o json | jq '.rules += [{"verbs":["get","list"],"apiGroups":["cassandra.datastax.com"],"resources":["cassandradatacenters"]}]' | oc apply -f -
```
4. Update the policy assignment
```
oc -n ibm-spectrum-fusion-ns patch policyassignment <policy-assignment-name> --type merge -p '{"spec":{"recipe":{"name":"cassandra-operator-based-backup-restore-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'
```