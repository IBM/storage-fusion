#!/bin/sh
#
# Extend script by adding namespaces to FOR loop
#

for i in virtualmachines; do
	echo "removing VolumeReplications from $i..."
	oc delete vr -n $i --all
	echo "Stopping VMs in $i..."
	for vm in $(oc get vms -n $i -o name | cut -d/ -f2); do
		virtctl stop -n $i $vm
	done
	while :; do
		test $(oc get vmi -n $i --no-headers | wc -l) -eq 0 && break
		echo "Pausing for VMs to stop..."
		sleep 5
	done
	echo "removing VMs from $i..."
	oc delete -n $i vms --all
done
