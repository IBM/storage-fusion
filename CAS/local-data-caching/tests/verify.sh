#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

#========================================
# Load Global Constants
#========================================
set -a
# shellcheck source=lib/constants.sh
source "$ROOT_DIR/lib/constants.sh"
# shellcheck source=config/config.env
source "$ROOT_DIR/config/config.env"
set +a

#========================================
# Local Constants
#========================================
PVC_NS="cache-fs-test-ns"
PVC_NAME="cache-fs-test-pvc"
PVC_SIZE="1Mi"
STORAGE_CLASS="ibm-spectrum-scale-sample"
ACCESS_MODE="ReadWriteMany"
VOLUME_MODE="Filesystem"
RETRY_COUNT=6
SLEEP_INTERVAL=10

#========================================
# Health Check Function
#========================================
check_health() {
	echo "🔍 Running IBM Spectrum Scale Health Checks..."

	#--- StorageCluster Phase Check ---
	sc_phase=$(oc get $STORAGE_CLUSTER "$OCS_CLUSTER_NAME" -n "$OCS_NAMESPACE" \
		-o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

	if [[ "$sc_phase" == "Ready" ]]; then
		echo "✅ StorageCluster is Ready"
	else
		echo "❌ StorageCluster NOT Ready (Current: $sc_phase)"
	fi

	#--- Scale Daemon Availability & Health ---
	daemon_available=$(oc get daemon "$SCALE_INSTANCE" -n "$SCALE_NAMESPACE" \
		-o jsonpath='{.status.conditions[?(@.type=="Available")].status}' \
		2>/dev/null || echo "False")

	running=$(oc get daemon "$SCALE_INSTANCE" -n "$SCALE_NAMESPACE" \
		-o jsonpath='{.status.podsStatus.running}' \
		2>/dev/null || echo "0")

	desired=$(oc get daemon "$SCALE_INSTANCE" -n "$SCALE_NAMESPACE" \
		-o jsonpath='{.status.pods.desired}' \
		2>/dev/null || echo "0")

	daemon_healthy=$(oc get daemon "$SCALE_INSTANCE" -n "$SCALE_NAMESPACE" \
		-o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' \
		2>/dev/null || echo "False")

	# Daemon Check Messages
	[[ "$daemon_available" == "True" ]] &&
		echo "✅ Spectrum Scale Daemon is Available" ||
		echo "❌ Spectrum Scale Daemon NOT Available (Current: $daemon_available)"

	[[ "$running" == "$desired" ]] &&
		echo "✅ All Daemon pods running ($running/$desired)" ||
		echo "❌ Daemon pods mismatch (Running: $running / Desired: $desired)"

	[[ "$daemon_healthy" == "True" ]] &&
		echo "✅ Spectrum Scale Daemon is Healthy" ||
		echo "❌ Spectrum Scale Daemon NOT Healthy (Current: $daemon_healthy)"

	#--- All pods are running, no pods in pending/terminating state in $SCALE_NAMESPACE ---
	if oc get pods -n $SCALE_NAMESPACE --no-headers |
		awk '$3 !~ /^Running$|^Completed$/ {exit 1}'; then
		echo "✅ All pods are Running/Completed in $SCALE_NAMESPACE namespace"
	else
		echo "❌ Some pods are not healthy in $SCALE_NAMESPACE namespace"
		oc get pods -n $SCALE_NAMESPACE --no-headers |
			awk '$3 !~ /^Running$|^Completed$/'
	fi

	#--- LocalDisks Shared + Healthy Check ---
	localdisk_failcount=$(oc get localdisk -n "$SCALE_NAMESPACE" \
		-o jsonpath='{range .items[?(@.status.type!="shared" || @.status.healthy!="Healthy")]}X {end}' \
		2>/dev/null | wc -w)

	if [[ "$localdisk_failcount" -eq 0 ]]; then
		echo "✅ All LocalDisks are shared & Healthy"
	else
		echo "❌ $localdisk_failcount LocalDisks NOT shared or NOT Healthy"
	fi

	#--- Filesystem Health ---
	fs_health=$(oc get filesystem "$DEFAULT_FS_NAME" -n "$SCALE_NAMESPACE" \
		-o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' \
		2>/dev/null || echo "Unknown")

	[[ "$fs_health" == "True" ]] &&
		echo "✅ Filesystem is Healthy" ||
		echo "❌ Filesystem NOT Healthy (Current: $fs_health)"
}

#========================================
# PVC Creation & Validation
#========================================
test_pvc() {
	echo "🔧 Deploying test PVC..."

	oc create ns "$PVC_NS" >/dev/null 2>&1 || true

	cat <<EOF | oc apply -n "$PVC_NS" -f - >/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes:
    - ${ACCESS_MODE}
  resources:
    requests:
      storage: ${PVC_SIZE}
  storageClassName: ${STORAGE_CLASS}
  volumeMode: ${VOLUME_MODE}
EOF

	echo "⏳ Waiting for PVC '${PVC_NAME}' to become Bound..."
	for ((i = 1; i <= RETRY_COUNT; i++)); do
		status=$(oc get pvc "$PVC_NAME" -n "$PVC_NS" \
			-o jsonpath='{.status.phase}' 2>/dev/null || echo "")

		if [[ "$status" == "Bound" ]]; then
			echo "🎯 PVC Test: PASS"
			return 0
		fi

		echo "⏳ Attempt $i/$RETRY_COUNT → PVC Status: ${status:-NotFound}"
		sleep "$SLEEP_INTERVAL"
	done

	echo "❌ PVC Test: FAIL — PVC not Bound"
	return 1
}

#========================================
# Cleanup Function
#========================================
cleanup() {
	echo "🧹 Cleanup: Removing test PVC and Namespace..."
	oc delete pvc "$PVC_NAME" -n "$PVC_NS" --ignore-not-found >/dev/null 2>&1
	oc delete ns "$PVC_NS" --ignore-not-found >/dev/null 2>&1
	echo "✅ Cleanup Complete."
}

#========================================
# Main Execution
#========================================
check_health
trap cleanup EXIT

if test_pvc; then
	exit 0
else
	exit 1
fi
