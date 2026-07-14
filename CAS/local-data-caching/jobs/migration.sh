#!/bin/bash
set -euo pipefail

# CAS Data Cache Migration - Job Script
# Executes inside Kubernetes Job pod with cluster access
# Performs actual migration operations with database and filesystem access

# ============================================================================
# 0. INSTALL REQUIRED CLI TOOLS
# ============================================================================

install_cli_tools() {
  log "Checking for required CLI tools..."

  # Detect OS/distro once — needed by multiple install blocks below
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID}"
    log "Detected OS: ${OS_ID}"
  else
    log_error "Cannot detect OS - /etc/os-release not found"
    return 1
  fi

  # kubectl
  if command -v kubectl &>/dev/null; then
    log "kubectl already installed: $(kubectl version --client 2>/dev/null | head -1)"
  else
    log "Installing kubectl..."
    case "${OS_ID}" in
      debian|ubuntu)
        apt-get update -qq
        apt-get install -y -qq curl
        ;;
      rhel|centos|fedora)
        microdnf install -y tar gzip
        ;;
      *)
        log_error "Unsupported OS: ${OS_ID}"
        return 1
        ;;
    esac
    curl -sSLo /tmp/kubectl \
      "https://dl.k8s.io/release/$(curl -sSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -m 755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
    if ! command -v kubectl &>/dev/null; then
      log_error "kubectl installation failed — binary not found after install"
      return 1
    fi
    log_success "kubectl installed: $(kubectl version --client 2>/dev/null | head -1)"
  fi

  # psql
  if command -v psql &>/dev/null; then
    log "psql already installed: $(psql --version)"
  else
    log "Installing postgresql-client..."
    case "${OS_ID}" in
      debian|ubuntu)
        apt-get update -qq
        apt-get install -y -qq postgresql-client
        ;;
      rhel|centos|fedora)
        microdnf install -y postgresql
        ;;
      *)
        log_error "Unsupported OS: ${OS_ID}"
        return 1
        ;;
    esac
    if ! command -v psql &>/dev/null; then
      log_error "psql installation failed — binary not found after install"
      return 1
    fi
    log_success "psql installed: $(psql --version)"
  fi

  # yq
  if command -v yq &>/dev/null; then
    log "yq already installed: $(yq --version 2>/dev/null)"
  else
    log "Installing yq..."
    curl -sSLo /tmp/yq \
      "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
    install -m 755 /tmp/yq /usr/local/bin/yq
    rm -f /tmp/yq
    if ! command -v yq &>/dev/null; then
      log_error "yq installation failed — binary not found after install"
      return 1
    fi
    log_success "yq installed: $(yq --version 2>/dev/null)"
  fi

  log_success "All required CLI tools are available"
}

# ============================================================================
# 1. LOGGING AND UTILITIES
# ============================================================================

# DRY_RUN_JOB mode: echo commands instead of executing
DRY_RUN_JOB="${DRY_RUN_JOB:-false}"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

log_error() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >&2
}

log_success() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SUCCESS: $*"
}

# ============================================================================
# 2. STATE MANAGEMENT FUNCTIONS
# ============================================================================

update_migration_progress() {
  local phase="${1}"
  local status="${2}"
  local backup_path="${3:-}"
  
  log "Updating migration state: ${phase} -> ${status}"
  
  # Check if ConfigMap exists, create if not
  if ! kubectl get configmap cas-migration-state -n "${CAS_NAMESPACE}" &>/dev/null; then
    log "Creating cas-migration-state ConfigMap..."
    if ! kubectl create configmap cas-migration-state -n "${CAS_NAMESPACE}" \
      --from-literal="${phase}-migration-status=${status}" \
      --from-literal="${phase}-migration-timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --from-literal="${phase}-migration-backup-path=${backup_path}"; then
      log_error "Failed to create state ConfigMap"
      return 1
    fi
    log_success "State ConfigMap created"
  else
    # Update existing ConfigMap
    if ! kubectl patch configmap cas-migration-state -n "${CAS_NAMESPACE}" \
      --type merge \
      -p "{\"data\":{\"${phase}-migration-status\":\"${status}\",\"${phase}-migration-timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"${phase}-migration-backup-path\":\"${backup_path}\"}}"; then
      log_error "Failed to update state ConfigMap"
      return 1
    fi
    log_success "State updated successfully"
  fi
}

# ============================================================================
# 3. DATABASE ACCESS
# ============================================================================

get_database_credentials() {
  log "Retrieving database credentials from Secret..."
  
  # Get database credentials from cluster-parade-app Secret
  local secret_name="cluster-parade-app"
  
  DB_HOST=$(kubectl get secret "${secret_name}" -n "${CAS_NAMESPACE}" \
    -o jsonpath='{.data.host}' | base64 -d)
  
  DB_USER=$(kubectl get secret "${secret_name}" -n "${CAS_NAMESPACE}" \
    -o jsonpath='{.data.username}' | base64 -d)
  
  DB_PASS=$(kubectl get secret "${secret_name}" -n "${CAS_NAMESPACE}" \
    -o jsonpath='{.data.password}' | base64 -d)
  
  DB_NAME=$(kubectl get secret "${secret_name}" -n "${CAS_NAMESPACE}" \
    -o jsonpath='{.data.dbname}' | base64 -d)
  
  export PGPASSWORD="${DB_PASS}"
  
  log_success "Database credentials retrieved"
}

test_database_connection() {
  log "Testing database connection..."
  log "  Host: ${DB_HOST}"
  log "  Port: 5432"
  log "  Database: ${DB_NAME}"
  log "  User: ${DB_USER}"
  
  # Test with verbose output and timeout
  if timeout 10 psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" \
    -c "SELECT 1" 2>&1; then
    log_success "Database connection successful"
    return 0
  else
    local exit_code=$?
    log_error "Database connection failed (exit code: ${exit_code})"
    
    # Try to diagnose the issue
    log "Attempting DNS resolution..."
    if command -v nslookup &>/dev/null; then
      nslookup "${DB_HOST}" 2>&1 || true
    elif command -v dig &>/dev/null; then
      dig "${DB_HOST}" 2>&1 || true
    else
      log "DNS tools not available"
    fi
    
    log "Attempting ping..."
    if command -v ping &>/dev/null; then
      timeout 3 ping -c 2 "${DB_HOST}" 2>&1 || true
    else
      log "ping not available"
    fi
    
    return 1
  fi
}

