#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

set -a
source "$ROOT_DIR/lib/constants.sh"
source "$ROOT_DIR/config/config.env"
set +a

LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/cleanup-data-cache-$(date +'%Y%m%d_%H%M%S').log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Logging initialized. All output will be saved to $LOG_FILE"

oc project default

FILESYSTEM_NAME="$DEFAULT_FS_NAME"

FUSION_NAMESPACE=$(oc get csv -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase 2>/dev/null | grep "$FUSION_PACKAGE_NAME" | awk '{print $1}')

res=$(oc get deployment "$ISF_CNS_MANAGER" -o jsonpath='{.metadata.annotations.environment}' -n "$FUSION_NAMESPACE")
if [[ "$res" == "HCI" ]]; then
	ENV="HCI"
else
	ENV="SDS"
fi

echo "Fusion environment: ${ENV}"

wait_for_delete() {
	local namespace="$1"
	local resource="$2"

	while oc get "${resource}" -n "${namespace}" &> /dev/null; do
		echo "Waiting for resource to delete... (10s)"
		sleep 10
	done
}

oc_nodes_cmd(){
	local nodes="${1}"
	shift
	local cmd="${@}"

	echo "Running command: ${cmd}"

	for node in ${nodes}; do
		echo ${node#*/}
		oc debug $node -- chroot /host /bin/bash -c "${CMD}" -s 2> /dev/null
	done
}

cleanup_cnsa() {
	echo "Cleaning up CNSA..."

	oc scale deployment --replicas=0 isf-cns-operator-controller-manager -n "$FUSION_NAMESPACE"

	oc label -n ${SCALE_NAMESPACE} filesystem ${FILESYSTEM_NAME} scale.spectrum.ibm.com/allowDelete=
	envsubst <templates/filesystem.yaml | oc delete -f - --ignore-not-found=true
	wait_for_delete "${SCALE_NAMESPACE}" "filesystem/${FILESYSTEM_NAME}"

	oc_nodes_cmd "$(oc get no -l scale=true -o name)" 'rm -rf /var/mmfs; rm -rf /usr/lpp/mmfs; rm -rf /var/adm/ras; rmmod tracedev mmfs26 mmfslinux;'

	oc delete localdisk disk0 disk1 disk2 -n "$SCALE_NAMESPACE" --ignore-not-found=true
	wait_for_delete "${SCALE_NAMESPACE}" "localdisk/disk0"

	if [[ $ENV == "HCI" ]]; then
		oc delete "$FUSION_SERVICE_INSTANCE_CR" "$SCALE_SERVICE_NAME" -n "$FUSION_NAMESPACE" --ignore-not-found=true
		oc delete scalemanager/scalemanager -n "$FUSION_NAMESPACE" --ignore-not-found=true
	else
		oc patch "$SPECTRUM_FUSION_CRD" "$SPECTRUM_FUSION" -n "$FUSION_NAMESPACE" --type merge -p '{"spec": {"GlobalDataPlatform": {"Enable": false}}}'
		oc delete scalemanager/scalemanager -n "$FUSION_NAMESPACE" --ignore-not-found=true
	fi

	oc delete clusters.scale.spectrum.ibm.com "${SCALE_NAMESPACE}" -n "$SCALE_NAMESPACE" --ignore-not-found=true
	wait_for_delete "${SCALE_NAMESPACE}" "clusters.scale.spectrum.ibm.com/${SCALE_NAMESPACE}"

	oc label node --all scale.spectrum.ibm.com/nsdFailureGroup- scale.spectrum.ibm.com/nsdFailureGroupMappingType-

	oc delete scc ibm-spectrum-scale-privileged spectrum-scale-csiaccess --ignore-not-found=true

	oc delete pvc -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=pmcollector --ignore-not-found=true
	oc delete sc -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=pmcollector --ignore-not-found=true

	oc delete sc "$SCALE_STORAGE_CLASS" --ignore-not-found=true
	oc delete volumesnapshotclass "$SCALE_STORAGE_CLASS" --ignore-not-found=true

	oc label node --all "scale-" "${SCALE_DAEMON_LABEL}-" "${SCALE_IMAGE_DIGEST_LABEL}-" "${SCALE_ROLE_LABEL}-" "${SCALE_DESIGNATION_LABEL}-"

	envsubst <templates/daemonset_expose_rbd.yaml | oc delete -f - --ignore-not-found=true
	envsubst <templates/pvc_local_disks.yaml | oc delete -f - --ignore-not-found=true
	oc delete project "$LOCAL_STORAGE_PROJECT" --ignore-not-found=true
	oc delete project "$SCALE_NAMESPACE" --ignore-not-found=true
	oc delete project "$SCALE_NAMESPACE-dns" --ignore-not-found=true
	oc delete project "$SCALE_CSI_NAMESPACE" --ignore-not-found=true
	oc delete project "$SCALE_OPERATOR_NAMESPACE" --ignore-not-found=true

	oc scale deployment --replicas=1 isf-cns-operator-controller-manager -n "$FUSION_NAMESPACE"
}

cleanup_df() {
	$ROOT_DIR/bin/delete-fusion-odf.sh "$FUSION_NAMESPACE"

	DEVICES=($(oc get pvc -n $OCS_NAMESPACE -l $DEVICESET_LABEL -o jsonpath='{range .items[*]}{.spec.volumeName}{"\n"}{end}' |
		while read pv; do
			oc get pv "$pv" -o jsonpath='{.metadata.annotations.storage\.openshift\.com/device-name}{"\n"}'
		done))

	for DEV in "${DEVICES[@]}"; do
		echo ">>> Cleaning device: $DEV"
		$ROOT_DIR/bin/disk-cleanup.sh "/dev/$DEV"
	done
}

cleanup_fusion() {
	if [[ $ENV == "HCI" ]]; then
		echo "Detected HCI environment. Skipping fusion cleanup."
	else
		echo "Cleaning up Fusion..."

		echo "Fusion namespace: $FUSION_NAMESPACE"
		oc delete isfproxydeps isf-proxy
		oc delete isflcdeps logcollector
		oc delete isfchdeps callhomeclient
		oc delete oauthclient isf-oauth
		oc delete consolelink ibm-spectrum-fusion

		oc delete sppmanagers sppmanager
		oc delete updatemanager version

		# Find all the ISF CRDs
		ISF_CRDS=$(oc get crd -o json | jq -r '.items[] | select(.spec.group | endswith("isf.ibm.com")) | .metadata.name')
		# List resources for each CRD

		# Remove all the resources for CRD's
		for CRD in $ISF_CRDS; do
			oc delete crd $CRD --wait=false
			RES_LIST=$(oc get $CRD --all-namespaces -o=jsonpath='{range .items[]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}')
			sleep 1
			if [ -n "$RES_LIST" ]; then
				# Loop through the resources and delete them
				while IFS= read -r res; do
					namespace=$(echo "$res" | cut -d ':' -f 1)
					res_name=$(echo "$res" | cut -d ':' -f 2)
					echo "patching resource $res_name in namespace $namespace"
					oc patch $CRD $res_name -n $namespace --type merge -p '{"metadata":{"finalizers": []}}'
				done <<<"$RES_LIST"
			fi
		done

		oc delete crd fusionservicedefinitions.service.isf.ibm.com
		oc delete crd fusionserviceinstances.service.isf.ibm.com

		oc delete crd odfmanagers.odf.isf.ibm.com
		oc delete crd odfclusters.odf.isf.ibm.com
		oc delete crd applications.application.isf.ibm.com
		oc delete crd clusters.application.isf.ibm.com
		oc delete crd connections.application.isf.ibm.com
		oc delete crd backuppolicies.data-protection.isf.ibm.com
		oc delete crd backups.data-protection.isf.ibm.com
		oc delete crd backupstoragelocations.data-protection.isf.ibm.com
		oc delete crd callhomes.scale.spectrum.ibm.com
		oc delete crd clusters.scale.spectrum.ibm.com
		oc delete crd compressionjobs.scale.spectrum.ibm.com
		oc delete crd controlplanebackups.bkprstr.isf.ibm.com
		oc delete crd csiscaleoperators.csi.ibm.com
		oc delete crd daemons.scale.spectrum.ibm.com
		oc delete crd deletebackuprequests.data-protection.isf.ibm.com
		oc delete crd encryptionclients.cns.isf.ibm.com
		oc delete crd encryptionconfigs.scale.spectrum.ibm.com
		oc delete crd encryptionservers.cns.isf.ibm.com
		oc delete crd filesystems.scale.spectrum.ibm.com
		oc delete crd grafanabridges.scale.spectrum.ibm.com
		oc delete crd guis.scale.spectrum.ibm.com
		oc delete crd hooks.data-protection.isf.ibm.com
		oc delete crd ibmsppcs.sppc.ibm.com
		oc delete crd ibmspps.ocp.spp.ibm.com
		oc delete crd isfchdeps.mgmtsft.isf.ibm.com
		oc delete crd isfemdeps.mgmtsft.isf.ibm.com
		oc delete crd isflcdeps.mgmtsft.isf.ibm.com
		oc delete crd isfproxydeps.mgmtsft.isf.ibm.com
		oc delete crd isfuideps.mgmtsft.isf.ibm.com
		oc delete crd isfconsoleplugins.mgmtsft.isf.ibm.com
		oc delete crd localdisks.scale.spectrum.ibm.com
		oc delete crd pmcollectors.scale.spectrum.ibm.com
		oc delete crd policyassignments.data-protection.isf.ibm.com
		oc delete crd recoverygroups.scale.spectrum.ibm.com
		oc delete crd remoteclusters.scale.spectrum.ibm.com
		oc delete crd restores.data-protection.isf.ibm.com
		oc delete crd scaleclusters.cns.isf.ibm.com
		oc delete crd scalemanagers.cns.isf.ibm.com
		oc delete crd spectrumfusions.prereq.isf.ibm.com
		oc delete crd sppmanagers.spp.isf.ibm.com
		oc delete crd updatemanagers.update.isf.ibm.com
		oc delete crd computeprovisionworkers.install.isf.ibm.com
		oc delete crd storagesetups.install.isf.ibm.com
		oc delete crd nodeconfigs.monitor.isf.ibm.com
		oc delete crd fusionservicedefinitions.service.isf.ibm.com
		oc delete crd fusionserviceinstances.service.isf.ibm.com
		oc delete crd recipes.spp-data-protection.isf.ibm.com
		oc delete crd sncfilesystems.cns.isf.ibm.com
		oc delete crd sncnodes.cns.isf.ibm.com
		oc delete crd cloudcsidisks.scale.spectrum.ibm.com
		oc delete crd diskjobs.scale.spectrum.ibm.com
		oc delete crd dnss.scale.spectrum.ibm.com
		oc delete crd dnsconfigs.scale.spectrum.ibm.com
		oc delete crd jobs.scale.spectrum.ibm.com
		oc delete crd restripefsjobs.scale.spectrum.ibm.com
		oc delete crd stretchclusters.scale.spectrum.ibm.com
		oc delete crd stretchclusterinitnodes.scale.spectrum.ibm.com
		oc delete crd stretchclustertiebreakers.scale.spectrum.ibm.com
		oc delete crd upgradeapprovals.scale.spectrum.ibm.com

		oc delete clusterrolebinding isf-sds-serviceability-rolebinding
		oc delete clusterrolebinding isf-serviceability-operator-manager-rolebinding
		oc delete clusterrolebinding isf-sds-backuprestore-rolebinding
		oc delete clusterrolebinding isf-bkprstr-operator-manager-rolebinding

		oc delete OperatorGroup isf-fusionbase -n $FUSION_NAMESPACE
		oc delete ns baas
		oc delete ns ibm-spectrum-protect-plus-ns
		oc delete ns ibm-spectrum-scale-csi
		oc delete ns ibm-spectrum-scale-operator
		oc delete ns ibm-spectrum-scale-dns
		oc delete ns ibm-spectrum-scale
		oc delete ns isf-prereq-operator-system

		# new script
		oc delete isfproxydeps isf-proxy
		oc delete isflcdeps logcollector
		oc delete isfchdeps callhomeclient
		oc delete oauthclient isf-oauth
		oc delete consolelink ibm-spectrum-fusion

		oc delete updatemanager version

		oc delete crd ibmusagemeterings.operator.ibm.com
		oc delete crd ibmservicemeterdefinitions.operator.ibm.com

		oc delete clusterrolebinding isf-sds-serviceability-rolebinding
		oc delete clusterrolebinding isf-serviceability-operator-manager-rolebinding
		oc delete clusterrolebinding isf-sds-backuprestore-rolebinding
		oc delete clusterrolebinding isf-bkprstr-operator-manager-rolebinding
		oc delete clusterrolebinding fusionmanager-addon
		oc delete clusterrolebinding fusion-support-rolebinding

		oc delete role fusionmanager-addon

		oc delete catalogsource ibm-usage-metering-catalog-source -n openshift-marketplace
		oc get CatalogSource -n openshift-marketplace -l app=ibm-fusion-hcp -o name | xargs -n1 oc delete -n openshift-marketplace CatalogSource

		oc delete ns $FUSION_NAMESPACE
	fi
}

show_help() {
	cat <<EOF
Usage: $0 [OPTION] [--filesystem-name NAME]

Options:
  --all               Clean CNSA, Local PVC, DF, and Fusion (in case of SDS environment)
  --cnsa              Clean only CNSA
  --df                Clean CNSA, Local PVC and DF
  --fusion            Clean CNSA, Local PVC, DF and Fusion (in case of SDS environment)

Optional:
  --filesystem-name   Override filesystem name (default: cache-fs)
EOF
}

ACTION=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--filesystem-name)
		FILESYSTEM_NAME="$2"
		export FILESYSTEM_NAME
		shift 2
		;;
	--help)
		show_help
		exit 0
		;;
	--all | --fusion | --df | --cnsa)
		ACTION="$1"
		shift
		;;
	*)
		echo "Invalid argument: $1"
		echo "Use --help for usage."
		exit 1
		;;
	esac
done

if [[ -z "${ACTION:-}" ]]; then
	show_help
	exit 1
fi

export FILESYSTEM_NAME

case "$ACTION" in
--all | --fusion)
	cleanup_cnsa || exit 1
	cleanup_df || exit 1
	cleanup_fusion || exit 1
	;;
--cnsa)
	cleanup_cnsa || exit 1
	;;
--df)
	cleanup_cnsa || exit 1
	cleanup_df || exit 1
	;;
esac
