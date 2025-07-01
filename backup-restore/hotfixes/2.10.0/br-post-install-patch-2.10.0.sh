#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.10.0 release.
HOTFIX_NUMBER=1

patch_usage() {
    echo "Usage: $0 (-hci |-sds | -help)"
    echo "Options:"
    echo "  -hci   Apply patch on HCI"
    echo "  -sds   Apply patch on SDS"
    echo "  -help  Display usage"
}

PATCH=
if [[ "$#" -ne 1 ]]; then
    patch_usage
    exit 0
elif [[ "$1" == "-hci" ]]; then
    PATCH="HCI"
elif [[ "$1" == "-sds" ]]; then
    PATCH="SDS"
elif [[ "$1" == "-help" ]]; then
    patch_usage
    exit 0
else
    echo "Unknown option: $1"
    patch_usage
    exit 1
fi

EXPECTED_VERSION=2.10.0

DRY_RUN=true # uncomment for dry run

if (mkdir -p /tmp/br-post-install-patch-2.10.0); then
    DIR=/tmp/br-post-install-patch-2.10.0
else
    DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-2.10.0_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-2.10.0.sh script to $LOG"

#check_cmd:
# Returns:
#   0 on finding the command
#   1 if the command does not exist
check_cmd() {
    type "$1" >/dev/null
    echo $?
}

update_hotfix_configmap() {
    hotfix=$1
    applied_on=$(date '+%Y-%m-%dT%T')
    if (oc -n "$BR_NS" get configmap bnr-hotfixes -o yaml 1>$DIR/bnr-hotfixes.save.yaml 2>&1); then
        patch="[{\"op\": \"add\", \"path\": \"/data/${hotfix}-applied-on\", \"value\": \"${applied_on}\"}]"
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" patch configmap bnr-hotfixes --type=json -p "${patch}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" patch configmap bnr-hotfixes --type=json -p "${patch}" --dry-run=client -o yaml >$DIR/bnr-hotfixes.patch.yaml
    else
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" create configmap bnr-hotfixes --from-literal="${hotfix}"-applied-on="${applied_on}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" create configmap bnr-hotfixes --from-literal="${hotfix}"-applied-on="${applied_on}" --dry-run=client -o yaml >$DIR/bnr-hotfixes.patch.yaml
    fi

}

set_deployment_image() {
    name=$1
    container=$2
    image=$3
    if (oc -n "$BR_NS" get deployment/"${name}" -o yaml >$DIR/"${name}".save.yaml); then
        echo "Patching deployment/${name} image..."
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" set image deployment/"${name}" "${container}"="${image}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" set image deployment/"${name}" "${container}"="${image}" --dry-run=client -o yaml >$DIR/"${name}".patch.yaml
        oc -n "$BR_NS" rollout status --timeout=65s deployment/"${name}"
    else
        echo "ERROR: Failed to save original deployment/${name}. Skipped updates."
    fi
}

update_backuplocation_role() {
    BSL_ROLES=$(
        cat <<EOF
- apiGroups:
  - config.openshift.io
  resources:
  - clusterversions
  verbs:
    - get
    - list
- apiGroups:
  - application.isf.ibm.com
  resources:
  - clusters
  verbs:
    - get
    - list
EOF
    )
    echo "Patching clusterrole backup-location-role-${BR_NS} ..."
    oc get clusterrole backup-location-role-"${BR_NS}" -o yaml >$DIR/clusterrole-backup-location-role.save.yaml
    [ -z "$DRY_RUN" ] && echo -e "$(cat $DIR/clusterrole-backup-location-role.save.yaml)\n${BSL_ROLES}" | oc apply -f -
    [ -n "$DRY_RUN" ] && echo -e "$(cat $DIR/clusterrole-backup-location-role.save.yaml)\n${BSL_ROLES}" >$DIR/clusterrole-backup-location-role.patch.yaml

}

set_velero_image() {
    image=$1
    if (oc -n "$BR_NS" get dpa velero -o yaml >$DIR/velero.save.yaml); then
        echo "Patching deployment/velero image..."
        patch="[{\"op\": \"replace\", \"path\": \"/spec/unsupportedOverrides/veleroImageFqin\", \"value\":\"${image}\"}]"
        [ -z "$DRY_RUN" ] && oc -n "$BR_NS" patch dataprotectionapplication.oadp.openshift.io velero --type='json' -p="${patch}"
        [ -n "$DRY_RUN" ] && oc -n "$BR_NS" patch dataprotectionapplication.oadp.openshift.io velero --type='json' -p="${patch}" --dry-run=client -o yaml >$DIR/velero.patch.yaml
        echo "Velero Deployement is restarting with replacement image"
        oc wait --namespace "$BR_NS" deployment.apps/velero --for=jsonpath='{.status.readyReplicas}'=1
    fi
}

