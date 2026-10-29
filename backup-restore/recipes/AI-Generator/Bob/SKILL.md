---
name: create-fusion-recipe
description: Guide the user through creating an IBM Fusion Data Protection Recipe custom resource for their OpenShift application. Use when the user wants to create, generate, or author a Fusion Recipe YAML for backup/restore of a Kubernetes or OpenShift application.
---

## Goal

Generate a valid IBM Fusion `Recipe` custom resource (`apiVersion: spp-data-protection.isf.ibm.com/v1alpha1`) that provides application-consistent backup and restore for a specific application running on OpenShift.

Before generating any YAML:
- Read `recipe-crd-reference.md` for the authoritative field reference
- Read `question-guide.md` for known quiesce/resume patterns for common applications
- Read recipe files in `storage-fusion/backup-restore/recipes/` (e.g. `PostgreSQL/`, `MySQL/`, `MongoDB/`, `Redis/`, `WordPress/`, `Elasticsearch/`, etc.) to understand real-world Recipe patterns and use them as structural models

---

## Step 1 — Identify the application

Ask the user the following questions in a **single message** (do not ask them one at a time):

1. **Application name / type**: What is the name of your application? (e.g. `postgresql`, `my-custom-app`, `wordpress`)
2. **Namespace(s)**: Which namespace(s) does the application run in?
3. **Workload types**: Does the application use `Deployments`, `StatefulSets`, or both? Are there any operator-managed CRDs?
4. **Label selectors**: What label selector(s) identify your application's pods/workloads? (e.g. `app=myapp`)
5. **Persistent volumes**: Does the application use PersistentVolumeClaims? Are they selected by label, by name pattern, or both?
6. **Quiesce requirement**: Does the application need to be quiesced before backup — i.e. does it need to flush writes, drain connections, or enter read-only mode before a storage snapshot?
7. **Quiesce mechanism**: If yes — is there a shell command or script inside a container that can quiesce it? Or does it support scaling to zero replicas? Provide the command and container name if known.
8. **Resume mechanism**: What command, action, or scale-up resumes normal operation after backup completes?
9. **Post-restore steps**: Are there any commands that must run after a restore? (e.g. re-initialise replication, drop and re-sync a local database, restart a cluster member)
10. **Additional Kubernetes resources**: Should any cluster-scoped resources, operator subscriptions, or custom CR types be included in the backup? (e.g. `ClusterRoleBindings`, `subscriptions.operators.coreos.com`, operator CRs)
11. **Fusion namespace**: What namespace is the IBM Fusion operator running in? (default: `ibm-spectrum-fusion-ns`)

**Before presenting these questions**, check `question-guide.md` to see if the named application is a well-known application. If it is, pre-fill the quiesce/resume answers with the known defaults, present them to the user as suggested values, and ask the user to confirm or override.

---

## Step 2 — Design the recipe structure

Based on the answers, plan the following before writing any YAML:

### Groups
- Always create at minimum:
  - One `volume` group — captures PersistentVolumeClaims
  - One `resource` group — captures Kubernetes objects (Deployments, StatefulSets, ConfigMaps, Secrets, Services, etc.)
- Always exclude ephemeral or re-creatable resources from `resource` groups: `events`, `event.events.k8s.io`, `replicasets`, `pods`
- If operator-managed CRDs need ordered restore (operator must exist before its CRs are created), create **separate resource groups** for the operator vs. its CRs and restore them in order
- Use the `${GROUP.<group-name>.namespace}` dynamic reference in hook `namespace` fields so the Recipe works across namespaces without hardcoding

### Hooks
- **`exec`** hooks run a shell command inside a container — use for quiesce, flush, fsync, and post-restore init commands
- **`scale`** hooks scale a workload up or down — use when no in-container quiesce command exists (scale to zero before backup, scale back up after restore)
- **`check`** hooks poll a JSONPath condition — use to verify readiness after restore before declaring success
- Set `inverseOp` on quiesce `exec` ops pointing to the resume op — this auto-triggers resume if backup fails mid-sequence
- Use `singlePodOnly: true` on `exec` hooks targeting replica sets or clusters where the command should run on only one pod (e.g. primary/leader)

### Workflows
Always create exactly two workflows named `backup` and `restore`:

