#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

show_help() {
  cat <<EOF
Usage: $0 <namespace> [options]

Arguments:
  namespace     Project namespace

Options (mutually exclusive):
  --cpu-only           Only evaluate CPU
  --mem-only           Only evaluate Memory
  --force              Include all running pods, ignoring 24h age filter
  --insecure-tls       Skip TLS verification for Prometheus connection

Outputs:
  - Excel report with Current vs New recommendations
  - Console table summary

  
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  show_help; exit 0
fi

NS=${1:-}
if [[ -z "$NS" ]]; then
  show_help; exit 1
fi

DURATION=15d
KEEP_TMP=${KEEP_TMP:-false}
INSECURE_PROM=${INSECURE_PROM:-false}



# --- Tuning knobs (do not affect output format; only recommendation safety) ---
THR_P95_BAD=${THR_P95_BAD:-0.10}
THR_MAX_BAD=${THR_MAX_BAD:-0.20}

# --- Sidecar floors (kube-rbac-proxy) ---
RBAC_CPU_FLOOR=${RBAC_CPU_FLOOR:-0.05}      # cores (50m)
RBAC_CPU_LIM_MIN=${RBAC_CPU_LIM_MIN:-0.20}  # cores (200m)
RBAC_MEM_FLOOR=${RBAC_MEM_FLOOR:-0.064}     # Gi (64Mi)
RBAC_MEM_LIM_MIN=${RBAC_MEM_LIM_MIN:-0.128} # Gi (128Mi)
RBAC_CPU_REQ_HEADROOM=${RBAC_CPU_REQ_HEADROOM:-1.20}
RBAC_CPU_LIM_MULT=${RBAC_CPU_LIM_MULT:-2.0}
RBAC_MEM_REQ_HEADROOM=${RBAC_MEM_REQ_HEADROOM:-1.10}
RBAC_MEM_LIM_MULT=${RBAC_MEM_LIM_MULT:-1.50}
RBAC_MEM_OOM_MULT=${RBAC_MEM_OOM_MULT:-2.0}

CPU_REQ_HEADROOM=${CPU_REQ_HEADROOM:-1.30}
CPU_LIM_HEADROOM=${CPU_LIM_HEADROOM:-1.25}
CPU_LIM_REQ_MULT=${CPU_LIM_REQ_MULT:-1.50}

MEM_REQ_HEADROOM=${MEM_REQ_HEADROOM:-1.10}
MEM_LIM_HEADROOM=${MEM_LIM_HEADROOM:-1.30}
MEM_LIM_REQ_MULT=${MEM_LIM_REQ_MULT:-1.50}
MEM_OOM_MULT=${MEM_OOM_MULT:-2.0}
MEM_PRESSURE_P95=${MEM_PRESSURE_P95:-0.85}


# --- Resource selection ---
RESOURCES="cpu,memory"
EXCLUSIVE_FLAG=""
FORCE=0

for arg in "$@"; do
  case $arg in
    --cpu-only)
      [[ -n "$EXCLUSIVE_FLAG" ]] && { echo "ERROR: $EXCLUSIVE_FLAG and --cpu-only cannot be combined"; exit 1; }
      EXCLUSIVE_FLAG="--cpu-only"; RESOURCES="cpu"
      ;;
    --mem-only)
      [[ -n "$EXCLUSIVE_FLAG" ]] && { echo "ERROR: $EXCLUSIVE_FLAG and --mem-only cannot be combined"; exit 1; }
      EXCLUSIVE_FLAG="--mem-only"; RESOURCES="memory"
      ;;
    -f|--force)
      FORCE=1
      ;;
    --insecure-tls|--insecure-skip-tls-verify) INSECURE_PROM="true" ;;
  esac
done

echo "Namespace: $NS"
echo "Resources selected: $RESOURCES"

echo
echo "NOTE:"
if [[ ${FORCE:-0} -eq 1 ]]; then
  echo "  • [FORCE MODE ENABLED] Including all running pods, ignoring 24h age filter."
else
  echo "  • Only recommending pods older than 24 hours (skip newer ones)."
  echo "    Use -f or --force to include all running pods."
fi
echo "  • Recommendations are more accurate if pods are older and scheduled backups have already completed."
echo


# --- Python venv setup ---
setup_venv() {
  REQUIRED_PYTHON_MIN="3.9"
  PKGS=(numpy pandas openpyxl xlsxwriter tabulate)

  # Launcher per platform
  if [[ "${OS:-}" == "Windows_NT" ]]; then
    PY_CMD="python"
    VENV_PY=".venv/Scripts/python.exe"
  else
    PY_CMD="python3"
    VENV_PY=".venv/bin/python3"
  fi

  # Ensure python exists
  if ! command -v "$PY_CMD" >/dev/null 2>&1; then
    echo "[ERROR] $PY_CMD not found. Please install Python $REQUIRED_PYTHON_MIN+."
    exit 1
  fi

  # Version check using Python
  if ! "$PY_CMD" - <<PY >/dev/null 2>&1
import sys
req = tuple(map(int, "$REQUIRED_PYTHON_MIN".split(".")))
sys.exit(0 if sys.version_info >= req else 1)
PY
  then
    DETECTED_VER="$("$PY_CMD" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
    echo "[ERROR] Python >= $REQUIRED_PYTHON_MIN required (found $DETECTED_VER)."
    exit 1
  fi

  # Use venv only if 'venv' module is available; else fall back
  USING_VENV=false
  if "$PY_CMD" - <<'PY' >/dev/null 2>&1
import importlib.util
import sys
sys.exit(0 if importlib.util.find_spec("venv") else 1)
PY
  then
    if [[ ! -x "$VENV_PY" ]]; then
      echo "[INFO] Creating virtual environment in .venv/ ..."
      if ! "$PY_CMD" -m venv .venv >/dev/null 2>&1; then
        echo "[WARN] Failed to create venv; falling back to system Python."
      fi
    fi
    if [[ -x "$VENV_PY" ]]; then
      PYTHON_EXEC="$VENV_PY"
      USING_VENV=true
      echo "[INFO] Using virtual environment: $PYTHON_EXEC"
    fi
  else
    echo "[WARN] 'venv' module not available; using system Python."
  fi

  # Fallback to system Python if no venv
  if [[ "$USING_VENV" != true ]]; then
    PYTHON_EXEC="$PY_CMD"
    echo "[INFO] Using system Python: $PYTHON_EXEC"
  fi

  # Dependency install (use --user only when not in venv)
  if [[ "$USING_VENV" == true ]]; then
    "$PYTHON_EXEC" -m pip install -q --upgrade pip
    "$PYTHON_EXEC" -m pip install -q --no-cache-dir "${PKGS[@]}"
  else
    "$PYTHON_EXEC" -m pip install -q --upgrade --user pip
    "$PYTHON_EXEC" -m pip install -q --user --no-cache-dir "${PKGS[@]}"
  fi
  export PYTHON_EXEC
  export USING_VENV
}
setup_venv

# --- Prometheus port-forward---
PROM_NS="openshift-monitoring"
PROM_POD="prometheus-k8s-0"
PF_LOG="/tmp/pf_prome.log"
TMPDIR="/tmp/podres_$(date +%s)"
mkdir -p "$TMPDIR"

# echo "[INFO] Starting port-forward to Prometheus pod $PROM_POD in namespace $PROM_NS..."
# oc -n "$PROM_NS" port-forward "$PROM_POD" 9090:9090 >"$PF_LOG" 2>&1 &
# PF_PID=$!
# trap "kill $PF_PID >/dev/null 2>&1 || true; wait $PF_PID 2>/dev/null || true;" EXIT

# for i in {1..30}; do
#   if curl -sS http://localhost:9090/-/ready >/dev/null 2>&1; then
#     echo "Port-forward established (PID=$PF_PID)"
#     break
#   fi
#   sleep 1
# done



