#!/bin/sh

for i in domino-compute domino-platform; do
	echo "removing Deploy and STS from $i..."
	oc delete -n $i deploy,sts --all
	echo "removing VolumeReplications from $i..."
	oc delete vr -n $i --all
	echo "removing ReplicationSources from $i..."
	oc delete replicationsources -n $i --all
done
for i in domino-compute domino-platform; do
	echo "removing PVCs from $i..."
	oc delete pvc -n $i --all
done
cat <<EOF

Optional: cleanup endpointslices on target cluster:
oc get endpointslices -n domino-platform | awk '/volsync-rsync/ {
	system("oc delete endpointslice -n domino-platform "\$1)
}'
oc delete pod -n submariner-operator -lcomponent=submariner-lighthouse
EOF
