# Application-Specific Quiesce/Resume Knowledge Guide

This file provides known quiesce, resume, and post-restore patterns for common applications.
When a user names one of these applications, use these patterns as pre-filled defaults and ask the user to confirm.

---

## PostgreSQL (Crunchy Data PGO operator)

**Flush (always)**: `CHECKPOINT` before the snapshot. It is non-blocking and only shortens crash recovery. **On its own it is crash-consistent, not application-consistent** (the sample below stops here).  
**Quiesce (for an application-consistent online backup)**: PostgreSQL has no freeze command. Instead locks can block writes while the snapshots are being taken:
- A background `psql` session that opens a transaction, takes `LOCK TABLE ... IN EXCLUSIVE MODE` on every user table (`lock_timeout` 3 s) and holds it until a release file exists or a hard cap (60 s) passes. Writers queue, reads keep working. The `exec` op returns once the locks are held.
**Resume** is an op that creates the release file, set as the quiesce op's `inverseOp`. See `ibm-bob-backup-restore-recipe.yaml` (`bob-db-quiesce`) for the full command.
- Not usable: `ALTER SYSTEM SET default_transaction_read_only` (blocked when `allow_alter_system = off`), `ALTER DATABASE ... SET default_transaction_read_only` (only new connections), `pg_backup_start()` (does not block writes), `fsfreeze` (needs privileges the pod does not have).
- The lock must cover every database that holds data (one session per database), and the volume snapshots must be taken while it is held. A snapshot of a single volume that holds data and WAL is crash-recoverable by itself (PostgreSQL docs, "File System Level Backup"); the quiesce makes several volumes consistent with each other.
**Post-restore**: Wait for StatefulSet replicas to be ready.

```yaml
hooks:
  - name: postgres-exec
    type: exec
    namespace: <app-namespace>
    labelSelector: postgres-operator.crunchydata.com/role=master
    singlePodOnly: true
    timeout: 120
    onError: fail
    ops:
      - name: checkpoint
        command: "psql -c CHECKPOINT"
        container: database
        timeout: 60
  - name: postgres-check
    type: check
    namespace: <app-namespace>
    selectResource: statefulset
    labelSelector: postgres-operator.crunchydata.com/instance-set=instance1
    timeout: 180
    onError: fail
    chks:
      - name: replicasReady
        timeout: 180
        onError: fail
        condition: "{$.spec.replicas} == {$.status.readyReplicas}"
```

**Backup sequence**: resources → exec/checkpoint → volumes
**Restore sequence**: volumes → resources → check/replicasReady

**Example**: `../PostgreSQL/postgres-backup-restore.yaml`

---

## MySQL (image-based, no operator)

**Quiesce**: `FLUSH TABLES WITH READ LOCK` acquires a global read lock flushing all dirty data.  
**Resume**: Not required for snapshot — the lock is released when the connection closes (i.e. after the exec command completes). For longer-held locks, issue `UNLOCK TABLES`.  
**Post-restore**: Wait for Deployment replicas to be ready.

```yaml
hooks:
  - name: mysql-exec
    type: exec
    namespace: <app-namespace>
    labelSelector: app=mysql
    timeout: 60
    onError: fail
    ops:
      - name: flush-tables-with-read-lock
        command: >
          ["/bin/bash", "-c", "mysql --user=root --password=$MYSQL_ROOT_PASSWORD -e 'FLUSH TABLES WITH READ LOCK;'"]
        container: mysql
  - name: mysql-check
    type: check
    namespace: <app-namespace>
    selectResource: deployment
    nameSelector: mysql
    timeout: 600
    onError: fail
    chks:
      - name: replicasReady
        timeout: 600
        onError: fail
        condition: "{$.spec.replicas} == {$.status.readyReplicas}"
```

**Backup sequence**: resources → exec/flush-tables-with-read-lock → volumes
**Restore sequence**: volumes → resources → check/replicasReady

**Example**: `../MySQL/mysql-image-based-backup-restore.yaml`

---

## MariaDB (image-based)

Same pattern as MySQL — `FLUSH TABLES WITH READ LOCK`.