cleanup() {
  if [[ "${PF_PID:-}" != "" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_TMP" != "true" ]]; then
    rm -rf "$TMPDIR" >/dev/null 2>&1 || true
  else
    echo "[INFO] Keeping tmpdir: $TMPDIR"
  fi
}
trap cleanup EXIT

# --- Prometheus connection ---
PROM_URL=""
PROM_TOKEN=""

# Prefer OpenShift monitoring route if present
if oc -n openshift-monitoring get route prometheus-k8s >/dev/null 2>&1; then
  host="$(oc -n openshift-monitoring get route prometheus-k8s -o jsonpath='{.spec.host}')"
  PROM_URL="https://${host}"
  PROM_TOKEN="$(oc whoami -t)"
  echo "[CONN] Using OpenShift Prometheus Route: $PROM_URL"
else
  echo "[CONN] Route not found. Using port-forward to prometheus-k8s-0 (openshift-monitoring)"
  # If prometheus-k8s-0 doesn't exist, user likely lacks access. Fail loudly.
  if ! oc -n openshift-monitoring get pod prometheus-k8s-0 >/dev/null 2>&1; then
    echo "[ERR] Cannot find prometheus-k8s-0 in openshift-monitoring and route not available."
    echo "      Provide access to openshift-monitoring or create the route."
    exit 1
  fi
  # find free local port
  for p in 9090 19090 29090 39090; do
    if ! nc -z 127.0.0.1 "$p" >/dev/null 2>&1; then
      LPORT="$p"; break
    fi
  done
  : "${LPORT:=9090}"
  oc -n openshift-monitoring port-forward pod/prometheus-k8s-0 "${LPORT}:9090" >/dev/null 2>&1 &
  PF_PID=$!
  PROM_URL="http://127.0.0.1:${LPORT}"
  PROM_TOKEN="$(oc whoami -t)"
  echo "[CONN] Port-forward pid=$PF_PID URL=$PROM_URL"
fi

# --- Prometheus queries ---
# query_to_tsv() {
#   local q="$1"; local out="$2"
  
#   curl -sG --compressed --max-time 120 "http://localhost:9090/api/v1/query" \
#     --data-urlencode "query=$q" \
#   | jq -r '.data.result[]? | [.metric.pod, .metric.container, .value[1]] | @tsv' > "$out" || true
# }

query_to_tsv() {
  local q="$1"
  local out="$2"
  local curl_log="${out}.curl.log"
  local json_out="${out}.json"
  local rc=0

  if [[ "$PROM_URL" == https://* && "${INSECURE_PROM}" == "true" ]]; then
    echo "[WARN] INSECURE_PROM=true → TLS certificate verification is DISABLED for Prometheus"
    curl -sS -k \
      --connect-timeout 10 \
      --max-time 60 \
      -H "Authorization: Bearer ${PROM_TOKEN}" \
      --get --data-urlencode "query=${q}" \
      "${PROM_URL}/api/v1/query" \
      -o "$json_out" 2> "$curl_log" || rc=$?
  else
    curl -sS \
      --connect-timeout 10 \
      --max-time 60 \
      -H "Authorization: Bearer ${PROM_TOKEN}" \
      --get --data-urlencode "query=${q}" \
      "${PROM_URL}/api/v1/query" \
      -o "$json_out" 2> "$curl_log" || rc=$?
  fi

  if [[ $rc -ne 0 ]]; then
    echo "[ERROR] curl failed (rc=$rc) for query:" >&2
    echo "        $q" >&2
    echo "[ERROR] curl log ($curl_log):" >&2
    sed -n '1,200p' "$curl_log" >&2 || true
    return $rc
  fi

  if ! jq -e '.status=="success"' "$json_out" >/dev/null 2>&1; then
    echo "[WARN] Prometheus query did not succeed" >&2
    echo "[WARN] Response:" >&2
    sed -n '1,200p' "$json_out" >&2 || true
    return 1
  fi

  # Convert to TSV: namespace, pod, container, value
  jq -r '
    .data.result[]
    | .metric as $m
    | [
        ($m.namespace // $m.kubernetes_namespace // ""),
        ($m.pod // $m.pod_name // ""),
        ($m.container // $m.container_name // ""),
        (.value[1] // "0")
      ]
    | @tsv
  ' "$json_out" > "$out"
}

CPU_F="$TMPDIR/cpu.tsv"; CPU_P95_F="$TMPDIR/cpu_p95.tsv"; MEM_F="$TMPDIR/mem.tsv"; MEM_P95_F="$TMPDIR/mem_p95.tsv"; FS_F="$TMPDIR/fs.tsv"; THR_MAX_F="$TMPDIR/cpu_throttle_max.tsv"; THR_P95_F="$TMPDIR/cpu_throttle_p95.tsv"; OOM_F="$TMPDIR/oom.tsv"; RESTART_F="$TMPDIR/restarts.tsv"

echo "[INFO] Querying Prometheus..."
if [[ "$RESOURCES" == *cpu* ]]; then
  # CPU max usage (kept for CPU_Use column)
  CPU_USAGE_Q='max by (pod,container) (
    max_over_time(
      rate(container_cpu_usage_seconds_total{namespace="'"$NS"'",container!="",container!="POD",image!=""}[5m])
    ['"$DURATION"':5m])
  )'
  query_to_tsv "$CPU_USAGE_Q" "$CPU_F"

  # CPU P95 (used for request sizing logic)
  CPU_P95_Q='max by (pod,container) (
    quantile_over_time(
      0.95,
      rate(container_cpu_usage_seconds_total{namespace="'"$NS"'",container!="",container!="POD",image!=""}[5m])
    ['"$DURATION"':5m])
  )'
  query_to_tsv "$CPU_P95_Q" "$CPU_P95_F"

  # CPU throttling ratio (MAX) = burst/startup-ish starvation indicator
  CPU_THR_MAX_Q='max by (pod,container) (
    max_over_time(
      (
        rate(container_cpu_cfs_throttled_periods_total{namespace="'"$NS"'",container!="",container!="POD",image!=""}[5m])
        /
        clamp_min(rate(container_cpu_cfs_periods_total{namespace="'"$NS"'",container!="",container!="POD",image!=""}[5m]), 1)
      )
    ['"$DURATION"':5m])
  )'
  query_to_tsv "$CPU_THR_MAX_Q" "$THR_MAX_F"

  # CPU throttling ratio (P95) = steady-state starvation indicator
  CPU_THR_P95_Q='max by (pod,container) (
    quantile_over_time(
      0.95,
      max by (pod, container)(
        rate(container_cpu_cfs_throttled_periods_total{namespace="'"$NS"'",container!="",container!="POD",image!=""}[5m])
        /
        clamp_min(rate(container_cpu_cfs_periods_total{namespace="'"$NS"'",container!="",container!="POD",image!=""}[5m]), 1)
      )
    ['"$DURATION"':5m])
  )'
  query_to_tsv "$CPU_THR_P95_Q" "$THR_P95_F"
fi

if [[ "$RESOURCES" == *memory* ]]; then
  # Memory max working set (kept for Mem_Use column)
  MEM_USAGE_Q='max by (pod,container) (
    max_over_time(
      container_memory_working_set_bytes{namespace="'"$NS"'",container!="",container!="POD",image!=""}
    ['"$DURATION"':5m])
  )'
  query_to_tsv "$MEM_USAGE_Q" "$MEM_F"

  # Memory P95 working set (used for request sizing logic)
  MEM_P95_Q='max by (pod,container) (
    quantile_over_time(
      0.95,
      container_memory_working_set_bytes{namespace="'"$NS"'",container!="",container!="POD",image!=""}
    ['"$DURATION"':5m])
  )'
  query_to_tsv "$MEM_P95_Q" "$MEM_P95_F"

  # OOM indicator in-range (more reliable than last_terminated_reason alone)
  # OOM=1 only if:
  #   - last terminated reason shows OOMKilled at least once in the window AND
  #   - there was at least one restart in the window
  OOM_Q='max by (pod,container) (
    (
      max_over_time(
        kube_pod_container_status_last_terminated_reason{namespace="'"$NS"'",reason="OOMKilled"}['"$DURATION"':5m]
      )
    )
    *
    (
      increase(kube_pod_container_status_restarts_total{namespace="'"$NS"'"}['"$DURATION"']) > 0
    )
  )'
  query_to_tsv "$OOM_Q" "$OOM_F"

  # Restarts count over range
  RESTART_Q='sum by (pod,container) (
    increase(kube_pod_container_status_restarts_total{namespace="'"$NS"'"}['"$DURATION"'])
  )'
  query_to_tsv "$RESTART_Q" "$RESTART_F"
