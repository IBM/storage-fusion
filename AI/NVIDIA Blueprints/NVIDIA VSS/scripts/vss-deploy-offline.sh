#!/usr/bin/env bash
# =============================================================================
# vss-deploy-offline.sh
#
# PURPOSE: Run this on the machine with oc access to your OFFLINE OCP cluster.
#          Applies the offline fix for two VSS pods:
#
#   1. vss-agent             — mounts pre-built NumPy/OpenCV bundle from PVC
#   2. vss-vios-streamprocessing — redirects apt to internal offline repo
#
# PREREQUISITES:
#   - oc CLI installed and logged into the target cluster
#   - vss-codecs.tar.gz    (from vss-prepare-offline.sh)
#   - vss-apt-repo.tar.gz  (from vss-prepare-offline.sh)
#
# USAGE:
#   ./vss-deploy-offline.sh
# =============================================================================

set -euo pipefail

# ── colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── banner ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  VSS Offline — Cluster Deployment"
echo "============================================================"
echo ""
echo -e "${YELLOW}Each prompt shows a default value in [brackets].${NC}"
echo -e "${YELLOW}Press Enter to accept the default, or type a new value.${NC}"
echo ""

# ── prompt helper ─────────────────────────────────────────────────────────────
prompt() {
    local var_name="$1" desc="$2" default="$3"
    if [[ -z "${!var_name:-}" ]]; then
        read -rp "${desc} [${default}]: " input
        eval "${var_name}=\"${input:-${default}}\""
    fi
}

# ── inputs ────────────────────────────────────────────────────────────────────
NAMESPACE="${NAMESPACE:-}"
CODECS_BUNDLE="${CODECS_BUNDLE:-}"
APT_BUNDLE="${APT_BUNDLE:-}"
VSS_AGENT_IMAGE="${VSS_AGENT_IMAGE:-}"
APT_SERVER_IMAGE="${APT_SERVER_IMAGE:-}"

# common
prompt NAMESPACE      "OCP namespace where VSS is deployed"   "vss-base"
prompt CODECS_BUNDLE  "Path to vss-codecs.tar.gz"             "./vss-codecs.tar.gz"
prompt APT_BUNDLE     "Path to vss-apt-repo.tar.gz"           "./vss-apt-repo.tar.gz"

# vss-agent image — already mirrored as part of the VSS bundle
if [[ -z "$VSS_AGENT_IMAGE" ]]; then
    echo ""
    echo -e "${CYAN}[INFO]${NC}  The VSS Agent image (nvidia/vss-core/vss-agent:3.2.1) must already be"
    echo -e "${CYAN}[INFO]${NC}  mirrored in your offline registry as part of the VSS bundle."
    echo -e "${CYAN}[INFO]${NC}  Provide the full reference including your registry prefix, e.g.:"
    echo -e "${CYAN}[INFO]${NC}    myregistry.example.com/nvidia/vss-core/vss-agent:3.2.1"
    echo ""
    read -rp "VSS Agent image (full reference with offline registry): " VSS_AGENT_IMAGE
    [[ -n "$VSS_AGENT_IMAGE" ]] || die "VSS Agent image is required."
fi

# python image for apt server — must be mirrored separately
if [[ -z "$APT_SERVER_IMAGE" ]]; then
    echo ""
    echo -e "${CYAN}[INFO]${NC}  The apt server requires a python:3.12-slim image."
    echo -e "${CYAN}[INFO]${NC}  This must be mirrored in your offline registry."
    echo -e "${CYAN}[INFO]${NC}  Provide the full reference including your registry prefix, e.g.:"
    echo -e "${CYAN}[INFO]${NC}    myregistry.example.com/library/python:3.12-slim"
    echo ""
    read -rp "python:3.12-slim image (full reference with offline registry): " APT_SERVER_IMAGE
    [[ -n "$APT_SERVER_IMAGE" ]] || die "Python image is required."
fi

