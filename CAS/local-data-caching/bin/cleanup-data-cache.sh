#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

set -a
# shellcheck source=lib/constants.sh
source "$ROOT_DIR/lib/constants.sh"
# shellcheck source=config/config.env
source "$ROOT_DIR/config/config.env"
set +a

# shellcheck source=modules/df_utils.sh
source "$ROOT_DIR/modules/df_utils.sh"

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
	shift
	local resources=("$@")

	local any_exist=true
	while $any_exist; do
		any_exist=false
		local existing_resources=""
		for resource in "${resources[@]}"; do
			local count
			count=$(oc get "${resource}" -n "${namespace}" --no-headers=true 2>/dev/null | wc -l)
			if [[ "${count}" -gt 0 ]]; then
				any_exist=true
				existing_resources="${existing_resources} ${resource}"
			fi
		done
		if $any_exist; then
			echo "Waiting for resource(s) to delete:${existing_resources} (10s)"
			sleep 10
		fi
	done
}

oc_delete_scale_sc_pvs(){
	#
	# Make sure the internal PVs created by the Scale installer are not just released but really gone
	# to prevent a reinstall failure
	#
	echo "Deleting Scale Storage Class (SC=ibm-spectrum-scale-internal) PVs"
	for pv in $(oc get pv -l app.kubernetes.io/name="pmcollector" -o name --no-headers)
	do
		oc delete "${pv}"
	done
}

oc_nodes_cmd(){
	local nodes="${1}"
	shift
	local cmd="$*"

	echo "Running command: ${cmd}"

	for node in ${nodes}; do
		echo "-> ${node#*/}"
		oc debug "$node" -- chroot /host /bin/bash -c "${cmd}" -s #2> /dev/null
	done
}

