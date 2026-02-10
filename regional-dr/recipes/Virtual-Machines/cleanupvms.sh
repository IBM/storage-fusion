#!/bin/sh
#
# Extend script by adding namespaces to FOR loop
#

for i in virtualmachines; do
	echo "removing VolumeReplications from $i..."
	oc delete vr -n $i --all
	echo "Stopping VMs in $i..."
	for vm in $(oc get vms -n $i -o name | cut -d/ -f2); do
		virtctl stop -n $i $vm || {
			while :; do
				echo "Pausing for retry in 10 seconds..."
				sleep 10
				virtctl stop -n $i $vm && break
			done
		}
	done
	while :; do
		test $(oc get vmi -n $i --no-headers | wc -l) -eq 0 && break
		echo "Pausing 10 seconds for VMs to stop..."
		sleep 10
	done
	echo "removing VMs from $i..."
	oc delete -n $i vms --all
done