# ============================================================================
# 4. PRE-MIGRATION OPERATIONS
# ============================================================================

# get_s3_cachefs_datasources — prints newline-delimited names of S3 datasources
# that reference FILESYSTEM_NAME in spec.s3.fileSystemName
get_s3_cachefs_datasources() {
  kubectl get datasources -n "${CAS_NAMESPACE}" \
    -o jsonpath='{range .items[?(@.spec.s3.fileSystemName=="'"${FILESYSTEM_NAME}"'")]}{.metadata.name}{"\n"}{end}' \
    2>/dev/null
}

backup_datasources() {
  local backup_dir="${1}"

  log "Backing up S3+cache-fs DataSources to: ${backup_dir}"

  # Create backup directory
  mkdir -p "${backup_dir}"

  # Collect S3+cache-fs datasource names
  local s3_ds_names
  s3_ds_names=$(get_s3_cachefs_datasources)

  if [[ -z "${s3_ds_names}" ]]; then
    log "No S3 datasources using filesystem '${FILESYSTEM_NAME}' found — nothing to backup"
    # Write empty list file so verify_backup_exists still has a file to check
    echo '{"apiVersion":"v1","kind":"List","items":[]}' > "${backup_dir}/datasources.yaml"
    return 0
  fi

  # Backup each S3 datasource CR individually into a combined List yaml
  {
    echo "apiVersion: v1"
    echo "kind: List"
    echo "items:"
    while IFS= read -r ds_name; do
      [[ -z "${ds_name}" ]] && continue
      kubectl get datasource "${ds_name}" -n "${CAS_NAMESPACE}" -o yaml 2>/dev/null \
        | yq eval 'del(.spec.disconnect)' - \
        | sed 's/^/- /' \
        | sed '2,$s/^- /  /'
    done <<< "${s3_ds_names}"
  } > "${backup_dir}/datasources.yaml"

  local ds_count
  ds_count=$(echo "${s3_ds_names}" | grep -c '[^[:space:]]')
  log_success "Backed up ${ds_count} S3+cache-fs DataSource(s)"

  # Backup the S3 credentials secrets for each datasource
  mkdir -p "${backup_dir}/secrets"
  while IFS= read -r ds_name; do
    [[ -z "${ds_name}" ]] && continue
    local secret_name
    secret_name=$(kubectl get datasource "${ds_name}" -n "${CAS_NAMESPACE}" \
      -o jsonpath='{.spec.s3.credentials.secretName}' 2>/dev/null)
    if [[ -z "${secret_name}" ]]; then
      log "DataSource '${ds_name}' has no spec.s3.credentials.secretName — skipping secret backup"
      continue
    fi
    log "Backing up secret '${secret_name}' for DataSource '${ds_name}'"
    if ! kubectl get secret "${secret_name}" -n "${CAS_NAMESPACE}" -o yaml \
      > "${backup_dir}/secrets/${ds_name}-credentials.yaml"; then
      log_error "Failed to backup secret '${secret_name}' for DataSource '${ds_name}'"
      return 1
    fi
  done <<< "${s3_ds_names}"
  log_success "S3 credentials secrets backed up"

  # Disconnect each S3+cache-fs DataSource so the Scale watch is torn down
  # Note: do NOT delete PVC/Kafka topic/AFM fileset yet — Document Processor needs
  # them to drain. The datasource is disconnected but not deleted here.
  while IFS= read -r ds_name; do
    [[ -z "${ds_name}" ]] && continue
    log "Patching DataSource '${ds_name}' with spec.disconnect=true"
    if [[ "${DRY_RUN_JOB}" == "true" ]]; then
      log "[DRY-RUN] Would execute: kubectl patch datasource '${ds_name}' -n '${CAS_NAMESPACE}' --type=merge -p '{\"spec\":{\"disconnect\":true}}'"
      continue
    fi
    kubectl patch datasource "${ds_name}" -n "${CAS_NAMESPACE}" \
      --type=merge -p '{"spec":{"disconnect":true}}' || {
      log_error "Failed to patch DataSource '${ds_name}' with disconnect=true"
      return 1
    }
  done <<< "${s3_ds_names}"
  log_success "All S3+cache-fs DataSources disconnected"
}

