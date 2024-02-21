Cassandra Operator Based Recipe
==============================

## Preparation for Backup & Restore
1. `./scripts/labels.sh`

2. Create the recipe `oc apply -f cassandra-operator-based-backup-restore.yaml`

3. Update the policy assignment
```
oc -n ibm-spectrum-fusion-ns patch policyassignment <policy-assignment-name> --type merge -p '{"spec":{"recipe":{"name":"cassandra-operator-based-backup-restore-recipe", "namespace":"ibm-spectrum-fusion-ns"}}}'
```