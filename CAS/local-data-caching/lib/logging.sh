#!/usr/bin/env bash

# Derive the caller's script name (without .sh) before the guard clause so
# it is captured on first source. Caller may pre-set LOG_FILE_PREFIX to override.
LOG_FILE_PREFIX="${LOG_FILE_PREFIX:-$(basename "${BASH_SOURCE[1]:-logging}" .sh)}"

# GUARD CLAUSE: Prevent sourcing this file multiple times
if [[ -n "${LOADED_LOGGING_SH:-}" ]]; then
    return 0
fi
export LOADED_LOGGING_SH=1

#------------------------------------------------------------
# Logger function
# Usage: logger [-n] <level> <message>
# Options: -n (no newline)
# Levels: info, warn, error, success
#------------------------------------------------------------
logger() {
	local no_newline=false
	if [[ "$1" == "-n" ]]; then
		no_newline=true
		shift
	fi

	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp=$(date +"%Y-%m-%d %H:%M:%S")
	local newline="\n"
	[[ "$no_newline" == true ]] && newline=""

	case "$level" in
	info)
		echo -ne "[$timestamp] ℹ️  INFO: $message${newline}" >&2
		;;
	warn)
		echo -ne "[$timestamp] ⚠️  WARNING: $message${newline}" >&2
		;;
	error)
		echo -ne "[$timestamp] ❌ ERROR: $message${newline}" >&2
		;;
	success)
		echo -ne "[$timestamp] ✅ SUCCESS: $message${newline}" >&2
		;;
	esac
}

#------------------------------------------------------------
# Setup logging (skipped when LOG_TO_FILE=false)
#------------------------------------------------------------
if [[ "${LOG_TO_FILE:-true}" == "true" ]]; then
    LOG_DIR="./logs"
    LOG_FILE="$LOG_DIR/${LOG_FILE_PREFIX}-$(date +'%Y%m%d_%H%M%S').log"

    mkdir -p "$LOG_DIR"

    exec > >(tee -a "$LOG_FILE") 2>&1

    logger info "Logging initialized. All output will be saved to $LOG_FILE"
fi
