#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: pod-res-apply.sh <patch.json> [options]

Options:
  --namespace=<ns>       Validate JSON namespace matches <ns>
  --max-age=<dur>        Max JSON age (default 1h). Units: s,m,h,d
  --deploy-only          Patch only Deployments
  --sts-only             Patch only StatefulSets
  --deploy-sts-only      Patch only Deployment and StatefulSet
  --deploy-csv-only      Patch only Deployment and CSV
  -p                     Actually apply changes (default mode is dry-run)
  -h, --help             Show this help message

EOF
}

[[ $# -lt 1 ]] && { show_help; exit 1; }
[[ "$1" == "-h" || "$1" == "--help" ]] && { show_help; exit 0; }

PATCH_FILE="$1"; shift
[[ -f "$PATCH_FILE" ]] || { echo "ERROR: file not found: $PATCH_FILE"; exit 1; }

NS_OVERRIDE=""; MAX_AGE="1h"; TRACE=1; YES=0
ALLOW="Deployment,StatefulSet,ClusterServiceVersion,DataProtectionApplication,Redis,KafkaBridge,KafkaNodePool,Kafka"

for arg in "$@"; do
  case "$arg" in
    --namespace=*) NS_OVERRIDE="${arg#*=}";;
    --max-age=*)   MAX_AGE="${arg#*=}";;
    --trace)       TRACE=1;;
    -p)            YES=1;;
    --deploy-only)         ALLOW="Deployment";;
    --sts-only)            ALLOW="StatefulSet";;
    --deploy-sts-only)     ALLOW="Deployment,StatefulSet";;
    --deploy-csv-only)     ALLOW="Deployment,ClusterServiceVersion";;
    *) echo "Unknown arg: $arg"; exit 1;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: need $1"; exit 1; }; }
need oc; need jq; need date

parse_duration_to_seconds() {
  [[ "$1" =~ ^([0-9]+)([smhd])$ ]] || { echo "ERROR: invalid duration '$1' (use 30m,2h,1d)" >&2; return 1; }
  local n="${BASH_REMATCH[1]}" u="${BASH_REMATCH[2]}"
  case "$u" in s) echo "$n";; m) echo $((n*60));; h) echo $((n*3600));; d) echo $((n*86400));; esac
}

rfc3339_epoch() {
  local ts="$1" nf; nf=$(sed -E 's/\.[0-9]+Z$/Z/' <<<"$ts")
  if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$nf" +%s >/dev/null 2>&1; then
    date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$nf" +%s
  elif date -u -d "$ts" +%s >/dev/null 2>&1; then date -u -d "$ts" +%s
  elif date -u -d "$nf" +%s >/dev/null 2>&1; then date -u -d "$nf" +%s
  elif command -v gdate >/dev/null 2>&1; then gdate -u -d "$ts" +%s 2>/dev/null || gdate -u -d "$nf" +%s 2>/dev/null
  else return 1; fi
}




is_target_parent() { [[ "$1" == "DataProtectionServer" || "$1" == "DataProtectionAgent" || "$1" == "ScalableKafkaBridge" ]]; }

is_kind_allowed() {
  local k="$1"; [[ -z "$ALLOW" ]] && return 0
  IFS=',' read -r -a arr <<< "$ALLOW"
  for a in "${arr[@]}"; do [[ "$a" == "$k" ]] && return 0; done
  return 1
}

save_backup() {
  local _k="$1" _n="$2"
  local lc; lc=$(printf '%s' "$_k" | tr '[:upper:]' '[:lower:]')
  local path="$backup_dir/${lc}_${_n}.yaml"
  oc get -n "$NS" "$_k" "$_n" -o yaml > "$path" 2>/dev/null || true
  echo "$path"
}

trace_and_choose() {
  local pod="$1" k n chain
  k=$(oc -n "$NS" get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)
  n=$(oc -n "$NS" get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)
  [[ -z "$k" || -z "$n" ]] && { echo "UNKNOWN|$pod|Pod/$pod"; return; }
  chain="Pod/$pod -> $k/$n"
  if [[ "$k" == "ReplicaSet" ]]; then
    local dep; dep=$(oc -n "$NS" get rs "$n" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)
    if [[ -n "$dep" ]]; then k="Deployment"; n="$dep"; chain="Pod/$pod -> RS/$dep -> Deployment/$dep"; fi
  fi
  for _ in {1..10}; do
    local onk onn
    onk=$(oc -n "$NS" get "$k" "$n" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)
    onn=$(oc -n "$NS" get "$k" "$n" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)
    if [[ -z "$onk" || -z "$onn" ]]; then
      onk=$(oc -n "$NS" get "$k" "$n" -o jsonpath='{.metadata.labels.olm\.owner\.kind}' 2>/dev/null || true)
      onn=$(oc -n "$NS" get "$k" "$n" -o jsonpath='{.metadata.labels.olm\.owner}' 2>/dev/null || true)
    fi
    [[ -z "$onk" || -z "$onn" ]] && break
    chain="$chain -> $onk/$onn"
    if is_target_parent "$onk"; then echo "$k|$n|$chain"; return; fi
    k="$onk"; n="$onn"
  done
  echo "$k|$n|$chain"
}

