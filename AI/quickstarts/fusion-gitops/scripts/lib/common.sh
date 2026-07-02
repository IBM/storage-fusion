#!/bin/bash
#
# Common utility functions for Fusion GitOps deployment scripts
#

# Color codes
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $1"
    fi
}

# Print a banner
print_banner() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title}) / 2 ))
    
    echo ""
    echo "$(printf '=%.0s' $(seq 1 $width))"
    printf "%${padding}s" ""
    echo "$title"
    echo "$(printf '=%.0s' $(seq 1 $width))"
    echo ""
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Detect CLI (oc or kubectl)
detect_cli() {
    if command_exists oc; then
        echo "oc"
    elif command_exists kubectl; then
        echo "kubectl"
    else
        log_error "Neither oc nor kubectl found. Please install one of them."
        exit 1
    fi
}

# Check if running on OpenShift
is_openshift() {
    local cli=$(detect_cli)
    if [ "$cli" = "oc" ]; then
        return 0
    fi
    
    # Check for OpenShift-specific resources
    if $cli api-resources | grep -q "route.openshift.io"; then
        return 0
    fi
    
    return 1
}

# Get cluster context
get_cluster_context() {
    local cli=$(detect_cli)
    $cli config current-context 2>/dev/null || echo "unknown"
}

# Confirm action
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [ "${FORCE:-false}" = "true" ]; then
        return 0
    fi
    
    local yn
    read -p "$prompt [y/N]: " yn
    case $yn in
        [Yy]* ) return 0;;
        * ) return 1;;
    esac
}

# Retry command with exponential backoff
retry_command() {
    local max_attempts="$1"
    shift
    local command="$@"
    local attempt=1
    local delay=5
    
    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts: $command"
        
        if eval "$command"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warning "Command failed. Retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Command failed after $max_attempts attempts"
    return 1
}

# Check if namespace exists
namespace_exists() {
    local namespace="$1"
    local cli=$(detect_cli)
    
    $cli get namespace "$namespace" &> /dev/null
}

# Create namespace if it doesn't exist
ensure_namespace() {
    local namespace="$1"
    local cli=$(detect_cli)
    
    if namespace_exists "$namespace"; then
        log_debug "Namespace $namespace already exists"
        return 0
    fi
    
    log_info "Creating namespace $namespace..."
    $cli create namespace "$namespace"
}

# Get resource status
get_resource_status() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local cli=$(detect_cli)
    
    local ns_flag=""
    if [ -n "$namespace" ]; then
        ns_flag="-n $namespace"
    fi
    
    $cli get "$resource_type" "$resource_name" $ns_flag -o jsonpath='{.status}' 2>/dev/null
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local cli=$(detect_cli)
    
    local ns_flag=""
    if [ -n "$namespace" ]; then
        ns_flag="-n $namespace"
    fi
    
    $cli get "$resource_type" "$resource_name" $ns_flag &> /dev/null
}

# Get pod status
get_pod_status() {
    local pod_name="$1"
    local namespace="$2"
    local cli=$(detect_cli)
    
    $cli get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Count running pods
count_running_pods() {
    local label_selector="$1"
    local namespace="$2"
    local cli=$(detect_cli)
    
    $cli get pods -n "$namespace" -l "$label_selector" \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null | wc -l | tr -d ' '
}

# Get deployment ready replicas
get_deployment_ready_replicas() {
    local deployment="$1"
    local namespace="$2"
    local cli=$(detect_cli)
    
    $cli get deployment "$deployment" -n "$namespace" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"
}

# Check if deployment is ready
is_deployment_ready() {
    local deployment="$1"
    local namespace="$2"
    local cli=$(detect_cli)
    
    local ready=$($cli get deployment "$deployment" -n "$namespace" \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
    
    [ "$ready" = "True" ]
}

# Get PVC status
get_pvc_status() {
    local pvc_name="$1"
    local namespace="$2"
    local cli=$(detect_cli)
    
    $cli get pvc "$pvc_name" -n "$namespace" \
        -o jsonpath='{.status.phase}' 2>/dev/null
}

# Check if PVC is bound
is_pvc_bound() {
    local pvc_name="$1"
    local namespace="$2"
    
    local status=$(get_pvc_status "$pvc_name" "$namespace")
    [ "$status" = "Bound" ]
}

# Get secret value
get_secret_value() {
    local secret_name="$1"
    local key="$2"
    local namespace="$3"
    local cli=$(detect_cli)
    
    $cli get secret "$secret_name" -n "$namespace" \
        -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d
}

# Get route host (OpenShift)
get_route_host() {
    local route_name="$1"
    local namespace="$2"
    
    if ! is_openshift; then
        return 1
    fi
    
    oc get route "$route_name" -n "$namespace" \
        -o jsonpath='{.spec.host}' 2>/dev/null
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code $exit_code"
    fi
    
    # Add any cleanup tasks here
    
    exit $exit_code
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Export functions
export -f log_info
export -f log_success
export -f log_warning
export -f log_error
export -f log_debug
export -f print_banner
export -f command_exists
export -f detect_cli
export -f is_openshift
export -f get_cluster_context
export -f confirm
export -f retry_command
export -f namespace_exists
export -f ensure_namespace
export -f get_resource_status
export -f resource_exists
export -f get_pod_status
export -f count_running_pods
export -f get_deployment_ready_replicas
export -f is_deployment_ready
export -f get_pvc_status
export -f is_pvc_bound
export -f get_secret_value
export -f get_route_host

# Made with Bob
