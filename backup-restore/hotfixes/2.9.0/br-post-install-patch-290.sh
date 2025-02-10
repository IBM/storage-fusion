#!/bin/bash
# Run this script on hub and spoke clusters to apply the latest hotfixes for 2.9.0 release.
# Refer to https://www.ibm.com/support/pages/node/7181447 for additional information.
# Version 02-04-2025

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

mkdir -p /tmp/br-post-install-patch-290
if [ "$?" -eq 0 ]
then DIR=/tmp/br-post-install-patch-290
else DIR=/tmp
fi
LOG=$DIR/br-post-install-patch-290_$$_log.txt
exec &> >(tee -a $LOG)
echo "Writing output of br-post-install-patch-290.sh script to $LOG"

ISF_NS=$(oc get spectrumfusion -A -o custom-columns=NS:metadata.namespace --no-headers)
if [ -z "$ISF_NS" ]; then
    echo "ERROR: No Successful Fusion installation found. Exiting."
    exit 1
fi

BR_NS=$(oc get dataprotectionserver -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
if [ -n "$BR_NS" ]
 then
 HUB=true
else
   BR_NS=$(oc get dataprotectionagent -A --no-headers -o custom-columns=NS:metadata.namespace 2>/dev/null)
fi

if [ -z "$BR_NS" ] 
 then
    echo "ERROR: No B&R installation found. Exiting."
    exit 1
fi

FSIROLETOADD=$(cat <<EOF
- apiGroups:
  - service.isf.ibm.com
  resources:
  - fusionserviceinstances
  verbs:
  - get
  - list
  - watch
EOF
    )
    echo "Patching isf-data-protection-operator-controller-manager clusterrole..."
    CLUSTERROLE=`oc get clusterrolebinding -o wide | grep "${ISF_NS}/isf-data-protection-operator-controller-manager" | grep isf-operator.v2.9.0 | awk '{print $2}'`
    oc get ${CLUSTERROLE} -o yaml > $DIR/clusterrole-isf-data-protection.save.yaml
    echo -e "$(cat $DIR/clusterrole-isf-data-protection.save.yaml)\n${FSIROLETOADD}" | oc apply -f -
   
    if (oc get csv -n $ISF_NS isf-operator.v2.9.0 -o yaml > $DIR/isf-operator.v2.9.0.save.yaml)
      then
        if [[ "$PATCH" == "HCI" ]]; then
            echo "Patching HCI clusterserviceversion/isf-operator.v2.9.0..."
            oc patch csv -n ${ISF_NS} isf-operator.v2.9.0  --type='json' -p='[{"op":"replace", "path":"/spec/install/spec/deployments/1/spec/template/spec/containers/0/image", "value":"cp.icr.io/cp/fusion-hci/isf-data-protection-operator@sha256:d6f1081340eed3b18e714acd86e4cc406b9c43ba92705cad76c7688c6d325581"}]'
        elif [[ "$PATCH" == "SDS" ]]; then
            echo "Patching SDS clusterserviceversion/isf-operator.v2.9.0..."
            oc patch csv -n ${ISF_NS} isf-operator.v2.9.0  --type='json' -p='[{"op":"replace", "path":"/spec/install/spec/deployments/1/spec/template/spec/containers/0/image", "value":"cp.icr.io/cp/fusion-sds/isf-data-protection-operator@sha256:8d0d7ef3064271b948a4b9a3b05177ae959613a0b353062a286edb972112cfc4"}]'
        else
            echo "ERROR: Unknown patch location. Skipped updates"
        fi
    else
        echo "ERROR: Failed to save original clusterserviceversion/isf-operator.v2.9.0. Skipped updates."
    fi

AGENTCSV=$(oc -n "$BR_NS" get csv -o name | grep ibm-dataprotectionagent)
VERSION=$(oc -n "$BR_NS" get "$AGENTCSV" -o custom-columns=:spec.version --no-headers)
if [ -z "$VERSION" ] 
  then
    echo "ERROR: Could not get B&R version. Skipped updates"
elif [[ $VERSION != 2.9.0* ]]; then
    echo "This patch applies to B&R version 2.9.0 only, you have $VERSION. Skipped updates"
fi

if [[ "$VERSION" == 2.9.0* ]]; then
    if (oc get deployment -n $BR_NS transaction-manager -o yaml > $DIR/transaction-manager-deployment.save.yaml)
    then
        echo "Patching deployment/transaction-manager image..."
        oc patch deployment/transaction-manager -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"transaction-manager","image":"cp.icr.io/cp/bnr/guardian-transaction-manager@sha256:0eaa0aca6f1decf69be3bb7d4fcc60a8c00a4ee18592452d85869c70d690c0cc"}]}}}}'
    else
        echo "ERROR: Failed to save original transaction-manager deployment. Skipped updates."
    fi

    if (oc -n "$BR_NS" get csv guardian-dm-operator.v2.9.0 -o yaml > $DIR/guardian-dm-operator.v2.9.0-original.yaml)
    then
      echo "Saved original configuration of guardian-dm-operator to $DIR/guardian-dm-operator.v2.9.0-original.yaml."
    else
      echo "ERROR: Failed to save original guardian-dm-operator.v2.9.0 csv. Skipped Patch."
    fi

    if (oc get configmap -n "$BR_NS" guardian-dm-image-config -o yaml > $DIR/guardian-dm-image-config-original.yaml)
    then
      echo "Scaling down guardian-dm-controller-manager deployment..."
      oc scale deployment guardian-dm-controller-manager -n "$BR_NS" --replicas=0
      oc set data -n "$BR_NS" cm/guardian-dm-image-config DM_IMAGE=icr.io/cpopen/guardian-datamover@sha256:1c8af5f70feda2d0074b90cc5fdeb53409718691530e7d64e8d8a3574cc0befa
      oc patch csv -n $BR_NS guardian-dm-operator.v2.9.0 --type='json' -p='[{"op":"replace", "path":"/spec/install/spec/deployments/0/spec/template/spec/containers/1/image", "value":"icr.io/cpopen/guardian-dm-operator@sha256:736babab4ab22bf3d2bdf6ea54100031a3e800cea9bf2226a6c1a80a69206ea6"}]'
      echo "Scaling up guardian-dm-controller-manager deployment..."
      oc scale deployment guardian-dm-controller-manager -n "$BR_NS" --replicas=1
    else
      echo "ERROR: Failed to save original configmap guardian-dm-image-config. skipped updates"
    fi

    if [ -n "$HUB" ]
    then
      echo "Apply patches to hub..."

      if (oc get deployment -n $BR_NS job-manager -o yaml > $DIR/job-manager-deployment.save.yaml)
      then
        echo "Patching job-manager-deployment image..."
        oc patch deployment job-manager -n $BR_NS -p '{"spec":{"template":{"spec":{"containers":[{"name":"job-manager-container","image":"cp.icr.io/cp/bnr/guardian-job-manager@sha256:8daeb9bf614d8e72aeded5f0e17e1a93bc5c071638e6adff1c28c30650ff26e0"}]}}}}'
      else
        echo "ERROR: Failed to save original job-manager-deployment. Skipped updates."
      fi
    fi
fi

echo "Please verify that these pods have successfully restarted after hotfix update in their corresponding namespace:"
printf "  %-25s: %s\n" "$ISF_NS" "isf-data-protection-operator-controller-manager"
if [[ "$VERSION" == 2.9.0* ]]; then
    printf "  %-25s: %s\n" "$BR_NS" "transaction-manager"
    printf "  %-25s: %s\n" "$BR_NS" "guardian-dm-controller-manager"
    printf "  %-25s: %s\n" "$BR_NS" "job-manager if HUB cluster"
fi