fi


if [[ "$RESOURCES" == *ephemeral* ]]; then
  FS_USAGE_Q='max by (pod,container) (max_over_time(container_fs_usage_bytes{namespace="'"$NS"'",container!="",container!="POD"}['"$DURATION"':]))'
  query_to_tsv "$FS_USAGE_Q" "$FS_F"
fi

# --- Get pod specs for running pods (requests & limits) ---
PODS_JSON="$TMPDIR/pods.json"
oc -n "$NS" get pods -o json > "$PODS_JSON"

# --- Outputs ---
XLSX="/tmp/usage_report_${NS}_${DURATION}.xlsx"
PATCH_FILE="/tmp/pods_to_patch_${NS}.json"

# --- Python analysis ---
RESOURCES="$RESOURCES" NS="$NS" CPU_F="$CPU_F" CPU_P95_F="$CPU_P95_F" MEM_F="$MEM_F" MEM_P95_F="$MEM_P95_F" FS_F="$FS_F" THR_MAX_F="$THR_MAX_F" THR_P95_F="$THR_P95_F" OOM_F="$OOM_F" RESTART_F="$RESTART_F" PODS_JSON="$PODS_JSON" XLSX="$XLSX" PATCH_FILE="$PATCH_FILE" FORCE="$FORCE" THR_P95_BAD="$THR_P95_BAD" THR_MAX_BAD="$THR_MAX_BAD" CPU_REQ_HEADROOM="$CPU_REQ_HEADROOM" CPU_LIM_HEADROOM="$CPU_LIM_HEADROOM" MEM_REQ_HEADROOM="$MEM_REQ_HEADROOM" MEM_LIM_HEADROOM="$MEM_LIM_HEADROOM" MEM_LIM_REQ_MULT="$MEM_LIM_REQ_MULT" MEM_PRESSURE_P95="$MEM_PRESSURE_P95" RBAC_CPU_FLOOR="$RBAC_CPU_FLOOR" RBAC_CPU_LIM_MIN="$RBAC_CPU_LIM_MIN" RBAC_MEM_FLOOR="$RBAC_MEM_FLOOR" RBAC_MEM_LIM_MIN="$RBAC_MEM_LIM_MIN" RBAC_CPU_REQ_HEADROOM="$RBAC_CPU_REQ_HEADROOM" RBAC_CPU_LIM_MULT="$RBAC_CPU_LIM_MULT" RBAC_MEM_REQ_HEADROOM="$RBAC_MEM_REQ_HEADROOM" RBAC_MEM_LIM_MULT="$RBAC_MEM_LIM_MULT" RBAC_MEM_OOM_MULT="$RBAC_MEM_OOM_MULT" CPU_LIM_REQ_MULT="$CPU_LIM_REQ_MULT" MEM_OOM_MULT="$MEM_OOM_MULT" "$PYTHON_EXEC" - <<'PYEOF'
import sys, pandas as pd, numpy as np, json, os, re, math, datetime
from tabulate import tabulate
if sys.version_info < (3,7):
    print(f"[WARN] Running on Python {sys.version.split()[0]} — using legacy pandas path")
else:
    print(f"[INFO] Running on Python {sys.version.split()[0]} — using latest pandas path")


# ----------------- Config from env -----------------
selected = set(os.environ.get("RESOURCES", "cpu,memory,ephemeral").split(","))
XLSX       = os.environ.get("XLSX")
PATCH_FILE = os.environ.get("PATCH_FILE")
CPU_F      = os.environ.get("CPU_F")
CPU_P95_F  = os.environ.get("CPU_P95_F")
THR_MAX_F  = os.environ.get("THR_MAX_F")
THR_P95_F  = os.environ.get("THR_P95_F")

MEM_F      = os.environ.get("MEM_F")
MEM_P95_F  = os.environ.get("MEM_P95_F")
OOM_F      = os.environ.get("OOM_F")
RESTART_F  = os.environ.get("RESTART_F")

FS_F       = os.environ.get("FS_F")
PODS_JSON  = os.environ.get("PODS_JSON")
NS_NAME    = os.environ.get("NS")
FORCE      = os.environ.get("FORCE", "0").lower() in ("1","true","yes","y")

# Tuning knobs (passed from shell; defaults match common SRE practice)
def env_float(name, default):
    try:
        return float(os.environ.get(name, default))
    except Exception:
        return float(default)

# ---- Throttling & pressure thresholds ----
THR_P95_BAD        = env_float("THR_P95_BAD", 0.10)
THR_MAX_BAD        = env_float("THR_MAX_BAD", 0.20)

MEM_PRESSURE_P95  = env_float("MEM_PRESSURE_P95", 0.85)
MEM_OOM_MULT      = env_float("MEM_OOM_MULT", 2.0)

# ---- Application container policy ----

# CPU
APP_CPU_FLOOR          = env_float("APP_CPU_FLOOR", 0.05)     # 50m
APP_CPU_LIM_MIN        = env_float("APP_CPU_LIM_MIN", 0.10)   # 100m
APP_CPU_REQ_HEADROOM   = env_float("APP_CPU_REQ_HEADROOM", 1.20)
APP_CPU_LIM_REQ_MULT   = env_float("APP_CPU_LIM_REQ_MULT", 1.50)
APP_CPU_BURST_MULT     = env_float("APP_CPU_BURST_MULT", 2.00)

# Memory
APP_MEM_FLOOR          = env_float("APP_MEM_FLOOR", 0.064)    # 64Mi
APP_MEM_LIM_MIN        = env_float("APP_MEM_LIM_MIN", 0.128)  # 128Mi
APP_MEM_REQ_HEADROOM   = env_float("APP_MEM_REQ_HEADROOM", 1.10)
APP_MEM_LIM_REQ_MULT   = env_float("APP_MEM_LIM_REQ_MULT", 1.50)
APP_MEM_LIM_HEADROOM   = env_float("APP_MEM_LIM_HEADROOM", 1.30)

# ---- Proxy / sidecar policy (latency-critical) ----

# CPU
PROXY_CPU_FLOOR        = env_float("PROXY_CPU_FLOOR", 0.10)    # 100m
PROXY_CPU_LIM_MIN      = env_float("PROXY_CPU_LIM_MIN", 0.20)  # 200m
PROXY_CPU_REQ_HEADROOM = env_float("PROXY_CPU_REQ_HEADROOM", 1.10)
PROXY_CPU_LIM_REQ_MULT = env_float("PROXY_CPU_LIM_REQ_MULT", 2.00)
PROXY_CPU_BURST_MULT   = env_float("PROXY_CPU_BURST_MULT", 2.50)
PROXY_THR_SEVERE       = env_float("PROXY_THR_SEVERE", 0.20)

# Memory
PROXY_MEM_FLOOR        = env_float("PROXY_MEM_FLOOR", 0.128)   # 128Mi
PROXY_MEM_LIM_MIN      = env_float("PROXY_MEM_LIM_MIN", 0.256) # 256Mi
PROXY_MEM_REQ_HEADROOM = env_float("PROXY_MEM_REQ_HEADROOM", 1.10)
PROXY_MEM_LIM_REQ_MULT = env_float("PROXY_MEM_LIM_REQ_MULT", 1.50)
PROXY_MEM_LIM_HEADROOM = env_float("PROXY_MEM_LIM_HEADROOM", 1.30)
PROXY_MEM_OOM_MULT     = env_float("PROXY_MEM_OOM_MULT", 2.0)



now_utc = datetime.datetime.now(datetime.timezone.utc)
min_age = now_utc - datetime.timedelta(days=15)   # oldest allowed (≤ 15d old)
max_age = now_utc - datetime.timedelta(hours=24)  # newest allowed (≥ 24h old)

