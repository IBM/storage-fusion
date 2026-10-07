# IBM Fusion Recipe CRD Field Reference

Source: `isf-data-protection-operator/config/crd/bases/spp-data-protection.isf.ibm.com_recipes.yaml`

```
apiVersion: spp-data-protection.isf.ibm.com/v1alpha1
kind: Recipe
metadata:
  name: <string>         # Must match the Application CR name in IBM Fusion
  namespace: <string>    # Typically the IBM Fusion operator namespace (ibm-spectrum-fusion-ns)
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
| `includeClusterResources` | boolean | | Include cluster-scoped resources associated with included namespaced resources. Defaults to `true` if nil. |
| `backupRef` | string | | For restore-only groups: name of the backup group this group restores from. |
| `restoreOverwriteResources` | boolean | | If `true`, overwrite existing resources during restore instead of skipping them. |

### Common resource types to exclude from resource groups

Always exclude these from `resource` groups to avoid capturing ephemeral or auto-recreated objects:
```yaml
excludedResourceTypes:
  - events
  - event.events.k8s.io
  - replicasets
  - pods
```

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
| `command` | string | ✅ | The shell command to execute. Use JSON array format: `["/bin/bash", "-c", "..."]` |
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
