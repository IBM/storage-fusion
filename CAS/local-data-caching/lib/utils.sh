#!/usr/bin/env bash

# GUARD CLAUSE: Prevent sourcing this file multiple times
if [[ -n "${LOADED_UTILS_SH:-}" ]]; then
    return 0
fi
export LOADED_UTILS_SH=1

help() {
	echo "Deploy and configure CNSA local Scale cluster on OCP using DF block disks"
	echo "----------------------------------------------------------------------"
	echo "Optional Inputs:"
	echo "  --filesystem-name        Name of the filesystem (default: $DEFAULT_FS_NAME)"
	echo "  --filesystem-capacity    Capacity in Gi (default: $DEFAULT_FS_SIZE)"
	echo ""
	echo "Requirements:"
	echo "  - Minimum OpenShift version: ${OCP_TOLERATED_VERSION}"
	echo "  - Cluster admin access"
	echo "  - At least 3 worker nodes with local disks"
	echo ""
	echo "Usage:"
	echo "bin/setup-data-cache.sh [--filesystem-name <name>] [--filesystem-capacity <Gi>]"
}

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
# Setup logging
#------------------------------------------------------------
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/setup-data-cache-$(date +'%Y%m%d_%H%M%S').log"

mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

logger info "Logging initialized. All output will be saved to $LOG_FILE"

#------------------------------------------------------------
# get_param_value: Small wrapper around grep+awk
#------------------------------------------------------------
get_param_value() {
	local yaml="$1"
	local param="$2"
	local value
	value="$(echo "${yaml}" | grep "${param}:" | awk '{print $2}')"

	echo "${param}: ${value}"
}

#------------------------------------------------------------
# _output_selector_values: Helper to output values for node selector operators
# Usage: _output_selector_values "operator" "key" "values"
#------------------------------------------------------------
_output_selector_values() {
	local operator="$1"
	local key="$2"
	local values="$3"

	if [[ "$key" == "$values" ]]; then
		logger error "match_expressions_list: Operator '$operator' requires values (format: key=value1,value2)"
		return 1
	fi

	echo "  values:"
	IFS=',' read -ra value_array <<< "$values"
	for value in "${value_array[@]}"; do
		echo "  - $value"
	done
}

#------------------------------------------------------------
# _process_single_operation: Process a single operation string
# Usage: _process_single_operation "op:label1=value1,label2=value2"
#------------------------------------------------------------
_process_single_operation() {
	local input="$1"
	local first="$2"

	local operator="${input%%:*}"
	local label_expr="${input#*:}"

	case "$operator" in
		In|NotIn|Exists|DoesNotExist|Gt|Lt) ;;
		*)
			logger error "match_expressions_list: Invalid operator '$operator'. Must be one of: In NotIn Exists DoesNotExist Gt Lt"
			return 1
			;;
	esac

	local key="${label_expr%%=*}"
	local values="${label_expr#*=}"

	[[ "$first" != "true" ]] && echo -n ","
	echo -n '{"key":"'"$key"'","operator":"'"$operator"'"'

	if [[ "$operator" == "In" || "$operator" == "NotIn" || "$operator" == "Gt" || "$operator" == "Lt" ]]; then
		if [[ "$key" == "$values" ]]; then
			logger error "match_expressions_list: Operator '$operator' requires values (format: key=value1,value2)"
			return 1
		fi
		echo -n ',"values":['
		IFS=',' read -ra value_array <<< "$values"
		local val_count=0
		for value in "${value_array[@]}"; do
			[[ $val_count -gt 0 ]] && echo -n ","
			echo -n '"'"$value"'"'
			((val_count++))
		done
		echo -n ']'
	fi
	echo -n '}'
}

#------------------------------------------------------------
# match_expressions_list: Convert string to K8s node selector matchExpressions JSON
# Usage: match_expressions_list "op1:label1=value1,value2;op2:label2=value3;..."
# Output: JSON array for use with yq or other tools
# Supported operators: In, NotIn, Exists, DoesNotExist, Gt, Lt
# Multiple operations can be separated by semicolons (;)
#
# NOTE: Input must not contain whitespace - will error if found
#
# Examples:
#   match_expressions_list "Exists:node-role.kubernetes.io/worker"
#   match_expressions_list "NotIn:beta.kubernetes.io/instance-type=gx3d.160x1792.8h100,another.type"
#   match_expressions_list "In:region=us-east,us-west"
#   match_expressions_list "Exists:node-role.kubernetes.io/worker;NotIn:beta.kubernetes.io/instance-type=gx3d.160x1792.8h100"
#------------------------------------------------------------
match_expressions_list() {
	local input="$1"

	if [[ -z "$input" ]]; then
		logger error "match_expressions_list: No input provided"
		return 1
	fi

	if [[ "$input" =~ [[:space:]] ]]; then
		logger error "match_expressions_list: Input contains whitespace. Please remove all spaces."
		return 1
	fi

	echo -n '['
	IFS=';' read -ra operations <<< "$input"
	local op_count=0
	for operation in "${operations[@]}"; do
		_process_single_operation "$operation" "$([[ $op_count -eq 0 ]] && echo "true" || echo "false")" || return 1
		((++op_count))
	done
	echo ']'
}

#------------------------------------------------------------
# wait_for_condition: Wait for a condition to be met with rewritable progress
# Usage: wait_for_condition "message" timeout "command"
# Parameters:
#   msg: Display message for the wait operation
#   timeout: Timeout in seconds
#   condition: Shell command that returns 0 when condition is met
# Returns: 0 on success, 1 on timeout
#------------------------------------------------------------
wait_for_condition() {
	local msg="$1"
	local timeout="$2"
	local condition="$3"

	if [[ -z "$msg" || -z "$timeout" || -z "$condition" ]]; then
		logger error "wait_for_condition: Missing required parameters (msg, timeout, condition)"
		return 1
	fi

	logger -n info "${msg}... "

	local retry_count=0
	local max_retries=$((timeout / RETRY_INTERVAL))
	local start_time
	start_time=$(date +%s)

	local prev_progress_len=0
	while true; do
		local now_time
		now_time=$(date +%s)
		local elapsed=$((now_time - start_time))
		if eval "$condition" &>/dev/null; then
			echo >&2
			logger success "${msg}... DONE after ${elapsed}s."
			return 0
		fi

		((++retry_count))
		if [[ $max_retries -ne 0 ]] && [[ $retry_count -ge $max_retries ]]; then
			echo >&2
			logger error "Timeout: ${msg} - condition not met after ${timeout} seconds."
			return 1
		fi

		local progress
		if [[ $timeout -eq 0 ]]; then
			progress="(${elapsed}s)"
		else
			progress="(${elapsed}s/${timeout}s)"
		fi

		# Move cursor back by exact length of previous progress string
		if [[ $prev_progress_len -gt 0 ]]; then
			printf "\b%.0s" $(seq 1 "$prev_progress_len") >&2
		fi
		echo -ne "${progress}" >&2
		prev_progress_len=${#progress}
		sleep "$RETRY_INTERVAL"
	done
}