# wait_for_kafka_lag_zero — waits until the Kafka consumer lag for every
# S3+cache-fs datasource's child topic reaches 0 (or timeout expires).
#
# Uses kafka-consumer-groups.sh inside the Strimzi Kafka pod to query lag.
# The child topic name is taken from the datasource's fsnotify-topic annotation.
# The consumer group is derived as "<fsnotify-topic>" (the group registered by
# the DocumentProcessor consumer for that topic).
wait_for_kafka_lag_zero() {
  local timeout_seconds="${KAFKA_DRAIN_TIMEOUT:-600}"
  local poll_interval=10

  log "=== Waiting for Kafka consumer lag to drain ==="
  log "Timeout: ${timeout_seconds}s  Poll interval: ${poll_interval}s"

  # Locate the Strimzi Kafka pod (label: strimzi.io/kind=Kafka)
  local kafka_pod
  kafka_pod=$(kubectl get pods -n "${CAS_NAMESPACE}" \
    -l "strimzi.io/kind=Kafka" \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -n1)

  if [[ -z "${kafka_pod}" ]]; then
    log "No Strimzi Kafka pod found in namespace '${CAS_NAMESPACE}' — skipping Kafka lag check"
    return 0
  fi
  log "Using Kafka pod: ${kafka_pod}"

  # Collect per-datasource (topic, group) pairs
  local s3_ds_names
  s3_ds_names=$(get_s3_cachefs_datasources)

  if [[ -z "${s3_ds_names}" ]]; then
    log "No S3+cache-fs datasources — skipping Kafka lag check"
    return 0
  fi

  local elapsed=0
  while [[ ${elapsed} -lt ${timeout_seconds} ]]; do
    local all_zero=true

    while IFS= read -r ds_name; do
      [[ -z "${ds_name}" ]] && continue

      local topic
      topic=$(kubectl get datasource "${ds_name}" -n "${CAS_NAMESPACE}" \
        -o jsonpath='{.metadata.annotations.fsnotify-topic}' 2>/dev/null)

      if [[ -z "${topic}" ]]; then
        log "DataSource '${ds_name}' has no fsnotify-topic annotation — skipping"
        continue
      fi

      # Query lag for this topic across all consumer groups
      local lag_output
      lag_output=$(kubectl exec -n "${CAS_NAMESPACE}" "${kafka_pod}" \
        -c kafka -- \
        bin/kafka-consumer-groups.sh \
          --bootstrap-server localhost:9092 \
          --describe --all-groups \
          2>/dev/null | grep "^${topic}\b\|${topic}$\| ${topic} ")

      # Sum the LAG column (column 5 in the output: GROUP TOPIC PARTITION CURRENT-OFFSET LOG-END-OFFSET LAG ...)
      local total_lag=0
      while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        local lag_val
        lag_val=$(echo "${line}" | awk '{print $6}' | grep -E '^[0-9]+$' || echo "0")
        total_lag=$(( total_lag + ${lag_val:-0} ))
      done <<< "${lag_output}"

      log "  DataSource '${ds_name}' topic '${topic}': lag=${total_lag}"

      if [[ ${total_lag} -gt 0 ]]; then
        all_zero=false
      fi
    done <<< "${s3_ds_names}"

    if [[ "${all_zero}" == "true" ]]; then
      log_success "Kafka consumer lag reached 0 for all S3+cache-fs datasource topics"
      return 0
    fi

    log "Kafka lag not yet 0 — waiting ${poll_interval}s (elapsed: ${elapsed}s / ${timeout_seconds}s)"
    sleep "${poll_interval}"
    elapsed=$(( elapsed + poll_interval ))
  done

  log_error "Kafka consumer lag did not reach 0 within ${timeout_seconds}s"
  return 1
}

# wait_for_task_queue_zero — waits until the Document Processor task queue
# depth reaches 0, queried from the cast-runtime pod's /metrics endpoint.
#
# Metric: cast_task_queue_depth (gauge exposed by cast-runtime container)
# Label:  dp_name=<documentprocessor-name>
wait_for_task_queue_zero() {
  local timeout_seconds="${TASK_QUEUE_DRAIN_TIMEOUT:-600}"
  local poll_interval=10

  log "=== Waiting for Document Processor task queues to drain ==="
  log "Timeout: ${timeout_seconds}s  Poll interval: ${poll_interval}s"

  # Discover DocumentProcessors that reference S3+cache-fs datasources
  local s3_ds_names
  s3_ds_names=$(get_s3_cachefs_datasources)

  if [[ -z "${s3_ds_names}" ]]; then
    log "No S3+cache-fs datasources — skipping task queue drain check"
    return 0
  fi

  # Build set of DocumentProcessor names associated with affected datasources
  local dp_names=""
  while IFS= read -r ds_name; do
    [[ -z "${ds_name}" ]] && continue
    # Find DPs whose domain references this datasource
    local dp_list
    dp_list=$(kubectl get documentprocessors -n "${CAS_NAMESPACE}" \
      --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null)
    while IFS= read -r dp_name; do
      [[ -z "${dp_name}" ]] && continue
      # Check if any domain associated with this DP references our datasource
      local dp_domains
      dp_domains=$(kubectl get documentprocessor "${dp_name}" -n "${CAS_NAMESPACE}" \
        -o jsonpath='{.spec.domains[*]}' 2>/dev/null | tr ' ' '\n')
      while IFS= read -r domain_name; do
        [[ -z "${domain_name}" ]] && continue
        local domain_ds
        domain_ds=$(kubectl get domain "${domain_name}" -n "${CAS_NAMESPACE}" \
          -o jsonpath='{.spec.dataSources[*]}' 2>/dev/null | tr ' ' '\n')
        if echo "${domain_ds}" | grep -qx "${ds_name}"; then
          if ! echo "${dp_names}" | grep -qx "${dp_name}"; then
            dp_names="${dp_names:+${dp_names}$'\n'}${dp_name}"
          fi
        fi
      done <<< "${dp_domains}"
    done <<< "${dp_list}"
  done <<< "${s3_ds_names}"

  if [[ -z "${dp_names}" ]]; then
    log "No DocumentProcessors found for S3+cache-fs datasources — skipping task queue check"
    return 0
  fi

  local elapsed=0
  while [[ ${elapsed} -lt ${timeout_seconds} ]]; do
    local all_zero=true

    while IFS= read -r dp_name; do
      [[ -z "${dp_name}" ]] && continue

      # Find the running cast-runtime pod for this DP
      local dp_pod
      dp_pod=$(kubectl get pods -n "${CAS_NAMESPACE}" \
        -l "app.kubernetes.io/component=cast-runtime,app.kubernetes.io/part-of=${dp_name}" \
        --no-headers -o custom-columns=NAME:.metadata.name,STATUS:.status.phase 2>/dev/null \
        | awk '$2=="Running"{print $1}' | head -n1)

      if [[ -z "${dp_pod}" ]]; then
        log "  DocumentProcessor '${dp_name}': no running pod found — treating queue as 0"
        continue
      fi

      # Scrape the cast_task_queue_depth metric from the pod's /metrics endpoint
      local queue_depth=0
      local metrics_raw
      metrics_raw=$(kubectl exec -n "${CAS_NAMESPACE}" "${dp_pod}" \
        -- curl -sSf http://localhost:8080/metrics 2>/dev/null \
        || kubectl exec -n "${CAS_NAMESPACE}" "${dp_pod}" \
           -- curl -sSf http://localhost:9090/metrics 2>/dev/null \
        || echo "")

      if [[ -n "${metrics_raw}" ]]; then
        # Sum all cast_task_queue_depth values (may have multiple label combos)
        queue_depth=$(echo "${metrics_raw}" \
          | grep '^cast_task_queue_depth' \
          | awk '{sum += $NF} END {print int(sum+0)}')
        queue_depth="${queue_depth:-0}"
      else
        log "  DocumentProcessor '${dp_name}' pod '${dp_pod}': could not scrape metrics — treating queue as 0"
      fi

      log "  DocumentProcessor '${dp_name}' task queue depth: ${queue_depth}"

      if [[ "${queue_depth}" -gt 0 ]]; then
        all_zero=false
      fi
    done <<< "${dp_names}"

    if [[ "${all_zero}" == "true" ]]; then
      log_success "All Document Processor task queues drained to 0"
      return 0
    fi

    log "Task queues not yet empty — waiting ${poll_interval}s (elapsed: ${elapsed}s / ${timeout_seconds}s)"
    sleep "${poll_interval}"
    elapsed=$(( elapsed + poll_interval ))
  done

  log_error "Document Processor task queues did not drain within ${timeout_seconds}s"
  return 1
}