```yaml
ops:
  - name: flush-tables-with-read-lock
    command: >
      ["/bin/bash", "-c", "mariadb --user=root --password=$MARIADB_ROOT_PASSWORD -e 'FLUSH TABLES WITH READ LOCK;'"]
    container: mariadb
```

---

## MongoDB (community operator, replica set)

**Quiesce**: `db.fsyncLock()` on the primary flushes all pending writes and prevents new writes.  
**Resume**: `db.fsyncUnlock()` releases the lock.  
**Post-restore**: Shut down and restart each member so it resyncs from the restored data. Drop the `local` database (contains stale replication state). Scale the StatefulSet down then back up to force re-sync.

Key pattern: check `rs.isMaster().ismaster` first so the command only takes action on the primary pod.

```yaml
hooks:
  - name: mongodb-exec
    type: exec
    namespace: <app-namespace>
    labelSelector: app=mongodb-cluster
    selectResource: pod
    timeout: 300
    onError: fail
    ops:
      - name: fsyncLock
        command: >
          ["/bin/bash", "-c", "[[ $(mongosh -u `printenv MONGO_ROOT_USERNAME` -p `printenv MONGO_ROOT_PASSWORD` --eval \"rs.isMaster().ismaster\" --quiet | tail -1) == \"true\" ]] && mongosh -u `printenv MONGO_ROOT_USERNAME` -p `printenv MONGO_ROOT_PASSWORD` --eval \"db.fsyncLock()\" || echo \"Not Master\""]
        container: mongo
        inverseOp: fsyncUnlock
      - name: fsyncUnlock
        command: >
          ["/bin/bash", "-c", "[[ $(mongosh -u `printenv MONGO_ROOT_USERNAME` -p `printenv MONGO_ROOT_PASSWORD` --eval \"rs.isMaster().ismaster\" --quiet | tail -1) == \"true\" ]] && mongosh -u `printenv MONGO_ROOT_USERNAME` -p `printenv MONGO_ROOT_PASSWORD` --eval \"db.fsyncUnlock()\" || echo \"Not Master\""]
        container: mongo
      - name: shutdown-server
        command: >
          ["/bin/bash", "-c", "mongosh --eval \"var conn = new Mongo('mongodb://admin:`printenv MONGO_ROOT_PASSWORD`@localhost:27017/admin'); conn.getDB('admin').shutdownServer();\"; exit 0"]
        container: mongo
        onError: continue
      - name: drop-local-database
        command: >
          ["/bin/bash", "-c", "mongosh --eval \"var conn = new Mongo(); conn.getDB('local').dropDatabase();\""]
        container: mongo
        onError: continue
  - name: mongodb-scale
    type: scale
    namespace: <app-namespace>
    selectResource: statefulset
    labelSelector: app=mongodb-cluster
```

**Backup sequence**: resources → instances (CRs) → exec/fsyncLock → volumes → exec/fsyncUnlock
**Restore sequence**: volumes → resources → operator-check/replicasReady → instances → cluster-check/replicasReady → exec/shutdown-server → exec/drop-local-database → scale/down → scale/sync → scale/up → scale/sync

**Example**: `../MongoDB/mongodb-community-cluster-backup-restore.yaml`

---

## Redis (IBM Cloud Databases Redis operator)

**Quiesce**: Run `BGSAVE` to trigger a non-blocking background save to disk before snapshot.  
**Resume**: None required — `BGSAVE` is asynchronous, poll `rdb_bgsave_in_progress` to wait for completion.  
**Post-restore**: Wait for master and sentinel StatefulSets to be ready.

The Redis password is stored in a Kubernetes Secret and must be retrieved via the Kubernetes API before calling `redis-cli`.

**Backup sequence**: resources → instances (CRs) → exec/copy-password → exec/bgsave → volumes
**Restore sequence**: volumes → resources → operator-check/replicasReady → instances → master-check/replicasReady → sentinel-check/replicasReady

**Example**: `../Redis/redis-backup-restore.yaml`

---

## Elasticsearch (ECK operator)

**Quiesce**: Block writes on all indices and flush (`_flush`) to ensure all data is on disk.  
**Resume**: Unblock writes on all indices.  
**Post-restore**: Wait for operator and cluster to be ready. The operator re-reconciles the Elasticsearch CR on restore.

