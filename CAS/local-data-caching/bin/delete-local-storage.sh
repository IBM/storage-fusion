#!/usr/bin/env bash
# start_Copyright_Notice
# Licensed Materials - Property of IBM

# IBM Spectrum Fusion 5900-AOY
# (C) Copyright IBM Corp. 2022 All Rights Reserved.

# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

set -u

# Function to print help message
print_help() {
	cat << EOF
Usage: $0 [OPTIONS] <VOLUME_SET>

Delete local storage resources associated with a LocalVolumeSet.

⚠️  DESTRUCTIVE WARNING:
    THIS SCRIPT WILL DELETE ALL PVs, STORAGE CLASSES, AND LOCAL STORAGE
    ASSOCIATED WITH THE SPECIFIED LOCALVOLUMESET.

    THIS OPERATION CANNOT BE UNDONE!

Arguments:
  <VOLUME_SET>                  Name of the LocalVolumeSet to clean up

Options:
  -h, --help                    Show this help message and exit
  --yes-i-really-mean-it        Skip confirmation prompts (use with caution)

Examples:
  $0 local-block
  $0 --yes-i-really-mean-it local-block

EOF
}

# Parse command-line arguments
SKIP_CONFIRMATION=false
VOLUME_SET=""

while [[ $# -gt 0 ]]; do
	case $1 in
		-h|--help)
			print_help
			exit 0
			;;
		--yes-i-really-mean-it)
			SKIP_CONFIRMATION=true
			shift
			;;
		*)
			if [ -z "$VOLUME_SET" ]; then
				VOLUME_SET="$1"
			else
				echo "Error: Unknown argument '$1'"
				echo ""
				print_help
				exit 1
			fi
			shift
			;;
	esac
done

if [ -z "$VOLUME_SET" ]; then
	print_help
	exit 1
fi

echo
echo "================================================================="
echo "Cleanup local storage from LocalVolumeSet: ${VOLUME_SET}"
echo "================================================================="

# Get list of PVs
PVS="$(oc get pv -l "storage.openshift.com/owner-name=${VOLUME_SET}" --no-headers | awk '{print $1}')"

printf "\n------delete local storage pv and storageclass------\n"
CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)

# Determine which flag to pass to disk-cleanup.sh
DISK_CLEANUP_FLAG=""
if [ "$SKIP_CONFIRMATION" = true ]; then
	DISK_CLEANUP_FLAG="--yes-i-really-mean-it"
fi

for PV in $PVS; do
	if [ -n "$DISK_CLEANUP_FLAG" ]; then
		"$CURRENT_DIR"/disk-cleanup.sh "$DISK_CLEANUP_FLAG" "${PV}"
	else
		"$CURRENT_DIR"/disk-cleanup.sh "${PV}"
	fi
done

sc_list=$(oc get sc -l "storage.openshift.com/owner-name=${VOLUME_SET}" --no-headers | awk '{print $1}')
for i in $sc_list; do
	oc delete sc "$i"
done

printf "\n------delete localvolumesets------\n"
oc delete localvolumesets.local.storage.openshift.io "${VOLUME_SET}" -n openshift-local-storage

printf "\n------delete the symlinks created by the LocalVolumeSet------\n"
for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do
	oc debug node/"$i" -- chroot /host rm -rfv /mnt/local-storage/
done

echo "================================================================="
echo "Cleanup local storage completed in $(date +"%F %Z")"
echo "================================================================="
