#!/usr/bin/env bash
# =============================================================================
# create-bob-user.sh — create a local Bob login (Keycloak realm "bob") with its own password
#
# Usage: create-bob-user.sh <instance-namespace> <email> <username> [--admin] [--out <file>] [--delete]
#   --admin   also add the user to group bob-admins (Admin UI access). Every user is put in bob-users.
#   --out     write the generated password to <file> (chmod 600). Without it the password is printed once.
#   --delete  remove the user from Keycloak instead (no password needed).
#
# Why this script: `bobctl configure-idp` only creates ONE Keycloak user ("bob-admin", for the first
# adminEmails entry, without a password). Emails added later are registered as Bob admins in Postgres
# but get NO Keycloak login. The email's domain must be in the BobIdp `domains` list, otherwise the
# login page answers "Client not found" — run configure-idp first.
#
# How: kcadm.sh inside bob-keycloak-0, master realm, credentials from secret bob-keycloak-initial-admin.
#      HOME=/tmp + --config /tmp/… are required (default config path is read-only); the admin session is
#      short-lived, so login and all changes run in ONE exec. Verified with a password-grant token request.
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
need oc python3 curl
ADMIN=0; OUT=""; DEL=0; POS=()
while [ $# -gt 0 ]; do case "$1" in --admin) ADMIN=1;; --delete) DEL=1;; --out) OUT="$2"; shift;; *) POS+=("$1");; esac; shift; done
[ ${#POS[@]} -ge 3 ] || { sed -n 3,19p "$0"; exit 2; }
NS=${POS[0]}; EM=${POS[1]}; UN=${POS[2]}

DOM=${EM#*@}
section "Checks ($NS)"
DOMS=$(oc get bobidp -n "$NS" -o jsonpath='{.items[0].spec.domains}' 2>/dev/null)
echo "$DOMS" | grep -q "\"$DOM\"" && ok "domain $DOM is in the BobIdp domains" \
  || warn "domain $DOM is NOT in the BobIdp domains ($DOMS) — add it with bobctl configure-idp or the login fails"
KU=$(oc get secret bob-keycloak-initial-admin -n "$NS" -o jsonpath='{.data.username}' | base64 -d)
KP=$(oc get secret bob-keycloak-initial-admin -n "$NS" -o jsonpath='{.data.password}' | base64 -d)
[ -n "$KU" ] && ok "Keycloak master admin from bob-keycloak-initial-admin" || { fail "secret bob-keycloak-initial-admin missing"; summary; exit 1; }

NP=""
[ $DEL = 0 ] && NP=$(python3 -c 'import secrets,string;a=string.ascii_letters+string.digits;print("Bob-"+"".join(secrets.choice(a) for _ in range(16))+"!9")')

section "Keycloak realm bob"
RES=$(oc exec -n "$NS" bob-keycloak-0 -c keycloak -- env HOME=/tmp KU="$KU" KP="$KP" NP="$NP" EM="$EM" UN="$UN" ADM="$ADMIN" DEL="$DEL" bash -c '
K=/opt/keycloak/bin/kcadm.sh; C="--config /tmp/kc-cbu.cfg"; trap "rm -f /tmp/kc-cbu.cfg" EXIT
$K config credentials $C --server http://localhost:8080 --realm master --user "$KU" --password "$KP" >/dev/null 2>&1 || { echo LOGIN_FAIL; exit 1; }
uid(){ $K get users -r bob $C -q username="$UN" --fields id 2>/dev/null | tr -d "\n " | sed -n "s/.*\"id\":\"\([^\"]*\)\".*/\1/p"; }
gid(){ $K get groups -r bob $C -q search="$1" --fields id,name 2>/dev/null | tr -d "\n " | sed -n "s/.*\"id\":\"\([^\"]*\)\",\"name\":\"$1\".*/\1/p"; }
ID=$(uid)
if [ "$DEL" = 1 ]; then [ -n "$ID" ] && $K delete users/$ID -r bob $C >/dev/null 2>&1 && echo DELETED || echo NOT_FOUND; exit 0; fi
if [ -z "$ID" ]; then
  # firstName/lastName are required by the realm user profile — without them the account is
  # "not fully set up" and every login (also the password grant) answers HTTP 400
  $K create users -r bob $C -s username="$UN" -s email="$EM" -s emailVerified=true -s enabled=true \
     -s firstName="${UN%%-*}" -s lastName="${UN#*-}" >/dev/null 2>&1 && echo CREATED
  ID=$(uid)
else echo EXISTS; fi
[ -z "$ID" ] && { echo NO_USER; exit 1; }
$K set-password -r bob $C --userid "$ID" --new-password "$NP" >/dev/null 2>&1 && echo PW_OK
GR="bob-users"; [ "$ADM" = 1 ] && GR="bob-users bob-admins"
for g in $GR; do G=$(gid $g); [ -n "$G" ] && $K update users/$ID/groups/$G -r bob $C -s realm=bob -s userId=$ID -s groupId=$G -n >/dev/null 2>&1; done
echo "GROUPS=$($K get users/$ID/groups -r bob $C --fields name 2>/dev/null | tr -d "\n ")"
' 2>&1)
case "$RES" in *LOGIN_FAIL*) fail "kcadm login to the master realm failed"; summary; exit 1;; esac
if [ $DEL = 1 ]; then
  case "$RES" in *DELETED*) ok "deleted $UN";; *) warn "$UN not found";; esac; summary; exit 0
fi
case "$RES" in *CREATED*) ok "created $UN <$EM>";; *EXISTS*) ok "$UN already existed — password reset";; *) fail "user not created: $RES"; summary; exit 1;; esac
case "$RES" in *PW_OK*) ok "password set";; *) fail "set-password failed"; summary; exit 1;; esac
ok "$(echo "$RES" | grep GROUPS=)"

section "Login test (password grant against https://bob-keycloak.${NS}.<apps>)"
HOST=$(oc get route -n "$NS" -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' | grep '^bob-keycloak\.' | head -1)
CA=$(mktemp); oc get secret bob-external-tls -n "$NS" -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CA"
code=$(curl -s --cacert "$CA" -o /dev/null -w '%{http_code}' --max-time 20 "https://$HOST/realms/bob/protocol/openid-connect/token" \
  --data-urlencode grant_type=password --data-urlencode client_id=admin-cli \
  --data-urlencode "username=$UN" --data-urlencode "password=$NP")
rm -f "$CA"
[ "$code" = 200 ] && ok "token issued for $UN" || fail "token request HTTP $code"

if [ -n "$OUT" ]; then
  umask 077; printf 'BOB_USER_NAMESPACE=%s\nBOB_USER_USERNAME=%s\nBOB_USER_EMAIL=%s\nBOB_USER_PASSWORD=%s\n' "$NS" "$UN" "$EM" "$NP" >"$OUT"
  chmod 600 "$OUT"; ok "password written to $OUT (chmod 600)"
else
  info "password (shown once): $NP"
fi
summary