cleanup_cnsa() {
	echo "Cleaning up CNSA..."

	oc scale deployment --replicas=0 isf-cns-operator-controller-manager -n "$FUSION_NAMESPACE"

	# Check if filesystem exists and get deviceVolumes
	FS_HAS_DEVICE_VOLUMES=$(oc get filesystem "${FILESYSTEM_NAME}" -n "${SCALE_NAMESPACE}" -o jsonpath='{.spec.local.pools[*].deviceVolumes}' 2>/dev/null)
	FS_EXISTS=$?

	# Proceed with filesystem cleanup if it exists
	if [[ $FS_EXISTS -eq 0 ]]; then
		oc label -n "${SCALE_NAMESPACE}" filesystem "${FILESYSTEM_NAME}" scale.spectrum.ibm.com/allowDelete=
		envsubst <templates/filesystem.yaml | oc delete -f - --ignore-not-found=true
		wait_for_delete "${SCALE_NAMESPACE}" "filesystem/${FILESYSTEM_NAME}"

		# Only delete localdisks if no deviceVolumes were defined in the Filesystem CR
		if [[ -z "$FS_HAS_DEVICE_VOLUMES" ]]; then
			oc delete localdisk disk0 disk1 disk2 -n "$SCALE_NAMESPACE" --ignore-not-found=true
			wait_for_delete "${SCALE_NAMESPACE}" "localdisk/disk0" "localdisk/disk1" "localdisk/disk2"
		fi
	fi

	oc_nodes_cmd "$(oc get no -o name)" 'rm -rf /var/mmfs; rm -rf /usr/lpp/mmfs; rm -rf /var/adm/ras; rm -rf /var/lib/firmware; rm -rf /mnt/'"${FILESYSTEM_NAME}"'; rmmod tracedev mmfs26 mmfslinux;'

	if [[ $ENV == "HCI" ]]; then
		oc delete "$FUSION_SERVICE_INSTANCE_CR" "$SCALE_SERVICE_NAME" -n "$FUSION_NAMESPACE" --ignore-not-found=true
		oc delete scalemanager/scalemanager -n "$FUSION_NAMESPACE" --ignore-not-found=true
	else
		oc patch "$SPECTRUM_FUSION_CRD" "$SPECTRUM_FUSION" -n "$FUSION_NAMESPACE" --type merge -p '{"spec": {"GlobalDataPlatform": {"Enable": false}}}'
		oc delete scalemanager/scalemanager -n "$FUSION_NAMESPACE" --ignore-not-found=true
	fi

	oc delete clusters.scale.spectrum.ibm.com "${SCALE_NAMESPACE}" -n "$SCALE_NAMESPACE" --ignore-not-found=true
	wait_for_delete "${SCALE_NAMESPACE}" "clusters.scale.spectrum.ibm.com/${SCALE_NAMESPACE}"

	oc delete modules.kmm.sigs.x-k8s.io -n "${SCALE_NAMESPACE}" gpfs-kmod --ignore-not-found=true

	oc label node --all scale.spectrum.ibm.com/nsdFailureGroup- scale.spectrum.ibm.com/nsdFailureGroupMappingType-

	oc delete scc ibm-spectrum-scale-privileged spectrum-scale-csiaccess --ignore-not-found=true

	oc delete pvc -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=pmcollector --ignore-not-found=true
	oc delete sc -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=pmcollector --ignore-not-found=true

	oc delete sc "$SCALE_STORAGE_CLASS" --ignore-not-found=true
	oc delete volumesnapshotclass "$SCALE_STORAGE_CLASS" --ignore-not-found=true

	oc label node --all "scale-" "${SCALE_DAEMON_LABEL}-" "${SCALE_IMAGE_DIGEST_LABEL}-" "${SCALE_ROLE_LABEL}-" "${SCALE_DESIGNATION_LABEL}-"

	# Skip local storage cleanup if filesystem exists and has device volumes
	if [[ $FS_EXISTS -eq 0 && -n "$FS_HAS_DEVICE_VOLUMES" ]]; then
		echo "Skipping local storage cleanup - filesystem with device volumes was found"
	else
		envsubst <templates/daemonset_expose_rbd.yaml | oc delete -f - --ignore-not-found=true
		envsubst <templates/pvc_local_disks.yaml | oc delete -f - --ignore-not-found=true
		oc delete project "$LOCAL_STORAGE_PROJECT" --ignore-not-found=true
	fi
	oc delete project "$SCALE_NAMESPACE" --ignore-not-found=true --wait=false
	oc delete project "$SCALE_NAMESPACE-dns" --ignore-not-found=true --wait=false
	oc delete project "$SCALE_CSI_NAMESPACE" --ignore-not-found=true --wait=false
	oc delete project "$SCALE_OPERATOR_NAMESPACE" --ignore-not-found=true --wait=false

	wait_for_delete "${SCALE_NAMESPACE}" "pods"

	oc scale deployment --replicas=1 isf-cns-operator-controller-manager -n "$FUSION_NAMESPACE"
	oc_delete_scale_sc_pvs

	delete_scale_rbd_sc
}

