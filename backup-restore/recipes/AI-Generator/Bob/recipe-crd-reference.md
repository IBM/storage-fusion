# IBM Fusion Recipe CRD Field Reference

Source: `isf-data-protection-operator/config/crd/bases/spp-data-protection.isf.ibm.com_recipes.yaml`

```
apiVersion: spp-data-protection.isf.ibm.com/v1alpha1
kind: Recipe
metadata:
  name: <string>         # Referenced from PolicyAssignment spec.recipe (not auto-matched to the Application name)
  namespace: <string>    # Fusion namespace (recommended) or the application namespace; must match PolicyAssignment spec.recipe.namespace
spec:
  appType: <string>      # REQUIRED. Type/name of application this recipe targets.
  groups: []             # REQUIRED. At least one group must be defined.
  hooks: []              # Optional. List of exec, scale, or check hooks.
  workflows: []          # REQUIRED. Must include "backup" and/or "restore" workflows.
```

---

## spec.groups[]

Each group narrows the scope of what is captured or restored.

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | ✅ | Unique name for this group within the Recipe |
| `type` | enum | ✅ | `volume` — captures PVCs; `resource` — captures Kubernetes objects |
| `parent` | string | | Name of the parent group in the Application CR. If omitted, uses the Application CR's implicit default group. |
| `essential` | boolean | | Defaults to `true`. If `false`, a group failure is not treated as fatal. |
| `includedNamespaces` | string[] | | Namespaces to include. |
| `includedNamespacesByLabel` | string | | Select namespaces by label selector. |
| `includedResourceTypes` | string[] | | Resource types to include. If omitted, all types are included. (**resource** groups only) |
| `excludedResourceTypes` | string[] | | Resource types to exclude. (**resource** groups only) |
| `excludedNamespaces` | string[] | | Namespaces to exclude. |
| `labelSelector` | string | | Select items matching this label selector. |
| `nameSelector` | string | | Select volumes whose PVC name matches this expression. (**volume** groups only) |
| `selectResource` | enum | | What resource type `labelSelector`/`nameSelector` apply to for PVC selection. One of: `pvc` (default), `pod`, `deployment`, `statefulset`. (**volume** groups only) |
| `includeClusterResources` | boolean | | Include cluster-scoped resources associated with included namespaced resources. If nil or `true`, the default set is Namespace, ClusterRole, ClusterRoleBinding, and (OpenShift 4.22+) SecurityContextConstraints of the application's pods. **CRDs and webhook configurations are not in the default set** — capture them with `includedResourceTypes` plus a label selector (see "Cluster-scoped resources" in SKILL.md). |
| `orLabelSelector` | string[] | | Select items matching ANY of the label selectors (OR). `labelSelector` is AND. |
| `ignoreNoResources` | boolean | | If `includedResourceTypes` or `includeClusterResources` is used and no objects of a listed type exist, the group fails. Set `true` for optional types, but only in a group that still matches at least one object: a group that backs up nothing fails regardless (BMYBR0009). |
| `backupRef` | string | | For restore-only groups: name of the backup group this group restores from. |
| `restoreOverwriteResources` | boolean | | If `true`, overwrite existing resources during restore instead of skipping them. |

### Common resource types to exclude from resource groups

Exclude these from `resource` groups to avoid capturing ephemeral or auto-recreated objects:
```yaml
excludedResourceTypes:
  - replicasets
  - pods
```

Do not list `events` or `event.events.k8s.io`: Fusion and Velero already exclude events by default.

### Dynamic namespace reference

Use `${GROUP.<group-name>.namespace}` in hook `namespace` fields to avoid hardcoding namespaces. The value is resolved at runtime from the namespace of the named group.

```yaml
namespace: ${GROUP.myapp-volumes.namespace}
```

---

## spec.hooks[]