# ----------------- Helpers -----------------
def parse_ts(ts: str):
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None

def should_check(kind):
    k = kind.lower()
    if k.startswith("cpu"): return "cpu" in selected
    if k.startswith("mem"): return "memory" in selected
    if k.startswith("eph"): return "ephemeral" in selected
    return True

def is_na(v):
    if v is None: return True
    if isinstance(v, float): return math.isnan(v)
    if isinstance(v, str): return v.strip().upper() in ("N/A","NA","","NONE","NULL")
    return False

def to_float_or_none(v):
    if is_na(v): return None
    try: return float(v)
    except Exception: return None

def nz(v, default=0.0):
    if v is None: return default
    if isinstance(v, str):
        if v.strip().upper() in ("N/A","NA","","NONE","NULL"): return default
        try: return float(v)
        except: return default
    if isinstance(v, (int,float)):
        if isinstance(v,float) and math.isnan(v): return default
        return v
    return default

def ceil_cpu(val): return None if is_na(val) else (math.ceil(float(val)*1000)/1000)
def ceil_mem(val): return None if is_na(val) else (math.ceil(float(val)*100)/100)

def fmt_cpu(val):  return f"{math.ceil(float(val)*1000)/1000:.3f}"
def fmt_mem(val):  return f"{math.ceil(float(val)*100)/100:.2f}"

def fmt_cpu_or_na(val):
    fv = to_float_or_none(val)
    return "N/A" if fv is None else fmt_cpu(fv)

def fmt_mem_or_na(val):
    fv = to_float_or_none(val)
    return "N/A" if fv is None else fmt_mem(fv)

def fmt_cpu_k8s(val):
    v = nz(val)
    return f"{int(math.ceil(v*1000))}m" if v > 0 else None

def fmt_mem_k8s_mi(val):
    v = nz(val)
    return f"{int(math.ceil(v*1024))}Mi" if v > 0 else None

def load(path, col):
    if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
        return pd.DataFrame(columns=["Pod","Container",col])
    return pd.read_csv(path, sep="\t", names=["Pod","Container",col])

def parse_cpu(v):
    if v in (None,"",0,"0"): return None
    s = str(v)
    if s.endswith("m"):
        try:
            f = float(s[:-1]) / 1000.0
            return None if f == 0.0 else f
        except: return None
    try:
        f = float(s); return None if f == 0.0 else f
    except: return None

def parse_mem(v):
    if v in (None,"",0,"0"): return None
    s = str(v).strip()
    try:
        if s.endswith("Ki"): f = float(s[:-2]) / 1024.0 / 1024.0; return None if f == 0.0 else f
        if s.endswith("Mi"): f = float(s[:-2]) / 1024.0;         return None if f == 0.0 else f
        if s.endswith("Gi"): f = float(s[:-2]);                   return None if f == 0.0 else f
        if s.endswith("Ti"): f = float(s[:-2]) * 1024.0;          return None if f == 0.0 else f
        if re.match(r"^[0-9]+(\.[0-9]+)?$", s):
            f = float(s) / (1024.0**3);                           return None if f == 0.0 else f
        f = float(s);                                             return None if f == 0.0 else f
    except: return None

# ----------------- Load current requests/limits from running pods -----------------
with open(PODS_JSON) as f:
    pods = json.load(f)

# --- Workload detection (group replicas), incl. Strimzi ---
def workload_of(p):
    """Return (Kind, Name) for top-level controller of this pod."""
    refs = (p.get("metadata", {}) or {}).get("ownerReferences") or []
    if refs:
        ref = refs[0]
        kind = ref.get("kind")
        name = ref.get("name")

        if kind == "ReplicaSet" and name:
            base = name.rsplit("-", 1)[0]  # Deployment -> ReplicaSet -> Pod
            return ("Deployment", base)
        if kind == "ReplicationController" and name:
            base = name.rsplit("-", 1)[0]  # OpenShift DC
            return ("DeploymentConfig", base)
        if kind in ("StatefulSet","DaemonSet","Job","CronJob") and name:
            return (kind, name)
        if kind == "StrimziPodSet" and name:
            base = re.sub(r"-\d+$", "", name)  # strip ordinal
            return ("Strimzi", base)
        if kind in ("Kafka","KafkaConnect","KafkaMirrorMaker","KafkaMirrorMaker2","KafkaBridge") and name:
            return ("Strimzi", name)

    return ("Pod", (p.get("metadata", {}) or {}).get("name"))

# Map Pod -> "Kind/Name"
pod_to_wl = {}
for p in pods.get("items", []):
    name = (p.get("metadata", {}) or {}).get("name")
    if not name: continue
    kind, wname = workload_of(p)
    wl_key = f"{kind}/{wname}" if wname else f"{kind}/{name}"
    pod_to_wl[name] = wl_key

def effective_start(p):
    # 1) Pod Ready lastTransitionTime
    ready_ts = None
    for c in (p.get("status", {}) or {}).get("conditions", []) or []:
        if c.get("type") == "Ready" and c.get("lastTransitionTime"):
            t = parse_ts(c["lastTransitionTime"])
            if t: ready_ts = t
    if ready_ts: return ready_ts
    # 2) latest container startedAt / finishedAt
    best = None
    for cs in (p.get("status", {}) or {}).get("containerStatuses", []) or []:
        ts = ((cs.get("state", {}) or {}).get("running", {}) or {}).get("startedAt")
        if not ts:
            ts = ((cs.get("lastState", {}) or {}).get("terminated", {}) or {}).get("finishedAt")
        if ts:
            t = parse_ts(ts)
            if t and (best is None or t > best): best = t
    if best: return best
    # 3) fallback
    ts = (p.get("metadata", {}) or {}).get("creationTimestamp")
    return parse_ts(ts) if ts else None

# ---- Age filter with Java special-case ----
exclude_java_pods_lits = [
    "applicationsvc","backup-location-deployment","backuppolicy-deployment",
    "backup-service","job-manager"
]
allowed_pods = set()
for p in pods.get("items", []):
    if p.get("status", {}).get("phase") != "Running": continue
    name = p.get("metadata", {}).get("name")
    if not name: continue
    estart = effective_start(p)
    if not estart: continue
    is_java_pod = any(excl in name for excl in exclude_java_pods_lits)

    if FORCE:
        # Force removes only the 24h minimum
        if is_java_pod:
            if estart >= min_age:  # <= 15d old
                allowed_pods.add(name)
        else:
            allowed_pods.add(name)  # any age OK
    else:
        if is_java_pod:
            if min_age <= estart <= max_age:  # 24h ≤ age ≤ 15d
                allowed_pods.add(name)
        else:
            if estart <= max_age:            # ≥ 24h old (no 15d cap)
                allowed_pods.add(name)

# ----------------- Load usage (max_over_time results already pre-aggregated) -----------------
cpu = load(CPU_F, "CPU_Use") if "cpu" in selected else pd.DataFrame(columns=["Pod","Container","CPU_Use"])
mem = load(MEM_F, "Mem_Use") if "memory" in selected else pd.DataFrame(columns=["Pod","Container","Mem_Use"])
fs  = load(FS_F,  "Eph_Use") if "ephemeral" in selected else pd.DataFrame(columns=["Pod","Container","Eph_Use"])

# --- Additional signals (do not change output columns; used only for safer recommendations) ---
cpu_p95 = load(CPU_P95_F, "CPU_P95") if "cpu" in selected else pd.DataFrame(columns=["Pod","Container","CPU_P95"])
thr_max = load(THR_MAX_F, "CPU_Thr_Max") if "cpu" in selected else pd.DataFrame(columns=["Pod","Container","CPU_Thr_Max"])
thr_p95 = load(THR_P95_F, "CPU_Thr_P95") if "cpu" in selected else pd.DataFrame(columns=["Pod","Container","CPU_Thr_P95"])

