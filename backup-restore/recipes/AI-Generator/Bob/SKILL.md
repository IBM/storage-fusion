---
name: create-fusion-recipe
description: Guide the user through creating an IBM Fusion Data Protection Recipe custom resource for their OpenShift application. Use when the user wants to create, generate, or author a Fusion Recipe YAML for backup/restore of a Kubernetes or OpenShift application.
---

## Goal

Generate a valid IBM Fusion `Recipe` custom resource (`apiVersion: spp-data-protection.isf.ibm.com/v1alpha1`) that provides application-consistent backup and restore for a specific application running on OpenShift.

### What a Recipe is for (design goals, check every recipe against these)

1. **Application-consistent, not crash-consistent.** Without a Recipe, Fusion Backup & Restore takes a crash-consistent backup of the namespace and its PVCs. The whole point of a Recipe is to do better: the recipe must put the application into a consistent state for the snapshot, using the application's own mechanism (a quiesce/freeze/lock/write-block command, a backup-mode call, scaling the writers to zero), and then release it. A recipe that only flushes (for example `CHECKPOINT`, `FLUSH TABLES`, `fsync`) while the application keeps accepting writes is still crash-consistent. Flush hooks are a supplement, not a substitute.
2. **Online backup, with the shortest possible downtime.** The application keeps running while the backup runs, and the Recipe must interrupt it as little as possible. The quiesce window should cover only the volume snapshot step, which is seconds, not the data upload that follows (Fusion uploads snapshot data to the backup location after the workflow has finished, see "Post recipe execution" in the backup log). So:
   - Prefer an in-application quiesce (block or pause writes, keep the process and connections up) over scaling the workload to zero. Scaling to zero stops reads as well, restarts pods and can be undone by an operator.
   - Put the quiesce hook immediately before the `volume` groups and the resume hook immediately after them. Do all slow work (resource groups, label jobs, readiness checks) outside that window.
   - Set a hard upper bound on the window, so a failed or hung backup cannot leave the application blocked (a server-side timeout in the quiesce command itself, plus `inverseOp`).
   - Group all the volume groups of one application between a single quiesce/resume pair, so the volumes are consistent with each other.
   - Take the PVC snapshots of independent, large data (for example model weights or media) outside the window when they do not need to be consistent with the databases.
3. **Restore must put the application back into a working state** with as few manual steps as possible (see the sections below).

Before generating any YAML:
- Read `recipe-crd-reference.md` for the authoritative field reference
- Read `question-guide.md` for known quiesce/resume patterns for common applications
- Read recipe files in `storage-fusion/backup-restore/recipes/` (e.g. `PostgreSQL/`, `MySQL/`, `MongoDB/`, `Redis/`, `WordPress/`, `Elasticsearch/`, etc.) to understand real-world Recipe patterns and use them as structural models

---

## Online documentation access (MCP fetch server)

Reference material for this task may reside on web pages, such as the application's own backup/restore documentation.  Bob cannot read web pages by default with its built-in tools, so if online documentation is provided, this skill expects an MCP **fetch** server to be configured.

**Check first:** look for a tool named like `mcp__fetch__fetch` in your available tools. If it is present, use it to read any URL the user gives you or that you need (application backup docs, Fusion Recipe docs, GitHub sample recipes). Do not ask the user to paste page text when the tool is available. For GitHub files, fetch the raw file (`https://raw.githubusercontent.com/IBM/storage-fusion/master/backup-restore/recipes/<App>/<file>.yaml`) rather than the HTML page.

**If it is not present:** tell the user that no web-reading tool is available, and offer to set one up with the `configure-mcp` skill. The server entry for `~/.bob/settings/mcp.json` (global) or `.bob/mcp.json` (project) is:

```json
{
  "mcpServers": {
    "fetch": {
      "command": "uvx",
      "args": ["mcp-server-fetch"]
    }
  }
}
```

