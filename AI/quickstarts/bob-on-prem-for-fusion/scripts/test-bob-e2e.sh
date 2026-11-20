#!/usr/bin/env bash
# =============================================================================
# test-bob-e2e.sh — end-to-end test with the real Bob Shell CLI (gateway → authz → Bifrost → model → metering)
#
# Usage: test-bob-e2e.sh <bob-namespace> ["prompt"] [--no-tools]
#   BOB_API_KEY / NODE_EXTRA_CA_CERTS / BOB_GATEWAY_URL are taken from the environment if set,
#   otherwise derived from the cluster (admin key from bob-admin-secret, CA from bob-external-tls like `bobctl get-ca-cert`).
#
# Runs 2 prompts:  1) plain chat   2) a prompt that forces a tool call (read a local file) — this is
# what breaks when vLLM lacks --enable-auto-tool-choice. Then checks bob-inference/gateway logs for
# errors in the test window and shows the bobcoin counters before/after.
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
need oc bob jq
NS=; PROMPT="Tell me a short joke about IBM."; TOOLS=1; P=()
for a in "$@"; do case "$a" in --no-tools) TOOLS=0;; *) P+=("$a");; esac; done
[ ${#P[@]} -ge 1 ] && NS=${P[0]}; [ ${#P[@]} -ge 2 ] && PROMPT=${P[1]}
[ -n "$NS" ] || { echo "Usage: $0 <bob-namespace> [\"prompt\"] [--no-tools]   (find it with: oc get bob -A)" >&2; exit 2; }

section "Client environment"
unset BOBSHELL_API_KEY CUSTOM_BASE_URL          # legacy vars conflict with BOB_API_KEY
if [ -z "${BOB_GATEWAY_URL:-}" ]; then
  H=$(bob_api_host "$NS"); [ -n "$H" ] || { fail "no api.* route in $NS"; summary; exit 1; }
  export BOB_GATEWAY_URL="https://$H"
fi
if [ -z "${BOB_API_KEY:-}" ]; then
  BOB_API_KEY=$(oc get secret bob-admin-secret -n "$NS" -o jsonpath='{.data.BOB_API_KEY}' | base64 -d); export BOB_API_KEY
fi
if [ -z "${NODE_EXTRA_CA_CERTS:-}" ] || [ ! -f "${NODE_EXTRA_CA_CERTS:-/nonexistent}" ]; then
  CA="$(pwd)/bob-ca.crt"
  # same CA as `bobctl get-ca-cert` (bob-external-tls); older installs only have bob-internal-ca-key-pair
  oc get secret bob-external-tls -n "$NS" -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d >"$CA"
  grep -q BEGIN "$CA" 2>/dev/null || oc get secret bob-internal-ca-key-pair -n "$NS" -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CA"
  export NODE_EXTRA_CA_CERTS="$CA"
fi
[ -n "$BOB_API_KEY" ] && ok "BOB_API_KEY set (${BOB_API_KEY:0:22}…)" || fail "BOB_API_KEY empty"
ok "BOB_GATEWAY_URL=$BOB_GATEWAY_URL"
ok "NODE_EXTRA_CA_CERTS=$NODE_EXTRA_CA_CERTS"
code=$(curl -s --cacert "$NODE_EXTRA_CA_CERTS" -o /dev/null -w '%{http_code}' "$BOB_GATEWAY_URL/")
[ "$code" != 000 ] && ok "gateway reachable with CA (HTTP $code)" || fail "gateway unreachable / TLS error with this CA"

usage_now() { redis_exec "$NS" HGET "$(redis_exec "$NS" --scan --pattern 'Subscription:*' | head -1)" usage 2>/dev/null; }
U0=$(usage_now); T0=$(date -u +%s)

WORK=$(mktemp -d); trap 'rm -rf "$WORK"; cleanup_pf' EXIT
section "Prompt 1 — chat: $PROMPT"
OUT=$(cd "$WORK" && bob --accept-license -p "$PROMPT" 2>&1); echo "$OUT" | tail -12 | sed 's/^/    /'
echo "$OUT" | grep -q "Error:" && fail "prompt 1 failed" || ok "prompt 1 answered"

if [ $TOOLS = 1 ]; then
  section "Prompt 2 — tool call (read a file)"
  printf 'alpha\nbeta\ngamma\n' >"$WORK/words.txt"
  OUT=$(cd "$WORK" && bob --accept-license -p "Read the file words.txt in the current directory and reply with its second line only." 2>&1)
  echo "$OUT" | tail -10 | sed 's/^/    /'
  TC=$(echo "$OUT" | awk -F: '/Tool Calls/{gsub(/ /,"",$2); print $2}')
  if echo "$OUT" | grep -q "Error:"; then fail "prompt 2 failed — typical cause: vLLM without --enable-auto-tool-choice (doc-troubleshooting-inference.md)"
  elif [ "${TC:-0}" -ge 1 ]; then ok "tool call executed (Tool Calls: $TC)"
  else warn "answered without a tool call (model chose not to use tools)"; fi
fi

section "Server-side logs during the test"
S=$(( $(date -u +%s) - T0 + 5 ))s
E=$(oc logs -n "$NS" deploy/bob-inference -c runtime --since="$S" 2>/dev/null | grep -E 'returned error|error while executing|Failed to send metering')
[ -z "$E" ] && ok "bob-inference: no upstream/metering errors" || { fail "bob-inference errors:"; echo "$E" | jq -r .msg 2>/dev/null | cut -c1-220 | sed 's/^/      /'; }
G=$(oc logs -n "$NS" deploy/bob-gateway --since="$S" 2>/dev/null | grep -c 'INFERENCE ERROR')
[ "$G" -eq 0 ] && ok "bob-gateway: no [INFERENCE ERROR]" || fail "bob-gateway: $G [INFERENCE ERROR]"

section "Metering"
sleep 2; U1=$(usage_now)
if [ -n "$U1" ] && [ "${U1:-0}" -gt "${U0:-0}" ]; then ok "subscription usage ${U0:-0} → $U1 credits (+$(( U1 - ${U0:-0} )) = $(python3 -c "print(round(($U1-${U0:-0})/1e6,4))") bobcoins)"
else warn "usage counters did not move (${U0:-none} → ${U1:-none}) — run scripts/enable-metering.sh $NS"; fi
summary
