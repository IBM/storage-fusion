#!/usr/bin/env bash

set -eu

help() {
	echo "Deploy and configure CNSA local Scale cluster on OCP using DF block disks"
	echo "----------------------------------------------------------------------"
	echo "Optional Inputs:"
	echo "  --filesystem-name        Name of the filesystem (default: $DEFAULT_FS_NAME)"
	echo "  --filesystem-capacity    Capacity in Gi (default: $DEFAULT_FS_SIZE)"
	echo ""
	echo "Requirements:"
	echo "  - Minimum OpenShift version: ${OCP_TARGET_VERSION}"
	echo "  - Cluster admin access"
	echo "  - At least 3 worker nodes with local disks"
	echo ""
	echo "Usage:"
	echo "bin/setup-data-cache.sh [--filesystem-name <name>] [--filesystem-capacity <Gi>]"
}

#------------------------------------------------------------
# Logger function
# Usage: logger <level> <message>
# Levels: info, warn, error, success
#------------------------------------------------------------
logger() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp=$(date +"%Y-%m-%d %H:%M:%S")

	case "$level" in
	info)
		echo -e "[$timestamp] ℹ️  INFO: $message" >&2
		;;
	warn)
		echo -e "[$timestamp] ⚠️  WARNING: $message" >&2
		;;
	error)
		echo -e "[$timestamp] ❌ ERROR: $message" >&2
		;;
	success)
		echo -e "[$timestamp] ✅ SUCCESS: $message" >&2
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
	local value="$(echo "${yaml}" | grep "${param}:" | awk '{print $2}')"

	echo "${param}: ${value}"
}
