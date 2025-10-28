#!/bin/sh

for i in domino-shared-store domino-blob-store; do
	oc get pv $(oc get pvc $i -n domino-platform \
		-o jsonpath='{.spec.volumeName}') -o json | \
		jq '.metadata.name += "-copy" | del(.metadata.uid) | del(.metadata.creationTimestamp) | del(.metadata.resourceVersion) | del(.metadata.finalizers) | del(.spec.claimRef) | del(.status)' | \
		oc apply -f -
	sleep 2
	oc get pvc $i -n domino-platform -o json | \
		jq '.metadata.name += "-domino-compute" | .metadata.namespace = "domino-compute" | del(.metadata.uid) | del(.metadata.creationTimestamp) | del(.metadata.resourceVersion) | del(.metadata.annotations."pv.kubernetes.io/bind-completed") | del(.metadata.annotations."pv.kubernetes.io/bound-by-controller") | del(.metadata.finalizers) | .spec.volumeName += "-copy" |  del(.status)' | \
		oc apply -f -
done