Hooks are actions executed at specific points in the backup or restore workflow sequence.

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | ✅ | Unique hook name within the Recipe |
| `namespace` | string | ✅ | Namespace where the hook executes |
| `type` | enum | ✅ | `exec` — run a command; `scale` — scale a workload; `check` — poll a condition |
| `selectResource` | enum | | Resource type the hook targets: `pod`, `deployment`, or `statefulset` |
| `labelSelector` | string | | Select target resources by label |
| `nameSelector` | string | | Select target resources by name expression |
| `singlePodOnly` | boolean | | If `true`, run the exec command on only one matching pod (use for primary/leader targeting) |
| `essential` | boolean | | Defaults to `true`. If `false`, hook failure is not fatal. |
| `onError` | enum | | Default error behaviour. `fail` (default) or `continue` |
| `timeout` | integer | | Default timeout in seconds for all ops/chks in this hook. Default: 30s |
| `ops` | Op[] | | List of exec operations (for `exec` type hooks) |
| `chks` | Chk[] | | List of check conditions (for `check` type hooks) |

### Hook type: `exec` — ops[]

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | ✅ | Unique operation name within this hook |
| `command` | string | ✅ | The command to execute. For simple commands use a plain quoted string, as in the IBM PostgreSQL sample (`command: "psql -c CHECKPOINT"`). The JSON-array form (`command: >` followed by `["/bin/bash", "-c", "..."]`) is used in some other samples, but on a Fusion 2.14 cluster it was run as a literal string and failed with `executable file '/["/bin/bash",' not found`. Prefer the plain string; use the array form only when a shell is genuinely needed (pipes, `&&`, env var expansion), and test it with a backup before relying on it. |
| `container` | string | | Container name to run the command in. Required when the pod has multiple containers. |
| `timeout` | integer | | Timeout for this operation in seconds (overrides hook-level timeout) |
| `onError` | string | | `fail` or `continue` (overrides hook-level onError) |
| `inverseOp` | string | | Name of another op in this hook that reverses this operation. Auto-triggered on backup failure. |

### Hook type: `check` — chks[]

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | ✅ | Unique check name within this hook |
| `condition` | string | | JSONPath condition expression to evaluate, e.g. `{$.spec.replicas} == {$.status.readyReplicas}` |
| `jsonpath` | string | | Alternative field name for `condition` (older field name — use `condition` in new recipes) |
| `timeout` | integer | | How long to wait for the condition to become true, in seconds |
| `onError` | string | | `fail` or `continue` |

### Hook type: `scale`

Scale hooks use built-in operations. Reference them in workflow sequences as:
- `hook: <hook-name>/down` — scale the workload to zero replicas
- `hook: <hook-name>/up` — scale the workload back to its original replica count
- `hook: <hook-name>/sync` — wait for the scale operation to complete

No `ops` or `chks` are needed for scale hooks.

**Caution: `/sync` on Deployments after `/up`.** For a Deployment, `sync` finds its pods through the *latest ReplicaSet by `creationTimestamp`* (one-second resolution). After a restore, Velero and the app operators often leave several ReplicaSets created in the same second. Fusion then picks the first of the tied ones, which may be an inactive (0-replica) ReplicaSet, and `sync` loops forever with `Syncing: configured are N, currently there's 0 pods` (verified from the transaction-manager log and the ReplicaSet list; the logic was read from the compiled `bacutils.get_pods_for_deployments`). For Deployments, after `/up` use a `check` hook (`{$.spec.replicas} == {$.status.readyReplicas}`) instead of `/sync`. `/sync` after `/down` is harmless (it expects 0 pods), and `/sync` on StatefulSets is fine because their pods are found by owner reference.
### Hook type: `job` — jobs[] (verified on IBM Bob: backup-time and restore-time jobs both worked)

The Job object itself is defined either inline in the hook, or in the top-level `spec.jobs` list, whose entries are `<hook name>: <Job as a YAML/JSON string>`.