# delete_document_processors — scales the CAS operator to 0, deletes every
# DocumentProcessor CR (removing any blocking finalizers), waits for them to
# be fully gone, then scales the operator back up.
delete_document_processors() {
  local operator_deploy="ibm-isf-cas-operator-controller-manager"
  local timeout_seconds="${DP_DELETE_TIMEOUT:-300}"
  local poll_interval=5

  log "=== Deleting DocumentProcessors via operator scale-down ==="

  # Collect all DocumentProcessor names up front
  local dp_names
  dp_names=$(kubectl get documentprocessors -n "${CAS_NAMESPACE}" \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null)

  if [[ -z "${dp_names}" ]]; then
    log "No DocumentProcessors found — nothing to delete"
    return 0
  fi

  # Step 1: Scale the CAS operator to 0 and wait for its pod to terminate.
  # NOTE: the CLI launcher (migrate-data-cache.sh) labels the CSV olm.managed=false
  # before launching this job, so OLM will not fight the scale-down.
  log "Scaling CAS operator '${operator_deploy}' to 0"
  if [[ "${DRY_RUN_JOB}" == "true" ]]; then
    log "[DRY-RUN] Would execute: kubectl scale deployment '${operator_deploy}' -n '${CAS_NAMESPACE}' --replicas=0"
    log "[DRY-RUN] Would execute: kubectl wait pod -n '${CAS_NAMESPACE}' -l control-plane=controller-manager --for=delete --timeout=120s"
  else
    kubectl scale deployment "${operator_deploy}" -n "${CAS_NAMESPACE}" --replicas=0 || {
      log_error "Failed to scale down CAS operator '${operator_deploy}'"
      return 1
    }
    log "Waiting for CAS operator pod to terminate..."
    kubectl wait pod -n "${CAS_NAMESPACE}" \
      -l "control-plane=controller-manager" \
      --for=delete --timeout=120s 2>/dev/null || true
    log "CAS operator pod gone"
  fi

  # Step 2: Delete first; if the object gets stuck on finalizers (operator is
  # scaled to 0 and cannot process them), strip them so the delete completes.
  # --wait=false avoids blocking on the API server's delete confirmation.
  while IFS= read -r dp_name; do
    [[ -z "${dp_name}" ]] && continue
    log "Deleting DocumentProcessor '${dp_name}'"
    if [[ "${DRY_RUN_JOB}" == "true" ]]; then
      log "[DRY-RUN] Would execute: kubectl delete documentprocessor '${dp_name}' -n '${CAS_NAMESPACE}' --ignore-not-found --wait=false"
      log "[DRY-RUN] Would execute: kubectl patch documentprocessor '${dp_name}' -n '${CAS_NAMESPACE}' --type=merge -p '{\"metadata\":{\"finalizers\":[]}}'"
      continue
    fi
    kubectl delete documentprocessor "${dp_name}" -n "${CAS_NAMESPACE}" --ignore-not-found --wait=false || {
      log_error "Failed to delete DocumentProcessor '${dp_name}'"
      return 1
    }
    # Strip finalizers so the object is not stuck waiting for operator
    # reconciliation (operator is scaled to 0 at this point)
    kubectl patch documentprocessor "${dp_name}" -n "${CAS_NAMESPACE}" \
      --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  done <<< "${dp_names}"

  # Step 3: Wait for all DocumentProcessors to be gone
  if [[ "${DRY_RUN_JOB}" != "true" ]]; then
    log "Waiting for DocumentProcessors to be fully deleted (timeout: ${timeout_seconds}s)"
    local elapsed=0
    while [[ ${elapsed} -lt ${timeout_seconds} ]]; do
      local remaining
      remaining=$(kubectl get documentprocessors -n "${CAS_NAMESPACE}" \
        --no-headers 2>/dev/null | grep -v '^$' | wc -l)
      if [[ "${remaining}" -eq 0 ]]; then
        log_success "All DocumentProcessors deleted"
        break
      fi
      log "  ${remaining} DocumentProcessor(s) still present — waiting ${poll_interval}s (elapsed: ${elapsed}s / ${timeout_seconds}s)"
      sleep "${poll_interval}"
      elapsed=$(( elapsed + poll_interval ))
    done
    if [[ ${elapsed} -ge ${timeout_seconds} ]]; then
      log_error "DocumentProcessors did not finish deleting within ${timeout_seconds}s"
      return 1
    fi
  fi

  # Operator is intentionally left at 0 replicas here.
  # perform_pre_migration() scales it back up only after delete_s3_datasources()
  # completes, so the operator cannot pick up the DP Terminating event and drop
  # the ParadeDB tables before we are done.
}

