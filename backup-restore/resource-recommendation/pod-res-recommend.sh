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

Outputs:
  - Excel report with Current vs New recommendations
  - Console table summary

Rules:
  - Requests: usage < 50% of request → cut to 50%
  - Limits:   usage < 50% of limit → cut to 75%
  
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

echo "[INFO] Starting port-forward to Prometheus pod $PROM_POD in namespace $PROM_NS..."
oc -n "$PROM_NS" port-forward "$PROM_POD" 9090:9090 >"$PF_LOG" 2>&1 &
PF_PID=$!
trap "kill $PF_PID >/dev/null 2>&1 || true; wait $PF_PID 2>/dev/null || true; rm -rf $TMPDIR" EXIT

for i in {1..30}; do
  if curl -sS http://localhost:9090/-/ready >/dev/null 2>&1; then
    echo "Port-forward established (PID=$PF_PID)"
    break
  fi
  sleep 1
done

# --- Prometheus queries ---
query_to_tsv() {
  local q="$1"; local out="$2"
  
  curl -sG --compressed --max-time 120 "http://localhost:9090/api/v1/query" \
    --data-urlencode "query=$q" \
  | jq -r '.data.result[]? | [.metric.pod, .metric.container, .value[1]] | @tsv' > "$out" || true

}

CPU_F="$TMPDIR/cpu.tsv"; MEM_F="$TMPDIR/mem.tsv"; FS_F="$TMPDIR/fs.tsv"

echo "[INFO] Querying Prometheus..."
if [[ "$RESOURCES" == *cpu* ]]; then
  CPU_USAGE_Q='max by (pod,container) (max_over_time(rate(container_cpu_usage_seconds_total{namespace="'"$NS"'",container!="",container!="POD"}[5m])['"$DURATION"':]))'
  query_to_tsv "$CPU_USAGE_Q" "$CPU_F"
fi

if [[ "$RESOURCES" == *memory* ]]; then
  MEM_USAGE_Q='max by (pod,container) (max_over_time(container_memory_working_set_bytes{namespace="'"$NS"'",container!="",container!="POD"}['"$DURATION"':]))'
  query_to_tsv "$MEM_USAGE_Q" "$MEM_F"
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
RESOURCES="$RESOURCES" NS="$NS" CPU_F="$CPU_F" MEM_F="$MEM_F" FS_F="$FS_F" PODS_JSON="$PODS_JSON" XLSX="$XLSX" PATCH_FILE="$PATCH_FILE" FORCE="$FORCE" "$PYTHON_EXEC" - <<'PYEOF'
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
MEM_F      = os.environ.get("MEM_F")
FS_F       = os.environ.get("FS_F")
PODS_JSON  = os.environ.get("PODS_JSON")
NS_NAME    = os.environ.get("NS")
FORCE      = os.environ.get("FORCE", "0").lower() in ("1","true","yes","y")

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

if "memory" in selected and not mem.empty:
    mem["Mem_Use"] = pd.to_numeric(mem["Mem_Use"], errors="coerce") / (1024**3)
if "ephemeral" in selected and not fs.empty:
    fs["Eph_Use"] = pd.to_numeric(fs["Eph_Use"], errors="coerce") / (1024**3)

dfs = [d for d in [cpu, mem, fs] if not d.empty]
df_usage = dfs[0] if dfs else pd.DataFrame(columns=["Pod","Container"])
for d in dfs[1:]:
    df_usage = df_usage.merge(d, on=["Pod","Container"], how="outer")
# coerce numerics but DO NOT fillna here; missing stays NaN
for c in [col for col in df_usage.columns if col.endswith("_Use")]:
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
    df["__score__"] = df[use_cols].sum(axis=1, skipna=True) if use_cols else 0.0

    agg = {col: "max" for col in use_cols}
    for col in ("CPU_Req","CPU_Lim","Mem_Req","Mem_Lim","Eph_Req","Eph_Lim"):
        if col in df.columns: agg[col] = "max"

    idx = df.groupby(["Workload","Container"])["__score__"].idxmax()
    rep = df.loc[idx, ["Workload","Container","Pod","__score__"]].rename(columns={"Pod":"RepPod","__score__":"Score"})
    aggdf = df.groupby(["Workload","Container"], as_index=False).agg(agg)
    df = aggdf.merge(rep, on=["Workload","Container"], how="left")

    df["WL"]  = df["Workload"]                           # internal workload key
    df["Pod"] = df["RepPod"].fillna(df["Workload"])      # display chosen replica
    if "Score" in df.columns:
        df = df.sort_values(["Score","Pod","Container"], ascending=[False,True,True], ignore_index=True)
    else:
        df = df.sort_values(["Pod","Container"], ascending=[True,True], ignore_index=True)
    df = df.drop(columns=["Workload","RepPod","__score__"], errors="ignore")