mem_p95 = load(MEM_P95_F, "Mem_P95") if "memory" in selected else pd.DataFrame(columns=["Pod","Container","Mem_P95"])
oom = load(OOM_F, "OOMKilled") if "memory" in selected else pd.DataFrame(columns=["Pod","Container","OOMKilled"])
restarts = load(RESTART_F, "Restarts") if "memory" in selected else pd.DataFrame(columns=["Pod","Container","Restarts"])


if "memory" in selected and not mem.empty:
    mem["Mem_Use"] = pd.to_numeric(mem["Mem_Use"], errors="coerce") / (1024**3)
if "memory" in selected and not mem_p95.empty:
    mem_p95["Mem_P95"] = pd.to_numeric(mem_p95["Mem_P95"], errors="coerce") / (1024**3)

if "ephemeral" in selected and not fs.empty:
    fs["Eph_Use"] = pd.to_numeric(fs["Eph_Use"], errors="coerce") / (1024**3)

dfs = [d for d in [cpu, cpu_p95, thr_max, thr_p95, mem, mem_p95, oom, restarts, fs] if not d.empty]
df_usage = dfs[0] if dfs else pd.DataFrame(columns=["Pod","Container"])
for d in dfs[1:]:
    df_usage = df_usage.merge(d, on=["Pod","Container"], how="outer")
# coerce numerics but DO NOT fillna here; missing stays NaN
for c in [col for col in df_usage.columns if col.endswith("_Use")]:
    df_usage[c] = pd.to_numeric(df_usage[c], errors="coerce")
# additional numeric coercions
for c in ["CPU_P95","CPU_Thr_Max","CPU_Thr_P95","Mem_P95","OOMKilled","Restarts"]:
    if c in df_usage.columns:
        df_usage[c] = pd.to_numeric(df_usage[c], errors="coerce")

if not df_usage.empty:
    df_usage = df_usage.groupby(["Pod","Container"], as_index=False).max()
    df_usage["Workload"] = df_usage["Pod"].map(pod_to_wl)
    df_usage = df_usage[df_usage["Pod"].isin(allowed_pods)]



# ----------------- Requests/Limits from pod specs (for allowed pods) -----------------
rows = []
for pod in pods.get("items", []):
    pod_name = (pod.get("metadata", {}) or {}).get("name")
    if pod_name not in allowed_pods: continue
    for c in (pod.get("spec", {}) or {}).get("containers", []) or []:
        cname = c.get("name")
        reqs = (c.get("resources", {}) or {}).get("requests", {}) or {}
        lims = (c.get("resources", {}) or {}).get("limits", {}) or {}
        rows.append({
            "Workload": pod_to_wl.get(pod_name, pod_name),
            "Pod": pod_name, "Container": cname,
            "CPU_Req": parse_cpu(reqs.get("cpu")),
            "Mem_Req": parse_mem(reqs.get("memory")),
            "Eph_Req": parse_mem(reqs.get("ephemeral-storage")),
            "CPU_Lim": parse_cpu(lims.get("cpu")),
            "Mem_Lim": parse_mem(lims.get("memory")),
            "Eph_Lim": parse_mem(lims.get("ephemeral-storage")),
        })
df_req_lim = pd.DataFrame(rows)

# --- Merge usage with req/lim ---
df = df_req_lim.copy() if (df_usage.empty) else df_usage.merge(df_req_lim, on=["Pod","Container"], how="outer")
df = df[df["Pod"].isin(allowed_pods)] if not df.empty else df
if not df.empty and "Workload" not in df.columns:
    df["Workload"] = df["Pod"].map(pod_to_wl)

# --- Aggregate by (Workload, Container), pick representative pod with max total usage ---
if not df.empty:
    use_cols = [c for c in df.columns if c.endswith("_Use")]

    # columns that are not *_Use but must survive aggregation
    signal_cols = [c for c in ["CPU_P95","CPU_Thr_Max","CPU_Thr_P95","Mem_P95","OOMKilled","Restarts"]
                if c in df.columns]

    # score can still be based on *_Use (or include signals if you want)
    df["__score__"] = df[use_cols].sum(axis=1, skipna=True) if use_cols else 0.0

    # aggregate: keep max of usage AND signals
    agg = {col: "max" for col in (use_cols + signal_cols)}

    # also aggregate req/lim
    for col in ("CPU_Req","CPU_Lim","Mem_Req","Mem_Lim","Eph_Req","Eph_Lim"):
        if col in df.columns:
            agg[col] = "max"

    idx = df.groupby(["Workload","Container"])["__score__"].idxmax()
    rep = df.loc[idx, ["Workload","Container","Pod","__score__"]].rename(
        columns={"Pod":"RepPod","__score__":"Score"}
    )

    aggdf = df.groupby(["Workload","Container"], as_index=False).agg(agg)
    df = aggdf.merge(rep, on=["Workload","Container"], how="left")



    df["WL"]  = df["Workload"]                           # internal workload key
    df["Pod"] = df["RepPod"].fillna(df["Workload"])      # display chosen replica
    if "Score" in df.columns:
        df = df.sort_values(["Score","Pod","Container"], ascending=[False,True,True], ignore_index=True)
    else:
        df = df.sort_values(["Pod","Container"], ascending=[True,True], ignore_index=True)
    df = df.drop(columns=["Workload","RepPod","__score__"], errors="ignore")

# ----------------- Recommendation-----------------

pods_to_patch, controller_pods, recs = [], [], []

# ---------- Container classification ----------
def classify_container(container):
    c = str(container).lower()
    if c in ("kube-rbac-proxy", "rbac-proxy") or "proxy" in c or "envoy" in c:
        return "proxy"
    return "app"


# ---------- Policy map (env-driven) ----------
POLICY = {
    "app": {
        "cpu": {
            "floor": APP_CPU_FLOOR,
            "lim_min": APP_CPU_LIM_MIN,
            "req_headroom": APP_CPU_REQ_HEADROOM,
            "lim_req_mult": APP_CPU_LIM_REQ_MULT,
            "burst_mult": APP_CPU_BURST_MULT,
        },
        "mem": {
            "floor": APP_MEM_FLOOR,
            "lim_min": APP_MEM_LIM_MIN,
            "req_headroom": APP_MEM_REQ_HEADROOM,
            "lim_req_mult": APP_MEM_LIM_REQ_MULT,
            "lim_headroom": APP_MEM_LIM_HEADROOM,
            "oom_mult": MEM_OOM_MULT,
        },
    },
    "proxy": {
        "cpu": {
            "floor": PROXY_CPU_FLOOR,
            "lim_min": PROXY_CPU_LIM_MIN,
            "req_headroom": PROXY_CPU_REQ_HEADROOM,
            "lim_req_mult": PROXY_CPU_LIM_REQ_MULT,
            "burst_mult": PROXY_CPU_BURST_MULT,
            "thr_severe": PROXY_THR_SEVERE,
        },
        "mem": {
            "floor": PROXY_MEM_FLOOR,
            "lim_min": PROXY_MEM_LIM_MIN,
            "req_headroom": PROXY_MEM_REQ_HEADROOM,
            "lim_req_mult": PROXY_MEM_LIM_REQ_MULT,
            "lim_headroom": PROXY_MEM_LIM_HEADROOM,
            "oom_mult": PROXY_MEM_OOM_MULT,
        },
    },
}