scale_up_cas_operator() {
  local operator_deploy="ibm-isf-cas-operator-controller-manager"
  # NOTE: the CLI launcher (migrate-data-cache.sh) restores the olm.managed label
  # after the job completes. No CSV label manipulation is done here.
  log "Scaling CAS operator '${operator_deploy}' back to 1"
  if [[ "${DRY_RUN_JOB}" == "true" ]]; then
    log "[DRY-RUN] Would execute: kubectl scale deployment '${operator_deploy}' -n '${CAS_NAMESPACE}' --replicas=1"
  else
    kubectl scale deployment "${operator_deploy}" -n "${CAS_NAMESPACE}" --replicas=1 || {
      log_error "Failed to scale CAS operator '${operator_deploy}' back up"
      return 1
    }
  fi
  log_success "CAS operator scaled back to 1"
}

# delete_s3_datasources — deletes each S3+cache-fs datasource after backup.
# Before each delete, reads the watch-id annotation and disables the mmwatch
# on the Scale filesystem — the operator will not clean this up once the
# DataSource CR is gone.
delete_s3_datasources() {
  local s3_ds_names
  s3_ds_names=$(get_s3_cachefs_datasources)

  if [[ -z "${s3_ds_names}" ]]; then
    log "No S3+cache-fs datasources to delete"
    return 0
  fi

  log "=== Deleting S3+cache-fs DataSources ==="

  # Locate the Scale core pod once — reused for every mmwatch disable call
  local core_pod
  core_pod=$(kubectl get pod -n "${SCALE_NAMESPACE}" \
    -l "app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core" \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -n1)

  while IFS= read -r ds_name; do
    [[ -z "${ds_name}" ]] && continue
    log "Deleting DataSource '${ds_name}'"
    if [[ "${DRY_RUN_JOB}" == "true" ]]; then
      log "[DRY-RUN] Would execute: mmwatch ${FILESYSTEM_NAME} disable --watch-id <watch-id>"
      log "[DRY-RUN] Would execute: kubectl delete datasource '${ds_name}' -n '${CAS_NAMESPACE}'"
      continue
    fi
    # Disable the Scale mmwatch before deleting so no orphaned watch is left behind
    local watch_id
    watch_id=$(kubectl get datasource "${ds_name}" -n "${CAS_NAMESPACE}" \
      -o jsonpath='{.metadata.annotations.watch-id}' 2>/dev/null)
    if [[ -n "${watch_id}" && -n "${core_pod}" ]]; then
      log "  Disabling mmwatch watch-id '${watch_id}' for DataSource '${ds_name}'"
      kubectl exec -n "${SCALE_NAMESPACE}" "${core_pod}" -- \
        mmwatch "${FILESYSTEM_NAME}" disable --watch-id "${watch_id}" 2>&1 || true
    else
      log "  No watch-id annotation on '${ds_name}' — skipping mmwatch disable"
    fi
    kubectl delete datasource "${ds_name}" -n "${CAS_NAMESPACE}" || {
      log_error "Failed to delete DataSource '${ds_name}'"
      return 1
    }
  done <<< "${s3_ds_names}"

  log_success "All S3+cache-fs DataSources deleted"
}

backup_document_processors() {
  local backup_dir="${1}"

  log "Backing up DocumentProcessors..."

  {
    echo "apiVersion: v1"
    echo "kind: List"
    echo "items:"
    kubectl get documentprocessors -n "${CAS_NAMESPACE}" -o yaml 2>/dev/null \
      | yq eval '.items[]' - \
      | sed 's/^/- /' \
      | sed '2,$s/^- /  /'
  } > "${backup_dir}/documentprocessors.yaml"

  local count
  count=$(yq eval '.items | length' "${backup_dir}/documentprocessors.yaml" 2>/dev/null || echo 0)
  log_success "Backed up ${count} DocumentProcessor(s)"
}

backup_configmaps() {
  local backup_dir="${1}"
  
  log "Backing up CAS ConfigMaps..."
  
  if kubectl get configmaps -n "${CAS_NAMESPACE}" \
    -l "app.kubernetes.io/name=cas" \
    -o yaml > "${backup_dir}/configmaps.yaml"; then
    log_success "ConfigMaps backed up"
  else
    log_error "Failed to backup ConfigMaps"
    return 1
  fi
}

create_backup_metadata() {
  local backup_dir="${1}"
  
  log "Creating backup metadata..."
  
  cat > "${backup_dir}/metadata.json" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "filesystem": "${FILESYSTEM_NAME}",
  "namespace": "${CAS_NAMESPACE}",
  "migration_marker": "cas_migration_${MIGRATION_TIMESTAMP}",
  "phase": "pre-migration",
  "job_name": "${JOB_NAME:-unknown}"
}
EOF
  
  log_success "Metadata created"
}

perform_pre_migration() {
  local backup_dir="/mnt/${MIGRATION_PVC_NAME}/migration-backup/${MIGRATION_TIMESTAMP}"

  log "=== Starting Pre-Migration ==="
  log "Backup directory: ${backup_dir}"

  # Create backup directory
  mkdir -p "${backup_dir}" || {
    log_error "Failed to create backup directory"
    return 1
  }

  # i. Save S3+cache-fs datasource yaml and secret yaml(s), then disconnect each datasource
  backup_datasources "${backup_dir}" || return 1

  # ii.a. Wait for Kafka consumer lag to reach 0 for each affected topic
  wait_for_kafka_lag_zero || return 1

  # ii.b. Wait for Document Processor task queues to reach 0
  wait_for_task_queue_zero || return 1

  # iii. Backup DocumentProcessors now that queues are drained
  backup_document_processors "${backup_dir}" || return 1

  # iv. Create metadata
  create_backup_metadata "${backup_dir}" || return 1

  # v. Delete DocumentProcessors (operator scaled to 0 inside)
  delete_document_processors || return 1

  # vi. Scale operator back up now that all DP CRs are gone — safe because there
  #     are no admission webhooks for DataSources that would re-trigger DP deletion
  scale_up_cas_operator || return 1

  # vii. Delete S3 datasources (operator is running; webhooks for DS are present
  #      but DP tables are already preserved since no DP CRs remain to reconcile)
  delete_s3_datasources || return 1

  # Update state
  update_migration_progress "pre" "completed" "${backup_dir}" || return 1

  log_success "=== Pre-Migration Complete ==="
  log "Backup location: ${backup_dir}"
}

