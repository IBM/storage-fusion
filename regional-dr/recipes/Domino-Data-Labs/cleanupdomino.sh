#!/bin/sh

for i in domino-platform domino-compute; do
	echo "removing Deploy and STS from $i..."
	oc delete -n $i deploy,sts --all
	echo "removing VolumeReplications from $i..."
	oc delete vr -n $i --all
	echo "removing ReplicationSources from $i..."
	oc delete replicationsources -n $i --all
	echo "removing PVCs from $i..."
	oc delete pvc -n $i --all --wait=false
done
cat <<EOF

Optional: cleanup endpointslices on target cluster:
oc delete endpointslices -n domino-platform --all
oc delete pod -n submariner-operator -lcomponent=submariner-lighthouse
EOF
