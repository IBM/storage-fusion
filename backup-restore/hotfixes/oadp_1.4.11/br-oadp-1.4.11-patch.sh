#!/bin/bash
# Run this script on hub and spoke clusters to apply the hotfixes for oadp 1.4.11 issue.

patch_usage() {
    echo "Patches the Fusion Backup & Restore install for OADP 1.4.11 issue."
    echo "This command should be run on each hub and spoke of a Fusion Backup & Restore install"
    echo "Usage: $0 [ -help ] [ -dryrun ] [-logdir <path>]"
    echo "Options:"
    echo "  -help             Display usage"
    echo "  -dryrun           Run without applying fixes. Proposed patches will be written to logdir."
    echo "  -logdir           Directory to log output, patches, and saved YAMLs. Defaults to /tmp"
}

DRY_RUN=
while [[ $# -gt 0 ]]; do
    case "${1}" in
    -dryrun)
        DRY_RUN="--dry-run=client"
        shift
        ;;
    -logdir)
        shift
        DIR="${1}"
        shift
        ;;
    -help)
        patch_usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        patch_usage
        exit 1
        ;;
    esac
done

[ -z "$DIR" ] && DIR=/tmp
if ! mkdir -p "${DIR}"; then
    DIR=/tmp
fi
LOG=$DIR/br-oadp-1.4.11-patch_$$_log.txt
exec &> >(tee -a "$LOG")
echo "Writing output of $0 script to $LOG"

# check_cmd:
#   Returns 0 if the command exists, 1 if it does not.
check_cmd() {
    type "$1" > /dev/null
    echo $?
}

check_for_required_dependencies() {
    REQUIREDCOMMANDS=("oc" "jq")
    echo -e "Checking for required commands: ${REQUIREDCOMMANDS[*]}"
    for COMMAND in "${REQUIREDCOMMANDS[@]}"; do
        IS_COMMAND=$(check_cmd "$COMMAND")
        if [ "$IS_COMMAND" -ne 0 ]; then
            echo "ERROR: $COMMAND command not found, install $COMMAND command to apply patch"
            exit "$IS_COMMAND"
        fi
    done

    echo -e "Checking for required version of oc 4.14+"
    OC_VERSION=$(oc version --client -o json | jq -r '.clientVersion.gitVersion')
    MAJOR=$(echo "${OC_VERSION}" | sed 's/v//' | cut -d. -f1)
    MINOR=$(echo "${OC_VERSION}" | sed 's/v//' | cut -d. -f2)
    if [ "${MAJOR}" -lt 4 ]; then
        echo "Detected oc client version ${OC_VERSION}. Minimum 4.14"
        exit 1
    fi
    if [ "${MINOR}" -lt 14 ]; then
        echo "Detected oc client version ${OC_VERSION}. Minimum 4.14"
        exit 1
    fi
}

check_for_required_dependencies

if ! oc whoami > /dev/null; then
    echo "Not logged in to your cluster"
    exit 1
fi

ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)
if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

if BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null) && [ -n "$BR_NS" ]; then
    true
else
    BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
fi

if [ -z "$BR_NS" ]; then
    echo "ERROR: No B&R installation found. Exiting."
    exit 1
fi

BR_VERSION=$(oc -n "$BR_NS" get dataprotectionagent -o custom-columns=:status.upgradeVersionAvailable --no-headers | grep -vi none)
[ -z "$BR_VERSION" ] && BR_VERSION=$(oc -n "$BR_NS" get dataprotectionagent -o custom-columns=:status.installedVersion --no-headers)
export BR_VERSION
echo "Backup & Restore Version: $BR_VERSION"

if [ -z "$BR_VERSION" ]; then
    echo "ERROR: Could not determine B&R Version. Exiting."
    exit 1
fi

AGENT_CSV=$(oc -n "$BR_NS" get csv -o name | grep ibm-dataprotectionagent)
# Build the properties object as a plain string, then JSON-encode it as the patch value.
AGENT_CSV_PROPS='{"properties":[{"type":"olm.gvk","value":{"group":"dataprotectionagent.idp.ibm.com","kind":"DataProtectionAgent","version":"v1"}},{"type":"olm.package","value":{"packageName":"ibm-dataprotectionagent","version":"'"${BR_VERSION}"'"}},{"type":"olm.package.required","value":{"packageName":"guardian-dm-operator","versionRange":">= '"${BR_VERSION}"'-1"}},{"type":"olm.package.required","value":{"packageName":"guardian-dp-operator","versionRange":">= '"${BR_VERSION}"'-1"}},{"type":"olm.package.required","value":{"packageName":"redhat-oadp-operator","versionRange":">= 1.4.1 <1.7.0 !1.4.11"}}]}'
# Escape inner double-quotes so the props string is valid as a JSON string value.
AGENT_CSV_PROPS_ESCAPED="${AGENT_CSV_PROPS//\"/\\\"}"
AGENT_CSV_PATCH="[{\"op\":\"replace\",\"path\":\"/metadata/annotations/operatorframework.io~1properties\",\"value\":\"${AGENT_CSV_PROPS_ESCAPED}\"}]"
oc patch -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} "$AGENT_CSV" --type=json -p "${AGENT_CSV_PATCH}"

OADP_SUB=$(oc -n "$BR_NS" get subs -o name | grep oadp)
OADP_CSV=$(oc -n "$BR_NS" get csv -o name | grep oadp)
OADP_VER=$(oc -n "$BR_NS" get "$OADP_CSV" -o custom-columns=:spec.version --no-headers)
OADP_DEPLOYMENT="openshift-adp-controller-manager"

if [ "$OADP_VER" == "1.4.11" ]; then
    oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} delete "$OADP_CSV"
    oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} delete deployment "$OADP_DEPLOYMENT"
    oc -n "$BR_NS" ${DRY_RUN:+"${DRY_RUN}"} patch "$OADP_SUB" --type=merge -p '{"spec":{"startingCSV":null}}'

    if [ -z "$DRY_RUN" ]; then
        NEW_OADP_CSV=$(oc -n "$BR_NS" get csv -l "operators.coreos.com/redhat-oadp-operator.$BR_NS" -o name)
        while [ -z "$NEW_OADP_CSV" ]; do
            UIP=$(oc -n "$BR_NS" get installplan -o custom-columns=:.metadata.name,:.spec.approved -l operators.coreos.com/redhat-oadp-operator."$BR_NS" | awk '/ false/ {print $1}')
            [ -n "$UIP" ] && oc -n "$BR_NS" patch installplan "$UIP" --type merge --patch '{"spec":{"approved":true}}'
            echo "Waiting for new OADP to be installed..."
            sleep 5
            NEW_OADP_CSV=$(oc -n "$BR_NS" get csv -l "operators.coreos.com/redhat-oadp-operator.$BR_NS" -o name)
        done
        echo "$NEW_OADP_CSV is created"

        until oc get deployment "${OADP_DEPLOYMENT}" -n "${BR_NS}" &> /dev/null; do
            echo "Waiting for deployment ${OADP_DEPLOYMENT} to be created..."
            sleep 5
        done

        echo "Deployment $OADP_DEPLOYMENT created! Now waiting for it to become fully available..."
        oc -n "$BR_NS" rollout status deployment/"${OADP_DEPLOYMENT}" --timeout=5m
        oc -n "$BR_NS" get deployment "${OADP_DEPLOYMENT}"
    fi
fi