# ============================================================================
# 5. BACKUP OPERATIONS
# ============================================================================

verify_backup_exists() {
  local backup_dir="${1}"
  
  log "Verifying backup directory: ${backup_dir}"
  
  if [[ ! -d "${backup_dir}" ]]; then
    log_error "Backup directory not found: ${backup_dir}"
    log_error "Pre-migration must be run first"
    return 1
  fi
  
  # Check for required backup files
  for file in datasources.yaml documentprocessors.yaml metadata.json; do
    if [[ ! -f "${backup_dir}/${file}" ]]; then
      log_error "Required backup file missing: ${file}"
      return 1
    fi
  done
  
  log_success "Backup verification complete"
  log "  Location: ${backup_dir}"
  log "  Files: datasources.yaml documentprocessors.yaml metadata.json"
  
  return 0
}

find_latest_backup() {
  local backup_base_dir="/mnt/${MIGRATION_PVC_NAME}/migration-backup"
  
  log "Searching for latest backup in: ${backup_base_dir}" >&2
  
  if [[ ! -d "${backup_base_dir}" ]]; then
    log_error "Backup base directory not found: ${backup_base_dir}"
    return 1
  fi
  
  # Find most recent backup directory
  local latest_backup
  latest_backup=$(find "${backup_base_dir}" -maxdepth 1 -type d -name "20*" | sort -r | head -n1)
  
  if [[ -z "${latest_backup}" ]]; then
    log_error "No backup found in ${backup_base_dir}"
    return 1
  fi
  
  log_success "Found backup: ${latest_backup}" >&2
  echo "${latest_backup}"
}

# ============================================================================
# 6. DATABASE OPERATIONS
# ============================================================================

