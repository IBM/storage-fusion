#!/usr/bin/env bash
# start_Copyright_Notice
# Licensed Materials - Property of IBM

# IBM Spectrum Fusion 5900-AOY
# (C) Copyright IBM Corp. 2022 All Rights Reserved.

# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with
# IBM Corp.
# end_Copyright_Notice

# disk-cleanup.sh - Wipe a given disk on all worker nodes in an OCP cluster
#
# USAGE:
#   ./disk-cleanup.sh /dev/sdX
#
# DESTRUCTIVE WARNING:
#   ⚠️ THIS SCRIPT WILL IRREVERSIBLY ERASE ALL DATA ON THE GIVEN DISK
#   ACROSS *ALL* WORKER NODES IN THE CLUSTER.
#
#   DOUBLE-CHECK THE DISK NAME BEFORE RUNNING!
#   DO NOT USE ON OS/BOOT DISKS.

set -euo pipefail

if [ $# -ne 1 ]; then
	echo "Usage: $0 <disk-path>"
	echo "Example: $0 /dev/sdb or /dev/vdb or /dev/nvme0n1"
	exit 1
fi

DISK=$1

echo "=============================================================="
echo "  DESTRUCTIVE OPERATION: Wiping disk $DISK on all worker nodes"
echo "=============================================================="

# Get list of worker nodes
WORKER_NODES=$(oc get nodes -l node-role.kubernetes.io/worker= -o name)

# Track results
SUCCESS_NODES=()
FAILED_NODES=()

for NODE in $WORKER_NODES; do
	echo
	echo ">>> Processing $NODE with disk $DISK"

	if oc debug $NODE -- chroot /host /bin/bash -c "
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
    "; then
		SUCCESS_NODES+=("$NODE")
	else
		FAILED_NODES+=("$NODE")
	fi
done

echo "================== SUMMARY =================="
if [ ${#SUCCESS_NODES[@]} -gt 0 ]; then
	echo "✅ Successful nodes:"
	for n in "${SUCCESS_NODES[@]}"; do
		echo "   - $n"
	done
else
	echo "⚠️ No successful nodes"
fi

if [ ${#FAILED_NODES[@]} -gt 0 ]; then
	echo "❌ Failed nodes:"
	for n in "${FAILED_NODES[@]}"; do
		echo "   - $n"
	done
else
	echo "🎉 No failures"
fi
echo "==========================================================================="
echo "Cleanup disks on worker nodes in ODF cluster completed in $(date +"%F %Z")"
echo "==========================================================================="