**Backup sequence** (canonical ordering):
1. Capture Kubernetes resource metadata (`resource` groups)
2. Quiesce hook (flush writes, lock tables, fsync, block writes, etc.)
3. Capture volumes (`volume` groups) — quiesce must hold for the duration of this step
4. Resume hook (if not handled via `inverseOp`)

**Restore sequence** (canonical ordering):
1. Restore volumes (`volume` groups)
2. Restore base Kubernetes resources (excluding operator CRs if separated)
3. Readiness `check` hook — wait for operator/controller to be ready
4. Restore operator-managed CRs (if in a separate group)
5. Readiness `check` hook — wait for application pods to be ready
6. Post-restore `exec` hooks (re-init replication, drop stale local state, etc.)
7. Scale hooks to bring replicas back up (if workload was scaled down)

---

## Step 3 — Generate the YAML

Produce a complete, valid Recipe YAML. Use this structure as the starting template and adapt it to the application's needs:

```yaml
apiVersion: spp-data-protection.isf.ibm.com/v1alpha1
kind: Recipe
metadata:
  name: <appname>-backup-restore-recipe
  namespace: <fusion-namespace>
spec:
  appType: <appType>
  groups:
    - name: <appname>-volumes
      type: volume
      includedNamespaces:
        - <app-namespace>
    - name: <appname>-resources
      type: resource
      includedNamespaces:
        - <app-namespace>
      excludedResourceTypes:
        - events
        - event.events.k8s.io
        - replicasets
        - pods
  hooks:
    - name: <appname>-exec
      type: exec
      namespace: <app-namespace>
      labelSelector: <selector>
      singlePodOnly: true
      timeout: 60
      onError: fail
      ops:
        - name: quiesce
          command: >
            ["/bin/bash", "-c", "<quiesce command>"]
          container: <container-name>
          inverseOp: resume
        - name: resume
          command: >
            ["/bin/bash", "-c", "<resume command>"]
          container: <container-name>
    - name: <appname>-check
      type: check
      namespace: <app-namespace>
      selectResource: <deployment|statefulset>
      labelSelector: <selector>
      timeout: 120
      onError: fail
      chks:
        - name: replicasReady
          timeout: 180
          onError: fail
          condition: "{$.spec.replicas} == {$.status.readyReplicas}"
  workflows:
    - name: backup
      sequence:
        - group: <appname>-resources
        - hook: <appname>-exec/quiesce
        - group: <appname>-volumes
    - name: restore
      sequence:
        - group: <appname>-volumes
        - group: <appname>-resources
        - hook: <appname>-check/replicasReady
```

Remove any sections not required by the application. Add additional groups or hooks as the application's complexity requires.

---

## Step 4 — Explain and confirm

After generating the YAML:

1. Describe in plain language what each hook and group does and why it is needed
2. Call out any assumptions made where the user did not provide specifics
3. Ask the user to confirm the YAML is correct before finalising
4. Remind the user to apply the recipe to the Fusion namespace:
   ```
   oc apply -f <recipe-filename>.yaml -n <fusion-namespace>
   ```
5. Remind the user that the Recipe CR `name` must match the name of the Application CR in IBM Fusion for the recipe to be automatically associated with the application

---

## Reference files

| File | Purpose |
|---|---|
| `recipe-crd-reference.md` | Authoritative field names, types, enums, and constraints from the CRD |
| `question-guide.md` | Known quiesce/resume patterns for common applications |
| `../../PostgreSQL/postgres-backup-restore.yaml` | PostgreSQL: CHECKPOINT exec hook, label-based primary selection, replica readiness check |
| `../../MySQL/mysql-image-based-backup-restore.yaml` | MySQL: FLUSH TABLES WITH READ LOCK exec hook, deployment readiness check |
| `../../MongoDB/mongodb-community-cluster-backup-restore.yaml` | MongoDB: fsyncLock/fsyncUnlock, scale hooks, post-restore drop-local-database |
| `../../Redis/redis-backup-restore.yaml` | Redis: BGSAVE exec hook, multi-component readiness checks |
| `../../WordPress/wordpress-backup-restore.yaml` | Multi-component app: MySQL exec hook, dynamic `${GROUP...namespace}` reference |
| `../../Elasticsearch/operator-based/elasticsearch-operator-based-backup-restore.yaml` | Operator-based app: multiple ordered resource groups, write-block hooks with inverseOp |
| `../../FusionReference/fusion-reference-backup-restore.yaml` | Canonical dynamic namespace reference pattern |