update_isf_operator_csv() {
    name=$1
    image=$2
    if (oc get csv -n "$ISF_NS" "$name" -o yaml >$DIR/"$name".save.yaml); then
        echo "Scaling down isf-data-protection-operator-controller-manager deployment..."
        [ -z "$DRY_RUN" ] && oc scale deployment -n "$ISF_NS" isf-data-protection-operator-controller-manager --replicas=0

        echo "Patching clusterserviceversion/$name..."
        index=$(oc get csv -n "$ISF_NS" "$name" -o json | jq '[.spec.install.spec.deployments[].name] | index("isf-data-protection-operator-controller-manager")')
        patch="[{\"op\":\"replace\", \"path\":\"/spec/install/spec/deployments/${index}/spec/template/spec/containers/0/image\", \"value\":\"${image}\"}]"

        [ -z "$DRY_RUN" ] && oc patch csv -n "$ISF_NS" "$name" --type='json' -p "${patch}"
        [ -n "$DRY_RUN" ] && oc patch csv -n "$ISF_NS" "$name" --type='json' -p "${patch}" --dry-run=client -o yaml >$DIR/"$name".patch.yaml

        echo "Scaling up isf-data-protection-operator-controller-manager deployment..."
        [ -z "$DRY_RUN" ] && oc scale deployment -n "$ISF_NS" isf-data-protection-operator-controller-manager --replicas=1
    else
        echo "ERROR: Failed to save original clusterserviceversion/$name. Skipped updates."
    fi
}

REQUIREDCOMMANDS=("oc" "jq")
echo -e "Checking for required commands: ${REQUIREDCOMMANDS[*]}"
for COMMAND in "${REQUIREDCOMMANDS[@]}"; do
    IS_COMMAND=$(check_cmd "$COMMAND")
    if [ "$IS_COMMAND" -ne 0 ]; then
        echo "ERROR: $COMMAND command not found, install $COMMAND command to apply patch"
        exit "$IS_COMMAND"
    fi
done

oc whoami >/dev/null || (
    echo "Not logged in to your cluster"
    exit 1
)

ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)
if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
if [ -n "$BR_NS" ]; then
    HUB=true
else
    BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace 2 >/dev/null)
fi

if [ -z "$BR_NS" ]; then
    echo "ERROR: No B&R installation found. Exiting."
    exit 1
fi

AGENTCSV=$(oc -n "$BR_NS" get csv -o name | grep ibm-dataprotectionagent)
VERSION=$(oc -n "$BR_NS" get "$AGENTCSV" -o custom-columns=:spec.version --no-headers)
if [ -z "$VERSION" ]; then
    echo "ERROR: Could not get B&R version. Skipped updates"
    exit 0
elif [[ $VERSION != $EXPECTED_VERSION* ]]; then
    echo "This patch applies to B&R version $EXPECTED_VERSION only, you have $VERSION. Skipped updates"
    exit 0
fi

if [ -n "$HUB" ]; then
    echo "Apply patches to hub..."

    update_backuplocation_role

    backuplocation_img=BACKUP-LOCATION-IMAGE
    set_deployment_image backup-location-deployment backup-location-container "${backuplocation_img}"

    backupservice_img=BACKUP-SERVICE-IMAGE
    set_deployment_image backup-service backup-service ${backupservice_img}

    backuppolicy_img=BACKUP-POLICY-IMAGE
    set_deployment_image backuppolicy-deployment backuppolicy-container ${backuppolicy_img}

    guardiandpoperator_img=GUARDIAN-DP-OPERATOR-IMAGE
    set_deployment_image guardian-dp-operator-controller-manager manager ${guardiandpoperator_img}

fi

transactionmanager_img=TRANSACTION-MANAGER-IMAGE
set_deployment_image transaction-manager transaction-manager ${transactionmanager_img}

velero_img=VELERO-IMAGE
set_velero_image ${velero_img}

[ "$PATCH" == "HCI" ] && isfdataprotection_img=ISF-DATA-PROTECTION-IMAGE-HCI
[ "$PATCH" == "SDS" ] && isfdataprotection_img=ISF-DATA-PROTECTION-IMAGE-SDS
update_isf_operator_csv isf-operator.v2.10.0 "${isfdataprotection_img}"

update_hotfix_configmap "hotfix-"${EXPECTED_VERSION}.${HOTFIX_NUMBER}

echo "Please verify that the pods for the following deployment have successfully restarted:"
if [ -n "$HUB" ]; then
    printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "backup-location-deployment"
    printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "backuppolicy-deployment"
    printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "backup-service"
    printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "guardian-dp-operator-controller-manager"
fi
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "transaction-manager"
printf "  %-${#BR_NS}s: %s\n" "$BR_NS" "velero"
printf "  %-${#ISF_NS}s: %s\n" "$ISF_NS" "isf-data-protection-operator-controller-manager"