# ---------- CPU tuning ----------
def tune_cpu(cur_req, cur_lim, sig, pol):
    notes = []
    cpu = sig["cpu"]
    changed = False

    # --- Force mode (testing / override) ---
    if FORCE:
        cpu["thr_p95"] = 0.0
        cpu["thr_max"] = 0.0

    # -----------------------------
    # Throttling classification
    # -----------------------------

    cpu_near_req = cpu["p95"] >= 0.5 * max(cur_req, pol["floor"])

    steady_throttling = (
        cpu["thr_p95"] >= THR_P95_BAD and
        cpu_near_req
    )

    bursty_throttling = (
        cpu["thr_p95"] >= THR_P95_BAD and
        not cpu_near_req
    )

    # -----------------------------
    # CPU REQUEST tuning
    # -----------------------------

    # Base target from utilization
    target_req = cpu["p95"] * pol["req_headroom"]

    # Correct hidden demand ONLY for steady starvation
    if steady_throttling:
        eff = min(cpu["thr_p95"], 0.90)
        target_req = (cpu["p95"] / (1.0 - eff)) * pol["req_headroom"]
        target_req = max(target_req, cur_req)
        notes.append("Steady CPU throttling detected")

    # Bursty throttling → HOLD request (do not shrink)
    elif bursty_throttling:
        target_req = cur_req
        notes.append("CPU bursty throttling detected; Req held")

    # Enforce floor
    target_req = max(target_req, pol["floor"])

    # Apply hysteresis (±20%)
    new_req = cur_req
    if cur_req == 0 or abs(target_req - cur_req) / max(cur_req, 0.01) >= 0.20:
        new_req = target_req
        if new_req > cur_req:
            notes.append("CPU Req ↑")
        elif new_req < cur_req:
            notes.append("CPU Req ↓")

    # -----------------------------
    # CPU LIMIT tuning
    # -----------------------------

    new_lim = cur_lim
    if cur_lim > 0:
        # Base limit from request + absolute floor
        target_lim = max(
            new_req * pol["lim_req_mult"],
            pol["lim_min"]
        )

        # ---- Limit decisions (mutually exclusive) ----

        # Steady throttling → HOLD or increase, never shrink
        if steady_throttling:
            target_lim = max(target_lim, cur_lim)
            notes.append("CPU Lim held (steady throttling)")

        # Bursty throttling → HOLD limit (Redis-safe)
        elif bursty_throttling:
            target_lim = cur_lim
            notes.append("CPU Lim held (bursty throttling)")

        # Startup bursts → ignore
        elif (
            cpu["thr_max"] >= THR_MAX_BAD and
            cpu["thr_p95"] < THR_P95_BAD / 2 and
            cpu["p95"] < new_req * 0.5
        ):
            target_lim = cur_lim
            notes.append("CPU startup burst ignored")

        # Legitimate bursts (no throttling) → allow burst limit
        elif cpu["thr_max"] >= THR_MAX_BAD:
            burst_lim = new_req * pol["burst_mult"]
            if burst_lim > target_lim:
                target_lim = burst_lim
                notes.append("CPU burst limit applied")

        # Otherwise allow limit to follow observed max
        elif cpu["max"] > 0 and cpu["thr_p95"] < THR_P95_BAD:
            target_lim = max(target_lim, cpu["max"] * 1.10)

        # Apply hysteresis (±20%)
        if abs(target_lim - cur_lim) / max(cur_lim, 0.01) >= 0.20:
            new_lim = target_lim
            if new_lim > cur_lim:
                notes.append("CPU Lim ↑")
            elif new_lim < cur_lim:
                notes.append("CPU Lim ↓")

        # Safety invariant
        new_lim = max(new_lim, new_req)

    # -----------------------------
    # Final change detection
    # -----------------------------

    if new_req != cur_req or new_lim != cur_lim:
        changed = True

    return new_req, new_lim, changed, notes

def tune_mem(cur_req, cur_lim, sig, pol):
    notes = []
    mem, ev = sig["mem"], sig["events"]
    changed = False

    # Request: p95 × headroom
    target_req = mem["p95"] * pol["req_headroom"]

    # OOM protection
    if ev["oom"]:
        target_req = max(target_req, cur_req)

    # Enforce floor
    target_req = max(target_req, pol["floor"])

    new_req = cur_req
    if cur_req == 0 or abs(target_req - cur_req) / max(cur_req, 1) >= 0.20:
        new_req = target_req
        if new_req > cur_req:       
            notes.append("Mem Req ↑")
        elif new_req < cur_req:
            notes.append("Mem Req ↓")   

    # Limit: req-based + max burst + OOM
    new_lim = cur_lim
    if cur_lim > 0:
        target_lim = new_req * pol["lim_req_mult"]

        if mem["max"] > 0:
            target_lim = max(target_lim, mem["max"] * pol["lim_headroom"])

        if ev["oom"]:
            target_lim = max(target_lim, new_req * pol["oom_mult"])
            notes.append("OOMKilled observed")

        target_lim = max(target_lim, pol["lim_min"])

        if abs(target_lim - cur_lim) / max(cur_lim, 1) >= 0.20:
            new_lim = target_lim
            if new_lim > cur_lim:       
                notes.append("Mem Lim ↑")
            elif new_lim < cur_lim:
                notes.append("Mem Lim ↓")

    if new_req != cur_req or new_lim != cur_lim:
        changed = True 

    return new_req, new_lim, changed, notes


def ensure_limit_ge_req(res, kind):
    if nz(res.get(f"{kind}_Lim")) < nz(res.get(f"{kind}_Req")):
        res[f"{kind}_Lim"] = res[f"{kind}_Req"]


# ----------------- MAIN LOOP -----------------

for _, r in df.iterrows():
    pod, cont = r["Pod"], r["Container"]
    
    # if not cont.lower().startswith("redis"):
    #     continue

    res, notes = {}, []
    changed_flag = False

    signals = {
        "cpu": {
            "p95": nz(r.get("CPU_P95"), 0.0),
            "max": nz(r.get("CPU_Use"), 0.0),
            "thr_p95": nz(r.get("CPU_Thr_P95"), 0.0),
            "thr_max": nz(r.get("CPU_Thr_Max"), 0.0),
        },
        "mem": {
            "p95": nz(r.get("Mem_P95"), nz(r.get("Mem_Use"), 0.0)),
            "max": nz(r.get("Mem_Use"), 0.0),
        },
        "events": {
            "oom": nz(r.get("OOMKilled"), 0) >= 1,
            "mem_pressure": (
                nz(r.get("Mem_Lim")) > 0 and
                nz(r.get("Mem_P95"), 0) / nz(r.get("Mem_Lim")) >= MEM_PRESSURE_P95
            ),
            "restarts": nz(r.get("Restarts"), 0),
        }
    }
    policy = POLICY[classify_container(cont)]

    print(f"[INFO] Processing Pod='{pod}' Container='{cont}'")
    print(f"Signals: {signals}")

     # Build record

    rec = {"Pod": pod, "Container": cont}
    wl_key = r.get("WL", None)
    if wl_key:
        rec["WL"] = wl_key
    rec["Score"] = nz(r.get("Score"), 0.0)

    if should_check("cpu"):
        cpu_req, cpu_lim, changed, cpu_notes = tune_cpu(
            nz(r.get("CPU_Req")), nz(r.get("CPU_Lim")), signals, policy["cpu"]
        )
        res["CPU_Req"], res["CPU_Lim"] = cpu_req, cpu_lim

        rec.update({ 
        "CPU_P95": ceil_cpu(r.get("CPU_P95")), 
        "CPU_Max": ceil_cpu(r.get("CPU_Use")), 
        "CPU_Req_Current": ceil_cpu(r.get("CPU_Req")), 
        "CPU_Req_New": ceil_cpu(res.get("CPU_Req", r.get("CPU_Req"))), 
        "CPU_Lim_Current": ceil_cpu(r.get("CPU_Lim")), 
        "CPU_Lim_New": ceil_cpu(res.get("CPU_Lim", r.get("CPU_Lim"))), 
        })
        
        changed_flag = changed_flag or changed
        notes.extend(cpu_notes)

    if should_check("mem"):
        mem_req, mem_lim, changed, mem_notes = tune_mem(
            nz(r.get("Mem_Req")), nz(r.get("Mem_Lim")), signals, policy["mem"]
        )
        res["Mem_Req"], res["Mem_Lim"] = mem_req, mem_lim

        rec.update({ 
        "Mem_P95": ceil_mem(r.get("Mem_P95")), 
        "Mem_Max": ceil_mem(r.get("Mem_Use")), 
        "Mem_Req_Current": ceil_mem(r.get("Mem_Req")), 
        "Mem_Req_New": ceil_mem(res.get("Mem_Req", r.get("Mem_Req"))), 
        "Mem_Lim_Current": ceil_mem(r.get("Mem_Lim")), 
        "Mem_Lim_New": ceil_mem(res.get("Mem_Lim", r.get("Mem_Lim"))), 
        })

        changed_flag = changed_flag or changed
        notes.extend(mem_notes)

    if should_check("cpu"):
        ensure_limit_ge_req(res, "CPU")
    if should_check("mem"):
        ensure_limit_ge_req(res, "Mem")



    rec["Changed"] = "Yes" if changed_flag else "No" 
    rec["Notes"] = "; ".join(notes) 
    recs.append(rec)

    if changed_flag:
        reqs, lims = {}, {}
        if nz(res.get("CPU_Req")) > 0: reqs["cpu"] = fmt_cpu_k8s(res["CPU_Req"])
        if nz(res.get("Mem_Req")) > 0: reqs["memory"] = fmt_mem_k8s_mi(res["Mem_Req"])
        if nz(res.get("CPU_Lim")) > 0: lims["cpu"] = fmt_cpu_k8s(res["CPU_Lim"])
        if nz(res.get("Mem_Lim")) > 0: lims["memory"] = fmt_mem_k8s_mi(res["Mem_Lim"])
        entry = {"Pod": pod, "Container": cont, "requests": reqs, "limits": lims}

        if pod.startswith(("ibm-dataprotectionserver-controller-manager",
                            "ibm-dataprotectionagent-controller-manager")):
            controller_pods.append(entry)
        else:
            pods_to_patch.append(entry)

