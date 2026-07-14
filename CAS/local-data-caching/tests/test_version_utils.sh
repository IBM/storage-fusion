#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/logging.sh
source "$ROOT_DIR/lib/logging.sh"
# shellcheck source=lib/utils.sh
source "$ROOT_DIR/lib/utils.sh"
# shellcheck source=modules/scale_utils.sh
source "$ROOT_DIR/modules/scale_utils.sh"

# ---------------------------------------------------------------------------
# Minimal test harness
# ---------------------------------------------------------------------------
PASS=0
FAIL=0

assert_eq() {
	local desc="$1"
	local expected="$2"
	local actual="$3"
	if [[ "${expected}" == "${actual}" ]]; then
		echo "  PASS: ${desc}"
		((++PASS))
	else
		echo "  FAIL: ${desc} — expected '${expected}', got '${actual}'"
		((++FAIL))
	fi
}

# ---------------------------------------------------------------------------
# version_gte tests
# ---------------------------------------------------------------------------
echo "version_gte"

assert_eq "equal versions (1.1.5 >= 1.1.5)"          true  "$(version_gte "1.1.5"  "1.1.5")"
assert_eq "patch greater (1.1.6 >= 1.1.5)"           true  "$(version_gte "1.1.6"  "1.1.5")"
assert_eq "minor greater (1.2.0 >= 1.1.5)"           true  "$(version_gte "1.2.0"  "1.1.5")"
assert_eq "major greater (2.0.0 >= 1.1.5)"           true  "$(version_gte "2.0.0"  "1.1.5")"
assert_eq "patch less (1.1.4 < 1.1.5)"               false "$(version_gte "1.1.4"  "1.1.5")"
assert_eq "minor less (1.0.9 < 1.1.5)"               false "$(version_gte "1.0.9"  "1.1.5")"
assert_eq "major less (0.9.0 < 1.1.5)"               false "$(version_gte "0.9.0"  "1.1.5")"

assert_eq "equal CNSA CSV (60.1.0 >= 60.1.0)"        true  "$(version_gte "60.1.0" "60.1.0")"
assert_eq "CNSA patch greater (60.1.1 >= 60.1.0)"    true  "$(version_gte "60.1.1" "60.1.0")"
assert_eq "CNSA minor greater (60.2.0 >= 60.1.0)"    true  "$(version_gte "60.2.0" "60.1.0")"
assert_eq "CNSA less (60.0.9 < 60.1.0)"              false "$(version_gte "60.0.9" "60.1.0")"

assert_eq "equal ODF (4.21 >= 4.21)"                 true  "$(version_gte "4.21"   "4.21")"
assert_eq "ODF minor greater (4.21 >= 4.20)"         true  "$(version_gte "4.21"   "4.20")"
assert_eq "ODF minor less (4.20 < 4.21)"             false "$(version_gte "4.20"   "4.21")"

# ---------------------------------------------------------------------------
# cnsa_product_to_csv tests
# ---------------------------------------------------------------------------
echo "cnsa_product_to_csv"

assert_eq "6.0.0.0 -> 60.0.0"  "60.0.0" "$(cnsa_product_to_csv "6.0.0.0")"
assert_eq "6.0.0.5 -> 60.0.5"  "60.0.5" "$(cnsa_product_to_csv "6.0.0.5")"
assert_eq "6.0.1.0 -> 60.1.0"  "60.1.0" "$(cnsa_product_to_csv "6.0.1.0")"
assert_eq "6.0.1.2 -> 60.1.2"  "60.1.2" "$(cnsa_product_to_csv "6.0.1.2")"
assert_eq "6.0.2.0 -> 60.2.0"  "60.2.0" "$(cnsa_product_to_csv "6.0.2.0")"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]]