find_pointer() {
  local kind="$1" name="$2" pod="$3" container="$4"
  case "$kind" in
    Deployment|StatefulSet|DaemonSet)
      oc -n "$NS" get "$kind" "$name" -o json 2>/dev/null |
        jq -r --arg c "$container" '
          (.spec.template.spec.containers // []) as $arr
          | ($arr | map(.name // "")) as $names
          | ($names | index($c)) as $i
          | if $i != null then
              "/spec/template/spec/containers/\($i)/resources"
            elif ($names | length) == 1 then
              "/spec/template/spec/containers/0/resources"
            else empty end
        ' | head -n1
      ;;
    DataProtectionApplication)
      oc -n "$NS" get "$kind" "$name" -o json 2>/dev/null |
        jq -r --arg c "$container" '
          .spec.configuration as $cfg
          | if ($c == "velero") and ($cfg.velero.podConfig.resourceAllocations? != null) then
              "/spec/configuration/velero/podConfig/resourceAllocations"
            elif ($c == "node-agent") and ($cfg.nodeAgent.podConfig.resourceAllocations? != null) then
              "/spec/configuration/nodeAgent/podConfig/resourceAllocations"
            else
              empty
            end
        ' | head -n1
      ;;
    Redis)
      oc -n "$NS" get "$kind" "$name" -o json 2>/dev/null |
        jq -r --arg pod "$pod" '
          .spec as $spec
          | if ($pod | test("(?i)master")) and ($spec.master.resources? != null) then
              "/spec/master/resources"
            elif ($pod | test("(?i)replica")) and ($spec.replica.resources? != null) then
              "/spec/replica/resources"
            else
              empty
            end
        ' | head -n1
      ;;
    ClusterServiceVersion)
      oc -n "$NS" get "$kind" "$name" -o json 2>/dev/null |
        jq -r --arg c "$container" --arg pod "$pod" '
          # Extract deployments array robustly
          (.spec.install? | objects | .spec? | objects | .deployments? // []) as $deps
          | if ($deps | type) != "array" or ($deps | length) == 0 then
              empty
            else
              # Stream entries; select first where pod contains deployment name
              $deps
              | to_entries[]
              | . as $e
              | ($e.value | objects | .name? // "") as $depName
              | select(($depName != "") and ($pod | contains($depName)))
              | ($e.key) as $d
              | ($e.value | objects | .spec? | objects | .template? | objects | .spec? | objects | .containers? // []) as $arr
              | ($arr | map(.name // "")) as $names
              | ($names | index($c)) as $i
              | if $i != null then
                  "/spec/install/spec/deployments/\($d)/spec/template/spec/containers/\($i)/resources"
                elif ($names | length) == 1 then
                  "/spec/install/spec/deployments/\($d)/spec/template/spec/containers/0/resources"
                else
                  empty
                end
            end
        ' | head -n1
      ;;
      KafkaBridge)
        oc -n "$NS" get "$kind" "$name" -o json 2>/dev/null |
          jq -r '
            .spec as $s
            | if ($s.resources? != null) then
                "/spec/resources"
              elif ($s.template? // {} | .bridgeContainer? // {} | .resources? != null) then
                "/spec/template/bridgeContainer/resources"
              else
                empty
              end
          ' | head -n1
      ;;
      KafkaNodePool)
        oc -n "$NS" get "$kind" "$name" -o json 2>/dev/null |
          jq -r '
            .spec as $s
            | if ($s.resources? != null) then
                "/spec/resources"
              elif ($s.template? // {} | .kafkaContainer? // {} | .resources? != null) then
                "/spec/template/kafkaContainer/resources"
              else
                empty
              end
          ' | head -n1
        ;;
      Kafka)
        oc -n "$NS" get "$kind" "$name" -o json 2>/dev/null |
          jq -r --arg c "$container" '
            if      $c == "kafka" then
              "/spec/kafka/resources"
            elif    $c == "guardian-kafka-cluster-kafka-exporter" then
              "/spec/kafkaExporter/resources"
            elif    $c == "topic-operator" then
              "/spec/entityOperator/topicOperator/resources"
            elif    $c == "user-operator" then
              "/spec/entityOperator/userOperator/resources"
            else
              empty
            end
          ' | head -n1
        ;;
    *) echo "" ;;
  esac
}

apply_patch() {
  local kind="$1" name="$2" pointer="$3" value_json="$4"
  local backup_file="" status="Failed"

  backup_file=$(save_backup "$kind" "$name")
  local patch="[ {\"op\":\"replace\",\"path\":\"$pointer\",\"value\": $value_json } ]"

  echo "oc patch $kind $name -n $NS --type=json -p '$patch'"
  echo "Patching $kind/$name at $pointer (replace)"

  local out rc
  if out=$(oc patch "$kind" "$name" -n "$NS" --type=json -p "$patch" 2>&1); then
    echo "$out"
    if grep -qi "(no change)" <<<"$out"; then
      status="Patched/No change"
    else
      status="Patched"
    fi
  else
    rc=$?
    status="Failed"
    echo "Patch failed for $kind/$name"
    echo "$out" >&2
  fi
  echo -e "$pod\t$container\t$kind/$name\t$status\t$backup_file" >>"$summary_file"
}


JSON_NS=$(jq -r '.namespace // empty' "$PATCH_FILE")
JSON_TS=$(jq -r '.created // empty' "$PATCH_FILE")
COUNT=$(jq -r '.containers | length' "$PATCH_FILE")
APPLIED_AT=$(jq -r '.applied_at // empty' "$PATCH_FILE")

[[ -n "$JSON_NS" && -n "$JSON_TS" ]] || { echo "ERROR: JSON missing 'namespace' or 'created'"; exit 1; }
[[ -n "$NS_OVERRIDE" && "$NS_OVERRIDE" != "$JSON_NS" ]] && { echo "ERROR: --namespace does not match JSON"; exit 1; }
NS="$JSON_NS"

if (( YES == 1 )) && [[ -n "$APPLIED_AT" ]]; then
  echo "ERROR: This patch JSON was already applied at ${APPLIED_AT}."
  echo " Re-generate a new Patch JSON after the next sheduled backups and apply."
  exit 1
fi

MAX_AGE_SECS=$(parse_duration_to_seconds "$MAX_AGE")
if ! ts_epoch=$(rfc3339_epoch "$JSON_TS"); then ts_epoch=$(date -u +%s); fi
now_epoch=$(date -u +%s); age=$(( now_epoch - ts_epoch ))
(( age > MAX_AGE_SECS )) && { echo "ERROR: Patch JSON is stale (age ${age}s > ${MAX_AGE_SECS}s)."; exit 1; }

echo "Namespace: $NS"
echo "Generated: $JSON_TS (age ${age}s <= ${MAX_AGE_SECS}s OK)"
echo "Entries  : $COUNT"
echo "Allowed  : ${ALLOW}"
echo "Note     : Only allowed kinds will be patched."
backup_dir="/tmp/resctl_$( ((YES)) && echo apply || echo sdr )_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"
summary_file="$backup_dir/summary.tsv"
echo -e "Pod\tContainer\tOwner\tStatus\tBackupFile" >"$summary_file"

now_ts=$(date -u +"%Y-%m-%dT%H:%M:%S.Z")

if (( YES == 1 )); then
  tmp_file="${PATCH_FILE}.stamped"
  jq --arg ts "$now_ts" '
    .applied_at = $ts
    | .created = $ts
  ' "$PATCH_FILE" > "$tmp_file" && mv "$tmp_file" "$PATCH_FILE"
fi


jq -c '.containers[]' "$PATCH_FILE" | while read -r entry; do
  pod=$(jq -r '.Pod' <<<"$entry")
  container=$(jq -r '.Container' <<<"$entry")
  
  # if [[ "$pod" == *"ibm-dataprotectionagent-controller-manager"* || \
  #       "$pod" == *"ibm-dataprotectionserver-controller-manager"* ]]; then
  #   echo "SKIP: Pod $pod (controller-manager)"
  #   continue
  # fi

  echo "----"
  echo "Target: Pod=$pod, Container=$container"
  info=$(trace_and_choose "$pod")
  owner_kind="${info%%|*}"; tmp="${info#*|}"; owner_name="${tmp%%|*}"; chain="${info##*|}"
  (( TRACE )) && echo "Trace: $chain  | chosen: $owner_kind/$owner_name"
  [[ -z "$owner_kind" || "$owner_kind" == "UNKNOWN" ]] && { echo "WARN: owner not resolved — skip"; continue; }
  if ! is_kind_allowed "$owner_kind"; then echo "SKIP: $owner_kind not allowed [${ALLOW}]"; continue; fi
  pointer=$(find_pointer "$owner_kind" "$owner_name" "$pod" "$container" || true)
  [[ -z "$pointer" ]] && { echo "WARN: container path not found for $owner_kind/$owner_name — skip"; continue; }
  value_json=$(jq -c '{requests:.requests, limits:.limits}' <<<"$entry")
  if (( YES == 0 )); then
    echo "oc patch $owner_kind $owner_name -n $NS --type=json --dry-run=server -p '[...]'"
    oc patch "$owner_kind" "$owner_name" -n "$NS" --type=json --dry-run=server -p "[{\"op\":\"replace\",\"path\":\"$pointer\",\"value\":$value_json}]" || true
  else
    apply_patch "$owner_kind" "$owner_name" "$pointer" "$value_json"
  fi
done

echo
if (( YES == 0 )); then
  echo "[SERVER DRY-RUN] Complete. Logs saved to: $backup_dir"
else
  echo
  echo "=== Summary (patched run) ==="
  if command -v column >/dev/null 2>&1; then column -t -s $'\t' "$summary_file"; else cat "$summary_file"; fi
fi

echo
echo "Backups saved to: $backup_dir"
cat <<EOF

------------------------------------------------------
NOTE:
  • Use the following command to watch pods rollout:
      watch -n 2 'oc get pods -n $NS -o wide'
  • Press Ctrl+C to stop watching.
------------------------------------------------------
EOF
