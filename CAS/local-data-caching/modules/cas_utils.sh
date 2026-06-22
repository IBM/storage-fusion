#!/usr/bin/env bash

# GUARD CLAUSE: Prevent sourcing this file multiple times
if [[ -n "${LOADED_CAS_UTILS_SH:-}" ]]; then
    return 0
fi
export LOADED_CAS_UTILS_SH=1

# shellcheck source=modules/df_utils.sh
source "$ROOT_DIR/modules/df_utils.sh"

#----------------------------------------
# Function: Patch the CAS FusionServiceDefinition with the CAS version
#----------------------------------------
patch_cas_fsd() {
  if ! oc patch fusionservicedefinition ibm-cas-service \
  -n ibm-spectrum-fusion-ns \
  -p='[{"op": "replace", "path": "/spec/onboarding/serviceOperatorSubscription/catalogSourceDetails/imageTag", "value": "'"$CAS_VERSION"'"}]' \
  --type='json' >/dev/null 2>&1; then
		logger error "Failed to set CAS version in FusionServiceDefinition."
		return 1
	fi
}

#----------------------------------------
# Function: Patch CasInstall with CPU docling/vllm flags
#----------------------------------------
patch_cas_install_cpu_flags() {
  local namespace="${1}"
  local name="${2}"

  # Get RELATED_IMAGE_CAS_DOCLING_CUDA value from cas-operator deployment
  local docling_image
  docling_image=$(oc get deployment ibm-isf-cas-operator-controller-manager -n "${namespace}" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RELATED_IMAGE_CAS_DOCLING_CUDA")].value}' 2>/dev/null)

  if [[ -z "${docling_image}" ]]; then
    logger error "Failed to retrieve RELATED_IMAGE_CAS_DOCLING_CUDA from cas-operator deployment in namespace '${namespace}'."
    return 1
  fi

  # Get RELATED_IMAGE_CAS_VLLM_CUDA value from cas-operator deployment
  local vllm_image
  vllm_image=$(oc get deployment ibm-isf-cas-operator-controller-manager -n "${namespace}" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RELATED_IMAGE_CAS_VLLM_CUDA")].value}' 2>/dev/null)

  if [[ -z "${vllm_image}" ]]; then
    logger error "Failed to retrieve RELATED_IMAGE_CAS_VLLM_CUDA from cas-operator deployment in namespace '${namespace}'."
    return 1
  fi

  if ! oc patch casinstall "${name}" -n "${namespace}" --type=merge -p '{
    "spec": {
      "flags": [
        "RELATED_IMAGE_CAS_DOCLING_CPU='"${docling_image}"'",
        "DOCLING_GPU_TYPE=cpu",
        "RELATED_IMAGE_CAS_VLLM_CPU='"${vllm_image}"'",
        "VLLM_GPU_TYPE=cpu"
      ]
    }
  }' >/dev/null 2>&1; then
    logger error "Failed to patch CasInstall '${name}' in namespace '${namespace}'."
    return 1
  fi
}

#----------------------------------------
# Function: Patch CasInstall immediately after creation
#----------------------------------------
patch_cas_install() {
  local namespace="${1}"
  local name="${2}"

  # Patch CAS install to use CPU, if configured
  if [[ "${CAS_RHAI_USE_CPU}" == "true" ]]; then
    logger info "Patching CasInstall to use CPU for RHAI"
    patch_cas_install_cpu_flags "${namespace}" "${name}"
  fi
}

#----------------------------------------
# Function: Wait for CasInstall CR to exist
#----------------------------------------
wait_for_casinstall() {
  local namespace="${1}"
  local name="${2}"

  wait_for_condition \
    "Waiting for CasInstall CR '${name}' in namespace '${namespace}'" \
    "${CAS_INSTALL_TIMEOUT}" \
    "oc get casinstall '${name}' -n '${namespace}'"
}

#----------------------------------------
# Function: Configure Scale watch for CAS Kafka instance
#----------------------------------------
configure_scale_watch() {
  NAMESPACE="${1}"
  FS_NAME="${2}"

  TEMP_DIR=$(mktemp -d)
  cd "${TEMP_DIR}" || {
    logger error "Failed to change directory to ${TEMP_DIR}"
    return 1
  }

  config_dir="/mnt/${FS_NAME}/${NAMESPACE}"
  config_file="${NAMESPACE}.watch.config"

  oc extract -n "${NAMESPACE}" secret/kafka-cluster-ca-cert --keys=ca.crt --to=-> cluster_ca.crt
  oc extract -n "${NAMESPACE}" secret/cas-user --keys=user.crt --to=-> user.crt
  oc extract -n "${NAMESPACE}" secret/cas-user --keys=user.key --to=-> user.key
  openssl x509 -in user.crt -out user.pem -outform PEM

  cas_pw="$(oc extract -n "${NAMESPACE}" secret/cas-user --keys=user.password --to=-)"

  cat <<EOF >"${config_file}"
SINK_AUTH_TYPE:CERT
CA_CERT_LOCATION:${config_dir}/cluster_ca.crt
CLIENT_KEY_FILE_LOCATION:${config_dir}/user.key
CLIENT_PEM_CERT_LOCATION:${config_dir}/user.pem
CLIENT_KEY_FILE_PASSWORD:$cas_pw
EOF

  scale_core_pod="$(get_scale_core_pod)"
  logger info "Configuring Scale watch through Pod: ${scale_core_pod}"
  scale_core_exec "sudo mkdir -p ${config_dir} && sudo chmod 755 ${config_dir}"
  oc rsync -n "${SCALE_NAMESPACE}" ./ "${scale_core_pod}:${config_dir}/" -c gpfs

  rm -rf "${TEMP_DIR}"

  op_cm="$(oc get configmap -n "${NAMESPACE}" operator-config -oyaml --ignore-not-found 2> /dev/null)"

  if [[ -n "${op_cm}" ]]; then
	  oc patch -n "${NAMESPACE}" configmap operator-config \
		  --type=merge \
		  -p '{"data": {"KAFKA_AUTHEN_LOCAL": "'"${config_dir}/${config_file}"'"}}'
  else
    cat <<EOF | oc apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: operator-config
  labels:
    app.kubernetes.io/name: cas.isf.ibm.com
    app.kubernetes.io/component: kafka-op-config
data:
  KAFKA_AUTHEN_LOCAL: ${config_dir}/${config_file}
EOF
  fi

  logger success "Scale watch configured"
}