# remaining with defaults
VSS_AGENT_DEPLOYMENT="${VSS_AGENT_DEPLOYMENT:-vss-agent}"
CODEC_PVC_NAME="${CODEC_PVC_NAME:-vss-agent-codecs}"
CODEC_PVC_SIZE="${CODEC_PVC_SIZE:-1Gi}"
CODEC_STORAGE_CLASS="${CODEC_STORAGE_CLASS:-ocs-storagecluster-cephfs}"
CODEC_MOUNT_PATH="${CODEC_MOUNT_PATH:-/codec-bundle}"
CODEC_FS_GROUP="${CODEC_FS_GROUP:-1001190000}"
CODEC_LOADER_POD="${CODEC_LOADER_POD:-vss-codec-loader}"

APT_PVC_NAME="${APT_PVC_NAME:-vss-offline-apt-repo}"
APT_PVC_SIZE="${APT_PVC_SIZE:-2Gi}"
APT_STORAGE_CLASS="${APT_STORAGE_CLASS:-ocs-storagecluster-ceph-rbd}"
APT_SERVER_DEPLOYMENT="${APT_SERVER_DEPLOYMENT:-vss-offline-apt-server}"
APT_SERVICE_NAME="${APT_SERVICE_NAME:-vss-offline-apt-repo}"
APT_LOADER_POD="${APT_LOADER_POD:-vss-offline-apt-loader}"
STS_NAME="${STS_NAME:-vss-vios-streamprocessing}"

prompt CODEC_STORAGE_CLASS  "StorageClass for codec PVC (RWX / CephFS)"     "$CODEC_STORAGE_CLASS"
prompt APT_STORAGE_CLASS    "StorageClass for APT PVC (RWO / Ceph RBD)"     "$APT_STORAGE_CLASS"

echo ""
log "Namespace               : $NAMESPACE"
log "Codecs bundle           : $CODECS_BUNDLE"
log "APT bundle              : $APT_BUNDLE"
log "VSS Agent image         : $VSS_AGENT_IMAGE"
log "APT server image        : $APT_SERVER_IMAGE"
log "Codec PVC               : $CODEC_PVC_NAME ($CODEC_PVC_SIZE, $CODEC_STORAGE_CLASS)"
log "Codec mount path        : $CODEC_MOUNT_PATH"
log "APT PVC                 : $APT_PVC_NAME ($APT_PVC_SIZE, $APT_STORAGE_CLASS)"
log "APT server deployment   : $APT_SERVER_DEPLOYMENT"
log "APT service             : $APT_SERVICE_NAME"
log "vss-agent deployment    : $VSS_AGENT_DEPLOYMENT"
log "streamprocessing STS    : $STS_NAME"
echo ""

# ── preflight ─────────────────────────────────────────────────────────────────
command -v oc >/dev/null 2>&1   || die "oc CLI not found."
oc whoami >/dev/null 2>&1       || die "Not logged into OCP. Run 'oc login' first."
[[ -f "$CODECS_BUNDLE" ]]       || die "Codecs bundle not found: $CODECS_BUNDLE"
[[ -f "$APT_BUNDLE" ]]          || die "APT bundle not found: $APT_BUNDLE"
oc get namespace "$NAMESPACE" >/dev/null 2>&1 \
    || die "Namespace '$NAMESPACE' not found."
oc get deployment "$VSS_AGENT_DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1 \
    || die "Deployment '$VSS_AGENT_DEPLOYMENT' not found in '$NAMESPACE'."
oc get statefulset "$STS_NAME" -n "$NAMESPACE" >/dev/null 2>&1 \
    || die "StatefulSet '$STS_NAME' not found in '$NAMESPACE'."
ok "Preflight checks passed."