if controller_pods:
    pods_to_patch.extend(controller_pods)


# --- Build overrides from RAW records (keep WL), then build display df_recs ---
df_recs_raw = pd.DataFrame(recs)  # contains WL for workload-keyed overrides

# 1) Overrides keyed by (Workload, Container) so all replicas inherit "New"
overrides = {}
if not df_recs_raw.empty:
    for _, r in df_recs_raw.iterrows():
        wl = r.get("WL", None)
        key = ((wl if wl else r.get("Pod")), r.get("Container"))
        o = {}
        for RES in ("CPU","Mem","Eph"):
            req_new = r.get(f"{RES}_Req_New")
            lim_new = r.get(f"{RES}_Lim_New")
            if not is_na(req_new): o[f"{RES}_Req_New"] = req_new
            if not is_na(lim_new): o[f"{RES}_Lim_New"] = lim_new
        if o and key[0] and key[1]:
            overrides[key] = o

# 2) Display DataFrame (no WL column)
df_recs = df_recs_raw.copy()
ordered = ["Pod","Container"]
if "cpu" in selected:       ordered += ["CPU_P95","CPU_Max","CPU_Req_Current","CPU_Req_New","CPU_Lim_Current","CPU_Lim_New"]
if "memory" in selected:    ordered += ["Mem_P95","Mem_Max","Mem_Req_Current","Mem_Req_New","Mem_Lim_Current","Mem_Lim_New"]
if "ephemeral" in selected: ordered += ["Eph_Max","Eph_Req_Current","Eph_Req_New","Eph_Lim_Current","Eph_Lim_New"]
ordered += ["Changed","Notes"]
for col in ordered:
    if col not in df_recs.columns:
        df_recs[col] = ("" if col == "Notes" else float("nan"))
df_recs = df_recs.reindex(columns=ordered)

# ----------------- Namespace totals (per-pod sum; replicas counted) -----------------
def eff_new(pod_or_wl, cont, RES, kind, current):
    val = overrides.get((pod_or_wl, cont), {}).get(f"{RES}_{kind}_New")
    return nz(val, nz(current))

ns_acc, acc = {"Namespace": NS_NAME}, {}
def add_acc(name, val):
    if val is None: return
    if isinstance(val, float) and math.isnan(val): return
    acc[name] = acc.get(name, 0.0) + float(val)

for pod in pods.get("items", []):
    if (pod.get("status", {}) or {}).get("phase") != "Running": continue
    pod_name = (pod.get("metadata", {}) or {}).get("name")
    if not pod_name: continue
    wl = pod_to_wl.get(pod_name, pod_name)
    for c in (pod.get("spec", {}) or {}).get("containers", []) or []:
        cname = c.get("name")
        if not cname: continue
        reqs = (c.get("resources", {}) or {}).get("requests", {}) or {}
        lims = (c.get("resources", {}) or {}).get("limits", {}) or {}
        cur_cpu_req = parse_cpu(reqs.get("cpu"))
        cur_cpu_lim = parse_cpu(lims.get("cpu"))
        cur_mem_req = parse_mem(reqs.get("memory"))
        cur_mem_lim = parse_mem(lims.get("memory"))
        cur_eph_req = parse_mem(reqs.get("ephemeral-storage"))
        cur_eph_lim = parse_mem(lims.get("ephemeral-storage"))

        if "cpu" in selected:
            add_acc("CPU_Req_Current", nz(cur_cpu_req))
            add_acc("CPU_Req_New",     nz(eff_new(wl, cname, "CPU","Req", cur_cpu_req)))
            add_acc("CPU_Lim_Current", nz(cur_cpu_lim))
            add_acc("CPU_Lim_New",     nz(eff_new(wl, cname, "CPU","Lim", cur_cpu_lim)))
        if "memory" in selected:
            add_acc("Mem_Req_Current", nz(cur_mem_req))
            add_acc("Mem_Req_New",     nz(eff_new(wl, cname, "Mem","Req", cur_mem_req)))
            add_acc("Mem_Lim_Current", nz(cur_mem_lim))
            add_acc("Mem_Lim_New",     nz(eff_new(wl, cname, "Mem","Lim", cur_mem_lim)))
        if "ephemeral" in selected:
            add_acc("Eph_Req_Current", nz(cur_eph_req))
            add_acc("Eph_Req_New",     nz(eff_new(wl, cname, "Eph","Req", cur_eph_req)))
            add_acc("Eph_Lim_Current", nz(cur_eph_lim))
            add_acc("Eph_Lim_New",     nz(eff_new(wl, cname, "Eph","Lim", cur_eph_lim)))

ns_acc.update(acc)
df_ns = pd.DataFrame([ns_acc])

# -------- Convert NaN/None -> "N/A" in Req/Lim columns (display only) --------
def replace_na_with_str(df, cols_like=("Req","Lim")):
    cols = [c for c in df.columns if any(k in c for k in cols_like)]
    for c in cols:
        df[c] = df[c].apply(lambda x: "N/A" if is_na(x) else x)

replace_na_with_str(df_recs)
replace_na_with_str(df_ns)

