#!/usr/bin/env bash
# lib.sh — shared helpers for the install-bob-onprem scripts (source it, do not run it).
# Requires: oc, jq, python3 (+ PyYAML for model-config parsing), curl.

if [ -t 1 ]; then
  C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_FAIL=$'\e[31m'; C_HEAD=$'\e[1;36m'; C_DIM=$'\e[2m'; C_OFF=$'\e[0m'
else
  C_OK=""; C_WARN=""; C_FAIL=""; C_HEAD=""; C_DIM=""; C_OFF=""
fi
# results are tallied in a file so that ok/warn/fail also count inside `… | while read` subshells
TALLY=$(mktemp "${TMPDIR:-/tmp}/bobchk.XXXXXX")

section() { printf '\n%s== %s ==%s\n' "$C_HEAD" "$*" "$C_OFF"; }
ok()      { echo P >>"$TALLY"; printf '  %sPASS%s  %s\n' "$C_OK"   "$C_OFF" "$*"; }
warn()    { echo W >>"$TALLY"; printf '  %sWARN%s  %s\n' "$C_WARN" "$C_OFF" "$*"; }
fail()    { echo F >>"$TALLY"; printf '  %sFAIL%s  %s\n' "$C_FAIL" "$C_OFF" "$*"; }
info()    { printf '  %s....%s  %s\n' "$C_DIM" "$C_OFF" "$*"; }
summary() {
  local p w f
  p=$(grep -c P "$TALLY"); w=$(grep -c W "$TALLY"); f=$(grep -c F "$TALLY")
  printf '\n%sSummary:%s %d pass, %d warn, %d fail\n' "$C_HEAD" "$C_OFF" "$p" "$w" "$f"
  [ "$f" -eq 0 ]
}

need() { for b in "$@"; do command -v "$b" >/dev/null 2>&1 || { echo "missing required tool: $b" >&2; exit 2; }; done; }

# free local TCP port
free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }

# port_forward <ns> <svc> <remote-port>  → echoes local port
# (PIDs go to a file because callers use lp=$(port_forward …), i.e. a subshell)
PF_FILE=$(mktemp "${TMPDIR:-/tmp}/bobpf.XXXXXX")
port_forward() {
  local ns=$1 svc=$2 rport=$3 lport
  lport=$(free_port)
  oc port-forward -n "$ns" "svc/$svc" "$lport:$rport" >/dev/null 2>&1 &
  echo $! >>"$PF_FILE"
  for _ in $(seq 1 40); do
    (echo >"/dev/tcp/127.0.0.1/$lport") 2>/dev/null && { echo "$lport"; return 0; }
    sleep 0.25
  done
  return 1
}
cleanup_pf() {
  [ -f "$PF_FILE" ] && while read -r p; do kill "$p" 2>/dev/null; done <"$PF_FILE"
  rm -f "$TALLY" "$PF_FILE"
}
trap cleanup_pf EXIT

# host of the Bob API route (api.bob.<ns>.<apps-domain>)
bob_api_host() {
  oc get route -n "$1" -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' 2>/dev/null | grep -m1 '^api\.'
}
bob_ui_host() {
  oc get route -n "$1" -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' 2>/dev/null | grep -m1 '^bob\.'
}

# effective Bifrost config (the file bob-inference actually loads) → stdout
#   honours an init container that writes BIFROST_CONFIG_B64, if the deployment has one
bifrost_effective_config() {
  local ns=$1 b64
  b64=$(oc get deploy bob-inference -n "$ns" -o json 2>/dev/null | jq -r '
    [.spec.template.spec.initContainers[]? | .env[]? | select(.name=="BIFROST_CONFIG_B64") | .value][0] // empty')
  if [ -n "$b64" ]; then
    echo "# source: initContainer BIFROST_CONFIG_B64" ; echo "$b64" | base64 -d
  else
    echo "# source: ConfigMap bob-inference-config"
    oc get cm bob-inference-config -n "$ns" -o jsonpath='{.data.config\.yaml}'
  fi
}

# credentials-free Redis CLI inside the admin Redis pod: redis_cmd <ns> <redis-cli args…>
redis_exec() {
  local ns=$1; shift
  local auth; auth=$(oc get secret bob-admin-redis -n "$ns" -o jsonpath='{.data.auth}' | base64 -d)
  oc exec -n "$ns" bob-admin-redis-server-0 -c redis -- sh -c \
    "export REDISCLI_AUTH='$auth'; redis-cli -h bob-admin-redis-master-svc.$ns.svc.cluster.local -p 6380 --tls --insecure --no-auth-warning $*" 2>/dev/null
}

# stale_key_deploys <ns> → deployments whose pods started BEFORE bob-internal-tls was (re)issued.
# bob-authn signs session JWTs with bob-internal-tls/tls.key and the gateway verifies with bob-jwt-tls;
# both are loaded at process start. When the operator rotates the cert (e.g. after enabling metering,
# which adds bob-metering to the SANs) running pods keep the OLD key → Admin UI 401
# "Token verification failed" (user lands on /admin/subscription with nothing loaded). Fix: restart them.
STALE_KEY_DEPLOYS="bob-authn bob-authz bob-admin bob-admin-ui bob-gateway"
stale_key_deploys() {
  local ns=$1 nb nbs d st sts
  nb=$(oc get secret bob-internal-tls -n "$ns" -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -startdate 2>/dev/null | cut -d= -f2)
  [ -n "$nb" ] || return 0
  nbs=$(python3 -c "import sys,datetime;print(int(datetime.datetime.strptime(sys.argv[1],'%b %d %H:%M:%S %Y GMT').replace(tzinfo=datetime.timezone.utc).timestamp()))" "$nb")
  for d in $STALE_KEY_DEPLOYS; do
    sel=$(oc get deploy "$d" -n "$ns" -o json 2>/dev/null | jq -r '.spec.selector.matchLabels|to_entries|map("\(.key)=\(.value)")|join(",")') || continue
    [ -n "$sel" ] || continue
    for st in $(oc get pods -n "$ns" -l "$sel" --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.status.startTime}{"\n"}{end}'); do
      sts=$(python3 -c "import sys,datetime;print(int(datetime.datetime.strptime(sys.argv[1],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()))" "$st")
      [ "$sts" -lt "$nbs" ] && { echo "$d"; break; }
    done
  done
}