# ── confirm ───────────────────────────────────────────────────────────────────
echo ""
warn "This will make the following changes to namespace '$NAMESPACE':"
warn "  [vss-agent fix]"
warn "    - Create PVC '$CODEC_PVC_NAME' (RWX, CephFS)"
warn "    - Create loader pod '$CODEC_LOADER_POD', stream codec bundle into PVC"
warn "    - Patch Deployment '$VSS_AGENT_DEPLOYMENT' (add volume + fsGroup)"
warn "  [streamprocessing fix]"
warn "    - Create PVC '$APT_PVC_NAME' (RWO, Ceph RBD)"
warn "    - Create loader pod '$APT_LOADER_POD', stream apt bundle into PVC"
warn "    - Deploy '$APT_SERVER_DEPLOYMENT' + Service '$APT_SERVICE_NAME'"
warn "    - Patch StatefulSet '$STS_NAME' args (redirect apt to offline server)"
echo ""
read -rp "Proceed? (yes/no) [no]: " CONFIRM
[[ "${CONFIRM}" == "yes" ]] || { echo "Aborted."; exit 0; }

# ══════════════════════════════════════════════════════════════════════════════
# PART 1 — vss-agent fix
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "------------------------------------------------------------"
echo "  Part 1/2 — vss-agent offline codec fix"
echo "------------------------------------------------------------"

# -- 1a: create codec PVC -----------------------------------------------------
echo ""
log "Step 1/4 — Creating PVC '$CODEC_PVC_NAME'..."

if oc get pvc "$CODEC_PVC_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    warn "PVC '$CODEC_PVC_NAME' already exists — skipping."
else
    oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${CODEC_PVC_NAME}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ${CODEC_STORAGE_CLASS}
  resources:
    requests:
      storage: ${CODEC_PVC_SIZE}
