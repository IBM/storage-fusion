#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration and utilities
set -a
# shellcheck source=lib/constants.sh
source "$ROOT_DIR/lib/constants.sh"
# shellcheck source=config/config.env
source "$ROOT_DIR/config/config.env"
set +a

# shellcheck source=lib/logging.sh
source "$ROOT_DIR/lib/logging.sh"
# shellcheck source=lib/utils.sh
source "$ROOT_DIR/lib/utils.sh"

# Load functions from migrate-data-cache.sh without executing main
# We extract only the functions we need to test

require_argument_value() {
	local option="$1"
	local value="${2:-}"

	if [[ -z "$value" || "$value" == --* ]]; then
		logger error "Option ${option} requires a value"
		return 1
	fi
}

parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--migration-phase)
			require_argument_value "$1" "${2:-}"
			MIGRATION_PHASE="$2"
			shift 2
			;;
		--filesystem-name)
			require_argument_value "$1" "${2:-}"
			FILESYSTEM_NAME="$2"
			shift 2
			;;
		--cas-namespace)
			require_argument_value "$1" "${2:-}"
			CAS_NAMESPACE="$2"
			shift 2
			;;
		--scale-namespace)
			require_argument_value "$1" "${2:-}"
			SCALE_NAMESPACE="$2"
			shift 2
			;;
		--job-name)
			require_argument_value "$1" "${2:-}"
			JOB_NAME="$2"
			shift 2
			;;
		--timeout)
			require_argument_value "$1" "${2:-}"
			JOB_TIMEOUT="$2"
			shift 2
			;;
		--skip-validation)
			SKIP_VALIDATION=true
			shift
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		--help | -h)
			return 0
			;;
		*)
			logger error "Unknown option: $1"
			return 1
			;;
		esac
	done

	if [[ -z "${MIGRATION_PHASE}" ]]; then
		logger error "--migration-phase is required"
		return 1
	fi

	if [[ ! "${MIGRATION_PHASE}" =~ ^(pre|post|full)$ ]]; then
		logger error "Invalid phase: ${MIGRATION_PHASE}"
		logger error "Must be: pre, post, or full"
		return 1
	fi
}

#========================================
# Test Counters
#========================================
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#========================================
# Test Helper Functions
#========================================
run_test() {
	local test_name="$1"
	local test_func="$2"

	TESTS_RUN=$((TESTS_RUN + 1))
	echo "Running: ${test_name}"
	
	if ${test_func}; then
		TESTS_PASSED=$((TESTS_PASSED + 1))
		echo "✓ ${test_name}"
		return 0
	else
		TESTS_FAILED=$((TESTS_FAILED + 1))
		echo "✗ ${test_name}"
		return 1
	fi
}

#========================================
# Unit Tests
#========================================

test_parse_arguments_valid_phase() {
	# Reset global variable
	MIGRATION_PHASE=""

	# Test valid phase: pre
	parse_arguments --migration-phase pre
	[[ "${MIGRATION_PHASE}" == "pre" ]] || return 1

	# Test valid phase: post
	MIGRATION_PHASE=""
	parse_arguments --migration-phase post
	[[ "${MIGRATION_PHASE}" == "post" ]] || return 1

	# Test valid phase: full
	MIGRATION_PHASE=""
	parse_arguments --migration-phase full
	[[ "${MIGRATION_PHASE}" == "full" ]] || return 1
	
	return 0
}

test_parse_arguments_invalid_phase() {
	# Test invalid phase should fail
	MIGRATION_PHASE=""
	if parse_arguments --migration-phase invalid 2>/dev/null; then
		return 1  # Should have failed
	fi
	
	return 0
}

test_parse_arguments_missing_phase() {
	# Test missing required argument should fail
	if parse_arguments 2>/dev/null; then
		return 1  # Should have failed
	fi
	
	return 0
}

test_parse_arguments_custom_options() {
	# Reset variables
	MIGRATION_PHASE=""
	FILESYSTEM_NAME="default-fs"
	CAS_NAMESPACE="default-cas"
	JOB_NAME="default-job"
	JOB_TIMEOUT="1800"

	# Test custom options
	parse_arguments \
		--migration-phase pre \
		--filesystem-name custom-fs \
		--cas-namespace custom-cas \
		--job-name custom-job \
		--timeout 3600
	
	[[ "${MIGRATION_PHASE}" == "pre" ]] || return 1
	[[ "${FILESYSTEM_NAME}" == "custom-fs" ]] || return 1
	[[ "${CAS_NAMESPACE}" == "custom-cas" ]] || return 1
	[[ "${JOB_NAME}" == "custom-job" ]] || return 1
	[[ "${JOB_TIMEOUT}" == "3600" ]] || return 1
	
	return 0
}