cleanup_df() {
	echo "================================================================="
	echo "Cleanup Fusion Data Foundation"
	echo "================================================================="

	printf "\n------scale isf-cns deployment to 0 replica------\n"
	oc scale deployment --replicas=0 "$ISF_CNS_MANAGER" -n "$FUSION_NAMESPACE"

	printf "\n------delete odf fusionserviceinstance------\n"
	oc delete "$FUSION_SERVICE_INSTANCE_CR" "$DF_SERVICE_NAME" -n "$FUSION_NAMESPACE" --ignore-not-found=true

	printf "\n------delete odfmanager------\n"
	oc delete odfmanager "$DF_SERVICE_NAME" --ignore-not-found=true

	printf "\n------delete odfcluster------\n"
	oc delete odfcluster odfcluster -n "$FUSION_NAMESPACE" --ignore-not-found=true

	if [[ "$ENV" == "HCI" ]]; then
		printf "\n------scale isf-bkprstr deployment to 0 replica------\n"
		oc scale deployment --replicas=0 isf-bkprstr-operator-controller-manager -n "$FUSION_NAMESPACE"

		printf "\n------scale logcollector deployment to 0 replica------\n"
		oc scale deployment --replicas=0 logcollector -n "$FUSION_NAMESPACE"

		printf "\n------delete Fusion internal used PVC isf-bkprstr-claim logcollector------\n"
		oc delete pvc isf-bkprstr-claim logcollector -n "$FUSION_NAMESPACE" --ignore-not-found=true
	fi

	# Call the ODF cleanup script
	"$ROOT_DIR/bin/delete-odf.sh"

	result=$?
	if [[ $result -ne 0 ]]; then
		echo ""
		echo "================================================================="
		echo "Delete ODF failed"
		echo "Please check failure and retry"
		echo "================================================================="
		exit 1
	fi

	printf "\n------delete storageclass ibm-spectrum-fusion-mgmt-sc------\n"
	oc delete sc "$FUSION_SC" --ignore-not-found=true

	printf "\n------delete fdf catalogsource------\n"
	oc delete catalogsource "$DF_CATALOG" -n "$MARKETPLACE_NAMESPACE" --ignore-not-found=true

	printf "\n------scale isf-cns deployment back to 1 replica------\n"
	oc scale deployment --replicas=1 "$ISF_CNS_MANAGER" -n "$FUSION_NAMESPACE"

	if [[ "$ENV" == "HCI" ]]; then
		printf "\n------recreate the PVC isf-bkprstr-claim and logcollector------\n"
		oc apply -f - <<EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
    name: isf-bkprstr-claim
    namespace: $FUSION_NAMESPACE
spec:
    accessModes:
        - ReadWriteMany
    resources:
        requests:
            storage: 25Gi
    storageClassName: $FUSION_SC
    volumeMode: Filesystem
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
    name: logcollector
    namespace: $FUSION_NAMESPACE
spec:
    accessModes:
        - ReadWriteMany
    resources:
        requests:
            storage: 25Gi
    storageClassName: $FUSION_SC
    volumeMode: Filesystem
EOF

		printf "\n------scale isf-bkprstr deployment to 1 replica------\n"
		oc scale deployment --replicas=1 isf-bkprstr-operator-controller-manager -n "$FUSION_NAMESPACE"

		printf "\n------scale logcollector deployment to 2 replica------\n"
		oc scale deployment --replicas=2 logcollector -n "$FUSION_NAMESPACE"
	fi

	# Clean up devices
	printf "\n------delete localvolumeset------\n"
	result=$(oc get localvolumeset -n openshift-local-storage "$OCS_BACKING_STORAGECLASS" --no-headers 2>/dev/null | wc -l | tr -d ' ')
	if [[ $result -eq 0 ]]; then
		info "There is no localvolumeset detected"
	else
		info "localvolumeset detected, start to remove local storage"
		CURRENT_DIR=$(cd "$(dirname "$0")" && pwd)
		"$CURRENT_DIR"/delete-local-storage.sh --yes-i-really-mean-it "$OCS_BACKING_STORAGECLASS"
	fi

	echo "================================================================="
	echo "Cleanup Fusion with ODF completed in $(date +"%F %Z")"
	echo "================================================================="
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
			oc delete crd "$CRD" --wait=false
			RES_LIST=$(oc get "$CRD" --all-namespaces -o=jsonpath='{range .items[]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}')
			sleep 1
			if [ -n "$RES_LIST" ]; then
				# Loop through the resources and delete them
				while IFS= read -r res; do
					namespace=$(echo "$res" | cut -d ':' -f 1)
					res_name=$(echo "$res" | cut -d ':' -f 2)
					echo "patching resource $res_name in namespace $namespace"
					oc patch "$CRD" "$res_name" -n "$namespace" --type merge -p '{"metadata":{"finalizers": []}}'
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

		oc delete OperatorGroup isf-fusionbase -n "$FUSION_NAMESPACE"
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

		oc delete ns "$FUSION_NAMESPACE"
	fi
}