# ----------------- Recommendation rules -----------------
pods_to_patch, recs = [], []
controller_pods = []

for _, r in df.iterrows():
    pod = r["Pod"]; cont = r["Container"]
    res, notes = {}, []

    def adj_request(use, req, kind):
        req_v = nz(req)
        if req_v > 0 and use < 0.5 * req_v:
            res[f"{kind}_Req"] = req_v * 0.5; notes.append(f"{kind} ↓ Req")

    def adj_limit(use, req, cur_lim, kind):
        lim_v = nz(cur_lim); req_v = nz(req)
        if lim_v == 0: return
        if use < 0.5 * lim_v:
            new_lim = lim_v * 0.75
            if new_lim < req_v:
                new_lim = req_v; notes.append(f"{kind} ↓ Lim→Req")
            else:
                notes.append(f"{kind} ↓ Lim")
            res[f"{kind}_Lim"] = new_lim

    # Use nz(...) for rule math; but for display we won't coerce to zero
    if should_check("cpu"):
        adj_request(nz(r.get("CPU_Use", 0.0)), r.get("CPU_Req"), "CPU")
        adj_limit  (nz(r.get("CPU_Use", 0.0)), r.get("CPU_Req"), r.get("CPU_Lim"), "CPU")
    if should_check("mem"):
        adj_request(nz(r.get("Mem_Use", 0.0)), r.get("Mem_Req"), "Mem")
        adj_limit  (nz(r.get("Mem_Use", 0.0)), r.get("Mem_Req"), r.get("Mem_Lim"), "Mem")
    if should_check("eph"):
        adj_request(nz(r.get("Eph_Use", 0.0)), r.get("Eph_Req"), "Eph")
        adj_limit  (nz(r.get("Eph_Use", 0.0)), r.get("Eph_Req"), r.get("Eph_Lim"), "Eph")

    changed = "Yes" if notes else "No"
    wl_key = r.get("WL", None)

    rec = {"Pod": pod, "Container": cont}
    if wl_key: rec["WL"] = wl_key
    rec["Score"] = nz(r.get("Score"), 0.0)

    # ---------- Display: DO NOT coerce usage to 0; keep None/NaN as N/A ----------
    if "cpu" in selected:
        rec.update({
            "CPU_Use":         ceil_cpu(r.get("CPU_Use")),   # <-- no nz()
            "CPU_Req_Current": ceil_cpu(r.get("CPU_Req")),
            "CPU_Req_New":     ceil_cpu(res.get("CPU_Req", r.get("CPU_Req"))),
            "CPU_Lim_Current": ceil_cpu(r.get("CPU_Lim")),
            "CPU_Lim_New":     ceil_cpu(res.get("CPU_Lim", r.get("CPU_Lim"))),
        })
    if "memory" in selected:
        rec.update({
            "Mem_Use":         ceil_mem(r.get("Mem_Use")),   # <-- no nz()
            "Mem_Req_Current": ceil_mem(r.get("Mem_Req")),
            "Mem_Req_New":     ceil_mem(res.get("Mem_Req", r.get("Mem_Req"))),
            "Mem_Lim_Current": ceil_mem(r.get("Mem_Lim")),
            "Mem_Lim_New":     ceil_mem(res.get("Mem_Lim", r.get("Mem_Lim"))),
        })
    if "ephemeral" in selected:
        rec.update({
            "Eph_Use":         ceil_mem(r.get("Eph_Use")),   # <-- no nz()
            "Eph_Req_Current": ceil_mem(r.get("Eph_Req")),
            "Eph_Req_New":     ceil_mem(res.get("Eph_Req", r.get("Eph_Req"))),
            "Eph_Lim_Current": ceil_mem(r.get("Eph_Lim")),
            "Eph_Lim_New":     ceil_mem(res.get("Eph_Lim", r.get("Eph_Lim"))),
        })

    rec["Changed"] = changed
    rec["Notes"]   = "; ".join(notes)
    recs.append(rec)
    
    if notes:
        reqs, lims = {}, {}
        cpu_req = res.get("CPU_Req", r.get("CPU_Req"))
        mem_req = res.get("Mem_Req", r.get("Mem_Req"))
        eph_req = res.get("Eph_Req", r.get("Eph_Req"))
        if not is_na(cpu_req) and nz(cpu_req) > 0: reqs["cpu"] = fmt_cpu_k8s(cpu_req)
        if not is_na(mem_req) and nz(mem_req) > 0: reqs["memory"] = fmt_mem_k8s_mi(mem_req)
        if not is_na(eph_req) and nz(eph_req) > 0: reqs["ephemeral-storage"] = fmt_mem_k8s_mi(eph_req)

        cpu_lim = res.get("CPU_Lim", r.get("CPU_Lim"))
        mem_lim = res.get("Mem_Lim", r.get("Mem_Lim"))
        eph_lim = res.get("Eph_Lim", r.get("Eph_Lim"))
        if not is_na(cpu_lim) and nz(cpu_lim) > 0: lims["cpu"] = fmt_cpu_k8s(cpu_lim)
        if not is_na(mem_lim) and nz(mem_lim) > 0: lims["memory"] = fmt_mem_k8s_mi(mem_lim)
        if not is_na(eph_lim) and nz(eph_lim) > 0: lims["ephemeral-storage"] = fmt_mem_k8s_mi(eph_lim)
        
        print(f"[INFO] Pod '{pod}' Container '{cont}' to be patched: Requests={reqs} Limits={lims}")
        if pod.startswith("ibm-dataprotectionserver-controller-manager") or pod.startswith("ibm-dataprotectionagent-controller-manager"):
            print(f"[INFO] --> Special controller pod detected; all replicas will inherit these settings.")
            controller_pods.append({"Pod": pod, "Container": cont, "requests": reqs, "limits": lims})
        else:
            pods_to_patch.append({"Pod": pod, "Container": cont, "requests": reqs, "limits": lims})

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
if "cpu" in selected:       ordered += ["CPU_Use","CPU_Req_Current","CPU_Req_New","CPU_Lim_Current","CPU_Lim_New"]
if "memory" in selected:    ordered += ["Mem_Use","Mem_Req_Current","Mem_Req_New","Mem_Lim_Current","Mem_Lim_New"]
if "ephemeral" in selected: ordered += ["Eph_Use","Eph_Req_Current","Eph_Req_New","Eph_Lim_Current","Eph_Lim_New"]
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
        ["CPU_Use", "CPU_Req_Current", "CPU_Req_New",
         "CPU_Lim_Current", "CPU_Lim_New"]):
        cpu_series = df.apply(
            lambda r: f"{fmt_cpu_or_na(r['CPU_Use'])} | "
                      f"{fmt_cpu_or_na(r['CPU_Req_Current'])}→{fmt_cpu_or_na(r['CPU_Req_New'])} | "
                      f"{fmt_cpu_or_na(r['CPU_Lim_Current'])}→{fmt_cpu_or_na(r['CPU_Lim_New'])}",
            axis=1
        )
        # --- Fix 3: use .insert() (avoids get_loc path entirely) ---
        out.insert(len(out.columns), "CPU", cpu_series.to_numpy())

    # Memory section
    if "memory" in selected and all(c in df.columns for c in
        ["Mem_Use","Mem_Req_Current","Mem_Req_New",
         "Mem_Lim_Current","Mem_Lim_New"]):
        mem_series = df.apply(
            lambda r: f"{fmt_mem_or_na(r['Mem_Use'])} | "
                      f"{fmt_mem_or_na(r['Mem_Req_Current'])}→{fmt_mem_or_na(r['Mem_Req_New'])} | "
                      f"{fmt_mem_or_na(r['Mem_Lim_Current'])}→{fmt_mem_or_na(r['Mem_Lim_New'])}",
            axis=1
        )
        out.insert(len(out.columns), "Mem", mem_series.to_numpy())

    # Ephemeral section (same pattern)
    if "ephemeral" in selected and all(c in df.columns for c in
        ["Eph_Use","Eph_Req_Current","Eph_Req_New",
         "Eph_Lim_Current","Eph_Lim_New"]):
        eph_series = df.apply(
            lambda r: f"{fmt_mem_or_na(r['Eph_Use'])} | "
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

print("\n Rules applied:")
print(" - Requests: usage < 50% of request → cut to 50%")
print(" - Limits:   usage < 50% of limit → cut to 75%")
print("\nExcel report:", XLSX)
print("Patch JSON:", PATCH_FILE)
print("Patch JSON includes only podcontainers with changes in the selected resources.")
print(f"\nTo apply the recommendations, run :\n./pod-res-apply.sh {PATCH_FILE}\n")
print("above script runs in dry-run mode by default; use -p to patch changes.")
print("Done.")

PYEOF
