#!/usr/bin/env bash

# Test script for wait_for_condition function

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source required files
# shellcheck source=lib/constants.sh
source "${PROJECT_ROOT}/lib/constants.sh"
# shellcheck source=lib/utils.sh
source "${PROJECT_ROOT}/lib/utils.sh"

echo "=========================================="
echo "Testing wait_for_condition function"
echo "=========================================="
echo ""

RETRY_INTERVAL=5
echo "Using RETRY_INTERVAL: ${RETRY_INTERVAL}s"

# Test 1: Successful condition (file creation)
echo "Test 1: Waiting for file creation (should succeed)"
TEST_FILE="/tmp/test_wait_condition_$$"
rm -f "${TEST_FILE}"

# Create file in background after 3 seconds
(sleep 13 && touch "${TEST_FILE}") &

if wait_for_condition "Waiting for test file" 30 "test -f ${TEST_FILE}"; then
	echo "✅ Test 1 PASSED: Condition met successfully"
	rm -f "${TEST_FILE}"
else
	echo "❌ Test 1 FAILED: Condition should have been met"
	exit 1
fi
echo ""

# Test 2: Zero timeout (should wait indefinitely)
echo "Test 2: Zero timeout (should wait indefinitely)"
TEST_FILE_ZERO="/tmp/test_wait_zero_$$"
rm -f "${TEST_FILE_ZERO}"

# Create file in background after 3 seconds (but timeout is 0)
(sleep 3 && touch "${TEST_FILE_ZERO}") &

if wait_for_condition "Waiting for test file with zero timeout" 0 "test -f ${TEST_FILE_ZERO}"; then
	echo "✅ Test 2 PASSED: Waited indefinitely"
	rm -f "${TEST_FILE_ZERO}"
else
	echo "❌ Test 2 FAILED: Should have waited indefinitely"
	rm -f "${TEST_FILE_ZERO}"
	exit 1
fi
echo ""

# Test 3: Timeout condition
echo "Test 3: Waiting for non-existent file (should timeout)"
TEST_FILE_TIMEOUT="/tmp/test_wait_timeout_nonexistent_$$"

if wait_for_condition "Waiting for non-existent file" 15 "test -f ${TEST_FILE_TIMEOUT}"; then
	echo "❌ Test 3 FAILED: Should have timed out"
	exit 1
else
	echo "✅ Test 3 PASSED: Timed out as expected"
fi
echo ""

# Test 4: Immediate success
echo "Test 4: Condition already met (should succeed immediately)"
TEST_FILE_IMMEDIATE="/tmp/test_wait_immediate_$$"
touch "${TEST_FILE_IMMEDIATE}"

if wait_for_condition "Waiting for existing file" 30 "test -f ${TEST_FILE_IMMEDIATE}"; then
	echo "✅ Test 4 PASSED: Immediate success"
	rm -f "${TEST_FILE_IMMEDIATE}"
else
	echo "❌ Test 4 FAILED: Should have succeeded immediately"
	exit 1
fi
echo ""

# Test 5: Missing parameters
echo "Test 5: Missing parameters (should fail)"
if wait_for_condition "Only message" "" ""; then
	echo "❌ Test 5 FAILED: Should have failed with missing parameters"
	exit 1
else
	echo "✅ Test 5 PASSED: Failed as expected with missing parameters"
fi
echo ""

# Test 6: Command-based condition
echo "Test 6: Command-based condition (process check)"
# Start a background process
sleep 30 &
BG_PID=$!

if wait_for_condition "Waiting for background process" 20 "ps -p ${BG_PID}"; then
	echo "✅ Test 6 PASSED: Process found"
	kill "${BG_PID}" 2>/dev/null || true
else
	echo "❌ Test 6 FAILED: Process should have been found"
	kill "${BG_PID}" 2>/dev/null || true
	exit 1
fi
echo ""

echo "=========================================="
echo "All tests completed successfully!"
echo "=========================================="

# Made with Bob