EOF
    log "Waiting for PVC to become Bound..."
    for i in {1..30}; do
        STATUS=$(oc get pvc "$CODEC_PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        [[ "$STATUS" == "Bound" ]] && { ok "PVC is Bound."; break; }
        [[ $i -eq 30 ]] && die "PVC '$CODEC_PVC_NAME' did not become Bound within 60s."
        sleep 2
    done
fi

# -- 1b: create codec loader pod ----------------------------------------------
echo ""
log "Step 2/4 — Creating codec loader pod '$CODEC_LOADER_POD'..."

if oc get pod "$CODEC_LOADER_POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    warn "Loader pod '$CODEC_LOADER_POD' already exists — deleting first..."
    oc delete pod "$CODEC_LOADER_POD" -n "$NAMESPACE" --wait=true
fi

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${CODEC_LOADER_POD}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  securityContext:
    fsGroup: ${CODEC_FS_GROUP}
  containers:
    - name: loader
      image: ${VSS_AGENT_IMAGE}
      command: ["sleep", "3600"]
      volumeMounts:
        - name: codecs
          mountPath: ${CODEC_MOUNT_PATH}
  volumes:
    - name: codecs
      persistentVolumeClaim:
        claimName: ${CODEC_PVC_NAME}
EOF

log "Waiting for codec loader pod to be Running..."
for i in {1..60}; do
    STATUS=$(oc get pod "$CODEC_LOADER_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    [[ "$STATUS" == "Running" ]] && { ok "Codec loader pod is Running."; break; }
    [[ "$STATUS" == "Failed"  ]] && { oc logs "$CODEC_LOADER_POD" -n "$NAMESPACE" || true; die "Codec loader pod failed."; }
    [[ $i -eq 60 ]] && die "Codec loader pod did not reach Running within 120s."
    sleep 2
done

log "Step 3/4 — Streaming codec bundle into PVC..."
cat "$CODECS_BUNDLE" | \
    oc exec -i "$CODEC_LOADER_POD" -n "$NAMESPACE" -- \
    /usr/local/bin/python3 -c '
import sys, tarfile, io
data = sys.stdin.buffer.read()
with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
    tar.extractall("'"${CODEC_MOUNT_PATH}"'")
print("Codec bundle extracted.")
' || die "Failed to stream codec bundle into pod."

MARKER=$(oc exec "$CODEC_LOADER_POD" -n "$NAMESPACE" -- \
    /bin/sh -c "test -f '${CODEC_MOUNT_PATH}/.installed' && echo yes || echo no")
[[ "$MARKER" == "yes" ]] || die ".installed marker not found in codec PVC."
ok "Codec bundle extracted and .installed marker confirmed."

# -- 1c: patch vss-agent deployment -------------------------------------------
echo ""
log "Step 4/4 — Patching Deployment '$VSS_AGENT_DEPLOYMENT'..."

EXISTING_VOL=$(oc get deployment "$VSS_AGENT_DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath="{.spec.template.spec.volumes[?(@.name=='codecs')].name}" 2>/dev/null || true)

if [[ "$EXISTING_VOL" == "codecs" ]]; then
    warn "Deployment already has 'codecs' volume — skipping patch."
else
    VOLUMES_EXISTS=$(oc get deployment "$VSS_AGENT_DEPLOYMENT" -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.spec.volumes}' 2>/dev/null || true)
    if [[ -z "$VOLUMES_EXISTS" || "$VOLUMES_EXISTS" == "null" ]]; then
        VOL_OP="add"; VOL_PATH="/spec/template/spec/volumes"
        VOL_VALUE="[{\"name\":\"codecs\",\"persistentVolumeClaim\":{\"claimName\":\"${CODEC_PVC_NAME}\"}}]"
    else
        VOL_OP="add"; VOL_PATH="/spec/template/spec/volumes/-"
        VOL_VALUE="{\"name\":\"codecs\",\"persistentVolumeClaim\":{\"claimName\":\"${CODEC_PVC_NAME}\"}}"
    fi

    oc patch deployment "$VSS_AGENT_DEPLOYMENT" -n "$NAMESPACE" --type=json -p="[
      {\"op\":\"add\",\"path\":\"/spec/template/spec/securityContext\",\"value\":{\"fsGroup\":${CODEC_FS_GROUP}}},
      {\"op\":\"${VOL_OP}\",\"path\":\"${VOL_PATH}\",\"value\":${VOL_VALUE}},
      {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/volumeMounts/-\",
       \"value\":{\"name\":\"codecs\",\"mountPath\":\"${CODEC_MOUNT_PATH}\"}}
    ]" || die "Failed to patch Deployment '$VSS_AGENT_DEPLOYMENT'."
    ok "Deployment patched."
fi

log "Waiting for rollout of '$VSS_AGENT_DEPLOYMENT'..."
oc rollout status deployment/"$VSS_AGENT_DEPLOYMENT" -n "$NAMESPACE" --timeout=300s \
    || die "Rollout of '$VSS_AGENT_DEPLOYMENT' did not complete within 5 minutes."
ok "vss-agent rollout complete."

# verify log line
sleep 5
NEW_POD=$(oc get pods -n "$NAMESPACE" \
    -l "$(oc get deployment "$VSS_AGENT_DEPLOYMENT" -n "$NAMESPACE" \
          -o jsonpath='{range .spec.selector.matchLabels}{@key}={@value}{","}{end}' | sed 's/,$//')" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -n "$NEW_POD" ]]; then
    if oc logs "$NEW_POD" -n "$NAMESPACE" 2>/dev/null | grep -q "Already installed at ${CODEC_MOUNT_PATH}"; then
        ok "Verified: [proprietary-codecs] Already installed at ${CODEC_MOUNT_PATH}"
    else
        warn "Expected log line not seen yet — pod may still be starting."
        warn "Check: oc logs $NEW_POD -n $NAMESPACE | grep proprietary-codecs"
    fi
else
    warn "Could not determine new vss-agent pod name — verify manually."
fi

# ══════════════════════════════════════════════════════════════════════════════
# PART 2 — vss-vios-streamprocessing fix
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "------------------------------------------------------------"
echo "  Part 2/2 — vss-vios-streamprocessing offline apt fix"
echo "------------------------------------------------------------"

# -- 2a: create APT PVC -------------------------------------------------------
echo ""
log "Step 1/5 — Creating PVC '$APT_PVC_NAME'..."

if oc get pvc "$APT_PVC_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    warn "PVC '$APT_PVC_NAME' already exists — skipping."
else
    oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${APT_PVC_NAME}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${APT_STORAGE_CLASS}
  resources:
    requests:
      storage: ${APT_PVC_SIZE}
EOF
    log "Waiting for PVC to become Bound..."
    for i in {1..30}; do
        STATUS=$(oc get pvc "$APT_PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        [[ "$STATUS" == "Bound" ]] && { ok "PVC is Bound."; break; }
        [[ $i -eq 30 ]] && die "PVC '$APT_PVC_NAME' did not become Bound within 60s."
        sleep 2
    done
fi

# -- 2b: create APT loader pod ------------------------------------------------
echo ""
log "Step 2/5 — Creating APT loader pod '$APT_LOADER_POD'..."

if oc get pod "$APT_LOADER_POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    warn "Loader pod '$APT_LOADER_POD' already exists — deleting first..."
    oc delete pod "$APT_LOADER_POD" -n "$NAMESPACE" --wait=true
fi

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${APT_LOADER_POD}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  containers:
    - name: loader
      image: ${APT_SERVER_IMAGE}
      command: ["sleep", "3600"]
      volumeMounts:
        - name: apt-repo
          mountPath: /repo
  volumes:
    - name: apt-repo
      persistentVolumeClaim:
        claimName: ${APT_PVC_NAME}
EOF

log "Waiting for APT loader pod to be Running..."
for i in {1..60}; do
    STATUS=$(oc get pod "$APT_LOADER_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    [[ "$STATUS" == "Running" ]] && { ok "APT loader pod is Running."; break; }
    [[ "$STATUS" == "Failed"  ]] && { oc logs "$APT_LOADER_POD" -n "$NAMESPACE" || true; die "APT loader pod failed."; }
    [[ $i -eq 60 ]] && die "APT loader pod did not reach Running within 120s."
    sleep 2
done

log "Step 3/5 — Streaming APT bundle into PVC..."
cat "$APT_BUNDLE" | \
    oc exec -i "$APT_LOADER_POD" -n "$NAMESPACE" -- \
    python3 -c '
import sys, tarfile, io
data = sys.stdin.buffer.read()
with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
    tar.extractall("/repo/packages")
print("APT bundle extracted.")
' || die "Failed to stream APT bundle into pod."

PACKAGES_OK=$(oc exec "$APT_LOADER_POD" -n "$NAMESPACE" -- \
    /bin/sh -c "test -f /repo/packages/Packages && echo yes || echo no")
[[ "$PACKAGES_OK" == "yes" ]] || die "Packages index not found in APT PVC."
ok "APT bundle extracted and Packages index confirmed."

# -- 2c: deploy apt server ----------------------------------------------------
echo ""
log "Step 4/5 — Deploying apt server '$APT_SERVER_DEPLOYMENT' and Service '$APT_SERVICE_NAME'..."

if oc get deployment "$APT_SERVER_DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    warn "Deployment '$APT_SERVER_DEPLOYMENT' already exists — skipping."
else
    oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APT_SERVER_DEPLOYMENT}
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APT_SERVER_DEPLOYMENT}
  template:
    metadata:
      labels:
        app: ${APT_SERVER_DEPLOYMENT}
    spec:
      containers:
        - name: apt-server
          image: ${APT_SERVER_IMAGE}
          command: ["python3", "-m", "http.server", "8080", "--directory", "/repo/packages"]
          ports:
            - containerPort: 8080
              protocol: TCP
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            runAsNonRoot: true
          volumeMounts:
            - name: apt-repo
              mountPath: /repo
      volumes:
        - name: apt-repo
          persistentVolumeClaim:
            claimName: ${APT_PVC_NAME}
EOF
    ok "Deployment '$APT_SERVER_DEPLOYMENT' created."
fi

if oc get service "$APT_SERVICE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    warn "Service '$APT_SERVICE_NAME' already exists — skipping."
else
    oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APT_SERVICE_NAME}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${APT_SERVER_DEPLOYMENT}
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
EOF
    ok "Service '$APT_SERVICE_NAME' created."
fi

log "Waiting for apt server to be Ready..."
for i in {1..60}; do
    READY=$(oc get deployment "$APT_SERVER_DEPLOYMENT" -n "$NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    [[ "${READY}" == "1" ]] && { ok "Apt server is Ready."; break; }
    [[ $i -eq 60 ]] && die "Apt server did not become Ready within 120s."
    sleep 2
done

# -- 2d: patch streamprocessing StatefulSet -----------------------------------
echo ""
log "Step 5/5 — Patching StatefulSet '$STS_NAME'..."

CURRENT_ARGS=$(oc get statefulset "$STS_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].args[0]}' 2>/dev/null || true)

if echo "$CURRENT_ARGS" | grep -q "${APT_SERVICE_NAME}"; then
    warn "StatefulSet '$STS_NAME' already patched — skipping."
else
    NEW_ARGS='echo "deb [trusted=yes] http://'"${APT_SERVICE_NAME}"':8080 ./" > /etc/apt/sources.list.d/offline.list
rm -f /etc/apt/sources.list.d/ubuntu.sources
if [ "$VST_INSTALL_ADDITIONAL_PACKAGES" = "true" ]; then
  /home/vst/vst_release/tools/user_additional_install.sh
fi
exec /home/vst/vst_release/launch_vst'

    NEW_ARGS_JSON=$(printf '%s' "$NEW_ARGS" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

    oc patch statefulset "$STS_NAME" -n "$NAMESPACE" --type=json -p="[
      {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args/0\",\"value\":${NEW_ARGS_JSON}}
    ]" || die "Failed to patch StatefulSet '$STS_NAME'."
    ok "StatefulSet patched."

    log "Waiting for rollout of '$STS_NAME'..."
    oc rollout status statefulset/"$STS_NAME" -n "$NAMESPACE" --timeout=300s \
        || die "Rollout of '$STS_NAME' did not complete within 5 minutes."
    ok "vss-vios-streamprocessing rollout complete."
fi

# ── cleanup loader pods ───────────────────────────────────────────────────────
echo ""
read -rp "Delete loader pods '$CODEC_LOADER_POD' and '$APT_LOADER_POD'? (yes/no) [yes]: " DEL_LOADERS
DEL_LOADERS="${DEL_LOADERS:-yes}"
if [[ "$DEL_LOADERS" == "yes" ]]; then
    oc delete pod "$CODEC_LOADER_POD" "$APT_LOADER_POD" -n "$NAMESPACE" --wait=false 2>/dev/null || true
    ok "Loader pods deletion triggered."
fi

# ── final summary ─────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Deployment complete."
echo ""
echo "  Verify vss-agent:"
echo "    oc logs -f \$(oc get pod -n ${NAMESPACE} -l app=${VSS_AGENT_DEPLOYMENT} \\"
echo "       -o jsonpath='{.items[0].metadata.name}') -n ${NAMESPACE}"
echo "  Expected: [proprietary-codecs] Already installed at ${CODEC_MOUNT_PATH}"
echo ""
echo "  Verify streamprocessing:"
echo "    oc logs -f \$(oc get pod -n ${NAMESPACE} \\"
echo "       -l app.kubernetes.io/name=${STS_NAME} \\"
echo "       -o jsonpath='{.items[0].metadata.name}') -n ${NAMESPACE}"
echo "  Expected: GStreamer plugins loading without errors."
echo ""
echo "  ── Permanent resources (do NOT delete) ──────────────────"
echo "    PVC        : ${CODEC_PVC_NAME}  (codec bundle)"
echo "    PVC        : ${APT_PVC_NAME}  (apt packages)"
echo "    Deployment : ${APT_SERVER_DEPLOYMENT}  (apt http server)"
echo "    Service    : ${APT_SERVICE_NAME}  (apt server ClusterIP)"
echo ""
echo "  ── Temporary resources (safe to delete) ─────────────────"
echo "    oc delete pod ${CODEC_LOADER_POD} ${APT_LOADER_POD} -n ${NAMESPACE}"
echo "============================================================"
echo ""