cleanup_cas() {
	echo "================================================================="
	echo "Cleanup CAS (Content Aware Storage)"
	echo "================================================================="

	# Check if CAS namespace exists before running cleanup script
	if oc get namespace "$CAS_NAMESPACE" &>/dev/null; then
		local cas_cleanup_script="$ROOT_DIR/bin/customer_cas_cleanup.sh"

		# Check if cleanup script exists, download if not
		if [[ ! -f "$cas_cleanup_script" ]]; then
			printf "\n------Downloading CAS cleanup script------\n"
			if ! curl -fsSL "$CAS_CLEANUP_SCRIPT_URL" -o "$cas_cleanup_script"; then
				echo "ERROR: Failed to download CAS cleanup script from $CAS_CLEANUP_SCRIPT_URL"
				return 1
			fi
			chmod +x "$cas_cleanup_script"
			echo "CAS cleanup script downloaded successfully"
		else
			echo "Using existing CAS cleanup script: $cas_cleanup_script"
		fi

		printf "\n------Running CAS cleanup script------\n"
		if ! yes y | "$cas_cleanup_script"; then
			echo "ERROR: CAS cleanup script failed"
			return 1
		fi
	else
		echo "CAS namespace '$CAS_NAMESPACE' not found - skipping CAS cleanup script"
	fi

	# Check if filesystem exists and get deviceVolumes
	FS_HAS_DEVICE_VOLUMES=$(oc get filesystem "${FILESYSTEM_NAME}" -n "${SCALE_NAMESPACE}" -o jsonpath='{.spec.local.pools[*].deviceVolumes}' 2>/dev/null)
	FS_EXISTS=$?

	# Proceed with filesystem cleanup if it exists
	if [[ $FS_EXISTS -eq 0 ]]; then
		oc label -n "${SCALE_NAMESPACE}" filesystem "${FILESYSTEM_NAME}" scale.spectrum.ibm.com/allowDelete=
		envsubst <templates/filesystem.yaml | oc delete -f - --ignore-not-found=true
		wait_for_delete "${SCALE_NAMESPACE}" "filesystem/${FILESYSTEM_NAME}"

		# Only delete localdisks if no deviceVolumes were defined in the Filesystem CR
		if [[ -z "$FS_HAS_DEVICE_VOLUMES" ]]; then
			oc delete localdisk disk0 disk1 disk2 -n "$SCALE_NAMESPACE" --ignore-not-found=true
			wait_for_delete "${SCALE_NAMESPACE}" "localdisk/disk0" "localdisk/disk1" "localdisk/disk2"
		fi
	fi

	oc delete sc ibm-cas-cache-fs-internal --ignore-not-found=true

	echo "================================================================="
	echo "CAS cleanup completed in $(date +"%F %Z")"
	echo "================================================================="
}

show_help() {
	cat <<EOF
Usage: $0 <ACTION> [--filesystem-name NAME]

ACTION:
  --all, --fusion     Clean CAS, CNSA, Local PVC, DF, and Fusion (in case of SDS environment)
  --cas               Clean only CAS
  --cnsa              Clean CAS, CNSA, and Local PVC
  --df                Clean CAS, CNSA, Local PVC, and DF

Optional:
  --filesystem-name   Override filesystem name (default: cache-fs)
EOF
}

ACTION=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--filesystem-name)
		if [[ $# -lt 2 || -z "$2" ]]; then
			echo "Missing value for --filesystem-name"
			echo "Use --help for usage."
			exit 1
		fi
		FILESYSTEM_NAME="$2"
		export FILESYSTEM_NAME
		shift 2
		;;
	--help)
		show_help
		exit 0
		;;
	--all | --fusion | --df | --cnsa | --cas)
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
	cleanup_cas || exit 1
	cleanup_cnsa || exit 1
	cleanup_df || exit 1
	cleanup_fusion || exit 1
	;;
--cas)
	cleanup_cas || exit 1
	;;
--cnsa)
	cleanup_cas || exit 1
	cleanup_cnsa || exit 1
	;;
--df)
	cleanup_cas || exit 1
	cleanup_cnsa || exit 1
	cleanup_df || exit 1
	;;
esac