It requires `uv` (`brew install uv` on macOS; see https://docs.astral.sh/uv/getting-started/installation/ for other platforms). A new Bob task may be needed before the tool appears.

**Limits to be aware of:**
- The fetch server refuses private, loopback, and link-local addresses by default, so it cannot read anything inside the user's cluster. Use `oc` commands run by the user for cluster information.
- It respects `robots.txt`; if a page is blocked, ask the user to paste the content.
- Pages behind authentication are not reachable; ask the user to paste the content.

---

## Step 1 — Identify the application

Ask the user the following questions in a **single message** (do not ask them one at a time):

1. **Application name / type**: What is the name of your application? (e.g. `postgresql`, `my-custom-app`, `wordpress`)
2. **Namespace(s)**: Which namespace(s) does the application run in? If more than one (for example an application namespace plus a separate operators namespace), see "Multi-namespace applications" in Step 2 — the Fusion Application CR must list every namespace.
3. **Workload types**: Does the application use `Deployments`, `StatefulSets`, or both? Are there any operator-managed CRDs?
4. **Label selectors**: What label selector(s) identify your application's pods/workloads? (e.g. `app=myapp`)
5. **Persistent volumes**: Does the application use PersistentVolumeClaims? Are they selected by label, by name pattern, or both?
6. **Quiesce requirement**: Does the application need to be quiesced before backup — i.e. does it need to flush writes, drain connections, or enter read-only mode before a storage snapshot?
7. **Quiesce mechanism**: If yes — is there a shell command or script inside a container that can quiesce it? Or does it support scaling to zero replicas? Provide the command and container name if known.
8. **Resume mechanism**: What command, action, or scale-up resumes normal operation after backup completes?
9. **Post-restore steps**: Are there any commands that must run after a restore? (e.g. re-initialise replication, drop and re-sync a local database, restart a cluster member)
10. **Additional Kubernetes resources**: Should any cluster-scoped resources, operator subscriptions, or custom CR types be included in the backup? (e.g. `ClusterRoleBindings`, `subscriptions.operators.coreos.com`, operator CRs)
11. **Fusion namespace**: What namespace is the IBM Fusion operator running in? (default: `ibm-spectrum-fusion-ns`; some installs use `ibm-fusion` — confirm with `oc get fapp -A` or `oc get namespaces | grep -i fusion`)

**Before presenting these questions**, check `question-guide.md` to see if the named application is a well-known application. If it is, pre-fill the quiesce/resume answers with the known defaults, present them to the user as suggested values, and ask the user to confirm or override.

---

## Step 2 — Design the recipe structure

Based on the answers, plan the following before writing any YAML:

### Groups
- Always create at minimum:
  - One `volume` group — captures PersistentVolumeClaims
  - One `resource` group — captures Kubernetes objects (Deployments, StatefulSets, ConfigMaps, Secrets, Services, etc.)
- Always exclude ephemeral or re-creatable resources from `resource` groups: `replicasets`, `pods`. Do **not** add `events` / `event.events.k8s.io` — Fusion and Velero already exclude events by default, so listing them is redundant.
- If operator-managed CRDs need ordered restore (operator must exist before its CRs are created), create **separate resource groups** for the operator vs. its CRs and restore them in order
- Use the `${GROUP.<group-name>.namespace}` dynamic reference in hook `namespace` fields so the Recipe works across namespaces without hardcoding. Variables (`${GROUP...}` and Application CR `variables`) are only valid in hook `namespace` fields and inside exec hook commands — not in group fields.
- **Decide whether the application needs cluster-scoped resources** — see "Cluster-scoped resources" below. This is easy to miss and only shows up when restoring onto a fresh cluster.

### Cluster-scoped resources

By default (`includeClusterResources` unset or `true`) Fusion captures only the cluster-scoped objects *associated with* the included namespaced resources: **Namespaces, ClusterRoles, ClusterRoleBindings, and (OpenShift 4.22+) SecurityContextConstraints of the application's pods**. It does **not** capture **CustomResourceDefinitions**, admission webhook configurations, PriorityClasses, StorageClasses, and similar.

If the application's custom resources are backed up but their CRDs are not, a restore onto a fresh cluster fails with, for example:

```
error restoring imagecatalogs.pg.ibm.com/ns/name: the server could not find the requested resource
```

That error is the signature of a missing CRD (or webhook/other cluster-scoped dependency) on the restore target. An in-place restore on the original cluster hides the problem because the CRDs are still there, so **always ask whether restores onto a fresh or different cluster must work**, and if so include the cluster-scoped resources.

Discovery (run on the source cluster and review with the user):
```bash
# CRDs for the application's custom resources, with their labels
oc get crd -o custom-columns='NAME:.metadata.name,LABELS:.metadata.labels' | grep -iE '<app-or-operator-api-group>'
# Which CRDs have instances in the application namespaces
for c in $(oc get crd -o name | cut -d/ -f2); do oc get $c -n <ns> -o name 2>/dev/null | head -1 | sed "s|^|$c: |"; done
# Cluster-scoped RBAC and webhooks belonging to the operators
oc get clusterrole,clusterrolebinding -o name | grep -i <operator>
oc get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep -i <operator>
# Scope of each CRD (Namespaced vs Cluster)
oc get crd <name> -o jsonpath='{.spec.scope}'
```

Pattern: a dedicated `resource` group, restored **before** the operator and application groups:
```yaml
- name: <app>-cluster-resources
  type: resource
  includedNamespaces:            # must be in the Application CR's includedNamespaces
    - <app-namespace>
  includeClusterResources: true
  includedResourceTypes:
    - customresourcedefinitions.apiextensions.k8s.io
    - clusterroles.rbac.authorization.k8s.io
    - clusterrolebindings.rbac.authorization.k8s.io
  orLabelSelector:               # OR'd; use labelSelector for AND
    - component-id=<operator-label-value>
```

Rules:
1. **Select by label, not by listing names.** Operators usually label their CRDs (e.g. `component-id=...`, `app.kubernetes.io/instance=...`). Use `orLabelSelector` (OR) to combine several operators' labels. `labelSelector` is AND.
2. **CRDs with no labels cannot be selected by a recipe group**, and a recipe cannot label them itself:
   - A `label` hook against `customresourcedefinitions` fails backup validation (`BMYBR0022`). Fusion requires `namespace` on label hooks, despite the CRD text "leave unset for cluster-scoped objects". The `transaction-manager` ServiceAccount in `ibm-backup-restore` also has no `list`/`patch` on CRDs (403).
   - `nameSelector` on a hook is a literal name, not a regex. On a resource group it is volume-only.
   - A recipe has no conditional logic, so "use the label if present, otherwise try to add it" cannot be expressed. `onError: continue` covers failing ops, not validation failures.
   - **Do not rely on Velero capturing unlabelled CRDs.** Velero's backup of a namespace-only group does store a CRD that has an instance in that namespace (`Backing up item ... resource: customresourcedefinitions`), but the matching namespace-only **restore** logs `Skipping resource customresourcedefinitions because it's cluster-scoped and only specific namespaces are included` and never recreates it. On a fresh cluster the custom resource then fails with `error restoring <kind>/<ns>/<name>: the server could not find the requested resource`. Verified with `keycloaks.k8s.keycloak.org`.
   - **What works (manual):** a one-time label on the unlabelled CRDs on the source cluster (`oc label crd <names> <key>=<value>`), plus a selector for that label. Put the exact command in a comment in the recipe and in the hand-off to the user.
   - **Without a manual step (job hook):** a `job` hook at the START of the backup workflow that runs `oc label crd <names> <key>=<value> --overwrite` under a ServiceAccount whose ClusterRole allows `get`/`patch` on exactly those CRDs (`resourceNames`). The ServiceAccount, Role/RoleBinding and ClusterRole/ClusterRoleBinding are applied once on the source.  The same ServiceAccount also runs on the restore, so the user has one `oc apply` instead of a label command. Label the ClusterRole/ClusterRoleBinding with a label the cluster-scoped group selects so the restore recreates them. 
   - **A check hook cannot verify the label.** Check hooks run as the `transaction-manager` ServiceAccount (and the app namespaces' ServiceAccounts), none of which can `get` CRDs (tested with `oc auth can-i`). A job hook can, if you give its ServiceAccount that right.
   - **Make a missing label fail the backup instead of the restore (verified):** put the label selector in a resource group of its own, with `includedResourceTypes` set to the CRD type and `ignoreNoResources` left unset. A group that finds no objects of a listed type fails, and the backup fails with it (confirmed by running a backup with the label removed). Name the group after what it captures; with a labelling job hook in front, a failure here means the job did not label the CRDs. Do not add the label to an `orLabelSelector` shared with labelled CRDs: the other CRDs would satisfy the check. Limitation: it only proves that at least one CRD carries the label, not that all do.
   - List the unlabelled CRDs the app owns with `oc get crd -o json` and check for missing labels, ownerReferences and annotations. Do not label cluster objects for the user without asking.
3. **Webhooks need their own group, and some operators need them to start.** Use a separate group with `includedResourceTypes` of `validatingwebhookconfigurations.admissionregistration.k8s.io` / `mutatingwebhookconfigurations.admissionregistration.k8s.io`. Check three things on the source cluster before choosing where it goes in the restore order: the webhook's `failurePolicy`, its `namespaceSelector`/`rules` (which namespaces and resources it can block), and whether the operator looks the webhook up at startup. Verified with the IBM PG operator: it exits with `unable to setup PKI infrastructure ... webhookconfigurations ... not found` when its webhooks are missing, so they must be restored **before** the operator. Its webhooks only select the operator namespace, so a restored webhook cannot block the database objects in the app namespace.
4. **Restore order:** volumes → cluster-scoped (CRDs, RBAC) → webhooks → operator resources → application resources → operator readiness check. **Never put the operator readiness check before the application-namespace resources.** Operators often need Roles/RoleBindings and CRDs that live with the application, and crash-loop (`CrashLoopBackOff`, 403 `forbidden` in logs) until those are restored. A check placed right after the operator group times out (`1 == []`, meaning `readyReplicas` is unset). Give that check a long timeout (900s), because crash-loop back-off grows to 5 minutes. In the backup workflow put the cluster-scoped groups first.
5. **A group that backs up zero objects always fails the backup** (`BMYBR0009 No resources were backed up for resource group …`), even with `ignoreNoResources: true` (verified). The flag only downgrades a *missing type* to a warning when the group still backed up at least one other object. So put an optional type (e.g. an SCC that exists only when a component is installed) in a group that also lists always-present types, and set `ignoreNoResources: true` there. Never give an optional type a group of its own.
6. Cluster-scoped groups still need `includedNamespaces` that are in the Application CR's `includedNamespaces`.
7. **Prerequisites that a recipe cannot supply** (image pull secrets for a registry, entitlement keys, storage classes, an operator catalog/Helm install) should be called out to the user as fresh-cluster prerequisites.
8. Validate with a server-side dry run: `oc apply --dry-run=server -f <recipe>.yaml -n <recipe-namespace>`. This checks the schema only; a real backup and a restore onto a fresh cluster are the real test.

### Multi-namespace applications

A recipe group listing a namespace in `includedNamespaces` does **not** make that namespace part of the application. Fusion builds its original-to-target namespace mappings from the **Application CR** (`fapp`), not from the recipe. If a group names a namespace that is not in the Application CR's `spec.includedNamespaces`, backup may appear to succeed but **restore fails** after the volume groups with:

```
AssertionError('Unexpected: No original namespace(s) defined!')
```

(Restore logs show `namespace_mappings: {'ns-a': 'ns-a'}` with the missing namespace absent.)

Rules:
1. **Every namespace used by any group must be in the Application CR's `spec.includedNamespaces`.** Verify before generating the recipe:
   ```bash
   oc get fapp <app> -n <fusion-namespace> -o jsonpath='{.spec.includedNamespaces}{"\n"}'
   ```
2. If a namespace is missing, add it to the existing Application CR:
   ```bash
   oc patch fapp <app> -n <fusion-namespace> --type=json \
     -p '[{"op":"add","path":"/spec/includedNamespaces/-","value":"<extra-namespace>"}]'
   ```
3. **Do not delete the extra namespace's auto-created fapp to "merge" applications.** Fusion monitors namespaces and automatically creates a `fapp` for each one, so a deleted fapp is simply recreated. Leave it in place, and do not assign a policy to it (so it is not backed up twice).
4. **Take a new backup after changing the Application CR.** Each backup records its namespace mappings at backup time; a backup taken before the change will still fail on restore and cannot be used to test the fix.
5. **Dynamic recipes (parent/child recipes) do not solve this.** They add per-component workflows with priorities and parallel hook execution (child recipes linked by `dp.isf.ibm.com/parent-recipe` and `dp.isf.ibm.com/parent-recipe-namespace` labels). They do not add namespaces to an application. Only suggest them when the user needs separately maintained components or parallel hooks.
6. Use `${GROUP.<group-name>.namespace}` (single namespace enforced) or `${GROUP.<group-name>.namespaces}` (all effective namespaces) in hook namespaces rather than hardcoding any of the namespaces.
7. **Never hardcode namespace names; use Application variables.** An application default namespace can always differ from a real install. A recipe with the wrong names fails the backup at validation (`BMYBR0009`): `Hook '<name>' refers to a non-existing variable 'GROUP.<group>.namespace'`, because the group's namespace is not in the Application CR's `spec.includedNamespaces` and so has no value for `${GROUP...}`. A server dry run does NOT catch this. Fix: Fusion has a variable mechanism. The Application CR has `spec.variables` (a list of `name`/`value`), and the transaction-manager substitutes `${NAME}` in group `includedNamespaces` and in hook `namespace`/command fields (found in `RecipeCommand.substitute_variables` and `Recipe.apply_application`; Fusion's own recipes use `${FBR_NAMESPACE}` and `${PARENT_NAMESPACE}` from the `ibm-spectrum-fusion-ns` Application, and the Maximo samples use `${MAS_INSTANCE_ID}` and `${MONGODB_NAMESPACE}` in `includedNamespaces`). So: (a) write every `includedNamespaces` entry as `${APP_NAMESPACE}`-style variables; (b) set them in the SAME `oc patch fapp ... --type merge` that adds the namespaces to `includedNamespaces`; (c) leave `metadata.namespace` out of the Recipe and apply with `oc apply -n <app-ns>`; (d) leave `metadata.namespace` out of Jobs under `spec.jobs` (a Job runs in its hook's namespace), and have job scripts read their namespace from `/var/run/secrets/kubernetes.io/serviceaccount/namespace`; (e) ship RBAC as an OpenShift `Template` with a namespace parameter (`oc process -f x.yaml -p NS=<ns> | oc apply -f -`). Only the `PolicyAssignment` `recipe.namespace` has to be a literal. Put a comment block at the top of the recipe with the exact `oc patch` command. Use the variable names only inside `includedNamespaces` and hook fields. Do not write `${` anywhere in a Job string unless it is a Fusion variable. UNVERIFIED on a cluster: whether the variable values survive into the saved backup metadata for a restore on another cluster. Check that the target Application CR has the variables after the restore, and set them first if it does not.

### Hooks
- **`exec`** hooks run a shell command inside a container — use for quiesce, flush, fsync, and post-restore init commands
- **`scale`** hooks scale a workload up or down — use when no in-container quiesce command exists (scale to zero before backup, scale back up after restore)
  - **Do not put `<scale-hook>/sync` after `/up` for Deployments.** Fusion's `sync` locates a Deployment's pods through the latest ReplicaSet by `creationTimestamp` (1s resolution). After a restore several ReplicaSets often share a second, Fusion may pick an inactive one, and the job hangs forever on `Syncing: configured are 1, currently there's 0 pods` while the pods are healthy. Use a `check` hook (`{$.spec.replicas} == {$.status.readyReplicas}`) to wait instead. `/sync` after `/down` and `/sync` on StatefulSets are fine. See `recipe-crd-reference.md`.
- **`check`** hooks poll a JSONPath condition — use to verify readiness after restore before declaring success
  - **Verify the workload kind before choosing `selectResource`.** Don't assume a StatefulSet or Deployment. Some operators run each database as a **bare pod** with no StatefulSet, so a `selectResource: statefulset` check finds nothing and fails the restore. Ask the user to run `oc get statefulsets,deployments,pods -n <ns> -l <label>` and pick the kind that actually exists.
  - For pods use `selectResource: pod` with `condition: '{$.status.phase} == {"Running"}'`. String comparisons use the `{"Value"}` form, as in the IBM Db2 sample (`'{$.status.state} == {"Ready"}'`). Custom resources can be selected by `group/version/kind-plural` (e.g. `db2u.databases.ibm.com/v1/db2uinstances`).
- Set `inverseOp` on quiesce `exec` ops pointing to the resume op — this auto-triggers resume if backup fails mid-sequence
- A quiesce that only flushes (`CHECKPOINT`, `FLUSH TABLES`) is not a quiesce: the backup stays crash-consistent. Also give the quiesce its own time limit inside the application (a lock session that ends by itself, `timeout`, a server-side limit), because `inverseOp` only runs when Fusion survives the failure.
- **An exec command runs without a shell.** A plain string is split on spaces. A string that contains `[` is parsed as a JSON array first (read from the transaction-manager `AppHooks.executeHook`). For pipes, `&&`, redirection or background processes write the command as one JSON array line, `["/bin/bash","-c","..."]`, in a `|-` block scalar, and check it with `python3 -c "import json;json.loads(...)"`. Do not use `$` or `{` in it (Fusion substitutes `${...}` variables in exec commands; test with `oc apply --dry-run=server` and read the object back). Run the exact argv by hand with `oc exec <pod> -c <container> -- <argv>` before the first backup.
- A `volume` group returns when each VolumeSnapshot is `readyToUse`, not when the data has been uploaded: the upload happens after the workflow ("=== Post recipe execution ===" in the log). So a quiesce wrapped around the volume groups only lasts as long as the snapshot creation (seconds), not the upload time.
- The PVC snapshots of several volume groups are taken one group after the other, so wrap all the groups that must be consistent with each other in a single quiesce/resume pair.
- Use `singlePodOnly: true` on `exec` hooks targeting replica sets or clusters where the command should run on only one pod (e.g. primary/leader)

### Workflows
Always create exactly two workflows named `backup` and `restore`:

**Backup sequence** (canonical ordering):
1. Capture Kubernetes resource metadata (`resource` groups) and run slow prerequisites (label jobs, flush/CHECKPOINT)
2. Quiesce hook (block writes, lock tables, freeze, enter backup mode). Start it as late as possible, immediately before the volume groups
3. Capture the volumes that must be consistent with each other (`volume` groups): the quiesce holds for exactly this step
4. Resume hook, immediately after those volume groups (also set as `inverseOp` of the quiesce op)
5. Capture any volumes that do not need to be consistent with the application (large static or independent data) after the resume, so they do not lengthen the write block

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
          command: "<quiesce command>"   # plain string; see recipe-crd-reference.md before using the JSON-array form
          container: <container-name>
          inverseOp: resume
        - name: resume
          command: "<resume command>"
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
4. Remind the user to apply the recipe. The Recipe may resdide in a common namespace like the Fusion namespace or in the application's namespace.    Follow the user's preference:
   ```
   oc apply -f <recipe-filename>.yaml -n <recipe-namespace>
   ```
5. Explain how the recipe is associated with the application: it is **assigned through the `PolicyAssignment` CR's `spec.recipe`** (`name` and `namespace`), not by matching the Recipe name to the Application name. Provide the PolicyAssignment (see `recipe-crd-reference.md`) and note that the Recipe must exist before the PolicyAssignment references it. A single recipe can be specified per PolicyAssignment. Setting it on an existing assignment:
   ```
   oc -n <fusion-namespace> patch policyassignment <name> --type merge \
     -p '{"spec":{"recipe":{"name":"<recipe>","namespace":"<recipe-namespace>"}}}'
   ```
6. Explain restore behaviour: Fusion copies the recipe used at backup time into the backup metadata. On restore to the original namespace, a Recipe CR with the same name and namespace takes precedence if it exists (useful for changing workflows or hooks at restore time); otherwise Fusion uses the copy saved with the backup. Editing the recipe therefore does not change what an existing backup will do on restore unless a same-named Recipe CR is present.
7. Tell the user that after changing a recipe's groups or the Application CR's namespaces, they should take a new backup before testing restore.
8. **Clean the target cluster properly between restore tests.** Do not force-remove a namespace's finalizers (`/finalize`) to get past a hung `Terminating` namespace. The objects still holding finalizers stay in etcd and **reappear, already marked for deletion, when a namespace of the same name is recreated**. To clean up:
   - Delete the application namespace first and wait for it to finish, and only then the operator namespace. If both are deleted together the operator is gone before it can process its finalizers, which is the likely cause of the hang.
   - If it still hangs, list what is left (`oc api-resources --verbs=list --namespaced -o name | xargs -n1 oc get -n <ns> --ignore-not-found`) and clear the finalizer on that single object (`oc patch <kind> <name> -n <ns> --type merge -p '{"metadata":{"finalizers":null}}'`), not on the namespace 
   - Clearing a finalizer on a single object is acceptable only because the whole namespace is being thrown away.
   - Check the first lines of the Velero restore log for `attempting patch on` entries for the app's top-level custom resource. If they are there, the target was not clean.


---

## Restoring to a different cluster: operator-managed objects

These are tips when restoring from one OpenShift cluster to another with a different apps domain.

1. **Exclude `certificaterequests.cert-manager.io` from resource groups.** A restored request named with the source cluster makes cert-manager fail with `Failed to create CertificateRequest: ... already exists` when it must re-issue the certificate. The TLS Secret then keeps the source cluster's hostnames and the Certificate stays `Ready=False`. Verified: deleting the restored requests let cert-manager re-issue, and the Secret then listed the new hostnames.
2. **Known limitation: Velero does not restore `metadata.ownerReferences`** (upstream Velero issue https://github.com/velero-io/velero/issues/4707). Fusion Backup & Restore is built on Velero, so this applies to every Fusion restore. Fusion has custom code that re-adds ownerReferences only for Virtual Machine PVCs; nothing equivalent exists for other kinds, and a recipe cannot set ownerReferences itself (annotation and label hooks cannot). Consequences for any operator-managed application:
   - Every restored object that the source cluster had owned (Deployments, Services, Secrets, ConfigMaps, Roles, Certificates, ...) comes back **ownerless**. Garbage collection no longer ties it to its parent CR, and operators that expect to adopt or patch their generated objects can fail on the restored copies.
   - Designs that work: (a) **exclude the kinds the operator generates** (`excludedResourceTypes`) so the operator recreates them with owners; (b) where one restored object must be kept for its data (a credential matching a restored database), **re-add only its ownerReference with a `job` hook** (patch with the NEW parent CR's uid; the old uid in the backup is invalid on the new cluster).
   - Do not plan on restoring objects with their original ownerReferences, and do not copy a parent uid from the backup: uids are regenerated.
   - Because of this, ask in Step 1 which objects are operator-generated, and check the source for `metadata.ownerReferences` (`oc get <kind> -o json | grep -c ownerReferences`).
3. **The operator that owns the application CR may gate its own reconcile on the dependency CR being Ready.** 
4. **Do not delete a generated admin Secret without saving it first.** The operator generates a new random password, which no longer matches the credential stored in a restored database. Save `.data`, and restore it with `oc patch` if you delete it. Delete the saved copy afterwards.
5. **Restart the application operator after fixing its dependency.** Restarting operators clears the (regenerated) password. Restart the operator whenever a Secret it reads was recreated or patched.
6. **Hostnames in restored operator-generated objects are not rewritten.** Restored objects keep the source cluster's hostnames: `EXTERNAL_DOMAIN` and similar env vars in the Deployments, ConfigMaps, Secret, Certificat, or CRs. The operator does not recreate a deleted object by itself; it requires a restart.  Additionally, Routes restored from the source have no owner after the restore, so nothing garbage-collects them.  The Ingress controller creates new Routes with the new hostname. CRs may be different if it is applied by Helm without an owner, and its `spec.clusterID` is not in the Helm manifest. The restored CR carries the source cluster value, so deleting and recreating its Deployment leaves `CLUSTER_ID` on the source domain. Whether the operator would overwrite a non-empty `clusterID` depends on the operator.
7. **Service CA serving-cert Secrets restored from another cluster are rejected.** Secrets will be restored with the `originating-service-uid` of the source cluster's Service. The target's Service CA logs `secret ... does not have corresponding service UID` and will not regenerate it, and as a result, the restored operator cannot recreate its Deployment because the secret already exists. The certificate was also signed by the source cluster's service signer, so it is not valid on the target. One solution is to delete the Secret and restart the operator; the Service CA issues a new one for the target Service's UID.  A recipe group cannot exclude it by label or name (groups only have `excludedResourceTypes`, not excluded labels or names), and excluding all `secrets` is not an option because operator-generated database credentials must match the restored data.
8. **Excluding `deployments.apps` for the operator-generated Deployments.** With `deployments.apps` and `certificaterequests.cert-manager.io` excluded from the app group, a restore to a cluster with a different apps domain finished with 0 failed commands and no manual step for the Deployments. The operator creates all Deployments itself (with owner references and target cluster string in Deployments).  The scale hooks need `skipHookIfNotPresent: true` (their `down` and `sync` ran as no-ops).  Certificates are re-issued, and the gateway Ingress and Routes will get the target hostnames. No operator restart is needed for the Deployments. One possible side effect: a few app pods may restart or replace themselves while the databases come up.
9. **Resource-type exclusion is the only filter a recipe group offers, so it excludes a whole kind.** Excluding a kind is safe only where every object of that kind in the namespace is operator-generated. If deployed by Helm, check the Helm manifest: the only Helm Service was in the operator namespace). It does NOT hold for `secrets` (database credentials must match the restored data), or `configmaps` (Helm-owned).
10. **Fusion transformation** (`Transform` CR, referenced from the `Restore` CR with `transform` and `transformMapping`) can rewrite resources during the restore, including string patches on `deployments.apps` and `configmaps`. For a custom recipe, each resource group needs `disableTransform: false`. The `Transform` CR must exist on the target cluster. Use it only if excluding operator-generated objects from the backup does not work.
11. **`job` hook for RBAC** Any RBAC that needs to be applied can be done with a job hook.  The Fusion agent creates the Job, waits for Complete/Failed, collects the pod log, then deletes the Job. Rules found: `${...}` in the Job string is substituted by Fusion, so write `$VAR` in scripts and never `${`; a missing Job name/namespace defaults to the hook's. The Job pod runs under normal admission, so in a namespace with the `restricted` Pod Security Standard set `runAsNonRoot`, `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, drop `ALL` and `readOnlyRootFilesystem` (mount an `emptyDir` on `/tmp`, set `HOME=/tmp`). A container is required to run the job.
    - **The Job needs its own ServiceAccount, Role and RoleBinding in the app namespace, and those must exist before the job runs.** A recipe cannot create them, and the existing operator ServiceAccounts cannot do the work; no single operator ServiceAccount has all the rights, and a Job pod cannot use a ServiceAccount from another namespace anyway). Put them in the application namespace on the SOURCE (`application-rbac.yaml`, an OpenShift Template: `oc process -f appication-rbac.yaml -p APP_NAMESPACE=<app-ns> | oc apply -f -`); the backup captures them and the restore brings them back before the job. Scope every rule with `resourceNames`.
    - **Placement:** the job step goes at the END of the restore workflow, after the scale hooks and before check hooks.
12. **Helm-installed sub-components can add objects and vary deployments.** Re-inspect each new install; do not assume the recipe from the first one is complete or will work for a different install with different components.
13. **Never put a `scale` hook on a workload that an operator owns and reconciles** On the restore, manually scaling can conflict with operator scaling and result in a hang.  Scaling only works for workloads with no controller above them.


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
