#!/usr/bin/env bash

#----------------------------------------
# Function: Configure Scale watch for CAS Kafka instance
#----------------------------------------
configure_scale_watch() {
  NAMESPACE="${1}"
  FS_NAME="${2}"

  TEMP_DIR=$(mktemp -d)
  cd "${TEMP_DIR}"

  config_dir="/mnt/${FS_NAME}/${NAMESPACE}"
  config_file="${NAMESPACE}.watch.config"

  oc extract -n ${NAMESPACE} secret/kafka-cluster-ca-cert --keys=ca.crt --to=-> cluster_ca.crt
  oc extract -n ${NAMESPACE} secret/cas-user --keys=user.crt --to=-> user.crt
  oc extract -n ${NAMESPACE} secret/cas-user --keys=user.key --to=-> user.key
  openssl x509 -in user.crt -out user.pem -outform PEM

  cas_pw="$(oc extract -n ${NAMESPACE} secret/cas-user --keys=user.password --to=-)"

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

  op_cm="$(oc get configmap -n ${NAMESPACE} operator-config -oyaml --ignore-not-found 2> /dev/null)"

  if [[ "x${op_cm}" != "x" ]]; then
	  oc patch -n $NAMESPACE configmap operator-config \
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
