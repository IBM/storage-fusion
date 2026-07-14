# W002 — docling / vllm / cast-runtime CrashLoopBackOff: SCC fsGroup Override

**Recurrence:** Non-Recurrent — apply once before affected pods first start; persists until
the SCC or RBAC is removed.

---

## Symptom

After a CAS upgrade (or on a fresh install), one or more of the following are observed:

- `docling` pod is `1/2 CrashLoopBackOff`. Logs show:
  ```
  FileNotFoundError: .../ch_PP-OCRv4_det_mobile.onnx does not exist
  ```
  A stale `huggingface-model-data` PVC contains `_infer`-suffix model files; CAS 1.1.5
  expects `_mobile`-suffix files.

- `vllm-embedding` or `vllm-vision` pods are `1/2 CrashLoopBackOff`. Logs show:
  ```
  PermissionError: [Errno 13] Permission denied: '/models/modules'
  ```

- `cast-runtime` pod logs show:
  ```
  Error publishing messages [Errno 13] Permission denied: '/shared/<jobID>'
  ```
  Inside the pod:
  ```bash
  $ stat /shared
  Access: (0755/drwxr-xr-x)  Uid: (0/root)  Gid: (0/root)
  ```

## Root Cause

`ibm-cas-setuid-setgid-scc` is configured with `fsGroup: RunAsAny` (priority 10). When this
SCC wins pod admission, the kubelet skips fsGroup injection entirely and does not chown
volume mounts. PVC mounts remain owned by `root:root`, and pods running as a non-root UID
cannot write to them.

## When to Apply

**Before the DocumentProcessor, vllm, and docling pods first start.** The SCC must exist at
pod admission time.

If the affected pods have already started under the wrong SCC, apply all steps below and
then bounce them (step 4).

## Steps

**Step 1 — Create override SCC** (priority 11 beats the existing SCC at priority 10):

```bash
oc apply -f - <<'EOF'
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: ibm-cas-cast-runtime-mustrunasgroup
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
allowedCapabilities: [SETUID, SETGID]
fsGroup:
  type: MustRunAs
groups: []
users: []
runAsUser:
  type: MustRunAsNonRoot
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
volumes: [configMap, emptyDir, persistentVolumeClaim, secret]
EOF
```

**Step 2 — Create ClusterRole:**

```bash
oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ibm-cas-cast-runtime-mustrunasgroup-use
rules:
- apiGroups: [security.openshift.io]
  resourceNames: [ibm-cas-cast-runtime-mustrunasgroup]
  resources: [securitycontextconstraints]
  verbs: [use]
EOF
```

**Step 3 — Bind to the relevant service accounts:**

```bash
oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ibm-cas-cast-runtime-mustrunasgroup-use
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ibm-cas-cast-runtime-mustrunasgroup-use
subjects:
- kind: ServiceAccount
  name: ibm-isf-cas-operator-system
  namespace: ibm-cas
- kind: ServiceAccount
  name: default
  namespace: ibm-cas
EOF
```

**Step 4 — Bounce affected pods** so they are re-admitted under the new SCC:

```bash
# Replace <domain> with your DocumentProcessor domain name (e.g. deucalion-domain)
oc delete pod -n ibm-cas \
  -l app.kubernetes.io/component=cast-runtime,app.kubernetes.io/part-of=<domain>
oc delete pod -n ibm-cas -l app.kubernetes.io/component=vllm
oc delete pod -n ibm-cas -l app.kubernetes.io/name=docling
```

## Verify

After pods restart, confirm they are admitted under the new SCC:

```bash
oc get pod <pod-name> -n ibm-cas \
  -o jsonpath='{.metadata.annotations.openshift\.io/scc}{"\n"}'
# Expected: ibm-cas-cast-runtime-mustrunasgroup
```