check_database_migration_applied() {
  local migration_marker="cas_migration_${MIGRATION_TIMESTAMP}"
  
  log "Checking if database migration already applied..."
  log "Migration marker: ${migration_marker}"
  
  # In dry-run mode, skip all database checks
  if [[ "${DRY_RUN_JOB}" == "true" ]]; then
    log "[DRY-RUN] Would check if migration_log table exists"
    log "[DRY-RUN] Would check for migration marker: ${migration_marker}"
    log "[DRY-RUN] Assuming migration not yet applied"
    return 1
  fi
  
  # Check if migration_log table exists
  local table_exists
  table_exists=$(psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" \
    -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'migration_log')" 2>/dev/null || echo "f")
  
  if [[ "${table_exists}" == "f" ]]; then
    log "Migration log table does not exist, creating..."
    
    local create_table_sql
    create_table_sql=$(cat <<EOF
CREATE TABLE IF NOT EXISTS migration_log (
  id SERIAL PRIMARY KEY,
  marker VARCHAR(255) UNIQUE NOT NULL,
  timestamp TIMESTAMP NOT NULL,
  phase VARCHAR(50) NOT NULL,
  old_path TEXT,
  new_path TEXT
);
EOF
)
    
    if [[ "${DRY_RUN_JOB}" == "true" ]]; then
      log "[DRY-RUN] Would execute: psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} <<EOF"
      echo "${create_table_sql}"
      log "[DRY-RUN] EOF"
      return 1
    fi
    
    psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" <<EOF
${create_table_sql}
EOF
    return 1  # Not applied yet
  fi
  
  # Check for migration marker
  local already_migrated
  already_migrated=$(psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" \
    -tAc "SELECT EXISTS(SELECT 1 FROM migration_log WHERE marker='${migration_marker}')" 2>/dev/null || echo "f")
  
  if [[ "${already_migrated}" == "t" ]]; then
    log "Migration marker found - migration already applied"
    return 0
  else
    log "Migration marker not found - migration not yet applied"
    return 1
  fi
}

# update_file_table_inodes BACKUP_DIR
#
# After the new cache-fs is created, the operator runs an initial-load scan that
# inserts a new row into each <domain>_file table for every file it discovers.
# This new row carries the new inode (file_id) and new pvc_path for the file on
# the new filesystem.  The pre-migration row for the same file — which has the
# old inode, old pvc_path, and status=completed plus all its processed embeddings
# — is still in the table.  We must update the pre-migration row with the new
# inode/pvc_path/path_id values so the operator's deduplication logic resolves
# correctly, then remove the now-redundant initial-load row.
#
# Strategy: for each <domain>_file table, find pairs of rows that share the same
# source_path but differ in pvc_path (old fileset vs new fileset).  For each
# pair, copy file_id, pvc_path, and path_id from the new row onto the old row,
# then delete the new row.  Rows with no matching new counterpart are left alone.
update_file_table_inodes() {
  local backup_dir="${1}"
  local migration_marker="cas_migration_${MIGRATION_TIMESTAMP}"

  log "=== Database Inode Update ==="

  # Check if migration already applied
  if check_database_migration_applied; then
    log "WARN: Database migration already applied (marker: ${migration_marker})"
    log "WARN: Skipping database updates to maintain idempotency"
    return 0
  fi

  # Derive domain names from the DocumentProcessor backup — each DP name maps
  # directly to a <domain>_file table in ParadeDB.
  local domains
  domains=$(yq eval '.items[].metadata.name' "${backup_dir}/documentprocessors.yaml" 2>/dev/null || true)

  if [[ -z "${domains}" ]]; then
    log "No DocumentProcessors in backup — skipping inode update"
    return 0
  fi

  if [[ "${DRY_RUN_JOB}" == "true" ]]; then
    log "[DRY-RUN] Would update _file table inodes for domains: ${domains}"
    log "[DRY-RUN] Would record migration marker: ${migration_marker}"
    log_success "[DRY-RUN] Database inode update skipped (dry-run)"
    return 0
  fi

  local any_updated=false

  while IFS= read -r domain; do
    [[ -z "${domain}" ]] && continue
    local table="\"${domain}_file\""
    log "Processing table: ${table}"

    # Check the table exists
    local table_exists
    table_exists=$(psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" \
      -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '${domain}_file')" \
      2>/dev/null || echo "f")

    if [[ "${table_exists}" != "t" ]]; then
      log "Table ${table} does not exist — skipping"
      continue
    fi

    # Count duplicate source_path pairs (old completed row + new empty-status row)
    local pair_count
    pair_count=$(psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" -tAc "
      SELECT COUNT(*)
      FROM ${table} AS old_row
      JOIN ${table} AS new_row USING (source_path)
      WHERE old_row.pvc_path <> new_row.pvc_path
        AND old_row.status = 'completed'
        AND (new_row.status IS NULL OR new_row.status = '')
    " 2>/dev/null || echo 0)

    if [[ "${pair_count}" -eq 0 ]]; then
      log "No stale inode pairs found in ${table} — skipping"
      continue
    fi

    log "Found ${pair_count} stale inode pair(s) in ${table} — applying update"

    psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" <<EOSQL
BEGIN;

-- Step 1: capture the mapping of old pk -> new values into a temp table.
-- This avoids unique-constraint violations when the UPDATE and DELETE run
-- against the same table in the same statement.
CREATE TEMP TABLE _inode_update_${domain} AS
SELECT
  old_row.pk        AS old_pk,
  new_row.pk        AS new_pk,
  new_row.file_id   AS new_file_id,
  new_row.pvc_path  AS new_pvc_path,
  new_row.path_id   AS new_path_id
FROM ${table} AS old_row
JOIN ${table} AS new_row USING (source_path)
WHERE old_row.pvc_path <> new_row.pvc_path
  AND old_row.status    = 'completed'
  AND (new_row.status IS NULL OR new_row.status = '');

-- Step 2: delete the new (initial-load) row first to release the unique
-- constraint on file_id before the UPDATE tries to assign that value.
DELETE FROM ${table}
WHERE pk IN (SELECT new_pk FROM _inode_update_${domain});

-- Step 3: update the old (completed) row with the new inode values.
UPDATE ${table}
SET
  file_id     = u.new_file_id,
  pvc_path    = u.new_pvc_path,
  path_id     = u.new_path_id,
  row_updated = NOW()
FROM _inode_update_${domain} u
WHERE pk = u.old_pk;

COMMIT;
EOSQL

    log_success "Inode update applied for ${table}"
    any_updated=true
  done <<< "${domains}"

  # Record migration marker
  psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" <<EOSQL
INSERT INTO migration_log (marker, timestamp, phase, old_path, new_path)
VALUES ('${migration_marker}', NOW(), 'post-migration', '', '')
ON CONFLICT (marker) DO NOTHING;
EOSQL

  if [[ "${any_updated}" == "true" ]]; then
    log_success "Database inode update complete"
  else
    log "No inode pairs required updating across all tables"
  fi
  log "Migration marker recorded: ${migration_marker}"
}

# ============================================================================
# 7. POST-MIGRATION OPERATIONS
# ============================================================================

count_datasources_in_backup() {
  local backup_file="${1}"
  
  if [[ ! -f "${backup_file}" ]]; then
    echo "0"
    return 0
  fi
  
  # The backup is an 'apiVersion: v1 / kind: List' document.
  # Items are indented; count by matching the per-item apiVersion line.
  local count
  count=$(grep -c "apiVersion: cas.isf.ibm.com/v1beta1" "${backup_file}" 2>/dev/null || true)
  
  if [[ -z "${count}" ]]; then
    count="0"
  fi
  
  echo "${count}"
}

count_datasources_in_cluster() {
  local namespace="${1}"
  
  # Count DataSource CRs in the cluster
  local count
  count=$(kubectl get datasources -n "${namespace}" --no-headers 2>/dev/null | wc -l || true)
  
  # If empty, default to 0
  if [[ -z "${count}" ]]; then
    count="0"
  fi
  
  # Trim whitespace
  count=$(echo "${count}" | tr -d '[:space:]')
  
  echo "${count}"
}

restore_datasources() {
  local backup_dir="${1}"
  local backup_file="${backup_dir}/datasources.yaml"
  local clean_file="${backup_dir}/datasources-clean.yaml"
  
  log "Restoring DataSources from: ${backup_dir}"
  
  # Count DataSources in backup
  local backup_count
  backup_count=$(count_datasources_in_backup "${backup_file}")
  log "DataSources in backup: ${backup_count}"
  
  if [[ "${backup_count}" -eq 0 ]]; then
    log "No DataSources to restore (backup is empty)"
    return 0
  fi
  
  if [[ "${DRY_RUN_JOB}" == "true" ]]; then
    log "[DRY-RUN] Would strip server fields and execute: kubectl apply -f ${clean_file}"
    log_success "[DRY-RUN] ${backup_count} DataSource(s) would be restored"
    return 0
  fi
  
  # Strip server-managed fields and all operator-written annotations.
  # The operator re-derives fileset, watch, pvc, and connection annotations
  # on first reconcile — restoring stale values causes the operator to
  # skip re-provisioning and leaves the DataSource pointing at the old fileset.
  log "Stripping server-managed fields and operator annotations from backup..."
  yq eval '
    del(.items[].metadata.resourceVersion) |
    del(.items[].metadata.uid) |
    del(.items[].metadata.creationTimestamp) |
    del(.items[].metadata.selfLink) |
    del(.items[].metadata.generation) |
    del(.items[].metadata.managedFields) |
    del(.items[].metadata.finalizers) |
    del(.items[].metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]) |
    del(.items[].metadata.annotations["fileset-path"]) |
    del(.items[].metadata.annotations["fileset-name"]) |
    del(.items[].metadata.annotations["fileset-id"]) |
    del(.items[].metadata.annotations["fsnotify-topic"]) |
    del(.items[].metadata.annotations["pvc-name"]) |
    del(.items[].metadata.annotations["pv-name"]) |
    del(.items[].metadata.annotations["watch-id"]) |
    del(.items[].metadata.annotations["watch-parent-id"]) |
    del(.items[].metadata.annotations["connection-status"]) |
    del(.items[].metadata.annotations["cluster-id"]) |
    del(.items[].metadata.annotations["cluster-name"]) |
    del(.items[].metadata.annotations["filesystem-name"]) |
    del(.items[].metadata.annotations["filesystem-uuid"]) |
    del(.items[].metadata.annotations["num-retried"]) |
    del(.items[].status)
  ' "${backup_file}" > "${clean_file}"

  if ! kubectl apply -f "${clean_file}"; then
    log_error "Failed to restore DataSources"
    return 1
  fi
  
  log_success "DataSources restored"
}

validate_datasource_count() {
  local backup_dir="${1}"
  local namespace="${2}"
  
  log "Validating DataSource count..."
  
  # Count in backup
  local backup_count
  backup_count=$(count_datasources_in_backup "${backup_dir}/datasources.yaml")
  
  # Count in cluster
  local cluster_count
  cluster_count=$(count_datasources_in_cluster "${namespace}")
  
  log "  Backup count: ${backup_count}"
  log "  Cluster count: ${cluster_count}"
  
  if [[ "${backup_count}" -eq "${cluster_count}" ]]; then
    log_success "DataSource count matches (${cluster_count}/${backup_count})"
    return 0
  else
    log_error "DataSource count mismatch!"
    log_error "  Expected: ${backup_count}"
    log_error "  Found: ${cluster_count}"
    return 1
  fi
}

restore_document_processors() {
  local backup_dir="${1}"
  local backup_file="${backup_dir}/documentprocessors.yaml"
  local clean_file="${backup_dir}/documentprocessors-clean.yaml"

  log "Restoring DocumentProcessors from: ${backup_dir}"

  local count
  count=$(yq eval '.items | length' "${backup_file}" 2>/dev/null || echo 0)
  log "DocumentProcessors in backup: ${count}"

  if [[ "${count}" -eq 0 ]]; then
    log "No DocumentProcessors to restore (backup is empty)"
    return 0
  fi

  if [[ "${DRY_RUN_JOB}" == "true" ]]; then
    log "[DRY-RUN] Would strip server fields and execute: kubectl apply -f ${clean_file}"
    log_success "[DRY-RUN] ${count} DocumentProcessor(s) would be restored"
    return 0
  fi

  log "Stripping server-managed fields from backup..."
  yq eval '
    del(.items[].metadata.resourceVersion) |
    del(.items[].metadata.uid) |
    del(.items[].metadata.creationTimestamp) |
    del(.items[].metadata.selfLink) |
    del(.items[].metadata.generation) |
    del(.items[].metadata.managedFields) |
    del(.items[].metadata.finalizers) |
    del(.items[].metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]) |
    del(.items[].status)
  ' "${backup_file}" > "${clean_file}"

  if ! kubectl apply -f "${clean_file}"; then
    log_error "Failed to restore DocumentProcessors"
    return 1
  fi

  log_success "DocumentProcessors restored"
}