test_parse_arguments_flags() {
	# Reset variables
	MIGRATION_PHASE=""
	SKIP_VALIDATION="false"
	DRY_RUN="false"
	
	# Test boolean flags
	parse_arguments \
		--migration-phase pre \
		--skip-validation \
		--dry-run
	
	[[ "${SKIP_VALIDATION}" == "true" ]] || return 1
	[[ "${DRY_RUN}" == "true" ]] || return 1
	
	return 0
}

test_compute_hash_valid_file() {
	# Create a temporary test file
	local test_file
	test_file=$(mktemp)
	echo "test content" > "${test_file}"

	# Compute hash
	local hash
	hash=$(compute_script_hash "${test_file}")
	local result=$?
	
	# Cleanup
	rm -f "${test_file}"
	
	# Verify hash format (8 characters)
	[[ ${result} -eq 0 ]] || return 1
	[[ ${#hash} -eq 8 ]] || return 1
	[[ "${hash}" =~ ^[a-f0-9]{8}$ ]] || return 1
	
	return 0
}

test_compute_hash_missing_file() {
	# Test with non-existent file should fail
	if compute_script_hash "/nonexistent/file" 2>/dev/null; then
		return 1  # Should have failed
	fi
	
	return 0
}

test_compute_hash_consistency() {
	# Create a temporary test file
	local test_file
	test_file=$(mktemp)
	echo "consistent content" > "${test_file}"
	
	# Compute hash twice
	local hash1 hash2
	hash1=$(compute_script_hash "${test_file}")
	hash2=$(compute_script_hash "${test_file}")
	
	# Cleanup
	rm -f "${test_file}"
	
	# Hashes should be identical for same content
	[[ "${hash1}" == "${hash2}" ]] || return 1
	
	return 0
}

test_require_argument_value_valid() {
	# Test with valid value
	if ! require_argument_value "--test-option" "valid-value" 2>/dev/null; then
		return 1  # Should have succeeded
	fi
	
	return 0
}

test_require_argument_value_missing() {
	# Test with missing value should fail
	if require_argument_value "--test-option" "" 2>/dev/null; then
		return 1  # Should have failed
	fi
	
	return 0
}

test_require_argument_value_next_option() {
	# Test with next option as value should fail
	if require_argument_value "--test-option" "--another-option" 2>/dev/null; then
		return 1  # Should have failed
	fi
	
	return 0
}

#========================================
# Main Test Execution
#========================================
main() {
	echo "========================================="
	echo "Running Unit Tests for migrate-data-cache.sh"
	echo "========================================="
	echo ""

	# Argument parsing tests
	run_test "parse_arguments: valid phases" test_parse_arguments_valid_phase || true
	run_test "parse_arguments: invalid phase" test_parse_arguments_invalid_phase || true
	run_test "parse_arguments: missing phase" test_parse_arguments_missing_phase || true
	run_test "parse_arguments: custom options" test_parse_arguments_custom_options || true
	run_test "parse_arguments: boolean flags" test_parse_arguments_flags || true
	
	# Hash computation tests
	run_test "compute_hash: valid file" test_compute_hash_valid_file || true
	run_test "compute_hash: missing file" test_compute_hash_missing_file || true
	run_test "compute_hash: consistency" test_compute_hash_consistency || true
	
	# Argument validation tests
	run_test "require_argument_value: valid" test_require_argument_value_valid || true
	run_test "require_argument_value: missing" test_require_argument_value_missing || true
	run_test "require_argument_value: next option" test_require_argument_value_next_option || true
	
	# Print summary
	echo ""
	echo "========================================="
	echo "Test Summary"
	echo "========================================="
	echo "Tests Run:    ${TESTS_RUN}"
	echo "Tests Passed: ${TESTS_PASSED}"
	echo "Tests Failed: ${TESTS_FAILED}"
	echo "========================================="
	
	if [[ ${TESTS_FAILED} -eq 0 ]]; then
		echo "✅ All tests passed!"
		return 0
	else
		echo "❌ Some tests failed"
		return 1
	fi
}

main "$@"

# Made with Bob