# -------- Excel NaN-safe writer --------
def _excel_safe(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    for c in out.columns:
        if pd.api.types.is_integer_dtype(out[c].dtype):
            out[c] = out[c].astype("float64")
    out = out.where(~out.isna(), None)
    return out

df_recs_out = _excel_safe(df_recs)
df_ns_out   = _excel_safe(df_ns)

# ----------------- Write Excel (formatting + autofit) -----------------
with pd.ExcelWriter(XLSX, engine="xlsxwriter") as writer:
    df_recs_out.to_excel(writer, sheet_name="Pod-Level", index=False)
    df_ns_out.to_excel(writer, sheet_name="Namespace-Level", index=False)

    wb = writer.book

    # Pod-Level sheet
    sh = writer.sheets["Pod-Level"]

    if "Changed" in df_recs.columns:
        ch_idx = df_recs.columns.get_loc("Changed")
        ch_col = chr(ord("A") + ch_idx)
        ch_rng = f"{ch_col}2:{ch_col}{len(df_recs) + 1}"
        sh.conditional_format(ch_rng, {
            "type":"text","criteria":"containing","value":"Yes",
            "format": wb.add_format({"bg_color":"#C6EFCE","align":"center","border":1})
        })
        sh.conditional_format(ch_rng, {
            "type":"text","criteria":"containing","value":"No",
            "format": wb.add_format({"bg_color":"#D9D9D9","align":"center","border":1})
        })

    if "Notes" in df_recs.columns:
        nt_idx = df_recs.columns.get_loc("Notes")
        nt_col = chr(ord("A") + nt_idx)
        nt_rng = f"{nt_col}2:{nt_col}{len(df_recs) + 1}"
        sh.conditional_format(nt_rng, {
            "type":"text","criteria":"containing","value":"↓",
            "format": wb.add_format({"bg_color":"#FFF2CC","border":1})
        })
        sh.conditional_format(nt_rng, {
            "type":"text","criteria":"containing","value":"↑",
            "format": wb.add_format({"bg_color":"#F4CCCC","border":1})
        })

    num_fmt_cpu = wb.add_format({"num_format":"0.000"})
    num_fmt_mem = wb.add_format({"num_format":"0.00"})
    for i, col in enumerate(df_recs.columns):
        col_vals = df_recs[col].apply(lambda x: "" if is_na(x) else str(x))
        mc = col_vals.map(len).max()
        max_cell = int(mc) if pd.notna(mc) else 0
        width = max(len(col), max_cell) + 2
        if col.startswith("CPU_"):
            sh.set_column(i, i, width, num_fmt_cpu)
        elif col.startswith(("Mem_","Eph_")):
            sh.set_column(i, i, width, num_fmt_mem)
        else:
            sh.set_column(i, i, width)

    # Namespace-Level sheet
    sh_ns = writer.sheets["Namespace-Level"]
    for i, col in enumerate(df_ns.columns):
        col_vals = df_ns[col].apply(lambda x: "" if is_na(x) else str(x))
        mc = col_vals.map(len).max()
        max_cell = int(mc) if pd.notna(mc) else 0
        width = max(len(col), max_cell) + 2
        if col.startswith("CPU_"):
            sh_ns.set_column(i, i, width, num_fmt_cpu)
        elif col.startswith(("Mem_","Eph_")):
            sh_ns.set_column(i, i, width, num_fmt_mem)
        else:
            sh_ns.set_column(i, i, width)

# ----------------- Save Patch JSON -----------------
patch_bundle = {
    "namespace": NS_NAME,
    "created": datetime.datetime.utcnow().isoformat() + "Z",
    "containers": pods_to_patch
}
with open(PATCH_FILE, "w") as f:
    json.dump(patch_bundle, f, indent=2)

# ----------------- Console output -----------------
def truncate(val, maxlen=20):
    s = str(val)
    return s if len(s) <= maxlen else s[:maxlen-1] + "…"

def build_console_df(df, selected, full):
    if full:
        return df

    out = pd.DataFrame(index=df.index)

    out["Pod"] = df["Pod"].map(lambda v: truncate(v, 20))
    out["Container"] = df["Container"].map(lambda v: truncate(v, 20))

    # CPU section
    if "cpu" in selected and all(c in df.columns for c in
        ["CPU_P95", "CPU_Max", "CPU_Req_Current", "CPU_Req_New",
         "CPU_Lim_Current", "CPU_Lim_New"]):
        cpu_series = df.apply(
            lambda r: f"P95={fmt_cpu_or_na(r['CPU_P95'])}"
                    f" (Max={fmt_cpu_or_na(r['CPU_Max'])}) | "
                    f"{fmt_cpu_or_na(r['CPU_Req_Current'])}→{fmt_cpu_or_na(r['CPU_Req_New'])} | "
                    f"{fmt_cpu_or_na(r['CPU_Lim_Current'])}→{fmt_cpu_or_na(r['CPU_Lim_New'])}",
            axis=1
        )
        # --- Fix 3: use .insert() (avoids get_loc path entirely) ---
        out.insert(len(out.columns), "CPU", cpu_series.to_numpy())

    # Memory section
    if "memory" in selected and all(c in df.columns for c in
        ["Mem_P95","Mem_Max","Mem_Req_Current","Mem_Req_New",
         "Mem_Lim_Current","Mem_Lim_New"]):
        mem_series = df.apply(
            lambda r: f"P95={fmt_mem_or_na(r['Mem_P95'])}"
                      f" (Max={fmt_mem_or_na(r['Mem_Max'])}) | "
                      f"{fmt_mem_or_na(r['Mem_Req_Current'])}→{fmt_mem_or_na(r['Mem_Req_New'])} | "
                      f"{fmt_mem_or_na(r['Mem_Lim_Current'])}→{fmt_mem_or_na(r['Mem_Lim_New'])}",
            axis=1
        )
        out.insert(len(out.columns), "Mem", mem_series.to_numpy())

    # Ephemeral section (same pattern)
    if "ephemeral" in selected and all(c in df.columns for c in
        ["Eph_Max","Eph_Req_Current","Eph_Req_New",
         "Eph_Lim_Current","Eph_Lim_New"]):
        eph_series = df.apply(
            lambda r: f"{fmt_mem_or_na(r['Eph_Max'])} | "
                      f"{fmt_mem_or_na(r['Eph_Req_Current'])}→{fmt_mem_or_na(r['Eph_Req_New'])} | "
                      f"{fmt_mem_or_na(r['Eph_Lim_Current'])}→{fmt_mem_or_na(r['Eph_Lim_New'])}",
            axis=1
        )
        out.insert(len(out.columns), "Eph", eph_series.to_numpy())

    if "Changed" in df.columns:
        out["Changed"] = df["Changed"]
    if "Notes" in df.columns:
        out["Notes"] = df["Notes"]

    return out


full = os.environ.get("CONSOLE_FULL", "0").lower() in ("1","true","yes","y")

print("\n=== Recommendations ===")
df_console = build_console_df(df_recs, selected, full)
print(tabulate(df_console, headers="keys", tablefmt="github"))
if not full:
    print("\nLegend: Each resource column shows 'Use | ReqCurrent→ReqNew | LimCurrent→LimNew'")

print("\n=== Namespace Quota (Current vs New) ===")
print(tabulate(df_ns, headers="keys", tablefmt="github"))

print("\nRules applied:")

print("\nCPU Requests:")
print("  - Base = P95 CPU usage × headroom")
print("  - CPU demand is considered meaningful only if P95 ≥ 50% of current request (or floor)")
print("  - If steady throttling exists (P95 throttle ≥ threshold AND meaningful CPU):")
print("      * Correct hidden demand: P95 / (1 - throttle) × headroom")
print("      * Never reduce CPU request while steady throttling exists")
print("  - If bursty throttling exists (high throttle, low P95):")
print("      * Hold CPU request (do not shrink)")
print("  - If no throttling exists:")
print("      * CPU request may be reduced based on P95")
print("  - Minimum CPU floors are always enforced")
print("  - Changes are applied only if the delta is ≥ 20%")

print("\nCPU Limits:")
print("  - Base = max(new CPU request × limit-multiplier, absolute minimum limit)")
print("  - If steady throttling exists:")
print("      * Never reduce CPU limit")
print("  - If bursty throttling exists:")
print("      * Hold CPU limit (do not shrink)")
print("  - Startup-only bursts (high max throttle, low P95 throttle, low P95 usage) are ignored")
print("  - If no throttling exists:")
print("      * Allow burst headroom (new request × burst-multiplier)")
print("      * Or track observed max usage (max × 1.1)")
print("  - CPU limit is never allowed below CPU request")
print("  - Changes are applied only if the delta is ≥ 20%")

print("\nMemory Requests:")
print("  - Base = P95 memory usage × headroom")
print("  - If an OOM occurred:")
print("      * Never reduce memory request")
print("  - Minimum memory floors are always enforced")
print("  - Changes are applied only if the delta is ≥ 20%")

print("\nMemory Limits:")
print("  - Base = new memory request × limit-multiplier")
print("  - Allow memory bursts using observed max × headroom")
print("  - If an OOM occurred:")
print("      * Memory limit ≥ request × OOM multiplier")
print("  - Minimum memory limits are always enforced")
print("  - Changes are applied only if the delta is ≥ 20%")


print("\nExcel report:", XLSX)
print("Patch JSON:", PATCH_FILE)
print("Patch JSON includes only podcontainers with changes in the selected resources.")
print(f"\nTo apply the recommendations, run :\n./pod-res-apply.sh {PATCH_FILE}\n")
print("above script runs in dry-run mode by default; use -p to patch changes.")
print("Done.")
PYEOF
