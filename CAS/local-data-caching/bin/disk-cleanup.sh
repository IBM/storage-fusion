#!/usr/bin/env bash
# start_Copyright_Notice
# Licensed Materials - Property of IBM

# IBM Spectrum Fusion 5900-AOY
# (C) Copyright IBM Corp. 2022 All Rights Reserved.

# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

# DESTRUCTIVE WARNING:
#   ⚠️ THIS SCRIPT WILL IRREVERSIBLY ERASE ALL DATA FOR THE GIVEN PV'S BACKING DISK
#   ON THE WORKER NODE WHERE THAT PV IS ATTACHED.
#
#   DOUBLE-CHECK THE DISK NAME BEFORE RUNNING!
#   DO NOT USE ON OS/BOOT DISKS.

print_help() {
	cat << EOF
Usage: $0 [OPTIONS] <PV NAME>

Wipe a given disk on the worker node where the specified PV is attached.

⚠️  DESTRUCTIVE WARNING:
    THIS SCRIPT WILL IRREVERSIBLY ERASE ALL DATA FOR THE GIVEN PV'S BACKING DISK
    ON THE WORKER NODE WHERE THAT PV IS ATTACHED.

    DOUBLE-CHECK THE DISK NAME BEFORE RUNNING!
    DO NOT USE ON OS/BOOT DISKS.

Arguments:
  <PV NAME>                     Name of the PersistentVolume to clean up

Options:
  -h, --help                    Show this help message and exit
  --yes-i-really-mean-it        Skip confirmation prompt (use with caution)

Examples:
  $0 local-pv-12345
  $0 --yes-i-really-mean-it local-pv-12345

EOF
}

# Parse command-line arguments
SKIP_CONFIRMATION=false
PV=""

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
			if [ -z "$PV" ]; then
				PV="$1"
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

if [ -z "$PV" ]; then
	print_help
	exit 1
fi

echo "=============================================================="
echo "  DESTRUCTIVE OPERATION: Wiping disk for PV $PV"
echo "=============================================================="

pv_yaml=$(oc get pv "$PV" -o yaml)
NODE="$(echo "$pv_yaml" | grep "kubernetes.io/hostname:" | awk '{print $2}')"
DISK="/dev/$(echo "$pv_yaml" | grep "storage.openshift.com/device-name:" | awk '{print $2}')"

echo ">>> Processing $NODE with disk $DISK"

# Confirmation prompt unless --yes-i-really-mean-it flag is provided
if [ "$SKIP_CONFIRMATION" = false ]; then
	echo ""
	echo "⚠️  WARNING: This will IRREVERSIBLY ERASE ALL DATA on disk $DISK on node $NODE"
	echo ""
	read -p "Are you sure you want to proceed? (yes/no): " -r
	echo ""
	if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
		echo "Operation cancelled by user."
		exit 1
	fi
	echo "Proceeding with disk wipe..."
fi

oc debug "no/$NODE" -- chroot /host /bin/bash -c "
    echo 'Checking disks before wipe on $DISK...'
    lsblk $DISK || echo 'Disk $DISK not found'

    if [ -b $DISK ]; then
        echo '--- Wiping partition table ---'
        wipefs -fa $DISK

        echo '--- Zeroing beginning of disk ---'
        dd if=/dev/zero of=$DISK bs=1M count=1000 oflag=direct,dsync

        echo '--- Removing possible Ceph metadata ---'
        for gb in 0 1 10 100 1000; do
            dd if=/dev/zero of=$DISK bs=1K count=200 oflag=direct,dsync seek=\$((gb * 1024**2))
        done

        echo '--- Attempt blkdiscard (if supported) ---'
        blkdiscard $DISK || echo 'blkdiscard not supported on $DISK'

        echo '--- Rescanning partition table ---'
        rescan-scsi-bus.sh || true
        partprobe $DISK || true

        echo '--- Verifying wipe (sample hexdump) ---'
        hexdump -C -s 1073741824 -n 22 $DISK || echo 'hexdump failed'

        echo '--- Post-wipe check ---'
        lsblk $DISK

        echo '--- Check rook dir ---'
        ls /var/lib/rook/
    else
        echo 'Skipping: $DISK not present on $NODE'
        exit 2
    fi
" && oc delete pv "$PV"

# echo "================== SUMMARY =================="
# if [ ${#SUCCESS_NODES[@]} -gt 0 ]; then
# 	echo "✅ Successful nodes:"
# 	for n in "${SUCCESS_NODES[@]}"; do
# 		echo "   - $n"
# 	done
# else
# 	echo "⚠️ No successful nodes"
# fi

# if [ ${#FAILED_NODES[@]} -gt 0 ]; then
# 	echo "❌ Failed nodes:"
# 	for n in "${FAILED_NODES[@]}"; do
# 		echo "   - $n"
# 	done
# else
# 	echo "🎉 No failures"
# fi
echo "==========================================================================="
echo "Cleanup disks on worker nodes in ODF cluster completed in $(date +"%F %Z")"
echo "==========================================================================="