Use `inverseOp: unblock-write` on the `block-write` operation so writes are automatically unblocked if backup fails.

Operator-based apps require **ordered resource groups** during restore:
1. Operator subscription and OperatorGroup
2. Configuration secrets and ConfigMaps
3. Elasticsearch CR
4. StatefulSets (with `restoreOverwriteResources: true`)
5. Kibana CR

**Example**: `../Elasticsearch/operator-based/elasticsearch-operator-based-backup-restore.yaml`

---

## Db2 (Db2u operator)

**Quiesce**: Put the Db2 instance into `MAINTENANCE` mode using `db2 QUIESCE INSTANCE` or the Db2u operator's maintenance hook.  
**Resume**: Take the instance out of maintenance mode.  
**Post-restore**: Wait for the Db2u instance StatefulSet to be ready.

Db2u deployments have multiple components (engine, meta, head nodes) — ensure all StatefulSets are included in the volume group.

---

## Cassandra (operator-based)

**Quiesce**: Use `nodetool flush` to flush all memtables to SSTables on disk.  
**Resume**: None required after flush — Cassandra continues serving traffic.  
**Post-restore**: Wait for StatefulSet replicas to be ready.

For multi-DC deployments, run the flush command on pods in each datacenter.

---

## CockroachDB (operator-based)

**Quiesce**: CockroachDB is multi-version concurrency control (MVCC) — a strict quiesce is not typically required. Instead, run a full backup checkpoint or take a consistent snapshot.  
**Resume**: None required.  
**Post-restore**: Wait for StatefulSet replicas to be ready and run cluster health checks.

---

## Applications with no quiesce mechanism (scale-to-zero pattern)

When an application has no in-container quiesce command, use a `scale` hook to bring replicas to zero before capturing volumes, then scale back up after restore.

```yaml
hooks:
  - name: myapp-scale
    type: scale
    namespace: <app-namespace>
    selectResource: deployment
    labelSelector: app=myapp

workflows:
  - name: backup
    sequence:
      - group: myapp-resources
      - hook: myapp-scale/down
      - hook: myapp-scale/sync
      - group: myapp-volumes
      - hook: myapp-scale/up
      - hook: myapp-scale/sync
  - name: restore
    sequence:
      - group: myapp-volumes
      - group: myapp-resources
      - hook: myapp-scale/up
      - hook: myapp-scale/sync
```

---

## General best practices

- Always use `inverseOp` on quiesce operations — if backup fails mid-flight, IBM Fusion will automatically call the inverse to resume the application.
- Always add a `check` hook at the end of the restore workflow to verify the application is healthy before the restore is declared successful.
- Use `${GROUP.<name>.namespace}` in hook namespaces rather than hardcoding — this makes the Recipe portable across namespace names.
- Exclude `replicasets` and `pods` from resource groups — these are ephemeral and will be recreated automatically. Do not list `events`; Fusion and Velero exclude them by default.
- If restores onto a fresh or different cluster must work, check whether the application needs cluster-scoped resources (CRDs, webhook configurations) that Fusion does not capture by default. See "Cluster-scoped resources" in SKILL.md.
- For operator-based applications, always back up and restore the operator subscription and OperatorGroup in addition to the application's CRDs, so the operator is reinstalled on a bare-cluster restore.
- Use `restoreOverwriteResources: true` on groups containing resources that the operator will have already auto-created — otherwise the restore will skip them as duplicates.
- A hook's outer `timeout` must be greater than or equal to the largest inner `chks[].timeout` — the outer one is enforced first.                     
- A `check` hook on a custom resource (operator CR) needs a ClusterRole and ClusterRoleBinding granting the `transaction-manager` service account (`system:serviceaccount:ibm-backup-restore:transaction-manager`) `get`, `list` and `watch` on that CRD's API group. Verify with `oc auth can-i list <resource>.<group> --as=system:serviceaccount:ibm-backup-restore:transaction-manager`.
- Set `appType` to the exact name of the Application CR registered in Fusion (`oc get application.application.isf.ibm.com -n ibm-spectrum-fusion-ns`), not the technology name. For example, Crunchy PGO uses `postgres-operator`, not `postgresql`.