perform_post_migration() {
  log "=== Starting Post-Migration ==="
  
  # Find latest backup
  local backup_dir
  backup_dir=$(find_latest_backup) || return 1
  
  log "Using backup: ${backup_dir}"
  
  # Verify backup exists and is complete
  verify_backup_exists "${backup_dir}" || return 1
  
  # Get database credentials
  get_database_credentials || return 1
  
  # Test database connection
  test_database_connection || return 1
  
  # Restore DataSources
  restore_datasources "${backup_dir}" || return 1
  
  # Restore DocumentProcessors
  restore_document_processors "${backup_dir}" || return 1

  # Validate DataSource count matches backup
  validate_datasource_count "${backup_dir}" "${CAS_NAMESPACE}" || return 1
  
  # Update database inodes: copy new file_id/pvc_path/path_id from initial-load
  # rows onto the pre-migration completed rows, then remove the duplicates.
  log "Updating database inode references..."
  update_file_table_inodes "${backup_dir}" || return 1
  
  # Update state
  update_migration_progress "post" "completed" || return 1
  
  log_success "=== Post-Migration Complete ==="
}

# ============================================================================
# 8. MAIN EXECUTION FLOW
# ============================================================================

main() {
  log "========================================="
  log "CAS Data Cache Migration - Job Script"
  log "========================================="
  log "Phase: ${MIGRATION_PHASE}"
  log "Filesystem: ${FILESYSTEM_NAME}"
  log "Namespace: ${CAS_NAMESPACE}"
  log "Timestamp: ${MIGRATION_TIMESTAMP}"
  log "Dry Run: ${DRY_RUN_JOB}"
  log "========================================="
  
  # Install required CLI tools
  install_cli_tools || {
    log_error "Failed to install required CLI tools"
    exit 1
  }
  
  # Validate required environment variables
  if [[ -z "${MIGRATION_PHASE}" ]] || \
     [[ -z "${FILESYSTEM_NAME}" ]] || \
     [[ -z "${CAS_NAMESPACE}" ]] || \
     [[ -z "${MIGRATION_TIMESTAMP}" ]] || \
     [[ -z "${MIGRATION_PVC_NAME:-}" ]]; then
    log_error "Required environment variables not set"
    exit 1
  fi
  
  # Execute migration based on phase
  case "${MIGRATION_PHASE}" in
    pre)
      perform_pre_migration
      ;;
    post)
      perform_post_migration
      ;;
    full)
      perform_pre_migration || exit 1
      log ""
      log "Waiting 5 seconds before post-migration..."
      sleep 5
      perform_post_migration
      ;;
    *)
      log_error "Invalid migration phase: ${MIGRATION_PHASE}"
      log_error "Valid phases: pre, post, full"
      exit 1
      ;;
  esac
  
  local exit_code=$?
  
  if [[ ${exit_code} -eq 0 ]]; then
    log "========================================="
    log "Migration ${MIGRATION_PHASE} completed successfully"
    log "========================================="
  else
    log_error "========================================="
    log_error "Migration ${MIGRATION_PHASE} failed"
    log_error "========================================="
  fi
  
  exit ${exit_code}
}

# Execute main function
main

# Made with Bob