| Field (`hooks[].jobs[]`) | Type | Required | Description |
|---|---|---|---|
| `name` | string | ✅ | Job name, unique among jobs. Workflow step: `hook: <hook-name>/<name>` |
| `timeout` | integer | | Seconds to wait for the Job to complete. Default 864000 (10 days) |
| `onError` | string | | `fail` (default) or `continue` |
| `forceCreate` | boolean | | Remove an existing Job of the same name/namespace first. Default false |
| `inverseOp` | string | | Name of another operation that reverts this one if the hook fails |

Behaviour: the transaction-manager creates the Job, waits for Complete or Failed, collects the pod log, then deletes the Job. `${...}` variables inside the Job string are substituted (avoid `${` in shell scripts). The Job runs in the hook's `namespace` and needs its own ServiceAccount and Role there. Pod Security admission of that namespace applies.



---

## Application CR (fapp)

Fusion automatically creates one Application CR per monitored namespace, and recreates it if deleted. The Application CR, not the recipe, defines which namespaces belong to the application and therefore the namespace mappings used on restore.

```yaml
apiVersion: application.isf.ibm.com/v1alpha1
kind: Application
metadata:
  name: <app>
  namespace: <fusion-namespace>
spec:
  includedNamespaces:           # EVERY namespace referenced by any recipe group must be listed here
    - <namespace-1>
    - <namespace-2>
  variables:                    # optional; referenced as ${NAME} in hook namespace fields and exec commands
    - name: <NAME>
      value: <value>
```

Reserved variables set by Fusion (do not redefine, except `ISF_ALLOWED_UNRESOLVED_VARS`): `ISF_BACKUP_UID`, `ISF_NAMESPACE_MAPPINGS` (`src:target,src:target`), `ISF_NOT_EQUAL_NAMESPACE_MAPPINGS`, `ISF_ALLOWED_UNRESOLVED_VARS` (`"true"` skips unresolved-variable verification; needed if exec commands use shell variables/array syntax).

Group-derived variables: `${GROUP.<groupname>.namespaces}` (effective namespaces) and `${GROUP.<groupname>.namespace}` (single namespace enforced; runtime validation error otherwise). Variables are valid only in hook `namespace` fields and exec hook commands.

---

## PolicyAssignment CR

```yaml
apiVersion: data-protection.isf.ibm.com/v1alpha1
kind: PolicyAssignment
metadata:
  name: <name>
  namespace: <fusion-namespace>   # typically ibm-spectrum-fusion-ns or ibm-fusion
spec:
  application: <fapp-name>        # plain string — the name of the fapp CR
  backupPolicy: <policy-name>     # plain string — the name of the Fusion backup policy
  recipe:
    name: <recipe-name>           # must match Recipe metadata.name
    namespace: <recipe-namespace> # must match Recipe metadata.namespace
```

---

## spec.workflows[]

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | ✅ | Workflow name. `backup` and `restore` are reserved names used automatically by IBM Fusion. |
| `sequence` | object[] | ✅ | Ordered list of steps. Each step is either `group: <name>` or `hook: <name>/<op-or-chk>` |
| `failOn` | enum | | `any-error` (default), `essential-error`, or `full-error` |

### Sequence step format

```yaml
sequence:
  - group: my-volumes          # execute a group (capture or restore)
  - hook: my-exec/quiesce      # execute a specific op within an exec hook
  - hook: my-check/replicasReady  # evaluate a specific check within a check hook
  - hook: my-scale/down        # built-in scale-down operation
  - hook: my-scale/up          # built-in scale-up operation
  - hook: my-scale/sync        # built-in wait-for-scale operation
```

---

## Required fields summary

```
spec.appType        — required
spec.groups         — required (at least one)
spec.groups[].name  — required
spec.groups[].type  — required (volume | resource)
spec.workflows      — required (at least one)
spec.workflows[].name     — required
spec.workflows[].sequence — required

spec.hooks[].name       — required
spec.hooks[].namespace  — required
spec.hooks[].type       — required (exec | scale | check)
spec.hooks[].ops[].name    — required (exec hooks)
spec.hooks[].ops[].command — required (exec hooks)
spec.hooks[].chks[].name   — required (check hooks)
```
